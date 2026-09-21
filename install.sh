#!/usr/bin/env bash
# Turfbox — Parrot OS MATE customizer (Pwnbox-style, orange theme)
# Usage: sudo ./install.sh [--dry-run] [--verbose] [--skip-obsidian] [--skip-plymouth] [--skip-sysreptor]

set -euo pipefail

VERSION="1.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

DRY_RUN=0
VERBOSE=0
SKIP_OBSIDIAN=0
SKIP_PLYMOUTH=0
SKIP_SYSREPTOR=0
LOG_FILE="/var/log/turfbox-install.log"
SYSREPTOR_INSTALL_URL="https://docs.sysreptor.com/install.sh"
SYSREPTOR_DIR_DEFAULT="/opt/sysreptor"
OPT_DIR="/opt/turfbox"
THEME_PLYMOUTH="/usr/share/plymouth/themes/turfbox"
BG_DIR="/usr/share/backgrounds/turfbox"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

_log_write() {
  local level="$1"
  shift
  local msg="$*"
  local line
  line="$(_ts) [${level}] ${msg}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    line="$(_ts) [${level}] [DRY-RUN] ${msg}"
  fi
  printf '%s\n' "${line}"
  if [[ -w "$(dirname "${LOG_FILE}")" ]] || [[ -w "${LOG_FILE}" ]] 2>/dev/null; then
    printf '%s\n' "${line}" >> "${LOG_FILE}" 2>/dev/null || true
  fi
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

run_cmd() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_info "Would run: $*"
    return 0
  fi
  log_debug "Running: $*"
  "$@"
}

# ---------------------------------------------------------------------------
# Args / environment
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
Turfbox installer v${VERSION}

Usage: sudo ./install.sh [options]

Options:
  --dry-run          Print actions without changing the system
  --verbose          Extra debug logging
  --skip-obsidian    Do not download/install Obsidian
  --skip-plymouth    Skip Plymouth splash setup
  --skip-sysreptor   Do not install SysReptor (Docker reporting platform)
  -h, --help         Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --verbose) VERBOSE=1 ;;
      --skip-obsidian) SKIP_OBSIDIAN=1 ;;
      --skip-plymouth) SKIP_PLYMOUTH=1 ;;
      --skip-sysreptor) SKIP_SYSREPTOR=1 ;;
      -h|--help) usage; exit 0 ;;
      *) log_error "Unknown option: $1"; usage; exit 1 ;;
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
  log_info "=== Turfbox install v${VERSION} started ==="
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
    log_info "Would apt-get install ${pkgs[*]}"
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
    figlet \
    fonts-dejavu-core \
    flameshot \
    peek \
    imagemagick \
    curl \
    ca-certificates \
    wget \
    dconf-cli \
    gsettings-desktop-schemas \
    openssl \
    uuid-runtime \
    coreutils \
    sed
  log_ok "Base packages installed (including Flameshot and Peek)"
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    log_ok "Docker already present: $(docker --version 2>/dev/null || echo docker)"
  else
    log_info "Installing Docker (apt docker.io)"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      log_info "Would install docker.io and compose"
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

  # Compose v2 plugin or legacy binary
  if docker compose version >/dev/null 2>&1; then
    log_ok "docker compose available"
  else
    log_info "Installing Docker Compose"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      return 0
    fi
    apt-get install -y docker-compose-v2 2>/dev/null \
      || apt-get install -y docker-compose-plugin 2>/dev/null \
      || apt-get install -y docker-compose 2>/dev/null \
      || log_warn "Could not install docker compose package"
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
  groupadd -f docker 2>/dev/null || true
  usermod -aG docker "${TARGET_USER}" 2>/dev/null || true
  log_ok "User ${TARGET_USER} added to docker group (re-login may be required)"
}

install_sysreptor() {
  if [[ "${SKIP_SYSREPTOR}" -eq 1 ]]; then
    log_info "Skipping SysReptor (--skip-sysreptor)"
    return 0
  fi

  # Already installed?
  if [[ -d "${SYSREPTOR_DIR_DEFAULT}/deploy" ]] || [[ -d "${TARGET_HOME}/sysreptor/deploy" ]]; then
    log_ok "SysReptor directory already present; skipping download"
    write_sysreptor_helpers
    return 0
  fi

  log_info "Installing SysReptor (pentest reporting platform)"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_info "Would ensure Docker and run ${SYSREPTOR_INSTALL_URL}"
    return 0
  fi

  if ! ensure_docker; then
    log_warn "SysReptor skipped: Docker not available"
    return 0
  fi

  local install_script dest parent
  install_script="$(mktemp /tmp/sysreptor-install.XXXXXX.sh)"
  dest="${SYSREPTOR_DIR_DEFAULT}"
  parent="$(dirname "${dest}")"

  if ! curl -fsSL -o "${install_script}" "${SYSREPTOR_INSTALL_URL}"; then
    log_warn "Could not download SysReptor install script; skipping"
    rm -f "${install_script}"
    return 0
  fi
  chmod 755 "${install_script}"

  mkdir -p "${parent}"
  # Official installer creates ./sysreptor in the current working directory
  if ! (
    cd "${parent}"
    # Prefer running as target user with docker access; fall back to root
    if sudo -u "${TARGET_USER}" -H docker info >/dev/null 2>&1; then
      sudo -u "${TARGET_USER}" -H bash "${install_script}"
    elif sg docker -c "docker info" >/dev/null 2>&1; then
      sg docker -c "bash ${install_script}"
    else
      bash "${install_script}"
    fi
  ); then
    log_warn "SysReptor install script failed; continuing without it"
    rm -f "${install_script}"
    return 0
  fi
  rm -f "${install_script}"

  # Normalize location to /opt/sysreptor if script created ./sysreptor beside /opt
  if [[ -d "${parent}/sysreptor" && ! -d "${dest}" ]]; then
    mv "${parent}/sysreptor" "${dest}" || true
  fi
  if [[ -d "${dest}" ]]; then
    chown -R "${TARGET_USER}:${TARGET_USER}" "${dest}" 2>/dev/null || true
    log_ok "SysReptor installed at ${dest}"
  elif [[ -d "${TARGET_HOME}/sysreptor" ]]; then
    log_ok "SysReptor installed at ${TARGET_HOME}/sysreptor"
  else
    log_warn "SysReptor directory not found after install; check the log"
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
Icon=web-browser
Categories=Network;Office;
Terminal=false
EOF
  chown -R "${TARGET_USER}:${TARGET_USER}" \
    "${TARGET_HOME}/.local/share/applications/sysreptor.desktop" 2>/dev/null || true

  local hint="${TARGET_HOME}/.config/turfbox/SYSREPTOR.txt"
  mkdir -p "$(dirname "${hint}")"
  cat > "${hint}" <<EOF
SysReptor (Turfbox)
===================
Install path: ${root}
UI:           http://127.0.0.1:8000/

Start:  ${OPT_DIR}/sysreptor-start.sh
Stop:   ${OPT_DIR}/sysreptor-stop.sh

Docs: https://docs.sysreptor.com/setup/installation/
Note: you may need to log out/in once for docker group membership.
EOF
  chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config/turfbox" 2>/dev/null || true
  log_ok "SysReptor helpers written (${OPT_DIR}/sysreptor-*.sh)"
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
  local tmp api_url deb_url deb_file
  tmp="$(mktemp -d)"
  api_url="https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_info "Would download Obsidian for ${arch} and install .deb"
    rm -rf "${tmp}"
    return 0
  fi

  if ! deb_url="$(curl -fsSL "${api_url}" | grep -oE "https://[^\"]+obsidian_[0-9.]+_amd64\\.deb" | head -n1)"; then
    log_warn "Could not resolve Obsidian download URL; skipping"
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
    if command -v obsidian >/dev/null 2>&1 || dpkg -l obsidian 2>/dev/null | grep -q '^ii'; then
      log_ok "Obsidian installed (via dpkg)"
    else
      log_warn "Obsidian install did not complete"
    fi
  fi
  rm -rf "${tmp}"
}

# ---------------------------------------------------------------------------
# Deploy configs
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
  install -m 755 "${REPO_ROOT}/scripts/generate-splash.sh" "${OPT_DIR}/generate-splash.sh"
  cp -f "${REPO_ROOT}/assets/horse.txt" "${OPT_DIR}/horse.txt"
  cp -f "${REPO_ROOT}/assets/turfbox-banner.txt" "${OPT_DIR}/turfbox-banner.txt"
  cp -f "${REPO_ROOT}/configs/terminal/sequences" "${OPT_DIR}/sequences"
  cp -f "${REPO_ROOT}/configs/bash/turfbox.bashrc" "${OPT_DIR}/turfbox.bashrc"
  # Keep a copy of repo configs for apply-mate-theme (expects REPO_ROOT layout)
  mkdir -p "${OPT_DIR}/repo"
  cp -a "${REPO_ROOT}/configs" "${OPT_DIR}/repo/"
  cp -a "${REPO_ROOT}/assets" "${OPT_DIR}/repo/"
  cp -a "${REPO_ROOT}/scripts" "${OPT_DIR}/repo/"
  log_ok "Deployed ${OPT_DIR}"
}

configure_tmux() {
  log_info "Configuring tmux for ${TARGET_USER}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  local dest="${TARGET_HOME}/.config/tmux"
  mkdir -p "${dest}"
  if [[ -f "${dest}/tmux.conf" && ! -f "${dest}/tmux.conf.turfbox.bak" ]]; then
    cp -a "${dest}/tmux.conf" "${dest}/tmux.conf.turfbox.bak"
  fi
  cp -f "${REPO_ROOT}/configs/tmux/tmux.conf" "${dest}/tmux.conf"
  # Also support ~/.tmux.conf
  if [[ -f "${TARGET_HOME}/.tmux.conf" && ! -f "${TARGET_HOME}/.tmux.conf.turfbox.bak" ]]; then
    cp -a "${TARGET_HOME}/.tmux.conf" "${TARGET_HOME}/.tmux.conf.turfbox.bak"
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
  if [[ -f "${bashrc}" && ! -f "${bashrc}.turfbox.bak" ]]; then
    cp -a "${bashrc}" "${bashrc}.turfbox.bak"
  fi
  touch "${bashrc}"
  if ! grep -q 'turfbox.bashrc' "${bashrc}"; then
    cat >> "${bashrc}" <<'EOF'

# >>> Turfbox >>>
if [[ -f /opt/turfbox/turfbox.bashrc ]]; then
  # shellcheck disable=SC1091
  source /opt/turfbox/turfbox.bashrc
fi
# <<< Turfbox <<<
EOF
  fi
  chown "${TARGET_USER}:${TARGET_USER}" "${bashrc}"
  log_ok "bashrc updated"
}

apply_mate_as_user() {
  log_info "Applying MATE theme as ${TARGET_USER}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  # Prefer installed copy
  local apply="${OPT_DIR}/apply-mate-theme.sh"
  if [[ ! -x "${apply}" ]]; then
    apply="${REPO_ROOT}/scripts/apply-mate-theme.sh"
  fi
  sudo -u "${TARGET_USER}" -H \
    TURFBOX_OPT="${OPT_DIR}" \
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
    bash "${apply}" || log_warn "MATE theme apply returned non-zero (may need graphical session)"
  log_ok "MATE theme step finished"
}

# ---------------------------------------------------------------------------
# Plymouth
# ---------------------------------------------------------------------------

setup_plymouth() {
  if [[ "${SKIP_PLYMOUTH}" -eq 1 ]]; then
    log_info "Skipping Plymouth (--skip-plymouth)"
    return 0
  fi
  log_info "Setting up Plymouth theme turfbox"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  mkdir -p "${THEME_PLYMOUTH}" "${BG_DIR}"
  bash "${REPO_ROOT}/scripts/generate-splash.sh" "${REPO_ROOT}/assets/plymouth" || log_warn "Splash generate had warnings"

  cp -f "${REPO_ROOT}/configs/plymouth/turfbox/turfbox.plymouth" "${THEME_PLYMOUTH}/"
  cp -f "${REPO_ROOT}/configs/plymouth/turfbox/turfbox.script" "${THEME_PLYMOUTH}/"

  if [[ -f "${REPO_ROOT}/assets/plymouth/logo.png" ]]; then
    cp -f "${REPO_ROOT}/assets/plymouth/logo.png" "${THEME_PLYMOUTH}/logo.png"
    cp -f "${REPO_ROOT}/assets/plymouth/progress_bg.png" "${THEME_PLYMOUTH}/progress_bg.png"
    cp -f "${REPO_ROOT}/assets/plymouth/progress_fg.png" "${THEME_PLYMOUTH}/progress_fg.png"
  elif [[ -f "${REPO_ROOT}/configs/plymouth/turfbox/logo.png" ]]; then
    cp -f "${REPO_ROOT}/configs/plymouth/turfbox/"*.png "${THEME_PLYMOUTH}/" 2>/dev/null || true
    log_info "Using prebuilt Plymouth PNGs from configs/"
  else
    log_warn "logo.png missing; Plymouth theme may not display correctly"
  fi

  if [[ -f "${REPO_ROOT}/assets/plymouth/turfbox-wallpaper.png" ]]; then
    cp -f "${REPO_ROOT}/assets/plymouth/turfbox-wallpaper.png" "${BG_DIR}/turfbox-wallpaper.png"
  fi

  if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    plymouth-set-default-theme turfbox || log_warn "plymouth-set-default-theme failed"
  else
    # Fallback: write default.plymouth symlink style
    mkdir -p /etc/alternatives
    echo -e "[Plymouth Theme]\nName=Turfbox\nModuleName=script\n[script]\nImageDir=${THEME_PLYMOUTH}\nScriptFile=${THEME_PLYMOUTH}/turfbox.script" \
      > /usr/share/plymouth/themes/default.plymouth || true
  fi

  # GRUB splash
  if [[ -f /etc/default/grub ]]; then
    if ! grep -q 'splash' /etc/default/grub; then
      sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 splash"/' /etc/default/grub || true
    fi
    if command -v update-grub >/dev/null 2>&1; then
      update-grub || log_warn "update-grub failed"
    elif command -v grub-mkconfig >/dev/null 2>&1; then
      grub-mkconfig -o /boot/grub/grub.cfg || log_warn "grub-mkconfig failed"
    fi
  fi

  if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u || log_warn "update-initramfs failed"
  fi
  log_ok "Plymouth theme installed"
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
  deploy_opt
  configure_tmux
  configure_bashrc
  setup_plymouth
  apply_mate_as_user

  log_ok "=== Turfbox install complete ==="
  cat <<EOF

Turfbox is installed.

Next steps:
  1. Reboot to see the Turfbox Plymouth splash.
  2. Log into MATE — Plank dock + orange theme should apply.
  3. Add VPN IP to the top panel:
       Right-click top panel → Add to Panel → Command
       Command: ${OPT_DIR}/vpnpanel.sh   Interval: 5
     (details: ${TARGET_HOME}/.config/turfbox/VPN_PANEL.txt)
  4. Connect OpenVPN (tun0) to see VPN IP in panel and bash prompt.
  5. Apps: Flameshot, Peek, Obsidian, SysReptor (if installs succeeded).
  6. SysReptor UI: http://127.0.0.1:8000/
     Start/stop: ${OPT_DIR}/sysreptor-start.sh | ${OPT_DIR}/sysreptor-stop.sh
     (details: ${TARGET_HOME}/.config/turfbox/SYSREPTOR.txt)

Log file: ${LOG_FILE}
EOF
}

main "$@"
