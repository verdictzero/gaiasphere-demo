# fir_tall

30 m fir, glTF 2.0, Y-up, metres, origin at the trunk base.

| File | Triangles | Vertices | Use |
|---|---|---|---|
| `fir_tall_lod0.gltf` | 17,570 | 15,184 | near |
| `fir_tall_lod1.gltf` | 6,428 | 6,374 | mid |
| `fir_tall_lod2.gltf` | 1,230 | 1,216 | far |

All three share the four textures in `textures/` and two materials (two draw calls).

- `fir_bark` – opaque, tiling. Base colour / normal (OpenGL) / ORM, 1024².
  Source: [Poly Haven "Pine Bark"](https://polyhaven.com/a/pine_bark), CC0.
- `fir_foliage` – alpha-masked cards (cutoff 0.38), 1024×512, keyed from
  `source/fir_branch_magenta.jpg`. Single-sided on purpose: back faces are
  emitted as extra indices on the same vertices so both sides share one outward
  "volume" normal. Leave double-sided / two-sided lighting off.

Vertex data: `TEXCOORD_1` = wind (x: sway weight, 0 at the trunk base rising
toward branch tips; y: per-limb phase 0..1). `COLOR_0` on foliage = baked
interior darkening (multiplies base colour).

Tangents are not stored; let the importer generate MikkTSpace.

## Rebuild

    pip install numpy pillow scipy
    python3 tools/key_branch.py assets/fir_tall/source/fir_branch_magenta.jpg assets/fir_tall/textures/fir_branch_basecolor.png
    python3 tools/build_fir.py assets/fir_tall

Shape parameters (height, crown start, limb length, seed) are constants at the
top of `tools/build_fir.py`.
