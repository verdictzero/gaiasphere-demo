# Ferns

Four ferns, glTF 2.0, Y-up, metres, origin on the ground at the centre of the crown.
Each is a rosette of arching frond cards with three mesh LODs and two impostor LODs.

Triangle counts per LOD:

| Fern | Height | Width | LOD0 | LOD1 | LOD2 | LOD3 cross | LOD4 billboard |
|---|---|---|---|---|---|---|---|
| `fern_small_a` | 0.29 m | 0.82 m | 432 | 108 | 48 | 8 | 2 |
| `fern_medium_a` | 0.50 m | 1.42 m | 624 | 156 | 72 | 8 | 2 |
| `fern_medium_b` | 0.59 m | 2.02 m | 528 | 132 | 64 | 8 | 2 |
| `fern_large_a` | 0.78 m | 2.41 m | 816 | 204 | 96 | 8 | 2 |

Files per fern, in `<fern>/`: `_lod0/1/2.gltf` (meshes; LOD2 keeps two of every three
fronds, widened), `_lod3_cross.gltf` (four upright planes 45° apart) and
`_lod4_billboard.gltf` (one quad facing +Z; rotate it about Y toward the camera in the
engine, it is single-sided). `manifest.json` lists every file and the impostor plane size.

- `fern_frond` – alpha-masked (cutoff 0.4), `textures/fern_frond_basecolor.png`, 1024×512,
  keyed from `source/fern_frond_magenta.jpg`. Single-sided on purpose: back faces are
  extra indices on the same vertices. Leave two-sided rendering off. One draw call.
- `<fern>_impostor` – `textures/impostors/<fern>_impostor_basecolor.png` and `_normal.png`,
  1024×128 atlases (four views side by side: from +Z, +X and the two diagonals), cutoff 0.33.

Vertex data: `TEXCOORD_1` = wind (x: sway weight, 0 at the root to 1 at the frond tip;
y: per-frond phase). `COLOR_0` = baked darkening toward the root.

The impostors are upright planes, so they stand in for the fern seen from the side. Seen
from steeply above they lose the spread of the rosette; switch to them at distance.

## Rebuild

    python3 tools/key_magenta.py card assets/fern/source/fern_frond_magenta.jpg assets/fern/textures/fern_frond_basecolor.png --base 105,940 --tip 1910,130
    python3 tools/build_fern.py assets/fern
    (cd tools/impostor && npm install && node bake.js ../../assets/fern)   # needs Playwright + Chromium
    python3 tools/build_impostors.py assets/fern

Variants are the `FERNS` table at the top of `tools/build_fern.py`.
