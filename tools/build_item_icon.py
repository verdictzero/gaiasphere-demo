#!/usr/bin/env python3
"""An inventory icon from a photograph of the thing on a green screen.

    python3 tools/build_item_icon.py photo.png assets/ui/item_beef.png

The green is keyed out (and its spill taken off the rim), the biggest thing left
is kept, cropped, squared off and brought to 256 pixels, with its colour bled out
under the clear pixels so no green shows at the edge when it is drawn small.
"""
import sys

import numpy as np
from PIL import Image
from scipy import ndimage


def main(src, dst):
    im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    alpha = 1.0 - np.clip((g - np.maximum(r, b) - 14.0) / 60.0, 0, 1)
    lab, n = ndimage.label(alpha > 0.5)
    sizes = ndimage.sum(alpha > 0.5, lab, range(1, n + 1))
    alpha = alpha * ndimage.binary_dilation(lab == 1 + int(np.argmax(sizes)), iterations=2)
    rim = ndimage.binary_dilation(alpha < 0.98, iterations=3)
    g = np.where(rim, np.minimum(g, np.maximum(r, b) * 0.6), g)
    out = np.dstack([r, g, b, alpha * 255]).clip(0, 255).astype(np.uint8)
    ys, xs = np.nonzero(alpha > 0.2)
    cut = Image.fromarray(out[ys.min():ys.max() + 1, xs.min():xs.max() + 1], "RGBA")
    side = max(cut.size) + 16
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(cut, ((side - cut.width) // 2, (side - cut.height) // 2))
    a = np.asarray(square.resize((256, 256), Image.LANCZOS)).copy()
    idx = ndimage.distance_transform_edt(a[..., 3] <= 8, return_distances=False, return_indices=True)
    a[..., :3] = a[..., :3][idx[0], idx[1]]
    Image.fromarray(a, "RGBA").save(dst)
    print("icon ->", dst)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
