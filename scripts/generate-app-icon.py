#!/usr/bin/env python3
"""Generate the iOS app icon (1024x1024 RGB PNG, full-bleed, no alpha) from gim-static.

iOS needs a full-bleed square without transparency or rounded corners, which gim-static's app-icon.png (rounded frame)
is not. This composes gim-static's white glyph (svg/icon-white.svg) on the app icon's blue-violet background, a
vertical gradient sampled from png/app-icon.png (#4040E0 at the top to #1C1C88 at the bottom), with the glyph at the
size and position it has in app-icon.svg (640 px, centred). Uses only the Python standard library.

Usage: python3 scripts/generate-app-icon.py [path/to/icon-white.svg] [output.png]
"""

import re
import struct
import sys
import zlib

SIZE = 1024
TOP = (0x40, 0x40, 0xE0)
BOTTOM = (0x1C, 0x1C, 0x88)
GLYPH = (255, 255, 255)
GLYPH_SIZE = 640
SUBSAMPLES = 8
DEFAULT_SOURCE = "../gim-static/public/svg/icon-white.svg"
DEFAULT_OUTPUT = "GIM/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def glyph_path(svg):
    """The `d` attribute and the viewBox size of the glyph SVG."""
    view_box = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg)
    path = re.search(r'<path d="([^"]+)"', svg)
    return path.group(1), float(view_box.group(1))


def polygons(d, scale, offset):
    """Flattens an absolute M/L/H/V/C/Z path into closed polygons in icon coordinates."""
    tokens = re.findall(r"[MLHVCZ]|-?[\d.]+(?:e-?\d+)?", d)
    result, current, x, y, i, command = [], [], 0.0, 0.0, 0, None

    def point(px, py):
        current.append((px * scale + offset, py * scale + offset))

    def number():
        nonlocal i
        i += 1
        return float(tokens[i - 1])

    while i < len(tokens):
        if tokens[i].isalpha():
            command = tokens[i]
            i += 1
        if command == "M":
            if current:
                result.append(current)
            current = []
            x, y = number(), number()
            point(x, y)
            command = "L"
        elif command == "L":
            x, y = number(), number()
            point(x, y)
        elif command == "H":
            x = number()
            point(x, y)
        elif command == "V":
            y = number()
            point(x, y)
        elif command == "C":
            x1, y1, x2, y2, x3, y3 = (number() for _ in range(6))
            for step in range(1, 33):
                t = step / 32
                u = 1 - t
                point(
                    u**3 * x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t**3 * x3,
                    u**3 * y + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t**3 * y3,
                )
            x, y = x3, y3
        elif command == "Z":
            if current:
                result.append(current)
            current = []
        else:
            raise ValueError(f"unsupported path command {command}")
    if current:
        result.append(current)
    return result


def coverage(shapes):
    """Per-pixel coverage (0..1) of the shapes, nonzero fill, SUBSAMPLES scanlines per row."""
    edges = []
    for shape in shapes:
        for (x0, y0), (x1, y1) in zip(shape, shape[1:] + shape[:1]):
            if y0 != y1:
                edges.append((x0, y0, x1, y1))
    cover = [[0.0] * SIZE for _ in range(SIZE)]
    weight = 1 / SUBSAMPLES
    for row in range(SIZE):
        line = cover[row]
        for sub in range(SUBSAMPLES):
            sy = row + (sub + 0.5) / SUBSAMPLES
            crossings = []
            for x0, y0, x1, y1 in edges:
                if (y0 <= sy < y1) or (y1 <= sy < y0):
                    crossings.append((x0 + (sy - y0) * (x1 - x0) / (y1 - y0), 1 if y1 > y0 else -1))
            crossings.sort()
            winding = 0
            for (xa, direction), (xb, _) in zip(crossings, crossings[1:] + [(0, 0)]):
                winding += direction
                if winding == 0 or xb <= xa:
                    continue
                left, right = max(xa, 0.0), min(xb, float(SIZE))
                first, last = int(left), min(int(right), SIZE - 1)
                if first == last:
                    line[first] += (right - left) * weight
                    continue
                line[first] += (first + 1 - left) * weight
                for px in range(first + 1, last):
                    line[px] += weight
                line[last] += (right - last) * weight
    return cover


def write_png(path, pixels):
    raw = b"".join(b"\x00" + bytes(row) for row in pixels)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n")
        out.write(chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)))
        out.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        out.write(chunk(b"IEND", b""))


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SOURCE
    output = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUTPUT
    with open(source, encoding="utf-8") as svg:
        d, view_box = glyph_path(svg.read())
    cover = coverage(polygons(d, GLYPH_SIZE / view_box, (SIZE - GLYPH_SIZE) / 2))
    pixels = []
    for y in range(SIZE):
        t = (y + 0.5) / SIZE
        background = [TOP[c] + (BOTTOM[c] - TOP[c]) * t for c in range(3)]
        row = bytearray()
        for x in range(SIZE):
            alpha = min(cover[y][x], 1.0)
            row.extend(round(background[c] + (GLYPH[c] - background[c]) * alpha) for c in range(3))
        pixels.append(row)
    write_png(output, pixels)


if __name__ == "__main__":
    main()
