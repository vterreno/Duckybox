#!/usr/bin/env bash
# Duckybox — helpers shared by the per-desktop apply scripts.
# Source this; do not execute it.

DUCKYBOX_WALLPAPER_DIR="${DUCKYBOX_WALLPAPER_DIR:-/usr/share/backgrounds/duckybox}"

# duckybox_log <tag> <message...>
duckybox_log() {
  local tag="$1"
  shift
  printf '[duckybox-%s] %s\n' "${tag}" "$*"
}

duckybox_backup() {
  local f="$1"
  if [[ -f "${f}" && ! -f "${f}.duckybox.bak" ]]; then
    cp -a "${f}" "${f}.duckybox.bak"
  fi
}

# Width of the primary screen, or empty when it cannot be determined.
duckybox_screen_width() {
  local width=""
  if command -v xrandr >/dev/null 2>&1; then
    width="$(xrandr 2>/dev/null | awk '/\*/ {print $1; exit}' | cut -d x -f1)"
  fi
  if [[ ! "${width}" =~ ^[0-9]+$ ]] && command -v kscreen-doctor >/dev/null 2>&1; then
    width="$(kscreen-doctor -o 2>/dev/null \
      | grep -oE '[0-9]+x[0-9]+@' | head -n1 | cut -d x -f1)"
  fi
  if [[ "${width}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${width}"
  fi
}

# First existing file among the given basenames, as a full path.
duckybox_first_wallpaper() {
  local name ext
  for name in "$@"; do
    for ext in jpg png; do
      if [[ -f "${DUCKYBOX_WALLPAPER_DIR}/${name}.${ext}" ]]; then
        printf '%s' "${DUCKYBOX_WALLPAPER_DIR}/${name}.${ext}"
        return 0
      fi
    done
  done
  return 1
}

# Wallpaper whose resolution best fits the current screen, falling back to the
# smallest one. Artwork is shipped as JPEG and generated scenes as PNG, so both
# extensions are tried.
duckybox_pick_wallpaper() {
  local width choice
  width="$(duckybox_screen_width)"
  [[ "${width}" =~ ^[0-9]+$ ]] || width=1920

  if (( width >= 3840 )); then
    choice="duckybox-3840x2160"
  elif (( width >= 2560 )); then
    choice="duckybox-2560x1440"
  else
    choice="duckybox-1920x1080"
  fi

  duckybox_first_wallpaper "${choice}" "duckybox-1920x1080" || true
}

# Start the conky VPN overlay and make it persist across logins.
duckybox_setup_vpn_overlay() {
  local tag="$1" repo_root="$2" home_dir="${3:-${HOME}}"
  local conkyrc="${home_dir}/.config/conky/duckybox-vpn.conkyrc"

  if ! command -v conky >/dev/null 2>&1; then
    duckybox_log "${tag}" "conky not installed; skipping the VPN overlay"
    return 0
  fi

  mkdir -p "$(dirname "${conkyrc}")" "${home_dir}/.config/autostart"
  cp -f "${repo_root}/configs/conky/duckybox-vpn.conkyrc" "${conkyrc}"

  cat > "${home_dir}/.config/autostart/duckybox-vpn.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Duckybox VPN indicator
Comment=Shows the tun0 address in the top-right corner
Exec=conky -q -c ${conkyrc}
Icon=duckybox
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

  if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    duckybox_log "${tag}" "Wayland session: conky needs X11, overlay will start after switching"
    return 0
  fi

  pkill -f 'conky.*duckybox-vpn' 2>/dev/null || true
  nohup conky -q -c "${conkyrc}" >/dev/null 2>&1 &
  duckybox_log "${tag}" "VPN overlay running (top-right)"
}
