#!/usr/bin/env python3
"""A DETAIL TEXTURE, made from nothing but arithmetic: the small-scale wear a
painted texture is too coarse to carry (grain, pitting, scratches, dents, grime
in the low places), as two seamless tiles to lay over a model's own texture:

    assets/detail/textures/detail_grime.jpg    multiplied into the colour: 1.0 is
                                                no change, darker where grime and
                                                wear sit (mean about 0.92)
    assets/detail/textures/detail_normal.png   the same wear as a normal map

    python3 tools/build_detail_texture.py [size=1024] [seed=7]

EVERYTHING TILES because everything is made on a torus: the noise is white noise
shaped in the frequency domain (an FFT is periodic by construction), and every
scratch, dent and pit is drawn with wrap-around distances. So the tile repeats
with no seam however it is laid, which is what a triplanar projection needs.

The height field is the sum of:
  - fBm: power-law filtered noise, broad undulation down to the pixel (beta ~ 2.7)
  - pitting: sparse small sharp-rimmed craters, as on cast or blasted metal
  - dents: a few broad soft hollows
  - scratches: thin straight-ish grooves at clustered angles (things are
    scratched in one direction more than others), each fading in and out along
    its length, some deep and most shallow
  - grain: anisotropic fine noise, brushed along one axis
The grime is where dirt collects: the cavities of the height field (it minus its
own blur) and broad low-frequency blotches, with scratches cut bright.
"""
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "detail" / "textures"


def spectral_noise(n, rng, beta, lo=1.0, hi=None, aniso=(1.0, 1.0)):
    """Periodic noise with power ~ 1/f^beta between frequencies lo and hi (cycles per tile)."""
    white = rng.standard_normal((n, n))
    f = np.fft.fft2(white)
    fy = np.fft.fftfreq(n)[:, None] * n * aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * n * aniso[0]
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    amp = r ** (-beta / 2.0)
    amp[r < lo] = 0.0
    if hi is not None:
        amp *= np.exp(-((r / hi) ** 4))
    amp[0, 0] = 0.0
    out = np.real(np.fft.ifft2(f * amp))
    return out / (out.std() + 1e-9)


def wrap_dist(n, cx, cy):
    """Distance from (cx, cy) to every pixel, on the torus."""
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    dx = np.abs(x - cx)
    dy = np.abs(y - cy)
    dx = np.minimum(dx, n - dx)
    dy = np.minimum(dy, n - dy)
    return np.sqrt(dx * dx + dy * dy)


def wrap_blur(img, sigma):
    """A Gaussian blur on the torus (by FFT), so it is as seamless as what it blurs."""
    n = img.shape[0]
    f = np.fft.fftfreq(n)
    g = np.exp(-2.0 * (np.pi * sigma) ** 2 * (f[:, None] ** 2 + f[None, :] ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(img) * g)).astype(np.float32)


def stamp(field, n, cx, cy, radius, fn):
    """Add fn(d / radius) over a square round (cx, cy), wrapping at the edges."""
    r = int(np.ceil(radius * 1.6)) + 2
    ys = np.arange(int(cy) - r, int(cy) + r + 1)
    xs = np.arange(int(cx) - r, int(cx) + r + 1)
    yy, xx = np.meshgrid(ys, xs, indexing="ij")
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / radius
    np.add.at(field, (yy % n, xx % n), fn(d))


def scratches(n, rng, count):
    """Thin grooves (negative height), drawn with wrap-around, clustered in angle.
    Drawn as centrelines into three widths, each blurred once to its width."""
    widths = [0.6, 1.0, 1.6]
    lines = [np.zeros((n, n), np.float32) for _ in widths]
    main = rng.uniform(0, np.pi)
    for _ in range(count):
        ang = main + rng.normal(0, 0.35) if rng.random() < 0.7 else rng.uniform(0, np.pi)
        length = rng.uniform(0.04, 0.35) * n
        depth = rng.uniform(0.15, 1.0) ** 2
        layer = lines[rng.integers(0, len(widths))]
        x0, y0 = rng.uniform(0, n, 2)
        bend = rng.normal(0, 0.15)
        steps = int(length * 1.5)
        t = np.linspace(0.0, 1.0, steps)
        a = ang + bend * (t - 0.5)
        xi = np.round(x0 + np.cos(a) * length * t).astype(int) % n
        yi = np.round(y0 + np.sin(a) * length * t).astype(int) % n
        # Fading in and out along its length, as a groove dragged by something does.
        w = (np.sin(np.pi * t) ** 0.6 * depth).astype(np.float32)
        np.maximum.at(layer, (yi, xi), w)
    h = np.zeros((n, n), np.float32)
    for layer, width in zip(lines, widths):
        # (Blurring spreads a one-pixel line over about 2.5 sigma: scaled back up.)
        h -= wrap_blur(layer, width) * (2.5 * width)
    cut = np.clip(-h, 0.0, 1.0)
    return h, cut


def build(n=1024, seed=7):
    rng = np.random.default_rng(seed)
    # Broad undulation down to the pixel.
    fbm = spectral_noise(n, rng, 2.7, lo=2.0) * 0.35
    # Brushed grain: fine noise stretched along one axis.
    grain = spectral_noise(n, rng, 0.6, lo=n / 16, hi=n / 3, aniso=(0.15, 1.0)) * 0.015
    # Pitting: small sharp craters with a little rim.
    pits = np.zeros((n, n), np.float32)
    for _ in range(int(n * n / 2600)):
        cx, cy = rng.uniform(0, n, 2)
        radius = rng.uniform(1.2, 4.0)
        depth = rng.uniform(0.2, 0.9)
        stamp(pits, n, cx, cy, radius, lambda d, dp=depth: -dp * np.exp(-d * d * 2.5) + 0.25 * dp * np.exp(-(d - 1.1) ** 2 * 10))
    # Dents: a few broad soft hollows.
    dents = np.zeros((n, n), np.float32)
    for _ in range(14):
        cx, cy = rng.uniform(0, n, 2)
        radius = rng.uniform(n * 0.02, n * 0.07)
        stamp(dents, n, cx, cy, radius, lambda d, dp=rng.uniform(0.6, 1.6): -dp * np.exp(-d * d * 1.8))
    scr, cut = scratches(n, rng, int(n / 5))
    height = fbm + grain + pits * 0.5 + dents * 0.9 + scr * 1.1

    # GRIME: where dirt sits. The cavities (lower than their surroundings), broad
    # blotches, and a little speckle; the fresh scratches cut bright through it.
    blur = wrap_blur(height, 6.0)
    cavity = np.clip((blur - height) * 2.2, 0.0, 1.0)
    blotch = np.clip(spectral_noise(n, rng, 2.6, lo=1.0, hi=24) * 0.5 + 0.1, 0.0, 1.0)
    speck = np.clip(spectral_noise(n, rng, 0.8, lo=n / 12) * 0.5 - 0.9, 0.0, 1.0)
    grime = 1.0 - 0.3 * cavity - 0.14 * blotch - 0.12 * speck
    grime = grime + 0.08 * np.clip(cut * 2.0, 0.0, 1.0)
    grime = np.clip(grime, 0.55, 1.0)

    # NORMALS from the height, by periodic central differences.
    strength = 2.2
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5 * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5 * strength
    nz = np.ones_like(height)
    length = np.sqrt(dx * dx + dy * dy + nz * nz)
    # OpenGL convention (Godot's): +Y up in the picture.
    normal = np.stack([-dx / length, dy / length, nz / length], -1)

    OUT.mkdir(parents=True, exist_ok=True)
    g8 = np.clip(grime * 255.0 + 0.5, 0, 255).astype(np.uint8)
    cv2.imwrite(str(OUT / "detail_grime.jpg"), cv2.merge([g8, g8, g8]), [cv2.IMWRITE_JPEG_QUALITY, 92])
    n8 = np.clip((normal * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    cv2.imwrite(str(OUT / "detail_normal.png"), n8[..., ::-1])     # RGB -> BGR for OpenCV
    print("detail: %dx%d, grime mean %.3f, min %.3f" % (n, n, grime.mean(), grime.min()))
    # A 2x2 of each, to see that the tile has no seam.
    prev = np.hstack([np.tile(g8, (2, 2)), np.tile(n8[..., 0], (2, 2))])
    cv2.imwrite(str(ROOT / "assets" / "detail" / "preview_tiled.jpg"), cv2.resize(prev, (prev.shape[1] // 2, prev.shape[0] // 2)))


if __name__ == "__main__":
    build(int(sys.argv[1]) if len(sys.argv) > 1 else 1024, int(sys.argv[2]) if len(sys.argv) > 2 else 7)
