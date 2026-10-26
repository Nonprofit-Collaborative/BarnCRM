#!/usr/bin/env python3
"""Makes the BarnCRM app logo variants from the master barn logo.

    python3 scripts/brand/make-logos.py [--out DIR] [--sheet FILE]

The master is Core's ContentAsset `BarnCRM_Logo` (a 256 x 256 RGBA PNG, ADR-0102), which the
BarnCRM and BarnCRM Console apps use as it is. Each variant is the same barn with a round badge
in the bottom right corner, so the family reads as one product and the badge says which app:

  BarnCRM_Admin_Logo       (Core)        navy badge, white gear: BarnCRM Admin, BarnCRM Admin Console
  Fundraising_Logo         (giving)      red badge, white heart: Fundraising
  BarnCRM_Volunteers_Logo  (volunteers)  green badge, white person: BarnCRM Volunteers

Each package ships its own asset, because an app names a ContentAsset by its API name and a
module may not depend on Core's asset being addressable once the packages are namespaced.

Writes `<package>/main/default/contentassets/<Name>.asset` and its `.asset-meta.xml` under
`--out` (default: the repository root), and with `--sheet` a contact sheet PNG showing every
logo at 256, 64 and 32 pixels. Standard library only (zlib and struct), so it runs anywhere
Python 3 does; the drawing is supersampled 4 x 4 so edges stay smooth.
"""

import argparse
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MASTER = os.path.join(ROOT, "packages/core/main/default/contentassets/BarnCRM_Logo.asset")

BADGE_CENTER = (183.0, 183.0)
BADGE_RADIUS = 62.0
RING = 9.0  # white ring that separates the badge from the barn
SAMPLES = 4

VARIANTS = [
    ("core", "BarnCRM_Admin_Logo", (0x03, 0x2D, 0x60), "gear"),
    ("giving", "Fundraising_Logo", (0xC2, 0x39, 0x34), "heart"),
    ("volunteers", "BarnCRM_Volunteers_Logo", (0x2E, 0x84, 0x4A), "person"),
]

META = """<?xml version="1.0" encoding="UTF-8" ?>
<ContentAsset xmlns="http://soap.sforce.com/2006/04/metadata">
  <isVisibleByExternalUsers>false</isVisibleByExternalUsers>
  <language>en_US</language>
  <masterLabel>{name}</masterLabel>
  <relationships>
    <organization>
      <access>VIEWER</access>
    </organization>
  </relationships>
  <versions>
    <version>
      <number>1</number>
      <pathOnClient>{name}.png</pathOnClient>
    </version>
  </versions>
</ContentAsset>
"""


def read_png(path):
    """Width, height and rows of RGBA tuples from an 8-bit RGBA, non-interlaced PNG."""
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")
    pos, idat, width, height = 8, b"", 0, 0
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        body = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if (depth, color, interlace) != (8, 6, 0):
                raise SystemExit(f"{path}: expected 8-bit RGBA, not interlaced")
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = width * 4
    rows, prev = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1 : start + 1 + stride])
        for i in range(stride):
            left = line[i - 4] if i >= 4 else 0
            up = prev[i]
            corner = prev[i - 4] if i >= 4 else 0
            if kind == 1:
                line[i] = (line[i] + left) & 255
            elif kind == 2:
                line[i] = (line[i] + up) & 255
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif kind == 4:
                guess = left + up - corner
                pa, pb, pc = abs(guess - left), abs(guess - up), abs(guess - corner)
                pick = left if pa <= pb and pa <= pc else (up if pb <= pc else corner)
                line[i] = (line[i] + pick) & 255
        rows.append([tuple(line[x * 4 : x * 4 + 4]) for x in range(width)])
        prev = line
    return width, height, rows


def png_bytes(rows):
    """An RGBA PNG of the rows, unfiltered and compressed at level 9."""
    height, width = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in rows)

    def chunk(kind, body):
        crc = zlib.crc32(kind + body) & 0xFFFFFFFF
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc)

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def in_gear(x, y):
    r, angle = math.hypot(x, y), math.atan2(y, x)
    if r < 0.18:
        return False
    teeth = (math.cos(angle * 8) + 1) / 2  # 8 teeth
    return r < 0.48 or (r < 0.66 and teeth > 0.45)


def in_heart(x, y):
    x, y = x / 0.46, -(y + 0.06) / 0.46
    return (x * x + y * y - 1) ** 3 - x * x * y**3 <= 0


def in_person(x, y):
    head = math.hypot(x, y + 0.30) < 0.24
    shoulders = y > 0.04 and y < 0.58 and (x / 0.50) ** 2 + ((y - 0.58) / 0.54) ** 2 < 1
    return head or shoulders


GLYPHS = {"gear": in_gear, "heart": in_heart, "person": in_person}


def badge_pixel(px, py, color, glyph):
    """The badge's RGBA over one pixel, from SAMPLES x SAMPLES samples; None when outside."""
    cx, cy = BADGE_CENTER
    outer = BADGE_RADIUS + RING
    hits = [0.0, 0.0, 0.0, 0.0]
    covered = 0
    for sy in range(SAMPLES):
        for sx in range(SAMPLES):
            x = px + (sx + 0.5) / SAMPLES - cx
            y = py + (sy + 0.5) / SAMPLES - cy
            r = math.hypot(x, y)
            if r >= outer:
                continue
            covered += 1
            if r >= BADGE_RADIUS or GLYPHS[glyph](x / BADGE_RADIUS, y / BADGE_RADIUS):
                rgb = (255, 255, 255)
            else:
                rgb = color
            for i in range(3):
                hits[i] += rgb[i]
    if not covered:
        return None
    total = SAMPLES * SAMPLES
    return tuple(h / covered for h in hits[:3]) + (covered / total,)


def with_badge(rows, color, glyph):
    out = [list(row) for row in rows]
    cx, cy = BADGE_CENTER
    reach = int(BADGE_RADIUS + RING) + 1
    for py in range(max(0, int(cy) - reach), min(len(rows), int(cy) + reach + 1)):
        for px in range(max(0, int(cx) - reach), min(len(rows[0]), int(cx) + reach + 1)):
            badge = badge_pixel(px, py, color, glyph)
            if badge is None:
                continue
            r, g, b, a = out[py][px]
            alpha = badge[3]
            base = a / 255.0
            out_a = alpha + base * (1 - alpha)
            mixed = [
                (badge[i] * alpha + (r, g, b)[i] * base * (1 - alpha)) / out_a for i in range(3)
            ]
            out[py][px] = tuple(int(round(v)) for v in mixed) + (int(round(out_a * 255)),)
    return out


def shrink(rows, size):
    """A box-filtered copy at size x size, alpha weighted, as the header shows it."""
    step = len(rows) // size
    out = []
    for y in range(size):
        line = []
        for x in range(size):
            acc, alpha = [0.0, 0.0, 0.0], 0.0
            for yy in range(y * step, (y + 1) * step):
                for xx in range(x * step, (x + 1) * step):
                    r, g, b, a = rows[yy][xx]
                    alpha += a
                    for i, v in enumerate((r, g, b)):
                        acc[i] += v * a
            n = step * step
            rgb = [int(round(v / alpha)) if alpha else 0 for v in acc]
            line.append(tuple(rgb) + (int(round(alpha / n)),))
        out.append(line)
    return out


def contact_sheet(logos):
    """Every logo at 256, 64 and 32 on white, one row each, 16 px apart."""
    pad, sizes = 16, (256, 64, 32)
    width = pad + sum(s + pad for s in sizes)
    height = pad + len(logos) * (256 + pad)
    sheet = [[(255, 255, 255, 255)] * width for _ in range(height)]
    for row, rows in enumerate(logos):
        x0, y0 = pad, pad + row * (256 + pad)
        for size in sizes:
            img = rows if size == 256 else shrink(rows, size)
            for y, line in enumerate(img):
                for x, (r, g, b, a) in enumerate(line):
                    k = a / 255.0
                    sheet[y0 + y][x0 + x] = tuple(
                        int(round(v * k + 255 * (1 - k))) for v in (r, g, b)
                    ) + (255,)
            x0 += size + pad
    return sheet


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", default=ROOT, help="where the packages/ tree is written")
    parser.add_argument("--sheet", help="also write a contact sheet PNG here")
    args = parser.parse_args()

    _, _, master = read_png(MASTER)
    made = [master]
    for package, name, color, glyph in VARIANTS:
        rows = with_badge(master, color, glyph)
        made.append(rows)
        folder = os.path.join(args.out, "packages", package, "main/default/contentassets")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, name + ".asset"), "wb") as handle:
            handle.write(png_bytes(rows))
        with open(os.path.join(folder, name + ".asset-meta.xml"), "w", encoding="utf-8") as handle:
            handle.write(META.format(name=name))
        print(f"{package}: {name}")
    if args.sheet:
        with open(args.sheet, "wb") as handle:
            handle.write(png_bytes(contact_sheet(made)))
        print(f"contact sheet: {args.sheet}")


if __name__ == "__main__":
    main()
