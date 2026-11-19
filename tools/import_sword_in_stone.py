#!/usr/bin/env python3
"""Unpack the sword-in-the-stone model into a game-sized glTF.

    7z x assets/staged/sword/sword_in_stone_v2.7z.001 -o/tmp/sword
    python3 tools/import_sword_in_stone.py /tmp/sword/sword_in_stone_v2.glb assets/sword_in_stone

The model as delivered is one 108 MB .glb, nearly all of it three 4K textures on
the stone (the normal map alone is an 80 MB PNG). This writes the same scene as
sword_in_stone.gltf + .bin with its textures beside it, the stone's maps scaled to
2K and stored as JPEG. Geometry, nodes and materials are untouched.
"""
import io
import json
import struct
import sys
from pathlib import Path

from PIL import Image

Image.MAX_IMAGE_PIXELS = None
src, out = Path(sys.argv[1]), Path(sys.argv[2])
(out / "textures").mkdir(parents=True, exist_ok=True)
with open(src, "rb") as f:
    _, _, _ = struct.unpack("<4sII", f.read(12))
    n, _ = struct.unpack("<I4s", f.read(8))
    gltf = json.loads(f.read(n))
    n, _ = struct.unpack("<I4s", f.read(8))
    blob = f.read(n)

views = gltf["bufferViews"]
image_views = {img["bufferView"] for img in gltf["images"]}
for img in gltf["images"]:
    v = views[img["bufferView"]]
    data = blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
    name = img.get("name", "image").replace(" ", "_")
    im = Image.open(io.BytesIO(data))
    if max(im.size) > 2048:                       # the stone's 4K maps
        im = im.convert("RGB").resize((2048, 2048), Image.LANCZOS)
        uri = f"textures/{name}.jpg"
        im.save(out / uri, quality=90, optimize=True)
    else:
        uri = f"textures/{name}.png"
        (out / uri).write_bytes(data) if img["mimeType"] == "image/png" else im.save(out / uri)
    img.clear()
    img.update(uri=uri, name=name)

# keep only the geometry in the buffer, and renumber the views that point at it
keep, remap, packed = [], {}, bytearray()
for i, v in enumerate(views):
    if i in image_views:
        continue
    while len(packed) % 4:
        packed.append(0)
    data = blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
    remap[i] = len(keep)
    keep.append({**v, "byteOffset": len(packed)})
    packed.extend(data)
for a in gltf["accessors"]:
    if "bufferView" in a:
        a["bufferView"] = remap[a["bufferView"]]
gltf["bufferViews"] = keep
gltf["buffers"] = [dict(uri="sword_in_stone.bin", byteLength=len(packed))]
(out / "sword_in_stone.bin").write_bytes(bytes(packed))
(out / "sword_in_stone.gltf").write_text(json.dumps(gltf, indent=1))
print("wrote", out, "geometry %.1f MB" % (len(packed) / 1e6),
      "textures", sorted(p.name for p in (out / "textures").iterdir()))
