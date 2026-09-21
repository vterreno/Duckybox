#!/usr/bin/env bash
# Duckybox — apply the violet theme and performance tweaks to KDE Plasma.
# Runs as the target desktop user, not root.

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

log() { duckybox_log kde "$@"; }

# Plasma 6 suffixes its tools with 6, Plasma 5 with 5, older builds not at all.
pick_tool() {
  local name
  for name in "$@"; do
    if command -v "${name}" >/dev/null 2>&1; then
      printf '%s' "${name}"
      return 0
    fi
  done
  return 1
}

KWRITE="$(pick_tool kwriteconfig6 kwriteconfig5 kwriteconfig || true)"
QDBUS="$(pick_tool qdbus6 qdbus qdbus-qt6 qdbus-qt5 || true)"
BALOOCTL="$(pick_tool balooctl6 balooctl || true)"

kwrite() {
  # kwrite <file> <group> <key> <value>
  [[ -n "${KWRITE}" ]] || return 0
  "${KWRITE}" --file "$1" --group "$2" --key "$3" "$4" 2>/dev/null || true
}

install_color_scheme() {
  log "Installing the Duckybox color scheme"
  local dest="${HOME_DIR}/.local/share/color-schemes"
  mkdir -p "${dest}"
  cp -f "${REPO_ROOT}/configs/kde/color-schemes/Duckybox.colors" "${dest}/Duckybox.colors"

  if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    plasma-apply-colorscheme Duckybox >/dev/null 2>&1 \
      && log "Color scheme applied" \
      || log "plasma-apply-colorscheme failed; writing kdeglobals directly"
  fi

  # Belt and braces: the key the scheme tool would set anyway.
  kwrite kdeglobals General ColorScheme Duckybox
  kwrite kdeglobals General AccentColor '124,58,237'
  kwrite kdeglobals KDE widgetStyle Breeze
}

apply_icons_and_style() {
  log "Setting icons and widget style"
  kwrite kdeglobals Icons Theme Papirus-Dark
  kwrite kdeglobals General TerminalApplication konsole

  if command -v plasma-apply-desktoptheme >/dev/null 2>&1; then
    plasma-apply-desktoptheme breeze-dark >/dev/null 2>&1 || true
  fi

  # GTK apps inside Plasma follow these.
  mkdir -p "${HOME_DIR}/.config/gtk-3.0" "${HOME_DIR}/.config/gtk-4.0"
  duckybox_backup "${HOME_DIR}/.config/gtk-3.0/gtk.css"
  duckybox_backup "${HOME_DIR}/.config/gtk-3.0/settings.ini"
  cp -f "${REPO_ROOT}/configs/gtk/gtk-3.0/gtk.css" "${HOME_DIR}/.config/gtk-3.0/gtk.css"
  cp -f "${REPO_ROOT}/configs/gtk/gtk-3.0/settings.ini" "${HOME_DIR}/.config/gtk-3.0/settings.ini"
  cp -f "${REPO_ROOT}/configs/gtk/gtk-4.0/gtk.css" "${HOME_DIR}/.config/gtk-4.0/gtk.css"
}

apply_window_decorations() {
  log "Theming KWin window decorations"
  # Breeze reads titlebar colours from the [WM] block of the colour scheme,
  # which is where the brand violet lives.
  kwrite kwinrc org.kde.kdecoration2 library org.kde.breeze
  kwrite kwinrc org.kde.kdecoration2 theme Breeze
  kwrite kwinrc org.kde.kdecoration2 BorderSize None
  kwrite kwinrc org.kde.kdecoration2 BorderSizeAuto false
}

tune_performance() {
  log "Disabling compositing, animations and file indexing"

  # Compositing off is the single biggest win in a VM. X11 only; on Wayland
  # the compositor is the session, so KWin ignores this.
  if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
    kwrite kwinrc Compositing Enabled false
  else
    log "Wayland session: leaving compositing alone"
  fi
  kwrite kwinrc Compositing OpenGLIsUnsafe false
  kwrite kwinrc Compositing AnimationSpeed 0

  # Animations across Plasma widgets and dialogs.
  kwrite kdeglobals KDE AnimationDurationFactor 0
  kwrite kdeglobals General AllowKDEAppsToRememberWindowPositions true

  # Visual effects that cost the most.
  local effect
  for effect in blur contrast slidingpopups magiclamp glide fadingpopups \
    kwin4_effect_fade kwin4_effect_scale kwin4_effect_squash; do
    kwrite kwinrc Plugins "${effect}Enabled" false
  done

  # Baloo indexes the whole disk, which on a pentest box is pure overhead.
  kwrite baloofilerc "Basic Settings" Indexing-Enabled false
  if [[ -n "${BALOOCTL}" ]]; then
    "${BALOOCTL}" suspend >/dev/null 2>&1 || true
    "${BALOOCTL}" disable >/dev/null 2>&1 || true
    "${BALOOCTL}" purge >/dev/null 2>&1 || true
  fi
}

apply_wallpaper() {
  local wallpaper
  wallpaper="$(duckybox_pick_wallpaper)"
  if [[ -z "${wallpaper}" ]]; then
    log "No Duckybox wallpaper found; skipping"
    return 0
  fi
  log "Wallpaper: ${wallpaper}"

  if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    if plasma-apply-wallpaperimage "${wallpaper}" >/dev/null 2>&1; then
      log "Wallpaper applied"
      return 0
    fi
    log "plasma-apply-wallpaperimage failed; falling back to the config file"
  fi

  # Fallback for when plasmashell is not running yet: rewrite the Image key in
  # every containment of the desktop config so it takes effect at next login.
  local cfg="${HOME_DIR}/.config/plasma-org.kde.plasma.desktop-appletsrc"
  if [[ -f "${cfg}" ]]; then
    duckybox_backup "${cfg}"
    sed -i "s|^Image=.*|Image=file://${wallpaper}|" "${cfg}"
    log "Wallpaper written to ${cfg} (applies at next login)"
  fi
}

apply_konsole() {
  log "Installing the Duckybox Konsole profile"
  local dest="${HOME_DIR}/.local/share/konsole"
  mkdir -p "${dest}"
  cp -f "${REPO_ROOT}/configs/kde/konsole/Duckybox.colorscheme" "${dest}/Duckybox.colorscheme"
  cp -f "${REPO_ROOT}/configs/kde/konsole/Duckybox.profile" "${dest}/Duckybox.profile"
  kwrite konsolerc "Desktop Entry" DefaultProfile Duckybox.profile
  kwrite konsolerc General ConfigVersion 1
}

bind_flameshot() {
  log "Adding Flameshot to autostart"
  mkdir -p "${HOME_DIR}/.config/autostart"
  cat > "${HOME_DIR}/.config/autostart/flameshot.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Flameshot
Exec=flameshot
Icon=flameshot
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  # Plasma's own screenshot shortcut stays; Flameshot is launched from the tray.
}

write_notes() {
  local notes="${HOME_DIR}/.config/duckybox/KDE.txt"
  mkdir -p "$(dirname "${notes}")"
  cat > "${notes}" <<EOF
Duckybox on KDE Plasma
======================
Applied automatically:
  - Colour scheme "Duckybox" (violet accent #7C3AED, violet titlebars)
  - Icons: Papirus-Dark with violet folders
  - Konsole profile "Duckybox"
  - Wallpaper from /usr/share/backgrounds/duckybox
  - Compositing, animations and Baloo indexing disabled
  - VPN indicator via conky, top-right

If the panel still looks stock, log out and back in: Plasma caches its
configuration in memory and rewrites it on exit, which can undo edits made
while the session is running.

VPN overlay config: ~/.config/conky/duckybox-vpn.conkyrc
  Panel at the bottom instead of the top? Set gap_y = 8.
  Do not want it over windows? Change 'above' to 'below' in own_window_hints.
EOF
  log "Notes written to ${notes}"
}

reload_session() {
  if [[ -z "${QDBUS}" ]]; then
    return 0
  fi
  log "Asking KWin and Plasma to reload"
  "${QDBUS}" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  "${QDBUS}" org.kde.plasmashell /PlasmaShell \
    org.kde.PlasmaShell.refreshCurrentShell >/dev/null 2>&1 || true
}

main() {
  if [[ -z "${KWRITE}" ]]; then
    log "kwriteconfig not found; is this really a Plasma system?"
  fi
  install_color_scheme
  apply_icons_and_style
  apply_window_decorations
  tune_performance
  apply_wallpaper
  apply_konsole
  bind_flameshot
  duckybox_setup_vpn_overlay kde "${REPO_ROOT}" "${HOME_DIR}"
  write_notes
  reload_session
  log "Duckybox KDE theme applied (log out and back in to settle)"
}

main "$@"
