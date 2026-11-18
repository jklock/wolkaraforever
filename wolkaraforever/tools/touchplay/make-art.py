#!/usr/bin/env python3
"""TouchPlay art (R48, R49): draws addon/TouchPlay/Art/*.tga, the add-on's own sharp art for its non-spell buttons,
and Art/CREDITS.txt.

The game's small icons and frames (64 px icons, the 64 px tracking ring, the 16 px gossip bubble, the 256 px
minimap border) came out soft on the iPad's 2x screen at touch size. These are drawn at twice their drawn size
or more, in power-of-two textures, 32-bit TGA with alpha.

  Ring.tga     256 x 256    the round button: dark disc, gold ring, black edge, soft shadow; spans 1.25 x the button
  Glyphs.tga   2048 x 1024  8 x 4 cells of 256: the icons (game-icons.net, CC BY 3.0, shaded as gold metal),
                            the press glow, the page box
  Minimap.tga  512 x 512    the minimap's gold ring round the 172 disc and the zone name plate; 256 x 256 units

The icons are game-icons.net's (https://game-icons.net, CC BY 3.0). Their SVG sources are kept in tools/art-src/
<author>/<name>.svg so the art can be drawn again offline; a missing one is downloaded from the project's GitHub.

usage: tools/make-art.py            (needs Pillow, numpy and CairoSVG with the cairo library:
                                     pip install pillow numpy cairosvg; brew install cairo)
       tools/make-art.py --check    redraws in memory and fails when a file in Art/ differs
"""
import io
import math
import os
import sys
import urllib.request

import numpy as np
from PIL import Image

try:
    import cairosvg
except OSError:
    # cairocffi finds Homebrew's cairo only through the fallback library path, which dyld reads at start-up
    if os.environ.get("TOUCHPLAY_ART_REEXEC"):
        raise
    os.environ["TOUCHPLAY_ART_REEXEC"] = "1"
    os.environ["DYLD_FALLBACK_LIBRARY_PATH"] = "/opt/homebrew/lib:/usr/local/lib"
    os.execv(sys.executable, [sys.executable] + sys.argv)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "addon", "TouchPlay", "Art")
SRC = os.path.join(ROOT, "tools", "art-src")
SOURCE_URL = "https://raw.githubusercontent.com/game-icons/icons/master/%s/%s.svg"
PAGE_URL = "https://game-icons.net/1x1/%s/%s.html"
AUTHORS = {"lorc": "Lorc", "delapouite": "Delapouite", "skoll": "Skoll"}

RING_LIGHT = (255, 226, 140)  # #ffe28c, the ring's lit top
RING_DARK = (138, 113, 48)    # #8a7130, the ring's shaded bottom (the mockup's ring colour)
RING_INNER = (42, 34, 16)     # #2a2210, the dark line inside the ring
DISC_IN, DISC_OUT = (44, 42, 36), (11, 10, 8)   # radial-gradient(circle at 50% 40%, #2c2a24, #0b0a08)

# Gold metal (top, middle, bottom) and red metal for Next target and Cancel (the mockups' red #ff5040).
GOLD_METAL = ((255, 240, 176), (246, 196, 64), (164, 104, 18))
RED_METAL = ((255, 178, 156), (232, 78, 52), (138, 28, 16))

CELL = 256
COLS, ROWS = 8, 4
# The order is Style.lua's GLYPHS table: (column, row).
GLYPHS = [
    ["bag", "menu", "talk", "jump", "dive", "cross", "cancel", "mail"],
    ["loot", "open", "hook", "skin", "sword", "person", "book", "star"],
    ["scroll", "map", "hammer", "people", "chat", "gear", "layout", "exit"],
    ["glow", "box", "mount", None, None, None, None, None],
]

# glyph -> (author, game-icons name, what it shows, options)
ICONS = {
    "bag": ("lorc", "knapsack", "Bags (ring and Menu tile)", {}),
    "menu": ("delapouite", "hamburger-menu", "Menu", {}),
    "talk": ("lorc", "conversation", "Interact: talk", {}),
    "jump": ("delapouite", "plain-arrow", "Jump (turned to point up)", {"turn": True}),
    "dive": ("delapouite", "plain-arrow", "Dive and Dismount", {}),
    "cross": ("delapouite", "convergence-target", "Next target", {"metal": RED_METAL}),
    "cancel": ("lorc", "cross-mark", "Interact: cancel", {"metal": RED_METAL}),
    "mail": ("lorc", "envelope", "Minimap: new mail", {}),
    "loot": ("lorc", "swap-bag", "Interact: loot", {}),
    "open": ("skoll", "open-chest", "Interact: open", {}),
    "hook": ("lorc", "fishing-hook", "Interact: reel in", {}),
    "skin": ("delapouite", "animal-hide", "Interact: skin", {}),
    "sword": ("lorc", "crossed-swords", "Interact: attack", {}),
    "person": ("lorc", "visored-helm", "Menu: Character", {}),
    "book": ("delapouite", "spell-book", "Menu: Spellbook", {}),
    "star": ("delapouite", "stars-stack", "Menu: Talents", {}),
    "scroll": ("lorc", "scroll-unfurled", "Menu: Quests", {}),
    "map": ("lorc", "treasure-map", "Menu: Map", {}),
    "hammer": ("lorc", "anvil-impact", "Menu: Professions", {}),
    "people": ("delapouite", "three-friends", "Menu: Social", {}),
    "chat": ("delapouite", "chat-bubble", "Menu: Chat", {}),
    "gear": ("lorc", "cog", "Menu: Settings", {}),
    "layout": ("delapouite", "move", "Menu: Edit layout", {}),
    "exit": ("delapouite", "exit-door", "Menu: Log out", {}),
    "mount": ("lorc", "horse-head", "Mount", {}),
}

SS = 4          # supersampling for the icons
ICON_BOX = 0.86  # the icon's share of its cell; the rest is room for the outline and the shadow


# ---------------------------------------------------------------------------------------------------------------
# The icons: game-icons.net silhouettes, shaded as gold metal with a dark outline

def svg_source(author, name):
    path = os.path.join(SRC, author, name + ".svg")
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with urllib.request.urlopen(SOURCE_URL % (author, name), timeout=30) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def icon_mask(author, name, turn=False):
    """The icon's coverage (0..1) at SS x the cell, centred in ICON_BOX of it."""
    svg = svg_source(author, name).replace('<path d="M0 0h512v512H0z"/>', "")   # drop the black backdrop
    big = CELL * SS
    inner = int(round(big * ICON_BOX))
    png = cairosvg.svg2png(bytestring=svg.encode("utf-8"), output_width=inner, output_height=inner)
    icon = Image.open(io.BytesIO(png)).convert("RGBA").getchannel("A")
    if turn:
        icon = icon.rotate(180)
    canvas = Image.new("L", (big, big), 0)
    canvas.paste(icon, ((big - inner) // 2, (big - inner) // 2))
    return np.asarray(canvas, np.float64) / 255.0


def box_blur(a, r):
    """A box blur of radius r along both axes (three of them make a near-Gaussian)."""
    r = int(r)
    if r < 1:
        return a
    out = a
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(out, pad, mode="constant"), axis=axis)
        if axis == 0:
            out = (c[2 * r + 1:, :] - c[:-2 * r - 1, :]) / (2 * r + 1)
        else:
            out = (c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)
    return out


def blur(a, r):
    for _ in range(3):
        a = box_blur(a, r)
    return a


def metal_icon(mask, metal):
    """Gold (or red) metal: a top-to-bottom gradient, a bevel lit from the top left with a small shine,
    a soft dark outline and a drop shadow."""
    size = mask.shape[0]
    y = (np.mgrid[0:size, 0:size][0] + 0.5) / size
    top, mid, bottom = (np.array(c, np.float64) for c in metal)
    t = np.clip((y - 0.1) / 0.8, 0, 1)[..., None]
    base = np.where(t < 0.5, top * (1 - t * 2) + mid * (t * 2), mid * (2 - t * 2) + bottom * (t * 2 - 1))

    height = blur(mask, 2.5 * SS)
    gy, gx = np.gradient(height * 6.0 * SS)
    n = np.dstack([-gx, -gy, np.ones_like(gx)])
    n /= np.linalg.norm(n, axis=2)[..., None]
    light = np.array([-0.45, -0.65, 0.62])
    light /= np.linalg.norm(light)
    lambert = np.clip(np.tensordot(n, light, axes=([2], [0])), 0, 1)
    half = light + np.array([0, 0, 1.0])
    half /= np.linalg.norm(half)
    shine = np.clip(np.tensordot(n, half, axes=([2], [0])), 0, 1) ** 24
    flat = light[2]                                   # what a flat face gets: keep the face at its base colour
    shade = 0.55 + 0.45 * lambert / flat
    rgb = base * shade[..., None] + 255 * 0.55 * shine[..., None]
    # an inner dark line just inside the edge, as engraved metal
    edge = np.clip(mask - blur(mask, 1.2 * SS), 0, 1)
    rgb = rgb * (1 - 0.35 * np.clip(edge * 3, 0, 1))[..., None]
    rgb = np.clip(rgb, 0, 255)

    outline = np.clip(blur(mask, 2.0 * SS) * 3.2, 0, 1) * 0.92
    shadow = np.roll(np.clip(blur(mask, 4.0 * SS) * 1.6, 0, 1), int(2 * SS), axis=0) * 0.55
    dark = np.zeros_like(rgb) + np.array((22, 13, 2), np.float64)
    out_rgb, out_a = dark.copy(), np.maximum(outline, shadow)
    out_rgb, out_a = over(out_rgb, out_a, rgb, mask)
    big = to_image(out_rgb, out_a)
    # shrink with premultiplied alpha, so no dark fringe comes in from the clear pixels
    small = big.convert("RGBa").resize((CELL, CELL), Image.LANCZOS).convert("RGBA")
    return small


def make_icon(name):
    author, icon, _, opts = ICONS[name]
    return metal_icon(icon_mask(author, icon, opts.get("turn", False)), opts.get("metal", GOLD_METAL))


# ---------------------------------------------------------------------------------------------------------------
# Shared pixel helpers

def to_image(rgb, a):
    arr = np.dstack([np.clip(rgb, 0, 255), np.clip(a * 255, 0, 255)]).round().astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def band(r, inner, outer, aa):
    """1 inside [inner, outer], with aa-wide soft edges."""
    return smooth(inner - aa, inner + aa, r) * (1 - smooth(outer - aa, outer + aa, r))


def lerp(a, b, t):
    return np.array(a, np.float64)[None, None, :] * (1 - t[..., None]) + np.array(b, np.float64)[None, None, :] * t[..., None]


def over(rgb, a, colour_rgb, colour_a):
    """Paint colour_rgb (h, w, 3) with coverage colour_a over (rgb, a)."""
    new_a = colour_a + a * (1 - colour_a)
    num = colour_rgb * colour_a[..., None] + rgb * (a * (1 - colour_a))[..., None]
    safe = np.where(new_a > 0, new_a, 1)
    rgb = np.where(new_a[..., None] > 0, num / safe[..., None], colour_rgb)
    return rgb, new_a


def gold_ring(r, ny, inner, outer, aa):
    """The gold band: lit #ffe28c at the top to #8a7130 at the bottom, a bevel bright in the middle of the band."""
    t = np.clip((ny + 1) / 2, 0, 1)
    base = lerp(RING_LIGHT, RING_DARK, t)
    mid = (inner + outer) / 2
    half = (outer - inner) / 2
    bevel = 0.72 + 0.28 * (1 - np.clip(np.abs(r - mid) / half, 0, 1) ** 2)
    return base * bevel[..., None], band(r, inner, outer, aa)


# ---------------------------------------------------------------------------------------------------------------
# Ring.tga: the ring button. The texture spans 1.25 d; the button (d) is the middle 80 %.

def make_ring(size=256):
    d = size / 1.25
    R = d / 2
    aa = 0.75
    y, x = np.mgrid[0:size, 0:size] + 0.5
    cx = cy = size / 2
    r = np.hypot(x - cx, y - cy)
    ny = (y - cy) / R
    # the soft shadow under the button (the mockup's 0 3px 8px)
    sr = np.hypot(x - cx, y - (cy + 0.05 * d))
    rgb = np.zeros((size, size, 3))
    a = 0.55 * (1 - smooth(R, R + 0.12 * d, sr))
    # the black edge (0 0 0 2px #000 on a 60 button)
    edge = 1 - smooth(R + 0.033 * d - aa, R + 0.033 * d + aa, r)
    rgb, a = over(rgb, a, np.zeros((size, size, 3)), edge)
    # the disc
    gd = np.hypot(x - cx, y - (cy - R + 0.8 * R)) / (0.781 * d)
    disc_rgb = lerp(DISC_IN, DISC_OUT, np.clip(gd, 0, 1))
    rgb, a = over(rgb, a, disc_rgb, 1 - smooth(R - aa, R + aa, r))
    # the dark line inside the gold, then the gold
    inner_line = np.zeros((size, size, 3)) + np.array(RING_INNER)
    rgb, a = over(rgb, a, inner_line, band(r, R - 0.085 * d, R, aa))
    g_rgb, g_a = gold_ring(r, ny, R - 0.065 * d, R, aa)
    rgb, a = over(rgb, a, g_rgb, g_a)
    return to_image(rgb, a)


# ---------------------------------------------------------------------------------------------------------------
# Glyph cells that are not line glyphs

def make_glow(size=CELL):
    """The press glow: a soft warm halo on the ring (drawn ADD over the button)."""
    y, x = np.mgrid[0:size, 0:size] + 0.5
    r = np.hypot(x - size / 2, y - size / 2) / size
    a = 0.85 * np.exp(-((r - 0.45) / 0.055) ** 2) + 0.18 * (1 - smooth(0.0, 0.42, r))
    a = a * (1 - smooth(0.48, 0.5, r))
    rgb = np.zeros((size, size, 3)) + np.array((255, 220, 120))
    return to_image(rgb, np.clip(a, 0, 1))


def make_box(size=CELL):
    """The page box: the tooltip's dark fill in a white rounded frame (tinted gold or grey by the add-on)."""
    u = size / 42.0  # the box is 42 units
    y, x = np.mgrid[0:size, 0:size] + 0.5
    aa = 0.75

    def rrect_dist(inset, radius):
        # signed distance to a rounded square inset by `inset`, corner radius `radius` (negative inside)
        h = size / 2 - inset - radius
        qx = np.abs(x - size / 2) - h
        qy = np.abs(y - size / 2) - h
        return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - radius

    rgb = np.zeros((size, size, 3))
    outer = rrect_dist(0.5 * u, 4 * u)
    a = 1 - smooth(-aa, aa, outer)                      # black outline
    fill = 1 - smooth(-aa, aa, rrect_dist(1.0 * u, 3.5 * u))
    rgb, a = over(rgb, a, np.zeros((size, size, 3)) + np.array((230, 230, 230)), fill)
    inside = 1 - smooth(-aa, aa, rrect_dist(3.0 * u, 2.0 * u))
    rgb, a = over(rgb, a * 1.0, np.zeros((size, size, 3)) + np.array((9, 9, 19)), inside)
    # the tooltip fill is 0.92 opaque: let a little of the world through the middle only
    a = np.where(inside > 0.99, 0.92, a)
    return to_image(rgb, a)



def make_glyphs():
    sheet = Image.new("RGBA", (CELL * COLS, CELL * ROWS), (0, 0, 0, 0))
    for row, names in enumerate(GLYPHS):
        for col, name in enumerate(names):
            if name is None:
                continue
            if name == "glow":
                cell = make_glow()
            elif name == "box":
                cell = make_box()
            else:
                cell = make_icon(name)
            sheet.paste(cell, (col * CELL, row * CELL))
    return sheet


def credits_text():
    lines = [
        "TouchPlay art credits",
        "",
        "The icons in Glyphs.tga are from game-icons.net (https://game-icons.net), licensed under",
        "Creative Commons Attribution 3.0 Unported (CC BY 3.0, https://creativecommons.org/licenses/by/3.0/).",
        "TouchPlay recoloured them as gold or red metal (a gradient, a bevel, an outline and a shadow);",
        "Jump's arrow is turned to point up.",
        "",
    ]
    for row in GLYPHS:
        for name in row:
            if name is None or name not in ICONS:
                continue
            author, icon, use, _ = ICONS[name]
            lines.append("%s: \"%s\" by %s, CC BY 3.0, %s; used for %s" % (
                name, icon, AUTHORS[author], PAGE_URL % (author, icon), use))
    lines += ["", "Ring.tga, Minimap.tga and the glow and box cells of Glyphs.tga are TouchPlay's own,",
              "drawn by tools/make-art.py.", ""]
    return "\n".join(lines)


# ---------------------------------------------------------------------------------------------------------------
# Minimap.tga: 256 x 256 units at 2 px a unit. Its top-left sits 128 units left of the disc's centre, at the
# screen's top (Hud.lua): the disc's centre is at (128, 134), the zone plate centred on the zone text (115, 15).

def make_minimap(size=512):
    k = size / 256.0
    aa = 0.75
    y, x = np.mgrid[0:size, 0:size] + 0.5
    cx, cy = 128 * k, 134 * k
    r = np.hypot(x - cx, y - cy)
    disc_r = 86 * k
    ny = (y - cy) / (98 * k)
    rgb = np.zeros((size, size, 3))
    a = 0.5 * band(r, disc_r + 8 * k, disc_r + 15 * k, 4 * k)          # soft shadow round the ring
    rgb, a = over(rgb, a, np.zeros((size, size, 3)), band(r, disc_r - 1 * k, disc_r + 13.5 * k, aa))
    rgb, a = over(rgb, a, np.zeros((size, size, 3)) + np.array(RING_INNER), band(r, disc_r - 0.5 * k, disc_r + 2.5 * k, aa))
    g_rgb, g_a = gold_ring(r, ny, disc_r + 2 * k, disc_r + 12 * k, aa)
    rgb, a = over(rgb, a, g_rgb, g_a)
    # a fine dark groove in the middle of the gold
    rgb, a = over(rgb, a, np.zeros((size, size, 3)) + np.array(RING_DARK) * 0.55, band(r, disc_r + 6.6 * k, disc_r + 7.4 * k, aa) * 0.8)

    # the zone name plate: 183 x 26 units, centred at (115, 15)
    px, py, pw, ph = 115 * k, 15 * k, 183 * k, 26 * k

    def plate_dist(inset, radius):
        hx = pw / 2 - inset - radius
        hy = ph / 2 - inset - radius
        qx = np.abs(x - px) - hx
        qy = np.abs(y - py) - hy
        return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - radius

    plate_out = 1 - smooth(-aa, aa, plate_dist(0, 7 * k))
    rgb, a = over(rgb, a, np.zeros((size, size, 3)), plate_out)
    pny = (y - py) / (ph / 2)
    t = np.clip((pny + 1) / 2, 0, 1)
    plate_gold = lerp(RING_LIGHT, RING_DARK, t)
    rgb, a = over(rgb, a, plate_gold, 1 - smooth(-aa, aa, plate_dist(1 * k, 6 * k)))
    inner = 1 - smooth(-aa, aa, plate_dist(3.5 * k, 4 * k))
    rgb, a = over(rgb, a, np.zeros((size, size, 3)) + np.array((8, 8, 10)), inner)
    return to_image(rgb, a)


# ---------------------------------------------------------------------------------------------------------------

def save_tga(img, path):
    img.save(path, format="TGA", rle=False)


def main(argv):
    check = "--check" in argv
    files = {"Ring.tga": make_ring(), "Glyphs.tga": make_glyphs(), "Minimap.tga": make_minimap()}
    os.makedirs(ART, exist_ok=True)
    bad = []
    for name, img in files.items():
        path = os.path.join(ART, name)
        if check:
            try:
                on_disk = Image.open(path).convert("RGBA")
            except OSError:
                bad.append(name)
                continue
            if on_disk.size != img.size or on_disk.tobytes() != img.tobytes():
                bad.append(name)
        else:
            save_tga(img, path)
            print("make-art: wrote %s (%d x %d)" % (os.path.relpath(path, ROOT), img.size[0], img.size[1]))
    credits = os.path.join(ART, "CREDITS.txt")
    text = credits_text()
    if check:
        try:
            with open(credits, encoding="utf-8") as f:
                if f.read() != text:
                    bad.append("CREDITS.txt")
        except OSError:
            bad.append("CREDITS.txt")
    else:
        with open(credits, "w", encoding="utf-8") as f:
            f.write(text)
        print("make-art: wrote %s" % os.path.relpath(credits, ROOT))
    if bad:
        print("make-art: out of date: " + ", ".join(bad) + " (run tools/make-art.py)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
