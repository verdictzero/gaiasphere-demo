#!/usr/bin/env python3
"""Chroma-key magenta-backed plant photos into game-ready alpha textures.

  card   a frond / branch: rotated so the stem runs left->right (base at u=0),
         fitted into a WxH card.  The stem's v (from the top) is printed.
           key_magenta.py card SRC DST --base X,Y --tip X,Y [--size 1024x512]
  clump  an upright plant: cropped, scaled to fit and stood on the bottom edge
         with its root centred, for billboards.
           key_magenta.py clump SRC DST [--size 1024x1024]
  --edge N  de-pink a rim N texels wide along the silhouette (default 2, 0 = off)

All outputs are despilled and have their RGB bled into the transparent area so
mipmaps don't pick up a halo.
"""
import argparse
import json

import numpy as np
from PIL import Image
from scipy import ndimage as ndi


def key(path, edge=2):
    """-> float RGBA array (0..1) with magenta removed.

    `edge`: width in texels of a rim along the silhouette where red and blue are capped
    relative to green.  A green/yellow leaf mixed with a little magenta turns tan-pink
    rather than magenta, which despill cannot see; this removes that rim.  Only for
    green plants: it would also green a brown twig, so the fir branch uses --edge 0."""
    img = np.asarray(Image.open(path).convert("RGB")).astype(np.float32) / 255.0
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    m = np.minimum(r, b) - g                 # magenta-ness: R and B both above G
    lo, hi = 0.10, 0.45
    t = np.clip((m - lo) / (hi - lo), 0, 1)
    alpha = 1.0 - t * t * (3 - 2 * t)

    # drop isolated specks, keep the plant (+ close neighbours)
    solid = alpha > 0.5
    lab, n = ndi.label(ndi.binary_dilation(solid, iterations=3))
    if n > 1:
        sizes = ndi.sum(solid, lab, range(1, n + 1))
        alpha = alpha * np.isin(lab, 1 + np.flatnonzero(sizes > 0.002 * sizes.max()))

    # despill: remove the magenta component left on semi-transparent edges
    spill = np.clip(np.minimum(r, b) - g, 0, None)
    rgb = img.copy()
    rgb[..., 0] -= spill
    rgb[..., 2] -= spill
    if edge:
        rim = ~ndi.binary_erosion(alpha > 0.6, iterations=edge)
        # plus anything inside that is outright pink (magenta showing through small gaps);
        # browns and straw have low blue and are left alone
        rim |= (rgb[..., 0] > rgb[..., 1]) & (rgb[..., 2] > 0.7 * rgb[..., 1])
        rgb[..., 0] = np.where(rim, np.minimum(rgb[..., 0], rgb[..., 1] * 0.92), rgb[..., 0])
        rgb[..., 2] = np.where(rim, np.minimum(rgb[..., 2], rgb[..., 1] * 0.55), rgb[..., 2])
    return bleed(np.dstack([rgb, alpha]))


def bleed(rgba):
    """Copy the nearest opaque colour into transparent texels."""
    opaque = rgba[..., 3] > 0.6
    idx = ndi.distance_transform_edt(~opaque, return_distances=False, return_indices=True)
    out = rgba.copy()
    out[..., :3] = np.where(opaque[..., None], rgba[..., :3], rgba[idx[0], idx[1], :3])
    return out


def to_image(rgba):
    return Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def bbox(im, thresh=24):
    ys, xs = np.nonzero(np.asarray(im)[..., 3] > thresh)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def save(out, dst):
    o = bleed(np.asarray(out).astype(np.float32) / 255.0)   # re-bleed after resampling
    to_image(o).save(dst, optimize=True)
    return o


def card(src, dst, base, tip, size, edge):
    W, H = size
    im = to_image(key(src, edge))
    d = np.subtract(tip, base)
    ang = np.degrees(np.arctan2(-d[1], d[0]))                # image y is down
    rot = im.rotate(-ang, resample=Image.BICUBIC, expand=True)
    x0, y0, x1, y1 = bbox(rot)
    scale = min((W - 8) / (x1 - x0), (H - 8) / (y1 - y0))
    crop = rot.crop((x0, y0, x1, y1))
    crop = crop.resize((int(crop.width * scale), int(crop.height * scale)), Image.LANCZOS)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(crop, (4, (H - crop.height) // 2))
    o = save(out, dst)
    stem_v = np.nonzero(o[:, 6:14, 3].max(axis=1) > 0.5)[0].mean() / H
    print(json.dumps(dict(file=str(dst), size=[W, H], content_px=list(crop.size),
                          coverage=round(float((o[..., 3] > 0.5).mean()), 3),
                          stem_v_from_top=round(float(stem_v), 3))))


def clump(src, dst, size, edge):
    W, H = size
    im = to_image(key(src, edge))
    x0, y0, x1, y1 = bbox(im)
    a = np.asarray(im)[..., 3]
    rows = a[y1 - max(4, (y1 - y0) // 40):y1]                 # the root: lowest rows
    root_x = float((rows.sum(axis=0) * np.arange(a.shape[1])).sum() / rows.sum())
    half = max(root_x - x0, x1 - root_x)                     # keep the root on the centre line
    scale = min((W - 8) / (2 * half), (H - 4) / (y1 - y0))
    crop = im.crop((int(round(root_x - half)), y0, int(round(root_x + half)), y1))
    crop = crop.resize((int(crop.width * scale), int(crop.height * scale)), Image.LANCZOS)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(crop, ((W - crop.width) // 2, H - crop.height))
    o = save(out, dst)
    print(json.dumps(dict(file=str(dst), size=[W, H], content_px=list(crop.size),
                          coverage=round(float((o[..., 3] > 0.5).mean()), 3))))


def pair(sep, cast):
    return lambda s: tuple(cast(v) for v in s.split(sep))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["card", "clump"])
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--base", type=pair(",", float))
    ap.add_argument("--tip", type=pair(",", float))
    ap.add_argument("--size", type=pair("x", int))
    ap.add_argument("--edge", type=int, default=2, help="rim width to de-pink, in texels (0 = off)")
    a = ap.parse_args()
    if a.mode == "card":
        card(a.src, a.dst, a.base, a.tip, a.size or (1024, 512), a.edge)
    else:
        clump(a.src, a.dst, a.size or (1024, 1024), a.edge)
