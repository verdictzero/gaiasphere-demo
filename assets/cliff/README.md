# Cliff chunks

Eight big rock masses for embedding in the island's edge, glTF 2.0, Y-up, metres.

| Chunk | Width × height × depth | Use |
|---|---|---|
| `cliff_buttress_a` | 16 × 26 × 11 m | broad mass against the wall |
| `cliff_buttress_b` | 22 × 20 × 12 m | broad mass against the wall |
| `cliff_pillar_a` | 8 × 34 × 7 m | tall column, narrowing downward |
| `cliff_pillar_b` | 10 × 44 × 9 m | tall column, narrowing downward |
| `cliff_slab_a` | 14 × 22 × 5 m | thick leaning plate |
| `cliff_shelf_a` | 18 × 7 × 12 m | ledge jutting out part-way down |
| `cliff_fang_a` | 9 × 30 × 8 m | hanging spike for the underside |
| `cliff_fang_b` | 13 × 48 × 11 m | hanging spike for the underside |

Each has `_lod0` to `_lod3`: 5,120 / 1,280 / 320 / 80 triangles.

**The origin is at the top.** `y = 0` is where the chunk meets the rim (for a fang, the
underside of the island); a little stands above it and the rest hangs below
(`above_origin_m` in `manifest.json`). Place by rim height and sink it into the wall.

In the game they wear `materials/MAT_cliff_chunk.tres`: the boulder shader
(`shaders/SHADER_boulder.gdshader`) with Poly Haven "Dark Rock 02" (CC0), moss on
sky-facing faces, and large-scale light/dark variation to hide tiling.

Check them: `godot --path . --rendering-method mobile --script res://tests/RENDER_boulders.gd -- --out=/some/folder`

Rebuild: `python3 tools/build_cliff.py assets/cliff`
