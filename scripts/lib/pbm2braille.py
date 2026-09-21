#!/usr/bin/env python3
"""Convert an ASCII PBM (P1) bitmap on stdin into Unicode braille art on stdout.

Each braille glyph packs a 2x4 pixel cell, so the output is 1/2 the input width
and 1/4 its height. Set pixels become raised dots.
"""

import sys

# Braille dot bit positions, indexed as OFFSETS[x][y] within a 2x4 cell.
OFFSETS = ((0x01, 0x02, 0x04, 0x40), (0x08, 0x10, 0x20, 0x80))


def read_pbm(stream):
    tokens = []
    magic = None
    for raw in stream:
        line = raw.split("#", 1)[0].split()
        if not line:
            continue
        if magic is None:
            magic = line[0]
            if magic != "P1":
                raise SystemExit(f"expected P1 (ASCII PBM), got {magic}")
            tokens.extend(line[1:])
            continue
        tokens.extend(line)

    if len(tokens) < 2:
        raise SystemExit("truncated PBM header")

    width, height = int(tokens[0]), int(tokens[1])
    bits = "".join(tokens[2:])
    if len(bits) < width * height:
        bits = bits.ljust(width * height, "0")
    rows = [bits[y * width:(y + 1) * width] for y in range(height)]
    return width, height, rows


def to_braille(width, height, rows, invert):
    lines = []
    for top in range(0, height, 4):
        line = []
        for left in range(0, width, 2):
            mask = 0
            for dx in range(2):
                for dy in range(4):
                    x, y = left + dx, top + dy
                    if x >= width or y >= height:
                        continue
                    on = rows[y][x] == "1"
                    if invert:
                        on = not on
                    if on:
                        mask |= OFFSETS[dx][dy]
            line.append(chr(0x2800 + mask))
        lines.append("".join(line).rstrip() or "\u2800")
    while lines and lines[-1] == "\u2800":
        lines.pop()
    return lines


def main():
    invert = "--invert" in sys.argv[1:]
    width, height, rows = read_pbm(sys.stdin)
    for line in to_braille(width, height, rows, invert):
        print(line)


if __name__ == "__main__":
    main()
