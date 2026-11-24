#!/usr/bin/env python3
"""A .glb brought in with its pictures cut down to size: every embedded image is
resized so its longer side is at most `side` pixels and stored again as a JPEG
(or a PNG if it has any see-through in it). Everything else is carried over.

    python3 tools/import_glb_small.py <in.glb> <out.glb> [side=1024]
"""
import json
import struct
import sys

import cv2
import numpy as np


def main(src, dst, side=1024):
    data = open(src, "rb").read()
    n = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + n])
    blob = data[20 + n + 8:]
    views = doc["bufferViews"]
    image_views = {im["bufferView"]: im for im in doc.get("images", []) if "bufferView" in im}
    out = bytearray()
    for i, v in enumerate(views):
        chunk = blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        if i in image_views:
            img = cv2.imdecode(np.frombuffer(chunk, np.uint8), cv2.IMREAD_UNCHANGED)
            h, w = img.shape[:2]
            k = side / max(h, w)
            if k < 1.0:
                img = cv2.resize(img, (round(w * k), round(h * k)), interpolation=cv2.INTER_AREA)
            if img.ndim == 3 and img.shape[2] == 4 and img[..., 3].min() < 250:
                ok, enc = cv2.imencode(".png", img)
                image_views[i]["mimeType"] = "image/png"
            else:
                ok, enc = cv2.imencode(".jpg", img[..., :3] if img.ndim == 3 else img, [cv2.IMWRITE_JPEG_QUALITY, 88])
                image_views[i]["mimeType"] = "image/jpeg"
            chunk = enc.tobytes()
        while len(out) % 4:
            out.append(0)
        v["byteOffset"] = len(out)
        v["byteLength"] = len(chunk)
        out += chunk
    while len(out) % 4:
        out.append(0)
    doc["buffers"][0]["byteLength"] = len(out)
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(out), 0x004E4942)); f.write(out)
    print("%s: %.1f MB -> %.1f MB" % (dst, len(data) / 1e6, (28 + len(js) + len(out)) / 1e6))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1024)
