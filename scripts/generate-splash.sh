#!/usr/bin/env bash
# Generate Turfbox Plymouth logo + progress bar PNGs from ASCII assets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${1:-${REPO_ROOT}/assets/plymouth}"
HORSE="${REPO_ROOT}/assets/horse.txt"

mkdir -p "${OUT_DIR}"

BG='#0D1117'
FG='#FF6A00'
FG_DIM='#FF8C1A'

text_file="$(mktemp)"
{
  printf 'TURFBOX\n\n'
  cat "${HORSE}"
} > "${text_file}"

cleanup() { rm -f "${text_file}"; }
trap cleanup EXIT

generate_with_imagemagick() {
  local bin="$1"
  local font_args=()
  local font_path=""
  for cand in \
    /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf \
    /usr/share/fonts/TTF/DejaVuSansMono.ttf \
    /System/Library/Fonts/Menlo.ttc \
    /Library/Fonts/Andale Mono.ttf
  do
    if [[ -f "${cand}" ]]; then
      font_path="${cand}"
      break
    fi
  done
  if [[ -n "${font_path}" ]]; then
    font_args=(-font "${font_path}")
  fi

  if [[ "${bin}" == "magick" ]]; then
    magick -background "${BG}" -fill "${FG}" \
      "${font_args[@]}" -pointsize 16 \
      "label:@${text_file}" \
      -bordercolor "${BG}" -border 40 \
      "${OUT_DIR}/logo.png"
    magick -size 420x8 "xc:#3D2A1A" "${OUT_DIR}/progress_bg.png"
    magick -size 420x8 "xc:${FG}" "${OUT_DIR}/progress_fg.png"
    magick -size 1920x1080 "xc:${BG}" \
      -fill "${FG_DIM}" -draw "rectangle 0,1060 1920,1080" \
      "${OUT_DIR}/turfbox-wallpaper.png"
  else
    convert -background "${BG}" -fill "${FG}" \
      "${font_args[@]}" -pointsize 16 \
      "label:@${text_file}" \
      -bordercolor "${BG}" -border 40 \
      "${OUT_DIR}/logo.png"
    convert -size 420x8 "xc:#3D2A1A" "${OUT_DIR}/progress_bg.png"
    convert -size 420x8 "xc:${FG}" "${OUT_DIR}/progress_fg.png"
    convert -size 1920x1080 "xc:${BG}" \
      -fill "${FG_DIM}" -draw "rectangle 0,1060 1920,1080" \
      "${OUT_DIR}/turfbox-wallpaper.png"
  fi
}

generate_with_python() {
  TURFBOX_OUT="${OUT_DIR}" TURFBOX_TEXT="${text_file}" python3 - <<'PY'
import os
from pathlib import Path

out = Path(os.environ["TURFBOX_OUT"])
text = Path(os.environ["TURFBOX_TEXT"]).read_text(encoding="utf-8")
bg = (13, 17, 23)
fg = (255, 106, 0)
accent = (255, 140, 26)

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    # Minimal PNG writer (no Pillow)
    import struct, zlib

    def write_png(path, w, h, rgb_rows):
        def chunk(tag, data):
            return struct.pack(">I", len(data)) + tag + data + struct.pack(
                ">I", zlib.crc32(tag + data) & 0xFFFFFFFF
            )

        raw = b"".join(b"\x00" + row for row in rgb_rows)
        ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
        data = (
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b"")
        )
        path.write_bytes(data)

    out.mkdir(parents=True, exist_ok=True)
    # Solid orange logo placeholder 640x360
    row = bytes([255, 106, 0]) * 640
    write_png(out / "logo.png", 640, 360, [row] * 360)
    row_bg = bytes([61, 42, 26]) * 420
    write_png(out / "progress_bg.png", 420, 8, [row_bg] * 8)
    row_fg = bytes([255, 106, 0]) * 420
    write_png(out / "progress_fg.png", 420, 8, [row_fg] * 8)
    row_w = bytes([13, 17, 23]) * 64
    write_png(out / "turfbox-wallpaper.png", 64, 64, [row_w] * 64)
    print("placeholders (no Pillow)")
    raise SystemExit(0)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 16)
except Exception:
    try:
        font = ImageFont.truetype("DejaVuSansMono.ttf", 16)
    except Exception:
        font = ImageFont.load_default()

lines = text.splitlines()
tmp = Image.new("RGB", (10, 10), bg)
dr = ImageDraw.Draw(tmp)
max_w, total_h, sizes = 0, 0, []
for line in lines:
    bbox = dr.textbbox((0, 0), line if line else " ", font=font)
    w, h = bbox[2] - bbox[0], max(bbox[3] - bbox[1], 12)
    sizes.append((w, h))
    max_w = max(max_w, w)
    total_h += h + 2

pad = 40
img = Image.new("RGB", (max(max_w + pad * 2, 200), total_h + pad * 2), bg)
draw = ImageDraw.Draw(img)
y = pad
for line, (w, h) in zip(lines, sizes):
    x = pad + (max_w - w) // 2
    draw.text((x, y), line, fill=fg, font=font)
    y += h + 2

out.mkdir(parents=True, exist_ok=True)
img.save(out / "logo.png")
Image.new("RGB", (420, 8), (61, 42, 26)).save(out / "progress_bg.png")
Image.new("RGB", (420, 8), fg).save(out / "progress_fg.png")
wall = Image.new("RGB", (1920, 1080), bg)
ImageDraw.Draw(wall).rectangle([0, 1060, 1920, 1080], fill=accent)
wall.save(out / "turfbox-wallpaper.png")
print("ok (Pillow)")
PY
}

ok=0
if command -v magick >/dev/null 2>&1; then
  if generate_with_imagemagick magick; then
    ok=1
  fi
elif command -v convert >/dev/null 2>&1; then
  if generate_with_imagemagick convert; then
    ok=1
  fi
fi

if [[ "${ok}" -ne 1 ]]; then
  echo "ImageMagick failed or missing; trying Python…" >&2
  generate_with_python
fi

if [[ ! -f "${OUT_DIR}/logo.png" ]]; then
  echo "ERROR: failed to generate ${OUT_DIR}/logo.png" >&2
  exit 1
fi

echo "Generated splash assets in ${OUT_DIR}"
ls -la "${OUT_DIR}"
