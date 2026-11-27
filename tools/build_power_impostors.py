#!/usr/bin/env python3
"""The power kit's impostors, packed: the eight pictures of each piece that
tests/BAKE_power_impostors.gd took (renders/power_bake) brought down to the size
they are kept at and laid side by side in one atlas a piece,

    assets/power/<piece>_impostor.png      RGBA, eight views in a row, the first from +Z,
                                           each next one an eighth of a turn on toward +X

and the piece's entry in assets/power/manifest.json given what its last level,
a single upright quad turned to the eye (SHADER_part_impostor.gdshader), needs:
how wide and tall the quad is and where its middle stands.

    godot --path . --script res://tests/BAKE_power_impostors.gd
    python3 tools/build_power_impostors.py
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parent.parent
BAKE = ROOT / "renders" / "power_bake"
OUT = ROOT / "assets" / "power"


def view(path, w, h):
    """A picture at some whole multiple of (w, h), brought down by its coverage, and
    its colour run out past its edge so the smaller copies of it do not fringe."""
    c = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0
    fy, fx = c.shape[0] // h, c.shape[1] // w
    c = c[:h * fy, :w * fx]
    a = c[..., 3:4]
    box = lambda x: x.reshape(h, fy, w, fx, -1).mean(axis=(1, 3))
    cover = box(a)
    rgb = box(c[..., :3] * a) / np.maximum(cover, 1e-5)
    solid = cover[..., 0] > 0.02
    if solid.any():
        idx = ndi.distance_transform_edt(~solid, return_distances=False, return_indices=True)
        rgb = rgb[idx[0], idx[1]]
    return np.dstack([rgb, cover])


def main():
    sizes = json.loads((BAKE / "sizes.json").read_text())
    manifest = json.loads((OUT / "manifest.json").read_text())
    for piece in manifest:
        s = sizes[piece["name"]]
        w, h = s["cell"]
        if min(w, h) < 24:
            # A part that lies flat (the solar panel) is a line from every side: a
            # picture of it from the side is no use, and its last mesh is kept.
            piece.pop("impostor", None)
            (OUT / (piece["name"] + "_impostor.png")).unlink(missing_ok=True)
            print("%-16s no impostor: %d x %d from the side" % (piece["name"], w, h))
            continue
        cells = [view(BAKE / ("%s_%d.png" % (piece["name"], v)), w, h) for v in range(s["views"])]
        atlas = np.hstack(cells)
        Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT / (piece["name"] + "_impostor.png"), optimize=True)
        piece["impostor"] = {"views": s["views"], "half_wide": round(s["half_wide"], 4), "tall": round(s["tall"], 4),
                             "mid": round(s["mid"], 4), "cell": [w, h]}
        print("%-16s %d views of %d x %d" % (piece["name"], s["views"], w, h))
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")


if __name__ == "__main__":
    main()
