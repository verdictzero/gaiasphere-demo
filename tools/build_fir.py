#!/usr/bin/env python3
"""Procedural fir trees -> glTF 2.0: several sizes / variants, three mesh LODs each.

    python3 tools/build_fir.py assets/fir

Writes assets/fir/<tree>/<tree>_lod{0,1,2}.gltf (+ .bin) and assets/fir/manifest.json.
Impostor LODs (cross planes, billboard) are added by tools/build_impostors.py.

Y-up, metres, origin at the base of the trunk.
Materials: `fir_bark` (opaque, tiling Poly Haven pine_bark) and
`fir_foliage` (alpha-masked cards cut from the branch photo).
Vertex streams: POSITION, NORMAL, TEXCOORD_0, TEXCOORD_1 (wind: weight, phase)
and COLOR_0 on foliage (baked crown-interior darkening).
"""
import json
import math
import sys
from pathlib import Path

import numpy as np

# name, seed, height, trunk radius, crown start (fraction of height), longest limb,
# trunk bend phase
TREES = [
    dict(name="fir_small_a",  seed=11, H=11.0, base_r=0.13, crown=0.10, l_max=2.3, bend=1.0),
    dict(name="fir_small_b",  seed=23, H=14.0, base_r=0.17, crown=0.14, l_max=2.6, bend=2.3),
    dict(name="fir_medium_a", seed=31, H=20.0, base_r=0.26, crown=0.18, l_max=3.5, bend=4.1),
    dict(name="fir_medium_b", seed=47, H=23.0, base_r=0.30, crown=0.24, l_max=3.3, bend=5.2),
    dict(name="fir_tall_a",   seed=7,  H=30.0, base_r=0.42, crown=0.27, l_max=4.6, bend=0.0),
    dict(name="fir_tall_b",   seed=59, H=33.0, base_r=0.46, crown=0.34, l_max=4.3, bend=3.0),
    dict(name="fir_giant_a",  seed=71, H=40.0, base_r=0.62, crown=0.36, l_max=5.4, bend=1.7),
    dict(name="fir_giant_b",  seed=83, H=44.0, base_r=0.70, crown=0.44, l_max=5.0, bend=4.6),
]

SEED = 7
H = 30.0                 # tree height
BASE_R = 0.42            # trunk radius just above the root flare
CROWN_START = 0.27       # fraction of H where branches begin
L_MAX = 4.6              # longest limb
BEND = 0.0
STEM_V = 0.451           # v of the stem in the foliage card (from key_branch.py)
BARK_TILE_M = 1.6        # metres of trunk covered by one bark tile (v)
UP = np.array([0.0, 1.0, 0.0])


def configure(tree):
    global SEED, H, BASE_R, CROWN_START, L_MAX, BEND
    SEED, H, BASE_R = tree["seed"], tree["H"], tree["base_r"]
    CROWN_START, L_MAX, BEND = tree["crown"], tree["l_max"], tree["bend"]


def norm(v):
    return v / (np.linalg.norm(v) + 1e-12)


# ----------------------------------------------------------------- trunk ---
def trunk_radius(y):
    t = np.clip(y / H, 0, 1)
    return BASE_R * (1 - t) ** 0.9 + 0.015 + 0.52 * BASE_R * math.exp(-y / (0.2 + 0.6 * BASE_R))


def trunk_center(y):
    t = y / H
    k = H / 30.0
    return np.array([0.22 * k * math.sin(t * 2.6 + 0.4 + BEND) * t,
                     y,
                     0.16 * k * math.sin(t * 3.7 + 1.9 + 1.7 * BEND) * t])


# ------------------------------------------------------- tree description ---
def describe_tree():
    """Everything random is decided here so all LODs describe the same tree."""
    rng = np.random.default_rng(SEED)
    limbs = []
    y = H * CROWN_START
    az = rng.uniform(0, 2 * math.pi)
    while y < H - 0.5:
        t = (y - H * CROWN_START) / (H * (1 - CROWN_START))
        n = int(rng.integers(5, 9)) if t > 0.1 else int(rng.integers(2, 4))
        az += rng.uniform(0.5, 1.2)
        for i in range(n):
            a = az + 2 * math.pi * i / n + rng.uniform(-0.3, 0.3)
            ramp = 0.45 + 0.55 * min(1.0, t / 0.16)          # short, sparse lowest limbs
            L = L_MAX * (1 - t) ** 0.85 * ramp * rng.uniform(0.8, 1.12) + 0.35
            elev = math.radians(-22 + 60 * t + rng.uniform(-7, 7))
            limb = dict(y=y + rng.uniform(-0.12, 0.12), az=a, L=L, elev=elev, t=t,
                        sag=rng.uniform(0.10, 0.2) * (1 - 0.6 * t),
                        tint=rng.uniform(0.86, 1.06), phase=rng.uniform(0, 1), fronds=[])
            # side twigs alternate left / right along the limb
            step = 0.30 + 0.04 * L
            s_pos = 0.22 * L + rng.uniform(0, step)
            side = 1 if rng.random() < 0.5 else -1
            while s_pos < L * 0.97:
                s = s_pos / L
                flen = min(1.9, 0.5 * L + 0.4) * (1 - 0.4 * s) * rng.uniform(0.85, 1.15)
                limb["fronds"].append(dict(kind="side", s=s, side=side, len=flen,
                                           yaw=math.radians(rng.uniform(38, 62)),
                                           droop=rng.uniform(0.12, 0.42),
                                           roll=rng.uniform(-0.7, 0.7),
                                           flip=rng.random() < 0.5))
                side = -side
                s_pos += step * rng.uniform(0.8, 1.2)
            # hanging drapes give the bough thickness when seen edge-on
            for _ in range(int(L > 1.2) + int(L > 2.2) + int(L > 3.2)):
                limb["fronds"].append(dict(kind="drape", s=rng.uniform(0.45, 0.9), side=1,
                                           len=min(1.5, 0.35 * L + 0.4) * rng.uniform(0.8, 1.1),
                                           yaw=rng.uniform(-0.5, 0.5), droop=rng.uniform(1.0, 1.5),
                                           roll=rng.uniform(1.1, 2.0), flip=rng.random() < 0.5))
            limb["fronds"].append(dict(kind="tip", s=0.9, side=1,
                                       len=min(1.9, 0.5 * L + 0.45), yaw=0.0, droop=0.0,
                                       roll=rng.uniform(-0.3, 0.3), flip=rng.random() < 0.5))
            limbs.append(limb)
        y += (0.60 - 0.32 * t) * (H / 30.0) ** 0.5 * rng.uniform(0.85, 1.15)
    return limbs


def limb_point(limb, s):
    """Point on the limb centre line, s in [0, 1+]."""
    L, e = limb["L"], limb["elev"]
    out = np.array([math.cos(limb["az"]), 0.0, math.sin(limb["az"])])
    base = trunk_center(limb["y"]) + out * trunk_radius(limb["y"]) * 0.6
    horiz = L * s * math.cos(e)
    vert = L * (math.sin(e) * s - limb["sag"] * 2.2 * s * (1 - s) + 0.10 * s ** 3)
    return base + out * horiz + UP * vert


def limb_frame(limb, s):
    T = norm(limb_point(limb, s + 0.02) - limb_point(limb, s - 0.02))
    S = norm(np.cross(T, UP))
    N = np.cross(S, T)
    return T, S, N


# ------------------------------------------------------------ mesh buffer ---
class Mesh:
    def __init__(self, color=False):
        self.p, self.n, self.uv, self.uv1, self.c, self.idx = [], [], [], [], [], []
        self.color = color

    def vert(self, p, n, uv, wind, c=(1, 1, 1)):
        self.p.append(p); self.n.append(n); self.uv.append(uv); self.uv1.append(wind)
        self.c.append(c)
        return len(self.p) - 1

    def quad(self, a, b, c, d):
        self.idx += [a, b, c, a, c, d]
        if self.color:
            # foliage: back faces reuse the same vertices (and therefore the same
            # outward "volume" normals) so the underside of a bough is not shaded black
            # the way an engine-flipped double-sided normal would make it
            self.idx += [c, b, a, d, c, a]

    @property
    def tris(self):
        return len(self.idx) // 3


def add_tube(mesh, pts, radii, sides, v_coords, u_rep, winds):
    """Tube along pts with a duplicated seam column; closed by tapering."""
    rings = []
    ref = np.array([1.0, 0, 0])
    for i, p in enumerate(pts):
        T = norm(pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)])
        A = norm(ref - T * np.dot(ref, T))
        B = np.cross(T, A)
        ring = []
        for k in range(sides + 1):
            a = 2 * math.pi * k / sides
            d = A * math.cos(a) + B * math.sin(a)
            ring.append(mesh.vert(p + d * radii[i], d, (u_rep * k / sides, v_coords[i]), winds[i]))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            mesh.quad(rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k])


def add_card(mesh, origin, T, S, N, length, width, segs, bend, flip, color, wind0, wind1,
             center, u0=0.0, u1=1.0):
    """Foliage card. Stem runs along T from origin; `bend` curls the tip along -N.
    Normals are biased outward from the crown axis for soft, volume-like shading."""
    va, vb = (0.0, 1.0) if not flip else (1.0, 0.0)
    wa = STEM_V if not flip else 1 - STEM_V          # width on the +S side
    rows = []
    for i in range(segs + 1):
        f = i / segs
        p = origin + T * (length * f) - N * (bend * length * f * f)
        outward = p - center
        outward[1] *= 0.35
        n = norm(norm(outward) * 0.8 + UP * 0.6)
        w = (wind0 + (wind1 - wind0) * f, wind_phase(mesh))
        c = tuple(np.asarray(color) * (0.82 + 0.18 * f))
        u = u0 + (u1 - u0) * f
        a = mesh.vert(p + S * (width * wa), n, (u, va), w, c)
        b = mesh.vert(p - S * (width * (1 - wa)), n, (u, vb), w, c)
        rows.append((a, b))
    for i in range(segs):
        mesh.quad(rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0])


_phase = [0.0]


def wind_phase(_mesh):
    return _phase[0]


def rotate(v, axis, ang):
    c, s = math.cos(ang), math.sin(ang)
    return v * c + np.cross(axis, v) * s + axis * np.dot(axis, v) * (1 - c)


# ------------------------------------------------------------------- LODs ---
# frond_keep = (n, d): keep n of every d side twigs, enlarged by frond_scale to hold the
# silhouette.  All LODs are cut from the same tree description so they pop as little
# as possible.
LODS = [
    dict(name="lod0", trunk_sides=12, trunk_rings=18, limb_sides=3, limb_segs=3, card_segs=2,
         frond_keep=(1, 1), frond_scale=1.0, tip_scale=1.0, drapes=3, limb_min=0.8),
    dict(name="lod1", trunk_sides=8, trunk_rings=10, limb_sides=3, limb_segs=2, card_segs=1,
         frond_keep=(1, 2), frond_scale=1.45, tip_scale=1.15, drapes=1, limb_min=2.2),
    dict(name="lod2", trunk_sides=6, trunk_rings=7, limb_sides=0, limb_segs=0, card_segs=1,
         frond_keep=(1, 4), frond_scale=2.1, tip_scale=1.5, drapes=0, limb_min=99),
]


def build(limbs, lod):
    bark, leaf = Mesh(), Mesh(color=True)

    # trunk: rings packed toward the flared base
    ys = [H * (i / (lod["trunk_rings"] - 1)) ** 1.6 for i in range(lod["trunk_rings"])]
    pts = [trunk_center(y) for y in ys]
    radii = [trunk_radius(y) if y < H else 0.004 for y in ys]
    _phase[0] = 0.0
    add_tube(bark, pts, radii, lod["trunk_sides"], [y / BARK_TILE_M for y in ys], 2.0,
             [(0.25 * (y / H) ** 2, 0.0) for y in ys])

    for li, limb in enumerate(limbs):
        L, t = limb["L"], limb["t"]
        _phase[0] = limb["phase"]
        sway0 = 0.25 * (limb["y"] / H) ** 2
        center = trunk_center(limb["y"])
        depth = lambda s: 0.5 + 0.5 * min(1.0, (L * s) / (0.55 * L_MAX * (1 - t) + 0.6))
        tint = limb["tint"]
        col = lambda s: (0.93 * tint * depth(s), tint * depth(s), 0.90 * tint * depth(s))

        if lod["limb_sides"] and L >= lod["limb_min"]:
            n = lod["limb_segs"]
            ss = [i / n * 0.93 for i in range(n + 1)]
            r0 = min(0.010 + 0.011 * L, trunk_radius(limb["y"]) * 0.5)
            add_tube(bark, [limb_point(limb, s) for s in ss],
                     [r0 * (1 - 0.85 * s) for s in ss], lod["limb_sides"],
                     [L * s / 0.5 for s in ss], 1.0,
                     [(sway0 + 0.5 * s * s, limb["phase"]) for s in ss])

        k = nd = 0
        for fr in limb["fronds"]:
            if fr["kind"] == "drape":
                nd += 1
                if nd > lod["drapes"]:
                    continue
            if fr["kind"] == "side":
                k += 1
                if (k + li) % lod["frond_keep"][1] >= lod["frond_keep"][0]:
                    continue
            s = fr["s"]
            T, S, N = limb_frame(limb, s)
            if fr["kind"] == "side":
                d = norm(T * math.cos(fr["yaw"]) + S * fr["side"] * math.sin(fr["yaw"])
                         - N * fr["droop"] * 0.35)
            elif fr["kind"] == "drape":
                d = norm(rotate(T, UP, fr["yaw"]) * 0.75 - UP * fr["droop"] * 0.6)
            else:
                d = T
            cs = norm(np.cross(d, N))
            cs = rotate(cs, d, fr["roll"])
            cn = np.cross(cs, d)
            if cn[1] < 0 and fr["kind"] != "drape":
                cn, cs = -cn, -cs
            ln = fr["len"] * (lod["frond_scale"] if fr["kind"] == "side" else lod["tip_scale"])
            add_card(leaf, limb_point(limb, s), d, cs, cn, ln, ln * 0.6,
                     lod["card_segs"] if fr["kind"] != "side" else 1,
                     0.10 + 0.5 * fr["droop"] * 0.3, fr["flip"], col(s),
                     sway0 + 0.5 * s * s, sway0 + 0.5 * s * s + 0.35, center)

    # leader: crossed upright cards so the top comes to a point
    lead = 2.1 * min(1.0, (H / 30.0) ** 0.5)
    top = trunk_center(H - 0.72 * lead)
    _phase[0] = 0.5
    for i in range(3 if lod["name"] != "lod2" else 2):
        a = math.pi * i / (3 if lod["name"] != "lod2" else 2)
        S = np.array([math.cos(a), 0, math.sin(a)])
        add_card(leaf, top, UP, S, np.cross(S, UP), lead, lead * 0.48, 1, 0.0, i % 2 == 0,
                 (0.95, 1.0, 0.92), 0.25, 0.4, top - UP)
    return bark, leaf


# ------------------------------------------------------------ glTF writer ---
TEX = "../textures/"
SAMPLER_REPEAT = dict(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497)
SAMPLER_CLAMP = dict(magFilter=9729, minFilter=9987, wrapS=33071, wrapT=33071)


def material_bark():
    return dict(name="fir_bark", sampler=SAMPLER_REPEAT,
                base=TEX + "pine_bark_basecolor.jpg", normal=TEX + "pine_bark_normal.jpg",
                orm=TEX + "pine_bark_orm.jpg", extra=dict(), pbr=dict(roughnessFactor=1.0))


def material_foliage():
    # single-sided on purpose, see Mesh.quad
    return dict(name="fir_foliage", sampler=SAMPLER_CLAMP,
                base=TEX + "fir_branch_basecolor.png", normal=None, orm=None,
                extra=dict(alphaMode="MASK", alphaCutoff=0.38, doubleSided=False),
                pbr=dict(roughnessFactor=0.62, baseColorFactor=[0.84, 0.96, 0.86, 1.0]))


def write_gltf(path_stem, node_name, parts):
    """parts: list of (Mesh, material description)."""
    path_stem = Path(path_stem)
    path_stem.parent.mkdir(parents=True, exist_ok=True)
    blob = bytearray()
    views, accessors = [], []
    samplers, images, textures, materials, prims = [], [], [], [], []

    def push(arr, target, ctype, atype, minmax=False, normalized=False):
        while len(blob) % 4:
            blob.append(0)
        data = arr.tobytes()
        views.append(dict(buffer=0, byteOffset=len(blob), byteLength=len(data), target=target))
        blob.extend(data)
        acc = dict(bufferView=len(views) - 1, componentType=ctype, count=len(arr), type=atype)
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"] = [float(x) for x in arr.min(axis=0)]
            acc["max"] = [float(x) for x in arr.max(axis=0)]
        accessors.append(acc)
        return len(accessors) - 1

    def tex(uri, sampler):
        if sampler not in samplers:
            samplers.append(sampler)
        images.append(dict(uri=uri))
        textures.append(dict(sampler=samplers.index(sampler), source=len(images) - 1))
        return dict(index=len(textures) - 1)

    for m, md in parts:
        pbr = dict(baseColorTexture=tex(md["base"], md["sampler"]), metallicFactor=0.0, **md["pbr"])
        mat = dict(name=md["name"], pbrMetallicRoughness=pbr, **md["extra"])
        if md["normal"]:
            mat["normalTexture"] = tex(md["normal"], md["sampler"])
        if md["orm"]:
            orm = tex(md["orm"], md["sampler"])
            pbr["metallicRoughnessTexture"] = orm
            mat["occlusionTexture"] = orm
        materials.append(mat)
        attrs = dict(
            POSITION=push(np.asarray(m.p, np.float32), 34962, 5126, "VEC3", minmax=True),
            NORMAL=push(np.asarray(m.n, np.float32), 34962, 5126, "VEC3"),
            TEXCOORD_0=push(np.asarray(m.uv, np.float32), 34962, 5126, "VEC2"),
            TEXCOORD_1=push(np.asarray(m.uv1, np.float32), 34962, 5126, "VEC2"),
        )
        if m.color:
            c = np.clip(np.asarray(m.c), 0, 1)
            rgba = np.concatenate([c, np.ones((len(c), 1))], axis=1)
            attrs["COLOR_0"] = push((rgba * 255 + 0.5).astype(np.uint8), 34962, 5121, "VEC4",
                                    normalized=True)
        big = len(m.p) >= 65536
        idx = push(np.asarray(m.idx, np.uint32 if big else np.uint16), 34963,
                   5125 if big else 5123, "SCALAR")
        prims.append(dict(attributes=attrs, indices=idx, material=len(materials) - 1, mode=4))

    gltf = dict(
        asset=dict(version="2.0", generator="tools/build_fir.py"),
        scene=0,
        scenes=[dict(nodes=[0])],
        nodes=[dict(name=node_name, mesh=0)],
        meshes=[dict(name=node_name, primitives=prims)],
        materials=materials, textures=textures, samplers=samplers, images=images,
        buffers=[dict(uri=path_stem.name + ".bin", byteLength=len(blob))],
        bufferViews=views,
        accessors=accessors,
    )
    path_stem.with_suffix(".bin").write_bytes(bytes(blob))
    path_stem.with_suffix(".gltf").write_text(json.dumps(gltf, indent=1))


def main():
    out_dir = Path(sys.argv[1])
    manifest = []
    for tree in TREES:
        configure(tree)
        limbs = describe_tree()
        entry = dict(name=tree["name"], height=tree["H"], lods=[])
        for lod in LODS:
            bark, leaf = build(limbs, lod)
            stem = f'{tree["name"]}_{lod["name"]}'
            write_gltf(out_dir / tree["name"] / stem, stem.replace("_lod", "_LOD"),
                       [(bark, material_bark()), (leaf, material_foliage())])
            p = np.asarray(bark.p + leaf.p)
            if lod["name"] == "lod0":
                entry["radius"] = float(np.abs(p[:, [0, 2]]).max())
                entry["top"] = float(p[:, 1].max())
            entry["lods"].append(dict(file=f'{tree["name"]}/{stem}.gltf',
                                      triangles=bark.tris + leaf.tris, vertices=len(p)))
        print(f'{tree["name"]:14s} {tree["H"]:4.0f} m  {len(limbs):3d} limbs  tris ' +
              " / ".join(str(l["triangles"]) for l in entry["lods"]))
        manifest.append(entry)
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=1))


if __name__ == "__main__":
    main()
