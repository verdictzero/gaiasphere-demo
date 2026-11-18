#!/usr/bin/env python3
"""Compose whole fir boughs out of the keyed twig photo, for the mid-distance tree LODs.

    python3 tools/build_bough_atlas.py assets/fir

Writes textures/fir_bough_atlas_basecolor.png (2048x1024, four boughs side by side,
root at the bottom) and textures/fir_bough_atlas.json (each bough's size in metres).

LOD0 of a fir hangs a dozen twig cards on every limb. The mid LODs cannot afford
that, and dropping twigs or enlarging them changes how the tree looks. So each
limb's twigs are flattened here into ONE picture of the bough, laid out by the same
rule build_fir.py uses (spacing, length, angle, alternating sides), and the mid
LODs draw one card per limb with it: the needles keep their true size and number.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

LIMB_LENGTHS = [1.3, 2.3, 3.4, 4.6]      # one bough per class of limb length, metres
COLS, CELL_W, CELL_H = 4, 512, 1024
STEM_V = 0.451
S0, S1 = 0.12, 0.9                        # the stretch of limb a bough card covers


def frond_len(L):
    return min(1.9, 0.5 * L + 0.4)


def tip_len(L):
    return min(1.9, 0.5 * L + 0.45)


def layout(L, rng):
    """Twigs along a limb of length L, as (distance along, signed angle, length)."""
    out = []
    # A little closer together than on the tree: this one picture also stands for the
    # hanging twigs and the rolled ones that give the real bough its thickness.
    step = (0.30 + 0.04 * L) * 0.72
    pos = 0.22 * L + rng.uniform(0, step)
    side = 1 if rng.random() < 0.5 else -1
    while pos < L * 0.97:
        s = pos / L
        out.append((pos, side * math.radians(rng.uniform(38, 62)),
                    frond_len(L) * (1 - 0.4 * s) * rng.uniform(0.85, 1.15)))
        side = -side
        pos += step * rng.uniform(0.8, 1.2)
    for _ in range(int(L > 1.2) + int(L > 2.2) + int(L > 3.2)):
        out.append((rng.uniform(0.45, 0.88) * L, math.radians(rng.uniform(-24, 24)),
                    min(1.5, 0.35 * L + 0.4) * rng.uniform(0.8, 1.1)))
    out.sort()
    out.append((S1 * L, 0.0, tip_len(L)))
    return out


def main():
    root = Path(sys.argv[1]) / "textures"
    twig = Image.open(root / "fir_branch_basecolor.png").convert("RGBA")
    atlas = Image.new("RGBA", (COLS * CELL_W, CELL_H), (0, 0, 0, 0))
    meta = []
    rng = np.random.default_rng(4)
    for c, L in enumerate(LIMB_LENGTHS):
        twigs = layout(L, rng)
        length = (S1 - S0) * L + tip_len(L)
        half = max(abs(math.sin(a)) * ln + 0.3 * ln * abs(math.cos(a)) for _, a, ln in twigs) + 0.05
        ppm = min((CELL_H - 8) / length, (CELL_W - 8) / (2 * half))
        cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        # the limb itself, under everything
        wood = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        wpx = np.zeros((CELL_H, CELL_W, 4), np.uint8)
        x_mid = CELL_W // 2
        y_tip = int(CELL_H - 4 - (S1 - S0) * L * ppm)
        r = max(1, int(0.005 * L * ppm))
        wpx[y_tip:CELL_H - 4, x_mid - r:x_mid + r + 1] = (74, 56, 40, 255)
        cell.alpha_composite(Image.fromarray(wpx, "RGBA"))
        for pos, ang, ln in twigs:
            w = max(2, int(ln * ppm))
            h = max(2, int(ln * 0.6 * ppm))
            card = twig.resize((w, h), Image.LANCZOS)
            shade = rng.uniform(0.82, 1.05) * (0.8 + 0.2 * pos / L)     # inner twigs sit in shade
            a = np.asarray(card).astype(np.float32)
            a[..., :3] *= shade
            card = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
            if rng.random() < 0.5:                                    # mirror about the stem
                card = card.transpose(Image.FLIP_TOP_BOTTOM)
                stem = h * (1 - STEM_V)
            else:
                stem = h * STEM_V
            # the card's +x is the twig's direction; turn it to point up the limb, then by its angle
            deg = 90.0 - math.degrees(ang)
            rot = card.rotate(deg, resample=Image.BICUBIC, expand=True)
            # where the twig's root (x 0, y stem) went under that rotation
            th = math.radians(deg)
            dx, dy = -w / 2, stem - h / 2
            rx = dx * math.cos(th) + dy * math.sin(th) + rot.width / 2
            ry = -dx * math.sin(th) + dy * math.cos(th) + rot.height / 2
            px = x_mid - rx
            py = (CELL_H - 4 - (pos - S0 * L) * ppm) - ry
            layer = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
            layer.paste(rot, (int(round(px)), int(round(py))))
            cell.alpha_composite(layer)
        atlas.paste(cell, (c * CELL_W, 0))
        meta.append(dict(limb_length=L, length_m=round((CELL_H - 8) / ppm, 4),
                         width_m=round(CELL_W / ppm, 4), frond_len=frond_len(L)))
    o = np.asarray(atlas).astype(np.float32) / 255
    solid = o[..., 3] > 0.6
    idx = ndi.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    o[..., :3] = np.where(solid[..., None], o[..., :3], o[idx[0], idx[1], :3])
    Image.fromarray((o * 255 + 0.5).astype(np.uint8), "RGBA").save(root / "fir_bough_atlas_basecolor.png", optimize=True)
    (root / "fir_bough_atlas.json").write_text(json.dumps(meta, indent=1))
    print("boughs:", [(m["limb_length"], m["length_m"], m["width_m"]) for m in meta])


if __name__ == "__main__":
    main()
