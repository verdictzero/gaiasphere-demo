#!/usr/bin/env python3
"""Take the berry-cluster cards out of the berry bush model.

    python3 tools/strip_bush_clusters.py assets/berry_bush/viburnum_bush.glb

The bush is cards cut from one sheet of eight pictures: five of leafy sprays,
two of bare twigs, and one close-up of a single cluster of berries (the cell at
u 0.25-0.5, v 0.5-1). The cards showing that close-up hang about the bush as
big red discs; every triangle mapped into that cell is dropped. The sprays keep
the berries photographed among their leaves.
"""
import json
import struct
import sys

import numpy as np

CELL = (0.25, 0.5, 0.5, 1.0)      # u0, u1, v0, v1


def main(path):
    with open(path, "rb") as f:
        f.read(12)
        n, _ = struct.unpack("<II", f.read(8)); gltf = json.loads(f.read(n))
        m, _ = struct.unpack("<II", f.read(8)); blob = bytearray(f.read(m))
    dropped = kept = 0
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            def read(acc_i, dtype, width):
                acc = gltf["accessors"][acc_i]; view = gltf["bufferViews"][acc["bufferView"]]
                start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
                total = acc["count"] * (1 if acc["type"] == "SCALAR" else width)
                return np.frombuffer(bytes(blob[start:start + total * np.dtype(dtype).itemsize]), dtype).reshape(-1, width)
            uv = read(prim["attributes"]["TEXCOORD_0"], "<f4", 2)
            acc = gltf["accessors"][prim["indices"]]
            dtype = {5123: "<u2", 5125: "<u4"}[acc["componentType"]]
            tris = read(prim["indices"], dtype, 3)
            mid = uv[tris].mean(axis=1)
            mid = mid - np.floor(mid)
            out = (mid[:, 0] > CELL[0]) & (mid[:, 0] < CELL[1]) & (mid[:, 1] > CELL[2]) & (mid[:, 1] < CELL[3])
            keep = np.ascontiguousarray(tris[~out]).astype(dtype)
            dropped += int(out.sum()); kept += len(keep)
            while len(blob) % 4:
                blob.append(0)
            gltf["bufferViews"].append(dict(buffer=0, byteOffset=len(blob), byteLength=keep.nbytes, target=34963))
            blob.extend(keep.tobytes())
            gltf["accessors"].append(dict(bufferView=len(gltf["bufferViews"]) - 1, componentType=acc["componentType"],
                                          count=int(keep.size), type="SCALAR"))
            prim["indices"] = len(gltf["accessors"]) - 1
    while len(blob) % 4:
        blob.append(0)
    gltf["buffers"][0]["byteLength"] = len(blob)
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<I4s", len(js), b"JSON")); f.write(js)
        f.write(struct.pack("<I4s", len(blob), b"BIN\x00")); f.write(bytes(blob))
    print("%s: %d triangles dropped, %d kept" % (path, dropped, kept))


if __name__ == "__main__":
    main(sys.argv[1])
