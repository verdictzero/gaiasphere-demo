#!/usr/bin/env python3
"""Draw a 4x4 sprite sheet of single berry-bush leaves on a clear background.

    python3 tools/build_leaf_sheet.py assets/leaves/berry_leaves_atlas.png

Sixteen leaves, each its own: ovate with a pointed tip and a toothed edge, a
midrib and side veins, a stalk, and its own size, bend, colour and wear (some
yellowing, some with a hole or a bitten edge). Drawn, not photographed: the
same layout as the wood-chip atlas, so a sheet of photographs cut up by
tools/build_chip_atlas.py can replace it file for file.
"""
import sys
import math
import random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

CELL = 256
GRID = 4
SS = 4          # drawn at four times the size and brought down


def leaf(rng):
    n = CELL * SS
    length = rng.uniform(0.78, 0.93) * n
    width = length * rng.uniform(0.46, 0.66)
    bend = rng.uniform(-0.16, 0.16)             # the midrib's curve
    teeth = rng.randint(9, 15)
    fat = rng.uniform(0.36, 0.5)                # where along it the leaf is widest
    turn = rng.uniform(0, math.tau)

    def mid(t):                                 # the midrib, base (0) to tip (1), leaf's own frame
        return (bend * width * math.sin(t * math.pi), (t - 0.5) * length)

    def half(t):                                # half the width at t
        # One smooth swell, widest at `fat`, rounded at the base and drawn to a point.
        k = math.log(0.5) / math.log(fat)
        a = math.sin(math.pi * min(max(t, 0.0), 1.0) ** k) ** 0.8
        return 0.5 * width * max(a, 0.0) * (1.0 - 0.25 * max(t - 0.8, 0.0) / 0.2)

    left, right = [], []
    steps = 160
    for i in range(steps + 1):
        t = i / steps
        mx, my = mid(t)
        tooth = 1.0 + 0.11 * (1.0 - abs(((t * teeth) % 1.0) * 2.0 - 1.0)) * (1.0 if 0.08 < t < 0.95 else 0.0)
        w = half(t) * tooth
        left.append((mx - w, my))
        right.append((mx + w, my))
    outline = left + right[::-1]

    def place(p):
        x, y = p
        c, s = math.cos(turn), math.sin(turn)
        return (n / 2 + x * c - y * s, n / 2 + x * s + y * c)

    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).polygon([place(p) for p in outline], fill=255)
    stalk = Image.new("L", (n, n), 0)
    sd = ImageDraw.Draw(stalk)
    sd.line([place(mid(0.0)), place((mid(0.0)[0] - bend * 30, -0.5 * length - 0.05 * n))], fill=255, width=int(0.018 * n))

    # Wear: a hole, or a bite out of the edge.
    wear = ImageDraw.Draw(mask)
    if rng.random() < 0.35:
        t = rng.uniform(0.3, 0.75)
        mx, my = mid(t)
        off = rng.choice([-1, 1]) * half(t) * rng.uniform(0.3, 1.05)
        r = rng.uniform(0.018, 0.045) * n
        cx, cy = place((mx + off, my))
        wear.ellipse([cx - r, cy - r * rng.uniform(0.7, 1.3), cx + r, cy + r], fill=0)

    # Colour: the leaf's own green, lighter toward the midrib and base, a yellow or red turn on some.
    hue = rng.choice(["green", "green", "green", "green", "yellow", "red"])
    base = {"green": (58, 118, 44), "yellow": (128, 138, 46), "red": (126, 62, 40)}[hue]
    base = tuple(int(c * rng.uniform(0.82, 1.15)) for c in base)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    c, s = math.cos(-turn), math.sin(-turn)
    lx = (xx - n / 2) * c - (yy - n / 2) * s
    ly = (xx - n / 2) * s + (yy - n / 2) * c
    t = np.clip(ly / length + 0.5, 0, 1)
    off = np.abs(lx - bend * width * np.sin(t * math.pi)) / (0.5 * width + 1e-6)
    shade = 1.12 - 0.3 * np.clip(off, 0, 1) + 0.1 * (1 - t)
    # One half catches the light a little more: a leaf is never flat.
    shade += 0.07 * np.sign(lx - bend * width * np.sin(t * math.pi)) * rng.choice([-1, 1])
    noise = np.asarray(Image.effect_noise((n // 8, n // 8), 40).resize((n, n), Image.BICUBIC)).astype(np.float32) / 255.0 - 0.5
    shade += noise * 0.16
    rgb = np.clip(np.dstack([base[0] * shade, base[1] * shade, base[2] * shade * 0.95]), 0, 255)
    if hue == "green" and rng.random() < 0.5:   # browning toward the tip
        tip = np.clip((t - 0.72) / 0.28, 0, 1)[..., None] * rng.uniform(0.3, 0.75)
        rgb = rgb * (1 - tip) + np.array([120, 92, 44], np.float32) * tip
    img = Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")

    # Veins: the midrib and pairs running out and up from it.
    veins = Image.new("L", (n, n), 0)
    vd = ImageDraw.Draw(veins)
    vd.line([place(mid(i / 40)) for i in range(41)], fill=255, width=int(0.009 * n))
    pairs = rng.randint(5, 8)
    for k in range(1, pairs + 1):
        t0 = 0.08 + 0.74 * k / (pairs + 1)
        mx, my = mid(t0)
        for side in (-1, 1):
            reach = half(min(t0 + 0.16, 0.98)) * 0.92
            vd.line([place((mx, my)), place((mx + side * reach * 0.55, my + 0.07 * length)),
                     place((mx + side * reach, my + 0.17 * length))], fill=170, width=int(0.0045 * n), joint="curve")
    veins = veins.filter(ImageFilter.GaussianBlur(SS * 0.6))
    v = np.asarray(veins).astype(np.float32)[..., None] / 255.0
    a = np.asarray(img).astype(np.float32)
    pale = np.array([150, 176, 96, 255], np.float32) if hue != "red" else np.array([176, 120, 76, 255], np.float32)
    a = a * (1 - v * 0.6) + pale * v * 0.6
    img = Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")

    stem = Image.new("RGBA", (n, n), tuple(int(c * 0.8) for c in base) + (255,))
    out = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    out.paste(stem, (0, 0), stalk)
    out.paste(img, (0, 0), mask)
    # A darker rim, as a leaf's edge curls from the light.
    rim = np.asarray(mask.filter(ImageFilter.GaussianBlur(SS * 2.5))).astype(np.float32) / 255.0
    o = np.asarray(out).astype(np.float32)
    o[..., :3] *= (0.72 + 0.28 * np.clip((rim - 0.5) * 2.4, 0, 1))[..., None]
    return Image.fromarray(o.clip(0, 255).astype(np.uint8), "RGBA").resize((CELL, CELL), Image.LANCZOS)


def main(dst):
    rng = random.Random(7)
    sheet = Image.new("RGBA", (CELL * GRID, CELL * GRID), (0, 0, 0, 0))
    for i in range(GRID * GRID):
        sheet.alpha_composite(leaf(rng), ((i % GRID) * CELL, (i // GRID) * CELL))
    sheet.save(dst)
    print("leaves: 16 ->", dst)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/leaves/berry_leaves_atlas.png")
