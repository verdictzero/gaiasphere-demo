#!/usr/bin/env python3
"""THE CLIFF BLOCK, BAKED: the block out of the example .glb it was handed over in
(every block in it is the same mesh; the first is taken), with two things worked
out for every vertex and written into its vertex colour, for
SHADER_cliff_rock.gdshader to lay over the rock's texture:

    COLOR.r   1 - EDGE WEAR: how far the surface stands proud there (its convex
              edges and corners, where weather and knocks take the face off)
    COLOR.g   CREVICE LIGHT: how much of the sky a point sees (rays cast out over
              the hemisphere above it; 1 in the open, toward 0 deep in a crack)

White is "nothing to add", so a mesh with no baked colour (the shards, the old
kit) is drawn as before.

    python3 tools/bake_cliff_block.py /path/to/example.glb
    godot --headless --path . --import

Writes assets/cliff_block/cliff_block.glb (position, normal, colour, index).
"""
import json
import struct
import sys
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "cliff_block" / "cliff_block.glb"
RAYS = 48           # to a vertex
REACH = 1.6         # metres a ray looks for something in its way
RNG = np.random.default_rng(11)


def read_first_mesh(path):
    data = open(path, "rb").read()
    n = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + n])
    blob = data[20 + n + 8:]

    def acc(i):
        a = doc["accessors"][i]
        v = doc["bufferViews"][a["bufferView"]]
        comps = {"VEC3": 3, "VEC2": 2, "SCALAR": 1}[a["type"]]
        dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[a["componentType"]]
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        x = np.frombuffer(blob, dt, a["count"] * comps, off)
        return x.reshape(-1, comps) if comps > 1 else x

    for mesh in doc["meshes"]:
        if mesh.get("name", "").lower().startswith("plane"):
            continue
        p = mesh["primitives"][0]
        return (acc(p["attributes"]["POSITION"]).astype(np.float64),
                acc(p["attributes"]["NORMAL"]).astype(np.float64),
                acc(p["indices"]).astype(np.int64).reshape(-1, 3))
    raise SystemExit("no mesh")


def weld(pos):
    """Vertices at one place are one point: (index of each vertex's point, the points)."""
    keys = np.round(pos / 0.0005).astype(np.int64)
    _, first, to = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    return to.reshape(-1), pos[first]


def convexity(points, normals, tris):
    """How far each point stands proud of its neighbours, per metre: + on an edge or
    a corner, - in a hollow. Averaged over a few rings so it reads as a worn edge
    a hand wide, not as the mesh's own facets."""
    edges = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
    edges = np.unique(np.sort(edges, axis=1), axis=0)
    a, b = edges[:, 0], edges[:, 1]
    d = points[b] - points[a]
    length = np.linalg.norm(d, axis=1) + 1e-9
    # (a stands above b by -n_a.d ; b above a by n_b.d)
    ca = -(normals[a] * d).sum(1) / length
    cb = (normals[b] * d).sum(1) / length
    total = np.zeros(len(points))
    count = np.zeros(len(points))
    np.add.at(total, a, ca)
    np.add.at(total, b, cb)
    np.add.at(count, a, 1)
    np.add.at(count, b, 1)
    c = total / np.maximum(count, 1)
    for _ in range(3):          # a little spread
        s = np.zeros(len(points))
        np.add.at(s, a, c[b])
        np.add.at(s, b, c[a])
        c = 0.5 * c + 0.5 * s / np.maximum(count, 1)
    return c


def sky(points, normals, tris_pos):
    """The share of rays cast over each point's hemisphere that get away."""
    v0 = tris_pos[:, 0].astype(np.float32)
    e1 = (tris_pos[:, 1] - tris_pos[:, 0]).astype(np.float32)
    e2 = (tris_pos[:, 2] - tris_pos[:, 0]).astype(np.float32)
    open_share = np.zeros(len(points))
    for i in range(len(points)):
        n = normals[i]
        # Cosine-weighted directions about the normal.
        u = RNG.random(RAYS)
        w = RNG.random(RAYS) * 2.0 * np.pi
        r = np.sqrt(u)
        t = np.cross(n, [0.0, 1.0, 0.0] if abs(n[1]) < 0.9 else [1.0, 0.0, 0.0])
        t /= np.linalg.norm(t)
        bt = np.cross(n, t)
        dirs = (np.outer(r * np.cos(w), t) + np.outer(r * np.sin(w), bt) + np.outer(np.sqrt(1.0 - u), n)).astype(np.float32)
        origin = (points[i] + n * 0.02).astype(np.float32)
        # Moeller-Trumbore, every ray against every triangle.
        pvec = np.cross(dirs[:, None, :], e2[None, :, :])
        det = (e1[None, :, :] * pvec).sum(2)
        ok = np.abs(det) > 1e-9
        inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        tvec = origin[None, :] - v0
        uu = (tvec[None, :, :] * pvec).sum(2) * inv
        qvec = np.cross(tvec, e1)
        vv = (dirs[:, None, :] * qvec[None, :, :]).sum(2) * inv
        tt = (e2 * qvec).sum(1)[None, :] * inv
        hit = ok & (uu >= 0) & (vv >= 0) & (uu + vv <= 1) & (tt > 1e-4) & (tt < REACH)
        # Nearer things shut out more than far ones.
        near = np.where(hit, tt, REACH).min(1)
        open_share[i] = (near / REACH).mean()
        if i % 500 == 0:
            print("  sky %d / %d" % (i, len(points)), flush=True)
    return open_share


def main(src):
    pos, nrm, tris = read_first_mesh(src)
    to, points = weld(pos)
    wn = np.zeros_like(points)
    np.add.at(wn, to, nrm)
    wn /= np.linalg.norm(wn, axis=1, keepdims=True) + 1e-9
    wt = to[tris]
    wt = wt[(wt[:, 0] != wt[:, 1]) & (wt[:, 1] != wt[:, 2]) & (wt[:, 0] != wt[:, 2])]
    print("block: %d vertices (%d places), %d triangles" % (len(pos), len(points), len(tris)))
    c = convexity(points, wn, wt)
    # Wear from where it begins to stand proud to a sharp edge (by this mesh's own spread).
    lo, hi = np.percentile(c, 60), np.percentile(c, 97)
    wear = np.clip((c - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
    light = sky(points, wn, points[wt])
    # Stretched over what this block actually has, and hollows a little darker still.
    lo, hi = np.percentile(light, 3), np.percentile(light, 85)
    light = np.clip((light - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
    light *= 1.0 - 0.3 * np.clip(-c / max(-np.percentile(c, 3), 1e-6), 0.0, 1.0)
    print("wear: mean %.2f; crevice light: mean %.2f" % (wear.mean(), light.mean()))
    colour = np.ones((len(pos), 4), np.float32)
    colour[:, 0] = 1.0 - wear[to]
    colour[:, 1] = light[to]
    col8 = np.clip(colour * 255.0 + 0.5, 0, 255).astype(np.uint8)

    chunks = [pos.astype(np.float32).tobytes(), nrm.astype(np.float32).tobytes(), col8.tobytes(),
              tris.astype(np.uint32).tobytes()]
    views, blob = [], bytearray()
    for ch in chunks:
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(ch)})
        blob += ch
    while len(blob) % 4:
        blob.append(0)
    doc = {
        "asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "cliff_block"}],
        "meshes": [{"name": "cliff_block", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3}]}],
        "buffers": [{"byteLength": len(blob)}], "bufferViews": views,
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3",
             "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(pos), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5121, "normalized": True, "count": len(pos), "type": "VEC4"},
            {"bufferView": 3, "componentType": 5125, "count": int(tris.size), "type": "SCALAR"},
        ],
    }
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942))
        f.write(blob)
    print("wrote %s (%d KB)" % (OUT, OUT.stat().st_size // 1024))


if __name__ == "__main__":
    main(sys.argv[1])
