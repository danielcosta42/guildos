"""The Salão's art (specs/salao/fase3.md): every texture in Media/Salao, drawn from code.

    python3 tools/salao_art.py            # writes Media/Salao/*.tga
    python3 tools/salao_art.py --check    # exits 1 when a file on disk differs from what this draws

WoW draws no CSS: the mockup's gradients, rounded corners, grain and glow become small TGA files
here, tinted in Lua with SetVertexColor where a colour varies (a class, a state). TGA 32-bit,
uncompressed, top-left origin (descriptor 0x28), power-of-two sides, as Media/README.md asks.
Anti-aliased shapes are drawn at 4x and reduced. Noise uses a fixed seed, so a run is repeatable.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Media", "Salao")
SS = 4  # supersampling factor for anti-aliased shapes


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def reduce(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def mask_round(w, h, r, stroke=None):
    """A rounded rectangle's coverage (L), filled or as a `stroke`-wide outline, anti-aliased."""
    big = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(big)
    box = (0, 0, w * SS - 1, h * SS - 1)
    d.rounded_rectangle(box, radius=r * SS, fill=255)
    if stroke:
        s = int(round(stroke * SS))
        d.rounded_rectangle((s, s, w * SS - 1 - s, h * SS - 1 - s), radius=max(0, (r - stroke) * SS), fill=0)
    return reduce(big, w, h)


def mask_circle(size, stroke=None, inset=0.0):
    big = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(big)
    i = int(inset * SS)
    d.ellipse((i, i, size * SS - 1 - i, size * SS - 1 - i), fill=255)
    if stroke:
        s = i + int(round(stroke * SS))
        d.ellipse((s, s, size * SS - 1 - s, size * SS - 1 - s), fill=0)
    return reduce(big, size, size)


def white_with(mask, lum=None):
    """White (or a grey ramp from `lum(x, y)`) with `mask` as alpha."""
    w, h = mask.size
    img = Image.new("RGBA", (w, h))
    px, m = img.load(), mask.load()
    for y in range(h):
        for x in range(w):
            v = 255 if lum is None else max(0, min(255, int(round(255 * lum(x, y)))))
            px[x, y] = (v, v, v, m[x, y])
    return img


def wood():
    # Vertical boards, as the mockup's repeating-linear-gradient: 62px board, 2px groove, twice across 128.
    w, h = 128, 256
    rnd = random.Random(445)
    img = Image.new("RGBA", (w, h))
    px = img.load()
    boards = [(0, 62, hexc("3b2614")), (64, 126, hexc("3e2816"))]
    grooves = [(62, 64, hexc("311d0f")), (126, 128, hexc("2f1c0e"))]
    # Grain: streaks along each board, periodic in y (256) so the tile repeats down.
    streak = [[0.0] * w for _ in range(h)]
    for x0, x1, _ in boards:
        for _ in range(26):
            sx = rnd.uniform(x0 + 1, x1 - 1)
            amp = rnd.uniform(0.6, 2.2)
            k = rnd.choice([1, 2, 3])
            ph = rnd.uniform(0, 2 * math.pi)
            strength = rnd.uniform(-0.07, 0.05)
            for y in range(h):
                cx = sx + amp * math.sin(2 * math.pi * k * y / h + ph)
                for x in range(int(cx) - 1, int(cx) + 2):
                    if x0 <= x < x1:
                        streak[y][x] += strength * max(0.0, 1 - abs(x - cx))
    for y in range(h):
        for x in range(w):
            col = None
            for x0, x1, c in boards + grooves:
                if x0 <= x < x1:
                    col = c
            f = 1 + streak[y][x] + rnd.uniform(-0.015, 0.015)
            # A board's edges catch a little less light.
            for x0, x1, _ in boards:
                if x in (x0, x1 - 1):
                    f *= 0.93
            px[x, y] = (min(255, int(col[0] * f)), min(255, int(col[1] * f)), min(255, int(col[2] * f)), 255)
    return img


def grain():
    # The paper's grain: dark specks with a little alpha, tiled over the card (the mockup's noise at .12).
    size = 128
    rnd = random.Random(1445)
    base = Image.new("L", (size, size))
    bp = base.load()
    for y in range(size):
        for x in range(size):
            bp[x, y] = int(rnd.random() * 255)
    # Periodic blur: pad by wrapping, blur, crop, so the tile stays seamless.
    pad = Image.new("L", (size * 3, size * 3))
    for i in range(3):
        for j in range(3):
            pad.paste(base, (i * size, j * size))
    pad = pad.filter(ImageFilter.GaussianBlur(0.8)).crop((size, size, 2 * size, 2 * size))
    pp = pad.load()
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = pp[x, y]
            a = int(max(0, (128 - v)) * 0.32)  # the darker half of the noise, up to ~16% alpha
            px[x, y] = (0x6f, 0x5a, 0x3c, a)
    return img


def glow():
    # The fire in the bottom-right corner: warm orange, strongest at (88%, 105%), gone by about 60%.
    size = 128
    img = Image.new("RGBA", (size, size))
    px = img.load()
    cx, cy = 0.88 * size, 1.05 * size
    for y in range(size):
        for x in range(size):
            d = math.hypot((x + 0.5 - cx) / (0.62 * size), (y + 0.5 - cy) / (0.62 * size))
            a = max(0.0, 1 - d) ** 1.5 * 0.34
            px[x, y] = (255, 140, 30, int(round(a * 255)))
    return img


def titlebar():
    w, h = 16, 64
    top, bottom = hexc("3e2a15"), hexc("22160b")
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(int(round(top[i] + (bottom[i] - top[i]) * t)) for i in range(3)) + (255,)
        for x in range(w):
            px[x, y] = c
    return img


def card():
    return white_with(mask_round(32, 32, 8))


def card_line():
    return white_with(mask_round(32, 32, 8, stroke=1))


def shadow():
    # A soft shadow: a rounded box 16px in from each side, blurred. 9-sliced with 24px corners.
    size = 64
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((16, 16, size - 17, size - 17), radius=8, fill=255)
    m = m.filter(ImageFilter.GaussianBlur(6))
    img = Image.new("RGBA", (size, size))
    px, mp = img.load(), m.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = (0, 0, 0, mp[x, y])
    return img


def button():
    # A rounded button whose light falls from the top: tinted with the top colour, the bottom is 62% of it.
    return white_with(mask_round(64, 32, 6), lambda x, y: 1 - 0.38 * (y / 31))


def button_soft():
    # The quiet button's gentler light (cream to #e8d3a6): the bottom is 86% of the top.
    return white_with(mask_round(64, 32, 6), lambda x, y: 1 - 0.14 * (y / 31))


def button_line():
    return white_with(mask_round(64, 32, 6, stroke=1.4))


def pill():
    return white_with(mask_round(64, 32, 16))


def pill_line():
    return white_with(mask_round(64, 32, 16, stroke=1.4))


def orb():
    # A lit sphere: light at (40%, 35%), falling to 42% at the rim. Crest, close button, pin and glyphs.
    size = 64
    m = mask_circle(size)
    return white_with(m, lambda x, y: 1 - 0.58 * min(1, math.hypot((x - 0.4 * size) / size, (y - 0.35 * size) / size) / 0.62))


def disc():
    # An avatar's disc: light at the top left, 55% at the bottom right (the mockup's 135deg gradient).
    size = 64
    return white_with(mask_circle(size), lambda x, y: 1 - 0.45 * ((x + y) / (2 * (size - 1))))


def circle():
    return white_with(mask_circle(32))


def ring():
    # 3.2px at 64: 2px around a 40px avatar, about 1.4px around a 28px tool.
    return white_with(mask_circle(64, stroke=3.2))


def ring_dash():
    size = 64
    m = mask_circle(size, stroke=3.2)
    mp = m.load()
    for y in range(size):
        for x in range(size):
            ang = math.atan2(y + 0.5 - size / 2, x + 0.5 - size / 2)
            if int((ang + math.pi) / (2 * math.pi) * 20) % 2 == 1:
                mp[x, y] = 0
    return white_with(m)


def halo():
    # The glow around an avatar: drawn at 1.5x the disc, its rim at 2/3 of the radius.
    size = 64
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            d = math.hypot(x + 0.5 - size / 2, y + 0.5 - size / 2) / (size / 2)
            a = 0.0 if d >= 1 else (0.45 if d <= 0.62 else 0.45 * (1 - (d - 0.62) / 0.38) ** 2)
            px[x, y] = (255, 170, 60, int(round(a * 255)))
    return img


def fade():
    w, h = 64, 8
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = (255, 255, 255, int(round(255 * (1 - x / (w - 1)))))
    return img


def snow():
    size = 64
    big = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(big)
    rnd = random.Random(1225)
    for _ in range(7):
        x, y = rnd.uniform(4, size - 4), rnd.uniform(4, size - 4)
        r = rnd.choice([0.9, 1.2, 1.6])
        d.ellipse(((x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS), fill=rnd.choice([150, 200, 255]))
    m = reduce(big, size, size)
    return white_with(m)


def garland():
    # The green cord with red and gold baubles under the title bar (the mockup's .winter .bar::after).
    w, h = 64, 16
    big = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.rectangle((0, 3 * SS, w * SS - 1, 6 * SS - 1), fill=hexc("1f5a2a"))
    for cx, cy, col in ((16, 6, "e23b2e"), (48, 8, "f5c242")):
        r = 3.5
        d.ellipse(((cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS), fill=hexc(col))
        d.ellipse(((cx - 1.6) * SS, (cy - 2) * SS, (cx - 0.2) * SS, (cy - 0.6) * SS), fill=(255, 255, 255, 150))
    return reduce(big, w, h)


def icon_search():
    size = 32
    big = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(big)
    s = SS
    d.ellipse((6 * s, 5 * s, 20 * s, 19 * s), outline=255, width=int(2.6 * s))
    d.line((18 * s, 17 * s, 26 * s, 25 * s), fill=255, width=int(3.4 * s))
    return white_with(reduce(big, size, size))


def icon_gear():
    size = 32
    big = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(big)
    c = size * SS / 2
    teeth, r_out, r_in = 8, 12.5 * SS, 9.5 * SS
    pts = []
    for i in range(teeth * 4):
        a = 2 * math.pi * i / (teeth * 4) - math.pi / 2
        r = r_out if (i % 4) in (0, 1) else r_in
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
    d.polygon(pts, fill=255)
    d.ellipse((c - 4 * SS, c - 4 * SS, c + 4 * SS, c + 4 * SS), fill=0)
    return white_with(reduce(big, size, size))


ART = {
    "wood": wood, "grain": grain, "glow": glow, "titlebar": titlebar,
    "card": card, "card-line": card_line, "shadow": shadow,
    "button": button, "button-soft": button_soft, "button-line": button_line, "pill": pill, "pill-line": pill_line,
    "orb": orb, "disc": disc, "circle": circle, "ring": ring, "ring-dash": ring_dash, "halo": halo,
    "fade": fade, "snow": snow, "garland": garland, "icon-search": icon_search, "icon-gear": icon_gear,
}


def tga_bytes(img):
    """Uncompressed 32-bit TGA, top-left origin (descriptor 0x28), BGRA rows top to bottom."""
    img = img.convert("RGBA")
    w, h = img.size
    head = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, w & 255, w >> 8, h & 255, h >> 8, 32, 0x28])
    return head + img.tobytes("raw", "BGRA")


def main():
    check = "--check" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    stale = []
    for name, draw in ART.items():
        data = tga_bytes(draw())
        path = os.path.join(OUT, name + ".tga")
        if check:
            if not os.path.exists(path) or open(path, "rb").read() != data:
                stale.append(name)
        else:
            with open(path, "wb") as f:
                f.write(data)
    if check and stale:
        print("stale: " + ", ".join(stale))
        sys.exit(1)


if __name__ == "__main__":
    main()
