#!/usr/bin/env bash
# Duckybox — apply MATE performance tweaks, the violet theme, Plank and the
# VPN panel helper. Runs as the target desktop user, not root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

OPT_DIR="${DUCKYBOX_OPT:-/opt/duckybox}"
if [[ -d "${OPT_DIR}/repo/configs" ]]; then
  REPO_ROOT="${OPT_DIR}/repo"
else
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
HOME_DIR="${HOME}"

log() { duckybox_log mate "$@"; }
backup_file() { duckybox_backup "$1"; }

apply_gtk() {
  log "Applying GTK overrides"
  mkdir -p "${HOME_DIR}/.config/gtk-3.0" "${HOME_DIR}/.config/gtk-4.0"
  backup_file "${HOME_DIR}/.config/gtk-3.0/gtk.css"
  backup_file "${HOME_DIR}/.config/gtk-3.0/settings.ini"
  backup_file "${HOME_DIR}/.config/gtk-4.0/gtk.css"
  cp -f "${REPO_ROOT}/configs/gtk/gtk-3.0/gtk.css" "${HOME_DIR}/.config/gtk-3.0/gtk.css"
  cp -f "${REPO_ROOT}/configs/gtk/gtk-3.0/settings.ini" "${HOME_DIR}/.config/gtk-3.0/settings.ini"
  cp -f "${REPO_ROOT}/configs/gtk/gtk-4.0/gtk.css" "${HOME_DIR}/.config/gtk-4.0/gtk.css"
}

apply_theme_and_perf() {
  log "Tuning Marco and applying the Duckybox theme"
  if ! command -v gsettings >/dev/null 2>&1; then
    log "gsettings not available; skipping desktop settings"
    return 0
  fi

  # Performance: compositing stays on so kitty opacity works; animations and
  # desktop-icon drawing stay off. reduced-resources still helps Marco.
  gsettings set org.mate.Marco.general compositing-manager true 2>/dev/null || true
  gsettings set org.mate.Marco.general reduced-resources true 2>/dev/null || true
  gsettings set org.mate.interface enable-animations false 2>/dev/null || true
  gsettings set org.mate.background show-desktop-icons false 2>/dev/null || true

  # Appearance
  gsettings set org.mate.interface gtk-theme 'Duckybox' 2>/dev/null || true
  gsettings set org.mate.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
  gsettings set org.mate.Marco.general theme 'Duckybox' 2>/dev/null || true
  # Matches the darkest tone of the wallpaper artwork, so the solid fallback
  # shown before the image loads does not flash a different colour.
  gsettings set org.mate.background primary-color '#08012F' 2>/dev/null || true
  gsettings set org.mate.background secondary-color '#3304A5' 2>/dev/null || true
  gsettings set org.mate.background picture-options 'zoom' 2>/dev/null || true

  local wallpaper
  wallpaper="$(duckybox_pick_wallpaper)"
  if [[ -n "${wallpaper}" ]]; then
    log "Wallpaper: ${wallpaper}"
    gsettings set org.mate.background picture-filename "${wallpaper}" 2>/dev/null || true
  fi
}

apply_menu_logo() {
  log "Setting the application menu logo"
  # Brisk menu and MATE's own menu read different keys; set whichever exists.
  if command -v dconf >/dev/null 2>&1; then
    dconf write /org/mate/panel/objects/menu-bar/prefs/custom-icon \
      "'/usr/share/icons/duckybox/duckybox-48.png'" 2>/dev/null || true
    dconf write /org/mate/panel/objects/menu-bar/prefs/use-custom-icon true 2>/dev/null || true
  fi
  gsettings set org.mate.panel.menubar icon-name 'duckybox' 2>/dev/null || true
}

apply_terminal() {
  # Keep mate-terminal themed as a fallback, then switch the default to kitty.
  log "Applying mate-terminal colors (fallback)"
  if command -v dconf >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/configs/terminal/mate-terminal.dconf" ]]; then
    dconf load /org/mate/terminal/profiles/default/ \
      < "${REPO_ROOT}/configs/terminal/mate-terminal.dconf" || true
  fi
  duckybox_setup_kitty mate "${REPO_ROOT}" "${HOME_DIR}"

  # Kitty transparency needs a compositor. Keep animations off for speed.
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.mate.Marco.general compositing-manager true 2>/dev/null || true
    gsettings set org.mate.interface enable-animations false 2>/dev/null || true
    log "Marco compositing on (needed for kitty opacity); animations still off"
  fi
}

setup_plank() {
  log "Configuring Plank dock"
  mkdir -p "${HOME_DIR}/.config/autostart" "${HOME_DIR}/.config/plank/dock1/launchers"
  cp -f "${REPO_ROOT}/configs/plank/plank.desktop" "${HOME_DIR}/.config/autostart/plank.desktop"

  local dest="${HOME_DIR}/.config/plank/dock1/launchers"
  rm -f "${dest}"/*.dockitem 2>/dev/null || true

  resolve_desktop() {
    local name
    for name in "$@"; do
      if [[ -f "/usr/share/applications/${name}" ]]; then
        echo "/usr/share/applications/${name}"
        return 0
      fi
      if [[ -f "${HOME_DIR}/.local/share/applications/${name}" ]]; then
        echo "${HOME_DIR}/.local/share/applications/${name}"
        return 0
      fi
    done
    return 1
  }

  local i=0 desk pair
  local -a cands
  for pair in \
    "kitty.desktop" \
    "firefox.desktop|firefox-esr.desktop" \
    "flameshot.desktop|org.flameshot.Flameshot.desktop" \
    "peek.desktop|com.uploadedlobster.peek.desktop" \
    "obsidian.desktop" \
    "sysreptor.desktop"
  do
    IFS='|' read -r -a cands <<< "${pair}"
    if desk="$(resolve_desktop "${cands[@]}")"; then
      cat > "${dest}/$(printf '%02d' "$i").dockitem" <<EOF
[PlankDockItemPreferences]
Launcher=file://${desk}
EOF
      i=$((i + 1))
    fi
  done

  # Plank replaces the bottom panel, so drop it and keep the top one for the
  # VPN indicator. Only rewrite the list when it looks like the stock layout,
  # otherwise a custom panel setup would be destroyed.
  if command -v dconf >/dev/null 2>&1; then
    local toplevels
    toplevels="$(dconf read /org/mate/panel/general/toplevel-id-list 2>/dev/null || true)"
    if [[ "${toplevels}" == *"'top'"* && "${toplevels}" == *"'bottom'"* ]]; then
      log "Removing the bottom panel in favour of Plank"
      dconf write /org/mate/panel/general/toplevel-id-list "['top']" 2>/dev/null || true
    else
      log "Leaving the panel layout as is (${toplevels:-unset})"
    fi
  fi

  if command -v plank >/dev/null 2>&1; then
    if [[ -d /usr/share/plank/themes/Duckybox ]]; then
      mkdir -p "${HOME_DIR}/.config/plank/dock1"
      cat > "${HOME_DIR}/.config/plank/dock1/settings" <<'EOF'
[PlankDockPreferences]
Theme=Duckybox
Position=bottom
IconSize=44
HideMode=1
Alignment=center
EOF
    fi
    nohup plank >/dev/null 2>&1 &
  fi
}

setup_vpn_panel() {
  duckybox_disable_conky_vpn "${HOME_DIR}"
  duckybox_setup_mate_vpn_applet mate
  duckybox_setup_vpn_tray mate "${HOME_DIR}"

  local hint="${HOME_DIR}/.config/duckybox/VPN_PANEL.txt"
  mkdir -p "$(dirname "${hint}")"
  cat > "${hint}" <<EOF
Duckybox VPN indicator
======================
The tun0 address is shown in the top panel:
  - Command applet running ${OPT_DIR}/vpnpanel.sh
  - System-tray indicator (${OPT_DIR}/vpn-indicator.py)

OpenVPN connect helper:
  ${OPT_DIR}/openvpn-connect.sh /path/to/profile.ovpn
EOF
  log "VPN indicator is in the top panel"
}

reduce_workspaces() {
  duckybox_set_single_workspace_mate mate
}

apply_input() {
  local layout
  layout="$(duckybox_keyboard_layout)"
  log "Keyboard layout ${layout} and inverted scroll direction"

  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.mate.peripherals-keyboard-xkb.kbd layouts "['${layout}']" \
      2>/dev/null || true
    # Not every MATE release carries natural-scroll for mice, so check before
    # setting. The installer's X11 snippet covers the releases that do not.
    local schema
    for schema in org.mate.peripherals-mouse org.mate.peripherals-touchpad; do
      if gsettings writable "${schema}" natural-scroll >/dev/null 2>&1; then
        gsettings set "${schema}" natural-scroll true 2>/dev/null || true
        log "natural-scroll set on ${schema}"
      fi
    done
  fi

  duckybox_invert_scroll_live
  if command -v setxkbmap >/dev/null 2>&1; then
    setxkbmap "${layout}" 2>/dev/null || true
  fi
}

bind_flameshot() {
  log "Binding a shortcut to Flameshot"
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.mate.Marco.keybinding-commands command-1 'flameshot gui' 2>/dev/null || true
  fi
  mkdir -p "${HOME_DIR}/.config/autostart"
  cat > "${HOME_DIR}/.config/autostart/flameshot.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Flameshot
Exec=flameshot
Icon=flameshot
X-GNOME-Autostart-enabled=true
EOF
}

main() {
  apply_gtk
  apply_theme_and_perf
  apply_menu_logo
  apply_terminal
  setup_plank
  setup_vpn_panel
  reduce_workspaces
  apply_input
  bind_flameshot
  log "Duckybox desktop applied"
}

main "$@"
