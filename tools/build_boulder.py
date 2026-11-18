#!/usr/bin/env python3
"""Procedural boulders -> glTF 2.0: five shapes, three mesh LODs each.

    python3 tools/build_boulder.py assets/boulder

Writes assets/boulder/<name>/<name>_lod{0,1,2}.gltf (+ .bin) and manifest.json.

Each boulder is a sphere chiselled by random planes (the flat, fractured faces),
then squashed, dented and sat a little into the ground.  Every LOD evaluates the
same shape function at a coarser subdivision, so they share a silhouette.
About 2 m across; scale instances freely: the game shader textures them in
world space (shaders/SHADER_boulder.gdshader), so texel density does not stretch.
Y-up, metres, origin at ground level under the centre.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import build_fir as bf  # noqa: E402  (shared mesh buffer + glTF writer)

# name, seed, squash (x, y, z), number of chisel planes, roughness of the surface
BOULDERS = [
    dict(name="boulder_a", seed=5,  squash=(1.00, 0.72, 0.86), cuts=14, rough=0.05),
    dict(name="boulder_b", seed=17, squash=(1.00, 0.55, 0.70), cuts=18, rough=0.04),
    dict(name="boulder_c", seed=29, squash=(0.80, 0.95, 0.78), cuts=11, rough=0.07),
    dict(name="boulder_d", seed=43, squash=(1.00, 0.42, 0.92), cuts=22, rough=0.03),
    dict(name="boulder_e", seed=61, squash=(0.92, 0.80, 0.62), cuts=16, rough=0.06),
]
LODS = [("lod0", 3), ("lod1", 2), ("lod2", 1)]     # icosphere subdivisions: 1280 / 320 / 80 tris
SINK = 0.14                                          # fraction of the height buried


def material_rock():
    t = "../../../textures/polyhaven/mossy_rock_"
    return dict(name="boulder_rock", sampler=bf.SAMPLER_REPEAT, base=t + "basecolor.jpg",
                normal=t + "normal.jpg", orm=t + "orm.jpg", extra=dict(),
                pbr=dict(roughnessFactor=1.0))


def icosphere(level):
    t = (1 + 5 ** 0.5) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t),
         (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    v = [bf.norm(np.array(p, float)) for p in v]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4),
         (11, 10, 2), (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8),
         (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    for _ in range(level):
        mid, nf = {}, []

        def m(a, b):
            k = (min(a, b), max(a, b))
            if k not in mid:
                v.append(bf.norm(v[a] + v[b]))
                mid[k] = len(v) - 1
            return mid[k]
        for a, b, c in f:
            ab, bc, ca = m(a, b), m(b, c), m(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        f = nf
    return np.array(v), np.array(f)


def shape(dirs, b):
    """Unit directions -> boulder surface points."""
    rng = np.random.default_rng(b["seed"])
    p = dirs.copy()
    for _ in range(b["cuts"]):                       # chisel: clip against random planes
        n = bf.norm(rng.normal(size=3))
        d = rng.uniform(0.62, 0.93)
        over = np.clip(p @ n - d, 0, None)
        p -= np.outer(over, n)
    # broad dents and bulges, then fine roughness, both as smooth functions of direction
    for amp, freq in ((0.10, 1.7), (0.06, 3.1), (b["rough"], 6.3), (b["rough"] * 0.5, 12.0)):
        w = rng.normal(size=(3, 3)) * freq
        ph = rng.uniform(0, 6.28, size=3)
        p *= (1 + amp * (np.sin(dirs @ w.T + ph).prod(axis=1)))[:, None]
    p *= np.array(b["squash"])
    p /= np.abs(p[:, [0, 2]]).max()                  # ~2 m across
    y0, y1 = p[:, 1].min(), p[:, 1].max()
    p[:, 1] -= y0 + SINK * (y1 - y0)
    return p


def build(b, level):
    dirs, faces = icosphere(level)
    p = shape(dirs, b)
    fn = np.cross(p[faces[:, 1]] - p[faces[:, 0]], p[faces[:, 2]] - p[faces[:, 0]])
    n = np.zeros_like(p)
    for k in range(3):
        np.add.at(n, faces[:, k], fn)                # area-weighted vertex normals
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    mesh = bf.Mesh()
    for i in range(len(p)):
        # UVs only matter outside the game (its shader is triplanar): a top-down projection
        mesh.vert(p[i], n[i], (p[i][0] * 0.5, p[i][2] * 0.5), (0.0, 0.0))
    mesh.idx = [int(i) for i in faces.reshape(-1)]
    return mesh


def main():
    out = Path(sys.argv[1])
    manifest = []
    for b in BOULDERS:
        entry = dict(name=b["name"], lods=[])
        for lod, level in LODS:
            mesh = build(b, level)
            stem = f'{b["name"]}_{lod}'
            bf.write_gltf(out / b["name"] / stem, stem.replace("_lod", "_LOD"), [(mesh, material_rock())])
            p = np.asarray(mesh.p)
            if lod == "lod0":
                entry["size_m"] = [round(float(v), 2) for v in p.max(axis=0) - p.min(axis=0)]
            entry["lods"].append(dict(file=f'{b["name"]}/{stem}.gltf', triangles=mesh.tris,
                                      vertices=len(p)))
        print(b["name"], entry["size_m"], " / ".join(str(l["triangles"]) for l in entry["lods"]))
        manifest.append(entry)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
