#!/usr/bin/env python3
"""A kit of rough-hewn planks and beams cut from generated sheets, and wall
panels put together out of it.

    python3 tools/build_plank_kit.py assets/build/plank_kit

Reads the sheets in <out>/source (pieces on magenta, none touching) and writes:

    plank_kit_basecolor.png   every piece chosen, packed into one atlas, its wood bled
                              out under the background so no magenta is ever sampled
    plank_kit_normal.png      a normal map worked out from the picture (see `relief`)
    plank_kit.json            what is where: each piece's name, kind, place in the
                              atlas, size in metres and outline
    pieces/<name>.glb         each piece on its own, a slab cut to its outline
    wall_*, roof_*, floor_*, gable_left_*, gable_right_*  (each _lod0, _lod1, _lod2)
                              panels assembled from the pieces: see THE SET in main()

WHICH PIECES. Sheet 2 is a photograph's worth of wood, flat lit, and is the kit:
all eight planks and all three beams. Sheet 1's planks are added as extras with
their drawn black outlines cut away and their colour brought to sheet 2's, since
under the outline the wood is of the same kind; its beams are left out (they are
drawn in perspective, with an end face showing). Sheet 3 is painted, with
highlights brushed along every edge, and would never sit beside the others: none
of it is used.
"""
import json
import math
import random
import struct
import sys
from pathlib import Path

import cv2
import numpy as np
from scipy import ndimage as ndi

PX_PER_M = 585.0        # the sheets' scale: a plank 1170 px tall is 2 m
PLANK_T = 0.045         # how thick a plank is, metres
RAIL_T = 0.05           # and a rail, which stands in front of the planks
RAIL_SCALE = 0.68       # the beams are drawn heavier than a rail wants to be
PAD = 10                # clear pixels round every piece in the atlas
ATLAS = (4096, 2048)


# ------------------------------------------------------------------ cutting the sheets

def wood_mask(rgb, trim):
    """What is wood, drawn in by `trim` pixels (past a fringe, or a drawn outline)."""
    r, g, b = [rgb[..., i].astype(np.float32) for i in range(3)]
    mask = (np.minimum(r, b) - g) < 40.0
    mask = ndi.binary_opening(mask, iterations=2)
    return ndi.binary_erosion(mask, iterations=trim) if trim else mask


def cut(path, trim, prefix):
    """Each piece of a sheet: its picture, its mask, and whether it stands or lies."""
    rgb = cv2.cvtColor(cv2.imread(str(path)), cv2.COLOR_BGR2RGB)
    mask = wood_mask(rgb, trim)
    lab, n = ndi.label(mask)
    pieces = []
    for i, sl in enumerate(ndi.find_objects(lab)):
        m = lab[sl] == i + 1
        if m.sum() < 30000:
            continue
        h, w = m.shape
        kind = "plank" if h > w else "beam"
        pieces.append(dict(kind=kind, rgb=rgb[sl].copy(), mask=m, at=(sl[1].start, sl[0].start)))
    planks = sorted([p for p in pieces if p["kind"] == "plank"], key=lambda p: p["at"][0])
    beams = sorted([p for p in pieces if p["kind"] == "beam"], key=lambda p: p["at"][1])
    for i, p in enumerate(planks):
        p["name"] = f"{prefix}_plank_{chr(97 + i)}"
    for i, p in enumerate(beams):
        p["name"] = f"{prefix}_beam_{chr(97 + i)}"
    return planks, beams


def match_colour(pieces, like):
    """Bring one sheet's wood to another's: the same mean and spread, channel by channel."""
    def stats(ps):
        px = np.concatenate([p["rgb"][p["mask"]].astype(np.float32) for p in ps])
        return px.mean(axis=0), px.std(axis=0)
    m0, s0 = stats(pieces)
    m1, s1 = stats(like)
    for p in pieces:
        p["rgb"] = np.clip((p["rgb"].astype(np.float32) - m0) / s0 * s1 + m1, 0, 255).astype(np.uint8)


def pack(pieces):
    """Shelves: planks stood in rows along the top, beams laid under them."""
    x = y = PAD
    shelf = 0
    for p in sorted(pieces, key=lambda p: (p["kind"] != "plank", -p["mask"].shape[0])):
        h, w = p["mask"].shape
        if x + w + PAD > ATLAS[0]:
            x, y, shelf = PAD, y + shelf + PAD, 0
        p["rect"] = (x, y, w, h)
        x += w + PAD
        shelf = max(shelf, h)
    assert y + shelf + PAD <= ATLAS[1], "the pieces do not fit the atlas"


def relief(rgb, mask):
    """A NORMAL MAP FROM THE PICTURE ALONE. A photograph of wood is not a height map,
    but in flat light it is close to one: what is dark is mostly what is deep (a
    crack, the bottom of the grain) and what is pale is what stands proud. So the
    height is the picture's brightness with its slow changes taken out (a knot's
    stain is not a hill), in two sizes of detail, cracks deepened, and every piece
    rounded off toward its own edge. The normals are that height's slope, kept
    gentle: the picture already carries most of what the eye needs."""
    lum = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
    lum = np.where(mask, lum, lum[mask].mean())
    fine = lum - ndi.gaussian_filter(lum, 2.5)
    broad = ndi.gaussian_filter(lum, 2.5) - ndi.gaussian_filter(lum, 12.0)
    height = np.where(fine < 0.0, fine * 1.7, fine) + broad * 0.6
    height = ndi.gaussian_filter(height, 0.8)
    # The hewn edge: each piece falls away over its last centimetre and a half.
    inward = ndi.distance_transform_edt(mask)
    height += (1.0 - np.exp(-inward / 9.0)) * 0.035
    gy, gx = np.gradient(height)
    strength = 9.0
    nx, ny = -gx * strength, gy * strength            # (green is up: OpenGL's convention)
    nz = np.ones_like(nx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.dstack([nx / length, ny / length, nz / length])
    n[~ndi.binary_dilation(mask, iterations=3)] = (0.0, 0.0, 1.0)
    return ((n * 0.5 + 0.5) * 255.0 + 0.5).astype(np.uint8)


def outline(mask, eps):
    """A piece's outline in its own pixels."""
    contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    biggest = max(contours, key=cv2.contourArea)
    return cv2.approxPolyDP(biggest, eps, True).reshape(-1, 2).astype(float)


# ------------------------------------------------------------------ the mesh

def ear_clip(poly):
    """Triangles (index triples, counter-clockwise) of a simple polygon."""
    n = len(poly)
    area = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n))
    idx = list(range(n)) if area > 0 else list(range(n - 1, -1, -1))
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    tris = []
    guard = 0
    while len(idx) > 3 and guard < 20000:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if cross(a, b, c) <= 1e-12:
                continue
            if any(cross(a, b, poly[j]) > 0 and cross(b, c, poly[j]) > 0 and cross(c, a, poly[j]) > 0
                   for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            break
        else:
            idx.pop(0)
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


class Mesh:
    def __init__(self):
        self.p, self.n, self.t, self.uv, self.idx = [], [], [], [], []

    def vert(self, p, n, t, uv):
        self.p.append(tuple(map(float, p))); self.n.append(tuple(map(float, n)))
        self.t.append(tuple(map(float, t))); self.uv.append(tuple(map(float, uv)))
        return len(self.p) - 1

    def tri(self, a, b, c):
        self.idx += [a, b, c]

    @property
    def tris(self):
        return len(self.idx) // 3


def slab(mesh, pts, uvs, inner_uvs, z_back, z_front, u_dir, v_dir, back=True):
    """A piece as a slab. `pts` are its outline in the panel's plane (metres, y up),
    `uvs` where each point is in the atlas, `inner_uvs` a little inside the outline
    from each (what the slab's edge is coloured from); `u_dir` and `v_dir` are the
    ways the picture's u and v run in the panel's plane."""
    pts = [tuple(p) for p in pts]
    tris = ear_clip(pts)
    t3 = (u_dir[0], u_dir[1], 0.0)
    up = (-v_dir[0], -v_dir[1], 0.0)                    # green in the normal map is this way
    def handed(normal):
        c = np.cross(normal, t3)
        return 1.0 if np.dot(c, up) >= 0 else -1.0
    wf = handed((0, 0, 1))
    f = [mesh.vert((p[0], p[1], z_front), (0, 0, 1), (*t3, wf), uv) for p, uv in zip(pts, uvs)]
    for a, b, c in tris:
        mesh.tri(f[a], f[b], f[c])
    if back:
        wb = handed((0, 0, -1))
        bk = [mesh.vert((p[0], p[1], z_back), (0, 0, -1), (*t3, wb), uv) for p, uv in zip(pts, uvs)]
        for a, b, c in tris:
            mesh.tri(bk[a], bk[c], bk[b])
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    turn = 1.0 if area > 0 else -1.0
    for i in range(n):
        j = (i + 1) % n
        d = np.subtract(pts[j], pts[i])
        length = float(np.hypot(*d))
        if length < 1e-7:
            continue
        out = np.array([d[1], -d[0]]) / length * turn
        normal = (out[0], out[1], 0.0)
        along = (d[0] / length, d[1] / length, 0.0, 1.0)
        v0 = mesh.vert((*pts[i], z_front), normal, along, uvs[i])
        v1 = mesh.vert((*pts[j], z_front), normal, along, uvs[j])
        v2 = mesh.vert((*pts[j], z_back), normal, along, inner_uvs[j])
        v3 = mesh.vert((*pts[i], z_back), normal, along, inner_uvs[i])
        if turn > 0:
            mesh.tri(v0, v2, v1); mesh.tri(v0, v3, v2)
        else:
            mesh.tri(v0, v1, v2); mesh.tri(v0, v2, v3)


def clip(poly, keep):
    """A polygon of points (each a tuple of numbers, the first two its place) cut to
    the side of a line where keep(point) >= 0; every number is carried across the cut."""
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        da, db = keep(a), keep(b)
        if da >= 0:
            out.append(a)
        if (da >= 0) != (db >= 0):
            t = da / (da - db)
            out.append(tuple(x + (y - x) * t for x, y in zip(a, b)))
    return out


def place(mesh, piece, eps, centre, angle, flip_x, flip_y, z_back, z_front, back=True, cuts=(), crop=None, scale=1.0):
    """One piece of the kit put into a panel: turned, mirrored, moved, and cut."""
    x0, y0, w, h = piece["rect"]
    poly = outline(piece["mask"], eps)
    if crop is not None:                                # a stretch of a beam's length, in its own pixels
        m = piece["mask"].copy()
        m[:, :int(crop[0])] = False
        m[:, int(crop[1]):] = False
        poly = outline(m, eps)
        mid_px = ((crop[0] + crop[1]) / 2, h / 2)
    else:
        mid_px = (w / 2, h / 2)
    middle = poly.mean(axis=0)
    ca, sa = math.cos(angle), math.sin(angle)
    sx, sy = (-1.0 if flip_x else 1.0), (-1.0 if flip_y else 1.0)
    def to_panel(q):
        lx = (q[0] - mid_px[0]) / PX_PER_M * sx * scale
        ly = -(q[1] - mid_px[1]) / PX_PER_M * sy * scale
        return (centre[0] + lx * ca - ly * sa, centre[1] + lx * sa + ly * ca)
    atlas_uv = lambda q: ((x0 + q[0]) / ATLAS[0], (y0 + q[1]) / ATLAS[1])
    # Where the slab's edge takes its colour from: straight in from the outline at
    # each point (square to it, not toward the middle: a long beam's middle is a
    # long way along it), far enough to be clear of the cut.
    verts = []
    n = len(poly)
    turn = 1.0 if sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n)) > 0 else -1.0
    for i, q in enumerate(poly):
        # (The way in is taken over a few points either side: point to point it
        # swings about, and the edge's picture came out in zigzags.)
        along = poly[(i + 3) % n] - poly[i - 3] if n > 8 else poly[(i + 1) % n] - poly[i - 1]
        along = along / max(np.hypot(*along), 1e-6)
        inward = np.array([-along[1], along[0]]) * turn
        if not piece["mask"][int(np.clip(q[1] + inward[1] * 8, 0, h - 1)), int(np.clip(q[0] + inward[0] * 8, 0, w - 1))]:
            inward = -inward
        verts.append((*to_panel(q), *atlas_uv(q + inward * 4.0), *atlas_uv(q + inward * 9.0)))
    for keep in cuts:
        verts = clip(verts, keep)
    if len(verts) < 3:
        return
    u_dir = np.subtract(to_panel((1, 0)), to_panel((0, 0))); u_dir = u_dir / np.hypot(*u_dir)
    v_dir = np.subtract(to_panel((0, 1)), to_panel((0, 0))); v_dir = v_dir / np.hypot(*v_dir)
    slab(mesh, [v[:2] for v in verts], [v[2:4] for v in verts], [v[4:6] for v in verts], z_back, z_front, u_dir, v_dir, back)


def write_glb(path, mesh, name, textures):
    """The mesh, pointing at the kit's two textures beside it (not carrying its own copy)."""
    P = np.asarray(mesh.p, np.float32); N = np.asarray(mesh.n, np.float32)
    T = np.asarray(mesh.t, np.float32); UV = np.asarray(mesh.uv, np.float32)
    I = np.asarray(mesh.idx, np.uint32 if len(mesh.p) > 65535 else np.uint16)
    blob = bytearray(); views = []; accessors = []
    def push(arr, target, ctype, atype, minmax=False):
        while len(blob) % 4:
            blob.append(0)
        views.append(dict(buffer=0, byteOffset=len(blob), byteLength=arr.nbytes, target=target))
        blob.extend(arr.tobytes())
        acc = dict(bufferView=len(views) - 1, componentType=ctype, count=len(arr) if arr.ndim > 1 else arr.size, type=atype)
        if minmax:
            acc["min"], acc["max"] = arr.min(axis=0).tolist(), arr.max(axis=0).tolist()
        accessors.append(acc)
        return len(accessors) - 1
    attrs = dict(POSITION=push(P, 34962, 5126, "VEC3", True), NORMAL=push(N, 34962, 5126, "VEC3"),
                 TANGENT=push(T, 34962, 5126, "VEC4"), TEXCOORD_0=push(UV, 34962, 5126, "VEC2"))
    a_i = push(I, 34963, 5125 if I.dtype == np.uint32 else 5123, "SCALAR")
    gltf = dict(asset=dict(version="2.0", generator="tools/build_plank_kit.py"), scene=0, scenes=[dict(nodes=[0])],
                nodes=[dict(name=name, mesh=0)],
                meshes=[dict(name=name, primitives=[dict(attributes=attrs, indices=a_i, material=0)])],
                materials=[dict(name="plank_kit", pbrMetallicRoughness=dict(baseColorTexture=dict(index=0), metallicFactor=0.0,
                                roughnessFactor=0.88), normalTexture=dict(index=1, scale=1.0), doubleSided=False)],
                textures=[dict(source=0, sampler=0), dict(source=1, sampler=0)],
                samplers=[dict(magFilter=9729, minFilter=9987, wrapS=33071, wrapT=33071)],
                images=[dict(uri=textures[0]), dict(uri=textures[1])],
                accessors=accessors, bufferViews=views, buffers=[dict(byteLength=len(blob))])
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    while len(blob) % 4:
        blob.append(0)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<I4s", len(js), b"JSON")); f.write(js)
        f.write(struct.pack("<I4s", len(blob), b"BIN\x00")); f.write(bytes(blob))


# ------------------------------------------------------------------ a wall

PANEL_H = 2.0


def bounds(width, top=PANEL_H):
    """A PANEL KEEPS TO ITS OWN SQUARE. Planks and rails that ran past it lay in
    the same plane as the next panel's and the two flickered through each other."""
    return (lambda v: v[0] + width / 2, lambda v: width / 2 - v[0], lambda v: v[1], lambda v: top - v[1])


def wall(planks, beams, seed, eps, width=2.0):
    """A panel `width` metres wide: planks stood side by side until it is full, two
    rails across them, a brace from the foot of one side to the head of the other."""
    rng = random.Random(seed)
    mesh = Mesh()
    # Planks: drawn at random without a repeat, the last chosen to fit what is left.
    pool = planks[:]
    rng.shuffle(pool)
    chosen, used = [], 0.0
    gap = 0.008
    while pool:
        left = width - used
        fits = [p for p in pool if p["mask"].shape[1] / PX_PER_M <= left + 0.03]
        if not fits:
            break
        nxt = fits[0] if left > 0.75 else min(fits, key=lambda p: abs(left - p["mask"].shape[1] / PX_PER_M))
        pool = [q for q in pool if q is not nxt]
        chosen.append(nxt)
        used += nxt["mask"].shape[1] / PX_PER_M + gap
    # Whatever is left over is shared out between the planks as their gaps.
    total = sum(p["mask"].shape[1] / PX_PER_M for p in chosen)
    gap = max((width - total) / max(len(chosen) - 1, 1), 0.0)
    x = -width / 2
    for p in chosen:
        w_m = p["mask"].shape[1] / PX_PER_M
        h_m = p["mask"].shape[0] / PX_PER_M
        place(mesh, p, eps, (x + w_m / 2, h_m / 2 + rng.uniform(0.0, 0.03)), rng.uniform(-0.008, 0.008),
              rng.random() < 0.5, rng.random() < 0.35, 0.0, PLANK_T, cuts=bounds(width))
        x += w_m + gap
    # Rails: a stretch of a beam a little longer than the panel is wide.
    order = beams[:]
    rng.shuffle(order)
    rail_y = (0.34, 1.62)
    edges = []
    for k, y in enumerate(rail_y):
        b = order[k % len(order)]
        length_px = (width + 0.07) * PX_PER_M / RAIL_SCALE
        start = rng.uniform(0, max(b["mask"].shape[1] - length_px, 0))
        h_m = b["mask"].shape[0] / PX_PER_M * RAIL_SCALE
        place(mesh, b, eps, (0.0, y), rng.uniform(-0.006, 0.006), rng.random() < 0.5, rng.random() < 0.5,
              PLANK_T, PLANK_T + RAIL_T, back=False, crop=(start, start + length_px), scale=RAIL_SCALE, cuts=bounds(width))
        edges.append((y - h_m / 2, y + h_m / 2))
    # Between the rails: a brace from the foot of one side to the head of the other
    # (most walls), or a third rail across the middle (some).
    b = order[2 % len(order)]
    low, high = edges[0][1] - 0.01, edges[1][0] + 0.01
    if rng.random() < 0.72:
        run = width * rng.uniform(0.62, 0.8)
        angle = math.atan2(high - low, run) * (1 if rng.random() < 0.5 else -1)
        place(mesh, b, eps, (0.0, (low + high) / 2), angle, False, rng.random() < 0.5, PLANK_T, PLANK_T + RAIL_T * 0.68, back=False,
              cuts=(lambda v: v[1] - low, lambda v: high - v[1]) + bounds(width), scale=RAIL_SCALE)
    else:
        length_px = (width + 0.05) * PX_PER_M / RAIL_SCALE
        start = rng.uniform(0, max(b["mask"].shape[1] - length_px, 0))
        place(mesh, b, eps, (0.0, (low + high) / 2 + rng.uniform(-0.08, 0.08)), rng.uniform(-0.006, 0.006), rng.random() < 0.5,
              rng.random() < 0.5, PLANK_T, PLANK_T + RAIL_T, back=False, crop=(start, start + length_px), scale=RAIL_SCALE,
              cuts=bounds(width))
    return mesh, [p["name"] for p in chosen]


def deck(planks, beams, seed, eps, length, width=2.0, overhang=0.0):
    """BOARDS LAID ACROSS, for a roof or a floor: planks on their sides, each
    running the panel's whole `width`, one above the next for `length` metres (from
    y = -overhang), on two beams that run the length underneath. In the panel's own
    plane: x across, y along, the boards' face toward +z."""
    rng = random.Random(seed)
    mesh = Mesh()
    pool = planks[:]
    rng.shuffle(pool)
    y = -overhang
    used = []
    edge_cuts = (lambda v: v[0] + width / 2, lambda v: width / 2 - v[0],
                 lambda v: v[1] + overhang, lambda v: length - v[1])
    k = 0
    while y < length:
        p = pool[k % len(pool)]
        k += 1
        across = p["mask"].shape[1] / PX_PER_M               # a plank's width is what it covers of the length
        place(mesh, p, eps, (rng.uniform(-0.02, 0.02), y + across / 2), math.pi / 2 * (1 if rng.random() < 0.5 else -1),
              rng.random() < 0.5, False, 0.0, PLANK_T, cuts=edge_cuts)
        used.append(p["name"])
        y += across + rng.uniform(0.004, 0.012)
    # The beams under them: rafters under a roof, joists under a floor.
    order = beams[:]
    rng.shuffle(order)
    for i, x in enumerate((-width * 0.31, width * 0.31)):
        b = order[i % len(order)]
        length_px = min((length + overhang) * PX_PER_M / RAIL_SCALE, b["mask"].shape[1] - 4)
        start = rng.uniform(0, max(b["mask"].shape[1] - length_px, 0))
        place(mesh, b, eps, (x, (length - overhang) / 2), math.pi / 2, rng.random() < 0.5, rng.random() < 0.5,
              -RAIL_T * 1.6, 0.0, crop=(start, start + length_px), scale=RAIL_SCALE,
              cuts=(lambda v: v[1] + overhang, lambda v: length - v[1]))
    return mesh, used


def gable(planks, beams, seed, eps, rise_right, width=2.0):
    """THE TRIANGLE BETWEEN A SQUARE WALL AND A 45 DEGREE ROOF: a wall's planks,
    cut off along the slope, a rail along the foot and a rail up the rake. As tall
    at its high side as it is wide; `rise_right` says which side that is."""
    rng = random.Random(seed)
    mesh = Mesh()
    sign = 1.0 if rise_right else -1.0
    under = lambda v: (width / 2 + sign * v[0]) - v[1] - 0.008    # below the slope, and clear of the roof's underside
    pool = planks[:]
    rng.shuffle(pool)
    x = -width / 2
    used = []
    k = 0
    while x < width / 2 - 0.02:
        p = pool[k % len(pool)]
        k += 1
        w_m, h_m = p["mask"].shape[1] / PX_PER_M, p["mask"].shape[0] / PX_PER_M
        place(mesh, p, eps, (x + w_m / 2, h_m / 2 - 0.02), rng.uniform(-0.008, 0.008), rng.random() < 0.5, rng.random() < 0.35,
              0.0, PLANK_T, cuts=(under,) + bounds(width))
        used.append(p["name"])
        x += w_m + rng.uniform(0.006, 0.014)
    order = beams[:]
    rng.shuffle(order)
    rail_h = order[0]["mask"].shape[0] / PX_PER_M * RAIL_SCALE
    # The foot rail, and the rake rail lying just under the slope.
    length_px = min((width + 0.04) * PX_PER_M / RAIL_SCALE, order[0]["mask"].shape[1] - 4)
    start = rng.uniform(0, max(order[0]["mask"].shape[1] - length_px, 0))
    place(mesh, order[0], eps, (0.0, rail_h / 2 + 0.04), 0.0, rng.random() < 0.5, rng.random() < 0.5, PLANK_T, PLANK_T + RAIL_T,
          back=False, crop=(start, start + length_px), scale=RAIL_SCALE, cuts=(under,) + bounds(width))
    rake = order[1 % len(order)]
    inset = rail_h / 2 + 0.03                                       # square in from the slope
    centre = (0.0 + sign * inset * 0.7071, width / 2 - inset * 0.7071)
    place(mesh, rake, eps, centre, sign * math.pi / 4, rng.random() < 0.5, rng.random() < 0.5, PLANK_T, PLANK_T + RAIL_T * 0.68,
          back=False, scale=RAIL_SCALE,
          cuts=(under, lambda v: v[1] - (rail_h + 0.05), lambda v: v[0] + width / 2, lambda v: width / 2 - v[0]))
    return mesh, used


# A doorway's opening, metres: how wide, how tall, and the leaf that fills it.
DOOR_W = 1.1
DOOR_H = 1.95
LEAF_W = DOOR_W - 0.04
LEAF_H = DOOR_H - 0.05


def doorway(planks, beams, seed, eps, width=2.0):
    """A WALL WITH A DOORWAY IN IT: the wall's planks, but cut away where the door
    goes (those over the opening stop short above it), the rails stopping at
    either side of it, and a frame round it: two posts and a lintel."""
    rng = random.Random(seed)
    mesh = Mesh()
    half = DOOR_W / 2
    # The three parts of a wall that are not the opening.
    parts = ((lambda v: -half - v[0],), (lambda v: v[0] - half,),
             (lambda v: v[0] + half, lambda v: half - v[0], lambda v: v[1] - DOOR_H))
    pool = planks[:]
    rng.shuffle(pool)
    x = -width / 2
    k = 0
    while x < width / 2 - 0.05:
        p = pool[k % len(pool)]
        k += 1
        w_m, h_m = p["mask"].shape[1] / PX_PER_M, p["mask"].shape[0] / PX_PER_M
        lift, lean = rng.uniform(0.0, 0.03), rng.uniform(-0.008, 0.008)
        fx, fy = rng.random() < 0.5, rng.random() < 0.35
        for cuts in parts:
            place(mesh, p, eps, (x + w_m / 2, h_m / 2 + lift), lean, fx, fy, 0.0, PLANK_T,
                  cuts=cuts + bounds(width))
        x += w_m + rng.uniform(0.006, 0.014)
    order = beams[:]
    rng.shuffle(order)
    # The rails, each in two lengths either side of the opening.
    for k, y in enumerate((0.34, 1.62)):
        b = order[k % len(order)]
        length_px = (width + 0.07) * PX_PER_M / RAIL_SCALE
        start = rng.uniform(0, max(b["mask"].shape[1] - length_px, 0))
        fx, fy = rng.random() < 0.5, rng.random() < 0.5
        for cuts in parts[:2]:
            place(mesh, b, eps, (0.0, y), 0.0, fx, fy, PLANK_T, PLANK_T + RAIL_T, back=False,
                  crop=(start, start + length_px), scale=RAIL_SCALE, cuts=cuts + bounds(width))
    # The frame: a post up each side and a lintel across their heads, proud of everything.
    post = 0.6
    post_w = order[2 % len(order)]["mask"].shape[0] / PX_PER_M * post
    for side in (-1, 1):
        b = order[(2 + (side > 0)) % len(order)]
        length_px = min((DOOR_H + 0.02) * PX_PER_M / post, b["mask"].shape[1] - 4)
        start = rng.uniform(0, max(b["mask"].shape[1] - length_px, 0))
        place(mesh, b, eps, (side * (half + post_w / 2), (DOOR_H + 0.02) / 2), math.pi / 2, side > 0, rng.random() < 0.5,
              -0.02, PLANK_T + RAIL_T * 1.3, crop=(start, start + length_px), scale=post)
    b = order[0]
    length_px = (DOOR_W + post_w * 2 + 0.16) * PX_PER_M / post
    start = rng.uniform(0, max(b["mask"].shape[1] - length_px, 0))
    place(mesh, b, eps, (0.0, DOOR_H + post_w / 2), 0.0, rng.random() < 0.5, rng.random() < 0.5,
          -0.036, PLANK_T + RAIL_T * 1.62, crop=(start, start + length_px), scale=post, cuts=bounds(width))
    return mesh, []


def leaf(planks, beams, seed, eps):
    """THE DOOR ITSELF, ledged and braced: planks side by side, two ledges across
    them and a brace between, on the face. Its hinge edge is the y axis (x runs
    from 0 to the leaf's width), so turning it about y swings it."""
    rng = random.Random(seed)
    mesh = Mesh()
    inside = (lambda v: v[0], lambda v: LEAF_W - v[0], lambda v: v[1] - 0.0, lambda v: LEAF_H - v[1])
    pool = sorted(planks, key=lambda p: p["mask"].shape[1])[:9]          # the narrower ones: a door is not two boards
    rng.shuffle(pool)
    x = 0.0
    k = 0
    while x < LEAF_W - 0.01:
        p = pool[k % len(pool)]
        k += 1
        w_m, h_m = p["mask"].shape[1] / PX_PER_M, p["mask"].shape[0] / PX_PER_M
        place(mesh, p, eps, (x + w_m / 2, h_m / 2 - rng.uniform(0.02, 0.1)), 0.0, rng.random() < 0.5, rng.random() < 0.5,
              0.0, PLANK_T * 0.8, cuts=inside)
        x += w_m + 0.004
    order = beams[:]
    rng.shuffle(order)
    ledge = 0.5
    ledge_h = order[0]["mask"].shape[0] / PX_PER_M * ledge
    ys = (0.28, LEAF_H - 0.3)
    for k, y in enumerate(ys):
        b = order[k % len(order)]
        length_px = (LEAF_W - 0.06) * PX_PER_M / ledge
        start = rng.uniform(0, max(b["mask"].shape[1] - length_px, 0))
        place(mesh, b, eps, (LEAF_W / 2, y), 0.0, rng.random() < 0.5, rng.random() < 0.5, PLANK_T * 0.8, PLANK_T * 0.8 + RAIL_T * 0.7,
              back=False, crop=(start, start + length_px), scale=ledge)
    # The brace runs up from the hinge side, as it must to hold a door square.
    low, high = ys[0] + ledge_h / 2 - 0.01, ys[1] - ledge_h / 2 + 0.01
    b = order[2 % len(order)]
    place(mesh, b, eps, (LEAF_W / 2, (low + high) / 2), math.atan2(high - low, LEAF_W * 0.8), False, rng.random() < 0.5,
          PLANK_T * 0.8, PLANK_T * 0.8 + RAIL_T * 0.4, back=False, scale=ledge,
          cuts=(lambda v: v[1] - low, lambda v: high - v[1], lambda v: v[0] - 0.03, lambda v: LEAF_W - 0.03 - v[0]))
    return mesh, []


def tilted(mesh, pitch):
    """A panel built standing up, leaned back about its foot by `pitch` (radians): a
    quarter turn lays it flat, face up; an eighth makes a 45 degree roof. Its foot
    stays on the x axis; its length runs back (toward -z) and up."""
    c, s_ = math.cos(pitch), math.sin(pitch)
    turn = lambda v: (v[0], v[1] * c + v[2] * s_, -v[1] * s_ + v[2] * c)
    mesh.p = [turn(v) for v in mesh.p]
    mesh.n = [turn(v) for v in mesh.n]
    mesh.t = [(*turn(v[:3]), v[3]) for v in mesh.t]
    return mesh


def main(out_dir):
    out = Path(out_dir)
    src = out / "source"
    photo_planks, photo_beams = cut(src / "sheet_2_photo.jpg", 4, "photo")
    drawn_planks, _ = cut(src / "sheet_1_outlined.jpg", 9, "drawn")
    match_colour(drawn_planks, photo_planks)
    pieces = photo_planks + drawn_planks + photo_beams
    pack(pieces)
    base = np.zeros((ATLAS[1], ATLAS[0], 3), np.uint8)
    mask = np.zeros((ATLAS[1], ATLAS[0]), bool)
    for p in pieces:
        x, y, w, h = p["rect"]
        base[y:y + h, x:x + w][p["mask"]] = p["rgb"][p["mask"]]
        mask[y:y + h, x:x + w] |= p["mask"]
    idx = ndi.distance_transform_edt(~mask, return_distances=False, return_indices=True)
    bled = base[idx[0], idx[1]]
    cv2.imwrite(str(out / "plank_kit_basecolor.png"), cv2.cvtColor(bled, cv2.COLOR_RGB2BGR))
    normal = relief(bled, mask)
    cv2.imwrite(str(out / "plank_kit_normal.png"), cv2.cvtColor(normal, cv2.COLOR_RGB2BGR))
    textures = ("plank_kit_basecolor.png", "plank_kit_normal.png")
    # Each piece on its own, standing on the origin.
    (out / "pieces").mkdir(exist_ok=True)
    manifest = []
    for p in pieces:
        mesh = Mesh()
        w_m, h_m = p["mask"].shape[1] / PX_PER_M, p["mask"].shape[0] / PX_PER_M
        place(mesh, p, 2.0, (0.0, h_m / 2), 0.0, False, False, 0.0, PLANK_T if p["kind"] == "plank" else RAIL_T)
        write_glb(out / "pieces" / f'{p["name"]}.glb', mesh, p["name"], ["../" + t for t in textures])
        manifest.append(dict(name=p["name"], kind=p["kind"], rect=list(map(int, p["rect"])), width_m=round(w_m, 3),
                             height_m=round(h_m, 3), triangles=mesh.tris,
                             outline=[[round(float(a), 1), round(float(b), 1)] for a, b in outline(p["mask"], 2.0)]))
    (out / "plank_kit.json").write_text(json.dumps(dict(px_per_m=PX_PER_M, atlas=list(ATLAS), pieces=manifest), indent=1))
    print("kit: %d planks (%d photo, %d drawn), %d beams" % (len(photo_planks) + len(drawn_planks), len(photo_planks),
                                                              len(drawn_planks), len(photo_beams)))
    # THE SET. Every kind in several variants, each at three levels of detail.
    #   wall_*        2 m square, standing
    #   roof_*        2 m wide, pitched at 45 degrees: 2 m of run and 2 m of rise, so one
    #                 sits from the top of a wall to a ridge 2 m in and 2 m up
    #   floor_*       2 m square, lying flat, boards up: a platform
    #   gable_left_*, gable_right_*   the triangle under one roof panel's end, to stand
    #                 on a wall: high on the side it is named for
    #   doorway_*     a wall with a framed opening in the middle of it
    #   door_*        the leaf that hangs in it: its hinge edge on the y axis
    everything = photo_planks + drawn_planks
    builds = []
    for i, seed in enumerate((3, 11, 5, 23, 31, 47, 59, 71)):
        stock = photo_planks if i % 2 == 0 else everything
        builds.append((f"wall_{chr(97 + i)}", lambda eps, seed=seed, stock=stock: wall(stock, photo_beams, seed, eps)))
    for i, seed in enumerate((7, 19, 29, 43)):
        stock = photo_planks if i % 2 == 0 else everything
        builds.append((f"roof_{chr(97 + i)}", lambda eps, seed=seed, stock=stock:
                       (lambda m: (tilted(m[0], math.pi / 4), m[1]))(deck(stock, photo_beams, seed, eps, 2.0 * math.sqrt(2.0), overhang=0.12))))
    for i, seed in enumerate((13, 37, 53)):
        stock = photo_planks if i % 2 == 0 else everything
        builds.append((f"floor_{chr(97 + i)}", lambda eps, seed=seed, stock=stock:
                       (lambda m: (tilted(m[0], math.pi / 2), m[1]))(deck(stock, photo_beams, seed, eps, 2.0))))
    for side in ("left", "right"):
        for i, seed in enumerate((17, 41)):
            stock = photo_planks if i == 0 else everything
            builds.append((f"gable_{side}_{chr(97 + i)}", lambda eps, seed=seed, stock=stock, side=side:
                           gable(stock, photo_beams, seed, eps, side == "right")))
    for i, seed in enumerate((61, 67)):
        stock = photo_planks if i == 0 else everything
        builds.append((f"doorway_{chr(97 + i)}", lambda eps, seed=seed, stock=stock: doorway(stock, photo_beams, seed, eps)))
        builds.append((f"door_{chr(97 + i)}", lambda eps, seed=seed, stock=stock: leaf(stock, photo_beams, seed + 1, eps)))
    summary = {}
    for name, build in builds:
        counts = []
        for lod, eps in enumerate((2.0, 7.0, 22.0)):
            mesh, used = build(eps)
            write_glb(out / f"{name}_lod{lod}.glb", mesh, f"{name}_LOD{lod}", textures)
            counts.append(mesh.tris)
        summary.setdefault(name.rsplit("_", 1)[0], []).append(counts)
    for kind, rows in summary.items():
        print("%-12s %d variants; triangles lod0 %d-%d, lod1 %d-%d, lod2 %d-%d" % (
            kind, len(rows), min(r[0] for r in rows), max(r[0] for r in rows), min(r[1] for r in rows), max(r[1] for r in rows),
            min(r[2] for r in rows), max(r[2] for r in rows)))
    # The atlas with what was cut drawn on it, for checking.
    check = cv2.cvtColor(bled, cv2.COLOR_RGB2BGR)
    check[~mask] = (40, 40, 40)
    for p in pieces:
        x, y, w, h = p["rect"]
        cv2.polylines(check, [(outline(p["mask"], 2.0) + (x, y)).astype(np.int32)], True, (0, 255, 255), 2)
        cv2.putText(check, p["name"], (x + 6, y + h - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
    cv2.imwrite(str(out / "source" / "kit_traced.jpg"), cv2.resize(check, (2048, 1024)), [cv2.IMWRITE_JPEG_QUALITY, 88])


if __name__ == "__main__":
    main(sys.argv[1])
