#!/usr/bin/env python3
"""THE GROUND'S TEXTURE ARRAYS: every surface the terrain is painted with, as two
Texture2DArrays (colour, and normals) that the terrain shader samples by layer
number. Two samplers for any number of surfaces, where a sampler per picture had
already run past what a phone gives a shader.

    python3 tools/build_ground_arrays.py
    godot --headless --path . --import

Each layer is cut down to SIDE pixels square and the layers are stacked top to
bottom in one tall picture; the .import beside it tells Godot to slice it into
that many layers. The layer ORDER is the shader's (SHADER_terrain.gdshader's
L_* constants): change one, change the other.

Sources: textures/polyhaven/ (already in the game for other things) or
textures/source/ (kept out of the game; fetched with tools/fetch_polyhaven.py).
"""
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SIDE = 1024
LAYERS = [
    "leafy_grass",            # 0  meadow
    "sparse_grass",           # 1  dry grass
    "forrest_ground_01",      # 2  forest moss
    "forest_leaves_03",       # 3  needle litter
    "forest_floor",           # 4  leaf-strewn clearing
    "mud_forest",             # 5  soil
    "forest_ground_04",       # 6  trodden earth
    "damp_sand",              # 7  sand
    "ganges_river_pebbles",   # 8  river and mere bed
    "dark_rock_02",           # 9  cliff rock
    "rocky_gravel",           # 10 scree
    "rocks_ground_05",        # 11 rocky ground on the heights
    "brown_mud_03",           # 12 churned earth (the shuttle's skid)
    "cobblestone_floor_04",   # 13 the causeway's cobbles
]

IMPORT = """[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="res://textures/terrain/{name}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=1
slices/vertical={n}
"""


def source(name, kind):
    for folder in ("textures/polyhaven", "textures/source"):
        p = ROOT / folder / ("%s_%s.jpg" % (name, kind))
        if p.exists():
            return p
    raise SystemExit("no %s for %s" % (kind, name))


def build(kind, out):
    rows = []
    for name in LAYERS:
        img = cv2.imread(str(source(name, kind)), cv2.IMREAD_COLOR)
        rows.append(cv2.resize(img, (SIDE, SIDE), interpolation=cv2.INTER_AREA))
    dst = ROOT / "textures" / "terrain" / out
    cv2.imwrite(str(dst), np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 92])
    imp = dst.with_name(dst.name + ".import")
    imp.write_text(IMPORT.format(name=out, n=len(LAYERS)))
    print(out, len(LAYERS), "layers,", dst.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    build("basecolor", "ground_albedo.jpg")
    build("normal", "ground_normal.jpg")
