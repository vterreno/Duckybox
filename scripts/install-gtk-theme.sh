#!/usr/bin/env bash
# Duckybox — build and install the Duckybox GTK theme and violet icon set.
#
# The GTK theme is Orchis with its purple palette overwritten by the Duckybox
# violet before sassc compiles it, so buttons, selections and window controls
# all land on #7C3AED instead of Orchis' stock purple. Runs as root.

set -euo pipefail

ACCENT='#7C3AED'
ACCENT_DARK='#6D28D9'
THEME_NAME='Duckybox'
ORCHIS_URL='https://github.com/vinceliuice/Orchis-theme.git'
THEMES_DIR='/usr/share/themes'
ICON_THEME='Papirus-Dark'
ICON_COLOR='violet'

log() { printf '[duckybox-gtk] %s\n' "$*"; }
warn() { printf '[duckybox-gtk] WARN: %s\n' "$*" >&2; }

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

install_build_deps() {
  log "Installing theme build dependencies"
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y --no-install-recommends \
    sassc \
    gtk2-engines-murrine \
    gtk2-engines-pixbuf \
    gnome-themes-extra \
    papirus-icon-theme \
    git \
    || warn "some theme dependencies failed to install"
}

build_gtk_theme() {
  local work src produced
  work="$(mktemp -d)"
  src="${work}/Orchis-theme"

  log "Cloning Orchis"
  if ! git clone --depth 1 --quiet "${ORCHIS_URL}" "${src}"; then
    warn "clone failed; keeping the existing GTK theme"
    rm -rf "${work}"
    return 1
  fi

  local palette="${src}/src/_sass/_color-palette-default.scss"
  if [[ ! -f "${palette}" ]]; then
    warn "unexpected Orchis layout; aborting theme build"
    rm -rf "${work}"
    return 1
  fi

  log "Injecting Duckybox violet (${ACCENT}) into the palette"
  sed -i \
    -e "s|^\$purple-light:.*|\$purple-light: ${ACCENT};|" \
    -e "s|^\$purple-dark:.*|\$purple-dark: ${ACCENT_DARK};|" \
    "${palette}"

  log "Building ${THEME_NAME} (dark, standard size, black tweak)"
  if ! ( cd "${src}" && ./install.sh \
      --name "${THEME_NAME}" \
      --theme purple \
      --color dark \
      --size standard \
      --tweaks black \
      --dest "${THEMES_DIR}" >/dev/null ); then
    warn "Orchis install.sh failed"
    rm -rf "${work}"
    return 1
  fi

  # Orchis appends its variant suffixes; normalise to a single "Duckybox" dir.
  produced="$(find "${THEMES_DIR}" -maxdepth 1 -type d -name "${THEME_NAME}-*" | sort | head -n1)"
  if [[ -n "${produced}" ]]; then
    rm -rf "${THEMES_DIR}/${THEME_NAME}"
    mv "${produced}" "${THEMES_DIR}/${THEME_NAME}"
    log "Installed ${THEMES_DIR}/${THEME_NAME}"
  fi

  if [[ -f "${THEMES_DIR}/${THEME_NAME}/index.theme" ]]; then
    sed -i "s|^Name=.*|Name=${THEME_NAME}|" "${THEMES_DIR}/${THEME_NAME}/index.theme"
  fi

  rm -rf "${work}"
}

# Point every folder icon at its violet variant, the same way papirus-folders
# does, so we stay inside the packaged icon set.
recolor_icon_folders() {
  local base="/usr/share/icons/${ICON_THEME}"
  if [[ ! -d "${base}" ]]; then
    warn "${ICON_THEME} not installed; skipping icon recolor"
    return 0
  fi

  log "Recoloring ${ICON_THEME} folders to ${ICON_COLOR}"
  local dir src name dest count=0
  while IFS= read -r dir; do
    for src in "${dir}"/folder-"${ICON_COLOR}"*.svg; do
      [[ -e "${src}" ]] || continue
      name="$(basename "${src}")"
      dest="${dir}/${name/folder-${ICON_COLOR}/folder}"
      ln -sf "${name}" "${dest}"
      count=$((count + 1))
    done
  done < <(find "${base}" -type d -name places)

  if [[ "${count}" -eq 0 ]]; then
    warn "no ${ICON_COLOR} folder variants found in ${ICON_THEME}"
  else
    log "Relinked ${count} folder icons"
  fi

  gtk-update-icon-cache -f "${base}" >/dev/null 2>&1 || true
}

install_menu_icon() {
  local repo_root="${1:-}"
  local icons_src="${repo_root}/assets/icons"
  local dest="/usr/share/icons/duckybox"

  if [[ ! -d "${icons_src}" ]]; then
    warn "menu icons missing at ${icons_src}"
    return 0
  fi

  log "Installing Duckybox menu icons"
  mkdir -p "${dest}"
  cp -f "${icons_src}"/duckybox-*.png "${dest}/"
  cp -f "${icons_src}/duckybox.png" "${dest}/duckybox.png"

  # Also register in the hicolor theme so menus can resolve "duckybox" by name.
  local size
  for size in 16 22 24 32 48 64 128 256; do
    if [[ -f "${icons_src}/duckybox-${size}.png" ]]; then
      mkdir -p "/usr/share/icons/hicolor/${size}x${size}/apps"
      cp -f "${icons_src}/duckybox-${size}.png" \
        "/usr/share/icons/hicolor/${size}x${size}/apps/duckybox.png"
    fi
  done
  gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
}

main() {
  local repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  install_build_deps
  build_gtk_theme || warn "GTK theme build skipped; CSS overrides still apply"
  recolor_icon_folders
  install_menu_icon "${repo_root}"
  log "GTK theme step finished"
}

main "$@"
