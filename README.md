# West Virginia

A procedural floating island with rivers, creeks, waterfalls and a dark mere:
a standalone example of a terrain engine and a water engine, lifted out of a
larger game with everything that was the game left behind. There is no title
screen, no menu and no HUD. It starts, builds the island, and puts you on it.

Made with Godot 4.7-dev5, on the GL Compatibility renderer.

## Running it

Download the build for your machine from the repository's Releases page, unzip
it and run the one file in it (`WestVirginia.exe` on Windows,
`WestVirginia.x86_64` on Linux). Nothing is installed.

The first launch spends a while on a black screen that says `building the
island`: the terrain is generated when the program starts, not shipped. It is
kept on disk afterwards and later launches are much quicker.

To run it from source, open the folder in Godot 4.7-dev5 and press play.

## Controls

| | Keyboard and mouse | Controller |
|---|---|---|
| Move | W A S D | left stick |
| Look | mouse | right stick |
| Jump, swim up, fly up | Space | A |
| Swim down, fly down | Ctrl or C | B |
| Run, fly fast | Shift | click the left stick |
| Fly / walk | F | Y |
| Flying speed | mouse wheel, or [ and ] | the shoulders |
| Back to the start | R | Back |
| Free the mouse | Esc (click to take it again) | |
| Full screen | F11 | |

Walk into the water and you wade, then swim; hold down to go under. Flying has
no collision and its speed runs from a crawl to crossing the island in seconds.

## What is in it

The island is not a model. `data/ISLANDFIELD_forest_003_r2.tres` is a few
hundred numbers, and everything is generated from them at start-up.

**Terrain**

- `scripts/world/SCRIPT_island_field.gd`: the height field. The island's
  outline, hills, trails, cliffs and what the ground is made of at any point,
  as a function of position, so any chunk can be built at any resolution.
- `scripts/world/SCRIPT_flow_terrain.gd`: the water's landforms. Cones and
  vents the rivers rise from, the rivers themselves as splines that run
  downhill to the coast, the beds carved for them, and the mere round the
  middle with its islet, shelf and beaches.
- `scripts/world/SCRIPT_chunk_mesher.gd`: turns a square of the field into a
  mesh, with skirts and the cliff wall under the island's edge.
- `scripts/world/SCRIPT_island_world.gd`: streams those chunks round the
  camera at five levels of detail, on worker threads, lays collision under the
  near ones, and (here) builds the whole island before the first frame.
- `scripts/autoload/AUTOLOAD_terrain_bake.gd`: keeps built chunks in memory and
  on disk, so the second launch reads them back.
- `shaders/SHADER_terrain_splat_w2.gdshader`: the ground. A texture atlas
  splatted by what the field says is there, the wet river beds and banks, and
  fog by height and distance.

**Water**

- `scripts/world/SCRIPT_river_water.gd`: one mesh for all the water, swept
  along each river's spline and round the mere, carrying its own flow
  direction and speed; answers "is there water here, and how high" for
  swimming and the underwater view, and runs rings out from whatever disturbs
  it.
- `shaders/SHADER_river_water.gdshader`: the surface. Depth colour, ripples
  that run downstream and faster on the hills, foam at the banks and rapids,
  sky and sun on it, all on the ground's texel grid and stepped in whole
  frames.
- `scripts/world/SCRIPT_edge_falls.gd`: the waterfalls where a river reaches
  the island's edge and goes over.
- `scripts/world/SCRIPT_underwater_view.gd` and
  `shaders/SHADER_underwater.gdshader`: the waterline across the lens and the
  murk below it.
- `materials/MAT_river_water_003_r2.tres`: this water's numbers. The same
  shader makes a clear tropical lagoon with different ones.

**Everything else that is on screen**

- Vegetation: `SCRIPT_veg_scatter.gd` (the trees and understory, as crossed
  cards in multimeshes, planted from the field and kept off the water) and
  `SCRIPT_grass_scatter.gd`.
- Sky: `SCRIPT_sky_cycle_controller.gd` with `data/SKYCYCLE_003_forest.tres`
  (time of day), `SCRIPT_cloud_sea.gd` (the cloud deck the island floats
  over), `SCRIPT_horizon_clouds.gd`, `SCRIPT_forest_fog.gd`.
- The look: `shaders/SHADER_post_dither.gdshader`, an ordered dither onto a
  fixed palette (`data/palettes/LUT_forest-003.png`), and over it a CRT:
  slight curvature, scanlines, chroma bleed, dot crawl, ghosting, noise and
  chromatic aberration. `crt_amount` in `project.godot` turns it off (0.0)
  and the `crt_tune_*` vectors beside it are its strengths.

**What was written for this project**

- `scenes/SCENE_west_virginia.tscn`: the one scene.
- `scripts/SCRIPT_explorer.gd`: the body you walk, swim and fly.
- `scripts/SCRIPT_loading_cover.gd`: the black screen at the start.
- `tests/RENDER_tour.gd`: runs the scene unattended and saves stills.

The engine files are as they are in the game they came from, so they still
carry hooks for things that are not here (a golf course generator, ruins, a
vehicle's wake, burning vegetation). Nothing in this project switches them on.

## Building the executables

    tools/build.sh            # both, into build/
    tools/build.sh windows
    tools/build.sh linux

It needs the Godot 4.7-dev5 editor on the path (or `GODOT=/path/to/it`) and
fetches the two export templates it wants if they are missing. Pushing to the
`release` branch builds both on GitHub and attaches them to a release named
after `config/version` in `project.godot` (`.github/workflows/build.yml`), so
a new release is: bump that number, push `main`, push `main:release`.

## Changing the island

Open `data/ISLANDFIELD_forest_003_r2.tres` in the editor. `seed` is a
different island; the `flow_*` block is the water: how many rivers, how wide
and deep, the mere's size. The water's colour and behaviour are the parameters
of `materials/MAT_river_water_003_r2.tres`.
