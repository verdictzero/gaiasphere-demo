shader_type spatial;
render_mode cull_disabled, unshaded;

#include "res://shaders/SHADERINC_island_light.gdshaderinc"
#include "res://shaders/SHADERINC_golf_wall.gdshaderinc"
#include "res://shaders/SHADERINC_rock_atlas.gdshaderinc"
#include "res://shaders/SHADERINC_edge_falls.gdshaderinc"
#include "res://shaders/SHADERINC_buried_plates.gdshaderinc"
#include "res://shaders/SHADERINC_ember_ramp.gdshaderinc"

// NINE-SURFACE textured terrain for SCENE_test_zone_W2, from the `textures/`
// photo set plus the two crater layers baked from it.
//
// It is the same data `SHADER_terrain_flatcolor.gdshader` reads -- the four splat
// weights in COLOR, plus the grooming channels in the two UV sets -- with each of
// them resolved to a TEXTURE instead of to a flat colour:
//
//   COLOR.r  grass   base rough turf        UV.x   golf    -> mown fairway
//   COLOR.g  soil    bare earth            -UV.x   molten  -> the pool at the core
//   COLOR.b  rock    cliff and scree        UV.y   build   -> (stays soil)
//   COLOR.a  sand    bunkers               -UV.y   crater  -> charred dirt / slag
//                                           UV2.x  forest  -> needle floor
//                                          -UV2.x  divot   -> torn earth / scarp
//                                           UV2.y  path    -> worn trail
//
// THREE OF THE FOUR UV FLOATS CARRY TWO OF THEM, told apart by sign -- the
// ordinary world positive, an impact site negative. See the `crater` and `divot`
// uniform blocks, and `SCRIPT_chunk_mesher.gd` for why a sign rather than extra
// vertex channels.
//
// WHY A THIRD TERRAIN SHADER rather than a fourth material on
// `SHADER_terrain_splat.gdshader`. That one is the textured terrain for
// SCENE_test_zone_W and knows nothing about the grooming channels: it has four
// layers, no UV inputs, and its own fog band (-200 .. -320) which the W scene's
// cloud decks and palette assertions are tuned against. W2's fog is a different
// band (-170 .. -320) with a single colour, and W2 needs all seven layers. Fusing
// them would mean one shader carrying two fog models and three dead texture
// samplers for whichever scene was not using them.
//
// THE VARIANT LAYERS BORROW THEIR BASE'S NORMAL MAP. Golf turf, forest floor and
// trail are mixed into the ALBEDO of the grass and soil channels and take those
// channels' normals. Seven independent normal maps would be seven more fetches
// for a difference nobody can see: the three variants are ground at the same
// relief scale as the layer they replace, and it is the albedo the eye reads.
// This shader is at SIXTEEN texture fetches on GL Compatibility over ordinary
// ground — fifteen for the splat, plus one for the environment ball the lighting
// include samples — and NINETEEN inside the crash crater, which is one island's
// worth of one island in the world and is branched off everywhere else.
//
// THE SAMPLER BUDGET IS SPENT. Fourteen are declared below and the lighting
// include declares `env_ball` and `env_ball_night`, which is SIXTEEN against the
// sixteen texture image units GLES3 guarantees and V3D provides exactly. There is
// no seventeenth. This note used to read "fifteen ... room for one more"; that was
// a true count before the night ball landed and it is not one now, so read the
// number here as a ceiling already reached rather than as headroom.
//
// That budget is why the crater layers borrow their normals and share the
// vegetation's ember ramp instead of baking their own: a charred normal map, a
// slag normal map and a second fire palette would each have been a sampler, and
// three would have been one too many. It is also why the strata overlay is
// COMPUTED — see the `strata` uniform block, which has the rest of that argument.
//
// PROJECTIONS. Rock is full triplanar because it has to cover vertical cliffs.
// Everything else is top (XZ) projection only, which halves the fetches -- those
// surfaces only ever appear on ground flat enough that the stretching is
// invisible, because the slope rule hands steep ground to rock. The strata
// overlay is the one projection that goes the other way: SIDE planes only, no top,
// which is what confines it to faces.
//
// NEAREST FILTERING, and the 128 px bakes it goes with. `scripts/SCRIPT_crunch_art.gd`
// crunches the 512 px source art down to 128 and quantises its colours; sampling
// that bilinearly would smear it straight back into the photograph it came from.
// Mipmaps stay ON -- a tiling ground texture at a grazing angle across a 2.5 km
// island is far below one texel per pixel long before the horizon, and without
// them the whole surface crawls.
//
// UNLIT, and the light is computed here rather than by the engine. See
// `SHADERINC_island_light.gdshaderinc` for the model and for why it is indexed by the WORLD
// normal instead of the view-space one a matcap would use. The short version: the
// cloud sea, the horizon band and the sky are all world-anchored, so terrain whose
// lighting swung with the camera would be the only thing in frame that did.
//
// WHAT `unshaded` TAKES WITH IT, deliberately in the first two cases:
//
//   * ROUGHNESS / METALLIC / SPECULAR. All three are dead under `unshaded`, and
//     none is a loss — every layer already wrote ROUGHNESS 1 and METALLIC 0
//     because a specular lobe on ground that is then snapped to one of sixteen
//     palette entries does not read as sheen, it reads as a patch of the wrong
//     colour sliding around as the camera moves.
//   * THE EMISSION DANCE ROUND THE FOG. A lit shader cannot fog by darkening
//     ALBEDO, because zeroing albedo does not make a fragment unlit; it had to
//     drain ALBEDO, put the haze in EMISSION and pull SPECULAR down with it. With
//     no light term there is nothing to survive, so the fog is a straight mix
//     toward `fog_color` — which is how `SHADER_veg_billboard.gdshader` has done it since
//     it went unlit, and the two now agree by construction rather than by having
//     been tuned to the same numbers.
//   * RECEIVED SHADOWS, which IS a real loss, and one with a wider consequence than
//     this surface. Nothing left in SCENE_test_zone_W2 receives a directional
//     shadow — the vegetation, the grass, the cloud sea and the horizon band are
//     all `unshaded` already, and this shader and `cliff_wall` were the last two
//     that were not — so the light's whole shadow pass now renders into a map
//     nothing reads. `directional_shadow_max_distance` and the atlas size are still
//     tuned as if it mattered.
//     They were already faint here — ambient 1.2 against a 1.0 sun, through a
//     sixteen-level LUT — and the banded sun term replaces what they were mostly
//     doing, which is telling you which way the ground faces. If they are wanted
//     back, the move is a custom `void light()` rather than reverting: it keeps
//     LIGHT_COLOR and the shadow term while still throwing away the PBR response.
//
// SMOOTH SHADING, and a hard rim. See `flat_shading` below; the short version is
// that the mesh normals `SCRIPT_chunk_mesher.gd` emits are analytic rather than averaged
// from faces, so interpolating them is smooth by construction, and the crease at
// the coastline survives because the cliff is a separate mesh with its own
// material.

// PER-LAYER GRADE. `*_tint` is a plain vec3, NOT `source_color`: it is a LINEAR
// per-channel multiplier on the sampled albedo, so it may legitimately exceed
// 1.0. Both halves of that are load-bearing rather than pedantic.
//
// A photo set is graded to nothing. This one spans an order of magnitude in level
// (dark_rock_02 averages 0.036 linear luminance, forest_ground_01 0.246), so left
// raw the rough blew out to cream under the scene's 3.0-energy sun while the rock
// crushed to black. And matching the level alone is still not enough: the rough
// averages olive-TAN, so at the right brightness and the wrong hue the island
// rendered as a khaki dune field. Hence three numbers per layer, not one.
//
// It matters more here than it would in most scenes because `post_dither` snaps
// every pixel to one of sixteen palette entries. A colour landing between two of
// them does not blend — it jumps to whichever is nearer — so an un-graded hue does
// not read as slightly off, it reads as a different surface.
//
// The shipped values land each layer's MEAN on the flat-colour palette entry it
// replaced, measured through this project's own import pipeline; the texture keeps
// all of its own variation and only its average moves. See
// MAT_terrain_splat_w2.tres for the measurements and the two exceptions.

group_uniforms grass;
// Wild rough. `forest_ground_01` -- moss and twigs, not a lawn.
uniform sampler2D grass_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_nearest_mipmap, repeat_enable;
uniform float grass_scale = 9.0;
uniform vec3 grass_tint = vec3(1.0);
// MANY SURFACES ON THE OPEN GROUND. Off everywhere but island 004, the lava
// fields, whose open ground is six lava surfaces rather than one turf. With it
// on, `grass_albedo` is not one surface but a 3 x 2 atlas of them
// (TEX_lava_ground_atlas_576x384.png, tools/TOOL_gen_lava_textures.py): aa,
// pahoehoe and basalt plates across the top, red scoria, ash over lava and a
// young, still-live crust across the bottom. An atlas for the road's reason:
// there is no seventeenth sampler.
//
// Which surface is two slow value noises over world XZ, one choosing the column
// and one the row, `ground_variant_scale` metres to the cell, each handing over
// across a narrow band, so the ground runs in fields of one surface with short
// crossfades between: a stretch of aa, then pahoehoe, then a run of red cinder.
// Most fragments read one cell; a crossfade reads two, a corner four.
// THE GROUND ON STEEP SLOPES, TRIPLANAR. Off, the soil, the sand and the lava
// rivers' banks are projected from above, as every island's always were, and on a
// steep face they smear down it. On, each is sampled on all three planes and
// blended by the rock's own triplanar weights, so a cinder cone's flank, a levee's
// wall and a gorge's scoured bank hold their grain at any slope. Island 004's.
uniform bool ground_triplanar = false;
uniform bool ground_atlas = false;
uniform float ground_variant_scale = 140.0;
// THE LIVE CRUST. The atlas's ALPHA is heat, as the crater slag's is, and only
// the young crust carries any. It is lit through the crater's own ember ramp
// (`EMBER_RAMP`, `crack_glow`, the same cycle), so the island's seams and the
// crash site's are one fire. This scales it: 0 leaves every seam a dark red line
// in the albedo, which is the crust gone cold. A second slow noise
// (`ground_heat_scale` metres) decides which fields of young crust are still
// live and which have cooled, so the glow comes in patches, not everywhere the
// cell is drawn. The weight that reaches the light is the open ground's own,
// less whatever the burnt scrub's floor and the fairways have taken of it, so a
// seam never glows through the course.
uniform float ground_heat : hint_range(0.0, 4.0) = 0.0;
uniform float ground_heat_scale = 260.0;
// THE FIELD'S FRAME, for the three noises above. They are taken at the fragment's
// render-space XZ plus this, which is the island's origin offset, so they are
// functions of the FIELD's coordinates: a rebase moves nothing, and the CPU can
// ask the same question of the same point. `LavaSmoke` (SCRIPT_lava_smoke.gd)
// writes it, and stands its plumes on the live crust by asking `LavaGround`
// (SCRIPT_lava_ground.gd), which is these three noises in GDScript. That is also
// why they are INTEGER-hashed (`lava_hash`) and not `strata_vnoise`'s sine hash:
// a sine of a large argument comes out differently on a GPU and a CPU, and
// integer arithmetic does not, so the two agree texel for texel on which fields
// are young crust and which of them are live.
uniform vec2 ground_origin = vec2(0.0);
// THE MOLTEN MOVES. The user: "make the molten bits animated". Over the ember
// ramp's own flicker, the live seams are worked by a churn: two slow noises
// (`ground_flow_scale` metres to the cell) sliding across each other at
// `ground_flow_speed` metres a second, one with the wind and one against it.
// Where the churn runs high a surge of heat is coming through: the seams there
// SWELL (the baked heat raised to a power under 1, `melt_gamma`'s trick, down to
// `ground_flow_swell`) and BRIGHTEN; where it runs low they narrow and dim. So
// the light moves through the crack network in slow waves rather than standing
// in it, and a field of crust looks like it is breathing. `ground_flow_pulse` is
// how far the brightness swings either way; 0 stills it all. Off the CPU's
// question entirely: the smoke stands where the crust is live, not where a
// surge happens to be.
uniform float ground_flow_speed = 1.6;
uniform float ground_flow_scale = 22.0;
uniform float ground_flow_pulse : hint_range(0.0, 1.0) = 0.6;
uniform float ground_flow_swell : hint_range(0.05, 1.0) = 0.4;

group_uniforms golf;
// Mown fairway. `lawn_striped` -- the mower stripes are the point: they read as
// deliberate maintained ground from the air, which is exactly what a golf zone is.
uniform sampler2D golf_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform float golf_scale = 11.0;
uniform vec3 golf_tint = vec3(1.0);

group_uniforms soil;
// Cleared earth -- the build-pad surface, and the base the trail and the forest
// floor are mixed over. `dirt_01`.
uniform sampler2D soil_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_nearest_mipmap, repeat_enable;
uniform float soil_scale = 7.0;
uniform vec3 soil_tint = vec3(1.0);

group_uniforms forest;
// Needle litter under a canopy. `forest_ground_06`. Mixed into BOTH ground
// channels: `IslandField.forest_litter` has already moved part of the grass
// weight into soil, and the rest of the turf still wants to darken under the
// trees rather than stay open-meadow green.
uniform sampler2D forest_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform float forest_scale = 8.0;
uniform vec3 forest_tint = vec3(1.0);
// How far the grass channel darkens toward the floor under a full canopy. Under
// 1 because a wood is not bare -- there is still turf between the trees.
uniform float forest_grass_mix : hint_range(0.0, 1.0) = 0.75;

group_uniforms path;
// Worn track. `rocky_trail_02`.
uniform sampler2D path_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform float path_scale = 5.0;
uniform vec3 path_tint = vec3(1.0);
// AN OLD ROAD. Off everywhere but island 002, whose ring road is asphalt that
// has been breaking up for years. With it on, `path_albedo` is not one surface
// but six cells (TEX_desert_road_atlas_384x256.png, tools/TOOL_build_road_atlas.py):
// two asphalts in the top row, three sandy, worn-through asphalts in the bottom.
// An atlas and not five more samplers because this shader is at sixteen with the
// lighting include, the most GLES3 promises — see that tool.
//
// What it draws: asphalt down the carriageway — where the path weight (UV2.y,
// 1 on the road and falling across its bank) is above `path_core` — going over
// to sandy asphalt across `path_feather` below that, and the sandy surface then
// feathering into the open ground on the same weight the plain mode always used.
// The line between the two is pushed about by two octaves of wear noise
// (`path_wear_scale`, `path_wear`), so sand has broken through into the lanes in
// patches and runs of asphalt reach out into the shoulder; which asphalt and which
// sand is chosen by a slower noise (`path_variant_scale`), so the surface changes
// character along the road rather than tiling.
uniform bool path_atlas = false;
uniform float path_core : hint_range(0.0, 1.0) = 0.93;
uniform float path_feather : hint_range(0.01, 1.0) = 0.3;
uniform float path_wear : hint_range(0.0, 2.0) = 0.6;
uniform float path_wear_scale = 7.0;
uniform float path_variant_scale = 26.0;
// The asphalt cells' own tint, on top of `path_tint`, which tints the whole road
// sand and all. Darkening here darkens the blacktop alone, so the shoulder still
// feathers out through the sandy cells at their own colour into the desert.
uniform vec3 path_asphalt_tint = vec3(1.0);

group_uniforms rock;
// `dark_rock_02` -- fractured slabs. Full triplanar; it is the only layer that
// has to cover a vertical face.
uniform sampler2D rock_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_nearest_mipmap, repeat_enable;
uniform float rock_scale = 12.0;
uniform vec3 rock_tint = vec3(1.0);
// The blend's commitment to one projection plane — and therefore the reason the
// MESH NORMAL is a texture input here and not only a lighting one. See the same
// uniform in `SHADER_cliff_wall.gdshader`, which carries the full note: past 45 degrees
// of normal error this picks a plane lying along the surface rather than across
// it, which is a smear rather than a shading mistake.
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;
// THREE CLIFF FACES IN `rock_albedo` rather than one — island 002's sandstone and
// island 004's basalt.
// See `SHADERINC_rock_atlas.gdshaderinc`. `rock_variant_scale` is the metres per
// cell of the noise choosing between them. Keep both equal on the terrain and
// the cliff wall, or the shoulder and the wall under it draw different faces.
uniform bool rock_atlas = false;
uniform float rock_variant_scale = 90.0;

group_uniforms strata;
// SEDIMENTARY BEDS ON THE CLIFF FACES, and nothing else in this shader works at
// this scale: every layer above is a SURFACE, tiled at metres, and this is a
// LANDFORM, banded at tens of metres. It modulates the rock channel rather than
// adding a channel of its own, so it costs no vertex colour and cannot change
// what the splat classifies.
//
// OFF BY DEFAULT (`strata_strength = 0`), which is what keeps W2's ground exactly
// as it was: the whole block is inside a branch on a UNIFORM, so a material that
// does not opt in pays one scalar compare per fragment and takes no other path.
// `MAT_terrain_splat_q.tres` opts in; `MAT_terrain_splat_w2.tres` does not.
//
// THREE THINGS DEFINE IT, and they are worth separating because only the first is
// obvious:
//
//   1. SIDE PROJECTION ONLY. The triplanar weights are already computed for rock;
//      this uses `bw.x + bw.z` and DROPS `bw.y` entirely. That is the whole of
//      "cliff faces only" and it costs no uniform of its own -- the falloff is
//      `triplanar_sharpness`, the dial that is already there. Keeping the top
//      plane would draw the band stack across every flat rock top in plan view,
//      which is corduroy and not geology. It also means the gate is GEOMETRIC:
//      a plateau rim gets strata and the plateau's own tabletop does not, from
//      one term, with nothing to keep in step.
//
//   2. WORLD Y, so the beds are GLOBAL. A bed sits at one altitude everywhere in
//      the world -- two mesas 3 km apart show the same bed at the same height,
//      which is the thing that reads as a shared geological history rather than
//      as decoration applied per landform. It is also what makes the overlay free
//      of chunk and LOD state: nothing here is per-chunk, so there is no seam to
//      get wrong.
//
//   3. NO DIP TERM, and that is a floating-origin constraint rather than taste.
//      Tilted beds would make band altitude a function of X and Z -- and X and Z
//      are exactly what `SCRIPT_floating_origin.gd` rebases (Q sets
//      `horizontal_only`, so world Y here is absolute forever and the bands never
//      move). A dip would make every band in the world jump at every rebase.
//      `strata_waver` below is the same hazard bounded: it re-phases at a rebase
//      by at most its own metres, which is the re-phasing every tiling ground
//      texture in this shader already takes at the same moment.
uniform float strata_strength : hint_range(0.0, 1.0) = 0.0;
// MEAN bed thickness in metres -- mean, not fixed; see `strata_thickness_jitter`.
uniform float strata_height = 15.0;
// How far bed boundaries move off the regular stack, as a fraction of a bed.
// Equal beds are the failure mode here: a constant thickness reads as a comb, and
// worse, it gives the eye a ruler to measure the cliff against. Must stay under
// 1.0 or boundaries cross and the three-candidate lookup breaks.
uniform float strata_thickness_jitter : hint_range(0.0, 0.9) = 0.55;
// Bed-to-bed spread, as a fraction either side of neutral. 0.3 means beds run
// 0.7x to 1.3x the rock's own colour.
uniform float strata_contrast : hint_range(0.0, 1.0) = 0.3;
// THE CONTACT IS THE FEATURE. What reads as strata from a kilometre out is the
// line between two beds, not the beds. Width is in bed units; depth is how far
// the seam darkens.
uniform float strata_contact : hint_range(0.0, 0.4) = 0.12;
uniform float strata_contact_depth : hint_range(0.0, 1.0) = 0.35;
// Per-bed hue, taken off the same hash that sets its value: iron-stained at one
// end, leached and pale at the other. Both are near luminance 1 on purpose -- the
// VALUE comes from `strata_contrast`, and these only tint it. Raw multipliers, not
// `source_color`, matching `rock_tint` and the other tints in this file.
uniform vec3 strata_tint_lo = vec3(1.10, 1.00, 0.88);
uniform vec3 strata_tint_hi = vec3(0.94, 0.98, 1.06);
// Lateral waver: metres of vertical wander, over this many metres of ground. Beds
// are not spirit-levelled, and a dead-level contact across a 760 m hillside is the
// one thing that gives the whole effect away as a shader.
//
// It is ALSO the only term that can put one bed at two different altitudes in two
// places, so it is bounded by the thing it would otherwise cost. Beds measure
// 13.1 m mean, so +/- 6 m at each of two sites lets one sit 12 m out between them
// -- nearly a whole bed, at which point world Y has bought nothing. 3 measures
// +3.8 m between faces 3 km apart. See `tests/RENDER_strata_swatch.gd`.
uniform float strata_waver = 3.0;
uniform float strata_waver_scale = 260.0;
// The ledge. A contact is a notch, so it tilts the normal about the horizontal --
// this is the term that makes the band catch the light differently above and below
// the line instead of reading as a painted stripe.
uniform float strata_relief : hint_range(0.0, 2.0) = 0.5;
// The contact's own colour, a multiplier at the seam: white (the default, and
// every island's but the lava fields') leaves it the darkened rock above; island
// 004's is the red clinker between two stacked flows of basalt.
uniform vec3 strata_contact_tint = vec3(1.0);

group_uniforms sand;
// `coast_sand_02` -- gritty bunker sand.
uniform sampler2D sand_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_nearest_mipmap, repeat_enable;
uniform float sand_scale = 4.0;
uniform vec3 sand_tint = vec3(1.0);

group_uniforms crater;
// THE CRASH SITE. Two more ground layers and one emissive term, all gated on a
// single weight that is zero across the whole island but the one crater on it.
//
// THE WEIGHT RIDES IN UV.y AS A NEGATIVE NUMBER, sharing that float with the
// build-pad grooming weight, which is positive; the MOLTEN CORE rides the same
// way in UV.x, sharing with the fairway. `SCRIPT_chunk_mesher.gd`'s write site carries
// the argument for why the crater got signs rather than extra vertex channels;
// the consequence here is two `clamp`s and no new attribute. Note this shader
// already read `clamp(UV.y, 0.0, 1.0)` as `build` and then never used it
// — cleared earth IS the soil layer — so the positive half stays exactly as
// inert as it was.
//
// WHICH LAYER EACH REPLACES IS DECIDED CPU-SIDE, in `IslandField.splat_weights`,
// and this shader only resolves the choice to a texture — exactly what UV.x
// already does for the fairway and UV2.y for the trail. The field moves the
// crater's ground into SOIL where the blast dusted it and into ROCK where it
// scoured, off the LANDFORM slope, and those two arrive here as charred dirt and
// fused slag. Doing that angle rule here instead would have to work off the
// interpolated mesh normal, which inside a crater is the CRATER's normal — so
// the bowl would repaint its own walls, and the classification would swim as the
// LOD ladder changed how well the bowl was resolved. Having the good normal is
// the whole reason the splat is computed on the mesher.
uniform sampler2D char_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform float char_scale = 3.0;
uniform vec3 char_tint = vec3(1.0);
// Fused floor. ALPHA IS THE CRACK HEAT, not coverage — see
// `textures/proc/TOOL_gen_crater_textures.py`. `hint_default_black` rather than the
// white every other layer defaults to: unbound, white would paint the floor as a
// bright plate AND read alpha = 1, which is the whole crater at full glow. Black
// fails as a hole in the ground, which is at least the right shape.
uniform sampler2D slag_albedo : source_color, hint_default_black, filter_nearest_mipmap, repeat_enable;
uniform float slag_scale = 12.0;
uniform vec3 slag_tint = vec3(1.0);

// HOW HOT. Multiplies the ramp and routinely takes the result past 1.0, which is
// the point: the Environment runs `glow_enabled`, so this is the dial that
// decides whether the cracks are merely lit or actually radiating.
uniform float crack_glow : hint_range(0.0, 8.0) = 2.6;
// The palette ramp the cracks cycle through: `data/palettes/TEX_ember_ramp_ps1-soft.png`'s
// eight texels, cold coal at 0 and gold at 1 — THE SAME EIGHT the burning
// vegetation uses. Sharing it is not thrift. `SHADER_post_dither.gdshader` snaps the
// frame to a sixteen-entry LUT built from the same palette, so a second fire
// ramp would be quantised onto this one anyway and the two fires would agree
// only by accident; and when the burnt vegetation is rolled into the crater the
// embers on the stumps and the light in the ground are already the same colours.
//
// EIGHT CONSTANTS, NOT A TEXTURE AND NOT A UNIFORM. It was the PNG, eight texels
// read nearest, and that was a texture unit, of the sixteen GLES3 guarantees (and
// V3D has), which this shader and its lighting include had spent to the last; the
// buried plates round the obelisk needed one. Then it was a uniform array
// (`crack_colors`) bound in each terrain material's .tres, and on an Android
// phone that array came through UNBOUND: the cracks round the crash site drew
// white beside the crash plate's orange, which still reads the PNG. Constants
// can't come through unbound. `EMBER_RAMP` (SHADERINC_ember_ramp.gdshaderinc) is
// generated by `tools/TOOL_gen_burn_maps.py` off the same eight entries it writes
// the PNG from, already decoded to linear as the texture's sampler did, so
// nothing drawn changed; `tests/TEST_island_world.gd` holds the eight to the PNG's.
// Ramp steps per second. The wave is a triangle, so this is the round trip from
// a texel's own heat to the top of its swing and back.
uniform float crack_cycle_speed : hint_range(0.0, 12.0) = 1.1;
// How far the wave moves a texel through the ramp, as a fraction of the whole.
// 0 switches the animation off and leaves the ramp as a plain heat lookup.
uniform float crack_cycle_depth : hint_range(0.0, 1.0) = 0.42;
// How far apart in the cycle two neighbouring cracks sit — the phase scatter,
// in whole trips round the ramp across the baked heat's full range. 0 puts the
// entire network on one clock, which reads as a floor with a switch on it.
uniform float crack_cycle_scatter : hint_range(0.0, 16.0) = 3.5;

// THE MOLTEN CORE. `IslandField.crater_molten` decides how much of the floor is
// still liquid and the mesher hands it over in -UV.x; these three decide what
// that looks like.
//
// WHY A GAMMA AND NOT A MULTIPLIER, which is the only real idea in the block.
// The baked alpha is a NARROW heat core threaded down the middle of each seam —
// `TOOL_gen_crater_textures.py` sets it at 0.055 of the plate distance on purpose, so
// an ordinary crack reads as a bright line in a dark groove. A multiplier makes
// those same lines brighter and nothing else; the surface stays a cracked crust
// with a light turned up. `pow` with an exponent under 1 makes them WIDER: at
// 0.30 a texel at 0.03 goes to 0.35 and one at 0.30 goes to 0.70, so the seams
// swell until the plates between them are islands in a lit field. That is the
// difference between hot rock and molten rock, and it is one instruction.
//
// Its natural limit is the right one too. As the exponent falls the field goes
// to 1 everywhere the bake left ANY heat and stays 0 where it left none — which
// is the cooled rafts, drawn by the same Worley network as the cracks. So the
// pool that appears at the extreme is a pool with crust floating on it rather
// than a disc of light, at no extra cost and with no second mask to keep in step.
uniform float melt_gamma : hint_range(0.05, 1.0) = 0.30;
// Extra glow at the core, ON TOP of `crack_glow`. The pool is nearer the
// Environment's bloom threshold than the seams out on the floor are, which is
// most of what says it is the deep end.
uniform float melt_glow : hint_range(0.0, 6.0) = 1.6;
// How far the widened field is allowed to darken the plate it swells over, so
// the rafts read as crust ON something rather than as the surface itself. Small:
// this is a correction to the contrast the added light costs, not an effect.
uniform float melt_shade : hint_range(0.0, 1.0) = 0.35;
//
// THERE IS NO SEPARATE "WHERE IS IT HOT" THRESHOLD, and that is deliberate. The
// obvious build gives the glow its own onset on the char weight, tuned to sit
// above the lip so the rim stays cold. It is redundant: the cracks live in the
// SLAG, the slag is the rock channel, and `IslandField.splat_weights` has already
// decided — from the landform slope, in the one place the good normal exists —
// that the lip and the ash apron are not slag. Gating on the rock weight makes
// the cracks appear exactly where the fused ground is, by construction rather
// than by two numbers agreeing; a second threshold could only ever disagree with
// the first, and the way it would fail is a ring of light hanging in the air over
// unfused dirt.
//
// THE MOLTEN CORE IS NOT THAT THRESHOLD, though it is radial and it does make the
// middle hotter. It does not decide WHETHER a texel glows — the rock weight still
// does, and the core multiplies through it — only how far the seams have opened.
// Where the slag ends the core is already zero, so the two can no more disagree
// than one number can.

group_uniforms divot;
//
// THE ESCAPE POD'S DENT, which is the crash site's problem with the fire taken
// out: ground that has been TORN rather than burnt. The weight rides in UV2.x as
// a negative number, sharing that float with the forest litter, and the mesher's
// write site carries the argument for the sign and for why the divot wins the
// overlap. `IslandField.divot_scuff` has already remapped it, so what arrives is
// how torn the ground looks and not where in the dent it is.
//
// THERE IS NO SEVENTEENTH SAMPLER, AND THIS BLOCK IS WHAT THAT COSTS. The header
// counts sixteen against the sixteen texture image units GLES3 guarantees, so a
// dedicated `divot_albedo` was never available: the choice was between giving
// the dent no surface of its own and finding a channel for one. What it has
// instead is a SCUFF FIELD BAKED INTO `char_albedo`'s ALPHA — clods, drag streaks
// and grit, written by `tools/TOOL_gen_crater_textures.py` alongside the char
// itself, in the channel that plate was not using. The two features never share
// a fragment (`IslandField.divot_crater_clearance` is 420 m), so one sampler
// carrying both a crater's charred RGB and a divot's torn alpha costs nothing at
// any pixel, and the alternative — a second plate — costs a unit that does not
// exist. The slag's crack heat rides in its own alpha for exactly this reason
// one block up; this is the same trick with the same justification.
//
// EVERYTHING ELSE IS GRADED OFF LAYERS ALREADY FETCHED. `soil_a` is the churned
// earth and `rock_a` is the grit and the scarp, both already sampled for this
// fragment, so the dent costs ONE extra fetch inside its own footprint and
// nothing anywhere else.
//
// Metres per tile for the scuff field. Finer than `char_scale` (3.0) because the
// dent is 20 m long and a 3 m clod pattern would repeat six times down it and
// read as a printed texture rather than as ground.
uniform float divot_scale = 1.7;
// The grade of turned earth against the surface soil it replaces. Freshly opened
// ground is darker and warmer than the dry crust over it, and this is the whole
// of what says the dirt in the dent is not the dirt around it.
uniform vec3 divot_tint = vec3(0.82, 0.74, 0.66);
// How hard the scuff field breaks the churned ground's brightness up — clods
// catching the light, the hollows between them not. Bounded well under 1: this
// is a modulation on a surface, and at 1 the field stops being relief and starts
// being a pattern printed on the floor.
uniform float divot_break : hint_range(0.0, 1.0) = 0.45;
// How much of the ROCK layer comes up through the churned earth where the field
// is high: stones turned out of the topsoil, which is what a heavy thing dragged
// through ground actually leaves behind.
uniform float divot_grit : hint_range(0.0, 1.0) = 0.30;
// And the grade on the bank's cut face. The rock channel is already carrying it
// — `IslandField.splat_weights` hands scarped ground to rock the way it hands
// fused ground to slag — so this only says that a fresh cut is paler and drier
// than weathered cliff, which is the difference between a scarp and an outcrop.
uniform vec3 divot_scarp_tint = vec3(1.08, 1.05, 1.0);

group_uniforms flow_rivers;
// THE FLOWS' RIVERS (`FlowTerrain`, SCRIPT_flow_terrain.gd): island 004's molten
// lava and cooled, island 005's glacier ice and frozen meltwater; their levees
// (lateral moraines) and the scoured ground past them. The field has carved them
// into the ground; this draws their surfaces.
//
// THEY RIDE THE IMPACTS' HALVES, which an island with flows has neither impact to
// need: -UV.x is ACROSS (metres off the river's middle, plus
// `river_across_offset`), -UV.y is ALONG (1 plus the metres down the river,
// plus 10000 for a moving one), and -UV2.x is the BAND against the kipuka's
// litter, as the divot's scuff was: 1 down the river's middle, falling straight
// to 0 three half-widths out. So the half-widths out are `3 * (1 - band)`, and
// the channel (under one), the levees (to two) and the scour (to three) fall
// where the ground has them, in a crater lake as in a channel. With this on, the
// crater's and the divot's reads are off. SCRIPT_chunk_mesher.gd's write site has
// why the codes reach past the band.
//
// A MOVING RIVER is the slag sampler's plate (the crater's slag on island 004,
// glacier ice on 005), drawn in the river's own frame — along and across in
// metres — and moving down it: fastest down the middle, slowest at the banks
// (`river_edge_speed`), in two phases half a cycle apart and crossfaded, each
// reset when it is faded out, so the drift never shears the plate into streaks
// however long it runs. Its seams are lit through the ember ramp, opened wider
// toward the middle (`river_melt`, the crater's `melt_gamma`): `river_glow` 0
// for ice. A STILL river is the same plate stopped, in the same frame, or a
// cell of the ground atlas (`river_still_cell`: lake ice, on 005). The levees
// are a ground atlas cell (`river_levee_cell`: aa rubble, moraine scree), the
// scour past them the char sampler's. Where a trail crosses, the trail wins.
uniform bool flow_rivers = false;
uniform float river_across_offset = 100.0;
// Metres of moving river to one tile of the plate.
uniform float river_scale = 11.0;
// Metres a second down a moving river's middle, and the share of it at its banks.
uniform float river_speed = 1.6;
uniform float river_edge_speed : hint_range(0.0, 1.0) = 0.15;
// Seconds a flow phase runs before it is faded out and reset.
uniform float river_period = 8.0;
uniform float river_melt : hint_range(0.05, 1.0) = 0.3;
uniform float river_glow : hint_range(0.0, 8.0) = 2.4;
// Where up the ember ramp a moving river's heat reads, down its middle (x) and
// at its banks (y): gold in the middle, red against the banks.
uniform vec2 river_heat = vec2(0.95, 0.6);
// How far the plates are drawn out down a river, moving or stopped.
uniform float river_stretch = 1.6;
uniform vec3 river_crust_tint = vec3(1.0);
// Metres of still river to one tile of its surface, and which surface: the plate
// stopped (-1), or that cell of the ground atlas.
uniform float river_still_scale = 9.0;
uniform vec3 river_still_tint = vec3(1.0);
uniform int river_still_cell = -1;
// The ground atlas cell the levees are.
uniform int river_levee_cell = 0;
uniform vec3 river_levee_tint = vec3(1.0);
uniform vec3 river_scour_tint = vec3(1.0);
// THE RIVERS AS WATER (island 006's; the user: "spline based rivers with sandy
// bottoms and rocky edges, and beautiful but still retro looking water
// shaders"). The water is a surface of its own over the channel (`RiverWater`,
// SHADER_river_water.gdshader), so here the river's ground is what lies under
// and beside it, in half-widths off its middle:
//   * THE BED, to the shore (one half-width): the sand channel's own sand,
//     wet (`river_bed_tint`), and over it the sun's CAUSTICS, a web of light
//     moving in whole steps, brightest down the deep middle and gone at the
//     shore. LIGHT, ADDED after the shading as the cracks' glow is, not a tint
//     on the sand (the user: "Make caustics lower res but more additive with
//     chromatic abberation"): on a grid of its own, coarser than the ground's
//     (`river_caustic_texel`), in the sun's colour, and split into its colours
//     the way light through a ripple is: the red web, the green and the blue
//     each drawn `river_caustic_aberration` cells apart along the sun's way;
//   * THE ROCKY EDGES, from just inside the shore to about two half-widths:
//     the slag sampler's plate, which a water river has no crust to need,
//     holding the banks' rocks, projected on the world (triplanar) at
//     `river_scale`, steep or not;
//   * past them the scour, the char sampler's silt, as ever.
// The lagoon at island 006's middle is drawn the same way, its codes written as a
// river's 10 m to a half-width out from its shores (`FlowTerrain.KIND_LAGOON`),
// except that its shores are beaches: sand where a river's are rocks and silt.
uniform bool river_water_mesh = false;
uniform vec3 river_bed_tint = vec3(1.0);
// The caustics' light, added: the share of the sun's colour a bright strand
// adds (0, none).
uniform float river_caustics : hint_range(0.0, 2.0) = 0.0;
// Metres to a cell of the caustic web, and how fast it drifts (cells a second).
uniform float river_caustic_scale = 2.5;
uniform float river_caustic_speed = 0.35;
// The steps a second it moves in, and the texels a metre it is drawn on: the
// ground's own 21.3 is pixels of the sand's size, a quarter of it pixels four
// sand texels across.
uniform float river_caustic_rate = 8.0;
uniform float river_caustic_texel = 21.333;
// How thick a strand of the web is, in the two noises' difference.
uniform float river_caustic_width : hint_range(0.01, 0.4) = 0.09;
// How many of its own cells the red and the blue webs are drawn off the green,
// either way along the sun's bearing: the chromatic split. 0, one white web.
uniform float river_caustic_aberration : hint_range(0.0, 4.0) = 0.0;

group_uniforms buried_plates;
// THE BURIED PLATES round the obelisk (the user: "Scatter these splats (terrain
// tex) around the obelisk, most dense / full carpet at obelisk, radially randomly
// feathering outward from the obelisk, shouldn't spread too far but should give
// the sense of hidden infrastructure"). A floor of maze-grooved metal panels
// (TEX_buried_plates_albedo_256, tools/TOOL_buried_plates.py) laid over the ground in a grid
// squared to the obelisk, `plates_tile` metres a tile, six panels to a tile's side:
//   * every panel down out to `plates_full` metres from the obelisk: a carpet;
//   * past that, fewer and fewer to none at `plates_reach`, each panel kept or
//     dropped WHOLE by a roll of its own against how far out its middle is, with
//     a slow noise over the scatter so it thins in tongues and patches, not in
//     rings;
//   * and the further out, the more of each kept panel the ground has drifted
//     back over (`plates_burial`), in drifts on the ground's texel grid, so the
//     last of them are corners and strips showing through the earth;
//   * all of it on the obelisk's pad, ground levelled to the bit
//     (`IslandField.safe_pad_radius`, 88 m, past the 80 m every panel's middle is
//     inside); and off any slope steeper than a gentle one, which on the pad is
//     none: a floor, not a cladding.
// `Obelisk` writes the place and turn (render space; a rebase moves the obelisk
// and it writes them again), hands over the texture, and turns it on; and off
// when it goes, since another island may draw with this same material.
//
// ONE SAMPLER. This shader and its lighting include are at the sixteen texture
// units GLES3 guarantees (and V3D has), so which panel a texel is part of rides
// in the albedo's ALPHA (255 - 8 x the panel's index), read with `texelFetch` off
// the full-size level so no mip ever blends two; the panels' rolls and middles
// are constants, SHADERINC_buried_plates.gdshaderinc, written by the same tool.
uniform bool plates_enabled = false;
uniform sampler2D plates_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform vec2 plates_center = vec2(0.0);
uniform float plates_yaw = 0.0;
uniform float plates_tile = 12.0;
uniform float plates_full = 24.0;
uniform float plates_reach = 80.0;
uniform float plates_burial : hint_range(0.0, 1.0) = 0.7;
// Metres to a cell of the noise that shapes the scatter, and of the drifts.
uniform float plates_patch = 22.0;
uniform float plates_drift = 1.6;

group_uniforms lighting;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.6;
// Cheap ambient-occlusion-ish darkening on steep ground, carried over from the
// flat-colour shader so relief still reads where the texture has little tonal
// range of its own.
uniform float slope_shade : hint_range(0.0, 1.0) = 0.18;
// FLAT (faceted) shading. Off: the per-fragment normal is the mesh's
// interpolated one, which `SCRIPT_chunk_mesher.gd` computes analytically from the
// height field rather than by averaging faces, so it is smooth and continuous
// across chunk and LOD boundaries by construction. On: the geometric FACE normal
// recovered from screen-space derivatives of world position, oriented into the
// mesh normal's hemisphere because the raw cross-product sign is not dependable.
//
// Keep this in step with `MAT_cliff_gradient.tres`. The plateau and the cliff are
// separate meshes, so the coastline between them is a hard crease either way --
// but one faceted and one smooth makes that crease read as a seam rather than as
// an edge, which is why the test asserts the pair.
uniform bool flat_shading = false;

group_uniforms island_light;
// The unlit shading model's knobs. The COLOURS are not here — they are the four
// `tod_*` globals on the bus, so a day/night cycle moves the whole island (and the
// water spray, and the rainbow arc) without touching a material. These four are the
// SHAPE of the response, which is a per-surface art choice.
//
// `MAT_cliff_wall.tres` carries the same four, and has to: the wall continues this
// surface across a shared ring in plain sight, so a different response curve either
// side of it is a seam in the shading exactly where the albedo was made seamless.
uniform float sun_bands : hint_range(0.0, 12.0) = 4.0;
uniform float sun_wrap : hint_range(0.0, 1.0) = 0.35;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.25;

group_uniforms void_fog;
// W2's own band, and NOT `SHADER_terrain_splat.gdshader`'s: one colour rather than a
// high/low pair, and a higher onset. `fog_color` is an EXACT NEUTRAL matching the
// sky's bottom colour -- a tint here loses to a tinted palette-LUT entry and
// stripes the view. See MAT_terrain_flatcolor.tres, which this is copied from.
//
// "AN EXACT NEUTRAL" IS STILL TRUE OF THE AUTHORED VALUE and is no longer true of
// what reaches the screen, because of `tod_haze_tint` below. The reasoning is
// unchanged -- the fogged distance and the empty sky behind it have to resolve to
// the SAME palette entry -- but the value they agree on is now a product, and the
// sky's `bottom_color` is the same product. See the tint's own note.
uniform bool fog_enabled = true;
uniform vec3 fog_color : source_color = vec3(0.089, 0.089, 0.089);
uniform float fog_top = -170.0;
uniform float fog_bottom = -320.0;
uniform float fog_curve : hint_range(0.25, 6.0) = 2.2;
uniform float fog_opacity_gain : hint_range(1.0, 6.0) = 1.6;
uniform float fog_distance_start : hint_range(0.0, 3000.0) = 850.0;
uniform float fog_distance_density : hint_range(0.0, 0.01) = 0.0012;
uniform float fog_distance_power : hint_range(1.0, 4.0) = 2.0;

// THE HAZE BUS: a MULTIPLIER on `fog_color`, published by
// `scripts/SCRIPT_sky_cycle_controller.gd`.
//
// The whole of SCENE_test_zone_W2 is pinned to ONE haze value -- fourteen
// materials, the Environment's fog and the sky's own `bottom_color`, all at the
// exact neutral 0.30 -- and that pin is why the cycle could never be turned on
// there: recolour the sun and the world recolours against a horizon that does not.
// Putting the haze on the bus as a tint moves all fourteen at once and, because
// the sky's bottom is written as the same `base * tint` product, moves them to a
// value they still agree on.
//
// WHITE IS THE DEFAULT everywhere -- in project.godot, and at all three phases of
// the cycle -- so a scene that has not authored a haze tint renders exactly what
// it rendered before this line existed. That is what buys the change out of
// needing a per-material enable flag. See the Haze group in the controller.
global uniform vec4 tod_haze_tint;

group_uniforms;


// Top-projected normal sample, returned as a perturbation in world XZ.
vec3 sample_top_normal(sampler2D nrm, vec2 uv) {
	vec3 t = texture(nrm, uv).xyz * 2.0 - 1.0;
	return vec3(t.x, 0.0, t.y);
}


// ---- strata ----------------------------------------------------------------
// The bed stack is COMPUTED, not sampled, and the reason is the sampler budget in
// the header: fourteen samplers here plus `env_ball` and `env_ball_night` from the
// include is sixteen of the sixteen GLES3 guarantees, so there is no seventeenth
// to bind a strata texture to. (The header's "fifteen ... room for one more" is a
// count from before the night ball landed. There is no room.)
//
// It is also the better data structure for this particular signal, which is worth
// saying because it is not obvious. A bed is a function of ALTITUDE ALONE: baked as
// a 2D tile the field measures ~950x more variance down the tile than across it,
// so a texture would spend an entire axis storing a constant, and would still
// repeat every tile-height of cliff. These three hashes do not repeat at all.

float strata_hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453123);
}


// The boundary plane ABOVE bed `i`, in stack units (1.0 = one mean bed). Jitter is
// clamped below 1.0 by the caller, which keeps this sequence monotonic in `i` --
// that is what lets the lookup test three candidate beds instead of searching.
float strata_bound(float i, float jitter) {
	return i + (strata_hash(i * 1.7 + 11.3) - 0.5) * jitter;
}


// Value noise on the horizontal plane, for the lateral waver. Two-dimensional
// because a bed wanders in map view; it is deliberately NOT a function of Y, since
// anything that made band altitude depend on X or Z would tilt the beds -- see the
// note on dip in the `strata` uniform block.
float strata_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	const vec2 k = vec2(1.0, 57.0);
	float a = strata_hash(dot(i, k));
	float b = strata_hash(dot(i + vec2(1.0, 0.0), k));
	float c = strata_hash(dot(i + vec2(0.0, 1.0), k));
	float d = strata_hash(dot(i + vec2(1.0, 1.0), k));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


// One cell of the road atlas — see `path_atlas`. `uv` is the unwrapped tiling
// coordinate and `dx`/`dy` its screen derivatives, taken by the caller in
// uniform control flow: the cell's own coordinate jumps at every tile edge, and
// a mip level chosen off that jump would draw a seam down every one.
vec3 path_cell(vec2 uv, vec2 dx, vec2 dy, int cell) {
	vec2 size = vec2(1.0 / 3.0, 0.5);
	vec2 origin = vec2(float(cell % 3), float(cell / 3)) * size;
	// Half a texel in from the cell's edge, so neither filtering nor a coarser
	// mip reaches across into the neighbour.
	vec2 inset = 0.5 / vec2(textureSize(path_albedo, 0));
	vec2 q = origin + clamp(fract(uv) * size, inset, size - inset);
	return textureGrad(path_albedo, q, dx * size, dy * size).rgb;
}

// One cell of the ground atlas — see `ground_atlas`. Gradients by hand, for
// `path_cell`'s reason. RGB is the surface, alpha its heat.
vec4 ground_cell(vec2 uv, vec2 dx, vec2 dy, int cell) {
	vec2 size = vec2(1.0 / 3.0, 0.5);
	vec2 origin = vec2(float(cell % 3), float(cell / 3)) * size;
	vec2 inset = 0.5 / vec2(textureSize(grass_albedo, 0));
	vec2 q = origin + clamp(fract(uv) * size, inset, size - inset);
	return textureGrad(grass_albedo, q, dx * size, dy * size);
}

// THE LAVA GROUND'S NOISE: value noise on an integer hash of the lattice cell, so
// `LavaGround` (SCRIPT_lava_ground.gd) computes the same numbers on the CPU — see
// `ground_origin`. `salt` makes the three noises three. Keep the constants in
// step with that script.
float lava_hash(ivec2 c, uint salt) {
	uint h = uint(c.x) * 2376446787u + uint(c.y) * 3625334849u + salt * 668265261u;
	h = (h ^ (h >> 15u)) * 1540483477u;
	h ^= h >> 13u;
	return float(h >> 8u) / 16777216.0;
}

float lava_vnoise(vec2 p, uint salt) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	ivec2 c = ivec2(i);
	float a = lava_hash(c, salt);
	float b = lava_hash(c + ivec2(1, 0), salt);
	float d = lava_hash(c + ivec2(0, 1), salt);
	float e = lava_hash(c + ivec2(1, 1), salt);
	return mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
}

// The rivers' caustic web at the middle of the caustic grid's `cell` (its cells
// `texel` a metre), `tq` cells of drift on: 1 on a strand, 0 off one.
float caustic_web(vec2 cell, float texel, float tq) {
	vec2 cp = cell / texel / max(river_caustic_scale, 1e-3);
	float n1 = lava_vnoise(cp + vec2(tq * 0.83, tq * 0.51), 7u);
	float n2 = lava_vnoise(cp * 1.37 + vec2(-tq * 0.61, tq * 0.77), 9u);
	return 1.0 - smoothstep(0.0, river_caustic_width, abs(n1 - n2));
}

// The open ground off the atlas: two slow noises choose the column and the row,
// and only the cells with any weight are read. `p` is the field's XZ.
vec4 ground_mix(vec2 p, vec2 uv, vec2 dx, vec2 dy) {
	float s = max(ground_variant_scale, 1e-4);
	float vc = lava_vnoise(p / s, 1u);
	float vr = lava_vnoise(p / (s * 0.73), 2u);
	float t1 = smoothstep(0.36, 0.46, vc);
	float t2 = smoothstep(0.54, 0.64, vc);
	vec3 cw = vec3(1.0 - t1, t1 * (1.0 - t2), t2);
	float r = smoothstep(0.44, 0.56, vr);
	vec2 rw = vec2(1.0 - r, r);
	vec4 c = vec4(0.0);
	for (int row = 0; row < 2; row++) {
		for (int col = 0; col < 3; col++) {
			float k = cw[col] * rw[row];
			if (k > 0.0) {
				c += ground_cell(uv, dx, dy, row * 3 + col) * k;
			}
		}
	}
	return c;
}

// THE EMBER LIGHT of a seam, off the shared ramp: `baked` is the texel's own
// heat (the phase is scattered on it, so neighbouring seams keep their own
// clocks), `hot` the heat to index the ramp by, `heat` the weight of the light,
// `gain` how bright. The crater's cracks and the lava field's both come here;
// see the crater block in `fragment` for the reasoning behind every line.
vec3 ember_light(float baked, float hot, float heat, float gain) {
	const int steps = EMBER_RAMP_STEPS;
	float span = float(steps - 1);
	float ph = TIME * crack_cycle_speed + baked * crack_cycle_scatter;
	float wave = abs(fract(ph) * 2.0 - 1.0) - 0.5;
	float swing = crack_cycle_depth * (0.30 + 0.70 * heat);
	float idx = clamp(hot + wave * 2.0 * swing, 0.0, 1.0);
	// Linear already: the include holds the PNG's sRGB decoded.
	vec3 hue = EMBER_RAMP[clamp(int(floor(idx * span)), 0, steps - 1)];
	return hue * heat * gain;
}

vec3 path_road(vec2 p, float path, vec2 uv, vec2 dx, vec2 dy) {
	float variant = strata_vnoise(p / max(path_variant_scale, 1e-4));
	float wear = strata_vnoise(p / max(path_wear_scale, 1e-4)) * 0.65
			+ strata_vnoise(p / max(path_wear_scale * 0.31, 1e-4) + 17.0) * 0.35;
	vec3 asphalt = mix(path_cell(uv, dx, dy, 0), path_cell(uv, dx, dy, 1),
			smoothstep(0.35, 0.65, variant)) * path_asphalt_tint;
	// The three sands crossfade on the same slow noise, the other way round, so
	// a stretch of one asphalt is not always worn through to the same sand.
	float sv = 1.0 - variant;
	vec3 sandy = mix(path_cell(uv, dx, dy, 3), path_cell(uv, dx, dy, 4),
			smoothstep(0.2, 0.45, sv));
	sandy = mix(sandy, path_cell(uv, dx, dy, 5), smoothstep(0.55, 0.8, sv));
	float intact = smoothstep(path_core - path_feather, path_core,
			path + (wear - 0.5) * path_wear);
	return mix(sandy, asphalt, intact);
}


// A roll for an integer cell (Hoskins' hash, no sine).
float plates_hash(vec2 c) {
	vec3 p3 = fract(vec3(c.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float plates_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(plates_hash(i), plates_hash(i + vec2(1.0, 0.0)), f.x),
			mix(plates_hash(i + vec2(0.0, 1.0)), plates_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// THE BURIED PLATES at render-space `xz`: how much of a panel covers it, 0 or 1,
// and its colour. See the `buried_plates` uniforms.
float buried_plates(vec2 xz, out vec3 col) {
	col = vec3(0.0);
	vec2 d = xz - plates_center;
	// Into the obelisk's own frame: the grid squared to it, a tile's middle on it.
	float cs = cos(plates_yaw);
	float sn = sin(plates_yaw);
	vec2 q = vec2(cs * d.x - sn * d.y, sn * d.x + cs * d.y);
	vec2 uv = q / max(plates_tile, 1e-3) + 0.5;
	// The mip is chosen off the unbroken `uv`, here, before anything branches: off
	// the tile's own fraction it would jump at every seam and draw the smallest mip
	// down it.
	vec2 uv_dx = dFdx(uv);
	vec2 uv_dy = dFdy(uv);
	float r = length(d);
	if (r > plates_reach + plates_tile) {
		return 0.0;
	}
	vec2 tile = floor(uv);
	vec2 f = uv - tile;
	ivec2 size = textureSize(plates_albedo, 0);
	ivec2 texel = clamp(ivec2(f * vec2(size)), ivec2(0), size - 1);
	int index = int((1.0 - texelFetch(plates_albedo, texel, 0).a) * 255.0 / 8.0 + 0.5);
	vec3 panel = PLATES_PANELS[clamp(index, 0, PLATES_PANEL_COUNT - 1)];
	// The panel's middle, in metres off the obelisk: where its fate is cast, so it
	// stands or goes whole.
	vec2 mid = (tile + panel.yz - 0.5) * plates_tile;
	float rm = length(mid);
	float roll = fract(panel.x + plates_hash(tile + 17.0));
	float thin = 1.0 - smoothstep(plates_full, plates_reach, rm);
	// Tongues and patches: the scatter's edge pushed in and out by a slow noise,
	// and none past `plates_reach` whatever it says: out there the ground leaves
	// the obelisk's pad (`IslandField.safe_pad_radius`), which is level only so far.
	thin = clamp(thin + (plates_noise(mid / max(plates_patch, 1e-3) + 3.7) - 0.5) * 0.6
			* step(plates_full, rm) * (1.0 - smoothstep(plates_reach * 0.8, plates_reach, rm)), 0.0, 1.0);
	thin *= step(rm, plates_reach);
	if (roll >= thin) {
		return 0.0;
	}
	// The ground drifted back over it, the more the further out, in drifts on the
	// ground's own texel grid.
	vec2 g = (floor(q * 21.333) + 0.5) / 21.333;
	float drift = plates_noise(g / max(plates_drift, 1e-3)) * 0.65
			+ plates_noise(g / max(plates_drift * 0.3, 1e-3) + 9.1) * 0.35;
	float buried = smoothstep(plates_full * 0.75, plates_reach, r) * plates_burial;
	if (drift < buried) {
		return 0.0;
	}
	col = textureGrad(plates_albedo, f, uv_dx, uv_dy).rgb;
	return 1.0;
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 smooth_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_normal;
	if (flat_shading) {
		vec3 fn = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
		world_normal = dot(fn, smooth_n) < 0.0 ? -fn : fn;
	} else {
		world_normal = smooth_n;
	}
	// NO FRONT_FACING FLIP. The terrain is a single-layer shell drawn
	// `cull_disabled`, and under that the engine has already turned NORMAL toward
	// the viewer on a back face before this runs (`PROBE_ruin_light_normals.gd`
	// measures it on 4.7 GLES3). The `if (!FRONT_FACING)` flip that stood here
	// turned it away again, so every back face was lit as its own front: the
	// underside of the ground, seen from below, came out sunlit.

	vec4 w = max(COLOR, vec4(0.0));
	w /= max(w.x + w.y + w.z + w.w, 1e-5);

	float golf = clamp(UV.x, 0.0, 1.0);
	float build = clamp(UV.y, 0.0, 1.0);
	float forest = clamp(UV2.x, 0.0, 1.0);
	float path = clamp(UV2.y, 0.0, 1.0);
	// The other halves of the two UV floats — see the `crater` uniform block.
	// Each side clamps the other away, so the two never see each other.
	float charred = clamp(-UV.y, 0.0, 1.0);
	float molten = clamp(-UV.x, 0.0, 1.0);
	// ...and UV2's, which is the pod's dent against the forest litter.
	float torn = clamp(-UV2.x, 0.0, 1.0);
	// On an island with flows the same halves are their rivers': see the
	// `flow_rivers` uniform block. UV2's is the band; the other two are codes.
	float river_band = 0.0;
	if (flow_rivers) {
		river_band = torn;
		torn = 0.0;
		charred = 0.0;
		molten = 0.0;
	}

	// The triplanar weights, for the rock below and for the ground layers when
	// they are triplanar too (`ground_triplanar`).
	vec3 bw = pow(abs(world_normal), vec3(triplanar_sharpness));
	bw /= max(bw.x + bw.y + bw.z, 1e-5);

	// ---- ground layers: one top projection each ---------------------------
	vec2 p = world_pos.xz;
	// The ground atlas's derivatives, in uniform control flow — see `path_cell`.
	vec2 grass_uv = p / max(grass_scale, 1e-4);
	vec3 grass_a;
	float ground_hot = 0.0;
	if (ground_atlas) {
		vec4 g = ground_mix(p + ground_origin, grass_uv, dFdx(grass_uv), dFdy(grass_uv));
		grass_a = g.rgb * grass_tint;
		ground_hot = g.a;
	} else {
		grass_a = texture(grass_albedo, grass_uv).rgb * grass_tint;
	}
	vec3 soil_a;
	vec3 sand_a;
	if (ground_triplanar) {
		float ss = max(soil_scale, 1e-4);
		soil_a = (texture(soil_albedo, world_pos.zy / ss).rgb * bw.x
				+ texture(soil_albedo, p / ss).rgb * bw.y
				+ texture(soil_albedo, world_pos.xy / ss).rgb * bw.z) * soil_tint;
		float ds = max(sand_scale, 1e-4);
		sand_a = (texture(sand_albedo, world_pos.zy / ds).rgb * bw.x
				+ texture(sand_albedo, p / ds).rgb * bw.y
				+ texture(sand_albedo, world_pos.xy / ds).rgb * bw.z) * sand_tint;
	} else {
		soil_a = texture(soil_albedo, p / max(soil_scale, 1e-4)).rgb * soil_tint;
		sand_a = texture(sand_albedo, p / max(sand_scale, 1e-4)).rgb * sand_tint;
	}
	vec3 forest_a = texture(forest_albedo, p / max(forest_scale, 1e-4)).rgb * forest_tint;

	// Forest first, grooming over the top of it: where a deliberate surface and a
	// wood would meet, the deliberate one wins. They cannot actually overlap --
	// `IslandField.forest_at` multiplies the mask out by the zone weight -- so this
	// is belt and braces rather than an assumption.
	grass_a = mix(grass_a, forest_a, forest * forest_grass_mix);
	soil_a = mix(soil_a, forest_a, forest);

	// Mown fairway lifts the grass channel; the trail takes over the soil channel.
	// Build pads need no mix at all: cleared earth IS the soil layer, which is why
	// `build` only appears in the roughness blend below.
	if (golf > 0.0) {
		vec3 golf_a = texture(golf_albedo, p / max(golf_scale, 1e-4)).rgb * golf_tint;
		grass_a = mix(grass_a, golf_a, golf);
	}
	// The road's derivatives, here in uniform control flow — see `path_cell`.
	vec2 path_uv = p / max(path_scale, 1e-4);
	vec2 path_dx = vec2(0.0);
	vec2 path_dy = vec2(0.0);
	if (path_atlas) {
		path_dx = dFdx(path_uv);
		path_dy = dFdy(path_uv);
	}
	if (path > 0.0) {
		vec3 path_a = path_atlas ? path_road(p, path, path_uv, path_dx, path_dy)
				: texture(path_albedo, path_uv).rgb;
		soil_a = mix(soil_a, path_a * path_tint, path);
	}

	// ---- rock: full triplanar, it has to cover the cliffs -----------------
	// (`bw` is up top, with the ground layers'.)
	float rs = max(rock_scale, 1e-4);
	vec3 rock_a;
	if (rock_atlas) {
		rock_a = rock_atlas_triplanar(rock_albedo, world_pos, bw, rs, rock_variant_scale)
				* rock_tint;
	} else {
		rock_a = (texture(rock_albedo, world_pos.zy / rs).rgb * bw.x
				+ texture(rock_albedo, world_pos.xz / rs).rgb * bw.y
				+ texture(rock_albedo, world_pos.xy / rs).rgb * bw.z) * rock_tint;
	}

	// ---- strata: the cliff-face overlay -----------------------------------
	// See the `strata` uniform block for what this is and why it is computed
	// rather than sampled. Two nested branches, and which one is which matters:
	// the OUTER tests a uniform, so every fragment in the draw takes the same
	// path and `fwidth` below is well defined; the INNER tests `w.z`, which is
	// not uniform, so nothing needing a screen-space derivative may sit inside
	// it. That is the whole reason `fw` is computed where it is.
	vec3 strata_n = vec3(0.0);
	if (strata_strength > 0.0) {
		float sh = max(strata_height, 1e-4);
		// Beds per pixel. The overlay DISSOLVES as this approaches one, which is
		// the analytic answer to the one thing a computed band stack has that a
		// mipmapped texture does not: past about half a bed per pixel the stack
		// is no longer resolvable and sampling it can only shimmer. It fades at
		// roughly the range the distance fog is taking it anyway.
		float fw = fwidth(world_pos.y / sh);
		// SIDE PROJECTION: bw.y, the top plane, is dropped. This is the gate.
		float side = bw.x + bw.z;
		float amount = strata_strength * side * (1.0 - smoothstep(0.25, 0.8, fw));
		// `w.z` gates the WORK here, not the blend. The strata modulate `rock_a`,
		// and the combine further down already weights that channel by `w.z`;
		// folding it into the blend as well would square it and fade the beds out
		// across exactly the ground the splat is handing to rock.
		if (amount * w.z > 0.002) {
			float waver = (strata_vnoise(world_pos.xz / max(strata_waver_scale, 1e-4)) - 0.5)
					* 2.0 * strata_waver;
			float y = (world_pos.y + waver) / sh;
			float jitter = clamp(strata_thickness_jitter, 0.0, 0.9);
			// Which bed. Every boundary moves less than half a bed off the regular
			// stack, so `y` can only belong to the bed under `floor(y)`, that one,
			// or the one over it -- three tests, no search, no loop.
			float i0 = floor(y);
			float bed = i0;
			if (y < strata_bound(i0, jitter)) {
				bed = i0 - 1.0;
			} else if (y >= strata_bound(i0 + 1.0, jitter)) {
				bed = i0 + 1.0;
			}
			float below = y - strata_bound(bed, jitter);
			float above = strata_bound(bed + 1.0, jitter) - y;
			// One hash sets both the bed's value and its hue, so a pale bed is
			// always the cool one. They are the same rock; they should not be able
			// to disagree about which rock.
			float tone = strata_hash(bed * 3.1 + 0.7);

			// The contact, widened to at least a pixel and a half so the seam
			// blurs as it recedes rather than crawling.
			float edge = max(strata_contact, fw * 1.5);
			float t = clamp(min(below, above) / edge, 0.0, 1.0);
			float s = smoothstep(0.0, 1.0, t);
			float v = 1.0 + (tone - 0.5) * 2.0 * strata_contrast;
			v *= 1.0 - strata_contact_depth * (1.0 - s);
			vec3 seam = mix(strata_contact_tint, vec3(1.0), s);
			rock_a = mix(rock_a, rock_a * mix(strata_tint_lo, strata_tint_hi, tone) * v * seam, amount);

			// THE LEDGE, and it is the seam's own gradient rather than a second
			// field: `s` is a smoothstep, so ds/dt is 6t(1-t) exactly. That peaks
			// mid-ramp and vanishes at both ends, so the normal bends into the
			// notch and comes back out flat -- no crease across the middle of a
			// bed, where nothing is happening.
			//
			// Sign: just above a contact the face is climbing back out of the
			// groove, so the surface rises along +Y and its normal tilts -Y.
			float g = below < above ? -1.0 : 1.0;
			strata_n = vec3(0.0, g * 6.0 * t * (1.0 - t) * strata_relief, 0.0)
					* amount * w.z;
		}
	}

	// ---- the pod's divot ---------------------------------------------------
	// Torn earth takes over the soil channel and the scarp grades the rock one,
	// which is the same move the crash site makes below and the trail and the
	// fairway make above. It runs BEFORE the crash site for no reason of
	// precedence — the two are 420 m apart and cannot both be non-zero — but
	// after the rock block, which does matter: the bank's cut face is the
	// steepest ground the dent has, and grading a rock colour the triplanar
	// blend has not run on yet would grade a stretched one.
	if (torn > 0.0) {
		// The scuff field, and the only fetch this feature costs. See the
		// uniform block for why it is riding in the char plate's alpha.
		float scuff = texture(char_albedo, p / max(divot_scale, 1e-4)).a;
		// Churned earth: the soil layer, regraded and broken up by the field.
		vec3 turned = soil_a * divot_tint * (1.0 - divot_break * (1.0 - scuff));
		// ...with stones turned out of it where the field is highest.
		turned = mix(turned, rock_a, divot_grit * scuff);
		soil_a = mix(soil_a, turned, torn);
		// And the cut face. Scoped by `torn` so the weathered rock a metre
		// outside the dent is untouched.
		rock_a *= mix(vec3(1.0), divot_scarp_tint, torn);
	}

	// ---- the crash site ---------------------------------------------------
	// Charred dirt takes over the soil channel and fused slag the rock channel,
	// which is the same move the trail and the fairway make on theirs. Both
	// borrow their base's normal map, for the reason in the header: they are
	// ground at the same relief scale as the layer they replace, and it is the
	// albedo the eye reads.
	//
	// After the rock block rather than before it, so the slag mixes over a rock
	// colour that has already been triplanar-blended. That matters on the bowl
	// walls, which are the steepest ground the crater has and the only part of it
	// where the top projection alone would stretch. The divot above sits
	// between the strata and this for the same reason.
	vec3 crack_light = vec3(0.0);
	if (charred > 0.0) {
		vec3 char_a = texture(char_albedo, p / max(char_scale, 1e-4)).rgb * char_tint;
		soil_a = mix(soil_a, char_a, charred);
		vec4 slag_s = texture(slag_albedo, p / max(slag_scale, 1e-4));
		rock_a = mix(rock_a, slag_s.rgb * slag_tint, charred);

		// THE GLOWING CRACKS. `slag_s.a` is the heat baked into the seams and
		// says WHERE in the texture the light is; the ROCK WEIGHT says where in
		// the world the slag is, and is the whole of the gate — see the uniform
		// block. Without it the seams would light up through the charred dirt on
		// the apron, which has no fused ground under it at all.
		float baked = clamp(slag_s.a, 0.0, 1.0);
		// AT THE CORE THE SAME NETWORK OPENS UP. See `melt_gamma`: this is the
		// whole of "more molten toward the middle", and it is deliberately one
		// field widened rather than a second effect faded in. A separate pool
		// term would have its own outline, and a second outline inside a crater
		// floor is a ring — which is the one shape a melt does not have.
		float hot = baked;
		if (molten > 0.0) {
			hot = mix(baked, pow(baked, max(melt_gamma, 0.05)), molten);
			// The plate darkens as the field swells over it, so the cooled rafts
			// stay rafts. Scoped to the GAIN rather than to `hot` itself, so a
			// texel the bake left cold — the middle of a raft — is not darkened
			// for sitting next to something that is not.
			rock_a *= 1.0 - melt_shade * molten * clamp(hot - baked, 0.0, 1.0);
		}
		float heat = hot * w.z;
		if (heat > 0.0) {
			// The ramp's length off the texture rather than off a uniform, so
			// the two cannot disagree; unbound it is 1x1 and the guard leaves
			// every lookup on the single (white) texel.
			//
			// THE PHASE IS SCATTERED PER TEXEL, NOT SWEPT ACROSS THE CRATER,
			// and that is a correction rather than a preference. The plants get
			// a band that CLIMBS because `TOOL_gen_burn_maps.py` bakes a burn ORDER
			// per texel and the phase runs against it. A crater floor has no
			// equivalent axis: the two quantities here that look radial are the
			// char weight and the rock weight, and both are pinned flat at 1
			// across the whole floor — which is exactly where the cracks are. A
			// phase gradient on either is a gradient over nothing, and what it
			// draws is the entire network flashing in unison.
			//
			// The baked heat is per texel and is not flat, so it is what keeps
			// two neighbouring cracks out of step. Same role `bm.r` plays in
			// `SHADER_veg_billboard.gdshader`'s phase, minus the climb it cannot have.
			//
			// SCATTERED ON `baked`, NOT ON `hot`, and that is the one place the
			// molten term must not reach. `pow` flattens the field as it widens
			// it — that is what widening IS — so a phase taken off the widened
			// value converges as the pool deepens, and the middle of the crater
			// would pulse in unison. The texel's own baked heat is a fixed
			// property of the texture and keeps its clock wherever it is.
			//
			// Scoped to the live seams the way the plants scope theirs to the
			// flame: a hot crack cycles hard, a cooling one only shimmers.
			//
			// Indexed by the WIDENED heat, so the pool sits further up the ramp
			// than the seams out on the floor do and reads as gold against their
			// orange — but not by `heat`, which has the rock weight folded in and
			// would recolour the whole network as the crater faded out at its
			// edge instead of dimming it.
			//
			// Quantise to a whole step BEFORE the lookup. This is the difference
			// between indexed colour flipping and a gradient sliding.
			//
			// All of the above is `ember_light`, shared with the lava field's seams.
			crack_light = ember_light(baked, hot, heat, crack_glow + melt_glow * molten);
		}
	}

	// ---- the lava field's live crust ----------------------------------------
	// See `ground_heat`. The open ground's weight, less what the scrub's floor
	// and the fairway took of the grass channel above, times the slow field of
	// which young flows are still live.
	if (ground_heat > 0.0 && ground_hot > 0.0) {
		float live = smoothstep(0.36, 0.56,
				lava_vnoise((p + ground_origin) / max(ground_heat_scale, 1e-4), 3u));
		// ...and not under a lava river's ground, which is its own.
		float open_w = w.x * (1.0 - forest * forest_grass_mix) * (1.0 - golf)
				* (1.0 - smoothstep(0.0, 0.1, river_band));
		// The churn: see `ground_flow_speed`.
		vec2 lp = p + ground_origin;
		float fs = max(ground_flow_scale, 1e-4);
		vec2 drift = vec2(0.83, 0.56) * TIME * ground_flow_speed;
		float churn = strata_vnoise((lp + drift) / fs) * 0.6
				+ strata_vnoise((lp - drift.yx * 0.7) / (fs * 0.55) + 17.0) * 0.4;
		float surge = smoothstep(0.3, 0.75, churn);
		float hot = pow(ground_hot, mix(1.0, ground_flow_swell, surge));
		float heat = hot * live * open_w * (1.0 + (surge * 2.0 - 1.0) * ground_flow_pulse);
		if (heat > 0.0) {
			crack_light += ember_light(ground_hot, hot, heat, crack_glow * ground_heat);
		}
	}

	// ---- the flows' rivers -------------------------------------------------
	// See the `flow_rivers` uniform block. The river's frame and both sets of
	// derivatives in uniform control flow, for `path_cell`'s reason: the codes
	// jump at the river's margin, where the band is nothing.
	vec3 river_col = vec3(0.0);
	float river_w = 0.0;
	vec3 caustic_light = vec3(0.0);
	if (flow_rivers) {
		float code = -UV.y - 1.0;
		float kind = floor(code / 10000.0);
		vec2 ruv = vec2(code - kind * 10000.0, -UV.x - river_across_offset);
		vec2 rdx = dFdx(ruv);
		vec2 rdy = dFdy(ruv);
		vec2 gdx = dFdx(grass_uv);
		vec2 gdy = dFdy(grass_uv);
		// The banks' side planes, for `ground_triplanar`.
		vec2 gzy = world_pos.zy / max(grass_scale, 1e-4);
		vec2 gxy = world_pos.xy / max(grass_scale, 1e-4);
		vec2 gzy_dx = dFdx(gzy);
		vec2 gzy_dy = dFdy(gzy);
		vec2 gxy_dx = dFdx(gxy);
		vec2 gxy_dy = dFdy(gxy);
		if (river_band > 0.0 && river_water_mesh) {
			float at = 3.0 * (1.0 - river_band);
			float bed_w = 1.0 - smoothstep(0.82, 1.0, at);
			float bank_w = smoothstep(0.7, 0.95, at) * (1.0 - smoothstep(1.7, 2.1, at));
			float scour_w = smoothstep(1.7, 2.1, at) * (1.0 - smoothstep(2.5, 2.95, at)) * (1.0 - w.z);
			float rsc = max(river_scale, 1e-4);
			vec3 rocks = (texture(slag_albedo, world_pos.zy / rsc).rgb * bw.x
					+ texture(slag_albedo, p / rsc).rgb * bw.y
					+ texture(slag_albedo, world_pos.xy / rsc).rgb * bw.z) * slag_tint;
			float cs = max(char_scale, 1e-4);
			vec3 silt = texture(char_albedo, p / cs).rgb * char_tint * river_scour_tint;
			vec3 bed_a = sand_a * river_bed_tint;
			// THE LAGOON (its codes' kind 2, `FlowTerrain.KIND_LAGOON`): its
			// shores are beaches, not rocks; the same coral sand, dry.
			if (kind > 1.5) {
				rocks = sand_a;
				silt = sand_a;
			}
			if (river_caustics > 0.0) {
				// A web where two drifting value noises cross: on its own grid, in
				// whole steps of time, banded hard; three times, a whole number of
				// cells apart along the sun's bearing, for the red, the green and
				// the blue.
				float ct = max(river_caustic_texel, 1e-3);
				vec2 cell = floor((p + ground_origin) * ct) + 0.5;
				vec2 bearing = tod_sun_dir.xz / max(length(tod_sun_dir.xz), 1e-3);
				vec2 split = floor(bearing * river_caustic_aberration + 0.5);
				float tq = floor(TIME * river_caustic_rate) / max(river_caustic_rate, 1e-3)
						* river_caustic_speed;
				vec3 web = vec3(caustic_web(cell + split, ct, tq),
						caustic_web(cell, ct, tq),
						caustic_web(cell - split, ct, tq));
				float under = 1.0 - smoothstep(0.55, 0.95, at);
				// The sun's light, through the water: none at night, little low.
				float sun = clamp(tod_sun_dir.y * 2.0, 0.0, 1.0);
				caustic_light = vec3(island_posterize(web.r, 3.0), island_posterize(web.g, 3.0),
						island_posterize(web.b, 3.0))
						* tod_sun_color.rgb * (river_caustics * under * sun);
			}
			river_w = bed_w + bank_w + scour_w;
			river_col = (bed_a * bed_w + rocks * bank_w + silt * scour_w) / max(river_w, 1e-4);
			caustic_light *= bed_w / max(river_w, 1e-4);
			river_w = clamp(river_w, 0.0, 1.0) * (1.0 - path);
			caustic_light *= river_w;
		} else if (river_band > 0.0) {
			float at = 3.0 * (1.0 - river_band);
			float chan = 1.0 - smoothstep(0.85, 1.05, at);
			float levee = smoothstep(0.9, 1.1, at) * (1.0 - smoothstep(1.8, 2.2, at));
			float scour = smoothstep(1.8, 2.2, at) * (1.0 - smoothstep(2.5, 2.95, at));
			// The banks: aa rubble on the levees, and past them the ground the
			// flow scoured to ash. Steep ground stays the rock the splat made it,
			// which is a gorge's walls.
			float open_bank = 1.0 - w.z;
			vec3 lev_a;
			vec3 sc_a;
			float cs = max(char_scale, 1e-4);
			if (ground_triplanar) {
				lev_a = ground_cell(gzy, gzy_dx, gzy_dy, river_levee_cell).rgb * bw.x
						+ ground_cell(grass_uv, gdx, gdy, river_levee_cell).rgb * bw.y
						+ ground_cell(gxy, gxy_dx, gxy_dy, river_levee_cell).rgb * bw.z;
				sc_a = texture(char_albedo, world_pos.zy / cs).rgb * bw.x
						+ texture(char_albedo, p / cs).rgb * bw.y
						+ texture(char_albedo, world_pos.xy / cs).rgb * bw.z;
			} else {
				lev_a = ground_cell(grass_uv, gdx, gdy, river_levee_cell).rgb;
				sc_a = texture(char_albedo, p / cs).rgb;
			}
			lev_a *= grass_tint * river_levee_tint;
			sc_a *= char_tint * river_scour_tint;
			vec3 surf;
			if (kind > 0.5) {
				float v = river_speed * mix(1.0, river_edge_speed, min(at * at, 1.0));
				float per = max(river_period, 0.1);
				float ph0 = fract(TIME / per);
				float ph1 = fract(TIME / per + 0.5);
				// The plates drawn out down the flow, as a moving crust is.
				vec2 sc = vec2(1.0 / river_stretch, 1.0) / max(river_scale, 1e-4);
				vec2 u0 = (ruv - vec2(ph0 * per * v, 0.0)) * sc;
				vec2 u1 = (ruv - vec2(ph1 * per * v, 0.0)) * sc + vec2(0.31, 0.57);
				vec4 c0 = textureGrad(slag_albedo, u0, rdx * sc, rdy * sc);
				vec4 c1 = textureGrad(slag_albedo, u1, rdx * sc, rdy * sc);
				vec4 c = mix(c1, c0, 1.0 - abs(ph0 * 2.0 - 1.0));
				float baked = clamp(c.a, 0.0, 1.0);
				// Opened toward the middle, where it runs hottest; crusted at the
				// banks, where it has cooled against them, and redder there.
				float edge = smoothstep(0.15, 1.0, at);
				float hot = pow(baked, mix(river_melt, 1.0, edge));
				surf = c.rgb * slag_tint * river_crust_tint
						* (1.0 - melt_shade * clamp(hot - baked, 0.0, 1.0));
				float heat = hot * chan * (1.0 - path);
				if (heat > 0.0) {
					crack_light += ember_light(baked, hot * mix(river_heat.x, river_heat.y, edge),
							heat, river_glow);
				}
			} else if (river_still_cell >= 0) {
				// Still, and its own surface: a cell of the ground atlas in the
				// river's frame.
				float sc = 1.0 / max(river_still_scale, 1e-4);
				surf = ground_cell(ruv * sc, rdx * sc, rdy * sc, river_still_cell).rgb * grass_tint
						* river_still_tint;
			} else {
				// Still: the same crust, stopped, drawn out down the way it ran,
				// and gone black.
				vec2 sc = vec2(1.0 / river_stretch, 1.0) / max(river_still_scale, 1e-4);
				surf = textureGrad(slag_albedo, ruv * sc + vec2(0.71, 0.13), rdx * sc, rdy * sc).rgb
						* slag_tint * river_still_tint;
			}
			float lw = levee * open_bank;
			float sw = scour * open_bank;
			river_w = chan + lw + sw;
			river_col = (surf * chan + lev_a * lw + sc_a * sw) / max(river_w, 1e-4);
			river_w = clamp(river_w, 0.0, 1.0) * (1.0 - path);
		}
	}

	// ---- normals ----------------------------------------------------------
	vec3 grass_n = sample_top_normal(grass_normal, p / max(grass_scale, 1e-4));
	vec3 soil_n = sample_top_normal(soil_normal, p / max(soil_scale, 1e-4));
	vec3 sand_n = sample_top_normal(sand_normal, p / max(sand_scale, 1e-4));
	vec3 rnx = texture(rock_normal, world_pos.zy / rs).xyz * 2.0 - 1.0;
	vec3 rny = texture(rock_normal, world_pos.xz / rs).xyz * 2.0 - 1.0;
	vec3 rnz = texture(rock_normal, world_pos.xy / rs).xyz * 2.0 - 1.0;
	// UDN-style perturbation: each projection's tangent xy drives the two world
	// axes that projection spans.
	vec3 rock_n = vec3(0.0, rnx.y, rnx.x) * bw.x
			+ vec3(rny.x, 0.0, rny.y) * bw.y
			+ vec3(rnz.x, rnz.y, 0.0) * bw.z;

	// ---- combine ----------------------------------------------------------
	vec3 albedo = grass_a * w.x + soil_a * w.y + rock_a * w.z + sand_a * w.w;
	// The flows' rivers over all four, as the ground they have taken.
	albedo = mix(albedo, river_col, river_w);
	// And where they run off the edge, the falls down the shoulder: the rock
	// darkened under them and their light with the cracks'. The wall under the
	// shoulder draws the rest of them (SHADERINC_edge_falls.gdshaderinc).
	if (flow_rivers) {
		vec4 falls = edge_fall_light(world_pos, TIME, true);
		albedo *= 1.0 - 0.7 * falls.w;
		crack_light += falls.rgb;
	}
	// `strata_n` carries its own `w.z` (see the strata block) rather than taking
	// one here: it is a modifier on the rock channel, not a fifth channel.
	vec3 npert = grass_n * w.x + soil_n * w.y + rock_n * w.z + sand_n * w.w + strata_n;
	// The buried plates round the obelisk, on the ground's own albedo, flat (their
	// bevels are in their picture), and off anything but gentle ground.
	if (plates_enabled) {
		vec3 pc;
		float plate = buried_plates(world_pos.xz, pc) * smoothstep(0.86, 0.94, world_normal.y);
		albedo = mix(albedo, pc, plate);
		npert *= 1.0 - plate;
	}

	vec3 shaded_n = normalize(world_normal + npert * normal_strength);
	float slope = clamp(1.0 - world_normal.y, 0.0, 1.0);
	albedo *= 1.0 - slope * slope_shade;

	// UNLIT: this multiply IS the lighting. `VIEW` is the fragment->camera vector in
	// view space, so INV_VIEW_MATRIX takes it to the world frame the normal is
	// already in.
	vec3 world_v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	albedo *= island_light(shaded_n, world_v, sun_bands, sun_wrap, rim_power, rim_strength);

	// THE CRACKS ARE THEIR OWN LIGHT, so they are ADDED after the shading model
	// rather than multiplied through it. A seam radiating past 1.0 is not
	// something the sun's angle should be able to dim, and on the shadowed inner
	// wall of a bowl — which is where most of them are — that difference is the
	// entire effect: multiplied, the cracks would be darkest exactly where a
	// crater is meant to look hottest.
	//
	// BEFORE the fog, which does dim them, and should: haze sits between the
	// surface and the eye, so a crash site a kilometre out goes grey with
	// everything else instead of burning a hole through the murk. That is the
	// same ordering the surface's own shading gets, one line down.
	albedo += crack_light;
	// The caustics too: light the water lets through, not the sand's own colour.
	albedo += caustic_light;

	if (fog_enabled) {
		float t = clamp((fog_top - world_pos.y) / max(fog_top - fog_bottom, 1e-3), 0.0, 1.0);
		float depth_t = clamp(pow(t, 1.0 / max(fog_curve, 0.001)) * fog_opacity_gain, 0.0, 1.0);
		float d = max(length(VERTEX) - fog_distance_start, 0.0) * fog_distance_density;
		float dist_t = 1.0 - exp(-pow(d, fog_distance_power));
		float fog = 1.0 - (1.0 - depth_t) * (1.0 - dist_t);

		// A STRAIGHT MIX, now that there is no light term to survive. This used to
		// drain ALBEDO to black, put `fog_color` in EMISSION and pull SPECULAR down
		// with it, all so that fogged geometry landed on exactly the fog colour
		// whatever the sun was doing to it. Unshaded, ALBEDO *is* the output, so the
		// mix lands on it exactly and the other two are dead. Same construction as
		// `SHADER_veg_billboard.gdshader`, which the fog constants already have to match.
		//
		// AFTER the light, deliberately: haze sits between the surface and the eye,
		// so it is not something the surface's own shading should modulate.
		albedo = mix(albedo, fog_color * tod_haze_tint.rgb, fog);
	}

	// AFTER THE FOG, AND SO AFTER EVERYTHING. The wall is a grade on the finished
	// picture, not a term in the lighting — draining before the haze would leave
	// coloured fog hanging over a grey landscape. Unshaded, so this is the pixel.
	albedo = golf_wall_drain(albedo, world_pos.xz, SCREEN_UV, TIME);

	ALBEDO = albedo;
}
