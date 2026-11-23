#!/usr/bin/env python3
"""Remake the berry bush's leafy cards as domes.

    python3 tools/build_berry_bush_domes.py assets/berry_bush/viburnum_bush.glb

The bush as it came is flat cards: eight tall ones crossing through its middle
(the twigs) and seventy-odd round its outside, each a picture of a leafy spray,
each doubled back to back. Flat cards crossing each other take a light from one
side very badly: each is lit as one flat thing, edge-on ones go dark, and where
two cross the join is plain. A torch shone at the bush shows every card.

Each leafy card becomes four small domes instead (many small mounds read as
foliage; a few big ones read as balls): the same picture over the same place,
each quarter of it bulged outward from the bush and set a little in or out of
line with the next, with normals that turn across it the way a
mound of leaves does and lean toward the bush's own roundness. One layer, not
two back to back (the bush's shader draws both sides). The twig cards through
the middle are left as they are.

The file is rewritten in place (its pictures are carried over untouched); run
it on the bush as it came, not on its own output.
"""
import json
import struct
import sys

import numpy as np

SPLIT = 2                # each card is cut into this many domes each way: many small mounds, not a few big ones
GRID = 3                 # squares across a dome
BULGE = 0.34             # how far its middle stands out, as a share of its own width
LAP = 0.07               # how far each dome runs on into its neighbours' share of the card
SHUFFLE = 0.05           # metres each dome is set in or out of line, so they do not read as a quilt
ROUND = 0.4              # how much of each normal is the bush's roundness, not the dome's own
LEAF_CELLS = {(0, 0), (1, 0), (2, 0), (3, 0), (0, 1)}       # of the 4 x 2 sheet: the sprays (the rest are twigs)


def main(path):
    with open(path, "rb") as f:
        f.read(12)
        n, _ = struct.unpack("<II", f.read(8)); gltf = json.loads(f.read(n))
        m, _ = struct.unpack("<II", f.read(8)); blob = bytearray(f.read(m))

    def arr(i, dt, w):
        a = gltf["accessors"][i]; v = gltf["bufferViews"][a["bufferView"]]
        o = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        count = a["count"] * (1 if a["type"] == "SCALAR" else w)
        return np.frombuffer(bytes(blob[o:o + count * np.dtype(dt).itemsize]), dt).reshape(-1, w).copy()

    prim = gltf["meshes"][0]["primitives"][0]
    P = arr(prim["attributes"]["POSITION"], "<f4", 3)
    N = arr(prim["attributes"]["NORMAL"], "<f4", 3)
    T = arr(prim["attributes"]["TANGENT"], "<f4", 4)
    UV = arr(prim["attributes"]["TEXCOORD_0"], "<f4", 2)
    I = arr(prim["indices"], {5123: "<u2", 5125: "<u4"}[gltf["accessors"][prim["indices"]]["componentType"]], 3)
    if len(I) > 400:
        raise SystemExit("this bush has already been remade (or is not the bush as it came)")
    heart = np.array([0.0, (P[:, 1].min() + P[:, 1].max()) * 0.5, 0.0])

    # The cards: triangles that share corners.
    owner = list(range(len(P)))
    def find(x):
        while owner[x] != x:
            owner[x] = owner[owner[x]]; x = owner[x]
        return x
    for t in I:
        a, b, c = (find(int(v)) for v in t)
        owner[b] = a; owner[c] = a
    cards = {}
    for k, t in enumerate(I):
        cards.setdefault(find(int(t[0])), []).append(k)

    out_p, out_n, out_t, out_uv, out_i = [], [], [], [], []
    def keep(tris):
        verts = np.unique(I[tris]); at = {int(v): len(out_p) + j for j, v in enumerate(verts)}
        for v in verts:
            out_p.append(P[v]); out_n.append(N[v]); out_t.append(T[v]); out_uv.append(UV[v])
        for t in I[tris]:
            out_i.append([at[int(t[0])], at[int(t[1])], at[int(t[2])]])

    seen, domes = set(), 0
    for tris in cards.values():
        verts = np.unique(I[tris])
        mid = UV[verts].mean(axis=0)
        cell = (int(mid[0] * 4), int(mid[1] * 2))
        if cell not in LEAF_CELLS or len(verts) != 4:
            keep(tris)
            continue
        centre = P[verts].mean(axis=0)
        key = tuple(np.round(centre, 2)) + cell
        if key in seen:
            continue                                   # its twin, back to back with one already made
        seen.add(key)
        # The card's four corners by where they are in the picture.
        u, v = UV[verts][:, 0], UV[verts][:, 1]
        lo_u, lo_v = u < u.mean(), v < v.mean()
        corner = lambda a, b: verts[np.where((lo_u == a) & (lo_v == b))[0][0]]
        c00, c10, c01, c11 = corner(True, True), corner(False, True), corner(True, False), corner(False, False)
        du = (P[c10] - P[c00] + P[c11] - P[c01]) * 0.5
        dv = (P[c01] - P[c00] + P[c11] - P[c10]) * 0.5
        normal = np.cross(du, dv); normal /= np.linalg.norm(normal)
        if np.dot(normal, centre - heart) < 0:
            normal = -normal
        width = (np.linalg.norm(du) + np.linalg.norm(dv)) * 0.5
        rng = np.random.default_rng(abs(hash(key)) % (2 ** 32))
        for part_j in range(SPLIT):
            for part_i in range(SPLIT):
                s0, s1 = max(part_i / SPLIT - LAP, 0.0), min((part_i + 1) / SPLIT + LAP, 1.0)
                t0, t1 = max(part_j / SPLIT - LAP, 0.0), min((part_j + 1) / SPLIT + LAP, 1.0)
                own_width = width / SPLIT
                shift = normal * rng.uniform(-SHUFFLE, SHUFFLE)
                base = len(out_p)
                grid = np.zeros((GRID + 1, GRID + 1, 3))
                where = np.zeros((GRID + 1, GRID + 1, 2))
                for j in range(GRID + 1):
                    for i in range(GRID + 1):
                        a_, b_ = i / GRID, j / GRID
                        s_, t_ = s0 + (s1 - s0) * a_, t0 + (t1 - t0) * b_
                        flat = (P[c00] * (1 - s_) * (1 - t_) + P[c10] * s_ * (1 - t_) + P[c01] * (1 - s_) * t_ + P[c11] * s_ * t_)
                        r2 = ((2 * a_ - 1) ** 2 + (2 * b_ - 1) ** 2) * 0.5
                        # Out in the middle, back at the corners: the dome sits astride where the card was.
                        grid[j, i] = flat + shift + normal * own_width * BULGE * (0.5 - r2) * 2.0
                        where[j, i] = (s_, t_)
                for j in range(GRID + 1):
                    for i in range(GRID + 1):
                        s_, t_ = where[j, i]
                        ds = grid[j, min(i + 1, GRID)] - grid[j, max(i - 1, 0)]
                        dt_ = grid[min(j + 1, GRID), i] - grid[max(j - 1, 0), i]
                        own = np.cross(ds, dt_); own /= np.linalg.norm(own)
                        if np.dot(own, normal) < 0:
                            own = -own
                        outward = grid[j, i] - heart; outward /= np.linalg.norm(outward)
                        nrm = own * (1 - ROUND) + outward * ROUND; nrm /= np.linalg.norm(nrm)
                        tan = ds - nrm * np.dot(ds, nrm); tan /= np.linalg.norm(tan)
                        hand = 1.0 if np.dot(np.cross(nrm, tan), -dt_) >= 0 else -1.0
                        uv = (UV[c00] * (1 - s_) * (1 - t_) + UV[c10] * s_ * (1 - t_) + UV[c01] * (1 - s_) * t_ + UV[c11] * s_ * t_)
                        out_p.append(grid[j, i]); out_n.append(nrm); out_t.append([*tan, hand]); out_uv.append(uv)
                facing = np.dot(np.cross(grid[0, 1] - grid[0, 0], grid[1, 0] - grid[0, 0]), normal) > 0
                for j in range(GRID):
                    for i in range(GRID):
                        a = base + j * (GRID + 1) + i; b = a + 1; c = a + GRID + 1; d = c + 1
                        out_i += [[a, b, d], [a, d, c]] if facing else [[a, d, b], [a, c, d]]
                domes += 1

    def push(data, target, ctype, atype, minmax=False):
        while len(blob) % 4:
            blob.append(0)
        gltf["bufferViews"].append(dict(buffer=0, byteOffset=len(blob), byteLength=data.nbytes, target=target))
        blob.extend(data.tobytes())
        acc = dict(bufferView=len(gltf["bufferViews"]) - 1, componentType=ctype, count=len(data) if data.ndim > 1 else data.size, type=atype)
        if minmax:
            acc["min"], acc["max"] = data.min(axis=0).tolist(), data.max(axis=0).tolist()
        gltf["accessors"].append(acc)
        return len(gltf["accessors"]) - 1

    prim["attributes"] = dict(POSITION=push(np.asarray(out_p, np.float32), 34962, 5126, "VEC3", True),
                              NORMAL=push(np.asarray(out_n, np.float32), 34962, 5126, "VEC3"),
                              TANGENT=push(np.asarray(out_t, np.float32), 34962, 5126, "VEC4"),
                              TEXCOORD_0=push(np.asarray(out_uv, np.float32), 34962, 5126, "VEC2"))
    wide = len(out_p) > 65535
    prim["indices"] = push(np.asarray(out_i, np.uint32 if wide else np.uint16).reshape(-1), 34963, 5125 if wide else 5123, "SCALAR")
    while len(blob) % 4:
        blob.append(0)
    gltf["buffers"][0]["byteLength"] = len(blob)
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<I4s", len(js), b"JSON")); f.write(js)
        f.write(struct.pack("<I4s", len(blob), b"BIN\x00")); f.write(bytes(blob))
    print("%s: %d domes, %d triangles in all (%d vertices)" % (path, domes, len(out_i), len(out_p)))


if __name__ == "__main__":
    main(sys.argv[1])
