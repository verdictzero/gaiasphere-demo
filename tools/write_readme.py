#!/usr/bin/env python3
"""Regenerate assets/fir/README.md from manifest.json:  python3 tools/write_readme.py assets/fir"""
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
rows = []
for t in json.loads((out / "manifest.json").read_text()):
    tris = " | ".join(f'{l["triangles"]:,}' for l in t["lods"])
    w, h = t.get("impostor_size_m", ["-", "-"])
    rows.append(f'| `{t["name"]}` | {t["height"]:.0f} m | {2 * t["radius"]:.1f} m | {tris} |')

(out / "README.md").write_text(f"""# Fir trees

Eight firs (four sizes, two variants each), glTF 2.0, Y-up, metres, origin at the
trunk base. Every tree has three mesh LODs and two impostor LODs.

Triangle counts per LOD:

| Tree | Height | Max width | LOD0 | LOD1 | LOD2 | LOD3 cross | LOD4 billboard |
|---|---|---|---|---|---|---|---|
{chr(10).join(rows)}

Files per tree, in `<tree>/`:

- `<tree>_lod0.gltf`, `_lod1.gltf`, `_lod2.gltf` – meshes. All three are cut from the
  same branch layout (LOD1 keeps half the side twigs, LOD2 a quarter, enlarged to hold
  the silhouette; LOD2 drops the limb geometry).
- `<tree>_lod6_cross.gltf` – a double cross: four planes 45° apart, textured with renders of LOD0
  from +Z, +X and the two diagonals.
- `<tree>_lod7_billboard.gltf` – one quad facing +Z with the +Z render. Rotate it about Y
  toward the camera in the engine; it is single-sided.

`manifest.json` lists every file with its counts and the impostor plane size.

## Materials and textures (`textures/`)

- `fir_bark` – opaque, tiling. Base colour / normal (OpenGL) / ORM, 1024².
  Source: [Poly Haven "Pine Bark"](https://polyhaven.com/a/pine_bark), CC0.
- `fir_foliage` – alpha-masked cards (cutoff 0.38), 1024×512, keyed from
  `source/fir_branch_magenta.jpg`. Single-sided on purpose: back faces are extra indices
  on the same vertices so both sides share one outward "volume" normal. Leave two-sided
  rendering off.
- `<tree>_impostor` – alpha-masked (cutoff 0.33), single-sided. `impostors/<tree>_impostor_basecolor.png`
  and `_normal.png` are 1024×1024 atlases: four views side by side (from +Z, +X and the two diagonals).
  The base colour has soft overhead lighting and self-shadowing baked in. Impostor quads
  carry up-leaning vertex normals so both planes of the cross light evenly; do not let
  the cross shadow itself.

The mesh LODs of all eight trees share the bark and foliage textures (two draw calls
per tree, batchable across trees).

Vertex data: `TEXCOORD_1` = wind (x: sway weight, 0 at the trunk base rising toward
branch tips; y: per-limb phase 0..1). `COLOR_0` on foliage = baked interior darkening.
Tangents are not stored; let the importer generate MikkTSpace.

## Rebuild

    pip install numpy pillow scipy
    python3 tools/key_magenta.py card assets/fir/source/fir_branch_magenta.jpg assets/fir/textures/fir_branch_basecolor.png --base 150,862 --tip 1870,240 --edge 0
    python3 tools/build_fir.py assets/fir
    (cd tools/impostor && npm install && node bake.js ../../assets/fir)   # needs Playwright + Chromium
    python3 tools/build_impostors.py assets/fir
    python3 tools/write_readme.py assets/fir

Sizes and variants are the `TREES` table at the top of `tools/build_fir.py`
(seed, height, trunk radius, crown start, limb length); add a row to get another tree.
""")
