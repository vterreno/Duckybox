#!/usr/bin/env bash
# Duckybox — collect one report covering every part of the customization.
# Run after installing: bash /opt/duckybox/duckybox-doctor.sh

OPT_DIR="${DUCKYBOX_OPT:-/opt/duckybox}"
LOG_FILE="/var/log/duckybox-install.log"

section() { printf '\n=== %s ===\n' "$*"; }
check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  [ ok ] %s\n' "${label}"
  else
    printf '  [FAIL] %s\n' "${label}"
  fi
}

section "System"
. /etc/os-release 2>/dev/null
printf '  OS:      %s\n' "${PRETTY_NAME:-unknown}"
printf '  Kernel:  %s\n' "$(uname -r)"
printf '  Session: %s / %s\n' "${XDG_CURRENT_DESKTOP:-?}" "${XDG_SESSION_TYPE:-?}"
printf '  DM:      %s\n' "$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null || echo unknown)"
if command -v xrandr >/dev/null 2>&1; then
  printf '  Screen:  %s\n' "$(xrandr 2>/dev/null | awk '/\*/ {print $1; exit}')"
fi

section "Duckybox files"
check "${OPT_DIR} present" test -d "${OPT_DIR}"
check "vpnpanel.sh executable" test -x "${OPT_DIR}/vpnpanel.sh"
check "vpnbash.sh executable" test -x "${OPT_DIR}/vpnbash.sh"
check "banner present" test -f "${OPT_DIR}/duckybox-banner.txt"
check "bashrc hook in ~/.bashrc" grep -q duckybox.bashrc "${HOME}/.bashrc"

section "Theme"
check "GTK theme /usr/share/themes/Duckybox" test -d /usr/share/themes/Duckybox
check "metacity-1 (Marco) decorations" test -d /usr/share/themes/Duckybox/metacity-1
check "Papirus-Dark icons" test -d /usr/share/icons/Papirus-Dark
check "violet folder icons linked" test -L /usr/share/icons/Papirus-Dark/64x64/places/folder.svg
check "menu icon installed" test -f /usr/share/icons/duckybox/duckybox-48.png
check "Plank theme" test -f /usr/share/plank/themes/Duckybox/dock.theme
if command -v gsettings >/dev/null 2>&1; then
  printf '  gtk-theme:  %s\n' "$(gsettings get org.mate.interface gtk-theme 2>/dev/null)"
  printf '  icon-theme: %s\n' "$(gsettings get org.mate.interface icon-theme 2>/dev/null)"
  printf '  marco:      %s\n' "$(gsettings get org.mate.Marco.general theme 2>/dev/null)"
  printf '  compositing:%s\n' "$(gsettings get org.mate.Marco.general compositing-manager 2>/dev/null)"
  printf '  wallpaper:  %s\n' "$(gsettings get org.mate.background picture-filename 2>/dev/null)"
fi

section "Boot chain"
check "Plymouth theme dir" test -d /usr/share/plymouth/themes/duckybox
check "Plymouth logo" test -f /usr/share/plymouth/themes/duckybox/logo.png
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
  printf '  active plymouth theme: %s\n' "$(plymouth-set-default-theme 2>/dev/null)"
fi
check "GRUB theme" test -f /boot/grub/themes/duckybox/theme.txt
check "GRUB_THEME configured" grep -q '^GRUB_THEME=' /etc/default/grub
check "splash in cmdline" grep -q splash /etc/default/grub

section "Greeter"
check "greeter background" test -f /usr/share/backgrounds/duckybox/duckybox-login.jpg
for conf in /etc/lightdm/lightdm-gtk-greeter.conf /etc/lightdm/slick-greeter.conf; do
  if [[ -f "${conf}" ]]; then
    printf '  %s -> %s\n' "${conf}" "$(grep -E '^(background|theme-name)' "${conf}" | tr '\n' ' ')"
  fi
done

section "Wallpapers"
ls -1 /usr/share/backgrounds/duckybox/ 2>/dev/null | sed 's/^/  /' || echo '  (none)'

section "Apps"
for app in flameshot peek obsidian tmux docker plank; do
  if command -v "${app}" >/dev/null 2>&1; then
    printf '  [ ok ] %s\n' "${app}"
  else
    printf '  [ -- ] %s not found\n' "${app}"
  fi
done
check "SysReptor deploy dir" test -d /opt/sysreptor/deploy

section "VPN"
printf '  %s\n' "$("${OPT_DIR}/vpnpanel.sh" 2>/dev/null || echo 'vpnpanel.sh not runnable')"

section "Install log (last 25 lines)"
if [[ -r "${LOG_FILE}" ]]; then
  tail -n 25 "${LOG_FILE}" | sed 's/^/  /'
else
  echo "  ${LOG_FILE} not readable"
fi

printf '\nReport complete. Paste this output plus a screenshot of the login and desktop.\n'
