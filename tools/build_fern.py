#!/usr/bin/env python3
"""Procedural ferns -> glTF 2.0: a few sizes / variants, three mesh LODs each.

    python3 tools/build_fern.py assets/fern

Writes assets/fern/<fern>/<fern>_lod{0,1,2}.gltf (+ .bin) and assets/fern/manifest.json.
Impostor LODs (cross planes, billboard) are added by tools/build_impostors.py.

A fern is a rosette of arching frond cards cut from the frond photo: young upright
fronds in the middle, older ones arching over and drooping around them.
Y-up, metres, origin on the ground at the centre of the crown.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import build_fir as bf  # noqa: E402  (shared mesh buffer + glTF writer)

STEM_V = 0.485           # v of the stem in the frond card (printed by key_magenta.py)
CARD_ASPECT = 0.5        # card width / length (1024x512 texture)
GOLDEN = math.pi * (3 - math.sqrt(5))

# name, seed, frond count, typical frond length (m)
FERNS = [
    dict(name="fern_small_a",  seed=3,  fronds=9,  length=0.45),
    dict(name="fern_medium_a", seed=14, fronds=13, length=0.75),
    dict(name="fern_medium_b", seed=27, fronds=11, length=0.85),
    dict(name="fern_large_a",  seed=41, fronds=17, length=1.15),
]

# segs: quads along a frond; fold: extra centre row of vertices so the frond is a shallow V;
# keep (n, d): keep n of every d fronds, widened to hold the silhouette
LODS = [
    dict(name="lod0", segs=6, fold=True,  keep=(1, 1), widen=1.0),
    dict(name="lod1", segs=3, fold=False, keep=(1, 1), widen=1.0),
    dict(name="lod2", segs=2, fold=False, keep=(2, 3), widen=1.25),
]


def material_frond():
    return dict(name="fern_frond", sampler=bf.SAMPLER_CLAMP,
                base=bf.TEX + "fern_frond_basecolor.png", normal=None, orm=None,
                extra=dict(alphaMode="MASK", alphaCutoff=0.4, doubleSided=True),
                pbr=dict(roughnessFactor=0.7))


def describe(fern):
    rng = np.random.default_rng(fern["seed"])
    n = fern["fronds"]
    az0 = rng.uniform(0, 2 * math.pi)
    fronds = []
    for k in range(n):
        f = (k + 0.5) / n                                   # 0 = innermost, 1 = outermost
        fronds.append(dict(
            az=az0 + k * GOLDEN + rng.uniform(-0.25, 0.25),
            L=fern["length"] * (0.62 + 0.5 * f) * rng.uniform(0.85, 1.15),
            th0=math.radians(6 + 30 * f + rng.uniform(-5, 5)),      # lean from vertical at the base
            th1=math.radians(58 + 68 * f + rng.uniform(-10, 10)),   # ... and at the tip
            twist=rng.uniform(-0.35, 0.35), side=rng.uniform(-0.12, 0.12),
            tint=rng.uniform(0.85, 1.08), phase=rng.uniform(0, 1), flip=rng.random() < 0.5))
    return fronds


def frond_curve(fr, segs):
    """Centre line in the frond's own (outward, up) plane, plus the tangent angle."""
    pts, r, h, sub = [], 0.02 + 0.03 * fr["L"], 0.0, 8
    for i in range(segs * sub + 1):
        s = i / (segs * sub)
        th = fr["th0"] + (fr["th1"] - fr["th0"]) * s ** 1.4
        if i % sub == 0:
            pts.append((s, r, h, th))
        r += math.sin(th) * fr["L"] / (segs * sub)
        h += math.cos(th) * fr["L"] / (segs * sub)
    return pts


def build(fronds, lod):
    mesh = bf.Mesh(color=True)
    for k, fr in enumerate(fronds):
        if k % lod["keep"][1] >= lod["keep"][0]:
            continue
        out = np.array([math.cos(fr["az"]), 0.0, math.sin(fr["az"])])
        side = np.array([-out[2], 0.0, out[0]])
        width = fr["L"] * CARD_ASPECT * lod["widen"]
        wa = STEM_V if not fr["flip"] else 1 - STEM_V       # share of the width on the +side edge
        va, vb = (0.0, 1.0) if not fr["flip"] else (1.0, 0.0)
        rows = []
        for s, r, h, th in frond_curve(fr, lod["segs"]):
            p = out * r + bf.UP * h + side * (fr["side"] * fr["L"] * s * s)
            T = out * math.sin(th) + bf.UP * math.cos(th)
            S = bf.rotate(side, T, fr["twist"] * s)
            N = np.cross(S, T)                               # upper face of the frond
            if N[1] < 0:
                N = -N
            lift = N * (0.07 * width * math.sin(math.pi * min(1.0, s * 1.2)))   # edges of the V
            n = bf.norm(N * 0.6 + bf.UP * 0.5 + out * 0.25)
            shade = (0.55 + 0.45 * min(1.0, s * 1.6)) * fr["tint"]
            c = (0.94 * shade, shade, 0.9 * shade)
            w = (s * s, fr["phase"])
            row = [mesh.vert(p + S * (width * wa) + lift, n, (s, va), w, c)]
            if lod["fold"]:
                row.append(mesh.vert(p, n, (s, va + (vb - va) * wa), w, c))
            row.append(mesh.vert(p - S * (width * (1 - wa)) + lift, n, (s, vb), w, c))
            rows.append(row)
        for a, b in zip(rows, rows[1:]):
            for j in range(len(a) - 1):
                mesh.quad(a[j], a[j + 1], b[j + 1], b[j])
    return mesh


def main():
    out_dir = Path(sys.argv[1])
    manifest = []
    for fern in FERNS:
        fronds = describe(fern)
        entry = dict(name=fern["name"], lods=[], impostor_view=[256, 128])
        for lod in LODS:
            mesh = build(fronds, lod)
            stem = f'{fern["name"]}_{lod["name"]}'
            bf.write_gltf(out_dir / fern["name"] / stem, stem.replace("_lod", "_LOD"),
                          [(mesh, material_frond())])
            p = np.asarray(mesh.p)
            if lod["name"] == "lod0":
                entry["radius"] = float(np.abs(p[:, [0, 2]]).max())
                entry["top"] = float(p[:, 1].max())
                entry["height"] = round(entry["top"], 2)
            entry["lods"].append(dict(file=f'{fern["name"]}/{stem}.gltf',
                                      triangles=mesh.tris, vertices=len(p)))
        print(f'{fern["name"]:14s} {entry["top"]:.2f} m tall, {2 * entry["radius"]:.2f} m wide, tris ' +
              " / ".join(str(l["triangles"]) for l in entry["lods"]))
        manifest.append(entry)
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
