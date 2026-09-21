#!/usr/bin/env bash
# Duckybox — regenerate every branded asset from assets/brand/duckybox-logo.png
#
# Produces the duck ASCII art, Plymouth splash images, wallpapers at three
# resolutions, GRUB backgrounds, the LightDM greeter background and the menu
# icon set. Requires ImageMagick; everything else is stdlib Python.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BRAND_DIR="${REPO_ROOT}/assets/brand"
LOGO="${BRAND_DIR}/duckybox-logo.png"
MARK="${BRAND_DIR}/duckybox-mark.png"

# Duckybox palette (derived from the logo violet #4B0E8F)
BRAND='#4B0E8F'
ACCENT='#7C3AED'
ACCENT_HI='#A78BFA'
BG='#12071F'
BG_ALT='#2A0F52'
FG='#EDE9FE'
DIM='#2E1A47'

log() { printf '[duckybox-brand] %s\n' "$*"; }

if command -v magick >/dev/null 2>&1; then
  im() { magick "$@"; }
elif command -v convert >/dev/null 2>&1; then
  im() { convert "$@"; }
else
  echo "ERROR: ImageMagick (magick/convert) is required" >&2
  exit 1
fi

if [[ ! -f "${LOGO}" ]]; then
  echo "ERROR: missing ${LOGO}" >&2
  exit 1
fi

find_font() {
  local candidate
  for candidate in \
    /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf \
    /usr/share/fonts/TTF/DejaVuSans-Bold.ttf \
    /usr/share/fonts/dejavu/DejaVuSans-Bold.ttf \
    /System/Library/Fonts/Supplemental/Arial\ Bold.ttf \
    /Library/Fonts/Arial\ Bold.ttf \
    /System/Library/Fonts/Helvetica.ttc
  do
    if [[ -f "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

FONT_ARGS=()
if FONT_PATH="$(find_font)"; then
  FONT_ARGS=(-font "${FONT_PATH}")
  log "Using font ${FONT_PATH}"
else
  log "No bundled font found; relying on ImageMagick default"
fi

# ---------------------------------------------------------------------------
# 1. Transparent, trimmed duck mark
# ---------------------------------------------------------------------------

make_mark() {
  log "Building transparent mark"
  im "${LOGO}" -fuzz 18% -transparent "${BRAND}" -trim +repage "${MARK}"
}

# ---------------------------------------------------------------------------
# 2. Duck ASCII (braille) + terminal banner
# ---------------------------------------------------------------------------

make_ascii() {
  log "Converting mark to braille art"
  im "${MARK}" -background black -alpha remove -alpha off \
    -colorspace gray -resize 96x -threshold 55% -compress none pbm:- \
    | python3 "${SCRIPT_DIR}/lib/pbm2braille.py" --invert \
    > "${REPO_ROOT}/assets/duck.txt"

  log "Composing terminal banner"
  {
    cat <<'WORDMARK'
██████╗ ██╗   ██╗ ██████╗██╗  ██╗██╗   ██╗██████╗  ██████╗ ██╗  ██╗
██╔══██╗██║   ██║██╔════╝██║ ██╔╝╚██╗ ██╔╝██╔══██╗██╔═══██╗╚██╗██╔╝
██║  ██║██║   ██║██║     █████╔╝  ╚████╔╝ ██████╔╝██║   ██║ ╚███╔╝
██║  ██║██║   ██║██║     ██╔═██╗   ╚██╔╝  ██╔══██╗██║   ██║ ██╔██╗
██████╔╝╚██████╔╝╚██████╗██║  ██╗   ██║   ██████╔╝╚██████╔╝██╔╝ ██╗
╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═════╝  ╚═════╝ ╚═╝  ╚═╝
WORDMARK
    echo
    cat "${REPO_ROOT}/assets/duck.txt"
  } > "${REPO_ROOT}/assets/duckybox-banner.txt"
}

# ---------------------------------------------------------------------------
# 3. Plymouth assets
# ---------------------------------------------------------------------------

make_plymouth() {
  local out="${REPO_ROOT}/assets/plymouth"
  mkdir -p "${out}"
  log "Rendering Plymouth logo"

  # White duck over transparency, wordmark underneath in light violet.
  im "${MARK}" -resize 320x320 -background none -gravity center -extent 560x360 \
    "${out}/duck-tmp.png"
  im -size 560x120 xc:none "${FONT_ARGS[@]}" -pointsize 76 \
    -fill "${FG}" -gravity center -annotate +0+0 'DUCKYBOX' \
    "${out}/word-tmp.png"
  im "${out}/duck-tmp.png" "${out}/word-tmp.png" -background none -append \
    -trim +repage -bordercolor none -border 24 "${out}/logo.png"
  rm -f "${out}/duck-tmp.png" "${out}/word-tmp.png"

  im -size 420x6 "xc:${DIM}" "${out}/progress_bg.png"
  im -size 420x6 "xc:${ACCENT}" "${out}/progress_fg.png"
  im -size 28x28 xc:none -fill "${ACCENT_HI}" \
    -draw 'circle 14,14 14,4' "${out}/bullet.png"
}

# ---------------------------------------------------------------------------
# 4. Wallpapers / GRUB / greeter
# ---------------------------------------------------------------------------

compose_scene() {
  # compose_scene <width> <height> <output> [wordmark:0|1] [offset_pct_of_height]
  # offset_pct shifts the duck up from centre, leaving room for GRUB menu
  # entries or the login prompt.
  local w="$1" h="$2" dest="$3" wordmark="${4:-1}" offset_pct="${5:-5}"
  local duck_h=$(( h * 26 / 100 ))
  local point=$(( h * 5 / 100 ))
  local offset=$(( h * offset_pct / 100 ))

  im -size "${w}x${h}" \
    "radial-gradient:${BG_ALT}-${BG}" \
    -define distort:viewport="${w}x${h}" \
    "${dest}.base.png"

  im "${MARK}" -resize "x${duck_h}" "${dest}.duck.png"

  im "${dest}.base.png" "${dest}.duck.png" \
    -gravity center -geometry "+0-${offset}" -composite \
    "${dest}.stage.png"

  if [[ "${wordmark}" -eq 1 ]]; then
    im "${dest}.stage.png" "${FONT_ARGS[@]}" -pointsize "${point}" \
      -fill "${FG}" -gravity center \
      -annotate +0+$(( duck_h / 2 + h / 18 - offset )) 'DUCKYBOX' \
      "${dest}.stage2.png"
    mv "${dest}.stage2.png" "${dest}.stage.png"
  fi

  # Thin brand bar along the bottom edge. Force 8-bit: GRUB's PNG reader is
  # unreliable with the 16-bit output that gradients produce.
  im "${dest}.stage.png" -fill "${ACCENT}" \
    -draw "rectangle 0,$(( h - h / 180 - 2 )) ${w},${h}" \
    -depth 8 -strip "${dest}"

  rm -f "${dest}.base.png" "${dest}.duck.png" "${dest}.stage.png"
}

# Hand-made wallpaper artwork, if the user dropped one in assets/brand.
find_wallpaper_art() {
  local candidate
  for candidate in "${BRAND_DIR}/duckybox-wallpaper.jpg" "${BRAND_DIR}/duckybox-wallpaper.png"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

# Scale artwork to a target resolution, cropping to fill if the aspect ratio
# differs, then counter the softness that resampling introduces. Output format
# follows the destination extension; JPEG keeps these files ~10x smaller than
# PNG, which would otherwise losslessly preserve the source's JPEG artifacts.
scale_artwork() {
  local src="$1" w="$2" h="$3" dest="$4"
  im "${src}" \
    -filter Lanczos \
    -resize "${w}x${h}^" \
    -gravity center -extent "${w}x${h}" \
    -unsharp 0x1+0.6+0.02 \
    -quality 92 \
    -strip "${dest}"
}

make_wallpapers() {
  local out="${REPO_ROOT}/assets/wallpapers"
  mkdir -p "${out}"

  # Hand-made artwork wins over the generated gradient scene.
  local art=""
  art="$(find_wallpaper_art || true)"

  local res
  for res in 1920x1080 2560x1440 3840x2160; do
    if [[ -n "${art}" ]]; then
      log "Scaling wallpaper artwork to ${res}"
      scale_artwork "${art}" "${res%x*}" "${res#*x}" "${out}/duckybox-${res}.jpg"
      # Drop a stale PNG from a previous run so only one file per resolution
      # exists and the picker cannot choose the old one.
      rm -f "${out}/duckybox-${res}.png"
    else
      log "Rendering wallpaper ${res}"
      compose_scene "${res%x*}" "${res#*x}" "${out}/duckybox-${res}.png"
      rm -f "${out}/duckybox-${res}.jpg"
    fi
  done
}

make_grub() {
  local out="${REPO_ROOT}/assets/grub"
  mkdir -p "${out}"
  log "Rendering GRUB backgrounds"
  # No wordmark and a high duck: the menu occupies the lower half.
  compose_scene 1920 1080 "${out}/background-16x9.png" 0 20
  compose_scene 1440 1080 "${out}/background-4x3.png" 0 20
  # Menu chrome pieces for the GRUB theme
  im -size 4x4 "xc:${ACCENT}" "${out}/select-c.png"
  im -size 2x28 "xc:${ACCENT_HI}" "${out}/slider-c.png"
  im -size 2x28 "xc:${DIM}" "${out}/slider-bg.png"
}

make_greeter() {
  local out="${REPO_ROOT}/assets/greeter"
  mkdir -p "${out}"
  local art=""
  art="$(find_wallpaper_art || true)"

  if [[ -n "${art}" ]]; then
    # Same artwork as the desktop; the login prompt sits at 76%, clear of the
    # duck and its glow (see configs/lightdm/lightdm-gtk-greeter.conf).
    log "Scaling wallpaper artwork for the greeter"
    scale_artwork "${art}" 3840 2160 "${out}/duckybox-login.png"
  else
    log "Rendering greeter background"
    # Branding in the upper third so the login prompt at 70% stays clear.
    compose_scene 3840 2160 "${out}/duckybox-login.png" 1 22
  fi

  im "${out}/duckybox-login.png" -quality 92 "${out}/duckybox-login.jpg"
  rm -f "${out}/duckybox-login.png"
}

make_icons() {
  local out="${REPO_ROOT}/assets/icons"
  mkdir -p "${out}"
  log "Rendering menu icon set"
  # The mark is trimmed to its content, so scaling it straight to the box makes
  # the duck touch every edge and read as clipped. Panels and menus add no
  # padding of their own, so leave the margin here.
  local size inner
  for size in 16 22 24 32 48 64 128 256; do
    inner=$(( size * 84 / 100 ))
    (( inner > 0 )) || inner="${size}"
    im "${MARK}" -background none -resize "${inner}x${inner}" \
      -gravity center -extent "${size}x${size}" \
      "${out}/duckybox-${size}.png"
  done
  cp -f "${out}/duckybox-256.png" "${out}/duckybox.png"
}

main() {
  make_mark
  make_ascii
  make_plymouth
  make_wallpapers
  make_grub
  make_greeter
  make_icons
  log "Brand assets regenerated"
}

main "$@"
