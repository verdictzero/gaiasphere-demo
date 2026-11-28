#!/usr/bin/env python3
"""THE POWER KIT (the junction box, the light pole, the battery, the plug, the
solar panel and its mount), cut out of the set it was handed over in into one
file a piece and A CHAIN OF LEVELS OF DETAIL of each, for parts there will be a
great many of:

    assets/power/<piece>_lod0.glb ... _lodN.glb     geometry, each about half the last
    assets/power/power_parts_*.jpg, power_panel_*.jpg   the two materials' textures, once
    assets/power/manifest.json                      each piece's size and its levels' triangles

    pip install meshoptimizer
    python3 tools/build_power_kit.py assets/_inbox/power_stuff_set_1.glb
    python3 tools/set_texture_imports.py && godot --headless --path . --import

Every level keeps the first's own vertices where they sit on the texture, so
nothing swims as a piece steps down; only which of them are joined up changes
(and, after the first two, its hard edges are softened: see `joined`). The
textures stay the size they came at. No level is taken down by a pass that
ignores the texture's seams: where the simplifier can go no further and keep
them, the chain stops, and the level after it is the impostor. A piece's origin is its own, as modelled;
where the set had it standing in its row is dropped.
"""
import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
import meshoptimizer as mo
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "power"
# Each level's triangles as a share of the first's, and how far (a share of the
# piece's size) the simplifier may move the surface to get there.
STEPS = [(0.55, 0.01), (0.3, 0.03), (0.16, 0.07), (0.085, 0.14), (0.045, 0.28), (0.022, 0.5), (0.011, 1.0)]
# The levels that are colours with no texture (see "AND AFTER THOSE" below).
FLAT_STEPS = [(0.3, 0.04), (0.16, 0.08), (0.08, 0.15), (0.04, 0.3), (0.02, 0.5), (0.01, 1.0)]
FEWEST = 10                 # no level under this many triangles
# What each of the set's images is called here (in the order the set has them).
# EACH SET THAT HAS BEEN HANDED OVER (by its file's name): what its images are
# called here, in the order it has them, and what each of its parts is.
SETS = {
    "power_stuff_set_1": (
        ["power_parts_emission", "power_parts_basecolor", "power_parts_orm",
         "power_panel_normal", "power_panel_basecolor", "power_panel_orm"],
        {"4wayJunctionBox": "junction_box", "light_pole": "light_pole", "batteryBox": "battery_box", "plugEnd": "plug_end",
         "solarPanel": "solar_panel", "solarPanelAngleActuator": "solar_actuator",
         "solarPanelActuatorSupport": "solar_support", "solarPanelBox": "solar_box"}),
    "laser_ciws": (
        ["power_ciws_basecolor", "power_ciws_orm"],
        {"laser_CIWS_base": "ciws_base", "laser_CIWS_riser": "ciws_riser", "laser_CIWS_emitter": "ciws_emitter"}),
}
TEXTURES = []
NAMES = {}
COMP = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def main(src):
    global TEXTURES, NAMES
    TEXTURES, NAMES = SETS[Path(src).stem]
    data = open(src, "rb").read()
    n = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + n])
    blob = data[20 + n + 8:]

    def view(i):
        v = doc["bufferViews"][i]
        return blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]], v.get("byteStride", 0)

    def acc(i):
        a = doc["accessors"][i]
        raw, stride = view(a["bufferView"])
        kind = np.dtype(COMP[a["componentType"]])
        width = WIDTH[a["type"]]
        step = stride or kind.itemsize * width
        raw = raw[a.get("byteOffset", 0):]
        out = np.empty((a["count"], width), dtype=kind)
        for k in range(width):
            out[:, k] = np.ndarray((a["count"],), dtype=kind, buffer=raw, offset=k * kind.itemsize, strides=(step,))
        return out

    OUT.mkdir(parents=True, exist_ok=True)
    # ---- the textures, once, at the size they came at
    for i, image in enumerate(doc["images"]):
        raw, _ = view(image["bufferView"])
        im = Image.open(io.BytesIO(raw)).convert("RGB")
        im.save(OUT / (TEXTURES[i] + ".jpg"), quality=84, optimize=True)
        print("texture %-24s %d x %d" % (TEXTURES[i], im.width, im.height))
    source = [t["source"] for t in doc["textures"]]
    # Each material's colours, linear, a quarter the size (a face's own colour, not a texel's).
    base_colour = []
    for m in doc["materials"]:
        which = source[m["pbrMetallicRoughness"]["baseColorTexture"]["index"]]
        im = Image.open(OUT / (TEXTURES[which] + ".jpg")).convert("RGB")
        im = im.resize((im.width // 4, im.height // 4), Image.BOX)
        srgb = np.asarray(im).astype(np.float32) / 255.0
        base_colour.append(np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4))

    def tex(ref):
        return {"index": source[ref["index"]]}

    materials = []
    for m in doc["materials"]:
        pbr = m.get("pbrMetallicRoughness", {})
        out = {"name": "power_panel" if "normalTexture" in m else "power_parts", "doubleSided": bool(m.get("doubleSided", False)),
               "pbrMetallicRoughness": {}}
        if "baseColorTexture" in pbr:
            out["pbrMetallicRoughness"]["baseColorTexture"] = tex(pbr["baseColorTexture"])
        if "metallicRoughnessTexture" in pbr:
            out["pbrMetallicRoughness"]["metallicRoughnessTexture"] = tex(pbr["metallicRoughnessTexture"])
        if "normalTexture" in m:
            out["normalTexture"] = tex(m["normalTexture"])
        if "emissiveTexture" in m:
            out["emissiveTexture"] = tex(m["emissiveTexture"])
            out["emissiveFactor"] = m.get("emissiveFactor", [1.0, 1.0, 1.0])
        materials.append(out)
    # (And one with no texture: the far levels', drawn in their vertices' colours.)
    materials.append({"name": "power_flat", "doubleSided": True,
                      "pbrMetallicRoughness": {"metallicFactor": 0.25, "roughnessFactor": 0.62}})
    images = [{"uri": name + ".jpg"} for name in TEXTURES]
    textures = [{"source": i} for i in range(len(TEXTURES))]

    manifest = []
    for node in doc["nodes"]:
        if "mesh" not in node or node.get("name") not in NAMES:
            continue
        name = NAMES[node["name"]]
        parts = []
        for prim in doc["meshes"][node["mesh"]]["primitives"]:
            parts.append({"pos": acc(prim["attributes"]["POSITION"]).astype(np.float32),
                          "nrm": acc(prim["attributes"]["NORMAL"]).astype(np.float32),
                          "uv": acc(prim["attributes"]["TEXCOORD_0"]).astype(np.float32),
                          "idx": acc(prim["indices"]).astype(np.uint32).ravel(), "mat": prim.get("material", 0)})
        every = np.concatenate([p["pos"] for p in parts])
        lo, hi = every.min(axis=0), every.max(axis=0)
        # THE SAME PART WITH ITS HARD EDGES JOINED, for every level after the first
        # two: a hard edge is two rows of vertices with a normal each, and to a
        # simplifier that is a seam it may not close, so a boxy part will not come
        # down by much. Vertices that share a place AND a place on the texture are
        # made one (its normal the mean of theirs): the texture's own seams are
        # kept, so nothing is drawn with the wrong part of the picture, and far
        # off a softened edge is not seen.
        joined = []
        for p in parts:
            key = np.round(np.hstack([p["pos"], p["uv"]]) * 4096.0).astype(np.int64)
            _, first_of, back = np.unique(key, axis=0, return_index=True, return_inverse=True)
            back = back.ravel()
            nrm = np.zeros((len(first_of), 3), dtype=np.float64)
            np.add.at(nrm, back, p["nrm"])
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
            joined.append({"pos": p["pos"][first_of], "uv": p["uv"][first_of], "nrm": nrm.astype(np.float32),
                           "idx": back[p["idx"]].astype(np.uint32), "mat": p["mat"]})
        # [which set of vertices, the indices of each of its surfaces]
        levels = [[parts, [p["idx"] for p in parts]]]
        for step, (share, slack) in enumerate(STEPS):
            verts = parts if step == 0 else joined
            start = levels[-1][1] if levels[-1][0] is verts else [v["idx"] for v in verts]
            level = []
            for v, was in zip(verts, start):
                want = max(int(len(v["idx"]) // 3 * share), 2) * 3
                if want >= len(was):
                    level.append(was)
                    continue
                dest = np.zeros(len(was), dtype=np.uint32)
                got = mo.simplify(dest, was, v["pos"], target_index_count=want, target_error=slack)
                level.append(dest[:got].copy() if got >= 6 else was)
            tris = sum(len(i) // 3 for i in level)
            before = sum(len(i) // 3 for i in levels[-1][1])
            if tris < FEWEST:
                break
            if tris > before * 0.88:
                continue
            levels.append([verts, level])
        # AND AFTER THOSE, LEVELS WITH NO TEXTURE AT ALL. Every face of these parts is
        # its own island on the texture, and a simplifier that keeps the islands'
        # seams stops at about half the triangles. So the far levels give the
        # texture up: vertices are joined by place alone (no seams left, and it
        # comes down as far as wanted), and each carries the COLOUR the texture
        # has there, so the part is drawn in its own colours with no picture, from
        # a distance at which the picture could not be made out anyway.
        flats = []
        for p in parts:
            key = np.round(p["pos"] * 4096.0).astype(np.int64)
            _, first_of, back = np.unique(key, axis=0, return_index=True, return_inverse=True)
            back = back.ravel()
            nrm = np.zeros((len(first_of), 3), dtype=np.float64)
            np.add.at(nrm, back, p["nrm"])
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
            tex = base_colour[p["mat"]]
            h, w = tex.shape[:2]
            # (The colour at the MIDDLE of each face it is a corner of, not at the
            # corner itself: a corner sits on the face's edge, where the texture has
            # its worn, pale rim, and a part coloured from its corners came out
            # washed.)
            tri = p["idx"].reshape(-1, 3)
            mid = p["uv"][tri].mean(axis=1)
            px = np.clip((mid[:, 0] % 1.0 * w).astype(int), 0, w - 1)
            py = np.clip((mid[:, 1] % 1.0 * h).astype(int), 0, h - 1)
            face = tex[py, px]
            col = np.zeros((len(first_of), 3), dtype=np.float64)
            hits = np.zeros(len(first_of), dtype=np.float64)
            for corner in range(3):
                np.add.at(col, back[tri[:, corner]], face)
                np.add.at(hits, back[tri[:, corner]], 1.0)
            col /= np.maximum(hits[:, None], 1.0)
            flats.append({"pos": p["pos"][first_of], "nrm": nrm.astype(np.float32), "col": col.astype(np.float32),
                          "idx": back[p["idx"]].astype(np.uint32), "mat": len(materials) - 1})
        textured = len(levels)
        last = sum(len(i) // 3 for i in levels[-1][1])
        whole = sum(len(p["idx"]) // 3 for p in parts)
        for share, slack in FLAT_STEPS:
            level = []
            for v in flats:
                want = max(int(len(v["idx"]) // 3 * share), 4) * 3
                dest = np.zeros(len(v["idx"]), dtype=np.uint32)
                got = mo.simplify(dest, v["idx"], v["pos"], target_index_count=want, target_error=slack)
                level.append(dest[:got].copy() if got >= 6 else v["idx"])
            tris = sum(len(i) // 3 for i in level)
            if tris < FEWEST:
                break
            if tris > last * 0.75:
                continue
            levels.append([flats, level])
            last = tris
        counts = []
        for old in OUT.glob(name + "_lod*.glb*"):
            old.unlink()
        for k, (verts, level) in enumerate(levels):
            write(OUT / ("%s_lod%d.glb" % (name, k)), name, verts, level, materials, images, textures)
            counts.append(sum(len(i) // 3 for i in level))
        manifest.append({"name": name, "size_m": [round(float(v), 3) for v in (hi - lo)],
                         "low": [round(float(v), 3) for v in lo], "levels": len(levels), "textured": textured, "triangles": counts})
        print("%-16s %s" % (name, counts))
    # (The other sets' parts stay in the list as they are.)
    listed = OUT / "manifest.json"
    names = {m["name"] for m in manifest}
    if listed.exists():
        manifest = [m for m in json.loads(listed.read_text()) if m["name"] not in names] + manifest
    listed.write_text(json.dumps(manifest, indent=1) + "\n")


def write(path, name, parts, level, materials, images, textures):
    chunks, views, accessors, prims = [], [], [], []
    at = 0

    def put(arr, target=None, kind=5126, typ="VEC3", bounds=False):
        nonlocal at
        raw = np.ascontiguousarray(arr).tobytes()
        raw += b"\0" * ((4 - len(raw) % 4) % 4)
        v = {"buffer": 0, "byteOffset": at, "byteLength": len(raw)}
        if target:
            v["target"] = target
        views.append(v)
        a = {"bufferView": len(views) - 1, "componentType": kind, "count": len(arr), "type": typ}
        if bounds:
            a["min"] = [float(x) for x in arr.min(axis=0)]
            a["max"] = [float(x) for x in arr.max(axis=0)]
        accessors.append(a)
        chunks.append(raw)
        at += len(raw)
        return len(accessors) - 1

    for p, idx in zip(parts, level):
        used, back = np.unique(idx, return_inverse=True)       # only the vertices this level still joins up
        small = len(used) < 65536
        attributes = {"POSITION": put(p["pos"][used], 34962, bounds=True), "NORMAL": put(p["nrm"][used], 34962)}
        if "uv" in p:
            attributes["TEXCOORD_0"] = put(p["uv"][used], 34962, typ="VEC2")
        if "col" in p:
            attributes["COLOR_0"] = put(p["col"][used], 34962)
        prims.append({"attributes": attributes,
                      "indices": put(back.astype(np.uint16 if small else np.uint32), 34963, 5123 if small else 5125, "SCALAR"),
                      "material": p["mat"]})
    blob = b"".join(chunks)
    doc = {"asset": {"version": "2.0", "generator": "tools/build_power_kit.py"}, "scene": 0, "scenes": [{"nodes": [0]}],
           "nodes": [{"name": name, "mesh": 0}], "meshes": [{"name": name, "primitives": prims}],
           "materials": materials, "textures": textures, "images": images, "samplers": [{}],
           "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors}
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    with open(path, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<I", len(js)) + b"JSON" + js)
        f.write(struct.pack("<I", len(blob)) + b"BIN\0" + blob)


if __name__ == "__main__":
    main(sys.argv[1])
