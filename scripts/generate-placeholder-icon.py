#!/usr/bin/env python3
"""Generate the placeholder app icon (1024x1024 RGB PNG, no alpha).

Draws a deep-blue background with a lighter rounded square and a "G" built
from rectangles. Uses only the Python standard library.

Usage: python3 scripts/generate-placeholder-icon.py [output.png]
"""

import struct
import sys
import zlib

SIZE = 1024
BACKGROUND = (16, 42, 92)
TILE = (58, 110, 200)
GLYPH = (240, 244, 252)
DEFAULT_OUTPUT = "GIM/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def in_rounded_square(x, y, left, top, right, bottom, radius):
    if not (left <= x < right and top <= y < bottom):
        return False
    cx = min(max(x, left + radius), right - 1 - radius)
    cy = min(max(y, top + radius), bottom - 1 - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius**2


# "G" as rectangles (left, top, right, bottom) inside a 1024 canvas.
GLYPH_RECTS = [
    (312, 312, 712, 392),  # top bar
    (312, 312, 392, 712),  # left bar
    (312, 632, 712, 712),  # bottom bar
    (632, 512, 712, 712),  # right lower bar
    (512, 512, 712, 592),  # inner spur
]


def pixel(x, y):
    for left, top, right, bottom in GLYPH_RECTS:
        if left <= x < right and top <= y < bottom:
            return GLYPH
    if in_rounded_square(x, y, 192, 192, 832, 832, 120):
        return TILE
    return BACKGROUND


def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def main():
    output = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUTPUT
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # filter type: none
        for x in range(SIZE):
            raw.extend(pixel(x, y))
    # width, height, bit depth 8, color type 2 (RGB), compression, filter, interlace
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    with open(output, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    main()
