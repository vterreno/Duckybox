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
# dpkg's architecture is the one apt and every .deb follow; uname can differ when
# a 64-bit kernel runs a 32-bit userland.
printf '  Arch:    %s (uname %s)\n' \
  "$(dpkg --print-architecture 2>/dev/null || echo unknown)" "$(uname -m)"
printf '  Session: %s / %s\n' "${XDG_CURRENT_DESKTOP:-?}" "${XDG_SESSION_TYPE:-?}"
printf '  DM:      %s\n' "$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null || echo unknown)"
if command -v xrandr >/dev/null 2>&1; then
  printf '  Screen:  %s\n' "$(xrandr 2>/dev/null | awk '/\*/ {print $1; exit}')"
fi
printf '  Installed DEs:'
command -v plasmashell >/dev/null 2>&1 && printf ' KDE'
command -v marco >/dev/null 2>&1 && printf ' MATE'
printf '\n'
if [[ -f /etc/lightdm/lightdm.conf.d/99-duckybox.conf ]]; then
  printf '  Default session: %s\n' \
    "$(grep -E '^user-session=' /etc/lightdm/lightdm.conf.d/99-duckybox.conf | cut -d= -f2)"
else
  printf '  Default session: not pinned by Duckybox\n'
fi
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
  printf '  NOTE: running Wayland. Peek needs X11; the VPN tray still works.\n'
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

if command -v marco >/dev/null 2>&1; then
  section "Desktop: MATE"
  check "Plank theme" test -f /usr/share/plank/themes/Duckybox/dock.theme
  if command -v gsettings >/dev/null 2>&1 \
    && gsettings list-schemas 2>/dev/null | grep -q '^org.mate.interface$'; then
    printf '  gtk-theme:   %s\n' "$(gsettings get org.mate.interface gtk-theme 2>/dev/null)"
    printf '  icon-theme:  %s\n' "$(gsettings get org.mate.interface icon-theme 2>/dev/null)"
    printf '  marco:       %s\n' "$(gsettings get org.mate.Marco.general theme 2>/dev/null)"
    printf '  compositing: %s\n' "$(gsettings get org.mate.Marco.general compositing-manager 2>/dev/null)"
    printf '  wallpaper:   %s\n' "$(gsettings get org.mate.background picture-filename 2>/dev/null)"
  else
    printf '  [FAIL] org.mate.* schemas missing, so MATE theming cannot apply\n'
  fi
fi

if command -v plasmashell >/dev/null 2>&1; then
  section "Desktop: KDE Plasma"
  check "color scheme file" test -f "${HOME}/.local/share/color-schemes/Duckybox.colors"
  check "Konsole profile" test -f "${HOME}/.local/share/konsole/Duckybox.profile"
  check "Konsole colorscheme" test -f "${HOME}/.local/share/konsole/Duckybox.colorscheme"
  kread() {
    local tool
    for tool in kreadconfig6 kreadconfig5 kreadconfig; do
      if command -v "${tool}" >/dev/null 2>&1; then
        "${tool}" --file "$1" --group "$2" --key "$3" 2>/dev/null
        return 0
      fi
    done
    echo '(kreadconfig not found)'
  }
  printf '  ColorScheme:  %s\n' "$(kread kdeglobals General ColorScheme)"
  printf '  AccentColor:  %s\n' "$(kread kdeglobals General AccentColor)"
  printf '  icon theme:   %s\n' "$(kread kdeglobals Icons Theme)"
  printf '  widget style: %s\n' "$(kread kdeglobals KDE widgetStyle)"
  printf '  compositing:  %s\n' "$(kread kwinrc Compositing Enabled)"
  printf '  animations:   %s\n' "$(kread kdeglobals KDE AnimationDurationFactor)"
  printf '  baloo index:  %s\n' "$(kread baloofilerc 'Basic Settings' Indexing-Enabled)"
  printf '  konsole prof: %s\n' "$(kread konsolerc 'Desktop Entry' DefaultProfile)"
  printf '  wallpaper:    %s\n' \
    "$(grep -m1 '^Image=' "${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null | cut -d= -f2-)"
fi

section "VPN overlay"
check "vpnpanel.sh" test -x "${OPT_DIR}/vpnpanel.sh"
check "vpn-indicator.py" test -x "${OPT_DIR}/vpn-indicator.py"
check "tray autostart" test -f "${HOME}/.config/autostart/duckybox-vpn-indicator.desktop"
if pgrep -f 'vpn-indicator.py' >/dev/null 2>&1; then
  printf '  [ ok ] tray indicator running\n'
else
  printf '  [ -- ] tray indicator not running (starts at login)\n'
fi
# Legacy conky overlay should be gone.
if [[ -f "${HOME}/.config/autostart/duckybox-vpn.desktop" ]]; then
  printf '  [WARN] old conky VPN autostart still present\n'
fi
printf '  status: %s\n' "$("${OPT_DIR}/vpnpanel.sh" 2>/dev/null || echo 'vpnpanel.sh not runnable')"

section "Pentest tools"
check "openvpn" command -v openvpn
check "openvpn-connect" test -x "${OPT_DIR}/openvpn-connect.sh"
check "linpeas" test -f /opt/duckybox/tools/linpeas.sh
check "winPEASx64" test -f /opt/duckybox/tools/winPEASx64.exe
ls -1 /opt/duckybox/tools/ 2>/dev/null | sed 's/^/  /' || echo '  (none)'

section "Keyboard and mouse"
if [[ -r /etc/default/keyboard ]]; then
  printf '  /etc/default/keyboard XKBLAYOUT: %s\n' \
    "$(sed -n 's/^XKBLAYOUT=//p' /etc/default/keyboard | tr -d '"' | head -n1)"
fi
if command -v setxkbmap >/dev/null 2>&1; then
  printf '  active layout: %s\n' \
    "$(setxkbmap -query 2>/dev/null | sed -n 's/^layout: *//p' | head -n1)"
fi
check "x11 input snippet" test -f /etc/X11/xorg.conf.d/99-duckybox-input.conf
if command -v xinput >/dev/null 2>&1; then
  # Report the live property, which is the thing that actually decides.
  for devid in $(xinput list --id-only 2>/dev/null); do
    devprops="$(xinput list-props "${devid}" 2>/dev/null)" || continue
    printf '%s' "${devprops}" | grep -q 'Natural Scrolling Enabled (' || continue
    printf '  %s: natural scrolling = %s\n' \
      "$(xinput list --name-only "${devid}" 2>/dev/null | head -n1)" \
      "$(printf '%s\n' "${devprops}" \
        | sed -n 's/.*Natural Scrolling Enabled ([0-9]*):[[:space:]]*//p' | head -n1)"
  done
fi

section "Docker / SysReptor"
if command -v docker >/dev/null 2>&1; then
  docker_ver="$(docker --version 2>&1 | head -n1)"
  printf '  docker: %s\n' "${docker_ver}"
  # The podman shim is why SysReptor refuses to install.
  if printf '%s' "${docker_ver}" | grep -qi podman; then
    printf '  NOTE: this is the podman shim; re-run install.sh --force-docker\n'
  fi
  if docker compose version >/dev/null 2>&1; then
    printf '  compose: %s\n' "$(docker compose version 2>&1 | head -n1)"
  else
    printf '  compose: v2 not available\n'
  fi
else
  printf '  docker: not installed\n'
fi
check "sysreptor deploy dir" test -d /opt/sysreptor/deploy

section "Login screen"
dm=""
if [[ -L /etc/systemd/system/display-manager.service ]]; then
  dm="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)"
fi
printf '  display manager: %s\n' "${dm:-unknown}"
printf '  session type now: %s\n' "${XDG_SESSION_TYPE:-unknown}"
case "${dm}" in
  sddm)
    check "sddm duckybox config" test -f /etc/sddm.conf.d/99-duckybox.conf
    check "sddm breeze background" \
      grep -q duckybox /usr/share/sddm/themes/breeze/theme.conf.user
    if [[ -r /var/lib/sddm/state.conf ]]; then
      printf '  sddm last session: %s\n' \
        "$(sed -n 's/^Session=//p' /var/lib/sddm/state.conf | head -n1)"
    fi
    ;;
  lightdm)
    check "lightdm duckybox config" test -f /etc/lightdm/lightdm.conf.d/99-duckybox.conf
    ;;
esac

section "Branding"
# hicolor is what makes Icon=duckybox resolve under any icon theme.
check "duck icon in hicolor" test -f /usr/share/icons/hicolor/48x48/apps/duckybox.png
# Whether the name resolves at all: if it does not, the launcher falls back to
# its stock icon, which on Parrot is the Parrot logo and looks like the theme
# simply did nothing.
for finder in kiconfinder6 kiconfinder5 kiconfinder; do
  if command -v "${finder}" >/dev/null 2>&1; then
    printf '  duckybox resolves to: %s\n' \
      "$("${finder}" duckybox 2>/dev/null | head -n1 || echo 'nothing')"
    break
  fi
done
# The panel layout can come from a distro default rather than the home copy, so
# report every file that could define it.
for appletsrc in \
  "${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc" \
  /etc/xdg/plasma-org.kde.plasma.desktop-appletsrc; do
  [[ -f "${appletsrc}" ]] || continue
  if grep -qE '^icon=(duckybox|/usr/share/icons/duckybox/)' "${appletsrc}"; then
    printf '  plasma menu icon in %s: duckybox\n' "${appletsrc}"
  else
    printf '  plasma menu icon in %s: not ours\n' "${appletsrc}"
    # Whatever icon the launcher points at instead, so a distro-specific name
    # shows up rather than staying a mystery.
    printf '    icon= values: %s\n' \
      "$(sed -n 's/^icon=//p' "${appletsrc}" | sort -u | tr '\n' ' ')"
    printf '    panel plugins: %s\n' \
      "$(sed -n 's/^plugin=//p' "${appletsrc}" | sort -u | tr '\n' ' ')"
  fi
done

section "Boot chain"
check "Plymouth theme dir" test -d /usr/share/plymouth/themes/duckybox
check "Plymouth logo" test -f /usr/share/plymouth/themes/duckybox/logo.png
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
  printf '  default.plymouth alternative: %s\n' "$(plymouth-set-default-theme 2>/dev/null)"
fi
# plymouthd.conf wins over the alternative, so it is the one that decides.
if [[ -f /etc/plymouth/plymouthd.conf ]]; then
  printf '  plymouthd.conf Theme: %s\n' \
    "$(sed -n 's/^ *Theme *= *//p' /etc/plymouth/plymouthd.conf | head -n1)"
else
  printf '  plymouthd.conf: absent\n'
fi
# A theme baked into the initramfs draws before the one on the root filesystem.
initrd="/boot/initrd.img-$(uname -r)"
if command -v lsinitramfs >/dev/null 2>&1 && [[ -f "${initrd}" ]]; then
  themes="$(lsinitramfs "${initrd}" 2>/dev/null \
    | sed -n 's|.*plymouth/themes/\([^/]*\)/.*|\1|p' | sort -u | tr '\n' ' ')"
  printf '  themes in initramfs: %s\n' "${themes:-none}"
fi
# Each variant carries a "duckybox-style:" marker, so the installed style can be
# reported without guessing from its contents.
ply_script=/usr/share/plymouth/themes/duckybox/duckybox.script
if [[ -f "${ply_script}" ]]; then
  printf '  splash style: %s\n' \
    "$(sed -n 's/^# duckybox-style: *//p' "${ply_script}" | head -n1)"
fi
printf '  kernel cmdline: %s\n' \
  "$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub 2>/dev/null | cut -d= -f2-)"
if ! grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*splash' /etc/default/grub 2>/dev/null; then
  printf '  NOTE: no splash on the cmdline, so the boot shows text messages\n'
fi
check "GRUB theme" test -f /boot/grub/themes/duckybox/theme.txt
check "GRUB_THEME configured" grep -q '^GRUB_THEME=' /etc/default/grub
check "grub.d override present" test -f /etc/default/grub.d/99-duckybox.cfg
# A distro GRUB_BACKGROUND or a later grub.d snippet would hide our theme.
printf '  competing GRUB settings:\n'
grep -rHnE '^[[:space:]]*(GRUB_THEME|GRUB_BACKGROUND)=' \
  /etc/default/grub /etc/default/grub.d/ 2>/dev/null | sed 's/^/    /' || echo '    (none)'

section "Greeter"
check "greeter background" test -f /usr/share/backgrounds/duckybox/duckybox-login.jpg
for conf in /etc/lightdm/lightdm-gtk-greeter.conf /etc/lightdm/slick-greeter.conf; do
  if [[ -f "${conf}" ]]; then
    printf '  %s -> %s\n' "${conf}" "$(grep -E '^(background|theme-name)' "${conf}" | tr '\n' ' ')"
  fi
done

section "Wallpapers"
ls -1 /usr/share/backgrounds/duckybox/ 2>/dev/null | sed 's/^/  /' || echo '  (none)'

section "Terminal"
check "kitty installed" command -v kitty
check "kitty config" test -f "${HOME}/.config/kitty/kitty.conf"
if command -v kitty >/dev/null 2>&1; then
  printf '  kitty: %s\n' "$(command -v kitty)"
fi
if [[ -f "${HOME}/.config/kitty/kitty.conf" ]]; then
  printf '  opacity: %s\n' \
    "$(sed -n 's/^background_opacity[[:space:]]*//p' "${HOME}/.config/kitty/kitty.conf" | head -n1)"
fi
if command -v update-alternatives >/dev/null 2>&1; then
  printf '  x-terminal-emulator: %s\n' \
    "$(readlink -f /etc/alternatives/x-terminal-emulator 2>/dev/null || echo unset)"
fi
if command -v gsettings >/dev/null 2>&1 \
  && gsettings list-schemas 2>/dev/null | grep -q '^org.mate.applications-terminal$'; then
  printf '  MATE terminal: %s\n' \
    "$(gsettings get org.mate.applications-terminal exec 2>/dev/null)"
fi
if command -v kreadconfig6 >/dev/null 2>&1 || command -v kreadconfig5 >/dev/null 2>&1; then
  _kt="$(command -v kreadconfig6 || command -v kreadconfig5)"
  printf '  Plasma TerminalApplication: %s\n' \
    "$("${_kt}" --file kdeglobals --group General --key TerminalApplication 2>/dev/null)"
fi

section "Apps"
for app in kitty flameshot peek obsidian tmux docker plank openvpn; do
  if command -v "${app}" >/dev/null 2>&1; then
    printf '  [ ok ] %s\n' "${app}"
  else
    printf '  [ -- ] %s not found\n' "${app}"
  fi
done
# On arm64 Obsidian comes from a tarball, so it lives here instead of dpkg.
[[ -x /opt/obsidian/obsidian ]] && printf '  [ ok ] obsidian (tarball in /opt/obsidian)\n'
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
