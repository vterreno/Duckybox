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

# Kill the old conky corner overlay if a previous install left it behind.
duckybox_disable_conky_vpn() {
  local home_dir="${1:-${HOME}}"
  pkill -f 'conky.*duckybox-vpn' 2>/dev/null || true
  rm -f "${home_dir}/.config/autostart/duckybox-vpn.desktop" \
        "${home_dir}/.config/conky/duckybox-vpn.conkyrc" 2>/dev/null || true
}

# Autostart the tray indicator that shows tun0 in the top-panel system tray.
duckybox_setup_vpn_tray() {
  local tag="$1" home_dir="${2:-${HOME}}"
  local indicator="/opt/duckybox/vpn-indicator.py"

  mkdir -p "${home_dir}/.config/autostart"
  cat > "${home_dir}/.config/autostart/duckybox-vpn-indicator.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Duckybox VPN indicator
Comment=Shows the tun0 address in the top panel
Exec=${indicator}
Icon=network-vpn
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

  if [[ ! -x "${indicator}" ]]; then
    duckybox_log "${tag}" "VPN indicator script missing at ${indicator}"
    return 0
  fi

  pkill -f 'vpn-indicator.py' 2>/dev/null || true
  if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] || [[ -n "${DISPLAY:-}" ]]; then
    nohup "${indicator}" >/dev/null 2>&1 &
    duckybox_log "${tag}" "VPN tray indicator started"
  else
    duckybox_log "${tag}" "No display yet; VPN tray indicator will start at login"
  fi
}

# MATE: put vpnpanel.sh in the top panel as a Command applet (inline text).
duckybox_setup_mate_vpn_applet() {
  local tag="$1"
  command -v dconf >/dev/null 2>&1 || {
    duckybox_log "${tag}" "dconf missing; cannot add the VPN panel applet"
    return 0
  }

  local obj="duckybox-vpn"
  local list
  list="$(dconf read /org/mate/panel/general/object-id-list 2>/dev/null || true)"

  # Create or refresh the applet object.
  dconf write "/org/mate/panel/objects/${obj}/object-type" "'applet'" 2>/dev/null || true
  dconf write "/org/mate/panel/objects/${obj}/applet-iid" \
    "'CommandAppletFactory::CommandApplet'" 2>/dev/null || true
  dconf write "/org/mate/panel/objects/${obj}/toplevel-id" "'top'" 2>/dev/null || true
  dconf write "/org/mate/panel/objects/${obj}/position" "10" 2>/dev/null || true
  dconf write "/org/mate/panel/objects/${obj}/panel-right-stick" "true" 2>/dev/null || true
  dconf write "/org/mate/panel/objects/${obj}/locked" "true" 2>/dev/null || true
  dconf write "/org/mate/panel/objects/${obj}/prefs/command" \
    "'/opt/duckybox/vpnpanel.sh'" 2>/dev/null || true
  # Interval is seconds; older mate-applets used a different key name.
  dconf write "/org/mate/panel/objects/${obj}/prefs/interval" "5" 2>/dev/null || true

  if [[ "${list}" != *"'${obj}'"* ]]; then
    if [[ -z "${list}" || "${list}" == "@as []" || "${list}" == "[]" ]]; then
      dconf write /org/mate/panel/general/object-id-list "['${obj}']" 2>/dev/null || true
    else
      # Append without destroying the existing layout.
      local trimmed="${list%]*}"
      dconf write /org/mate/panel/general/object-id-list \
        "${trimmed}, '${obj}']" 2>/dev/null || true
    fi
  fi
  duckybox_log "${tag}" "VPN Command applet added to the top panel"
}

# KDE: install the plasmoid and pin it to the first panel when Plasma is live.
duckybox_setup_kde_vpn_plasmoid() {
  local tag="$1" repo_root="$2" home_dir="${3:-${HOME}}"
  local src="${repo_root}/configs/kde/plasmoids/org.duckybox.vpn"
  local dest="${home_dir}/.local/share/plasma/plasmoids/org.duckybox.vpn"

  if [[ ! -d "${src}" ]]; then
    duckybox_log "${tag}" "VPN plasmoid sources missing; tray indicator still covers it"
    return 0
  fi

  mkdir -p "$(dirname "${dest}")"
  rm -rf "${dest}"
  cp -a "${src}" "${dest}"
  duckybox_log "${tag}" "VPN plasmoid installed at ${dest}"

  local qdbus=""
  qdbus="$(command -v qdbus6 || command -v qdbus || command -v qdbus-qt6 || true)"
  if [[ -z "${qdbus}" ]] || ! pgrep -x plasmashell >/dev/null 2>&1; then
    duckybox_log "${tag}" "Plasma not running; add 'Duckybox VPN' to the panel after login"
    return 0
  fi

  local script result
  script='
var found = 0;
for (var i = 0; i < panelIds.length; i++) {
    var panel = panelById(panelIds[i]);
    for (var j = 0; j < panel.widgetIds.length; j++) {
        var w = panel.widgetById(panel.widgetIds[j]);
        if (w.type === "org.duckybox.vpn") { found++; }
    }
}
if (found === 0 && panelIds.length > 0) {
    var p = panelById(panelIds[0]);
    p.addWidget("org.duckybox.vpn");
    print("added");
} else {
    print("present:" + found);
}
'
  result="$("${qdbus}" org.kde.plasmashell /PlasmaShell \
    org.kde.PlasmaShell.evaluateScript "${script}" 2>/dev/null || true)"
  duckybox_log "${tag}" "VPN plasmoid: ${result:-no response}"
}

# Single workspace instead of Parrot's default four virtual desktops.
duckybox_set_single_workspace_mate() {
  local tag="$1"
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.mate.Marco.general num-workspaces 1 2>/dev/null || true
    gsettings set org.mate.Marco.general workspace-names "['Desktop']" 2>/dev/null || true
    duckybox_log "${tag}" "Virtual desktops reduced to 1"
  fi
}

duckybox_set_single_workspace_kde() {
  local tag="$1"
  local kwrite=""
  kwrite="$(command -v kwriteconfig6 || command -v kwriteconfig5 || command -v kwriteconfig || true)"
  if [[ -n "${kwrite}" ]]; then
    "${kwrite}" --file kwinrc --group Desktops --key Number 1 2>/dev/null || true
    "${kwrite}" --file kwinrc --group Desktops --key Rows 1 2>/dev/null || true
    "${kwrite}" --file kwinrc --group Desktops --key Name_1 Desktop 2>/dev/null || true
  fi

  # Live session: shrink the pager immediately when KWin is on the bus.
  local qdbus=""
  qdbus="$(command -v qdbus6 || command -v qdbus || command -v qdbus-qt6 || true)"
  if [[ -n "${qdbus}" ]]; then
    "${qdbus}" org.kde.KWin /VirtualDesktopManager \
      org.kde.KWin.VirtualDesktopManager.setCount 1 >/dev/null 2>&1 \
      || "${qdbus}" org.kde.KWin /KWin setCurrentDesktop 1 >/dev/null 2>&1 \
      || true
  fi
  duckybox_log "${tag}" "Virtual desktops reduced to 1"
}
