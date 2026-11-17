# Grass clumps (staged, textures only)

Three grass clumps cut out of the magenta-backed photos in `source/`, ready for
billboard-only grass. No meshes yet.

| Texture | Plant size in texels | Opaque coverage |
|---|---|---|
| `textures/grass_clump_a_basecolor.png` | 1015×1020 | 25% |
| `textures/grass_clump_b_basecolor.png` | 1016×870 | 20% |
| `textures/grass_clump_c_basecolor.png` | 1015×719 | 14% |

Each is 1024×1024 RGBA. The clump stands on the bottom edge with its root on the
vertical centre line, so a quad pivoted at bottom-centre (`uv 0.5, 1.0`) plants it on
the ground. The plant is scaled to fit, so the three do not share a texel scale: use
`content_px` in `manifest.json` to size quads consistently. Colour is despilled and
bled into the transparent area; use alpha test around 0.35-0.4.

Re-cut:

    python3 tools/key_magenta.py clump assets/grass/source/grass_clump_a_magenta.jpg assets/grass/textures/grass_clump_a_basecolor.png
