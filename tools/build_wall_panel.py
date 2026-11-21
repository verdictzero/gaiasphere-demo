#!/usr/bin/env python3
"""A rough-hewn plank wall panel, modelled from one picture of it and its normal map.

    python3 tools/build_wall_panel.py BASECOLOR.jpg NORMAL.jpg assets/build/wall_plank

The picture is of the panel face-on, on magenta. The model is the picture
PROJECTED onto geometry cut to it: every plank is its own slab, traced along its
own wavy edges and ragged ends; the two rails and the brace are slabs standing
proud of the planks, so the panel has real gaps, real edges and real depth from
the side, and the picture and its normal map supply everything else.

Writes (2 m x 2 m, origin at the middle of the bottom edge, facing +Z, metres):
    wall_plank_lod0.glb    every edge followed closely
    wall_plank_lod1.glb    edges followed loosely, ends cut square
    wall_plank_lod2.glb    two crossed-out cards: one quad each side, cut out by alpha
    wall_plank_basecolor.png   the picture, its wood bled out under the magenta, the
                               panel's own shape in the alpha
    wall_plank_normal.png
"""
import json
import struct
import sys
from pathlib import Path

import cv2
import numpy as np
from scipy import ndimage as ndi

SIZE_M = 2.0            # the picture's side, metres
PLANK_T = 0.045         # how thick a plank is
RAIL_T = 0.04           # how far the rails and the brace stand in front of the planks


# ------------------------------------------------------------------ the picture

def key(rgb):
    """The panel's mask: everything that is not the magenta behind it."""
    r, g, b = [rgb[..., i].astype(np.float32) for i in range(3)]
    pink = np.minimum(r, b) - g
    # (Generous to the background: the gaps between planks are a few pixels of
    # magenta that the picture's compression has muddied, and they must survive.)
    back = pink > 28.0
    # Specks of "background" inside the wood are not gaps: only what is of a size.
    lab, n = ndi.label(back)
    sizes = ndi.sum(back, lab, range(1, n + 1))
    back = np.isin(lab, [i + 1 for i, sz in enumerate(sizes) if sz >= 40])
    return ~back


def bleed(rgb, mask):
    """The wood's colour carried out over the background, so no magenta is ever sampled."""
    inner = ndi.binary_erosion(mask, iterations=2)
    idx = ndi.distance_transform_edt(~inner, return_distances=False, return_indices=True)
    return rgb[idx[0], idx[1]]


def runs(row):
    """[(start, end)] of the True stretches of a row."""
    d = np.diff(np.concatenate([[0], row.astype(np.int8), [0]]))
    return list(zip(np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]))


def read_panel(mask):
    """Where everything is: the rails' rows, each plank's two edges down the picture
    (seen where they can be, carried straight across where a rail or the brace hides
    them), each plank's top and bottom, and the brace's two edges."""
    h, w = mask.shape
    per_row = [runs(mask[y]) for y in range(h)]
    counts = np.array([len(r) for r in per_row])
    # How many planks: the most runs any good number of rows show. (Not the usual
    # number: the brace closes one gap or another in most rows.)
    tally = np.bincount(counts)
    planks = int(max(c for c in range(2, len(tally)) if tally[c] >= 0.07 * h))        # (a split end makes a few rows with one more)
    clean = [y for y in range(h) if counts[y] == planks]
    # A rail's rows: the panel is one unbroken run right across.
    solid = np.array([counts[y] == 1 and per_row[y][0][1] - per_row[y][0][0] > w * 0.8 for y in range(h)])
    lab, n = ndi.label(solid)
    bands = sorted([(sl[0].start, sl[0].stop) for sl in ndi.find_objects(lab) if sl[0].stop - sl[0].start > 12])
    top_rail, bottom_rail = bands[0], bands[-1]
    # The gaps between planks, by where they usually are.
    centres = np.median(np.array([[(per_row[y][i][1] + per_row[y][i + 1][0]) / 2 for i in range(planks - 1)] for y in clean]), axis=0)
    left = np.full((planks, h), np.nan)
    right = np.full((planks, h), np.nan)
    covered = np.zeros((planks - 1, h), bool)                          # the brace over a gap
    for y in range(h):
        if solid[y]:
            continue
        gaps = [(per_row[y][i][1], per_row[y][i + 1][0]) for i in range(len(per_row[y]) - 1)]
        for g, c in enumerate(centres):
            hit = [gp for gp in gaps if gp[0] - 6 <= c <= gp[1] + 6]
            if hit:
                right[g, y] = hit[0][0]
                left[g + 1, y] = hit[0][1]
            elif top_rail[1] <= y < bottom_rail[0]:
                covered[g, y] = True
        if per_row[y]:
            if abs(per_row[y][0][0] - np.nanmedian(left[0]) if np.isfinite(left[0]).any() else 0) < 40:
                left[0, y] = per_row[y][0][0]
            right[-1, y] = per_row[y][-1][1]
    # The outer planks' outer edges: not where a rail sticks out past them.
    for band in (top_rail, bottom_rail):
        left[0, band[0] - 2:band[1] + 2] = np.nan
        right[-1, band[0] - 2:band[1] + 2] = np.nan
    tops, bottoms = [], []
    for p in range(planks):
        seen = np.nonzero(np.isfinite(left[p]) & np.isfinite(right[p]))[0]
        x0, x1 = int(np.nanmedian(left[p])), int(np.nanmedian(right[p]))
        col = mask[:, x0 + 4:x1 - 4].any(axis=1)
        ys = np.nonzero(col)[0]
        tops.append(ys.min())
        bottoms.append(ys.max() + 1)
        for edge in (left[p], right[p]):
            ok = np.isfinite(edge)
            edge[:] = np.interp(np.arange(h), np.nonzero(ok)[0], edge[ok])
    # The brace: the rows it covers each gap in give a point on each of its edges.
    upper, lower = [], []
    for g in range(planks - 1):
        # (The longest unbroken stretch of rows: a knot closing the gap is not the brace.)
        lab, n = ndi.label(covered[g])
        if n == 0:
            continue
        longest = max(ndi.find_objects(lab), key=lambda sl: sl[0].stop - sl[0].start)[0]
        if longest.stop - longest.start > 12:
            upper.append((centres[g], longest.start))
            lower.append((centres[g], longest.stop))
    brace = None
    if len(upper) >= 2:
        ku, cu = np.polyfit([p[0] for p in upper], [p[1] for p in upper], 1)       # y = k x + c
        kl, cl = np.polyfit([p[0] for p in lower], [p[1] for p in lower], 1)
        y_top, y_bot = top_rail[1], bottom_rail[0]
        brace = np.array([[(y_top - cu) / ku, y_top], [(y_top - cl) / kl, y_top],
                          [(y_bot - cl) / kl, y_bot], [(y_bot - cu) / ku, y_bot]])
    rails = []
    for band in (top_rail, bottom_rail):
        xs = np.nonzero(mask[band[0]:band[1]].any(axis=0))[0]
        rails.append(np.array([[xs.min(), band[0]], [xs.max() + 1, band[0]], [xs.max() + 1, band[1]], [xs.min(), band[1]]], float))
    return dict(left=left, right=right, tops=tops, bottoms=bottoms, rails=rails, brace=brace, planks=planks)


def plank_outline(mask, panel, p, eps, square_ends):
    """One plank's outline in pixels, clockwise as seen (y down)."""
    left, right = panel["left"][p], panel["right"][p]
    y0, y1 = panel["tops"][p], panel["bottoms"][p]
    pts = []
    xs_top = np.linspace(left[y0 + 6] + 1, right[y0 + 6] - 1, 2 if square_ends else 7)
    for x in xs_top:                                    # the hewn top, left to right
        col = np.nonzero(mask[:y0 + 40, int(x)])[0]
        pts.append((x, y0 + 3 if square_ends else (col.min() if len(col) else y0)))
    for y in range(y0 + 8, y1 - 8, 2):                  # the right edge, down
        pts.append((right[y], y))
    xs_bot = xs_top[::-1]
    for x in xs_bot:                                    # the bottom, right to left
        col = np.nonzero(mask[y1 - 40:, int(x)])[0]
        pts.append((x, y1 - 3 if square_ends else (y1 - 40 + col.max() + 1 if len(col) else y1)))
    for y in range(y1 - 9, y0 + 7, -2):                 # the left edge, up
        pts.append((left[y], y))
    poly = cv2.approxPolyDP(np.array(pts, np.float32).reshape(-1, 1, 2), eps, True).reshape(-1, 2)
    return poly.astype(float)


# ------------------------------------------------------------------ the mesh

def ear_clip(poly):
    """Triangles (index triples) of a simple polygon, whichever way it winds."""
    n = len(poly)
    area = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n))
    idx = list(range(n)) if area > 0 else list(range(n - 1, -1, -1))
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    tris = []
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if cross(a, b, c) <= 1e-9:
                continue
            if any(cross(a, b, poly[j]) > 0 and cross(b, c, poly[j]) > 0 and cross(c, a, poly[j]) > 0
                   for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            break
        else:
            idx.pop(0)                                   # a sliver nothing can see past: drop a corner
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


class Mesh:
    def __init__(self):
        self.p, self.n, self.t, self.uv, self.idx = [], [], [], [], []

    def vert(self, p, n, t, uv):
        self.p.append(p); self.n.append(n); self.t.append(t); self.uv.append(uv)
        return len(self.p) - 1

    def tri(self, a, b, c):
        self.idx += [a, b, c]

    @property
    def tris(self):
        return len(self.idx) // 3


def slab(mesh, poly_px, z_back, z_front, px, back=True):
    """A polygon of the picture as a slab: its face, its back and its edge."""
    world = lambda q, z: ((q[0] - px / 2) * SIZE_M / px, (px - q[1]) * SIZE_M / px, z)
    uv = lambda q: (q[0] / px, q[1] / px)
    tris = ear_clip([tuple(q) for q in poly_px])
    centre = poly_px.mean(axis=0)
    # The face: the picture, straight on.
    f = [mesh.vert(world(q, z_front), (0, 0, 1), (1, 0, 0, 1), uv(q)) for q in poly_px]
    for a, b, c in tris:
        mesh.tri(f[a], f[c], f[b])        # (y is flipped going from picture to world)
    if back:
        bk = [mesh.vert(world(q, z_back), (0, 0, -1), (1, 0, 0, -1), uv(q)) for q in poly_px]
        for a, b, c in tris:
            mesh.tri(bk[a], bk[b], bk[c])
    # The edge: each stretch its own flat face, coloured by the wood just inside it.
    n = len(poly_px)
    for i in range(n):
        q0, q1 = poly_px[i], poly_px[(i + 1) % n]
        d = q1 - q0
        length = np.hypot(*d)
        if length < 1e-6:
            continue
        out = np.array([d[1], -d[0]]) / length
        if np.dot(out, (q0 + q1) / 2 - centre) < 0:
            out = -out
        normal = (out[0], -out[1], 0.0)
        along = (d[0] / length, -d[1] / length, 0.0, 1.0)
        inside0, inside1 = q0 - out * 5.0, q1 - out * 5.0
        deeper0, deeper1 = q0 - out * 9.0, q1 - out * 9.0
        v0 = mesh.vert(world(q0, z_front), normal, along, uv(inside0))
        v1 = mesh.vert(world(q1, z_front), normal, along, uv(inside1))
        v2 = mesh.vert(world(q1, z_back), normal, along, uv(deeper1))
        v3 = mesh.vert(world(q0, z_back), normal, along, uv(deeper0))
        # Wound to face outward, whichever way the outline runs.
        e1 = np.subtract(mesh.p[v1], mesh.p[v0]); e2 = np.subtract(mesh.p[v2], mesh.p[v0])
        if np.dot(np.cross(e1, e2), normal) > 0:
            mesh.tri(v0, v1, v2); mesh.tri(v0, v2, v3)
        else:
            mesh.tri(v0, v2, v1); mesh.tri(v0, v3, v2)


def card(mesh, px):
    """The whole picture on one quad each side, for far away."""
    for z, n, w, order in ((PLANK_T, (0, 0, 1), 1, (0, 1, 2, 0, 2, 3)), (0.0, (0, 0, -1), -1, (0, 2, 1, 0, 3, 2))):
        v = [mesh.vert(((x - 0.5) * SIZE_M, (1 - y) * SIZE_M, z), n, (1, 0, 0, w), (x, y)) for x, y in ((0, 1), (1, 1), (1, 0), (0, 0))]
        for a, b, c in zip(order[0::3], order[1::3], order[2::3]):
            mesh.tri(v[a], v[b], v[c])


# ------------------------------------------------------------------ glb

def write_glb(path, mesh, name, base_png, normal_png, cutout):
    P = np.asarray(mesh.p, np.float32)
    N = np.asarray(mesh.n, np.float32)
    T = np.asarray(mesh.t, np.float32)
    UV = np.asarray(mesh.uv, np.float32)
    I = np.asarray(mesh.idx, np.uint16)
    blob = bytearray()
    views, accessors = [], []

    def push(arr, target, ctype, atype, minmax=False):
        while len(blob) % 4:
            blob.append(0)
        views.append(dict(buffer=0, byteOffset=len(blob), byteLength=arr.nbytes, **({"target": target} if target else {})))
        blob.extend(arr.tobytes())
        acc = dict(bufferView=len(views) - 1, componentType=ctype, count=len(arr) if arr.ndim > 1 else arr.size, type=atype)
        if minmax:
            acc["min"], acc["max"] = arr.min(axis=0).tolist(), arr.max(axis=0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    a_p = push(P, 34962, 5126, "VEC3", True)
    a_n = push(N, 34962, 5126, "VEC3")
    a_t = push(T, 34962, 5126, "VEC4")
    a_uv = push(UV, 34962, 5126, "VEC2")
    a_i = push(I, 34963, 5123, "SCALAR")
    images = []
    for png in (base_png, normal_png):
        data = Path(png).read_bytes()
        while len(blob) % 4:
            blob.append(0)
        views.append(dict(buffer=0, byteOffset=len(blob), byteLength=len(data)))
        blob.extend(data)
        images.append(dict(bufferView=len(views) - 1, mimeType="image/png", name=Path(png).stem))
    material = dict(name="wall_plank" + ("_cutout" if cutout else ""),
                    pbrMetallicRoughness=dict(baseColorTexture=dict(index=0), metallicFactor=0.0, roughnessFactor=0.86),
                    normalTexture=dict(index=1), doubleSided=False)
    if cutout:
        material.update(alphaMode="MASK", alphaCutoff=0.5)
    gltf = dict(asset=dict(version="2.0", generator="tools/build_wall_panel.py"), scene=0, scenes=[dict(nodes=[0])],
                nodes=[dict(name=name, mesh=0)],
                meshes=[dict(name=name, primitives=[dict(attributes=dict(POSITION=a_p, NORMAL=a_n, TANGENT=a_t, TEXCOORD_0=a_uv),
                                                         indices=a_i, material=0)])],
                materials=[material], textures=[dict(source=0, sampler=0), dict(source=1, sampler=0)],
                samplers=[dict(magFilter=9729, minFilter=9987, wrapS=33071, wrapT=33071)], images=images,
                accessors=accessors, bufferViews=views, buffers=[dict(byteLength=len(blob))])
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    while len(blob) % 4:
        blob.append(0)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<I4s", len(js), b"JSON")); f.write(js)
        f.write(struct.pack("<I4s", len(blob), b"BIN\0")); f.write(bytes(blob))


def main(base_path, normal_path, out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    rgb = cv2.cvtColor(cv2.imread(base_path), cv2.COLOR_BGR2RGB)
    px = rgb.shape[0]
    mask = key(rgb)
    wood = bleed(rgb, mask)
    alpha = (ndi.gaussian_filter(mask.astype(np.float32), 0.7) * 255).astype(np.uint8)
    base_png = out / "wall_plank_basecolor.png"
    normal_png = out / "wall_plank_normal.png"
    cv2.imwrite(str(base_png), cv2.cvtColor(np.dstack([wood, alpha]), cv2.COLOR_RGBA2BGRA))
    # The normal map: flat where there is no wood (its background is flat already).
    cv2.imwrite(str(normal_png), cv2.imread(normal_path))
    panel = read_panel(mask)
    report = []
    for lod, (eps, square) in enumerate(((1.6, False), (4.5, True))):
        mesh = Mesh()
        for p in range(panel["planks"]):
            slab(mesh, plank_outline(mask, panel, p, eps, square), 0.0, PLANK_T, px)
        for rail in panel["rails"]:
            slab(mesh, rail, PLANK_T, PLANK_T + RAIL_T, px, back=False)
        if panel["brace"] is not None:
            slab(mesh, panel["brace"], PLANK_T, PLANK_T + RAIL_T * 0.8, px, back=False)
        write_glb(out / f"wall_plank_lod{lod}.glb", mesh, f"wall_plank_LOD{lod}", base_png, normal_png, False)
        report.append(f"lod{lod} {mesh.tris} triangles, {len(mesh.p)} vertices")
    mesh = Mesh()
    card(mesh, px)
    write_glb(out / "wall_plank_lod2.glb", mesh, "wall_plank_LOD2", base_png, normal_png, True)
    report.append(f"lod2 {mesh.tris} triangles")
    print("wall panel: %d planks, 2 rails%s; %s" % (panel["planks"], ", a brace" if panel["brace"] is not None else "", "; ".join(report)))
    # A drawing of what was traced, for checking it against the picture.
    check = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR).copy()
    check[~mask] = (40, 40, 40)
    for p in range(panel["planks"]):
        cv2.polylines(check, [plank_outline(mask, panel, p, 1.6, False).astype(np.int32)], True, (0, 255, 255), 1)
    for quad in panel["rails"] + ([panel["brace"]] if panel["brace"] is not None else []):
        cv2.polylines(check, [quad.astype(np.int32)], True, (255, 160, 0), 1)
    cv2.imwrite(str(out / "wall_plank_traced.png"), cv2.resize(check, (1024, 1024), interpolation=cv2.INTER_NEAREST))


if __name__ == "__main__":
    main(*sys.argv[1:4])
