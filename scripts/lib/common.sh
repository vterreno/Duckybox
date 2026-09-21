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

# Keyboard layout chosen at install time. Read from disk rather than passed in,
# so re-running an apply script by hand uses the same layout as the install did.
duckybox_keyboard_layout() {
  local conf="${DUCKYBOX_OPT:-/opt/duckybox}/input.conf"
  local layout=""
  if [[ -r "${conf}" ]]; then
    layout="$(sed -n 's/^KEYBOARD_LAYOUT=//p' "${conf}" | head -n1)"
  fi
  printf '%s' "${layout:-latam}"
}

# Pointing devices that can invert their scroll direction, one per line as
# "<xinput id>|<vendor>|<product>|<name>". Only libinput devices expose the
# property, so testing for it is both the filter and the capability check.
duckybox_pointer_devices() {
  command -v xinput >/dev/null 2>&1 || return 0
  local id props name ids vendor product
  for id in $(xinput list --id-only 2>/dev/null); do
    props="$(xinput list-props "${id}" 2>/dev/null)" || continue
    printf '%s' "${props}" | grep -q 'Natural Scrolling Enabled' || continue

    name="$(xinput list --name-only "${id}" 2>/dev/null | head -n1)"
    # Reported as "Device Product ID (275):\t1133, 49271"
    ids="$(printf '%s\n' "${props}" \
      | sed -n 's/.*Device Product ID ([0-9]*):[[:space:]]*//p' | head -n1)"
    vendor="${ids%%,*}"
    product="${ids##*,}"
    vendor="${vendor// /}"
    product="${product// /}"

    [[ -n "${name}" && -n "${vendor}" && -n "${product}" ]] || continue
    printf '%s|%s|%s|%s\n' "${id}" "${vendor}" "${product}" "${name}"
  done
}

# Invert scrolling in the running session, so it takes effect without a logout.
duckybox_invert_scroll_live() {
  command -v xinput >/dev/null 2>&1 || return 0
  local id
  while IFS='|' read -r id _ _ _; do
    [[ -n "${id}" ]] || continue
    xinput set-prop "${id}" "libinput Natural Scrolling Enabled" 1 2>/dev/null || true
  done < <(duckybox_pointer_devices)
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
