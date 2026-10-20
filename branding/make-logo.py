#!/usr/bin/env python3
"""Generate the armsense logo assets.

The mark is a monochrome badge in the family of the swtch.in logo: a filled
disc with a knocked-out shield, and inside the shield a chip (SoC) with pins
and a knocked-out die.  Everything is one colour plus transparency, so the
same geometry works black-on-light and white-on-dark.

Outputs (in out/):
  armsense-mark.svg, armsense-mark-white.svg        square mark
  armsense-logo.svg, armsense-logo-white.svg        mark + wordmark
  armsense-mark-<size>.png                          previews
  gui/logo.svg, gui/logo.css                        web GUI header (white on dark)
  gui/favicon.ico, favicon-*.png, android-chrome-*.png, mstile-150x150.png,
  gui/apple-touch/*.png, gui/safari-pinned-tab.svg  browser icons
"""
import math
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")

# ---------------------------------------------------------------- geometry
# Unit square 0..100; the badge disc fills it.
CX = CY = 50.0
R = 50.0

# Shield: flat top with chamfered shoulders, straight sides, pointed bottom.
SHIELD_TOP = 22.0
SHIELD_W = 44.0          # width at the shoulders
SHIELD_STRAIGHT_TO = 54.0  # y where the sides start curving in
SHIELD_TIP = 82.0

# Chip: rounded square centred in the shield, with pins on all four sides.
CHIP = 20.0
CHIP_CX, CHIP_CY = 50.0, 47.0
CHIP_RX = 2.6
PIN_LEN, PIN_W, PIN_GAP = 4.2, 2.6, 6.2   # three pins per side
DIE = 7.0                                  # knocked-out die in the chip centre


def shield_points(n=24):
    """Polygon approximation of the shield outline (clockwise from top-left)."""
    half = SHIELD_W / 2
    left, right = CX - half, CX + half
    pts = [(left + 4.0, SHIELD_TOP), (right - 4.0, SHIELD_TOP),
           (right, SHIELD_TOP + 4.0), (right, SHIELD_STRAIGHT_TO)]
    # right side: quadratic curve from (right, STRAIGHT_TO) to the tip,
    # control point pulled down so the lower half bulges like a shield.
    p0, p1, p2 = (right, SHIELD_STRAIGHT_TO), (right, SHIELD_TIP - 6.0), (CX, SHIELD_TIP)
    for i in range(1, n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        pts.append((x, y))
    p0, p1, p2 = (CX, SHIELD_TIP), (left, SHIELD_TIP - 6.0), (left, SHIELD_STRAIGHT_TO)
    for i in range(1, n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        pts.append((x, y))
    pts.append((left, SHIELD_TOP + 4.0))
    return pts


def shield_path():
    half = SHIELD_W / 2
    left, right = CX - half, CX + half
    return (f"M{left + 4:.2f} {SHIELD_TOP:.2f} H{right - 4:.2f} L{right:.2f} {SHIELD_TOP + 4:.2f} "
            f"V{SHIELD_STRAIGHT_TO:.2f} Q{right:.2f} {SHIELD_TIP - 6:.2f} {CX:.2f} {SHIELD_TIP:.2f} "
            f"Q{left:.2f} {SHIELD_TIP - 6:.2f} {left:.2f} {SHIELD_STRAIGHT_TO:.2f} "
            f"V{SHIELD_TOP + 4:.2f} Z")


def pin_rects():
    rects = []
    half = CHIP / 2
    for k in (-1, 0, 1):
        o = k * PIN_GAP
        # top and bottom
        rects.append((CHIP_CX + o - PIN_W / 2, CHIP_CY - half - PIN_LEN, PIN_W, PIN_LEN))
        rects.append((CHIP_CX + o - PIN_W / 2, CHIP_CY + half, PIN_W, PIN_LEN))
        # left and right
        rects.append((CHIP_CX - half - PIN_LEN, CHIP_CY + o - PIN_W / 2, PIN_LEN, PIN_W))
        rects.append((CHIP_CX + half, CHIP_CY + o - PIN_W / 2, PIN_LEN, PIN_W))
    return rects


# ---------------------------------------------------------------- SVG
def mark_svg_body(fill, scale=1.0, dx=0.0, dy=0.0, cls=None):
    """SVG elements for the mark, in a 100x100 unit box scaled/translated."""
    attr = f'class="{cls}"' if cls else f'fill="{fill}"'
    g = f'<g transform="translate({dx:.3f} {dy:.3f}) scale({scale:.5f})" {attr} fill-rule="evenodd">'
    disc = f'<path d="M{CX:.1f} 0a{R:.1f} {R:.1f} 0 1 0 0 100a{R:.1f} {R:.1f} 0 1 0 0-100Z {shield_path()}"/>'
    half = CHIP / 2
    chip = (f'<path d="M{CHIP_CX - half + CHIP_RX:.2f} {CHIP_CY - half:.2f}'
            f'h{CHIP - 2 * CHIP_RX:.2f}a{CHIP_RX} {CHIP_RX} 0 0 1 {CHIP_RX} {CHIP_RX}'
            f'v{CHIP - 2 * CHIP_RX:.2f}a{CHIP_RX} {CHIP_RX} 0 0 1 -{CHIP_RX} {CHIP_RX}'
            f'h-{CHIP - 2 * CHIP_RX:.2f}a{CHIP_RX} {CHIP_RX} 0 0 1 -{CHIP_RX} -{CHIP_RX}'
            f'v-{CHIP - 2 * CHIP_RX:.2f}a{CHIP_RX} {CHIP_RX} 0 0 1 {CHIP_RX} -{CHIP_RX}Z'
            f' M{CHIP_CX - DIE / 2:.2f} {CHIP_CY - DIE / 2:.2f}h{DIE}v{DIE}h-{DIE}Z"/>')
    pins = "".join(f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" rx="0.6"/>'
                   for x, y, w, h in pin_rects())
    return g + disc + chip + pins + "</g>"


def mark_svg(fill):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 100 100">'
            '<title>armsense</title>' + mark_svg_body(fill) + '</svg>\n')


def logo_svg(fill, width=282.8, height=84.2, cls=None, css_text=False):
    """Mark at the left, wordmark 'armsense' at the right; same box as the
    GUI logo it replaces (282.8 x 84.2)."""
    scale = 72.0 / 100.0
    body = mark_svg_body(fill, scale=scale, dx=4.0, dy=(height - 72.0) / 2, cls=cls)
    attr = f'class="{cls}"' if cls else f'fill="{fill}"'
    text = (f'<text x="{4 + 72 + 12:.1f}" y="{height / 2 + 13:.1f}" {attr} '
            'font-family="\'Helvetica Neue\', Helvetica, Arial, \'Liberation Sans\', sans-serif" '
            'font-size="37" font-weight="700" letter-spacing="-0.5">armsense</text>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" id="logo" role="img" aria-labelledby="armsense-logo" '
            f'viewBox="0 0 {width} {height}"><title id="armsense-logo">armsense</title>' + body + text + '</svg>\n')


# ---------------------------------------------------------------- raster (PIL)
def render_mark(size, fill=(0, 0, 0, 255), bg=(0, 0, 0, 0), supersample=8):
    """Render the mark with PIL at `size` px using supersampling."""
    S = size * supersample
    k = S / 100.0
    im = Image.new("RGBA", (S, S), bg)
    d = ImageDraw.Draw(im)
    clear = (0, 0, 0, 0) if bg[3] == 0 else bg
    d.ellipse([0, 0, S - 1, S - 1], fill=fill)
    d.polygon([(x * k, y * k) for x, y in shield_points()], fill=clear)
    half = CHIP / 2
    d.rounded_rectangle([(CHIP_CX - half) * k, (CHIP_CY - half) * k, (CHIP_CX + half) * k, (CHIP_CY + half) * k],
                        radius=CHIP_RX * k, fill=fill)
    for x, y, w, h in pin_rects():
        d.rounded_rectangle([x * k, y * k, (x + w) * k, (y + h) * k], radius=0.6 * k, fill=fill)
    d.rectangle([(CHIP_CX - DIE / 2) * k, (CHIP_CY - DIE / 2) * k, (CHIP_CX + DIE / 2) * k, (CHIP_CY + DIE / 2) * k],
                fill=clear)
    return im.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------- ASCII art
# figlet "small" glyphs (3 rows each) for the wordmark used on the console and
# in the boot loader brand.
GLYPHS = {
    "a": [" __ _ ", "/ _` |", "\\__,_|"],
    "r": [" _ _ ", "| '_|", "|_|  "],
    "m": [" _ __  ", "| '  \\ ", "|_|_|_|"],
    "s": [" ___ ", "(_-< ", "/__/ "],
    "e": [" ___ ", "/ -_)", "\\___|"],
    "n": [" _ _  ", "| ' \\ ", "|_||_|"],
}


def wordmark_ascii(word="armsense"):
    rows = ["", "", ""]
    for ch in word:
        for i in range(3):
            rows[i] += GLYPHS[ch][i]
    return [r.rstrip() for r in rows]


# Shield with a chip, sized for the loader's logo slot (pfSense's is 31x15).
LOADER_LOGO = [
    "         _______________         ",
    "        /               \\        ",
    "       |   ___________   |       ",
    "       |  |  _______  |  |       ",
    "       |  | |  ___  | |  |       ",
    "       |  | | |   | | |  |       ",
    "       |  | | |___| | |  |       ",
    "       |  | |_______| |  |       ",
    "       |  |___________|  |       ",
    "        \\               /        ",
    "         \\             /         ",
    "          \\           /          ",
    "           \\_________/           ",
    "                                 ",
]


def lua_list(lines, indent=""):
    out = []
    for l in lines:
        out.append(indent + '"' + l.replace("\\", "\\\\") + '",')
    return "\n".join(out)


def write_ascii():
    os.makedirs(os.path.join(OUT, "ascii-art"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "loader"), exist_ok=True)
    wm = wordmark_ascii()
    with open(os.path.join(OUT, "ascii-art", "armsense-logo-small.txt"), "w") as f:
        f.write("\n".join(wm) + "\n")
    header = ("--\n-- SPDX-License-Identifier: Apache-2.0\n--\n-- armsense boot loader %s\n--\n\n"
              "local drawer = require(\"drawer\")\n\n")
    with open(os.path.join(OUT, "loader", "brand-armsense.lua"), "w") as f:
        f.write(header % "brand")
        f.write("local armsense = {\n" + lua_list([""] + wm + [""]) + "\n}\n\n")
        f.write('drawer.addBrand("armsense", {\n\tgraphic = armsense,\n})\n\nreturn true\n')
    with open(os.path.join(OUT, "loader", "logo-armsensebw.lua"), "w") as f:
        f.write(header % "logo")
        f.write("local armsensebw = {\n" + lua_list(LOADER_LOGO) + "\n}\n\n")
        f.write('drawer.addLogo("armsensebw", {\n\tgraphic = armsensebw,\n\tshift = {x = 2, y = -2},\n})\n\nreturn true\n')


def main():
    os.makedirs(os.path.join(OUT, "gui", "apple-touch"), exist_ok=True)
    write_ascii()
    black, white = "#000", "#fff"

    with open(os.path.join(OUT, "armsense-mark.svg"), "w") as f:
        f.write(mark_svg(black))
    with open(os.path.join(OUT, "armsense-mark-white.svg"), "w") as f:
        f.write(mark_svg(white))
    with open(os.path.join(OUT, "armsense-logo.svg"), "w") as f:
        f.write(logo_svg(black))
    with open(os.path.join(OUT, "armsense-logo-white.svg"), "w") as f:
        f.write(logo_svg(white))

    # Web GUI header: colours come from logo.css so themes can override them.
    with open(os.path.join(OUT, "gui", "logo.svg"), "w") as f:
        f.write(logo_svg(None, cls="logo-st0"))
    with open(os.path.join(OUT, "gui", "logo.css"), "w") as f:
        f.write(".logo-st0 {\n  fill: #ffffff;\n}\n")
    with open(os.path.join(OUT, "gui", "safari-pinned-tab.svg"), "w") as f:
        f.write(mark_svg(black))

    # Previews: black on white and white on dark.
    for size in (64, 256):
        render_mark(size, bg=(255, 255, 255, 255)).save(os.path.join(OUT, f"armsense-mark-{size}.png"))
    render_mark(256, fill=(255, 255, 255, 255), bg=(27, 27, 27, 255)).save(os.path.join(OUT, "armsense-mark-256-dark.png"))

    # Browser icons: black mark on transparent background.
    icons = {
        "gui/favicon-16x16.png": 16,
        "gui/favicon-32x32.png": 32,
        "gui/android-chrome-192x192.png": 192,
        "gui/android-chrome-512x512.png": 512,
        "gui/mstile-150x150.png": 150,
        "gui/apple-touch/apple-touch-icon-iphone-60x60-precomposed.png": 60,
        "gui/apple-touch/apple-touch-icon-ipad-76x76-precomposed.png": 76,
        "gui/apple-touch/apple-touch-icon-iphone-retina-120x120-precomposed.png": 120,
        "gui/apple-touch/apple-touch-icon-ipad-retina-152x152-precomposed.png": 152,
    }
    for rel, size in icons.items():
        # Apple touch icons get an opaque white background (iOS does not composite alpha).
        bg = (255, 255, 255, 255) if "apple-touch" in rel else (0, 0, 0, 0)
        render_mark(size, bg=bg).save(os.path.join(OUT, rel))
    render_mark(64).save(os.path.join(OUT, "gui", "favicon.ico"), format="ICO", sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])

    # Wordmark preview (mark + text) via the SVG is browser-rendered; write a
    # composed PNG preview using PIL's default font substitute for the text.
    print("written to", OUT)
    for root, _, files in os.walk(OUT):
        for fn in sorted(files):
            p = os.path.join(root, fn)
            print(f"  {os.path.relpath(p, OUT):60s} {os.path.getsize(p):7d}")


if __name__ == "__main__":
    sys.exit(main())
