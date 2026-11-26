# GaiaSphere Demo

A procedural floating island with rivers, creeks, waterfalls and a dark mere,
built by **GaiaSphere**, the terrain world system (the `GaiaSphere` node,
`scripts/world/SCRIPT_gaiasphere.gd`, and the field, mesher and bake behind it).
This demo is a standalone example of that terrain engine and a water engine, lifted out of a
larger game with everything that was the game left behind. There is no title
screen, no menu and no HUD. It starts, builds the island, and puts you on it.

Made with Godot 4.7-dev5, on the Mobile renderer.

## Running it

Download the build for your machine from the repository's Releases page, unzip
it and run the one file in it (`GaiaSphereDemo.exe` on Windows,
`GaiaSphereDemo.x86_64` on Linux). Nothing is installed.

The first launch spends a while on a black screen that says `building the
island`: the terrain is generated when the program starts, not shipped. It is
built again on every launch.

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
| Flashlight | L or V | d-pad up |
| Take the sword, swing it | left mouse or E | right trigger or X |
| Charge the sword (release to throw a crescent) | hold right mouse | hold left trigger |
| Hotbar slot | 1 - 9 | |
| Bag | Tab or I | Start |
| Graphics menu (draw distances, LOD, grass, shadows, effects) | O or F10 | |
| Time and environment panel (hour, day length, moon, weather, fog, grade) | P or F8 | |
| Options panel (god mode, rock strata, cliffs, ambient occlusion, far terrain) | F9 or K | |
| Back to the start | R | Back |
| Free the mouse | Esc (click to take it again) | |
| Full screen | F11 | |

Swing the sword at a tree and it takes a bite; a few bites (one charged
crescent) and the tree bursts into logs. Walk up to the logs to gather them. Three bars sit over the hotbar: health, hunger and stamina. Running, jumping and
swinging spend stamina; getting it back spends food; and the hungrier you are
the less stamina you have and the slower it returns. A long fall costs health,
and so does an empty stomach; fed, it mends. At nothing (or under the cloud sea)
you are put back at the start with what you were carrying. Select the berries in the hotbar and
click to eat one.

A plank hut stands a few steps from where you start. Face its door and press
the use button (left mouse, E, the big touch button) to open or shut it.

Hit a berry bush (the ones hung with red) and it is stripped bare in a cloud of
leaves, and its berries go in the bag. The bag
holds what you gather: left click moves a stack, right click splits it. There
is nothing to craft yet.

A truck on one wheel waits up on the hill by the first herd of cows. Face it and
press the use button to get in; the view goes behind it. Forward and back drive
and brake (and reverse), left and right steer, Space (A, JUMP) kicks the strut
and jumps it, Shift (RUN) gives it more power, L lights the headlights, the
mouse or right stick swings the view round, and the use button again gets you
out. Two gyroscopes keep it upright: it leans into turns like a bike, tips
forward under power and back under braking, and lands level. When nobody is in
it, it rolls to a stop and stays put (`scripts/world/SCRIPT_uni_truck.gd`,
`assets/truck/`).

Walk into the water and you wade, then swim; hold down to go under. Flying has
no collision and its speed runs from a crawl to crossing the island in seconds.

## What is in it

The island is not a model. `data/ISLANDFIELD_forest_003_r2.tres` is a few
hundred numbers, and the ground, the rivers and where everything grows are
generated from them at start-up. It runs on Godot's Mobile renderer and
everything on screen is lit by one sun (or moon) and the sky.

**Sky, light and weather** (`scripts/world/SCRIPT_enviro.gd`)

One node owns the time of day, the sun and moon and the shadowed light they
share, the atmosphere, raymarched volumetric clouds, fog, rain, lightning, god
rays, wind and wetness, and publishes them as `enviro_*` shader globals that
every other shader reads. It is held at golden hour in fog (`hour`, `advance`,
`weather`). While playing: `T` / `G` move the time, `F1`-`F7` pick a weather
(golden fog, clear, cloudy, overcast, foggy, rain, storm). `quality` (0-2)
scales cloud steps, god-ray samples and shadow reach.

- `shaders/SHADER_enviro_sky.gdshader`: sky, sun, moon with a phase, stars, clouds.
- `shaders/SHADER_god_rays.gdshader`: light shafts, a screen pass.
- `scripts/world/SCRIPT_fog_patches.gd`, `shaders/SHADER_fog_patch.gdshader`:
  drifting banks of fog among the trees.
- `scripts/world/SCRIPT_cloud_sea.gd`, `shaders/SHADER_cloud_sea.gdshader`: the
  cloud deck the island floats over, lit by the same light and banked against
  the island's wall.

**Terrain**

- `scripts/world/SCRIPT_island_field.gd`, `SCRIPT_flow_terrain.gd`,
  `SCRIPT_chunk_mesher.gd`, `SCRIPT_gaiasphere.gd`: the height field, the
  rivers and mere, the mesher, and the streamer that draws chunks at five
  levels of detail. Unchanged from the original project.
- `shaders/SHADER_terrain.gdshader`, `materials/MAT_terrain.tres`: the lit
  ground, blended from Poly Haven scans (`textures/polyhaven/`, CC0).
- `scripts/world/SCRIPT_cliff_dressing.gd`: rock masses (`assets/cliff`) that
  can be set into the island's edge. Not in the scene at present: add a
  `CliffDressing` node with this script to bring them back.
  `shaders/SHADER_boulder.gdshader` and `SHADERINC_top_moss.gdshaderinc` are
  the boulders' rock and its moss.

**Everything that grows** (`scripts/world/SCRIPT_flora.gd`)

Firs, ferns, boulders and grass (`assets/fir`, `fern`, `boulder`, `grass`),
instanced per tile, with the level of detail stepping down by distance: three
meshes, then for trees crossed-plane impostors and billboards out to the far
shore. Grass thins with distance and then dissolves. `quality` and `density`
scale it. Each asset folder has its own README and is rebuilt by a script in
`tools/`. The sword in the stone (`assets/sword_in_stone`,
`SCRIPT_sword_stone.gd`) stands on the islet in the mere.

**Water**

- `scripts/world/SCRIPT_river_water.gd`: one mesh for the rivers and the mere.
- `shaders/SHADER_water.gdshader`, `materials/MAT_water.tres`: the lit surface:
  sky reflection, refraction, depth colour, foam.
- `scripts/world/SCRIPT_underwater_view.gd`, `shaders/SHADER_underwater.gdshader`:
  the view from below the surface, unchanged from the original project.

**Checking it without playing**

    godot --path . --script res://tests/RENDER_tour.gd -- --out=/some/folder [--hour=17.3] [--weather=storm]
    godot --path . --script res://tests/RENDER_plants.gd -- --out=/some/folder
    godot --path . --script res://tests/RENDER_boulders.gd -- --out=/some/folder

After adding textures from the command line, run `tools/set_texture_imports.py`
(it explains why).

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
and deep, the mere's size. The water's look is `materials/MAT_water.tres`; the
light and weather are the exports of the `Enviro` node in the scene.
