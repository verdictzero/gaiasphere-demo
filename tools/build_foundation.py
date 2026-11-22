#!/usr/bin/env python3
"""Foundation blocks: coursed stone in a frame of timber.

    python3 tools/build_foundation.py assets/build/foundation

A block is a box of stone (the block-wall texture beside this, tiled at 2 m to
the picture, so the courses run on from one block to the next) with a timber
at every edge: a post up each corner, a sill round the foot, a rim round the
head. The timbers are stretches of the plank kit's own beams
(assets/build/plank_kit), so a wall stood on a foundation is of the same wood.

Everything keeps inside the block's own box, its foot on the origin: blocks set
side by side on the kit's 2 m grid touch and never overlap. The stone sits a
little in from the timbers' faces, so no two surfaces share a plane.

    foundation_<a..c>_lod0.glb        2 m x 1 m x 2 m
    foundation_step_<a..b>_lod0.glb   1.2 m x 1 m x 0.6 m, a doorstep

    steps_<a..b>_lod0.glb             five steps up a metre in a run of two, 2 m wide
    steps_narrow_<a..b>_lod0.glb      the same, 1.2 m wide: a door's worth

They are a metre tall to be sunk into the ground to whatever depth the slope
asks for; the steps climb toward -z from their foot at y = 0 and carry on a metre
below it.
"""
import json
import random
import struct
import sys
from pathlib import Path

import numpy as np

PX_PER_M = 585.0
TILE = 2.0              # metres of wall to one repeat of the stone picture
INSET = 0.035           # how far the stone sits in from the timbers' faces
E = np.eye(3)


class Part:
    def __init__(self):
        self.p, self.n, self.t, self.uv, self.idx = [], [], [], [], []

    def quad(self, corner, t, up, uvs):
        """A face from `corner` along `t` and `up` (its normal is t x up); `uvs` are
        (u0, v0, u1, v1): u runs along t, and v0 is the picture's top, at the far end of up."""
        n = np.cross(t, up); n = n / np.linalg.norm(n)
        tan = (*(t / np.linalg.norm(t)), 1.0)
        u0, v0, u1, v1 = uvs
        base = len(self.p)
        for q, uv in ((corner, (u0, v1)), (corner + t, (u1, v1)), (corner + t + up, (u1, v0)), (corner + up, (u0, v0))):
            self.p.append(tuple(map(float, q))); self.n.append(tuple(map(float, n)))
            self.t.append(tuple(map(float, tan))); self.uv.append(uv)
        self.idx += [base, base + 1, base + 2, base, base + 2, base + 3]


def faces(lo, hi, along=None, skip=()):
    """The six faces of a box as (corner, t, up, axis of the normal, its sign). `along`
    is the axis a timber's grain runs: its long faces take t that way."""
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    for k in range(3):
        for s in (-1.0, 1.0):
            if (k, s) in skip:
                continue
            i, j = [a for a in range(3) if a != k]
            if along == j or (along is None and i == 1):
                i, j = j, i                                 # (stone: up the wall is up the picture)
            t, up = E[i].copy(), E[j].copy()
            if np.dot(np.cross(t, up), E[k] * s) < 0:
                t = -t
            corner = np.where(s > 0, hi, lo) * E[k]
            for a, d in ((i, t), (j, up)):
                corner = corner + E[a] * (lo[a] if d[a] > 0 else hi[a])
            yield corner, t * (hi[i] - lo[i]), up * (hi[j] - lo[j]), k, s


def stone(part, lo, hi, rng, shift=None, skip=((1, -1.0),)):
    shift = shift or (rng.random(), rng.random())
    for corner, t, up, k, s in faces(lo, hi, skip=skip):
        # Mapped by where it is in the world, so courses carry on round a corner's
        # worth of blocks; each block starts somewhere else in the picture.
        ti, ui = int(np.argmax(np.abs(t))), int(np.argmax(np.abs(up)))
        a0 = corner[ti] * np.sign(t[ti]); b0 = corner[ui] * np.sign(up[ui])
        u0 = a0 / TILE + shift[0]; u1 = u0 + np.linalg.norm(t) / TILE
        v1 = -b0 / TILE + shift[1]; v0 = v1 - np.linalg.norm(up) / TILE
        part.quad(corner, t, up, (u0, v0, u1, v1))


def timber(part, lo, hi, along, beams, atlas, rng):
    """A squared timber: each long face a stretch of one of the kit's beams, taken
    from inside its outline (so no edge of the photograph shows), each end a
    small square of the same."""
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    length = hi[along] - lo[along]
    for corner, t, up, k, s in faces(lo, hi, along=along):
        b = rng.choice(beams)
        x0, y0, w, h = b["rect"]
        band = h - 56                                       # clear of the waney edges
        top = y0 + 28 + rng.uniform(0, band * 0.25)
        tall = band * 0.72
        if k == along:                                      # an end: end grain is not to be had, a dark knotty patch stands in
            side = tall * 0.6
            left = x0 + 40 + rng.uniform(0, w - 80 - side)
            uv = (left, top, left + side, top + side)
        else:
            run = min(length * PX_PER_M / 0.5, w - 80)
            left = x0 + 40 + rng.uniform(0, w - 80 - run)
            uv = (left, top, left + run, top + tall)
            if rng.random() < 0.5:
                uv = (uv[2], uv[1], uv[0], uv[3])
        part.quad(corner, t, up, (uv[0] / atlas[0], uv[1] / atlas[1], uv[2] / atlas[0], uv[3] / atlas[1]))


def block(size, beam, beams, atlas, seed):
    rng = random.Random(seed)
    w, h, d = size
    rock, wood = Part(), Part()
    stone(rock, (-w / 2 + INSET, 0.0, -d / 2 + INSET), (w / 2 - INSET, h - INSET * 0.6, d / 2 - INSET), rng)
    x, z = w / 2, d / 2
    for sx in (-1, 1):
        for sz in (-1, 1):                                  # posts
            a = (min(sx * x, sx * (x - beam)), 0.0, min(sz * z, sz * (z - beam)))
            timber(wood, a, (a[0] + beam, h, a[2] + beam), 1, beams, atlas, rng)
    for y0, t in ((0.0, beam * 0.85), (h - beam, beam)):    # sill and rim, between the posts
        for sz in (-1, 1):
            a = (-x + beam, y0, min(sz * z, sz * (z - beam)))
            timber(wood, a, (x - beam, y0 + t, a[2] + beam), 0, beams, atlas, rng)
        for sx in (-1, 1):
            a = (min(sx * x, sx * (x - beam)), y0, -z + beam)
            timber(wood, a, (a[0] + beam, y0 + t, z - beam), 2, beams, atlas, rng)
    return rock, wood


STEPS = 5
SUNK = 1.0              # how far the steps go on down below their foot, for sloping ground


def steps(width, beam, beams, atlas, seed, run=2.0, rise=1.0):
    """STONE STEPS IN TIMBER: five of them, climbing a metre in two (toward -z), so
    a flight reaches the top of a foundation block from the ground beside it. Each
    step is its own block of stone with a timber along its nose, a post under each
    end of that, and a timber down each side of the tread. All of it carries on a
    metre below the foot, to be sunk like the blocks."""
    rng = random.Random(seed)
    rock, wood = Part(), Part()
    shift = (rng.random(), rng.random())
    tread, lift = run / STEPS, rise / STEPS
    x = width / 2
    for i in range(STEPS):
        front, back, top = run / 2 - i * tread, run / 2 - (i + 1) * tread, (i + 1) * lift
        hidden = ((1, -1.0),) + (((2, -1.0),) if i < STEPS - 1 else ())     # the next step stands against its back
        stone(rock, (-x + INSET, -SUNK, back), (x - INSET, top - INSET * 0.6, front - INSET), rng, shift, hidden)
        timber(wood, (-x + beam, top - beam, front - beam), (x - beam, top, front), 0, beams, atlas, rng)
        for sx in (-1, 1):
            a = min(sx * x, sx * (x - beam))
            timber(wood, (a, -SUNK, front - beam), (a + beam, top, front), 1, beams, atlas, rng)
            timber(wood, (a, top - beam, back), (a + beam, top, front - beam), 2, beams, atlas, rng)
    return rock, wood


def write_glb(path, name, rock, wood):
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
    prims = []
    for m, part in enumerate((rock, wood)):
        attrs = dict(POSITION=push(np.asarray(part.p, np.float32), 34962, 5126, "VEC3", True),
                     NORMAL=push(np.asarray(part.n, np.float32), 34962, 5126, "VEC3"),
                     TANGENT=push(np.asarray(part.t, np.float32), 34962, 5126, "VEC4"),
                     TEXCOORD_0=push(np.asarray(part.uv, np.float32), 34962, 5126, "VEC2"))
        prims.append(dict(attributes=attrs, indices=push(np.asarray(part.idx, np.uint16), 34963, 5123, "SCALAR"), material=m))
    gltf = dict(asset=dict(version="2.0", generator="tools/build_foundation.py"), scene=0, scenes=[dict(nodes=[0])],
                nodes=[dict(name=name, mesh=0)], meshes=[dict(name=name, primitives=prims)],
                materials=[
                    dict(name="block_wall", pbrMetallicRoughness=dict(baseColorTexture=dict(index=0),
                         metallicRoughnessTexture=dict(index=2)), normalTexture=dict(index=1, scale=1.0),
                         occlusionTexture=dict(index=2)),
                    dict(name="plank_kit", pbrMetallicRoughness=dict(baseColorTexture=dict(index=3), metallicFactor=0.0,
                         roughnessFactor=0.88), normalTexture=dict(index=4, scale=1.0))],
                textures=[dict(source=0, sampler=0), dict(source=1, sampler=0), dict(source=2, sampler=0),
                          dict(source=3, sampler=1), dict(source=4, sampler=1)],
                samplers=[dict(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497),
                          dict(magFilter=9729, minFilter=9987, wrapS=33071, wrapT=33071)],
                images=[dict(uri="block_wall_basecolor.jpg"), dict(uri="block_wall_normal.jpg"), dict(uri="block_wall_orm.jpg"),
                        dict(uri="../plank_kit/plank_kit_basecolor.png"), dict(uri="../plank_kit/plank_kit_normal.png")],
                accessors=accessors, bufferViews=views, buffers=[dict(byteLength=len(blob))])
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    while len(blob) % 4:
        blob.append(0)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<I4s", len(js), b"JSON")); f.write(js)
        f.write(struct.pack("<I4s", len(blob), b"BIN\x00")); f.write(bytes(blob))


def main(out_dir):
    out = Path(out_dir)
    kit = json.loads((out.parent / "plank_kit" / "plank_kit.json").read_text())
    beams = [p for p in kit["pieces"] if p["kind"] == "beam"]
    for stem, size, beam, count in (("foundation", (2.0, 1.0, 2.0), 0.14, 3), ("foundation_step", (1.2, 1.0, 0.6), 0.1, 2)):
        for i in range(count):
            name = f"{stem}_{chr(97 + i)}"
            rock, wood = block(size, beam, beams, kit["atlas"], 900 + i * 17 + len(stem))
            write_glb(out / f"{name}_lod0.glb", name, rock, wood)
            print("%s: %d triangles" % (name, (len(rock.idx) + len(wood.idx)) // 3))


    for stem, width, beam, count in (("steps", 2.0, 0.1, 2), ("steps_narrow", 1.2, 0.09, 2)):
        for i in range(count):
            name = f"{stem}_{chr(97 + i)}"
            rock, wood = steps(width, beam, beams, kit["atlas"], 700 + i * 13 + len(stem))
            write_glb(out / f"{name}_lod0.glb", name, rock, wood)
            print("%s: %d triangles" % (name, (len(rock.idx) + len(wood.idx)) // 3))


    # THE STONE IS MAPPED THROUGH THE WORLD, three ways, by materials/MAT_block_wall.tres:
    # every model here is told (in its .import, once Godot has written one) to take
    # that material in place of its own, so courses run unbroken across blocks and
    # steps however they are set down. The UVs written above are what it falls back to.
    want = '_subresources={\n"materials": {\n"block_wall": {\n"use_external/enabled": true,\n' \
           '"use_external/fallback_path": "res://materials/MAT_block_wall.tres",\n' \
           '"use_external/path": "res://materials/MAT_block_wall.tres"\n}\n}\n}'
    told = 0
    for imp in sorted(out.glob("*.glb.import")):
        text = imp.read_text()
        if "MAT_block_wall" in text:
            continue
        start = text.index("_subresources=")
        end = text.index("\ngltf/", start)
        imp.write_text(text[:start] + want + text[end:])
        told += 1
    print("%d models told to use the world-mapped stone%s" % (told, "" if list(out.glob("*.glb.import")) else " (none imported yet: import, then run this again)"))


if __name__ == "__main__":
    main(sys.argv[1])
