"""The onboarding's pictures (#449): one 512x256 TGA per picture key, in Media/Salao/onboarding.

    python3 tools/onboarding_art.py              # writes Media/Salao/onboarding/<key>.tga
    python3 tools/onboarding_art.py --check      # exits 1 when a file on disk differs from what this draws
    python3 tools/onboarding_art.py --png DIR    # also writes DIR/<key>.png previews

UI.Picture (UI/Onboarding.lua) shows them in What's new, the welcome, the tour's callout and the help's
guides, cropped by texcoords to the holder's shape (about 3:1, never stretched): what matters sits in the
middle band, y 48..208, and the scene runs on to the edges so any crop is filled. No words in a picture:
the addon is in eleven languages. Built from the Salão's own pieces: its wood (Media/Salao/wood.tga),
parchment, gold metal and the class colours. Drawn at 3x and reduced; noise has fixed seeds, so a run is
repeatable. TGA 32-bit, uncompressed, top-left origin, as Media/README.md asks.
"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "Media", "Salao", "onboarding")
W, H, K = 512, 256, 3
INSET = 0.94


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def mix(c1, c2, t):
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(4))


def k(v):
    return int(round(v * K))


INK = {
    "paper": hexc("f3e4c2"), "paper2": hexc("e2cb98"), "paperLine": hexc("b89a62"), "paperInk": hexc("6b4a22"),
    "dark": hexc("1c110a"), "dark2": hexc("2a1a0e"), "metal": hexc("6b5326"), "metal2": hexc("c9a24a"),
    "gold": hexc("ffd24a"), "gold2": hexc("ffd77a"), "soft": hexc("c9b48f"), "tan": hexc("8a7048"),
    "flame": hexc("ff9a3c"), "ember": hexc("ffcf6a"), "red": hexc("a8281a"), "red2": hexc("d0452c"),
    "green": hexc("3f8f3a"), "greenLit": hexc("6ee860"), "blue": hexc("2d6fb8"), "purple": hexc("a335ee"),
    "rare": hexc("0070dd"), "uncommon": hexc("1eff00"), "stone": hexc("6d665c"), "stone2": hexc("8d857a"),
    "wax": hexc("9b1c14"), "T": hexc("2d6fb8"), "H": hexc("2f8a3a"), "D": hexc("a8281a"),
}
CLASS = [hexc(c) for c in ("C69B6D", "F48CBA", "AAD372", "FFF468", "FFFFFF", "3FC7EB", "8788EE", "FF7C0A",
                           "0070DD", "A330C9", "C41E3A")]


class Pic:
    """A 512x256 picture drawn at K times its size."""

    def __init__(self, seed):
        self.rnd = random.Random(seed)
        self.bg = None
        self.img = Image.new("RGBA", (W * K, H * K), (0, 0, 0, 0))

    # -- layers ---------------------------------------------------------------------------------------
    def layer(self):
        return Image.new("RGBA", self.img.size, (0, 0, 0, 0))

    def put(self, lay, blur=0, alpha=1.0):
        if blur:
            lay = lay.filter(ImageFilter.GaussianBlur(k(blur)))
        if alpha < 1:
            a = lay.getchannel("A").point(lambda v: int(v * alpha))
            lay.putalpha(a)
        self.img = Image.alpha_composite(self.img, lay)

    def mask(self):
        return Image.new("L", self.img.size, 0)

    def fill_mask(self, m, color, alpha=1.0):
        lay = Image.new("RGBA", self.img.size, color)
        a = m if alpha >= 1 else m.point(lambda v: int(v * alpha))
        lay.putalpha(ImageChops.multiply(a, Image.new("L", self.img.size, color[3])))
        self.img = Image.alpha_composite(self.img, lay)

    def grad_mask(self, m, top, bottom, box=None):
        """Fill mask `m` with a vertical gradient from `top` to `bottom` over `box`'s height."""
        y0, y1 = (box[1], box[3]) if box else (0, H)
        g = Image.new("RGBA", (1, 256))
        for i in range(256):
            g.putpixel((0, i), mix(top, bottom, i / 255))
        hh = max(1, k(y1 - y0))
        g = g.resize((self.img.size[0], hh), Image.BILINEAR)
        lay = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        lay.paste(Image.new("RGBA", (self.img.size[0], max(0, k(y0))), top), (0, 0))
        lay.paste(Image.new("RGBA", (self.img.size[0], self.img.size[1]), bottom), (0, k(y0) + hh))
        lay.paste(g, (0, k(y0)))
        a = ImageChops.multiply(m, lay.getchannel("A"))
        lay.putalpha(a)
        self.img = Image.alpha_composite(self.img, lay)

    # -- primitives (in picture px) ---------------------------------------------------------------------
    def rr_mask(self, box, r):
        m = self.mask()
        ImageDraw.Draw(m).rounded_rectangle([k(box[0]), k(box[1]), k(box[2]), k(box[3])], radius=k(r), fill=255)
        return m

    def poly_mask(self, pts):
        m = self.mask()
        ImageDraw.Draw(m).polygon([(k(x), k(y)) for x, y in pts], fill=255)
        return m

    def ell_mask(self, cx, cy, rx, ry=None):
        ry = rx if ry is None else ry
        m = self.mask()
        ImageDraw.Draw(m).ellipse([k(cx - rx), k(cy - ry), k(cx + rx), k(cy + ry)], fill=255)
        return m

    def shadow(self, m, blur=5, off=(0, 3), alpha=0.7):
        sh = m.transform(m.size, Image.AFFINE, (1, 0, -k(off[0]), 0, 1, -k(off[1])))
        sh = sh.filter(ImageFilter.GaussianBlur(k(blur)))
        self.fill_mask(sh, (0, 0, 0, 255), alpha)

    def glow(self, cx, cy, r, color, alpha=0.6):
        m = self.ell_mask(cx, cy, r * 0.55)
        m = m.filter(ImageFilter.GaussianBlur(k(r * 0.45)))
        self.fill_mask(m, color, alpha)

    def rr(self, box, r, fill, line=None, lw=1.2):
        m = self.rr_mask(box, r)
        if line:
            self.fill_mask(m, line)
            inner = self.rr_mask((box[0] + lw, box[1] + lw, box[2] - lw, box[3] - lw), max(0, r - lw))
            self.fill_mask(inner, fill)
        else:
            self.fill_mask(m, fill)

    def bar(self, x, y, w, h, color):
        self.rr((x, y, x + w, y + h), h / 2, color)

    def line(self, pts, color, width=1.5):
        lay = self.layer()
        d = ImageDraw.Draw(lay)
        d.line([(k(x), k(y)) for x, y in pts], fill=color, width=max(1, k(width)), joint="curve")
        for x, y in (pts[0], pts[-1]):
            rr = k(width) / 2
            d.ellipse([k(x) - rr, k(y) - rr, k(x) + rr, k(y) + rr], fill=color)
        self.put(lay)

    def dot(self, cx, cy, r, color):
        self.fill_mask(self.ell_mask(cx, cy, r), color)

    def poly(self, pts, color):
        self.fill_mask(self.poly_mask(pts), color)

    # -- the Salão's surfaces ---------------------------------------------------------------------------
    def wood(self, dim=0.85):
        """The scene sits on the Salao's wood; drawn under it at the end (see done)."""
        self.bg = dim

    def _light(self, dim):
        # Warm light from above, the corners in shade.
        self.glow(256, 40, 300, INK["ember"], 0.16)
        v = Image.new("L", (W, H), 0)
        vp = v.load()
        for y in range(H):
            for x in range(W):
                dx, dy = (x - 256) / 300, (y - 128) / 190
                vp[x, y] = int(255 * min(1, max(0, (dx * dx + dy * dy) - 0.25)) * (1 - dim * 0.4))
        self.fill_mask(v.resize(self.img.size, Image.BILINEAR), (8, 4, 2, 255), 0.8)

    def noise_mask(self, box, amount, seed, scale=1.0):
        rnd = random.Random(seed)
        w, h = max(1, int((box[2] - box[0]) * scale)), max(1, int((box[3] - box[1]) * scale))
        n = Image.new("L", (w, h))
        n.putdata([int(rnd.random() ** 3 * 255 * amount) for _ in range(w * h)])
        n = n.resize((k(box[2] - box[0]), k(box[3] - box[1])), Image.BILINEAR)
        m = self.mask()
        m.paste(n, (k(box[0]), k(box[1])))
        return m

    def parchment(self, box, r=5, frame=True, tilt=0):
        m = self.rr_mask(box, r)
        self.shadow(m, 5, (0, 3), 0.75)
        if frame:
            self.fill_mask(self.rr_mask((box[0] - 1.6, box[1] - 1.6, box[2] + 1.6, box[3] + 1.6), r + 1.6), INK["metal"])
        self.grad_mask(m, INK["paper"], INK["paper2"], box)
        # Grain and burnt edges.
        g = ImageChops.multiply(self.noise_mask(box, 0.5, int(box[0] * 7 + box[1]), 0.5), m)
        self.fill_mask(g, hexc("8a6a3a"), 0.5)
        inner = self.rr_mask((box[0] + 4, box[1] + 4, box[2] - 4, box[3] - 4), r)
        edge = ImageChops.subtract(m, inner.filter(ImageFilter.GaussianBlur(k(4))))
        self.fill_mask(edge, hexc("9a7a44"), 0.55)

    def dark_panel(self, box, r=5, fill=None, line=None):
        m = self.rr_mask(box, r)
        self.shadow(m, 5, (0, 3), 0.7)
        self.fill_mask(m, line or INK["metal"])
        inner = self.rr_mask((box[0] + 1.3, box[1] + 1.3, box[2] - 1.3, box[3] - 1.3), r - 1)
        self.grad_mask(inner, fill or hexc("2b1b0f"), mix(fill or hexc("2b1b0f"), hexc("120a05"), 0.6), box)
        # A soft gold light along the top edge.
        top = self.rr_mask((box[0] + 2, box[1] + 1.3, box[2] - 2, box[1] + 3), 1)
        self.fill_mask(top, INK["metal2"], 0.25)

    def gold_frame(self, box, r=5, w=2.2):
        m = self.rr_mask(box, r)
        inner = self.rr_mask((box[0] + w, box[1] + w, box[2] - w, box[3] - w), max(0, r - w))
        ring = ImageChops.subtract(m, inner)
        self.grad_mask(ring, INK["gold2"], INK["metal"], box)

    # -- icons --------------------------------------------------------------------------------------------
    def chip(self, cx, cy, r, fill, ring=None):
        m = self.ell_mask(cx, cy, r)
        self.shadow(m, 2, (0, 1.5), 0.6)
        self.fill_mask(m, ring or INK["metal2"])
        self.grad_mask(self.ell_mask(cx, cy, r - max(1.2, r * 0.13)), mix(fill, hexc("ffffff"), 0.18),
                       mix(fill, hexc("000000"), 0.25), (0, cy - r, 0, cy + r))

    def orb(self, cx, cy, r, color, glow=True):
        if glow:
            self.glow(cx, cy, r * 3.2, color, 0.45)
        self.dot(cx, cy, r + 1.4, hexc("120a05"))
        self.grad_mask(self.ell_mask(cx, cy, r), mix(color, hexc("ffffff"), 0.35), mix(color, hexc("000000"), 0.3),
                       (0, cy - r, 0, cy + r))
        self.dot(cx - r * 0.3, cy - r * 0.35, r * 0.3, hexc("ffffff", 150))

    def shield_pts(self, cx, cy, s):
        def bez(p0, p1, p2, p3, n=14):
            out = []
            for i in range(1, n + 1):
                t = i / n
                u = 1 - t
                out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
            return out
        pts = [(6, 1), (10, 2.6), (10, 5.8)]
        pts += bez((10, 5.8), (10, 8.3), (8.3, 10), (6, 11))
        pts += bez((6, 11), (3.7, 10), (2, 8.3), (2, 5.8))
        pts += [(2, 2.6)]
        return [(cx + (x - 6) * s, cy + (y - 6) * s) for x, y in pts]

    def role(self, cx, cy, r, kind):
        """A raid role's chip: tank (a shield, blue), healer (a cross, green), damage (a sword, red)."""
        self.chip(cx, cy, r, INK[kind])
        light = hexc("f6ecd2")
        s = r / 7.5
        if kind == "T":
            self.poly(self.shield_pts(cx, cy + 0.3 * s, 0.95 * s), light)
        elif kind == "H":
            a, b = 1.6 * s, 4.8 * s
            self.rr((cx - a, cy - b, cx + a, cy + b), 0.6 * s, light)
            self.rr((cx - b, cy - a, cx + b, cy + a), 0.6 * s, light)
        else:
            self.sword(cx, cy, s, math.pi / 4, light)

    def sword(self, cx, cy, s, ang, blade, hilt=None):
        c, sn = math.cos(ang), math.sin(ang)
        hilt = hilt or blade

        def rot(x, y):
            return (cx + (x * c - y * sn) * s, cy + (x * sn + y * c) * s)
        self.poly([rot(-0.9, -5.6), rot(0, -6.6), rot(0.9, -5.6), rot(0.9, 2.2), rot(-0.9, 2.2)], blade)
        self.poly([rot(-3, 2.2), rot(3, 2.2), rot(3, 3.3), rot(-3, 3.3)], hilt)
        self.poly([rot(-0.7, 3.3), rot(0.7, 3.3), rot(0.7, 6), rot(-0.7, 6)], hilt)

    def check(self, cx, cy, s, color):
        self.line([(cx - 4 * s, cy), (cx - 1.2 * s, cy + 3 * s), (cx + 4.5 * s, cy - 3.5 * s)], color, 1.9 * s)

    def coin(self, cx, cy, r, mark=True):
        m = self.ell_mask(cx, cy, r)
        self.shadow(m, 1.5, (0, 1.2), 0.6)
        self.fill_mask(m, hexc("8a6210"))
        self.grad_mask(self.ell_mask(cx, cy, r * 0.86), hexc("ffe48a"), hexc("d39a1c"), (0, cy - r, 0, cy + r))
        if mark:
            self.fill_mask(self.ell_mask(cx, cy, r * 0.5), hexc("e9b33a"))
            self.dot(cx - r * 0.3, cy - r * 0.35, r * 0.2, hexc("fff6cc", 200))

    def coin_side(self, cx, cy, rx, ry):
        """A coin seen edge-on in a stack."""
        self.fill_mask(self.ell_mask(cx, cy + 1.6, rx, ry), hexc("8a6210"))
        self.grad_mask(self.ell_mask(cx, cy, rx, ry), hexc("ffe48a"), hexc("d9a426"), (0, cy - ry, 0, cy + ry))

    def stack(self, cx, base, n, rx=9, ry=3.4):
        for i in range(n):
            self.coin_side(cx, base - i * 3.3, rx, ry)

    def slot(self, x, y, s, quality, kind):
        """An item in a bag slot: a dark square with a quality border and a simple glyph."""
        self.rr((x, y, x + s, y + s), 2.2, quality, None)
        self.grad_mask(self.rr_mask((x + 1.5, y + 1.5, x + s - 1.5, y + s - 1.5), 1.5), hexc("3a2a1c"), hexc("120a05"),
                       (0, y, 0, y + s))
        cx, cy, u = x + s / 2, y + s / 2, s / 16
        if kind == "potion":
            self.dot(cx, cy + 2 * u, 4.5 * u, hexc("d8333a"))
            self.rr((cx - 1.6 * u, cy - 6 * u, cx + 1.6 * u, cy - 1 * u), 0.6 * u, hexc("c9b48f"))
            self.dot(cx - 1.5 * u, cy + 0.5 * u, 1.3 * u, hexc("ffb0a0"))
        elif kind == "gem":
            self.poly([(cx, cy - 5.5 * u), (cx + 5 * u, cy - 1 * u), (cx, cy + 5.5 * u), (cx - 5 * u, cy - 1 * u)],
                      hexc("b05cff"))
            self.poly([(cx, cy - 5.5 * u), (cx + 5 * u, cy - 1 * u), (cx, cy)], hexc("e0b0ff"))
        elif kind == "ore":
            self.poly([(cx - 5 * u, cy + 3 * u), (cx - 3 * u, cy - 3 * u), (cx + 2 * u, cy - 4.5 * u),
                       (cx + 5 * u, cy + 1 * u), (cx + 2 * u, cy + 4.5 * u)], hexc("8f8a84"))
            self.dot(cx, cy - 1 * u, 1.4 * u, hexc("f0c060"))
            self.dot(cx + 2.4 * u, cy + 1.5 * u, 1.0 * u, hexc("f0c060"))
        elif kind == "cloth":
            self.poly([(cx - 5 * u, cy - 4 * u), (cx + 5 * u, cy - 5 * u), (cx + 4 * u, cy + 5 * u),
                       (cx - 4.5 * u, cy + 4 * u)], hexc("cfc4a8"))
            self.line([(cx - 3.5 * u, cy - 0.5 * u), (cx + 3.5 * u, cy - 1.5 * u)], hexc("9a8e70"), 0.9 * u)
        elif kind == "sword":
            self.line([(cx - 4.5 * u, cy + 4.5 * u), (cx + 5 * u, cy - 5 * u)], hexc("d8dde4"), 2.2 * u)
            self.line([(cx - 4.5 * u, cy + 1 * u), (cx - 1 * u, cy + 4.5 * u)], hexc("c9a24a"), 1.8 * u)
        elif kind == "helm":
            dome = self.ell_mask(cx, cy, 5.5 * u, 6 * u)
            self.grad_mask(dome, hexc("dfe4ea"), hexc("7d848e"), (0, cy - 6 * u, 0, cy + 6 * u))
            self.rr((cx - 4.2 * u, cy - 0.8 * u, cx + 4.2 * u, cy + 0.9 * u), 0.6 * u, hexc("1c110a"))
            self.rr((cx - 0.7 * u, cy + 0.9 * u, cx + 0.7 * u, cy + 5 * u), 0.4 * u, hexc("1c110a"))
            self.line([(cx, cy - 6 * u), (cx, cy - 8 * u)], hexc("c41e3a"), 1.6 * u)
        elif kind == "herb":
            self.line([(cx, cy + 5 * u), (cx, cy - 2 * u)], hexc("4f8a3a"), 1.1 * u)
            for dx, dy in ((-3, -2), (3, -3), (-2.5, 2), (2.5, 1)):
                self.fill_mask(self.ell_mask(cx + dx * u, cy + dy * u, 2.4 * u, 1.4 * u), hexc("6fc05a"))

    def magnifier(self, cx, cy, r, color=None, glass=True):
        color = color or INK["gold2"]
        c, s = math.cos(math.pi / 4), math.sin(math.pi / 4)
        self.line([(cx + r * c * 0.95, cy + r * s * 0.95), (cx + r * c * 2.0, cy + r * s * 2.0)], hexc("3b2614"), r * 0.5)
        self.line([(cx + r * c * 1.05, cy + r * s * 1.05), (cx + r * c * 1.95, cy + r * s * 1.95)], color, r * 0.34)
        m = self.ell_mask(cx, cy, r)
        self.shadow(m, 2, (0, 1.5), 0.5)
        self.fill_mask(m, color)
        if glass:
            self.grad_mask(self.ell_mask(cx, cy, r * 0.78), hexc("9fd4e0", 150), hexc("2c4a58", 190), (0, cy - r, 0, cy + r))
            self.fill_mask(self.ell_mask(cx - r * 0.25, cy - r * 0.3, r * 0.28, r * 0.18), hexc("ffffff", 140))
        else:
            self.fill_mask(self.ell_mask(cx, cy, r * 0.72), hexc("1c110a"))

    def gear(self, cx, cy, r, color):
        pts = []
        teeth = 8
        for i in range(teeth * 4):
            a = 2 * math.pi * i / (teeth * 4)
            rr = r if (i % 4) in (0, 1) else r * 0.74
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        self.poly(pts, color)
        self.dot(cx, cy, r * 0.32, hexc("1c110a"))

    def toggle(self, x, y, on, w=22, h=11):
        self.rr((x, y, x + w, y + h), h / 2, INK["green"] if on else hexc("3a2a1c"), INK["metal2"] if on else INK["metal"], 1.1)
        cx = x + w - h / 2 if on else x + h / 2
        self.dot(cx, y + h / 2, h / 2 - 2, hexc("f6ecd2") if on else INK["soft"])

    def flame(self, cx, base, s, glow=True):
        """A campfire: crossed logs and a flame, with its warm light."""
        if glow:
            self.glow(cx, base - 6 * s, 60 * s, INK["flame"], 0.55)
            self.glow(cx, base - 4 * s, 26 * s, INK["ember"], 0.5)
        self.line([(cx - 9 * s, base + 2 * s), (cx + 9 * s, base - 2 * s)], hexc("5a3418"), 3.2 * s)
        self.line([(cx - 9 * s, base - 2 * s), (cx + 9 * s, base + 2 * s)], hexc("6b4020"), 3.2 * s)

        def tongue(dx, h, wd, col):
            self.poly([(cx + dx - wd, base - 1 * s), (cx + dx - wd * 0.9, base - h * 0.45), (cx + dx, base - h),
                       (cx + dx + wd * 0.9, base - h * 0.5), (cx + dx + wd, base - 1 * s)], col)
        tongue(0, 17 * s, 6.5 * s, hexc("e2501e"))
        tongue(-3 * s, 11 * s, 4 * s, hexc("ff8a2a"))
        tongue(2.5 * s, 13 * s, 4 * s, hexc("ff9a3c"))
        tongue(0, 8 * s, 3 * s, hexc("ffe08a"))

    def avatar(self, cx, cy, r, color):
        """A guildmate: a head and shoulders in a class colour, on a dark round."""
        self.chip(cx, cy, r, hexc("2a1a0e"), color)
        self.dot(cx, cy - r * 0.2, r * 0.32, color)
        m = self.ell_mask(cx, cy + r * 0.62, r * 0.58, r * 0.4)
        clip = self.ell_mask(cx, cy, r * 0.86)
        self.fill_mask(ImageChops.multiply(m, clip), color)

    def banner(self, cx, top, w, h, color, emblem=True):
        self.line([(cx - w / 2 - 4, top), (cx + w / 2 + 4, top)], INK["metal2"], 2.4)
        self.dot(cx - w / 2 - 4, top, 2.2, INK["gold2"])
        self.dot(cx + w / 2 + 4, top, 2.2, INK["gold2"])
        pts = [(cx - w / 2, top + 1), (cx + w / 2, top + 1), (cx + w / 2, top + h), (cx, top + h - w * 0.32),
               (cx - w / 2, top + h)]
        m = self.poly_mask(pts)
        self.shadow(m, 3, (1.5, 2.5), 0.6)
        self.grad_mask(m, mix(color, hexc("ffffff"), 0.12), mix(color, hexc("000000"), 0.35), (0, top, 0, top + h))
        trim = self.poly_mask([(cx - w / 2 + 2.5, top + 1), (cx + w / 2 - 2.5, top + 1), (cx + w / 2 - 2.5, top + h - 5),
                               (cx, top + h - w * 0.32 - 4), (cx - w / 2 + 2.5, top + h - 5)])
        self.fill_mask(ImageChops.subtract(m, trim), INK["metal2"], 0.85)
        if emblem:
            self.poly(self.shield_pts(cx, top + h * 0.42, w / 22), INK["gold2"])
            self.poly(self.shield_pts(cx, top + h * 0.42, w / 34), mix(color, hexc("000000"), 0.2))

    def seal(self, cx, cy, r):
        pts = []
        rnd = random.Random(int(cx * 13 + cy))
        for i in range(18):
            a = 2 * math.pi * i / 18
            rr = r * (1 + rnd.uniform(-0.08, 0.12))
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        m = self.poly_mask(pts)
        self.shadow(m, 1.5, (0, 1.5), 0.6)
        self.grad_mask(m, hexc("c4382a"), hexc("6e120c"), (0, cy - r, 0, cy + r))
        self.fill_mask(self.ell_mask(cx, cy, r * 0.62), hexc("7e1610"))
        self.poly(self.shield_pts(cx, cy, r / 9.5), hexc("c9443a"))

    def lines(self, x, y, w, n, color, gap=7, h=3):
        for i in range(n):
            f = 0.6 if i == n - 1 else (0.86 if i % 2 else 1)
            self.bar(x, y + i * gap, w * f, h, color)

    def done(self):
        if self.bg is not None:
            # The scene, a little smaller, in the room's light, on the Salão's wood (laid under it last, at the
            # wood's own scale). What matters stays inside y 48..208, x 48..464.
            content = self.img
            # Glows that reach the edge fade out before it, so the inset shows no seam.
            fe = Image.new("L", (W, H), 0)
            fp = fe.load()
            for y in range(H):
                for x in range(W):
                    d = min(x, W - 1 - x, y, H - 1 - y)
                    fp[x, y] = int(255 * min(1.0, max(0.0, (d - 2) / 26.0)))
            fe = fe.resize(content.size, Image.BILINEAR)
            content.putalpha(ImageChops.multiply(content.getchannel("A"), fe))
            self.img = Image.new("RGBA", content.size, (0, 0, 0, 0))
            self._light(self.bg)
            sw, sh = int(content.size[0] * INSET), int(content.size[1] * INSET)
            small = content.resize((sw, sh), Image.LANCZOS)
            lay = self.layer()
            lay.paste(small, ((content.size[0] - sw) // 2, (content.size[1] - sh) // 2))
            self.img = Image.alpha_composite(self.img, lay)
        out = self.img.resize((W, H), Image.LANCZOS)
        return on_wood(out).convert("RGBA") if self.bg is not None else out


# ----------------------------------------------------------------------------------------------------------
# The pictures
# ----------------------------------------------------------------------------------------------------------
def p_salao():
    p = Pic(1)
    p.wood()
    # The room bar on top: arched doors, the Hall's one lit.
    p.dark_panel((40, 42, 472, 72), 6)
    xs = [92, 160, 228, 296, 364, 432]
    for i, x in enumerate(xs):
        lit = i == 2
        if lit:
            p.glow(x, 56, 60, INK["ember"], 0.55)
        door = [(x - 11, 66), (x - 11, 55)] + [(x + 11 * math.cos(math.pi - a * math.pi / 10), 55 - 9 * math.sin(math.pi - a * math.pi / 10)) for a in range(11)] + [(x + 11, 66)]
        p.poly(door, INK["gold2"] if lit else INK["metal"])
        inner = [(x - 8, 66), (x - 8, 56)] + [(x + 8 * math.cos(math.pi - a * math.pi / 10), 56 - 6.5 * math.sin(math.pi - a * math.pi / 10)) for a in range(11)] + [(x + 8, 66)]
        p.poly(inner, hexc("ffcf6a") if lit else hexc("140b05"))
        if lit:
            p.bar(x - 16, 67, 32, 2.4, INK["gold"])
    # Left: the notices board, parchment notes pinned to it.
    p.dark_panel((44, 82, 178, 210), 5, hexc("4a2e18"))
    for (x, y, w, h, pin) in ((54, 92, 56, 50, INK["red2"]), (116, 90, 54, 40, hexc("3f8fd0")), (56, 150, 50, 50, hexc("6ee860")),
                              (112, 138, 58, 62, INK["red2"])):
        p.parchment((x, y, x + w, y + h), 2, frame=False)
        p.lines(x + 7, y + 12, w - 14, max(2, int((h - 16) / 8)), INK["paperLine"], 8, 3)
        p.dot(x + w / 2, y + 4, 3.2, pin)
        p.dot(x + w / 2 - 0.8, y + 3.2, 1.0, hexc("ffffff", 160))
    # Centre: the hearth, guildmates by the fire.
    p.glow(256, 170, 140, INK["flame"], 0.55)
    stone = p.poly_mask([(196, 210), (196, 120), (206, 96), (256, 84), (306, 96), (316, 120), (316, 210)])
    p.shadow(stone, 5, (0, 3), 0.7)
    p.grad_mask(stone, INK["stone2"], INK["stone"], (0, 84, 0, 210))
    for y in range(100, 210, 14):
        p.line([(198, y), (314, y)], hexc("4a443c"), 1)
    mouth = p.poly_mask([(214, 210), (214, 140), (222, 120), (256, 110), (290, 120), (298, 140), (298, 210)])
    p.fill_mask(mouth, hexc("1a0d06"))
    p.glow(256, 184, 70, INK["flame"], 0.8)
    p.flame(256, 198, 2.1, glow=False)
    p.rr((188, 80, 324, 88), 3, hexc("5a3418"), INK["metal2"], 1)
    # Right: the guild wall, a banner and posts.
    p.parchment((334, 82, 468, 210), 5)
    p.banner(358, 92, 26, 50, hexc("7a1c14"))
    for i, c in enumerate((CLASS[7], CLASS[2], CLASS[6])):
        y = 98 + i * 36
        p.avatar(392, y + 8, 9, c)
        p.lines(406, y + 2, 52, 2, INK["paperLine"], 8, 3)
    # Guildmates by the fire, in front.
    for x, c in ((180, CLASS[5]), (332, CLASS[3])):
        p.avatar(x, 196, 11, c)
    return p.done()


def p_search():
    p = Pic(2)
    p.wood()
    # The search field, a typed query and the caret.
    p.dark_panel((80, 46, 400, 80), 9, hexc("1c110a"), INK["metal2"])
    p.magnifier(102, 61, 7.5, INK["gold2"], glass=False)
    p.bar(122, 60, 92, 5, INK["soft"])
    p.bar(218, 55, 2, 15, INK["gold"])
    # The results.
    p.dark_panel((80, 86, 400, 212), 6)
    rows = [("person", CLASS[7]), ("item", INK["purple"]), ("recipe", INK["rare"]), ("setting", INK["soft"])]
    for i, (kind, c) in enumerate(rows):
        y = 92 + i * 30
        if i == 0:
            p.grad_mask(p.rr_mask((86, y, 394, y + 26), 4), hexc("ffd77a", 70), hexc("ffd77a", 30), (0, y, 0, y + 26))
            p.rr((86, y, 89, y + 26), 1.5, INK["gold"])
        if kind == "person":
            p.avatar(106, y + 13, 10, c)
            p.bar(124, y + 8, 96, 5, c)
            p.bar(124, y + 16, 56, 3, INK["tan"])
            p.chip(372, y + 13, 7, hexc("1f4f2a"), INK["greenLit"])
            p.poly(p.shield_pts(372, y + 13, 0.8), hexc("7fe07a"))
        elif kind == "item":
            p.slot(95, y + 2, 22, INK["purple"], "sword")
            p.bar(124, y + 8, 120, 5, c)
            p.bar(124, y + 16, 70, 3, INK["tan"])
        elif kind == "recipe":
            p.parchment((96, y + 4, 116, y + 22), 2, frame=False)
            p.line([(100, y + 10), (112, y + 10)], INK["paperLine"], 1.2)
            p.line([(100, y + 15), (110, y + 15)], INK["paperLine"], 1.2)
            p.bar(124, y + 8, 84, 5, c)
            p.bar(124, y + 16, 60, 3, INK["tan"])
        else:
            p.gear(106, y + 13, 9, INK["soft"])
            p.bar(124, y + 10, 76, 5, c)
            p.toggle(362, y + 7, True, 24, 12)
    # The big magnifier, lit.
    p.glow(448, 108, 80, INK["gold2"], 0.35)
    p.magnifier(440, 104, 24, INK["gold2"])
    # And the guild's own, left: a few people found.
    for i, c in enumerate((CLASS[1], CLASS[5], CLASS[2])):
        p.orb(46, 104 + i * 30, 6.5, c)
    return p.done()


def p_officers():
    p = Pic(3)
    p.wood()
    # The recruitment post: a poster with the guild's banner and the roles wanted.
    p.parchment((48, 44, 170, 212), 5)
    p.banner(109, 54, 34, 58, hexc("7a1c14"))
    p.lines(64, 124, 90, 3, INK["paperLine"], 9, 3.5)
    for i, r in enumerate(("T", "H", "D")):
        p.role(78 + i * 31, 168 + 22 * 0, 11, r)
    p.bar(64, 190, 90, 12, INK["green"])
    p.check(109, 196, 0.9, hexc("f6ecd2"))
    # The horn that posts it everywhere, its call spreading.
    hx, hy = 214, 128
    horn = [(186, hy - 6), (232, hy - 22), (240, hy - 26), (244, hy - 8), (244, hy + 8), (240, hy + 26), (232, hy + 22), (186, hy + 6)]
    m = p.poly_mask(horn)
    p.shadow(m, 3, (0, 2), 0.6)
    p.grad_mask(m, INK["gold2"], hexc("8a6210"), (0, hy - 26, 0, hy + 26))
    p.rr((180, hy - 7, 190, hy + 7), 3, INK["metal"])
    for i in range(3):
        a0, rr = -0.7, 16 + i * 11
        pts = [(246 + rr * math.cos(a0 + t * 1.4 / 10) - 6, hy + rr * math.sin(a0 + t * 1.4 / 10)) for t in range(11)]
        p.line(pts, hexc("ffd77a", 220 - i * 50), 2.4)
    # The channels it reaches: chat bubbles in their colours.
    for i, c in enumerate((hexc("40ff40"), hexc("ffc0c0"), hexc("7fb2ff"), hexc("ff9a3c"))):
        y = 50 + i * 41
        x0 = 296
        p.dark_panel((x0, y, x0 + 130, y + 30), 8)
        p.poly([(x0 + 6, y + 26), (x0 - 4, y + 36), (x0 + 18, y + 29)], INK["metal"])
        p.dot(x0 + 14, y + 15, 5, c)
        p.bar(x0 + 26, y + 9, 80 - i * 6, 4, mix(c, hexc("f6ecd2"), 0.35))
        p.bar(x0 + 26, y + 18, 54, 3, INK["tan"])
        p.chip(x0 + 130 + 14, y + 15, 9, hexc("1f4f2a"), INK["greenLit"])
        p.check(x0 + 144, y + 15, 0.85, hexc("bff5b8"))
    return p.done()


def p_members():
    p = Pic(4)
    p.wood()
    # The big numbers on top: guildmates, online now, running Guild OS.
    for i, (icon, c) in enumerate((("people", INK["gold2"]), ("online", INK["greenLit"]), ("crest", INK["greenLit"]))):
        x = 44 + i * 86
        p.dark_panel((x, 44, x + 78, 80), 6)
        if icon == "people":
            p.avatar(x + 18, 62, 10, CLASS[3])
        elif icon == "online":
            p.orb(x + 18, 62, 6, INK["greenLit"])
        else:
            p.chip(x + 18, 62, 10, hexc("1f4f2a"), INK["greenLit"])
            p.poly(p.shield_pts(x + 18, 62, 1.1), hexc("7fe07a"))
        p.bar(x + 34, 55, 34 - i * 4, 8, INK["gold2"])
        p.bar(x + 34, 67, 26, 3, INK["tan"])
    # The roster: a row per member, the class's colour and crest.
    p.dark_panel((44, 88, 300, 212), 6)
    for i, c in enumerate((CLASS[0], CLASS[6], CLASS[2], CLASS[4], CLASS[7])):
        y = 94 + i * 23.5
        if i == 1:
            p.rr((50, y, 294, y + 21), 4, hexc("ffd77a", 45))
        p.chip(62, y + 10.5, 8, mix(c, hexc("000000"), 0.45), c)
        p.poly(p.shield_pts(62, y + 10.5, 0.75), c)
        p.bar(76, y + 8, 76 - (i % 3) * 12, 5, c)
        p.bar(170, y + 9, 30, 3, INK["tan"])
        p.dot(222, y + 10.5, 3.4, INK["greenLit"] if i != 3 else hexc("5a4a38"))
        if i in (0, 1, 4):
            p.chip(280, y + 10.5, 6.5, hexc("1f4f2a"), INK["greenLit"])
    # The member's own window: portrait and equipment.
    p.parchment((320, 44, 468, 212), 6)
    p.glow(394, 80, 60, CLASS[6], 0.35)
    p.avatar(394, 80, 24, CLASS[6])
    p.gold_frame((368, 54, 420, 106), 26, 2.2)
    p.bar(352, 114, 84, 6, hexc("6a63c8"))
    gear = [(INK["purple"], "helm"), (INK["rare"], "sword"), (INK["purple"], "gem"), (INK["uncommon"], "cloth"),
            (INK["rare"], "potion"), (INK["purple"], "ore")]
    for i, (q, kind) in enumerate(gear):
        col, row = i % 3, i // 3
        p.slot(340 + col * 38, 128 + row * 38, 32, q, kind)
    return p.done()


def p_raids():
    p = Pic(5)
    p.wood()
    # The calendar: a sheet with its rings, the raid night marked.
    p.parchment((40, 44, 210, 212), 5)
    p.grad_mask(p.rr_mask((40, 44, 210, 68), 5), hexc("9b2216"), hexc("6e170e"), (0, 44, 0, 68))
    for x in (78, 172):
        p.rr((x - 3, 38, x + 3, 54), 3, INK["metal2"])
    for i in range(28):
        col, row = i % 7, i // 7
        x, y = 48 + col * 22.5, 76 + row * 33
        ev = i == 17
        if ev:
            p.glow(x + 9, y + 13, 50, INK["red2"], 0.45)
            p.rr((x - 1, y - 1, x + 20, y + 28), 3, INK["red"], INK["gold2"], 1.4)
            p.sword(x + 9.5, y + 13.5, 1.6, math.pi / 4, hexc("f6ecd2"), INK["gold2"])
            p.sword(x + 9.5, y + 13.5, 1.6, -math.pi / 4, hexc("f6ecd2"), INK["gold2"])
        else:
            p.rr((x, y, x + 19, y + 27), 2.5, hexc("e8d6ab"), hexc("c9ad78"), 0.9)
            if i in (3, 10, 24):
                p.dot(x + 9.5, y + 14, 3, INK["paperInk"])
    # The sign-ups: a role each, and a mark.
    p.dark_panel((222, 44, 342, 212), 6)
    for i, (r, c, ok) in enumerate((("T", CLASS[0], True), ("H", CLASS[4], True), ("D", CLASS[7], True),
                                    ("D", CLASS[5], False), ("H", CLASS[2], True))):
        y = 62 + i * 32
        p.role(242, y, 11, r)
        p.bar(258, y - 5, 46 - (i % 2) * 10, 5, c)
        p.bar(258, y + 3, 30, 3, INK["tan"])
        if ok:
            p.check(326, y, 0.9, INK["greenLit"])
        else:
            p.dot(326, y, 4, hexc("f0b850"))
    # The group cards: the one that fits washed green.
    for i, fits in enumerate((True, False)):
        y = 44 + i * 88
        p.parchment((354, y, 470, y + 80), 5)
        if fits:
            p.grad_mask(p.rr_mask((354, y, 470, y + 80), 5), hexc("4fd04a", 110), hexc("2f8a3a", 70), (0, y, 0, y + 80))
            p.gold_frame((354, y, 470, y + 80), 5, 1.6)
        p.lines(366, y + 12, 70, 2, INK["paperLine"], 9, 4)
        for j, r in enumerate(("T", "H", "D")):
            p.role(374 + j * 24, y + 52, 9, r)
        if fits:
            p.chip(450, y + 52, 10, INK["green"], INK["greenLit"])
            p.check(450, y + 52, 0.95, hexc("f6ecd2"))
    return p.done()


def _coast(cx, cy, rx, ry, seed, n=46):
    rnd = random.Random(seed)
    amp = [rnd.uniform(0, 0.16) for _ in range(5)]
    ph = [rnd.uniform(0, 6.28) for _ in range(5)]
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        f = 1 + sum(amp[j] * math.sin((j + 2) * a + ph[j]) for j in range(5)) + rnd.uniform(-0.04, 0.04)
        pts.append((cx + rx * f * math.cos(a), cy + ry * f * math.sin(a)))
    return pts


def p_map(fires=False):
    p = Pic(6)
    # The sea: aged blue-green parchment.
    p.fill_mask(p.rr_mask((0, 0, W, H), 0), hexc("8fae9e"))
    p.fill_mask(p.noise_mask((0, 0, W, H), 0.6, 61, 0.5), hexc("4d6d62"), 0.5)
    p.glow(256, 128, 520, hexc("c8dcc6"), 0.45)
    # Waves.
    rnd = random.Random(62)
    for _ in range(26):
        x, y = rnd.uniform(10, 500), rnd.uniform(10, 246)
        p.line([(x, y), (x + 4, y - 2), (x + 8, y), (x + 12, y - 2)], hexc("5d8173", 160), 1)
    lands = [(140, 128, 104, 70, 7), (378, 104, 82, 56, 11), (360, 200, 50, 24, 13), (60, 36, 40, 18, 17),
             (480, 230, 40, 26, 19)]
    for cx, cy, rx, ry, seed in lands:
        pts = _coast(cx, cy, rx, ry, seed)
        m = p.poly_mask(pts)
        # The shallows, then the land, then the ink line.
        p.fill_mask(m.filter(ImageFilter.MaxFilter(k(6) | 1)).filter(ImageFilter.GaussianBlur(k(3))), hexc("b6cdb3"), 0.9)
        p.fill_mask(m.filter(ImageFilter.MaxFilter(k(1.6) | 1)), hexc("5a4325"))
        p.grad_mask(m, hexc("e6d6a8"), hexc("cdb882"), (0, cy - ry, 0, cy + ry))
        p.fill_mask(ImageChops.multiply(p.noise_mask((0, 0, W, H), 0.5, seed, 0.5), m), hexc("8a6a3a"), 0.35)
    # Forests and mountains.
    for x, y in ((100, 110), (112, 118), (92, 124), (180, 148), (170, 158), (400, 92), (410, 100)):
        p.dot(x, y, 5, hexc("6f8a4a"))
        p.dot(x - 1, y - 1.5, 3, hexc("8aa55c"))
    for x, y in ((150, 96), (166, 102), (134, 100), (360, 116), (376, 120)):
        p.poly([(x - 9, y + 6), (x, y - 9), (x + 9, y + 6)], hexc("8f7552"))
        p.poly([(x, y - 9), (x + 9, y + 6), (x + 2, y + 6)], hexc("6b5536"))
        p.poly([(x - 3, y - 4), (x, y - 9), (x + 3, y - 4)], hexc("f3ead0"))
    # A road between them.
    p.line([(110, 150), (140, 140), (176, 128), (210, 120)], hexc("8a6a3a", 200), 1.4)
    # The compass.
    cx, cy = 468, 46
    p.dot(cx, cy, 15, hexc("e6d6a8", 200))
    p.poly([(cx, cy - 16), (cx + 3.5, cy), (cx, cy + 16), (cx - 3.5, cy)], hexc("6b4a22"))
    p.poly([(cx - 16, cy), (cx, cy - 3.5), (cx + 16, cy), (cx, cy + 3.5)], hexc("6b4a22"))
    p.poly([(cx, cy - 16), (cx + 3.5, cy), (cx - 3.5, cy)], INK["red"])
    if fires:
        for x, y, s in ((206, 150, 0.9), (402, 132, 0.8)):
            p.flame(x, y, s)
    # Guildmates, a glowing dot each.
    for i, (x, y) in enumerate(((102, 140), (150, 118), (190, 108), (126, 168), (352, 96), (396, 112), (420, 90),
                                (226, 132), (372, 196))):
        p.orb(x, y, 7, CLASS[i % len(CLASS)])
    # The parchment's own edge, so the map reads as one.
    v = Image.new("L", (W, H), 0)
    vp = v.load()
    for y in range(H):
        for x in range(W):
            dx, dy = (x - 256) / 270, (y - 128) / 150
            vp[x, y] = int(255 * min(1, max(0, dx * dx + dy * dy - 0.55)))
    p.fill_mask(v.resize(p.img.size, Image.BILINEAR), hexc("3a2a14"), 0.7)
    return p.done()


def p_bank():
    p = Pic(7)
    p.wood()
    # The bank's bag: slots with items.
    p.dark_panel((40, 50, 176, 206), 6)
    kinds = ["potion", "ore", "herb", "cloth", "gem", "sword", "herb", "potion", "ore", "cloth", "helm", "gem"]
    quals = [INK["uncommon"], hexc("9d9d9d"), INK["uncommon"], hexc("9d9d9d"), INK["purple"], INK["rare"],
             INK["uncommon"], INK["rare"], hexc("9d9d9d"), INK["uncommon"], INK["purple"], INK["rare"]]
    for i in range(12):
        col, row = i % 3, i // 3
        p.slot(50 + col * 40, 58 + row * 36, 33, quals[i], kinds[i])
    # The chest, open, its gold lit.
    p.glow(258, 122, 150, INK["gold"], 0.45)
    body = (200, 120, 316, 196)
    m = p.rr_mask(body, 5)
    p.shadow(m, 6, (0, 4), 0.8)
    p.grad_mask(m, hexc("7a4a22"), hexc("3e2410"), (0, 120, 0, 196))
    for x in (200, 252, 304):
        p.rr((x, 120, x + 12, 196), 2, INK["metal"], INK["metal2"], 1)
    p.rr((198, 116, 318, 128), 3, INK["metal2"])
    lid = p.poly_mask([(204, 116), (210, 72), (306, 72), (312, 116)])
    p.grad_mask(lid, hexc("4a2c14"), hexc("6e4220"), (0, 72, 0, 116))
    p.rr((204, 68, 312, 76), 3, INK["metal2"])
    # Coins heaped in it.
    for cx, cy, r in ((224, 116, 11), (246, 110, 12), (270, 112, 12), (292, 116, 11), (236, 104, 10), (258, 100, 11),
                      (282, 104, 10), (258, 114, 11)):
        p.coin(cx, cy, r)
    p.rr((250, 140, 266, 158), 3, INK["metal2"])
    p.dot(258, 147, 2.4, hexc("1c110a"))
    # Coins and stacks spilling right, and the vendor's scale.
    p.stack(340, 196, 6)
    p.stack(362, 198, 4)
    p.coin(330, 168, 9)
    sx = 424
    p.line([(sx, 194), (sx, 100)], INK["metal2"], 3)
    p.rr((sx - 22, 192, sx + 22, 200), 3, INK["metal"], INK["metal2"], 1)
    p.line([(sx - 40, 112), (sx + 40, 104)], INK["metal2"], 3)
    p.dot(sx, 100, 4.5, INK["gold2"])
    for x, y, load in ((sx - 40, 112, "coin"), (sx + 40, 104, "item")):
        p.line([(x, y), (x - 12, y + 32)], INK["metal"], 1)
        p.line([(x, y), (x + 12, y + 32)], INK["metal"], 1)
        p.fill_mask(p.ell_mask(x, y + 33, 16, 4), INK["metal2"])
        if load == "coin":
            p.stack(x, y + 28, 3, 8, 3)
        else:
            p.slot(x - 10, y + 10, 20, INK["rare"], "potion")
    return p.done()


def p_light():
    p = Pic(8)
    p.wood()
    # A feather, floating in its light: lighter.
    p.glow(110, 128, 150, INK["gold2"], 0.4)
    spine = [(70, 196), (96, 160), (122, 120), (146, 80), (164, 56)]
    m = p.poly_mask([(78, 182), (84, 150), (100, 118), (124, 84), (150, 62), (164, 56), (170, 80), (164, 108), (146, 140),
                     (122, 166), (92, 180)])
    p.shadow(m, 4, (2, 4), 0.55)
    p.grad_mask(m, hexc("fbf2dc"), hexc("d6c39a"), (0, 56, 0, 182))
    p.line(spine, hexc("a88a5a"), 1.8)
    for i in range(9):
        t = (i + 1) / 10
        x, y = 70 + (164 - 70) * t, 196 - (196 - 56) * t
        p.line([(x, y), (x - 14 + t * 4, y - 6)], hexc("c9b48f"), 0.8)
        p.line([(x, y), (x + 12 - t * 2, y + 2)], hexc("c9b48f"), 0.8)
    # The gauge: the needle low, in the green.
    gx, gy, gr = 256, 170, 64
    p.dark_panel((182, 84, 330, 196), 8)
    for i in range(30):
        a0, a1 = math.pi + i * math.pi / 30, math.pi + (i + 1) * math.pi / 30
        t = i / 29
        col = mix(INK["greenLit"], hexc("f0b850"), min(1, t * 1.6)) if t < 0.62 else mix(hexc("f0b850"), INK["red2"], (t - 0.62) / 0.38)
        p.poly([(gx + gr * math.cos(a0), gy + gr * math.sin(a0)), (gx + gr * math.cos(a1), gy + gr * math.sin(a1)),
                (gx + (gr - 12) * math.cos(a1), gy + (gr - 12) * math.sin(a1)),
                (gx + (gr - 12) * math.cos(a0), gy + (gr - 12) * math.sin(a0))], col)
    a = math.pi + 0.22 * math.pi
    p.line([(gx, gy), (gx + (gr - 16) * math.cos(a), gy + (gr - 16) * math.sin(a))], INK["gold2"], 3)
    p.dot(gx, gy, 6, INK["metal2"])
    p.dot(gx, gy, 3, hexc("1c110a"))
    # The backup: a strongbox, a circle arrow, and seven days ticked.
    p.parchment((350, 50, 468, 206), 6)
    bx = 409
    p.glow(bx, 108, 50, INK["gold2"], 0.3)
    pts = [(bx + 30 * math.cos(a), 108 + 30 * math.sin(a)) for a in [math.pi * (0.15 + 1.55 * i / 24) for i in range(25)]]
    p.line(pts, INK["green"], 4.5)
    end = pts[-1]
    p.poly([(end[0] - 9, end[1] - 2), (end[0] + 6, end[1] - 10), (end[0] + 5, end[1] + 6)], INK["green"])
    box = (bx - 17, 96, bx + 17, 124)
    p.rr(box, 3, hexc("6e4220"), INK["metal2"], 1.6)
    p.rr((bx - 17, 104, bx + 17, 108), 0, INK["metal2"])
    p.rr((bx - 4, 106, bx + 4, 114), 1.5, INK["gold2"])
    for i in range(7):
        x = 362 + i * 14
        p.rr((x, 162, x + 11, 176), 2, hexc("e8d6ab"), INK["paperLine"], 0.9)
        p.check(x + 5.5, 169, 0.5, INK["green"])
    p.bar(362, 186, 94, 4, INK["paperLine"])
    return p.done()


def p_shield():
    p = Pic(9)
    p.wood()
    # What is shared, flowing to the guildmates: gear, a craft, the spec, the wishlist.
    items = [(INK["purple"], "helm"), (INK["uncommon"], "herb"), (INK["rare"], "sword"), (INK["purple"], "gem")]
    for i, (q, kind) in enumerate(items):
        x, y = 54 + (i % 2) * 40, 74 + (i // 2) * 46
        p.slot(x, y, 32, q, kind)
    for y in (96, 142):
        p.line([(140, y), (162, y)], hexc("ffd77a", 140), 1.6)
        p.poly([(162, y - 4), (170, y), (162, y + 4)], hexc("ffd77a", 160))
    for i, c in enumerate((CLASS[5], CLASS[2], CLASS[1])):
        p.avatar(70 + i * 30, 200, 10, c)
    # The shield, the guild's crest, lit.
    p.glow(256, 128, 170, INK["gold2"], 0.45)
    outer = p.shield_pts(256, 132, 13.5)
    m = p.poly_mask(outer)
    p.shadow(m, 6, (0, 4), 0.8)
    p.grad_mask(m, INK["gold2"], hexc("8a6210"), (0, 52, 0, 214))
    inner = p.poly_mask(p.shield_pts(256, 132, 11.6))
    p.grad_mask(inner, hexc("2f6a3a"), hexc("163a1e"), (0, 62, 0, 204))
    p.poly(p.shield_pts(256, 128, 6.2), hexc("7fe07a"))
    p.poly(p.shield_pts(256, 128, 4.4), hexc("2f6a3a"))
    # The keyhole of what stays locked.
    p.dot(256, 122, 5, hexc("f6ecd2"))
    p.poly([(252, 124), (260, 124), (262, 140), (250, 140)], hexc("f6ecd2"))
    # Right: the officers' note, sealed, and the lock.
    p.parchment((352, 64, 462, 176), 4)
    p.lines(364, 80, 84, 4, INK["paperLine"], 10, 4)
    p.seal(434, 156, 15)
    lx, ly = 384, 172
    p.line([(lx - 9, ly - 4), (lx - 9, ly - 16)] + [(lx + 9 * math.cos(math.pi - a * math.pi / 10), ly - 16 - 9 * math.sin(math.pi - a * math.pi / 10)) for a in range(11)] + [(lx + 9, ly - 4)], INK["metal2"], 3.4)
    p.rr((lx - 14, ly - 6, lx + 14, ly + 18), 4, INK["metal2"], hexc("8a6210"), 1.4)
    p.dot(lx, ly + 4, 3, hexc("3a2a1c"))
    p.rr((lx - 1.3, ly + 5, lx + 1.3, ly + 12), 1, hexc("3a2a1c"))
    return p.done()


def p_compact():
    p = Pic(10)
    p.wood()
    # The window, open: its title, the rooms and two cards.
    win = (44, 46, 214, 210)
    p.dark_panel(win, 6)
    p.rr((46, 48, 212, 66), 4, hexc("3e2816"))
    p.chip(58, 57, 6, hexc("1f4f2a"), INK["gold2"])
    p.bar(70, 55, 50, 4, INK["gold2"])
    for i in range(5):
        p.rr((54 + i * 31, 72, 79 + i * 31, 84), 6, INK["gold2"] if i == 0 else hexc("4a3420"))
    p.parchment((54, 92, 128, 200), 4, frame=False)
    p.lines(62, 102, 56, 5, INK["paperLine"], 9, 3.4)
    p.parchment((136, 92, 204, 146), 4, frame=False)
    p.lines(144, 102, 50, 3, INK["paperLine"], 9, 3.4)
    p.parchment((136, 152, 204, 200), 4, frame=False)
    p.avatar(152, 170, 8, CLASS[6])
    p.bar(164, 166, 30, 4, INK["paperLine"])
    # The fold: a curved arrow to the slim bar.
    pts = [(226 + 50 * t, 90 - 28 * math.sin(math.pi * t)) for t in [i / 20 for i in range(21)]]
    p.line(pts, INK["gold2"], 3.2)
    p.poly([(276, 82), (286, 94), (270, 96)], INK["gold2"])
    # The compact bar.
    p.dark_panel((290, 92, 470, 122), 15, hexc("2b1b0f"), INK["metal2"])
    p.chip(308, 107, 9, hexc("1f4f2a"), INK["gold2"])
    p.poly(p.shield_pts(308, 107, 0.9), INK["gold2"])
    p.orb(332, 107, 4.5, INK["red2"], glow=False)
    p.bar(344, 104, 66, 5, INK["soft"])
    p.magnifier(446, 105, 5.5, INK["soft"], glass=False)
    # The minimap and its button: another way in.
    mx, my = 362, 176
    p.glow(mx, my, 60, hexc("8fd0e0"), 0.2)
    m = p.ell_mask(mx, my, 30)
    p.shadow(m, 4, (0, 3), 0.7)
    p.fill_mask(m, INK["metal2"])
    p.fill_mask(p.ell_mask(mx, my, 27), hexc("5b7a4a"))
    p.fill_mask(ImageChops.multiply(p.poly_mask(_coast(mx + 8, my - 4, 16, 10, 5)), p.ell_mask(mx, my, 27)), hexc("7f9a5c"))
    p.fill_mask(ImageChops.multiply(p.ell_mask(mx - 14, my + 12, 14, 9), p.ell_mask(mx, my, 27)), hexc("4b7aa0"))
    p.poly([(mx, my - 5), (mx + 4, my + 5), (mx, my + 3), (mx - 4, my + 5)], hexc("f6ecd2"))
    bx, by = mx + 30 * math.cos(-0.8), my + 30 * math.sin(-0.8)
    p.glow(bx, by, 30, INK["gold2"], 0.5)
    p.chip(bx, by, 10, hexc("1f4f2a"), INK["gold2"])
    p.poly(p.shield_pts(bx, by, 1.0), INK["gold2"])
    # And a key, for the shortcut.
    p.rr((420, 154, 456, 190), 6, hexc("4a3420"), INK["metal2"], 1.6)
    p.rr((424, 157, 452, 183), 4, hexc("6e4c2c"))
    p.poly(p.shield_pts(438, 170, 1.15), INK["gold2"])
    return p.done()


def p_gm():
    p = Pic(11)
    p.wood()
    # The Guild Master's crown over the guild's banner.
    p.glow(92, 100, 120, INK["gold2"], 0.45)
    p.banner(92, 90, 56, 112, hexc("7a1c14"))
    cx, cy = 92, 64
    crown = [(cx - 24, cy + 14), (cx - 26, cy - 10), (cx - 13, cy + 1), (cx, cy - 18), (cx + 13, cy + 1),
             (cx + 26, cy - 10), (cx + 24, cy + 14)]
    m = p.poly_mask(crown)
    p.shadow(m, 3, (0, 2), 0.6)
    p.grad_mask(m, INK["gold2"], hexc("b07a14"), (0, cy - 18, 0, cy + 14))
    p.rr((cx - 25, cy + 10, cx + 25, cy + 17), 2, hexc("d39a1c"))
    for x, c in ((cx - 12, hexc("3f8fd0")), (cx, INK["red2"]), (cx + 12, hexc("3fae4a"))):
        p.dot(x, cy + 13.5, 2.6, c)
    for x, y in ((cx - 26, cy - 10), (cx, cy - 18), (cx + 26, cy - 10)):
        p.dot(x, y, 3, INK["gold2"])
    # The guild-wide settings: a few switches.
    p.dark_panel((160, 50, 300, 206), 6)
    for i, on in enumerate((True, True, False, True)):
        y = 64 + i * 36
        ic = [("bubble", INK["soft"]), ("coin", None), ("star", None), ("link", None)][i][0]
        if ic == "bubble":
            p.rr((172, y, 192, y + 14), 4, INK["soft"])
            p.poly([(176, y + 12), (174, y + 20), (182, y + 13)], INK["soft"])
        elif ic == "coin":
            p.coin(182, y + 8, 9)
        elif ic == "star":
            pts = [(182 + (9 if j % 2 == 0 else 4) * math.cos(-math.pi / 2 + j * math.pi / 5),
                    y + 8 + (9 if j % 2 == 0 else 4) * math.sin(-math.pi / 2 + j * math.pi / 5)) for j in range(10)]
            p.poly(pts, INK["gold2"])
        else:
            p.dot(182, y + 8, 8, hexc("3f8fd0"))
            p.line([(176, y + 8), (188, y + 8)], hexc("cfe6ff"), 1)
            p.line([(182, y + 1), (182, y + 15)], hexc("cfe6ff"), 1)
        p.bar(200, y + 5, 46 - (i % 2) * 12, 5, INK["soft"])
        p.toggle(258, y + 2, on, 30, 14)
    # The bank tax: a coin with its percent.
    tx, ty = 338, 98
    p.glow(tx, ty, 70, INK["gold"], 0.4)
    p.coin(tx, ty, 26, mark=False)
    p.fill_mask(p.ell_mask(tx, ty, 18), hexc("e9b33a"))
    ink = hexc("6e4a0e")
    p.fill_mask(p.ell_mask(tx - 7, ty - 7, 4.5), ink)
    p.fill_mask(p.ell_mask(tx - 7, ty - 7, 2), hexc("e9b33a"))
    p.fill_mask(p.ell_mask(tx + 7, ty + 7, 4.5), ink)
    p.fill_mask(p.ell_mask(tx + 7, ty + 7, 2), hexc("e9b33a"))
    p.line([(tx + 9, ty - 11), (tx - 9, ty + 11)], ink, 3)
    p.stack(338, 196, 5, 14, 4.5)
    # The link to the site: a chain to a browser page.
    for i, (x, y) in enumerate(((374, 150), (388, 142))):
        ring = ImageChops.subtract(p.ell_mask(x, y, 9, 5.5), p.ell_mask(x, y, 6, 2.8))
        p.grad_mask(ring, hexc("e0e4ea"), hexc("7d848e"), (0, y - 6, 0, y + 6))
    p.dark_panel((398, 60, 470, 200), 6, hexc("e9dcc0"), INK["metal2"])
    p.rr((400, 62, 468, 76), 4, hexc("3e2816"))
    for j, c in enumerate((INK["red2"], hexc("f0b850"), INK["greenLit"])):
        p.dot(408 + j * 8, 69, 2.4, c)
    p.chip(434, 102, 16, hexc("1f4f2a"), INK["gold2"])
    p.poly(p.shield_pts(434, 102, 1.7), INK["gold2"])
    p.lines(410, 130, 48, 4, hexc("b89a62"), 10, 4)
    return p.done()


def p_departure():
    p = Pic(12)
    p.wood()
    # The door, open, a figure leaving and the light outside.
    dx, dy = 104, 210
    arch = [(dx - 38, dy), (dx - 38, dy - 100)] + [(dx + 38 * math.cos(math.pi - a * math.pi / 16), dy - 100 - 30 * math.sin(math.pi - a * math.pi / 16)) for a in range(17)] + [(dx + 38, dy)]
    m = p.poly_mask(arch)
    p.shadow(m, 5, (0, 3), 0.7)
    p.fill_mask(m, INK["stone"])
    inner = [(dx - 30, dy), (dx - 30, dy - 98)] + [(dx + 30 * math.cos(math.pi - a * math.pi / 16), dy - 98 - 24 * math.sin(math.pi - a * math.pi / 16)) for a in range(17)] + [(dx + 30, dy)]
    im = p.poly_mask(inner)
    p.grad_mask(im, hexc("ffe9a8"), hexc("f5b85a"), (0, 80, 0, 210))
    p.glow(dx, 170, 90, INK["ember"], 0.4)
    # The open leaf, swung in.
    leaf = p.poly_mask([(dx - 30, dy), (dx - 30, dy - 98), (dx - 8, dy - 112), (dx - 8, dy - 12)])
    p.grad_mask(leaf, hexc("6e4220"), hexc("3e2410"), (0, 90, 0, 210))
    p.dot(dx - 13, dy - 56, 2.6, INK["metal2"])
    # The one leaving, a silhouette in the light.
    p.dot(dx + 12, dy - 72, 7, hexc("2a1a0e"))
    p.poly([(dx + 2, dy - 4), (dx + 4, dy - 60), (dx + 20, dy - 60), (dx + 24, dy - 4)], hexc("2a1a0e"))
    # Footprints out.
    for i in range(4):
        x, y = 168 + i * 20, 204 - (i % 2) * 6
        p.fill_mask(p.ell_mask(x, y, 4, 2.4), hexc("1a0d06"), 0.75)
    # The departure's popup: the note, the ban, the alts.
    p.parchment((198, 46, 340, 206), 5)
    p.avatar(222, 72, 13, CLASS[7])
    p.bar(242, 64, 70, 6, hexc("c86a10"))
    p.bar(242, 75, 44, 3.5, INK["paperLine"])
    p.lines(212, 98, 112, 3, INK["paperLine"], 9, 3.5)
    # Its alts, chained.
    for i, c in enumerate((CLASS[2], CLASS[5])):
        p.avatar(222 + i * 34, 146, 9, c)
    ring = ImageChops.subtract(p.ell_mask(239, 146, 7, 4), p.ell_mask(239, 146, 4.5, 2))
    p.fill_mask(ring, INK["metal2"])
    # The ban, a red seal with its cross.
    p.chip(312, 146, 14, INK["red"], INK["gold2"])
    p.line([(306, 140), (318, 152)], hexc("f6ecd2"), 2.6)
    p.line([(318, 140), (306, 152)], hexc("f6ecd2"), 2.6)
    p.rr((212, 176, 270, 194), 5, INK["red"], INK["gold2"], 1.2)
    p.rr((278, 176, 326, 194), 5, hexc("e8d6ab"), INK["paperLine"], 1.2)
    # The return: the circle arrow, green, and a welcome back.
    rx, ry = 410, 128
    p.glow(rx, ry, 110, INK["greenLit"], 0.3)
    pts = [(rx + 44 * math.cos(a), ry + 44 * math.sin(a)) for a in [math.pi * (-0.1 + 1.6 * i / 30) for i in range(31)]]
    p.line(pts, INK["greenLit"], 6)
    s = pts[0]
    p.poly([(s[0] - 11, s[1] + 2), (s[0] + 11, s[1] + 2), (s[0], s[1] - 12)], INK["greenLit"])
    p.avatar(rx, ry, 24, CLASS[7])
    p.chip(rx + 24, ry + 22, 10, hexc("1f4f2a"), INK["greenLit"])
    p.check(rx + 24, ry + 22, 0.85, hexc("bff5b8"))
    return p.done()


def p_notes():
    p = Pic(13)
    p.wood()
    # A scroll unrolled: the release's notes, a mark on each.
    p.glow(250, 120, 220, INK["ember"], 0.25)
    sheet = (150, 54, 362, 202)
    p.parchment(sheet, 2)
    for y, top in ((50, True), (206, False)):
        rod = p.rr_mask((136, y - 9, 376, y + 9), 9)
        p.shadow(rod, 3, (0, 2.5), 0.6)
        p.grad_mask(rod, hexc("e9d4a2"), hexc("a88452"), (0, y - 9, 0, y + 9))
        for x in (136, 376):
            p.chip(x, y, 9, hexc("6e4220"), INK["metal2"])
    marks = [INK["greenLit"], INK["gold2"], hexc("7fb2ff"), INK["greenLit"], INK["gold2"]]
    for i, c in enumerate(marks):
        y = 76 + i * 23
        p.dot(176, y + 2, 5, mix(c, hexc("000000"), 0.35))
        p.dot(176, y + 2, 3.5, c)
        p.bar(188, y, 136 - (i % 3) * 22, 4.5, INK["paperInk"])
    p.seal(334, 182, 17)
    # The version's ribbon: a banner across the corner.
    p.banner(404, 58, 40, 96, hexc("7a1c14"))
    for i in range(3):
        p.dot(392 + i * 12, 152 + 18, 3.2, INK["gold2"])
    # A quill, left, still wet.
    q = p.poly_mask([(60, 196), (80, 150), (104, 104), (126, 72), (134, 70), (126, 98), (106, 140), (84, 174)])
    p.shadow(q, 3, (2, 3), 0.5)
    p.grad_mask(q, hexc("f6ecd2"), hexc("c9b48f"), (0, 70, 0, 196))
    p.line([(56, 206), (78, 162), (104, 116), (132, 72)], hexc("8a6a3a"), 1.4)
    p.fill_mask(p.ell_mask(74, 210, 16, 5), hexc("1a0d06"), 0.85)
    for x, y in ((452, 196), (466, 70)):
        p.glow(x, y, 30, INK["gold2"], 0.4)
        pts = [(x + (7 if j % 2 == 0 else 2.4) * math.cos(-math.pi / 2 + j * math.pi / 4),
                y + (7 if j % 2 == 0 else 2.4) * math.sin(-math.pi / 2 + j * math.pi / 4)) for j in range(8)]
        p.poly(pts, INK["gold2"])
    return p.done()


def p_done():
    p = Pic(14)
    p.wood()
    # The tour done: a medal on its ribbon, a check on its face, laurels and sparks around it.
    cx, cy = 256, 140
    p.glow(cx, cy, 150, INK["gold2"], 0.5)
    for side in (-1, 1):
        p.poly([(cx + side * 6, 40), (cx + side * 30, 40), (cx + side * 22, 104), (cx + side * 2, 100)],
               hexc("7a1c14") if side < 0 else hexc("8f2418"))
        p.line([(cx + side * 14, 42), (cx + side * 9, 100)], INK["gold2"], 1.4)
    for side in (-1, 1):
        for i in range(7):
            a = math.pi / 2 + side * (0.55 + i * 0.27)
            lx, ly = cx + 66 * math.cos(a) * -1, cy + 66 * math.sin(a) * -1
            ang = a + side * 0.9
            p.fill_mask(p.poly_mask([(lx + 10 * math.cos(ang), ly + 10 * math.sin(ang)),
                                     (lx + 3.5 * math.cos(ang + 1.57), ly + 3.5 * math.sin(ang + 1.57)),
                                     (lx - 6 * math.cos(ang), ly - 6 * math.sin(ang)),
                                     (lx + 3.5 * math.cos(ang - 1.57), ly + 3.5 * math.sin(ang - 1.57))]),
                        hexc("8fbf5a") if i % 2 else hexc("6f9f44"))
    m = p.ell_mask(cx, cy, 48)
    p.shadow(m, 5, (0, 4), 0.8)
    pts = [(cx + (50 if j % 2 == 0 else 44) * math.cos(j * math.pi / 16), cy + (50 if j % 2 == 0 else 44) * math.sin(j * math.pi / 16)) for j in range(32)]
    p.grad_mask(p.poly_mask(pts), INK["gold2"], hexc("a87414"), (0, cy - 50, 0, cy + 50))
    p.grad_mask(p.ell_mask(cx, cy, 38), hexc("ffe48a"), hexc("d39a1c"), (0, cy - 38, 0, cy + 38))
    p.fill_mask(p.ell_mask(cx, cy, 30), hexc("2f6a3a"))
    p.grad_mask(p.ell_mask(cx, cy, 28), hexc("3f8f4a"), hexc("1f4f2a"), (0, cy - 28, 0, cy + 28))
    p.check(cx, cy + 1, 3.2, hexc("f6ecd2"))
    for x, y, r in ((150, 70, 7), (370, 76, 8), (120, 176, 5), (392, 184, 6), (180, 206, 4), (336, 54, 4)):
        p.glow(x, y, r * 5, INK["gold2"], 0.4)
        pts = [(x + (r if j % 2 == 0 else r * 0.34) * math.cos(-math.pi / 2 + j * math.pi / 4),
                y + (r if j % 2 == 0 else r * 0.34) * math.sin(-math.pi / 2 + j * math.pi / 4)) for j in range(8)]
        p.poly(pts, INK["gold2"])
    return p.done()


def p_signup():
    p = Pic(15)
    p.wood()
    # The calendar, big: the raid night lit.
    p.parchment((48, 46, 250, 210), 5)
    p.grad_mask(p.rr_mask((48, 46, 250, 74), 5), hexc("9b2216"), hexc("6e170e"), (0, 46, 0, 74))
    for x in (92, 206):
        p.rr((x - 3.5, 38, x + 3.5, 56), 3.5, INK["metal2"])
    for i in range(15):
        col, row = i % 5, i // 5
        x, y = 58 + col * 37.5, 82 + row * 42
        if i == 7:
            p.glow(x + 16, y + 18, 70, INK["red2"], 0.5)
            p.rr((x - 2, y - 2, x + 34, y + 38), 4, INK["red"], INK["gold2"], 1.8)
            p.sword(x + 16, y + 18, 2.6, math.pi / 4, hexc("f6ecd2"), INK["gold2"])
            p.sword(x + 16, y + 18, 2.6, -math.pi / 4, hexc("f6ecd2"), INK["gold2"])
        else:
            p.rr((x, y, x + 32, y + 36), 3, hexc("e8d6ab"), hexc("c9ad78"), 1)
    # The night's sign-up: your role picked, and the green tick.
    p.line([(256, 128), (282, 128)], hexc("ffd77a", 170), 2)
    p.poly([(282, 122), (292, 128), (282, 134)], hexc("ffd77a", 200))
    p.dark_panel((298, 52, 466, 204), 8)
    for i, r in enumerate(("T", "H", "D")):
        cx = 330 + i * 52
        if i == 1:
            p.glow(cx, 96, 60, INK["gold2"], 0.55)
        p.role(cx, 96, 19, r)
        if i == 1:
            ring = ImageChops.subtract(p.ell_mask(cx, 96, 25), p.ell_mask(cx, 96, 22))
            p.fill_mask(ring, INK["gold"])
    p.rr((316, 140, 448, 184), 8, INK["green"], INK["greenLit"], 1.6)
    p.check(382, 162, 2.0, hexc("f6ecd2"))
    return p.done()


def p_groups():
    p = Pic(16)
    p.wood()
    # The LFG board: three group cards, the one you fit washed green; a free seat waits for you.
    for i in range(3):
        x = 44 + i * 144
        fits = i == 1
        top, bot = (44, 212) if fits else (50, 206)
        p.parchment((x, top, x + 132, bot), 6)
        if fits:
            p.glow(x + 66, 128, 150, INK["greenLit"], 0.35)
            p.grad_mask(p.rr_mask((x, top, x + 132, bot), 6), hexc("4fd04a", 120), hexc("2f8a3a", 80), (0, top, 0, bot))
            p.gold_frame((x, top, x + 132, bot), 6, 2.2)
        p.avatar(x + 24, top + 26, 13, CLASS[(i * 3 + 1) % len(CLASS)])
        p.lines(x + 44, top + 18, 72, 2, INK["paperLine"], 10, 4.5)
        seats = [("T", True), ("H", i != 1), ("D", True), ("D", i == 0)]
        for j, (r, taken) in enumerate(seats):
            cx, cy = x + 24 + (j % 2) * 42, top + 72 + (j // 2) * 40
            if taken:
                p.role(cx, cy, 14, r)
            else:
                ring = ImageChops.subtract(p.ell_mask(cx, cy, 14), p.ell_mask(cx, cy, 12))
                p.fill_mask(ring, INK["green"] if fits else INK["paperLine"])
                if fits:
                    p.role(cx, cy, 9, r)
        if fits:
            p.chip(x + 110, top + 92, 15, INK["green"], INK["greenLit"])
            p.check(x + 110, top + 92, 1.35, hexc("f6ecd2"))
        else:
            p.rr((x + 98, top + 80, x + 124, top + 100), 6, INK["soft"])
            p.poly([(x + 104, top + 98), (x + 101, top + 106), (x + 111, top + 99)], INK["soft"])
    return p.done()


def p_alts():
    p = Pic(17)
    p.wood()
    # The main, ringed in gold, chained to its alts; they share the Guild OS mark.
    cx, cy = 150, 128
    p.glow(cx, cy, 130, INK["gold2"], 0.45)
    p.avatar(cx, cy, 44, CLASS[6])
    ring = ImageChops.subtract(p.ell_mask(cx, cy, 50), p.ell_mask(cx, cy, 46))
    p.grad_mask(ring, INK["gold2"], INK["metal"], (0, cy - 50, 0, cy + 50))
    p.chip(cx + 34, cy + 34, 13, hexc("1f4f2a"), INK["greenLit"])
    p.poly(p.shield_pts(cx + 34, cy + 34, 1.4), hexc("7fe07a"))
    alts = [(340, 72, CLASS[7]), (392, 128, CLASS[2]), (340, 184, CLASS[1])]
    for ax, ay, c in alts:
        # A chain of links from the main to the alt.
        n = 5
        sx, sy = cx + 52, cy
        ex, ey = ax - 28, ay
        ang = math.atan2(ey - sy, ex - sx)
        for j in range(n):
            t = (j + 0.5) / n
            x0, y0 = sx + (ex - sx) * t, sy + (ey - sy) * t
            ry = 5 if j % 2 == 0 else 3
            m = ImageChops.subtract(p.ell_mask(x0, y0, 9, ry + 1.5), p.ell_mask(x0, y0, 6, max(0.8, ry - 1.5)))
            m = m.rotate(-math.degrees(ang), center=(k(x0), k(y0)), resample=Image.BICUBIC)
            p.grad_mask(m, hexc("e0e4ea"), hexc("7d848e"), (0, y0 - 6, 0, y0 + 6))
        p.avatar(ax, ay, 26, c)
        p.chip(ax + 20, ay + 20, 8, hexc("1f4f2a"), INK["greenLit"])
    return p.done()


def p_wishlist():
    p = Pic(18)
    p.wood()
    # The wishlist: items in order, gold, silver and bronze, the first starred; arrows to move them.
    p.parchment((120, 44, 392, 212), 6)
    rows = [(INK["purple"], "sword", hexc("ffd24a")), (INK["rare"], "helm", hexc("d8dde4")), (INK["purple"], "gem", hexc("d08a4a"))]
    for i, (q, kind, medal) in enumerate(rows):
        y = 56 + i * 50
        if i == 0:
            p.rr((132, y - 4, 380, y + 44), 6, hexc("ffd77a", 90), INK["metal2"], 1.2)
        p.chip(150, y + 20, 11, medal, mix(medal, hexc("000000"), 0.4))
        for j in range(i + 1):
            p.dot(150 - i * 3 + j * 6, y + 20, 2.2, hexc("3a2a14"))
        p.slot(172, y + 2, 38, q, kind)
        p.bar(222, y + 12, 104 - i * 18, 6, q)
        p.bar(222, y + 24, 64, 4, INK["paperLine"])
        if i == 0:
            pts = [(356 + (10 if j % 2 == 0 else 4) * math.cos(-math.pi / 2 + j * math.pi / 5),
                    y + 20 + (10 if j % 2 == 0 else 4) * math.sin(-math.pi / 2 + j * math.pi / 5)) for j in range(10)]
            p.poly(pts, INK["gold"])
    # Up and down, to put what you want first.
    for y, up in ((100, True), (156, False)):
        p.chip(432, y, 18, hexc("3a2614"), INK["metal2"])
        d = -1 if up else 1
        p.poly([(432, y + d * 10), (443, y - d * 1), (421, y - d * 1)], INK["gold2"])
        p.rr((428.5, min(y - d * 1, y - d * 9), 435.5, max(y - d * 1, y - d * 9)), 1.5, INK["gold2"])
    # The drop, left, in its light.
    p.glow(72, 128, 80, INK["purple"], 0.45)
    p.slot(52, 108, 40, INK["purple"], "sword")
    return p.done()


def p_crafts():
    p = Pic(19)
    p.wood()
    # The anvil, the hammer and its sparks.
    p.glow(150, 140, 150, INK["flame"], 0.45)
    anvil = [(84, 128), (220, 128), (214, 140), (188, 146), (180, 168), (200, 190), (104, 190), (124, 168), (116, 146),
             (60, 140), (66, 132)]
    m = p.poly_mask(anvil)
    p.shadow(m, 5, (0, 4), 0.75)
    p.grad_mask(m, hexc("9aa1aa"), hexc("3e434a"), (0, 128, 0, 190))
    p.rr((84, 124, 220, 132), 2, hexc("c9ced6"))
    p.rr((96, 188, 208, 200), 3, hexc("2a2d32"))
    p.glow(150, 122, 40, INK["ember"], 0.8)
    p.rr((126, 116, 176, 124), 3, hexc("ffb040"))
    p.line([(206, 52), (160, 110)], hexc("2a1a0e"), 9)
    p.line([(206, 52), (160, 110)], hexc("b07a40"), 6)
    hm = p.poly_mask([(186, 44), (214, 30), (230, 52), (202, 66)])
    p.shadow(hm, 3, (0, 2), 0.6)
    p.grad_mask(hm, hexc("c9ced6"), hexc("5a5f66"), (0, 30, 0, 66))
    rnd = random.Random(9)
    for _ in range(14):
        a = rnd.uniform(-math.pi * 0.95, -math.pi * 0.05)
        r0, r1 = rnd.uniform(8, 14), rnd.uniform(22, 46)
        p.line([(150 + r0 * math.cos(a), 116 + r0 * math.sin(a)), (150 + r1 * math.cos(a), 116 + r1 * math.sin(a))],
               hexc("ffd27a", 230), 1.4)
    # The craft order: the item asked for, the crafter, the coin.
    p.parchment((282, 50, 462, 206), 6)
    p.slot(298, 66, 46, INK["purple"], "helm")
    p.lines(356, 72, 92, 2, INK["paperLine"], 12, 5)
    p.avatar(312, 152, 16, CLASS[0])
    p.line([(336, 152), (372, 152)], INK["paperInk"], 2.4)
    p.poly([(372, 146), (382, 152), (372, 158)], INK["paperInk"])
    p.gear(408, 152, 16, hexc("8a6a3a"))
    p.coin(440, 184, 11)
    return p.done()


def p_site():
    p = Pic(20)
    p.wood()
    # The game, left: a small window with the guild's crest.
    p.dark_panel((48, 70, 168, 170), 6)
    p.rr((50, 72, 166, 84), 4, hexc("3e2816"))
    p.chip(108, 128, 24, hexc("1f4f2a"), INK["gold2"])
    p.poly(p.shield_pts(108, 128, 2.6), INK["gold2"])
    # The Companion carries it over: a dashed arc to the site.
    for i in range(6):
        x = 180 + i * 15
        p.line([(x, 132 - 22 * math.sin(math.pi * i / 6)), (x + 8, 132 - 22 * math.sin(math.pi * (i + 0.55) / 6))],
               INK["gold2"], 2.6)
    p.poly([(268, 124), (280, 132), (268, 140)], INK["gold2"])
    # The site: a browser page with the calendar and the roster.
    p.glow(370, 128, 140, hexc("9fd4e0"), 0.18)
    p.dark_panel((288, 46, 466, 210), 7, hexc("efe3c8"), INK["metal2"])
    p.rr((290, 48, 464, 66), 5, hexc("3e2816"))
    for j, c in enumerate((INK["red2"], hexc("f0b850"), INK["greenLit"])):
        p.dot(302 + j * 11, 57, 3.2, c)
    p.rr((338, 52, 452, 62), 5, hexc("5a3e24"))
    for i in range(12):
        col, row = i % 4, i // 4
        x, y = 300 + col * 23, 78 + row * 24
        ev = i == 6
        p.rr((x, y, x + 19, y + 20), 2.5, INK["red"] if ev else hexc("dccaa0"), INK["gold2"] if ev else None, 1)
    for i, c in enumerate((CLASS[0], CLASS[5], CLASS[2], CLASS[7])):
        y = 84 + i * 18
        p.dot(402, y, 5, c)
        p.bar(412, y - 2.5, 44 - (i % 2) * 10, 5, mix(c, hexc("3a2a14"), 0.35))
    p.bar(300, 158, 154, 5, INK["paperLine"])
    p.bar(300, 170, 116, 5, INK["paperLine"])
    p.rr((300, 182, 366, 200), 6, INK["green"])
    return p.done()


def p_moderation():
    p = Pic(21)
    p.wood()
    # The guild chat, one line flagged.
    p.dark_panel((44, 46, 290, 210), 6)
    green = hexc("40ff40")
    for i in range(5):
        y = 60 + i * 30
        flagged = i == 2
        c = CLASS[(i * 2 + 3) % len(CLASS)]
        if flagged:
            p.rr((50, y - 6, 284, y + 20), 4, hexc("d0452c", 80), INK["red2"], 1.2)
        p.dot(64, y + 7, 5, c)
        p.bar(76, y + 4, 40, 5, c)
        p.bar(122, y + 4, 124 - (i % 3) * 26, 5, mix(green, hexc("1c110a"), 0.1 if flagged else 0.45))
        if flagged:
            p.chip(268, y + 7, 9, hexc("5a3a08"), hexc("f0a830"))
            p.rr((266.6, y + 1.5, 269.4, y + 8.5), 1, hexc("ffe0a0"))
            p.dot(268, y + 11.5, 1.6, hexc("ffe0a0"))
    # The gavel, coming down.
    p.glow(352, 120, 90, INK["gold2"], 0.3)
    p.line([(316, 168), (372, 96)], hexc("6e4220"), 7)
    head = p.poly_mask([(350, 70), (378, 56), (402, 98), (374, 112)])
    p.shadow(head, 3, (0, 2), 0.6)
    p.grad_mask(head, hexc("9a6a3a"), hexc("4a2c14"), (0, 56, 0, 112))
    p.poly([(352, 74), (378, 61), (382, 68), (356, 81)], INK["metal2"])
    p.poly([(368, 102), (394, 89), (398, 96), (372, 109)], INK["metal2"])
    p.rr((316, 180, 388, 196), 5, hexc("5a3418"), INK["metal2"], 1.2)
    # The ban that follows the alts: a barred avatar, chained to its alt.
    p.avatar(430, 88, 20, CLASS[7])
    p.fill_mask(ImageChops.subtract(p.ell_mask(430, 88, 24), p.ell_mask(430, 88, 20)), INK["red2"])
    p.line([(414, 104), (446, 72)], INK["red2"], 4)
    p.avatar(430, 176, 15, CLASS[2])
    p.fill_mask(ImageChops.subtract(p.ell_mask(430, 176, 18.5), p.ell_mask(430, 176, 15.5)), INK["red2"])
    p.line([(419, 187), (441, 165)], INK["red2"], 3)
    for j in range(3):
        y = 124 + j * 10
        p.fill_mask(ImageChops.subtract(p.ell_mask(430, y, 4, 6), p.ell_mask(430, y, 2, 3.5)), hexc("b8bec6"))
    return p.done()


PICTURES = {
    "salao": p_salao, "search": p_search, "officers": p_officers, "members": p_members, "raids": p_raids,
    "map": p_map, "map-fires": lambda: p_map(True), "bank": p_bank, "light": p_light, "shield": p_shield,
    "compact": p_compact, "gm": p_gm, "departure": p_departure, "notes": p_notes, "done": p_done,
    "signup": p_signup, "groups": p_groups, "alts": p_alts, "wishlist": p_wishlist, "crafts": p_crafts,
    "site": p_site, "moderation": p_moderation,
}


def on_wood(img):
    """The painting as the game shows it: over the holder's wood, tiled at its own size."""
    tile = Image.open(os.path.join(ROOT, "Media", "Salao", "wood.tga")).convert("RGBA")
    out = Image.new("RGBA", img.size)
    for y in range(0, img.size[1], tile.size[1]):
        for x in range(0, img.size[0], tile.size[0]):
            out.paste(tile, (x, y))
    return Image.alpha_composite(out, img.convert("RGBA")).convert("RGB")


def tga_bytes(img):
    img = img.convert("RGBA")
    w, h = img.size
    head = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, w & 255, w >> 8, h & 255, h >> 8, 32, 0x28])
    return head + img.tobytes("raw", "BGRA")


def main():
    check = "--check" in sys.argv
    png = sys.argv[sys.argv.index("--png") + 1] if "--png" in sys.argv else None
    only = [a for a in sys.argv[1:] if a in PICTURES]
    os.makedirs(OUT, exist_ok=True)
    stale = []
    for name, draw in PICTURES.items():
        if only and name not in only:
            continue
        img = draw()
        data = tga_bytes(img)
        path = os.path.join(OUT, name + ".tga")
        if check:
            if not os.path.exists(path) or open(path, "rb").read() != data:
                stale.append(name)
        else:
            with open(path, "wb") as f:
                f.write(data)
        if png:
            os.makedirs(png, exist_ok=True)
            on_wood(img).save(os.path.join(png, name + ".png"))
    if check and stale:
        print("stale: " + ", ".join(stale))
        sys.exit(1)


if __name__ == "__main__":
    main()
