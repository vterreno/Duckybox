#!/usr/bin/env bash
# Turfbox — apply MATE performance tweaks, orange theme, Plank, VPN panel helpers
# Intended to run as the target desktop user (not root).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPT_DIR="${TURFBOX_OPT:-/opt/turfbox}"
if [[ -d "${OPT_DIR}/repo/configs" ]]; then
  REPO_ROOT="${OPT_DIR}/repo"
elif [[ -d "${SCRIPT_DIR}/../configs" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
HOME_DIR="${HOME}"

log() { printf '[turfbox-mate] %s\n' "$*"; }

backup_file() {
  local f="$1"
  if [[ -f "$f" && ! -f "${f}.turfbox.bak" ]]; then
    cp -a "$f" "${f}.turfbox.bak"
  fi
}

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

apply_marco_perf() {
  log "Tuning Marco compositor for performance"
  if ! command -v gsettings >/dev/null 2>&1; then
    log "gsettings not available; skipping Marco tweaks"
    return 0
  fi
  gsettings set org.mate.Marco.general compositing-manager false 2>/dev/null || true
  gsettings set org.mate.Marco.general reduced-resources true 2>/dev/null || true
  gsettings set org.mate.background show-desktop-icons false 2>/dev/null || true
  gsettings set org.mate.background picture-options 'wallpaper' 2>/dev/null || true
  if [[ -f /usr/share/backgrounds/turfbox/turfbox-wallpaper.png ]]; then
    gsettings set org.mate.background picture-filename \
      '/usr/share/backgrounds/turfbox/turfbox-wallpaper.png' 2>/dev/null || true
  fi
  gsettings set org.mate.background primary-color '#0D1117' 2>/dev/null || true
  gsettings set org.mate.background secondary-color '#FF6A00' 2>/dev/null || true
  gsettings set org.mate.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
  gsettings set org.mate.interface icon-theme 'Adwaita' 2>/dev/null || true
  gsettings set org.mate.Marco.general theme 'TraditionalOk' 2>/dev/null || true
}

apply_terminal() {
  log "Applying mate-terminal colors"
  if command -v dconf >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/configs/terminal/mate-terminal.dconf" ]]; then
    dconf load /org/mate/terminal/profiles/default/ < "${REPO_ROOT}/configs/terminal/mate-terminal.dconf" || true
  fi
}

setup_plank() {
  log "Configuring Plank dock"
  mkdir -p "${HOME_DIR}/.config/autostart"
  mkdir -p "${HOME_DIR}/.config/plank/dock1/launchers"
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

  local i=0
  local desk
  for pair in \
    "mate-terminal.desktop|org.mate.Terminal.desktop|xfce4-terminal.desktop" \
    "firefox.desktop|firefox-esr.desktop" \
    "flameshot.desktop|org.flameshot.Flameshot.desktop" \
    "peek.desktop|com.uploadedlobster.peek.desktop" \
    "obsidian.desktop"
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

  if command -v dconf >/dev/null 2>&1; then
    dconf write /org/mate/panel/general/toplevel-id-list "['top']" 2>/dev/null || true
  fi

  if command -v plank >/dev/null 2>&1; then
    nohup plank >/dev/null 2>&1 &
  fi
}

setup_vpn_panel_hint() {
  local hint="${HOME_DIR}/.config/turfbox/VPN_PANEL.txt"
  mkdir -p "$(dirname "$hint")"
  cat > "$hint" <<EOF
Turfbox VPN panel
=================
To show your VPN IP on the top panel (Pwnbox-style):

1. Right-click the top panel → Add to Panel
2. Add "Command"
3. Right-click the new applet → Preferences
4. Command: ${OPT_DIR}/vpnpanel.sh
5. Interval: 5 seconds

It will show "VPN: <ip>" when tun0 is up, or "VPN: Disconnected".
EOF
  log "Wrote VPN panel instructions to ${hint}"
}

bind_flameshot() {
  log "Binding Print key to Flameshot (best-effort)"
  if command -v gsettings >/dev/null 2>&1; then
    # Disable default screenshot bindings when present
    gsettings set org.mate.Marco.keybinding-commands command-1 'flameshot gui' 2>/dev/null || true
    gsettings set org.mate.Marco.keybinding-commands command-1-status true 2>/dev/null || true
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
  apply_marco_perf
  apply_terminal
  setup_plank
  setup_vpn_panel_hint
  bind_flameshot
  log "MATE theme applied"
}

main "$@"
