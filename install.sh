#!/usr/bin/env bash
# Duckybox — Parrot OS MATE customizer (Pwnbox-style, violet theme)
#
# Themes the whole visual chain: GRUB -> Plymouth -> LightDM -> MATE desktop,
# plus tmux, the bash prompt, a VPN indicator and a few working tools.
#
# Usage: sudo ./install.sh [options]

set -euo pipefail

VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

DRY_RUN=0
VERBOSE=0
SKIP_OBSIDIAN=0
SKIP_SYSREPTOR=0
SKIP_PLYMOUTH=0
SKIP_GRUB=0
SKIP_GTK=0
REGEN_BRAND=0

LOG_FILE="/var/log/duckybox-install.log"
OPT_DIR="/opt/duckybox"
THEME_PLYMOUTH="/usr/share/plymouth/themes/duckybox"
THEME_GRUB="/boot/grub/themes/duckybox"
BG_DIR="/usr/share/backgrounds/duckybox"
ICON_DIR="/usr/share/icons/duckybox"
PLANK_THEME_DIR="/usr/share/plank/themes/Duckybox"
SYSREPTOR_INSTALL_URL="https://docs.sysreptor.com/install.sh"
SYSREPTOR_DIR_DEFAULT="/opt/sysreptor"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

_log_write() {
  local level="$1"
  shift
  local prefix=""
  [[ "${DRY_RUN}" -eq 1 ]] && prefix="[DRY-RUN] "
  local line
  line="$(_ts) [${level}] ${prefix}$*"
  printf '%s\n' "${line}"
  printf '%s\n' "${line}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_info()  { _log_write "INFO"  "$*"; }
log_ok()    { _log_write "OK"    "$*"; }
log_warn()  { _log_write "WARN"  "$*"; }
log_error() { _log_write "ERROR" "$*"; }
log_debug() { [[ "${VERBOSE}" -eq 1 ]] && _log_write "DEBUG" "$*" || true; }

on_error() {
  local exit_code=$?
  local line_no="${1:-?}"
  log_error "Failed at line ${line_no} (exit ${exit_code}): ${BASH_COMMAND:-unknown}"
  log_error "See log: ${LOG_FILE}"
  exit "${exit_code}"
}

trap 'on_error ${LINENO}' ERR

# ---------------------------------------------------------------------------
# Args / environment
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
Duckybox installer v${VERSION}

Usage: sudo ./install.sh [options]

Options:
  --dry-run          Print actions without changing the system
  --verbose          Extra debug logging
  --regen-brand      Rebuild brand assets from assets/brand/duckybox-logo.png
  --skip-obsidian    Do not download/install Obsidian
  --skip-sysreptor   Do not install Docker / SysReptor
  --skip-plymouth    Skip the Plymouth boot splash
  --skip-grub        Skip the GRUB theme
  --skip-gtk         Skip building the Duckybox GTK theme and icons
  -h, --help         Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --verbose) VERBOSE=1 ;;
      --regen-brand) REGEN_BRAND=1 ;;
      --skip-obsidian) SKIP_OBSIDIAN=1 ;;
      --skip-sysreptor) SKIP_SYSREPTOR=1 ;;
      --skip-plymouth) SKIP_PLYMOUTH=1 ;;
      --skip-grub) SKIP_GRUB=1 ;;
      --skip-gtk) SKIP_GTK=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
  done
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo ./install.sh" >&2
    exit 1
  fi
}

init_log() {
  mkdir -p "$(dirname "${LOG_FILE}")"
  touch "${LOG_FILE}"
  chmod 644 "${LOG_FILE}"
  log_info "=== Duckybox install v${VERSION} started ==="
  log_info "Repo: ${REPO_ROOT}"
}

detect_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="${SUDO_USER}"
  else
    TARGET_USER="$(logname 2>/dev/null || true)"
  fi
  if [[ -z "${TARGET_USER:-}" || "${TARGET_USER}" == "root" ]]; then
    log_error "Could not determine a non-root desktop user (SUDO_USER)"
    exit 1
  fi
  TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  if [[ -z "${TARGET_HOME}" || ! -d "${TARGET_HOME}" ]]; then
    log_error "Home directory for ${TARGET_USER} not found"
    exit 1
  fi
  log_ok "Target user: ${TARGET_USER} (${TARGET_HOME})"
}

require_parrot() {
  if [[ ! -f /etc/os-release ]]; then
    log_error "/etc/os-release missing"
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "parrot" ]] && ! grep -qi parrot /etc/os-release; then
    log_warn "OS does not look like Parrot (ID=${ID:-unknown}); continuing anyway"
  else
    log_ok "Detected Parrot OS (${PRETTY_NAME:-Parrot})"
  fi
}

# ---------------------------------------------------------------------------
# Packages & apps
# ---------------------------------------------------------------------------

apt_install() {
  local pkgs=("$@")
  log_info "Installing packages: ${pkgs[*]}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends "${pkgs[@]}"
}

install_base_packages() {
  apt_install \
    plymouth \
    plymouth-themes \
    plank \
    tmux \
    fonts-dejavu-core \
    flameshot \
    peek \
    imagemagick \
    curl \
    wget \
    ca-certificates \
    dconf-cli \
    gsettings-desktop-schemas \
    x11-xserver-utils \
    openssl \
    uuid-runtime \
    coreutils \
    sed
  log_ok "Base packages installed (including Flameshot and Peek)"
}

install_obsidian() {
  if [[ "${SKIP_OBSIDIAN}" -eq 1 ]]; then
    log_info "Skipping Obsidian (--skip-obsidian)"
    return 0
  fi
  if command -v obsidian >/dev/null 2>&1 || dpkg -l obsidian 2>/dev/null | grep -q '^ii'; then
    log_ok "Obsidian already installed; skipping"
    return 0
  fi

  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "${arch}" in
    amd64|x86_64) arch="amd64" ;;
    *)
      log_warn "Obsidian auto-install supports amd64 only (got ${arch}); skipping"
      return 0
      ;;
  esac

  log_info "Downloading Obsidian .deb from GitHub Releases"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  local tmp deb_url deb_file
  tmp="$(mktemp -d)"
  if ! deb_url="$(curl -fsSL 'https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest' \
      | grep -oE 'https://[^"]+obsidian_[0-9.]+_amd64\.deb' | head -n1)"; then
    log_warn "Could not resolve the Obsidian download URL; skipping"
    rm -rf "${tmp}"
    return 0
  fi

  deb_file="${tmp}/obsidian.deb"
  if ! curl -fsSL -o "${deb_file}" "${deb_url}"; then
    log_warn "Obsidian download failed; continuing without it"
    rm -rf "${tmp}"
    return 0
  fi

  if apt-get install -y "${deb_file}"; then
    log_ok "Obsidian installed"
  else
    dpkg -i "${deb_file}" || true
    apt-get install -f -y || true
    if command -v obsidian >/dev/null 2>&1; then
      log_ok "Obsidian installed (via dpkg)"
    else
      log_warn "Obsidian install did not complete"
    fi
  fi
  rm -rf "${tmp}"
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    log_ok "Docker already present"
  else
    log_info "Installing Docker"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      return 0
    fi
    export DEBIAN_FRONTEND=noninteractive
    if ! apt-get install -y docker.io; then
      log_warn "apt docker.io failed; trying get.docker.com"
      if ! curl -fsSL https://get.docker.com | bash; then
        log_warn "Docker install failed"
        return 1
      fi
    fi
  fi

  if ! docker compose version >/dev/null 2>&1; then
    log_info "Installing Docker Compose"
    if [[ "${DRY_RUN}" -eq 0 ]]; then
      apt-get install -y docker-compose-v2 2>/dev/null \
        || apt-get install -y docker-compose-plugin 2>/dev/null \
        || apt-get install -y docker-compose 2>/dev/null \
        || log_warn "Could not install a docker compose package"
    fi
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
  groupadd -f docker 2>/dev/null || true
  usermod -aG docker "${TARGET_USER}" 2>/dev/null || true
  log_ok "User ${TARGET_USER} added to the docker group (re-login may be required)"
}

install_sysreptor() {
  if [[ "${SKIP_SYSREPTOR}" -eq 1 ]]; then
    log_info "Skipping SysReptor (--skip-sysreptor)"
    return 0
  fi

  if [[ -d "${SYSREPTOR_DIR_DEFAULT}/deploy" ]] || [[ -d "${TARGET_HOME}/sysreptor/deploy" ]]; then
    log_ok "SysReptor already present; skipping download"
    write_sysreptor_helpers
    return 0
  fi

  log_info "Installing SysReptor (pentest reporting platform)"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  if ! ensure_docker; then
    log_warn "SysReptor skipped: Docker not available"
    return 0
  fi

  local install_script parent dest
  install_script="$(mktemp /tmp/sysreptor-install.XXXXXX.sh)"
  dest="${SYSREPTOR_DIR_DEFAULT}"
  parent="$(dirname "${dest}")"

  if ! curl -fsSL -o "${install_script}" "${SYSREPTOR_INSTALL_URL}"; then
    log_warn "Could not download the SysReptor install script; skipping"
    rm -f "${install_script}"
    return 0
  fi
  chmod 755 "${install_script}"

  mkdir -p "${parent}"
  if ! ( cd "${parent}" && bash "${install_script}" ); then
    log_warn "SysReptor install script failed; continuing without it"
    rm -f "${install_script}"
    return 0
  fi
  rm -f "${install_script}"

  if [[ -d "${parent}/sysreptor" && ! -d "${dest}" ]]; then
    mv "${parent}/sysreptor" "${dest}" || true
  fi
  if [[ -d "${dest}" ]]; then
    chown -R "${TARGET_USER}:${TARGET_USER}" "${dest}" 2>/dev/null || true
    log_ok "SysReptor installed at ${dest}"
  fi
  write_sysreptor_helpers
}

write_sysreptor_helpers() {
  local root=""
  if [[ -d "${SYSREPTOR_DIR_DEFAULT}/deploy" ]]; then
    root="${SYSREPTOR_DIR_DEFAULT}"
  elif [[ -d "${TARGET_HOME}/sysreptor/deploy" ]]; then
    root="${TARGET_HOME}/sysreptor"
  else
    return 0
  fi

  mkdir -p "${OPT_DIR}"
  cat > "${OPT_DIR}/sysreptor-start.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${root}/deploy"
docker compose up -d
echo "SysReptor: http://127.0.0.1:8000/"
EOF
  cat > "${OPT_DIR}/sysreptor-stop.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${root}/deploy"
docker compose stop
EOF
  chmod 755 "${OPT_DIR}/sysreptor-start.sh" "${OPT_DIR}/sysreptor-stop.sh"

  mkdir -p "${TARGET_HOME}/.local/share/applications"
  cat > "${TARGET_HOME}/.local/share/applications/sysreptor.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SysReptor
Comment=Pentest reporting platform
Exec=xdg-open http://127.0.0.1:8000/
Icon=duckybox
Categories=Network;Office;
Terminal=false
EOF

  local hint="${TARGET_HOME}/.config/duckybox/SYSREPTOR.txt"
  mkdir -p "$(dirname "${hint}")"
  cat > "${hint}" <<EOF
SysReptor (Duckybox)
====================
Install path: ${root}
UI:           http://127.0.0.1:8000/

Start:  ${OPT_DIR}/sysreptor-start.sh
Stop:   ${OPT_DIR}/sysreptor-stop.sh

Docs: https://docs.sysreptor.com/setup/installation/
You may need to log out and back in once for docker group membership.
EOF
  chown -R "${TARGET_USER}:${TARGET_USER}" \
    "${TARGET_HOME}/.config/duckybox" \
    "${TARGET_HOME}/.local/share/applications/sysreptor.desktop" 2>/dev/null || true
  log_ok "SysReptor helpers written"
}

# ---------------------------------------------------------------------------
# Brand assets
# ---------------------------------------------------------------------------

regen_brand_assets() {
  local needed=0
  [[ -f "${REPO_ROOT}/assets/plymouth/logo.png" ]] || needed=1
  [[ -f "${REPO_ROOT}/assets/wallpapers/duckybox-1920x1080.png" ]] || needed=1
  [[ -f "${REPO_ROOT}/assets/greeter/duckybox-login.jpg" ]] || needed=1

  if [[ "${REGEN_BRAND}" -eq 0 && "${needed}" -eq 0 ]]; then
    log_debug "Brand assets already present"
    return 0
  fi

  log_info "Generating brand assets from the Duckybox logo"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  if bash "${REPO_ROOT}/scripts/generate-brand.sh" >>"${LOG_FILE}" 2>&1; then
    log_ok "Brand assets generated"
  else
    log_warn "Brand asset generation reported problems; check the log"
  fi
}

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------

deploy_opt() {
  log_info "Deploying scripts and assets to ${OPT_DIR}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  mkdir -p "${OPT_DIR}"
  install -m 755 "${REPO_ROOT}/scripts/vpnpanel.sh" "${OPT_DIR}/vpnpanel.sh"
  install -m 755 "${REPO_ROOT}/scripts/vpnbash.sh" "${OPT_DIR}/vpnbash.sh"
  install -m 755 "${REPO_ROOT}/scripts/apply-mate-theme.sh" "${OPT_DIR}/apply-mate-theme.sh"
  install -m 755 "${REPO_ROOT}/scripts/generate-brand.sh" "${OPT_DIR}/generate-brand.sh"
  install -m 755 "${REPO_ROOT}/scripts/duckybox-doctor.sh" "${OPT_DIR}/duckybox-doctor.sh"
  cp -f "${REPO_ROOT}/assets/duck.txt" "${OPT_DIR}/duck.txt"
  cp -f "${REPO_ROOT}/assets/duckybox-banner.txt" "${OPT_DIR}/duckybox-banner.txt"
  cp -f "${REPO_ROOT}/configs/terminal/sequences" "${OPT_DIR}/sequences"
  cp -f "${REPO_ROOT}/configs/bash/duckybox.bashrc" "${OPT_DIR}/duckybox.bashrc"

  # apply-mate-theme.sh reads configs relative to a repo layout.
  rm -rf "${OPT_DIR}/repo"
  mkdir -p "${OPT_DIR}/repo"
  cp -a "${REPO_ROOT}/configs" "${OPT_DIR}/repo/"
  cp -a "${REPO_ROOT}/assets" "${OPT_DIR}/repo/"
  cp -a "${REPO_ROOT}/scripts" "${OPT_DIR}/repo/"
  log_ok "Deployed ${OPT_DIR}"
}

install_wallpapers() {
  log_info "Installing wallpapers and the greeter background"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  mkdir -p "${BG_DIR}"
  if compgen -G "${REPO_ROOT}/assets/wallpapers/*.png" >/dev/null; then
    cp -f "${REPO_ROOT}/assets/wallpapers/"*.png "${BG_DIR}/"
  fi
  if [[ -f "${REPO_ROOT}/assets/greeter/duckybox-login.jpg" ]]; then
    cp -f "${REPO_ROOT}/assets/greeter/duckybox-login.jpg" "${BG_DIR}/duckybox-login.jpg"
  fi
  mkdir -p "${ICON_DIR}"
  if compgen -G "${REPO_ROOT}/assets/icons/*.png" >/dev/null; then
    cp -f "${REPO_ROOT}/assets/icons/"*.png "${ICON_DIR}/"
  fi
  log_ok "Wallpapers in ${BG_DIR}"
}

install_gtk_theme() {
  if [[ "${SKIP_GTK}" -eq 1 ]]; then
    log_info "Skipping the GTK theme build (--skip-gtk)"
    return 0
  fi
  log_info "Building the Duckybox GTK theme and violet icons"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  if bash "${REPO_ROOT}/scripts/install-gtk-theme.sh" "${REPO_ROOT}" >>"${LOG_FILE}" 2>&1; then
    log_ok "GTK theme installed"
  else
    log_warn "GTK theme build had problems; CSS overrides will still apply"
  fi
}

install_plank_theme() {
  log_info "Installing the Plank dock theme"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  mkdir -p "${PLANK_THEME_DIR}"
  cp -f "${REPO_ROOT}/configs/plank/theme/dock.theme" "${PLANK_THEME_DIR}/dock.theme"
  log_ok "Plank theme at ${PLANK_THEME_DIR}"
}

configure_tmux() {
  log_info "Configuring tmux for ${TARGET_USER}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  local dest="${TARGET_HOME}/.config/tmux"
  mkdir -p "${dest}"
  if [[ -f "${dest}/tmux.conf" && ! -f "${dest}/tmux.conf.duckybox.bak" ]]; then
    cp -a "${dest}/tmux.conf" "${dest}/tmux.conf.duckybox.bak"
  fi
  cp -f "${REPO_ROOT}/configs/tmux/tmux.conf" "${dest}/tmux.conf"
  if [[ -f "${TARGET_HOME}/.tmux.conf" && ! -f "${TARGET_HOME}/.tmux.conf.duckybox.bak" ]]; then
    cp -a "${TARGET_HOME}/.tmux.conf" "${TARGET_HOME}/.tmux.conf.duckybox.bak"
  fi
  cp -f "${REPO_ROOT}/configs/tmux/tmux.conf" "${TARGET_HOME}/.tmux.conf"
  chown -R "${TARGET_USER}:${TARGET_USER}" "${dest}" "${TARGET_HOME}/.tmux.conf"
  log_ok "tmux theme installed"
}

configure_bashrc() {
  log_info "Patching bashrc for ${TARGET_USER}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  local bashrc="${TARGET_HOME}/.bashrc"
  if [[ -f "${bashrc}" && ! -f "${bashrc}.duckybox.bak" ]]; then
    cp -a "${bashrc}" "${bashrc}.duckybox.bak"
  fi
  touch "${bashrc}"
  # Drop the older Turfbox block if this machine was themed before the rename.
  if grep -q '>>> Turfbox >>>' "${bashrc}"; then
    sed -i '/>>> Turfbox >>>/,/<<< Turfbox <<</d' "${bashrc}"
    log_info "Removed the legacy Turfbox bashrc block"
  fi
  if ! grep -q 'duckybox.bashrc' "${bashrc}"; then
    cat >> "${bashrc}" <<'EOF'

# >>> Duckybox >>>
if [[ -f /opt/duckybox/duckybox.bashrc ]]; then
  # shellcheck disable=SC1091
  source /opt/duckybox/duckybox.bashrc
fi
# <<< Duckybox <<<
EOF
  fi
  chown "${TARGET_USER}:${TARGET_USER}" "${bashrc}"
  log_ok "bashrc updated"
}

# ---------------------------------------------------------------------------
# Boot chain: Plymouth, GRUB, greeter
# ---------------------------------------------------------------------------

setup_plymouth() {
  if [[ "${SKIP_PLYMOUTH}" -eq 1 ]]; then
    log_info "Skipping Plymouth (--skip-plymouth)"
    return 0
  fi
  log_info "Installing the Duckybox Plymouth theme"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  mkdir -p "${THEME_PLYMOUTH}"
  cp -f "${REPO_ROOT}/configs/plymouth/duckybox/duckybox.plymouth" "${THEME_PLYMOUTH}/"
  cp -f "${REPO_ROOT}/configs/plymouth/duckybox/duckybox.script" "${THEME_PLYMOUTH}/"

  local asset
  for asset in logo.png progress_bg.png progress_fg.png bullet.png; do
    if [[ -f "${REPO_ROOT}/assets/plymouth/${asset}" ]]; then
      cp -f "${REPO_ROOT}/assets/plymouth/${asset}" "${THEME_PLYMOUTH}/${asset}"
    else
      log_warn "Plymouth asset missing: ${asset}"
    fi
  done

  if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    plymouth-set-default-theme duckybox || log_warn "plymouth-set-default-theme failed"
  else
    log_warn "plymouth-set-default-theme not found; theme copied but not activated"
  fi

  ensure_grub_cmdline_splash

  if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u || log_warn "update-initramfs failed"
  fi
  log_ok "Plymouth theme installed"
}

ensure_grub_cmdline_splash() {
  [[ -f /etc/default/grub ]] || return 0
  if ! grep -q 'splash' /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 splash"/' \
      /etc/default/grub || true
    log_info "Added splash to GRUB_CMDLINE_LINUX_DEFAULT"
  fi
}

setup_grub_theme() {
  if [[ "${SKIP_GRUB}" -eq 1 ]]; then
    log_info "Skipping the GRUB theme (--skip-grub)"
    return 0
  fi
  log_info "Installing the Duckybox GRUB theme"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  mkdir -p "${THEME_GRUB}"
  cp -f "${REPO_ROOT}/configs/grub/duckybox/theme.txt" "${THEME_GRUB}/theme.txt"

  if [[ -f "${REPO_ROOT}/assets/grub/background-16x9.png" ]]; then
    cp -f "${REPO_ROOT}/assets/grub/background-16x9.png" "${THEME_GRUB}/background.png"
    cp -f "${REPO_ROOT}/assets/grub/background-16x9.png" "${THEME_GRUB}/background-16x9.png"
  fi
  if [[ -f "${REPO_ROOT}/assets/grub/background-4x3.png" ]]; then
    cp -f "${REPO_ROOT}/assets/grub/background-4x3.png" "${THEME_GRUB}/background-4x3.png"
  fi
  local piece
  for piece in select-c slider-c slider-bg; do
    if [[ -f "${REPO_ROOT}/assets/grub/${piece}.png" ]]; then
      cp -f "${REPO_ROOT}/assets/grub/${piece}.png" "${THEME_GRUB}/${piece}.png"
    fi
  done

  if [[ -f /etc/default/grub ]]; then
    cp -a /etc/default/grub /etc/default/grub.duckybox.bak 2>/dev/null || true
    if grep -q '^GRUB_THEME=' /etc/default/grub; then
      sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"${THEME_GRUB}/theme.txt\"|" /etc/default/grub
    else
      printf '\nGRUB_THEME="%s/theme.txt"\n' "${THEME_GRUB}" >> /etc/default/grub
    fi
    if grep -q '^#\?GRUB_GFXMODE=' /etc/default/grub; then
      sed -i 's|^#\?GRUB_GFXMODE=.*|GRUB_GFXMODE=1920x1080,auto|' /etc/default/grub
    else
      printf 'GRUB_GFXMODE=1920x1080,auto\n' >> /etc/default/grub
    fi
    ensure_grub_cmdline_splash
  fi

  if command -v update-grub >/dev/null 2>&1; then
    update-grub || log_warn "update-grub failed"
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg || log_warn "grub-mkconfig failed"
  fi
  log_ok "GRUB theme installed"
}

setup_greeter() {
  log_info "Theming the LightDM greeter"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  if [[ ! -d /etc/lightdm ]]; then
    log_warn "/etc/lightdm not found; skipping greeter theming"
    return 0
  fi

  # Only touch configs for greeters this system actually has installed.
  local applied=0 entry conf binary
  for entry in "lightdm-gtk-greeter.conf:lightdm-gtk-greeter" "slick-greeter.conf:slick-greeter"; do
    conf="${entry%%:*}"
    binary="${entry##*:}"
    if ! command -v "${binary}" >/dev/null 2>&1 && [[ ! -f "/etc/lightdm/${conf}" ]]; then
      log_debug "${binary} not present; skipping ${conf}"
      continue
    fi
    if [[ -f "/etc/lightdm/${conf}" && ! -f "/etc/lightdm/${conf}.duckybox.bak" ]]; then
      cp -a "/etc/lightdm/${conf}" "/etc/lightdm/${conf}.duckybox.bak"
    fi
    cp -f "${REPO_ROOT}/configs/lightdm/${conf}" "/etc/lightdm/${conf}"
    log_info "Applied /etc/lightdm/${conf}"
    applied=$((applied + 1))
  done

  if [[ "${applied}" -eq 0 ]]; then
    log_warn "No known LightDM greeter config found; greeter left untouched"
  else
    log_ok "Greeter themed (${applied} config(s))"
  fi
}

apply_mate_as_user() {
  log_info "Applying the MATE desktop theme as ${TARGET_USER}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  local apply="${OPT_DIR}/apply-mate-theme.sh"
  [[ -x "${apply}" ]] || apply="${REPO_ROOT}/scripts/apply-mate-theme.sh"

  sudo -u "${TARGET_USER}" -H \
    DUCKYBOX_OPT="${OPT_DIR}" \
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
    bash "${apply}" \
    || log_warn "Desktop theming returned non-zero (a graphical session may be required)"
  log_ok "MATE desktop step finished"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  parse_args "$@"
  require_root
  init_log
  require_parrot
  detect_user

  install_base_packages
  install_obsidian
  install_sysreptor
  regen_brand_assets
  deploy_opt
  install_wallpapers
  install_gtk_theme
  install_plank_theme
  configure_tmux
  configure_bashrc
  setup_plymouth
  setup_grub_theme
  setup_greeter
  apply_mate_as_user

  log_ok "=== Duckybox install complete ==="
  cat <<EOF

Duckybox is installed.

Next steps:
  1. Reboot. You should see the violet GRUB menu, then the Duckybox splash,
     then a themed login screen.
  2. Log into MATE: Duckybox GTK theme, violet Papirus icons, Plank dock and
     the duck wallpaper.
  3. Add the VPN indicator to the top panel (one time):
       Right-click top panel -> Add to Panel -> Command
       Command: ${OPT_DIR}/vpnpanel.sh   Interval: 5
     (details: ${TARGET_HOME}/.config/duckybox/VPN_PANEL.txt)
  4. Connect OpenVPN (tun0) to see the VPN IP in the panel and prompt.
  5. Apps: Flameshot, Peek, Obsidian, SysReptor (http://127.0.0.1:8000/).

Verify everything at once:
  bash ${OPT_DIR}/duckybox-doctor.sh

Log file: ${LOG_FILE}
EOF
}

main "$@"
