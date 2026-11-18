#!/usr/bin/env python3
"""Pack the baked impostor views into atlases and write the impostor LODs.

    python3 tools/build_fir.py assets/fir
    (cd tools/impostor && npm install && node bake.js ../../assets/fir)
    python3 tools/build_impostors.py assets/fir

Per tree:
  textures/impostors/<tree>_impostor_basecolor.png   RGBA atlas, four views side by side:
  textures/impostors/<tree>_impostor_normal.png      from +Z, +X and the two diagonals
  <tree>/<tree>_lod3_cross.gltf      a double cross: four planes 45 degrees apart, each
                                     a front and a back quad (16 triangles, single-sided)
  <tree>/<tree>_lod4_billboard.gltf  one quad facing +Z (2 triangles); rotate it about Y
                                     toward the camera in the engine
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, str(Path(__file__).parent))
import build_fir as bf  # noqa: E402

DEFAULT_VIEW = (256, 1024)        # texels per view; a manifest entry may set impostor_view


def load_view(color_path, normal_path, VIEW_W, VIEW_H):
    """2x supersampled hard-alpha renders -> alpha-weighted downsample + edge bleed."""
    c = np.asarray(Image.open(color_path).convert("RGBA")).astype(np.float32) / 255
    n = np.asarray(Image.open(normal_path).convert("RGBA")).astype(np.float32) / 255
    a = c[..., 3:4]
    fy, fx = c.shape[0] // VIEW_H, c.shape[1] // VIEW_W

    def box(x):
        return x.reshape(VIEW_H, fy, VIEW_W, fx, -1).mean(axis=(1, 3))

    asum = box(a)
    rgb = box(c[..., :3] * a) / np.maximum(asum, 1e-5)
    nrm = box(n[..., :3] * a) / np.maximum(asum, 1e-5)
    solid = asum[..., 0] > 0.5
    idx = ndi.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    rgb = rgb[idx[0], idx[1]]
    nrm = nrm[idx[0], idx[1]] * 2 - 1
    nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-5)
    return np.dstack([rgb, asum]), nrm * 0.5 + 0.5


def to_img(a, mode):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), mode)


def impostor_material(tree):
    t = bf.TEX + "impostors/" + tree
    return dict(name=tree + "_impostor", sampler=bf.SAMPLER_CLAMP,
                base=t + "_impostor_basecolor.png", normal=t + "_impostor_normal.png", orm=None,
                extra=dict(alphaMode="MASK", alphaCutoff=0.33, doubleSided=False),
                pbr=dict(roughnessFactor=0.8))


def plane(mesh, corner0, corner1, y0, y1, facing, u0, u1, top, back=False):
    """Quad from corner0 to corner1 (xz), y0..y1, textured with atlas columns u0..u1.

    Vertex normals lean mostly upward with a little of the facing direction: a flat
    plane normal would light one side of the cross and leave the other black, which a
    real crown never does.  `back` emits the reverse-facing twin of the quad."""
    f = -np.asarray(facing, float) if back else np.asarray(facing, float)
    normal = tuple(bf.norm(f * 0.5 + bf.UP * 0.85))

    def v(xz, y, u, tv):
        sway = 0.25 * (max(y, 0) / top) ** 2
        return mesh.vert((xz[0], y, xz[1]), normal, (u, tv), (sway, 0.0))
    a, b = v(corner0, y0, u0, 1.0), v(corner1, y0, u1, 1.0)
    c, d = v(corner1, y1, u1, 0.0), v(corner0, y1, u0, 0.0)
    mesh.quad(*((d, c, b, a) if back else (a, b, c, d)))


def main():
    out = Path(sys.argv[1])
    bake = out / ".bake"
    frames = json.loads((bake / "frames.json").read_text())
    manifest = json.loads((out / "manifest.json").read_text())
    tex_dir = out / "textures" / "impostors"
    tex_dir.mkdir(parents=True, exist_ok=True)
    for entry in manifest:
        name, f = entry["name"], frames[entry["name"]]
        view = entry.get("impostor_view", DEFAULT_VIEW)
        # Four views side by side: from +Z, from +X, and from the two diagonals.
        cols, nrms = [], []
        for tag in ("z", "x", "a", "b"):
            c, n = load_view(bake / f"{name}_color_{tag}.png", bake / f"{name}_normal_{tag}.png", *view)
            cols.append(c)
            nrms.append(n)
        to_img(np.hstack(cols), "RGBA").save(tex_dir / f"{name}_impostor_basecolor.png", optimize=True)
        to_img(np.hstack(nrms), "RGB").save(tex_dir / f"{name}_impostor_normal.png", optimize=True)

        r, y0, y1 = f["radius"], f["y0"], f["y1"]
        mat = impostor_material(name)
        k = math.sqrt(0.5)
        dirs = [(0.0, 1.0), (1.0, 0.0), (k, k), (k, -k)]          # (x, z) the view was taken from
        # A DOUBLE CROSS: the first pair of planes at right angles, the second pair the
        # same, turned 45 degrees. Each plane is a front and a back quad.
        cross = bf.Mesh()
        for back in (False, True):
            for i, (dx, dz) in enumerate(dirs):
                right = (dz, -dx)                                 # the camera's right, in (x, z)
                plane(cross, (-r * right[0], -r * right[1]), (r * right[0], r * right[1]), y0, y1,
                      (dx, 0, dz), i / 4.0, (i + 1) / 4.0, entry["top"], back)
        bf.write_gltf(out / name / f"{name}_lod3_cross", f"{name}_LOD3", [(cross, mat)])
        bill = bf.Mesh()
        plane(bill, (-r, 0), (r, 0), y0, y1, (0, 0, 1), 0.0, 0.25, entry["top"])
        bf.write_gltf(out / name / f"{name}_lod4_billboard", f"{name}_LOD4", [(bill, mat)])

        entry["lods"] = entry["lods"][:3] + [
            dict(file=f"{name}/{name}_lod3_cross.gltf", triangles=cross.tris, vertices=len(cross.p)),
            dict(file=f"{name}/{name}_lod4_billboard.gltf", triangles=bill.tris, vertices=len(bill.p)),
        ]
        entry["impostor_size_m"] = [round(2 * r, 3), round(y1 - y0, 3)]
        print("impostor", name, "plane %.2f x %.2f m" % (2 * r, y1 - y0))
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
