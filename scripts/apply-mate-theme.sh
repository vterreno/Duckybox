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

  # Performance: no compositing, no animations, no desktop icon drawing.
  gsettings set org.mate.Marco.general compositing-manager false 2>/dev/null || true
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
  log "Applying mate-terminal colors"
  if command -v dconf >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/configs/terminal/mate-terminal.dconf" ]]; then
    dconf load /org/mate/terminal/profiles/default/ \
      < "${REPO_ROOT}/configs/terminal/mate-terminal.dconf" || true
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
    "mate-terminal.desktop|org.mate.Terminal.desktop|xfce4-terminal.desktop" \
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

setup_vpn_panel_hint() {
  local hint="${HOME_DIR}/.config/duckybox/VPN_PANEL.txt"
  mkdir -p "$(dirname "${hint}")"
  cat > "${hint}" <<EOF
Duckybox VPN indicator
======================
The conky overlay in the top-right corner is set up automatically and needs
no configuration. Its config lives at:
  ~/.config/conky/duckybox-vpn.conkyrc

If you would rather have it inside the MATE panel instead:

1. Right-click the top panel -> Add to Panel
2. Add "Command"
3. Right-click the new applet -> Preferences
4. Command: ${OPT_DIR}/vpnpanel.sh
5. Interval: 5 seconds

Either way it shows the tun0 address, or that the VPN is down.
EOF
  log "Wrote VPN indicator notes to ${hint}"
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
  duckybox_setup_vpn_overlay mate "${REPO_ROOT}" "${HOME_DIR}"
  setup_vpn_panel_hint
  bind_flameshot
  log "Duckybox desktop applied"
}

main "$@"
