#!/usr/bin/env python3
"""Procedural cliff chunks -> glTF 2.0: big rock masses to embed in the island's edge.

    python3 tools/build_cliff.py assets/cliff

Writes assets/cliff/<name>/<name>_lod{0..3}.gltf (+ .bin) and manifest.json.

Kinds:
  buttress  a broad mass standing against the wall
  pillar    a tall column, narrowing downward
  slab      a thick leaning plate
  shelf     a wide ledge that juts out part-way down
  fang      a hanging spike for the underside of the island

Each is a rounded block, stratified into ledges, chiselled by mostly-vertical
planes and tapered.  Y-up, metres.  THE ORIGIN IS AT THE TOP: y = 0 is where the
chunk meets the rim (or, for a fang, the underside), a little of it stands above,
and the rest hangs below.  Place by the rim height and sink it into the wall.
The game textures them in world space (shaders/SHADER_boulder.gdshader), so any
scale keeps its texel density.
"""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import build_fir as bf          # noqa: E402  (shared mesh buffer + glTF writer)
import build_boulder as bb      # noqa: E402  (icosphere)

# size = (width, height, depth) in metres; taper = width left at the bottom;
# above = fraction of the height standing above the origin; strata = ledge count
CHUNKS = [
    dict(name="cliff_buttress_a", seed=3,  size=(16, 26, 11), taper=0.55, above=0.10, strata=7, cuts=16),
    dict(name="cliff_buttress_b", seed=19, size=(22, 20, 12), taper=0.65, above=0.08, strata=5, cuts=20),
    dict(name="cliff_pillar_a",   seed=31, size=(8, 34, 7),   taper=0.45, above=0.12, strata=9, cuts=14),
    dict(name="cliff_pillar_b",   seed=47, size=(10, 44, 9),  taper=0.35, above=0.10, strata=11, cuts=18),
    dict(name="cliff_slab_a",     seed=53, size=(14, 22, 5),  taper=0.70, above=0.10, strata=4, cuts=12, lean=0.22),
    dict(name="cliff_shelf_a",    seed=67, size=(18, 7, 12),  taper=0.60, above=0.30, strata=3, cuts=12),
    dict(name="cliff_fang_a",     seed=71, size=(9, 30, 8),   taper=0.04, above=0.03, strata=8, cuts=14),
    dict(name="cliff_fang_b",     seed=89, size=(13, 48, 11), taper=0.03, above=0.03, strata=12, cuts=18),
]
LODS = [("lod0", 4), ("lod1", 3), ("lod2", 2), ("lod3", 1)]   # 5120 / 1280 / 320 / 80 triangles


def material_rock():
    t = "../../../textures/polyhaven/dark_rock_02_"
    return dict(name="cliff_rock", sampler=bf.SAMPLER_REPEAT, base=t + "basecolor.jpg",
                normal=t + "normal.jpg", orm=t + "orm.jpg", extra=dict(),
                pbr=dict(roughnessFactor=1.0))


def shape(dirs, c):
    rng = np.random.default_rng(c["seed"])
    # a rounded block rather than a ball
    cube = dirs / np.abs(dirs).max(axis=1, keepdims=True)
    p = dirs * 0.4 + cube * 0.6
    # chisel: fracture planes, mostly vertical faces
    for _ in range(c["cuts"]):
        n = rng.normal(size=3)
        n[1] *= 0.3
        n = bf.norm(n)
        d = rng.uniform(0.42, 0.9)
        over = np.clip(p @ n - d, 0, None)
        p -= np.outer(over, n)
    t = np.clip((1 - p[:, 1]) / 2, 0, 1)                  # 0 at the top, 1 at the bottom
    # strata: each bed stands a little proud of, or back from, its neighbours
    beds = c["strata"]
    wobble = 0.35 * np.sin(dirs[:, 0] * 2.3 + rng.uniform(0, 6)) * np.cos(dirs[:, 2] * 1.9)
    f = t * beds + wobble
    step = rng.uniform(-0.5, 0.5, size=beds + 3)
    i = np.clip(np.floor(f).astype(int) + 1, 0, beds + 1)
    frac = f - np.floor(f)
    edge = np.clip((frac - 0.5) / 0.18 + 0.5, 0, 1)       # a short ramp between beds = a ledge
    bed = step[i] * (1 - edge) + step[i + 1] * edge
    p[:, [0, 2]] *= (1 + 0.30 * bed)[:, None]
    # broad dents
    for amp, freq in ((0.16, 1.4), (0.09, 3.3), (0.05, 7.0)):
        w = rng.normal(size=(3, 3)) * freq
        ph = rng.uniform(0, 6.28, size=3)
        p[:, [0, 2]] *= (1 + amp * np.sin(dirs @ w.T + ph).prod(axis=1))[:, None]
    # taper toward the bottom, lean, and size
    p[:, [0, 2]] *= (1 + (c["taper"] - 1) * t ** 1.4)[:, None]
    W, Ht, D = c["size"]
    p[:, 0] *= W / 2 / np.abs(p[:, 0]).max()
    p[:, 2] *= D / 2 / np.abs(p[:, 2]).max()
    y0, y1 = p[:, 1].min(), p[:, 1].max()
    p[:, 1] = (p[:, 1] - y1) / (y1 - y0) * Ht + c["above"] * Ht
    p[:, 2] += c.get("lean", 0.0) * p[:, 1]
    return p


def build(c, level):
    dirs, faces = bb.icosphere(level)
    p = shape(dirs, c)
    fn = np.cross(p[faces[:, 1]] - p[faces[:, 0]], p[faces[:, 2]] - p[faces[:, 0]])
    n = np.zeros_like(p)
    for k in range(3):
        np.add.at(n, faces[:, k], fn)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    mesh = bf.Mesh()
    for i in range(len(p)):
        mesh.vert(p[i], n[i], (p[i][0] * 0.12, -p[i][1] * 0.12), (0.0, 0.0))
    mesh.idx = [int(i) for i in faces.reshape(-1)]
    return mesh


def main():
    out = Path(sys.argv[1])
    manifest = []
    for c in CHUNKS:
        entry = dict(name=c["name"], size_m=list(c["size"]), above_origin_m=round(c["above"] * c["size"][1], 2), lods=[])
        for lod, level in LODS:
            mesh = build(c, level)
            stem = f'{c["name"]}_{lod}'
            bf.write_gltf(out / c["name"] / stem, stem.replace("_lod", "_LOD"), [(mesh, material_rock())])
            entry["lods"].append(dict(file=f'{c["name"]}/{stem}.gltf', triangles=mesh.tris, vertices=len(mesh.p)))
        print(c["name"], c["size"], " / ".join(str(l["triangles"]) for l in entry["lods"]))
        manifest.append(entry)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
