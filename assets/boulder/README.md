# Boulders

Five boulder shapes, glTF 2.0, Y-up, metres, origin at ground level under the centre
(the bottom 14% is below the origin so they sit into the ground). About 2 m across;
scale instances freely.

Each has `_lod0` (1,280 triangles), `_lod1` (320) and `_lod2` (80), all cut from the
same shape function. `manifest.json` lists the files and each boulder's size.

In the game they wear `materials/MAT_boulder.tres`:

- `shaders/SHADER_boulder.gdshader` – lit rock, textured on three world-space planes,
  so scale and rotation never stretch the texture.
- `shaders/SHADERINC_top_moss.gdshaderinc` – the moss sub-shader. Moss settles on
  whatever faces the sky in world space and creeps along crevices first. Any lit
  shader can include it and call `top_moss(...)`. Its uniforms: `moss_amount`,
  `moss_sharpness`, `moss_scale`, `moss_tint`, `moss_roughness`,
  `moss_normal_strength`, `moss_softness`.

Textures are Poly Haven (CC0): "Lichen Rock" for the rock, "Forrest Ground 01" for the moss.

Check them: `godot --path . --rendering-method mobile --script res://tests/RENDER_boulders.gd -- --out=/some/folder`

Rebuild the meshes: `python3 tools/build_boulder.py assets/boulder`
