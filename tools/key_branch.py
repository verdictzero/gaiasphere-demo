#!/usr/bin/env python3
"""Chroma-key the magenta-backed fir branch photo into a game-ready foliage card.

Output: RGBA PNG, branch rotated so the stem runs left->right along the
horizontal (stem base at u=0; its v is printed), despilled, with RGB bled
into the transparent area so mipmaps don't pick up a halo.
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

SRC, DST = sys.argv[1], sys.argv[2]
OUT_W, OUT_H = 1024, 512
# stem base / leader tip in source pixels (measured from the photo)
BASE = np.array([150.0, 862.0])
TIP = np.array([1870.0, 240.0])

img = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float32) / 255.0
r, g, b = img[..., 0], img[..., 1], img[..., 2]

# magenta-ness: how far both R and B sit above G
m = np.minimum(r, b) - g
lo, hi = 0.10, 0.45
t = np.clip((m - lo) / (hi - lo), 0, 1)
alpha = 1.0 - t * t * (3 - 2 * t)

# drop isolated specks, keep the single connected branch (+ close neighbours)
solid = alpha > 0.5
lab, n = ndi.label(ndi.binary_dilation(solid, iterations=3))
if n > 1:
    sizes = ndi.sum(solid, lab, range(1, n + 1))
    keep = np.isin(lab, 1 + np.flatnonzero(sizes > 0.002 * sizes.max()))
    alpha *= keep

# despill: remove the magenta component left on semi-transparent edges
spill = np.clip(np.minimum(r, b) - g, 0, None)
rgb = img.copy()
rgb[..., 0] -= spill
rgb[..., 2] -= spill

# bleed opaque colour outward into transparent texels
opaque = alpha > 0.6
idx = ndi.distance_transform_edt(~opaque, return_distances=False, return_indices=True)
bled = rgb[idx[0], idx[1]]
rgb = np.where(opaque[..., None], rgb, bled)

rgba = np.dstack([rgb, alpha])
rgba = (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)

# rotate so the stem is horizontal, then map the branch bbox into the card
d = TIP - BASE
ang = np.degrees(np.arctan2(-d[1], d[0]))  # image y is down
im = Image.fromarray(rgba, "RGBA")
H, W = alpha.shape
c = np.array([W / 2, H / 2])
rot = im.rotate(-ang, resample=Image.BICUBIC, expand=True, center=tuple(c))
# alpha bbox in rotated image
ra = np.asarray(rot)[..., 3]
ys, xs = np.nonzero(ra > 24)
x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
# stem row = row of the base point after rotation
th = np.radians(ang)
R = np.array([[np.cos(th), -np.sin(th)], [np.sin(th), np.cos(th)]])
off = (np.array(rot.size) / 2)
base_r = R @ (BASE - c) + off
x0, x1, y0, y1 = int(x0), int(x1), int(y0), int(y1)
scale = min((OUT_W - 8) / (x1 - x0), (OUT_H - 8) / (y1 - y0))
crop = rot.crop((x0, y0, x1, y1))
crop = crop.resize((int(crop.width * scale), int(crop.height * scale)), Image.LANCZOS)
out = Image.new("RGBA", (OUT_W, OUT_H), (0, 0, 0, 0))
px, py = 4, (OUT_H - crop.height) // 2
out.paste(crop, (px, py))

# re-bleed after resampling so the padded area carries foliage colour, alpha 0
o = np.asarray(out).astype(np.float32) / 255.0
op = o[..., 3] > 0.6
idx = ndi.distance_transform_edt(~op, return_distances=False, return_indices=True)
o[..., :3] = np.where(op[..., None], o[..., :3], o[idx[0], idx[1], :3])
Image.fromarray((o * 255 + 0.5).astype(np.uint8), "RGBA").save(DST, optimize=True)
print("card", out.size, "branch px", crop.size, "coverage %.3f" % (o[..., 3] > 0.5).mean(),
      "stem_v_from_top %.3f" % (np.nonzero(o[:, 6:14, 3].max(axis=1) > 0.5)[0].mean() / OUT_H))
