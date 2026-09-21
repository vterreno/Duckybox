#!/usr/bin/env bash
# Duckybox — Parrot OS customizer (Pwnbox-style, violet theme)
#
# Themes the whole visual chain: GRUB -> Plymouth -> login screen -> desktop,
# plus tmux, the bash prompt, a VPN indicator and a few working tools.
# Both desktops are supported (MATE and KDE Plasma) and both display managers
# (LightDM and SDDM); everything is detected rather than assumed.
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
KEEP_WAYLAND=0
FORCE_SESSION="auto"
PLYMOUTH_STYLE="minimal"
FORCE_DOCKER=0
# XKB name for Spanish (Latin America). Override with --keyboard.
KEYBOARD_LAYOUT="latam"

# Rows collected during install and printed as a table at the end.
# Each entry is "Component|Status".
SUMMARY_ROWS=()

summary_set() {
  local component="$1" status="$2" i
  for i in "${!SUMMARY_ROWS[@]}"; do
    if [[ "${SUMMARY_ROWS[$i]}" == "${component}|"* ]]; then
      SUMMARY_ROWS[$i]="${component}|${status}"
      return 0
    fi
  done
  SUMMARY_ROWS+=("${component}|${status}")
}

LOG_FILE="/var/log/duckybox-install.log"
OPT_DIR="/opt/duckybox"
THEME_PLYMOUTH="/usr/share/plymouth/themes/duckybox"
THEME_GRUB="/boot/grub/themes/duckybox"
BG_DIR="/usr/share/backgrounds/duckybox"
ICON_DIR="/usr/share/icons/duckybox"
PLANK_THEME_DIR="/usr/share/plank/themes/Duckybox"
OBSIDIAN_DIR="/opt/obsidian"
TOOLS_DIR="/opt/duckybox/tools"
PEASS_RELEASE_API="https://api.github.com/repos/peass-ng/PEASS-ng/releases/latest"
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
  --session WHICH    Desktop to theme: auto (default), mate, kde, both, none
  --keep-wayland     Do not make Plasma X11 the default LightDM session
  --plymouth STYLE   Boot splash between GRUB and the login screen:
                       minimal (default)  the duck alone, static, nothing else
                       full               duck fading in plus a progress bar
                       none               no splash at all, plain text boot
  --skip-obsidian    Do not download/install Obsidian
  --skip-sysreptor   Do not install Docker / SysReptor
  --keyboard LAYOUT  XKB keyboard layout (default: latam, Spanish Latin America)
  --force-docker     Replace Parrot's podman-docker shim with official Docker.
                     SysReptor refuses to run against podman. Only the shim is
                     removed; the podman command keeps working.
  --skip-plymouth    Skip the Plymouth boot splash
  --skip-grub        Skip the GRUB theme
  --skip-gtk         Skip building the Duckybox GTK theme and icons
  -h, --help         Show this help

Duckybox themes MATE and KDE Plasma. With --session auto it detects which of
them are installed and themes each one, so a machine with both is covered.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --verbose) VERBOSE=1 ;;
      --regen-brand) REGEN_BRAND=1 ;;
      --keep-wayland) KEEP_WAYLAND=1 ;;
      --force-docker) FORCE_DOCKER=1 ;;
      --keyboard)
        shift
        KEYBOARD_LAYOUT="${1:-latam}"
        if [[ ! "${KEYBOARD_LAYOUT}" =~ ^[a-z][a-z0-9_-]*$ ]]; then
          echo "Invalid --keyboard layout: ${KEYBOARD_LAYOUT}" >&2
          exit 1
        fi
        ;;
      --plymouth)
        shift
        PLYMOUTH_STYLE="${1:-minimal}"
        case "${PLYMOUTH_STYLE}" in
          minimal|full|none) ;;
          *) echo "Invalid --plymouth: ${PLYMOUTH_STYLE}" >&2; exit 1 ;;
        esac
        ;;
      --session)
        shift
        FORCE_SESSION="${1:-auto}"
        case "${FORCE_SESSION}" in
          auto|mate|kde|both|none) ;;
          *) echo "Invalid --session: ${FORCE_SESSION}" >&2; exit 1 ;;
        esac
        ;;
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
# CPU architecture
# ---------------------------------------------------------------------------

# What this machine is, in the three forms the rest of the installer needs: the
# Debian package architecture, the family (x86 or arm) and the word size. Every
# third-party download below branches on these, because upstreams publish
# different artifacts per family and several are 64-bit only.
ARCH_DEB=""
ARCH_UNAME=""
ARCH_FAMILY=""
ARCH_BITS=""

detect_arch() {
  ARCH_UNAME="$(uname -m)"
  # dpkg is authoritative on Debian: a 64-bit kernel with a 32-bit userland
  # reports x86_64 or aarch64 from uname while apt and every .deb are 32-bit.
  ARCH_DEB="$(dpkg --print-architecture 2>/dev/null || true)"

  if [[ -z "${ARCH_DEB}" ]]; then
    case "${ARCH_UNAME}" in
      x86_64|amd64)        ARCH_DEB="amd64" ;;
      i386|i486|i586|i686) ARCH_DEB="i386" ;;
      aarch64|arm64)       ARCH_DEB="arm64" ;;
      armv7l|armv6l|armhf) ARCH_DEB="armhf" ;;
      *)                   ARCH_DEB="${ARCH_UNAME}" ;;
    esac
  fi

  case "${ARCH_DEB}" in
    amd64)       ARCH_FAMILY="x86"; ARCH_BITS=64 ;;
    i386)        ARCH_FAMILY="x86"; ARCH_BITS=32 ;;
    arm64)       ARCH_FAMILY="arm"; ARCH_BITS=64 ;;
    armhf|armel) ARCH_FAMILY="arm"; ARCH_BITS=32 ;;
    *)           ARCH_FAMILY="other"; ARCH_BITS="?" ;;
  esac

  local model=""
  if [[ -r /proc/cpuinfo ]]; then
    model="$(sed -n 's/^\(model name\|Model\|Hardware\)[[:space:]]*:[[:space:]]*//p' \
      /proc/cpuinfo | head -n1)"
  fi

  if [[ "${ARCH_FAMILY}" == "other" ]]; then
    log_ok "Architecture: ${ARCH_DEB} (uname ${ARCH_UNAME}), neither x86 nor arm"
  else
    log_ok "Architecture: ${ARCH_FAMILY} ${ARCH_BITS}-bit (${ARCH_DEB}, uname ${ARCH_UNAME})"
  fi
  [[ -n "${model}" ]] && log_info "CPU: ${model}"

  if [[ "${ARCH_FAMILY}" == "other" ]]; then
    log_warn "Unrecognised architecture ${ARCH_DEB}; third-party downloads will be skipped"
  elif [[ "${ARCH_BITS}" == "32" ]]; then
    log_warn "32-bit userland: Obsidian and SysReptor publish 64-bit builds only"
  fi

  # Everything else — apt packages, the GTK theme build, the boot chain, both
  # desktops — is architecture independent and installs the same either way.
}

# Which desktops this machine can actually run. Populates DESKTOPS.
detect_desktops() {
  DESKTOPS=()

  case "${FORCE_SESSION}" in
    mate) DESKTOPS=(mate) ;;
    kde) DESKTOPS=(kde) ;;
    both) DESKTOPS=(mate kde) ;;
    none) log_info "Desktop theming disabled (--session none)"; return 0 ;;
    auto)
      if command -v marco >/dev/null 2>&1 || command -v mate-session >/dev/null 2>&1; then
        DESKTOPS+=(mate)
      fi
      if command -v plasmashell >/dev/null 2>&1; then
        DESKTOPS+=(kde)
      fi
      ;;
  esac

  if [[ "${#DESKTOPS[@]}" -eq 0 ]]; then
    log_warn "Neither MATE nor KDE Plasma found; only system-level theming will apply"
  else
    log_ok "Desktops to theme: ${DESKTOPS[*]}"
  fi

  # The session the user is logged into right now, for the report at the end.
  CURRENT_SESSION_TYPE="$(loginctl show-session \
    "$(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="${TARGET_USER}" '$3==u {print $1; exit}')" \
    -p Type --value 2>/dev/null || true)"
  [[ -n "${CURRENT_SESSION_TYPE}" ]] && log_info "Current session type: ${CURRENT_SESSION_TYPE}"
}

in_desktops() {
  local want="$1" d
  for d in "${DESKTOPS[@]:-}"; do
    [[ "${d}" == "${want}" ]] && return 0
  done
  return 1
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
    tmux \
    fonts-dejavu-core \
    flameshot \
    imagemagick \
    curl \
    wget \
    ca-certificates \
    x11-xserver-utils \
    openssl \
    uuid-runtime \
    coreutils \
    sed \
    openvpn \
    python3 \
    python3-gi \
    gir1.2-gtk-3.0
  # AppIndicator backends differ across Parrot releases; try both.
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    apt-get install -y --no-install-recommends \
      gir1.2-ayatanaappindicator3-0.1 2>/dev/null \
      || apt-get install -y --no-install-recommends \
           gir1.2-appindicator3-0.1 2>/dev/null \
      || log_warn "No AppIndicator GI binding; VPN tray may not start"
  fi
  summary_set "OpenVPN" "installed"
  summary_set "Base packages" "installed"
  log_ok "Base packages installed"
}

# Plank and the MATE settings tools are only useful on MATE, and Peek only
# works on X11, so install them where they actually apply.
install_desktop_packages() {
  local pkgs=()
  if in_desktops mate; then
    # mate-applets ships the Command applet used for the VPN text in the panel.
    pkgs+=(plank dconf-cli gsettings-desktop-schemas mate-applets)
  fi
  if in_desktops kde; then
    pkgs+=(konsole)
  fi
  if [[ "${KEEP_WAYLAND}" -eq 0 ]]; then
    pkgs+=(peek)
  else
    log_warn "Peek does not work on Wayland; skipping it"
  fi

  if [[ "${#pkgs[@]}" -gt 0 ]]; then
    apt_install "${pkgs[@]}" || log_warn "some desktop packages failed to install"
  fi
  summary_set "Desktop packages" "installed"
}

install_obsidian() {
  if [[ "${SKIP_OBSIDIAN}" -eq 1 ]]; then
    log_info "Skipping Obsidian (--skip-obsidian)"
    summary_set "Obsidian" "skipped"
    return 0
  fi
  if command -v obsidian >/dev/null 2>&1 \
    || dpkg -l obsidian 2>/dev/null | grep -q '^ii' \
    || [[ -x "${OBSIDIAN_DIR}/obsidian" ]]; then
    log_ok "Obsidian already installed; skipping"
    summary_set "Obsidian" "already installed"
    return 0
  fi

  # Obsidian publishes a .deb for amd64 only. The arm64 desktop build ships as a
  # tarball and an AppImage, so arm64 gets the tarball unpacked by hand instead
  # of being skipped. There is no 32-bit Linux build at all.
  case "${ARCH_DEB}" in
    amd64)
      if obsidian_from_deb 'https://[^"]+obsidian_[0-9.]+_amd64\.deb'; then
        summary_set "Obsidian" "installed (amd64 .deb)"
        return 0
      fi
      log_warn "No amd64 .deb resolved; falling back to the x86_64 tarball"
      obsidian_from_tarball 'https://[^"]+obsidian-[0-9.]+\.tar\.gz'
      summary_set "Obsidian" "installed (amd64 tarball)"
      ;;
    arm64)
      log_info "arm64 detected: Obsidian has no arm64 .deb, using the arm64 tarball"
      obsidian_from_tarball 'https://[^"]+obsidian-[0-9.]+-arm64\.tar\.gz'
      summary_set "Obsidian" "installed (arm64 tarball)"
      ;;
    *)
      log_warn "Obsidian has no ${ARCH_DEB} build (amd64 and arm64 only); skipping"
      summary_set "Obsidian" "skipped (${ARCH_DEB})"
      ;;
  esac
  return 0
}

# The newest release carrying an asset that matches <regex>. Resolved from the
# release list rather than /releases/latest, because "latest" is frequently a
# mobile-only build whose single asset is an .apk, and a desktop download would
# then look unavailable.
obsidian_asset_url() {
  local pattern="$1" releases
  releases="$(curl -fsSL \
    'https://api.github.com/repos/obsidianmd/obsidian-releases/releases?per_page=15' \
    2>/dev/null)" || return 1
  printf '%s' "${releases}" | grep -oE "${pattern}" | head -n1
}

obsidian_from_deb() {
  local pattern="$1"
  log_info "Downloading the Obsidian ${ARCH_DEB} .deb from GitHub Releases"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  local tmp url deb_file
  tmp="$(mktemp -d)"
  if ! url="$(obsidian_asset_url "${pattern}")" || [[ -z "${url}" ]]; then
    rm -rf "${tmp}"
    return 1
  fi

  deb_file="${tmp}/obsidian.deb"
  if ! curl -fsSL -o "${deb_file}" "${url}"; then
    log_warn "Obsidian download failed; continuing without it"
    rm -rf "${tmp}"
    return 0
  fi

  if apt-get install -y "${deb_file}"; then
    log_ok "Obsidian installed (${ARCH_DEB} .deb)"
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

obsidian_from_tarball() {
  local pattern="$1"
  log_info "Downloading the Obsidian tarball for ${ARCH_DEB}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  local tmp url tar_file unpacked
  tmp="$(mktemp -d)"
  if ! url="$(obsidian_asset_url "${pattern}")" || [[ -z "${url}" ]]; then
    log_warn "Could not resolve an Obsidian tarball for ${ARCH_DEB}; skipping"
    rm -rf "${tmp}"
    return 0
  fi

  tar_file="${tmp}/obsidian.tar.gz"
  if ! curl -fsSL -o "${tar_file}" "${url}"; then
    log_warn "Obsidian download failed; continuing without it"
    rm -rf "${tmp}"
    return 0
  fi
  if ! tar -xzf "${tar_file}" -C "${tmp}"; then
    log_warn "Could not unpack the Obsidian tarball; skipping"
    rm -rf "${tmp}"
    return 0
  fi

  unpacked="$(find "${tmp}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  if [[ -z "${unpacked}" || ! -x "${unpacked}/obsidian" ]]; then
    log_warn "The Obsidian tarball did not contain the expected layout; skipping"
    rm -rf "${tmp}"
    return 0
  fi

  rm -rf "${OBSIDIAN_DIR}"
  mkdir -p "${OBSIDIAN_DIR}"
  cp -a "${unpacked}/." "${OBSIDIAN_DIR}/"
  rm -rf "${tmp}"

  # Electron refuses to start when its sandbox helper is not setuid root, and the
  # tarball cannot ship that permission the way a .deb's postinst sets it.
  if [[ -f "${OBSIDIAN_DIR}/chrome-sandbox" ]]; then
    chown root:root "${OBSIDIAN_DIR}/chrome-sandbox"
    chmod 4755 "${OBSIDIAN_DIR}/chrome-sandbox"
  fi
  ln -sf "${OBSIDIAN_DIR}/obsidian" /usr/local/bin/obsidian

  # The tarball has no icon in a standard location, so fall back to the Duckybox
  # mark, which install_icons puts in hicolor where any theme resolves it.
  local icon="duckybox" candidate
  for candidate in \
    "${OBSIDIAN_DIR}/obsidian.png" \
    "${OBSIDIAN_DIR}/resources/app.png" \
    "${OBSIDIAN_DIR}/resources/icon.png"; do
    if [[ -f "${candidate}" ]]; then
      install -D -m 644 "${candidate}" \
        /usr/share/icons/hicolor/512x512/apps/obsidian.png
      icon="obsidian"
      break
    fi
  done

  cat > /usr/share/applications/obsidian.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Obsidian
Comment=Markdown knowledge base
Exec=${OBSIDIAN_DIR}/obsidian %u
Icon=${icon}
Categories=Office;TextEditor;
Terminal=false
StartupWMClass=obsidian
MimeType=x-scheme-handler/obsidian;
EOF
  log_ok "Obsidian installed at ${OBSIDIAN_DIR} (${ARCH_DEB} tarball)"
}

# OpenVPN helper plus linpeas / winpeas from PEASS-ng, ready to copy onto targets.
install_pentest_tools() {
  log_info "Installing OpenVPN helper, linpeas and winpeas"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    summary_set "linpeas / winpeas" "dry-run"
    summary_set "openvpn-connect" "dry-run"
    return 0
  fi

  mkdir -p "${TOOLS_DIR}" "${OPT_DIR}"
  install -m 755 "${REPO_ROOT}/scripts/openvpn-connect.sh" "${OPT_DIR}/openvpn-connect.sh"
  ln -sf "${OPT_DIR}/openvpn-connect.sh" /usr/local/bin/openvpn-connect
  summary_set "openvpn-connect" "installed (${OPT_DIR}/openvpn-connect.sh)"

  local api assets url name
  if ! api="$(curl -fsSL "${PEASS_RELEASE_API}" 2>/dev/null)"; then
    log_warn "Could not reach PEASS-ng releases; linpeas/winpeas skipped"
    summary_set "linpeas / winpeas" "skipped (download failed)"
    return 0
  fi

  assets="$(printf '%s' "${api}" | grep -oE 'https://[^"]+/download/[^"]+')"

  download_tool() {
    local dest_name="$1" pattern="$2" dest link=""
    url="$(printf '%s\n' "${assets}" | grep -E "${pattern}" | head -n1 || true)"
    [[ -n "${url}" ]] || return 1
    dest="${TOOLS_DIR}/${dest_name}"
    if curl -fsSL -o "${dest}" "${url}"; then
      chmod 755 "${dest}" 2>/dev/null || chmod 644 "${dest}"
      log_ok "Downloaded ${dest_name}"
      return 0
    fi
    rm -f "${dest}"
    return 1
  }

  local peass_ok=0
  if download_tool "linpeas.sh" '/linpeas\.sh$'; then
    ln -sf "${TOOLS_DIR}/linpeas.sh" /usr/local/bin/linpeas
    peass_ok=1
  fi
  # Prefer the script; fall back to the fat build if the slim name is missing.
  if [[ "${peass_ok}" -eq 0 ]] && download_tool "linpeas.sh" '/linpeas_fat\.sh$'; then
    ln -sf "${TOOLS_DIR}/linpeas.sh" /usr/local/bin/linpeas
    peass_ok=1
  fi

  download_tool "winPEASx64.exe" '/winPEASx64\.exe$' && peass_ok=1 || true
  download_tool "winPEASx86.exe" '/winPEASx86\.exe$' && peass_ok=1 || true
  download_tool "winPEASany.exe" '/winPEASany\.exe$' && peass_ok=1 || true
  download_tool "winPEAS.bat" '/winPEAS\.bat$' && peass_ok=1 || true

  # Convenience names without the PEAS capitalisation.
  [[ -f "${TOOLS_DIR}/winPEASx64.exe" ]] && ln -sf winPEASx64.exe "${TOOLS_DIR}/winpeas.exe"
  [[ -f "${TOOLS_DIR}/linpeas.sh" ]] && ln -sf linpeas.sh "${TOOLS_DIR}/linpeas"

  chown -R root:root "${TOOLS_DIR}" 2>/dev/null || true
  if [[ "${peass_ok}" -eq 1 ]]; then
    summary_set "linpeas / winpeas" "installed (${TOOLS_DIR})"
    log_ok "PEASS tools in ${TOOLS_DIR}"
  else
    summary_set "linpeas / winpeas" "skipped (no assets resolved)"
    log_warn "Could not download linpeas/winpeas assets"
  fi
}

# Parrot ships podman-docker, which puts a podman shim at /usr/bin/docker. So
# `command -v docker` succeeds while `docker` is not Docker at all, and
# SysReptor's installer rejects it outright with `docker --version | grep -q
# podman`. Only the shim package is the problem; podman itself is untouched.
docker_is_podman() {
  command -v docker >/dev/null 2>&1 || return 1
  local target
  target="$(readlink -f "$(command -v docker)" 2>/dev/null || true)"
  [[ "${target}" == */podman ]] && return 0
  docker --version 2>&1 | grep -qi podman && return 0
  return 1
}

replace_podman_docker() {
  log_info "Removing the podman-docker shim and installing official Docker"
  export DEBIAN_FRONTEND=noninteractive

  # Only the CLI shim goes; the podman command keeps working.
  apt-get remove -y podman-docker >/dev/null 2>&1 \
    || log_warn "Could not remove podman-docker"

  if ! apt-get install -y docker.io >/dev/null 2>&1; then
    log_warn "apt docker.io failed; trying get.docker.com"
    if ! curl -fsSL https://get.docker.com | bash; then
      log_warn "Docker install failed"
      return 1
    fi
  fi

  if docker_is_podman; then
    log_warn "docker still resolves to podman; SysReptor cannot run"
    return 1
  fi
  log_ok "Official Docker installed; podman itself is still available"
}

ensure_docker() {
  if docker_is_podman; then
    if [[ "${FORCE_DOCKER}" -eq 1 ]]; then
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        return 0
      fi
      replace_podman_docker || return 1
    else
      log_warn "docker on this system is the podman shim, which SysReptor rejects"
      log_warn "Re-run with --force-docker to swap it for official Docker, or"
      log_warn "use --skip-sysreptor to stop trying. podman stays either way."
      return 1
    fi
  elif command -v docker >/dev/null 2>&1; then
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

  # SysReptor needs compose v2 specifically. Check now so it is skipped with a
  # clear reason instead of failing partway through its own installer.
  if ! docker compose version >/dev/null 2>&1; then
    log_warn "docker compose v2 is not available; SysReptor cannot be installed"
    return 1
  fi
}

install_sysreptor() {
  if [[ "${SKIP_SYSREPTOR}" -eq 1 ]]; then
    log_info "Skipping SysReptor (--skip-sysreptor)"
    summary_set "SysReptor" "skipped"
    return 0
  fi

  if [[ -d "${SYSREPTOR_DIR_DEFAULT}/deploy" ]] || [[ -d "${TARGET_HOME}/sysreptor/deploy" ]]; then
    log_ok "SysReptor already present; skipping download"
    write_sysreptor_helpers
    summary_set "SysReptor" "already installed"
    return 0
  fi

  # SysReptor's images are published for linux/amd64 and linux/arm64. Docker
  # picks the right one from the manifest, so arm64 needs nothing special, but
  # there is no 32-bit image to pull.
  case "${ARCH_DEB}" in
    amd64) ;;
    arm64) log_info "arm64 detected; Docker will pull the arm64 SysReptor images" ;;
    *)
      log_warn "SysReptor has no ${ARCH_DEB} images (amd64 and arm64 only); skipping"
      summary_set "SysReptor" "skipped (${ARCH_DEB})"
      return 0
      ;;
  esac

  log_info "Installing SysReptor (pentest reporting platform)"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    summary_set "SysReptor" "dry-run"
    return 0
  fi

  if ! ensure_docker; then
    log_warn "SysReptor skipped: no usable Docker (see the warnings above)"
    summary_set "SysReptor" "skipped (no Docker)"
    return 0
  fi

  local install_script parent dest
  install_script="$(mktemp /tmp/sysreptor-install.XXXXXX.sh)"
  dest="${SYSREPTOR_DIR_DEFAULT}"
  parent="$(dirname "${dest}")"

  if ! curl -fsSL -o "${install_script}" "${SYSREPTOR_INSTALL_URL}"; then
    log_warn "Could not download the SysReptor install script; skipping"
    rm -f "${install_script}"
    summary_set "SysReptor" "skipped (download failed)"
    return 0
  fi
  chmod 755 "${install_script}"

  mkdir -p "${parent}"
  if ! ( cd "${parent}" && bash "${install_script}" ); then
    log_warn "SysReptor install script failed; continuing without it"
    rm -f "${install_script}"
    summary_set "SysReptor" "failed"
    return 0
  fi
  rm -f "${install_script}"

  if [[ -d "${parent}/sysreptor" && ! -d "${dest}" ]]; then
    mv "${parent}/sysreptor" "${dest}" || true
  fi
  if [[ -d "${dest}" ]]; then
    chown -R "${TARGET_USER}:${TARGET_USER}" "${dest}" 2>/dev/null || true
    log_ok "SysReptor installed at ${dest}"
    summary_set "SysReptor" "installed (${dest})"
  else
    summary_set "SysReptor" "failed"
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
  # Only self-contained scripts get a flat copy; the rest run from repo/ below
  # because they source scripts/lib/.
  install -m 755 "${REPO_ROOT}/scripts/vpnpanel.sh" "${OPT_DIR}/vpnpanel.sh"
  install -m 755 "${REPO_ROOT}/scripts/vpnbash.sh" "${OPT_DIR}/vpnbash.sh"
  install -m 755 "${REPO_ROOT}/scripts/vpn-indicator.py" "${OPT_DIR}/vpn-indicator.py"
  install -m 755 "${REPO_ROOT}/scripts/openvpn-connect.sh" "${OPT_DIR}/openvpn-connect.sh"
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

  # Re-runnable entry point, handy after changing the wallpaper or a config.
  cat > "${OPT_DIR}/apply-desktop.sh" <<'EOF'
#!/usr/bin/env bash
# Duckybox — re-apply the desktop theme for the session you are in.
set -euo pipefail
SCRIPTS=/opt/duckybox/repo/scripts
case "${1:-auto}" in
  mate) targets=(mate) ;;
  kde)  targets=(kde) ;;
  auto)
    targets=()
    case "${XDG_CURRENT_DESKTOP:-}" in
      *KDE*|*plasma*|*Plasma*) targets=(kde) ;;
      *MATE*|*mate*) targets=(mate) ;;
      *)
        command -v plasmashell >/dev/null 2>&1 && targets+=(kde)
        command -v marco >/dev/null 2>&1 && targets+=(mate)
        ;;
    esac
    ;;
  *) echo "Usage: $0 [auto|mate|kde]" >&2; exit 1 ;;
esac
if [[ "${#targets[@]}" -eq 0 ]]; then
  echo "No supported desktop detected." >&2
  exit 1
fi
for t in "${targets[@]}"; do
  bash "${SCRIPTS}/apply-${t}-theme.sh"
done
EOF
  chmod 755 "${OPT_DIR}/apply-desktop.sh"
  log_ok "Deployed ${OPT_DIR}"
}

install_wallpapers() {
  log_info "Installing wallpapers and the greeter background"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  mkdir -p "${BG_DIR}"
  # Artwork ships as JPEG, generated scenes as PNG; clear the directory first so
  # a leftover file from a previous style cannot be picked instead.
  rm -f "${BG_DIR}"/duckybox-*x*.png "${BG_DIR}"/duckybox-*x*.jpg
  local ext
  for ext in png jpg; do
    if compgen -G "${REPO_ROOT}/assets/wallpapers/*.${ext}" >/dev/null; then
      cp -f "${REPO_ROOT}/assets/wallpapers/"*."${ext}" "${BG_DIR}/"
    fi
  done
  if [[ -f "${REPO_ROOT}/assets/greeter/duckybox-login.jpg" ]]; then
    cp -f "${REPO_ROOT}/assets/greeter/duckybox-login.jpg" "${BG_DIR}/duckybox-login.jpg"
  fi
  log_ok "Wallpapers in ${BG_DIR}"
}

install_icons() {
  log_info "Installing the Duckybox icon"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  # A flat directory of duckybox-<size>.png files is not an icon theme, so
  # Icon=duckybox would never resolve and every launcher fell back to the
  # generic file icon. hicolor is the mandatory fallback theme in the
  # freedesktop spec: installing there makes the name resolve under any active
  # theme, Papirus-Dark included.
  local size src dest installed=0
  for size in 16 22 24 32 48 64 128 256; do
    src="${REPO_ROOT}/assets/icons/duckybox-${size}.png"
    [[ -f "${src}" ]] || continue
    dest="/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "${dest}"
    cp -f "${src}" "${dest}/duckybox.png"
    installed=$((installed + 1))
  done

  if (( installed == 0 )); then
    log_warn "No icons in assets/icons; run scripts/generate-brand.sh"
    return 0
  fi

  # Keep the originals somewhere stable for the places that want an absolute
  # path rather than an icon name.
  mkdir -p "${ICON_DIR}"
  cp -f "${REPO_ROOT}/assets/icons/"*.png "${ICON_DIR}/" 2>/dev/null || true

  # Without a cache refresh the new icon stays invisible to Qt and GTK.
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
  fi
  log_ok "Icon installed at ${installed} sizes in hicolor"
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
  if ! in_desktops mate; then
    log_debug "Plank is a MATE-only piece here; skipping its theme"
    return 0
  fi
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

  if [[ "${PLYMOUTH_STYLE}" == "none" ]]; then
    log_info "Disabling the boot splash (--plymouth none)"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      return 0
    fi
    set_grub_splash off
    if command -v update-initramfs >/dev/null 2>&1; then
      update-initramfs -u || log_warn "update-initramfs failed"
    fi
    log_ok "Boot splash disabled; the boot now shows kernel and systemd messages"
    return 0
  fi

  log_info "Installing the Duckybox Plymouth theme (style: ${PLYMOUTH_STYLE})"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  mkdir -p "${THEME_PLYMOUTH}"
  cp -f "${REPO_ROOT}/configs/plymouth/duckybox/duckybox.plymouth" "${THEME_PLYMOUTH}/"

  # The theme always loads duckybox.script; the style decides which variant
  # that is, so switching styles is a re-run and never an edit.
  local variant="${REPO_ROOT}/configs/plymouth/duckybox/duckybox-${PLYMOUTH_STYLE}.script"
  if [[ ! -f "${variant}" ]]; then
    log_error "Missing Plymouth variant: ${variant}"
    return 1
  fi
  cp -f "${variant}" "${THEME_PLYMOUTH}/duckybox.script"

  local asset
  for asset in logo.png progress_bg.png progress_fg.png bullet.png; do
    if [[ -f "${REPO_ROOT}/assets/plymouth/${asset}" ]]; then
      cp -f "${REPO_ROOT}/assets/plymouth/${asset}" "${THEME_PLYMOUTH}/${asset}"
    else
      log_warn "Plymouth asset missing: ${asset}"
    fi
  done

  pin_plymouth_theme duckybox
  set_grub_splash on

  if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u || log_warn "update-initramfs failed"
  fi
  verify_plymouth_initramfs
  log_ok "Plymouth theme installed (${PLYMOUTH_STYLE})"
}

# Make a theme the one Plymouth actually uses. Three mechanisms decide this and
# they do not agree, so a theme can be "installed" while a distro spinner still
# draws at boot:
#   - /etc/plymouth/plymouthd.conf, which wins over everything else
#   - the default.plymouth alternative, which is what the initramfs hook copies
#   - plymouth-set-default-theme, a wrapper over the alternative
pin_plymouth_theme() {
  local theme="$1"
  local themefile="/usr/share/plymouth/themes/${theme}/${theme}.plymouth"

  mkdir -p /etc/plymouth
  if [[ -f /etc/plymouth/plymouthd.conf ]] \
    && [[ ! -f /etc/plymouth/plymouthd.conf.duckybox.bak ]]; then
    cp -a /etc/plymouth/plymouthd.conf /etc/plymouth/plymouthd.conf.duckybox.bak
  fi
  # ShowDelay=0 matters: with a delay Plymouth leaves the screen to whatever
  # was there before it starts drawing.
  cat > /etc/plymouth/plymouthd.conf <<EOF
# Duckybox — takes precedence over the default.plymouth alternative.
[Daemon]
Theme=${theme}
ShowDelay=0
DeviceTimeout=8
EOF

  if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    plymouth-set-default-theme "${theme}" >/dev/null 2>&1 \
      || log_warn "plymouth-set-default-theme failed"
    local active
    active="$(plymouth-set-default-theme 2>/dev/null || true)"
    if [[ "${active}" == "${theme}" ]]; then
      log_info "Default Plymouth theme is now ${active}"
    else
      log_warn "Default Plymouth theme reads as '${active}', not ${theme}"
    fi
  elif command -v update-alternatives >/dev/null 2>&1 && [[ -f "${themefile}" ]]; then
    # The mechanism plymouth-set-default-theme wraps, in case it is absent.
    update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
      default.plymouth "${themefile}" 200 >/dev/null 2>&1 || true
    update-alternatives --set default.plymouth "${themefile}" >/dev/null 2>&1 || true
    log_info "Set the default.plymouth alternative to ${theme}"
  else
    log_warn "No way to set the default theme; plymouthd.conf alone will have to do"
  fi
}

# The initramfs carries its own copy of the theme. A stale one means early boot
# draws the previously baked splash, which is where an unexpected spinner comes
# from before ours takes over after switch-root.
verify_plymouth_initramfs() {
  command -v lsinitramfs >/dev/null 2>&1 || return 0
  local img="/boot/initrd.img-$(uname -r)"
  [[ -f "${img}" ]] || return 0

  local listing
  listing="$(lsinitramfs "${img}" 2>/dev/null || true)"
  [[ -n "${listing}" ]] || return 0

  if printf '%s\n' "${listing}" | grep -q 'plymouth/themes/duckybox'; then
    log_ok "Duckybox theme is inside ${img}"
  else
    log_warn "Duckybox theme is NOT in ${img}; early boot will show another splash"
  fi

  # Any other theme in there can draw before ours does.
  local others
  others="$(printf '%s\n' "${listing}" \
    | sed -n 's|.*plymouth/themes/\([^/]*\)/.*|\1|p' \
    | grep -v '^duckybox$' | sort -u | tr '\n' ' ')"
  if [[ -n "${others// /}" ]]; then
    log_info "Other themes present in the initramfs: ${others}"
  fi
}

# set_grub_splash <on|off> — the splash keyword is what tells the kernel to
# hand the screen to Plymouth, so removing it is how you get a text boot.
set_grub_splash() {
  local mode="$1"
  [[ -f /etc/default/grub ]] || return 0
  cp -a /etc/default/grub /etc/default/grub.duckybox.bak 2>/dev/null || true

  local current
  current="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub \
    | head -n1 | sed -E 's/^[^=]+=//; s/^"//; s/"$//')"

  # Drop splash and quiet, then add back what this mode wants. Done in pure
  # bash on purpose: a grep pipeline here exits 1 when it filters everything
  # out, which under `set -o pipefail` would abort the install on the very
  # common value "quiet splash".
  local cleaned="" token
  for token in ${current}; do
    case "${token}" in
      splash|quiet) continue ;;
    esac
    cleaned="${cleaned:+${cleaned} }${token}"
  done

  local wanted
  if [[ "${mode}" == "on" ]]; then
    wanted="$(printf '%s quiet splash' "${cleaned}" | sed -E 's/^ +//')"
  else
    wanted="${cleaned}"
  fi

  if [[ "${current}" == "${wanted}" ]]; then
    log_debug "GRUB_CMDLINE_LINUX_DEFAULT already correct"
    return 0
  fi

  if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${wanted}\"|" \
      /etc/default/grub
  else
    printf '\nGRUB_CMDLINE_LINUX_DEFAULT="%s"\n' "${wanted}" >> /etc/default/grub
  fi
  log_info "GRUB_CMDLINE_LINUX_DEFAULT=\"${wanted}\""

  # The kernel command line lives in grub.cfg, so it has to be regenerated.
  if command -v update-grub >/dev/null 2>&1; then
    update-grub >/dev/null 2>&1 || log_warn "update-grub failed"
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || log_warn "grub-mkconfig failed"
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
    # Parrot ships its own GRUB_BACKGROUND; it would draw over our theme.
    if grep -q '^GRUB_BACKGROUND=' /etc/default/grub; then
      sed -i 's|^GRUB_BACKGROUND=|#GRUB_BACKGROUND=|' /etc/default/grub
      log_info "Disabled the stock GRUB_BACKGROUND in /etc/default/grub"
    fi
    if grep -q '^GRUB_THEME=' /etc/default/grub; then
      sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"${THEME_GRUB}/theme.txt\"|" /etc/default/grub
    else
      printf '\nGRUB_THEME="%s/theme.txt"\n' "${THEME_GRUB}" >> /etc/default/grub
    fi
    # setup_plymouth already decided whether splash belongs on the cmdline;
    # do not re-add it here or --plymouth none would be undone.
  fi

  # grub-mkconfig sources /etc/default/grub.d/*.cfg after /etc/default/grub,
  # so a distro snippet there can silently override the settings above. Land
  # ours last, alphabetically, and clear any inherited background.
  mkdir -p /etc/default/grub.d
  cat > /etc/default/grub.d/99-duckybox.cfg <<EOF
# Duckybox — sourced after every other grub.d snippet, so this wins.
GRUB_THEME="${THEME_GRUB}/theme.txt"
GRUB_BACKGROUND=
GRUB_GFXMODE=auto
EOF
  log_info "Wrote /etc/default/grub.d/99-duckybox.cfg"

  if command -v update-grub >/dev/null 2>&1; then
    update-grub || log_warn "update-grub failed"
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg || log_warn "grub-mkconfig failed"
  fi
  log_ok "GRUB theme installed"
}

# Keyboard layout and scroll direction, set at the system level so they also
# apply at the login screen and in sessions this installer never sees. The
# per-desktop scripts set the same things again through MATE and Plasma, which
# keep their own copies and would otherwise show the old values in their
# settings panels.
configure_input() {
  log_info "Setting the keyboard layout to ${KEYBOARD_LAYOUT} and inverting scroll"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  # localectl is the systemd way and writes both the console keymap and
  # /etc/X11/xorg.conf.d/00-keyboard.conf, keeping the two in agreement.
  local done_via=""
  if command -v localectl >/dev/null 2>&1 \
    && localectl set-x11-keymap "${KEYBOARD_LAYOUT}" >/dev/null 2>&1; then
    done_via="localectl"
  fi

  # Debian's own file. Written either way: localectl updates it on systemd
  # systems, but console-setup reads it directly and a mismatch is confusing.
  if [[ -f /etc/default/keyboard ]]; then
    [[ -f /etc/default/keyboard.duckybox.bak ]] \
      || cp -a /etc/default/keyboard /etc/default/keyboard.duckybox.bak
    if grep -q '^XKBLAYOUT=' /etc/default/keyboard; then
      sed -i "s|^XKBLAYOUT=.*|XKBLAYOUT=\"${KEYBOARD_LAYOUT}\"|" /etc/default/keyboard
    else
      printf 'XKBLAYOUT="%s"\n' "${KEYBOARD_LAYOUT}" >> /etc/default/keyboard
    fi
    # A stale variant would override the layout we just set.
    if grep -q '^XKBVARIANT=' /etc/default/keyboard; then
      sed -i 's|^XKBVARIANT=.*|XKBVARIANT=""|' /etc/default/keyboard
    fi
    [[ -n "${done_via}" ]] || done_via="/etc/default/keyboard"
  fi

  if command -v setupcon >/dev/null 2>&1; then
    setupcon --save-only >/dev/null 2>&1 || true
  fi
  log_ok "Keyboard layout ${KEYBOARD_LAYOUT} (via ${done_via:-nothing available})"

  # Recorded so the apply scripts use the same layout when run by hand later.
  mkdir -p "${OPT_DIR}"
  printf 'KEYBOARD_LAYOUT=%s\n' "${KEYBOARD_LAYOUT}" > "${OPT_DIR}/input.conf"

  # Natural scrolling for every pointer, device-independent. libinput ignores
  # the option on devices it does not drive, so this is safe to apply broadly.
  mkdir -p /etc/X11/xorg.conf.d
  cat > /etc/X11/xorg.conf.d/99-duckybox-input.conf <<EOF
# Duckybox — invert scroll direction for all pointing devices.
Section "InputClass"
    Identifier "Duckybox pointers"
    MatchIsPointer "on"
    Option "NaturalScrolling" "true"
EndSection
EOF
  log_ok "Scroll direction inverted in /etc/X11/xorg.conf.d/99-duckybox-input.conf"
}

# Which display manager actually runs the login screen. Parrot's MATE editions
# use LightDM and the KDE edition uses SDDM, so assuming LightDM meant the
# greeter and the default session were silently left untouched on Plasma.
DISPLAY_MANAGER=""

detect_display_manager() {
  local dm=""

  # The systemd alias is authoritative: it is the unit that will actually start.
  if [[ -L /etc/systemd/system/display-manager.service ]]; then
    dm="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)"
  fi
  # Debian's own record, used when the alias is missing.
  if [[ -z "${dm}" && -r /etc/X11/default-display-manager ]]; then
    dm="$(basename "$(cat /etc/X11/default-display-manager)" 2>/dev/null || true)"
  fi
  # Last resort: whatever is running.
  if [[ -z "${dm}" ]]; then
    local candidate
    for candidate in sddm lightdm gdm3; do
      if pgrep -x "${candidate}" >/dev/null 2>&1; then
        dm="${candidate}"
        break
      fi
    done
  fi

  DISPLAY_MANAGER="${dm}"
  if [[ -n "${DISPLAY_MANAGER}" ]]; then
    log_info "Display manager: ${DISPLAY_MANAGER}"
  else
    log_warn "Could not identify the display manager; the login screen may stay stock"
  fi
}

setup_greeter() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  case "${DISPLAY_MANAGER}" in
    sddm) setup_sddm; return 0 ;;
    lightdm) ;;
    "") log_warn "No display manager detected; skipping login screen theming"; return 0 ;;
    *)
      log_warn "${DISPLAY_MANAGER} is not supported; login screen left stock"
      return 0
      ;;
  esac

  log_info "Theming the LightDM greeter"
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

setup_sddm() {
  log_info "Theming the SDDM login screen"

  local login_bg="${BG_DIR}/duckybox-login.jpg"
  if [[ ! -f "${login_bg}" ]]; then
    log_warn "Login background missing: ${login_bg}; SDDM left stock"
    return 0
  fi

  # Breeze ships with Plasma, and theme.conf.user is its documented override
  # file, so the background survives package upgrades that rewrite theme.conf.
  local theme="breeze"
  local theme_dir="/usr/share/sddm/themes/${theme}"
  if [[ ! -d "${theme_dir}" ]]; then
    log_warn "SDDM theme ${theme} not installed; leaving the current theme alone"
    return 0
  fi

  cat > "${theme_dir}/theme.conf.user" <<EOF
# Duckybox — override file for the Breeze SDDM theme.
[General]
type=image
background=${login_bg}
needsFullUserModel=false
EOF

  mkdir -p /etc/sddm.conf.d
  cat > /etc/sddm.conf.d/99-duckybox.conf <<EOF
# Duckybox — sourced after the distro's own sddm.conf.d snippets.
[Theme]
Current=${theme}
CursorTheme=breeze_cursors
EOF
  log_ok "SDDM themed with the Duckybox login background"
}

# SDDM has no "default session" setting for interactive logins; it remembers the
# last one per user in its state file, so that is what has to be seeded.
sddm_default_session() {
  local session_file="$1"
  local state=/var/lib/sddm/state.conf

  [[ -d /var/lib/sddm ]] || mkdir -p /var/lib/sddm
  if [[ -f "${state}" && ! -f "${state}.duckybox.bak" ]]; then
    cp -a "${state}" "${state}.duckybox.bak"
  fi
  cat > "${state}" <<EOF
[Last]
User=${TARGET_USER}
Session=${session_file}
EOF
  # SDDM runs as its own user and will not read a file it cannot own.
  if id sddm >/dev/null 2>&1; then
    chown -R sddm:sddm /var/lib/sddm 2>/dev/null || true
  fi
  log_ok "SDDM will preselect $(basename "${session_file}") for ${TARGET_USER}"
}

# Peek needs X11, and KWin only honours the compositing and effects settings
# on X11. Make the Plasma X11 session the default.
setup_x11_session() {
  if [[ "${KEEP_WAYLAND}" -eq 1 ]]; then
    log_info "Leaving the default session alone (--keep-wayland)"
    return 0
  fi
  if ! in_desktops kde; then
    log_debug "No Plasma installed; nothing to switch"
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  if [[ -z "${DISPLAY_MANAGER}" ]]; then
    log_warn "No display manager detected; pick the X11 session manually at login"
    return 0
  fi

  local session=""
  find_x11_session() {
    local candidate
    for candidate in plasmax11 plasma-x11 plasma; do
      if [[ -f "/usr/share/xsessions/${candidate}.desktop" ]]; then
        printf '%s' "${candidate}"
        return 0
      fi
    done
    return 1
  }

  if ! session="$(find_x11_session)"; then
    log_info "No Plasma X11 session present; installing plasma-workspace-x11"
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y plasma-workspace-x11 >/dev/null 2>&1 \
      || log_warn "plasma-workspace-x11 install failed"
    session="$(find_x11_session || true)"
  fi

  if [[ -z "${session}" ]]; then
    log_warn "Could not find a Plasma X11 session; leaving the default as is"
    return 0
  fi

  # Everything under /usr/share/xsessions is X11 by definition; the Wayland
  # session lives in /usr/share/wayland-sessions and is deliberately not chosen.
  case "${DISPLAY_MANAGER}" in
    lightdm)
      mkdir -p /etc/lightdm/lightdm.conf.d
      cat > /etc/lightdm/lightdm.conf.d/99-duckybox.conf <<EOF
# Duckybox — default to Plasma on X11. Wayland breaks Peek and KWin's
# compositing switch. Pick Wayland at the login screen whenever you need it;
# this only sets the default.
[Seat:*]
user-session=${session}
EOF
      log_ok "Default session set to ${session} (X11)"
      ;;
    sddm)
      sddm_default_session "/usr/share/xsessions/${session}.desktop"
      ;;
    *)
      log_warn "${DISPLAY_MANAGER}: cannot set the default session; pick ${session} at login"
      ;;
  esac
}

apply_desktop_as_user() {
  if [[ "${#DESKTOPS[@]:-0}" -eq 0 ]]; then
    log_info "No desktop to theme; skipping"
    summary_set "Desktop theme" "skipped (no DE)"
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    summary_set "Desktop theme" "dry-run"
    return 0
  fi

  # Run from the repo copy so the scripts can source scripts/lib/common.sh.
  local scripts_dir="${OPT_DIR}/repo/scripts"
  [[ -d "${scripts_dir}" ]] || scripts_dir="${REPO_ROOT}/scripts"

  local desktop apply failed=0
  for desktop in "${DESKTOPS[@]}"; do
    apply="${scripts_dir}/apply-${desktop}-theme.sh"
    if [[ ! -f "${apply}" ]]; then
      log_warn "Missing ${apply}"
      failed=1
      continue
    fi
    log_info "Applying the ${desktop} desktop theme as ${TARGET_USER}"
    if sudo -u "${TARGET_USER}" -H \
      DUCKYBOX_OPT="${OPT_DIR}" \
      ${USER_SESSION_ENV[@]+"${USER_SESSION_ENV[@]}"} \
      bash "${apply}"; then
      log_ok "${desktop} theme applied"
    else
      log_warn "${desktop} theming returned non-zero (a graphical session may be required)"
      failed=1
    fi
  done

  # Also run the deployed entry point so a later manual re-run uses the same path.
  if [[ -x "${OPT_DIR}/apply-desktop.sh" ]]; then
    log_info "Re-running ${OPT_DIR}/apply-desktop.sh as ${TARGET_USER}"
    sudo -u "${TARGET_USER}" -H \
      DUCKYBOX_OPT="${OPT_DIR}" \
      ${USER_SESSION_ENV[@]+"${USER_SESSION_ENV[@]}"} \
      bash "${OPT_DIR}/apply-desktop.sh" \
      || log_warn "apply-desktop.sh returned non-zero"
  fi

  if [[ "${failed}" -eq 0 ]]; then
    summary_set "Desktop theme" "applied (${DESKTOPS[*]})"
  else
    summary_set "Desktop theme" "partial (re-run ${OPT_DIR}/apply-desktop.sh after login)"
  fi
  summary_set "Virtual desktops" "1 (was 4)"
  summary_set "VPN indicator" "top panel"
  log_ok "Desktop theming finished"
}

print_install_summary() {
  local themed="${DESKTOPS[*]:-none}"
  summary_set "Architecture" "${ARCH_FAMILY} ${ARCH_BITS}-bit (${ARCH_DEB})"
  summary_set "Desktops themed" "${themed}"
  summary_set "Keyboard" "${KEYBOARD_LAYOUT} + inverted scroll"
  summary_set "Boot splash" "${PLYMOUTH_STYLE}"

  local row component status
  local max_c=11 max_s=6
  for row in "${SUMMARY_ROWS[@]}"; do
    component="${row%%|*}"
    status="${row#*|}"
    (( ${#component} > max_c )) && max_c=${#component}
    (( ${#status} > max_s )) && max_s=${#status}
  done

  local rule_c rule_s
  rule_c="$(printf '%*s' "$((max_c + 2))" '' | tr ' ' '-')"
  rule_s="$(printf '%*s' "$((max_s + 2))" '' | tr ' ' '-')"

  printf '\n'
  printf '+%s+%s+\n' "${rule_c}" "${rule_s}"
  printf "| %-*s | %-*s |\n" "${max_c}" "Component" "${max_s}" "Status"
  printf '+%s+%s+\n' "${rule_c}" "${rule_s}"
  for row in "${SUMMARY_ROWS[@]}"; do
    component="${row%%|*}"
    status="${row#*|}"
    printf "| %-*s | %-*s |\n" "${max_c}" "${component}" "${max_s}" "${status}"
  done
  printf '+%s+%s+\n' "${rule_c}" "${rule_s}"

  cat <<EOF

╔══════════════════════════════════════════════════════════════════╗
║  Reinicia la computadora para terminar el proceso.               ║
║                                                                  ║
║  Después del reinicio verás GRUB, el splash y el login themed.   ║
║  El tema se re-aplica solo una vez al iniciar sesión.             ║
╚══════════════════════════════════════════════════════════════════╝

Tools:
  openvpn-connect <profile.ovpn>
  linpeas                  (${TOOLS_DIR}/linpeas.sh)
  winpeas / winPEAS*.exe   (${TOOLS_DIR}/)

Re-apply the desktop theme at any time:
  ${OPT_DIR}/apply-desktop.sh

Verify everything at once:
  bash ${OPT_DIR}/duckybox-doctor.sh

Notes: ${TARGET_HOME}/.config/duckybox/
Log:   ${LOG_FILE}
EOF
}

# Environment needed to talk to the user's running graphical session. sudo wipes
# all of it, and every Plasma tool (plasma-apply-colorscheme, qdbus, xrandr,
# plasmashell --replace) fails silently without it, which left only raw config
# file writes -- and those are lost when plasmashell rewrites its config from
# memory as the session ends.
USER_SESSION_ENV=()

detect_user_session_env() {
  USER_SESSION_ENV=()
  local uid
  uid="$(id -u "${TARGET_USER}" 2>/dev/null || true)"
  [[ -n "${uid}" ]] || return 0

  # The systemd user bus is at a predictable path, no guessing needed.
  if [[ -S "/run/user/${uid}/bus" ]]; then
    USER_SESSION_ENV+=(
      "XDG_RUNTIME_DIR=/run/user/${uid}"
      "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus"
    )
  fi

  # DISPLAY and XAUTHORITY only exist inside the session, so read them back out
  # of a process that is already in it.
  local name pid environ value
  for name in plasmashell plasma_session ksmserver kwin_x11 mate-session marco; do
    pid="$(pgrep -u "${TARGET_USER}" -x "${name}" 2>/dev/null | head -n1)"
    [[ -n "${pid}" ]] || continue
    environ="/proc/${pid}/environ"
    [[ -r "${environ}" ]] || continue

    value="$(tr '\0' '\n' < "${environ}" | sed -n 's/^DISPLAY=//p' | head -n1)"
    [[ -n "${value}" ]] || continue
    USER_SESSION_ENV+=("DISPLAY=${value}")

    value="$(tr '\0' '\n' < "${environ}" | sed -n 's/^XAUTHORITY=//p' | head -n1)"
    [[ -n "${value}" ]] && USER_SESSION_ENV+=("XAUTHORITY=${value}")

    value="$(tr '\0' '\n' < "${environ}" | sed -n 's/^XDG_SESSION_TYPE=//p' | head -n1)"
    [[ -n "${value}" ]] && USER_SESSION_ENV+=("XDG_SESSION_TYPE=${value}")

    log_info "Found ${TARGET_USER}'s session via ${name} (pid ${pid})"
    break
  done

  if [[ "${#USER_SESSION_ENV[@]}" -eq 0 ]]; then
    log_info "No live session for ${TARGET_USER}; the theme will apply at next login"
  fi
}

# Applying the theme from the installer is not enough on Plasma: the session
# that is running when you install rewrites its own config as it ends, so a
# reboot can undo everything. Re-apply once at the next login, from inside a
# real session, and then get out of the way.
install_first_login_hook() {
  if [[ "${#DESKTOPS[@]:-0}" -eq 0 ]]; then
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  local marker="${TARGET_HOME}/.config/autostart/duckybox-first-login.desktop"

  cat > "${OPT_DIR}/first-login.sh" <<EOF
#!/usr/bin/env bash
# Duckybox — runs once at the first login after install, then removes itself.
set -uo pipefail

# Plasma is still starting up: its tools are not on the bus yet, and applying
# too early means plasmashell overwrites the config right after.
sleep 10

mkdir -p "\${HOME}/.cache"
"${OPT_DIR}/apply-desktop.sh" >>"\${HOME}/.cache/duckybox-first-login.log" 2>&1

# Removed whether or not that succeeded: retrying every login would restart the
# panel every login. Read the log above if the desktop still looks stock.
rm -f "${marker}"
EOF
  chmod 755 "${OPT_DIR}/first-login.sh"

  mkdir -p "${TARGET_HOME}/.config/autostart"
  cat > "${marker}" <<EOF
[Desktop Entry]
Type=Application
Name=Duckybox first-login theming
Comment=Applies the Duckybox desktop theme once, then removes itself
Exec=${OPT_DIR}/first-login.sh
Icon=duckybox
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
  chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config/autostart" 2>/dev/null || true
  log_ok "The theme will re-apply automatically at your next login"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  parse_args "$@"
  require_root
  init_log
  require_parrot
  detect_arch
  detect_user
  detect_desktops
  detect_display_manager
  detect_user_session_env

  install_base_packages
  install_desktop_packages
  install_pentest_tools
  install_obsidian
  install_sysreptor
  regen_brand_assets
  deploy_opt
  install_wallpapers
  install_icons
  install_gtk_theme
  install_plank_theme
  configure_tmux
  configure_bashrc
  configure_input
  setup_plymouth
  setup_grub_theme
  setup_greeter
  setup_x11_session
  apply_desktop_as_user
  install_first_login_hook

  log_ok "=== Duckybox install complete ==="
  print_install_summary
}

main "$@"
