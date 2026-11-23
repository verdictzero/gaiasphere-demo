#!/usr/bin/env python3
"""Cut a sheet of chips photographed on blue (or magenta) into a 4x4 particle atlas.

    python3 tools/build_chip_atlas.py sheet.jpg assets/chips/chips_atlas.png
    python3 tools/build_chip_atlas.py sheet.jpg assets/chips/stone_atlas.png magenta
    python3 tools/build_chip_atlas.py sheet.webp assets/chips/gib_atlas.png green grid

The blue is keyed out (and its spill taken off the edges), each chip is found
as its own island of what is left, cropped, centred in a square cell and the
sixteen cells laid out four by four in reading order, largest islands only.

With `grid` the sheet is taken to be four by four already (a piece to a square,
with its own spatter round it): each square is keyed and kept whole, drops and
all, where the island-finding would throw the drops away.
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

CELL = 256
GRID = 4


def main(src, dst, key="blue", layout="islands"):
    rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # How much bluer than anything else a pixel is: the backdrop is far out, wood is negative.
    if key == "green":
        # Green screen: anything much greener than it is red or blue. Meat has almost none.
        green = g - np.maximum(r, b)
        alpha = 1.0 - np.clip((green - 14.0) / 60.0, 0.0, 1.0)
        rim = ndimage.binary_dilation(alpha < 0.98, iterations=3)
        g2 = np.where(rim, np.minimum(g, np.maximum(r, b) * 0.55), g)
        out = np.dstack([r, g2, b, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    elif key == "magenta":
        # Magenta is red and blue with no green: stone, being grey, has none of it.
        pink = np.minimum(r, b) - g
        alpha = 1.0 - np.clip((pink - 18.0) / 70.0, 0.0, 1.0)
        # Spill is taken off the rim only: inside, rust-brown stone keeps its red.
        rim = ndimage.binary_dilation(alpha < 0.98, iterations=4)
        r2 = np.where(rim, np.minimum(r, g * 1.06 + 6.0), r)
        b2 = np.where(rim, np.minimum(b, g * 1.06 + 6.0), b)
        out = np.dstack([r2, g, b2, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    else:
        blue = b - np.maximum(r, g)
        alpha = 1.0 - np.clip((blue - 18.0) / 70.0, 0.0, 1.0)
        # Spill: what blue is left on a kept pixel comes down to its other channels.
        b2 = np.minimum(b, np.maximum(r, g) * 0.82 + 8.0)
        out = np.dstack([r, g, b2, alpha * 255.0]).clip(0, 255).astype(np.uint8)

    if layout == "grid":
        atlas = Image.new("RGBA", (CELL * GRID, CELL * GRID), (0, 0, 0, 0))
        h, w = alpha.shape
        for n in range(GRID * GRID):
            x0, y0 = (n % GRID) * w // GRID, (n // GRID) * h // GRID
            cell = out[y0 + 4:y0 + h // GRID - 4, x0 + 4:x0 + w // GRID - 4]          # (clear of the ruled lines)
            ys, xs = np.nonzero(cell[..., 3] > 40)
            cell = cell[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
            im = Image.fromarray(cell, "RGBA")
            scale = (CELL - 12) / max(im.size)
            im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
            atlas.alpha_composite(im, ((n % GRID) * CELL + (CELL - im.width) // 2, (n // GRID) * CELL + (CELL - im.height) // 2))
        a = np.asarray(atlas).copy()
        known = a[..., 3] > 8
        idx = ndimage.distance_transform_edt(~known, return_distances=False, return_indices=True)
        a[..., :3] = a[..., :3][idx[0], idx[1]]
        Image.fromarray(a, "RGBA").save(dst)
        print("chips: %d squares -> %s" % (GRID * GRID, dst))
        return
    solid = ndimage.binary_dilation(alpha > 0.5, iterations=6)   # splinters stay with their chip
    labels, count = ndimage.label(solid)
    boxes = ndimage.find_objects(labels)
    sizes = ndimage.sum(alpha > 0.5, labels, range(1, count + 1))
    keep = sorted(np.argsort(sizes)[::-1][:GRID * GRID])
    # Reading order: by row of the sheet, then across.
    h = rgb.shape[0]
    keep.sort(key=lambda i: (int((boxes[i][0].start + boxes[i][0].stop) / 2 / (h / GRID)), boxes[i][1].start))
    atlas = Image.new("RGBA", (CELL * GRID, CELL * GRID), (0, 0, 0, 0))
    for n, i in enumerate(keep):
        ys, xs = boxes[i]
        chip = out[ys, xs].copy()
        chip[..., 3] = np.where(labels[ys, xs] == i + 1, chip[..., 3], 0)
        im = Image.fromarray(chip, "RGBA")
        side = max(im.size)
        scale = (CELL - 12) / side
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
        cx, cy = (n % GRID) * CELL, (n // GRID) * CELL
        atlas.alpha_composite(im, (cx + (CELL - im.width) // 2, cy + (CELL - im.height) // 2))
    # Colour bled out under the clear pixels, so mipmaps do not pull black in at the edges.
    a = np.asarray(atlas).copy()
    known = a[..., 3] > 8
    idx = ndimage.distance_transform_edt(~known, return_distances=False, return_indices=True)
    a[..., :3] = a[..., :3][idx[0], idx[1]]
    Image.fromarray(a, "RGBA").save(dst)
    print("chips: %d found, %d kept -> %s" % (count, len(keep), dst))


if __name__ == "__main__":
    main(*sys.argv[1:5])
