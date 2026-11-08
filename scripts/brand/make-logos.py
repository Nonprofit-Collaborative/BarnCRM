#!/usr/bin/env python3
"""Makes the BarnCRM app logo variants from the master barn logo.

    python3 scripts/brand/make-logos.py [--out DIR] [--sheet FILE]

The master is Core's ContentAsset `BarnCRM_Logo` (a 256 x 256 RGBA PNG, ADR-0102), which the
BarnCRM and BarnCRM Console apps use as it is. Each variant is the same barn with a round badge
in the bottom right corner, so the family reads as one product and the badge says which app.
Badge glyphs are white; every badge color is at least 4.5:1 against white, and none is a status
color (no error red, warning orange or yellow), so a launcher tile never reads as an alert.

  Asset                     Package      Badge             Color    App
  BarnCRM_Admin_Logo        core         gear              #032D60  BarnCRM Admin, Admin Console
  BarnCRM_Fundraising_Logo  giving       heart             #A3175F  BarnCRM Fundraising
  BarnCRM_Volunteers_Logo   volunteers   person            #2E844A  BarnCRM Volunteers
  BarnCRM_Programs_Logo     programs     sprout            #7526A8  BarnCRM Programs
  BarnCRM_Funders_Logo      funders      award ribbon      #7A5300  BarnCRM Funders
  BarnCRM_Logic_Models_Logo logicmodels  flow arrows       #3B44B5  BarnCRM Logic Models
  BarnCRM_Forms_Logo        forms        form page         #0B5C7A  BarnCRM Forms
  BarnCRM_Events_Logo       events       calendar          #0B6B6B  BarnCRM Events

Fundraising was red (#C23934) until 2026-11-04 (owner decision: red means error in the UI, the
reason D-58 declined red for the brand). The asset was renamed from Fundraising_Logo then:
redeploying a ContentAsset under its old name keeps the org's existing image, so a changed
image needs a new asset name to reach orgs that already have the old one.

Each package ships its own asset, because an app names a ContentAsset by its API name and a
module may not depend on Core's asset being addressable once the packages are namespaced.

Writes `<package>/main/default/contentassets/<Name>.asset` and its `.asset-meta.xml` under
`--out` (default: the repository root), a copy of each as `docs/brand/barncrm-<slug>-logo.png`,
and with `--sheet` a contact sheet PNG showing every logo at 256, 64 and 32 pixels. Standard
library only (zlib and struct), so it runs anywhere Python 3 does; the drawing is supersampled
4 x 4 so edges stay smooth. The output is deterministic: the same master gives the same bytes.
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

# (package, asset name, docs/brand slug, badge color, glyph)
VARIANTS = [
    ("core", "BarnCRM_Admin_Logo", "admin", (0x03, 0x2D, 0x60), "gear"),
    ("giving", "BarnCRM_Fundraising_Logo", "giving", (0xA3, 0x17, 0x5F), "heart"),
    ("volunteers", "BarnCRM_Volunteers_Logo", "volunteers", (0x2E, 0x84, 0x4A), "person"),
    ("programs", "BarnCRM_Programs_Logo", "programs", (0x75, 0x26, 0xA8), "sprout"),
    ("funders", "BarnCRM_Funders_Logo", "funders", (0x7A, 0x53, 0x00), "ribbon"),
    ("logicmodels", "BarnCRM_Logic_Models_Logo", "logic-models", (0x3B, 0x44, 0xB5), "flow"),
    ("forms", "BarnCRM_Forms_Logo", "forms", (0x0B, 0x5C, 0x7A), "form"),
    ("events", "BarnCRM_Events_Logo", "events", (0x0B, 0x6B, 0x6B), "calendar"),
]
BRAND_DIR = "docs/brand"

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


def near_segment(x, y, a, b, half_width):
    """True when (x, y) is within half_width of the segment a-b."""
    (ax, ay), (bx, by) = a, b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - ax - t * dx, y - ay - t * dy) <= half_width


def in_polygon(x, y, points):
    """Even-odd rule point in polygon."""
    inside = False
    j = len(points) - 1
    for i, (xi, yi) in enumerate(points):
        xj, yj = points[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def in_leaf(x, y, cx, cy, length, width, angle):
    """A pointed leaf (two arcs) centred on (cx, cy), its long axis at angle radians."""
    c, s = math.cos(angle), math.sin(angle)
    u = (x - cx) * c + (y - cy) * s
    v = -(x - cx) * s + (y - cy) * c
    if abs(u) >= length:
        return False
    return abs(v) <= width * (1 - (u / length) ** 2)


def in_sprout(x, y):
    """Programs: a seedling, two leaves on a stem (growth through a program)."""
    stem = abs(x) < 0.07 and -0.12 < y < 0.60
    left = in_leaf(x, y, -0.27, -0.16, 0.30, 0.15, math.radians(28))
    right = in_leaf(x, y, 0.25, -0.36, 0.34, 0.17, math.radians(-30))
    return stem or left or right


def in_ribbon(x, y):
    """Funders: an award ribbon, a medallion with two tails (a grant awarded)."""
    r = math.hypot(x, y + 0.20)
    if r < 0.38:
        return not 0.21 < r < 0.27  # medallion with an inner ring
    left_tail = [(-0.26, 0.02), (-0.06, 0.12), (-0.18, 0.64), (-0.27, 0.52), (-0.40, 0.58)]
    right_tail = [(0.26, 0.02), (0.06, 0.12), (0.18, 0.64), (0.27, 0.52), (0.40, 0.58)]
    return in_polygon(x, y, left_tail) or in_polygon(x, y, right_tail)


def in_flow(x, y):
    """Logic Models: three steps rising left to right, each leading to the next by an elbow
    arrow (inputs, outputs, outcomes)."""
    half, line = 0.20, 0.06
    boxes = [(-0.46, 0.42), (0.0, 0.0), (0.46, -0.42)]
    for cx, cy in boxes:
        if abs(x - cx) <= half and abs(y - cy) <= half:
            return True
    for (ax, ay), (bx, by) in zip(boxes, boxes[1:]):
        corner = (ax, by)
        if near_segment(x, y, (ax, ay - half), corner, line):
            return True
        if near_segment(x, y, corner, (bx - half - 0.10, by), line):
            return True
        tip = bx - half - 0.01
        if in_polygon(x, y, [(tip - 0.14, by - 0.12), (tip, by), (tip - 0.14, by + 0.12)]):
            return True
    return False


def in_form(x, y):
    """Forms: a page with three answer lines, the last one ticked (a form filled in)."""
    if not (abs(x) <= 0.42 and abs(y) <= 0.56):
        return False
    for line_y in (-0.32, -0.06):
        if -0.26 <= x <= 0.26 and abs(y - line_y) <= 0.06:
            return False
    tick = near_segment(x, y, (-0.24, 0.24), (-0.10, 0.36), 0.06) or near_segment(
        x, y, (-0.10, 0.36), (0.22, 0.12), 0.06
    )
    return not tick


def in_calendar(x, y):
    """Events: a calendar page, two rings on its header bar and a grid of four days."""
    half_w, top, bottom = 0.46, -0.36, 0.46
    if abs(x) <= 0.30 and abs(abs(x) - 0.22) <= 0.06 and -0.52 <= y <= -0.26:
        return True  # the rings
    if abs(x) > half_w or not top <= y <= bottom:
        return False
    if y <= -0.14:
        return True  # the header bar
    edge = 0.07
    if abs(x) >= half_w - edge or y >= bottom - edge:
        return True  # the page's border
    cells = [(-0.17, 0.04), (0.17, 0.04), (-0.17, 0.27), (0.17, 0.27)]
    return any(abs(x - cx) <= 0.09 and abs(y - cy) <= 0.07 for cx, cy in cells)


GLYPHS = {
    "form": in_form,
    "calendar": in_calendar,
    "gear": in_gear,
    "heart": in_heart,
    "person": in_person,
    "sprout": in_sprout,
    "ribbon": in_ribbon,
    "flow": in_flow,
}


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
    brand = os.path.join(args.out, BRAND_DIR)
    os.makedirs(brand, exist_ok=True)
    with open(MASTER, "rb") as source, open(
        os.path.join(brand, "barncrm-logo.png"), "wb"
    ) as handle:
        handle.write(source.read())
    for package, name, slug, color, glyph in VARIANTS:
        rows = with_badge(master, color, glyph)
        made.append(rows)
        image = png_bytes(rows)
        folder = os.path.join(args.out, "packages", package, "main/default/contentassets")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, name + ".asset"), "wb") as handle:
            handle.write(image)
        with open(os.path.join(brand, f"barncrm-{slug}-logo.png"), "wb") as handle:
            handle.write(image)
        with open(os.path.join(folder, name + ".asset-meta.xml"), "w", encoding="utf-8") as handle:
            handle.write(META.format(name=name))
        print(f"{package}: {name}")
    if args.sheet:
        with open(args.sheet, "wb") as handle:
            handle.write(png_bytes(contact_sheet(made)))
        print(f"contact sheet: {args.sheet}")


if __name__ == "__main__":
    main()
