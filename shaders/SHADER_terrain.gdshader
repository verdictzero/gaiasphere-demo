// THE GROUND: a lit, physically shaded blend of scanned surfaces. The mesher
// (SCRIPT_chunk_mesher.gd) writes what the ground is made of into each vertex:
//
//   COLOR   r moss and grass, g soil, b rock, a sand
//   UV2.x   +forest litter   or   -river band (1 at the middle of the bed)
//   UV2.y   +trail
//   UV.y    the river's code; kind 2 is the mere, whose shores are beaches
//
// There are no texture coordinates: every layer is laid from above in world
// metres, and rock, which lives on the steep faces, from three sides.
shader_type spatial;
render_mode cull_disabled;

// EVERY SURFACE IN TWO TEXTURE ARRAYS (tools/build_ground_arrays.py): colour and
// normals, one layer per surface, numbered as the L_ constants below. Two
// samplers for all of them: a sampler per picture had run past what a phone
// allows a shader.
uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
const float L_MEADOW = 0.0;
const float L_DRY = 1.0;
const float L_MOSS = 2.0;
const float L_LITTER = 3.0;
const float L_FLOOR = 4.0;
const float L_SOIL = 5.0;
const float L_TRAIL = 6.0;
const float L_SAND = 7.0;
const float L_BED = 8.0;
const float L_ROCK = 9.0;
const float L_SCREE = 10.0;
const float L_STONY = 11.0;
const float L_CHURN = 12.0;
const float L_COBBLE = 13.0;
// Large soft patches: breaks the tiling and varies how damp the ground looks.
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

// Metres covered by one tile of each layer.
uniform float moss_size = 3.2;
uniform float soil_size = 2.6;
uniform float litter_size = 2.8;
uniform float trail_size = 3.0;
uniform float sand_size = 2.4;
uniform float bed_size = 2.2;
uniform float rock_size = 5.0;
uniform float meadow_size = 2.4;
uniform float dry_size = 2.6;
uniform float floor_size = 3.0;
uniform float scree_size = 2.2;
uniform float stony_size = 4.0;
uniform vec3 meadow_tint : source_color = vec3(0.68, 0.95, 0.5);
// (The scan is a brown-olive that the ground's brightness turns orange: pulled
// well toward green, a paler, yellower grass than the meadow's and no more.)
uniform vec3 dry_tint : source_color = vec3(0.62, 0.95, 0.42);
// (The scan is strewn with orange leaves: taken most of the way to grey-brown,
// and darkened, so a clearing is old leaf mould and not a carpet of autumn.)
uniform vec3 floor_tint : source_color = vec3(0.4, 0.38, 0.33);
uniform vec3 scree_tint : source_color = vec3(0.62, 0.6, 0.6);
uniform vec3 stony_tint : source_color = vec3(0.85, 0.85, 0.82);
// The high ground (metres over the island's base) where rocky ground shows
// through the grass in patches, from the first height to all of it by the second.
uniform vec2 stony_heights = vec2(45.0, 95.0);
// STOCHASTIC SAMPLING: how many tiles a variant runs across before the next
// takes over (larger, slower), and on/off.
uniform float stochastic_scale = 22.0;
uniform bool stochastic = true;
uniform vec3 moss_tint : source_color = vec3(0.5, 0.66, 0.3);
uniform vec3 soil_tint : source_color = vec3(0.8, 0.78, 0.72);
uniform vec3 litter_tint : source_color = vec3(0.85, 0.8, 0.72);
uniform vec3 trail_tint : source_color = vec3(0.8, 0.76, 0.7);
uniform vec3 sand_tint : source_color = vec3(0.7, 0.68, 0.62);
uniform vec3 bed_tint : source_color = vec3(0.6, 0.62, 0.58);
// Dry sand on the mere's beaches, as a multiple of the (damp, dark) sand scan.
uniform vec3 beach_tint : source_color = vec3(1.3, 1.2, 1.0);
uniform vec3 rock_tint : source_color = vec3(0.85, 0.88, 0.86);
// The scans are dark; this lifts the whole ground.
uniform float brightness = 1.7;
// How deep (0 hard edge .. 1 plain cross-fade) the height blend between layers is.
uniform float blend_depth : hint_range(0.02, 1.0) = 0.22;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 6.0;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.45;
// Detail normals fade out by this distance: they are noise beyond it.
uniform float detail_distance = 140.0;

// The causeway across the mere: a line (xz to xz) and half its cobbled width.
uniform vec4 causeway = vec4(0.0);
uniform float causeway_half = 0.0;
// How far from its middle line the causeway's banks reach, metres.
uniform float causeway_reach = 0.0;
uniform float cobble_size = 4.4;
uniform vec3 cobble_tint : source_color = vec3(0.9, 0.9, 0.86);

// THE SHUTTLE'S SKID AND DIVOT (FlowTerrain's crash; SCRIPT_bridge.gd sets these):
// the ground it broke is churned earth, not the meadow's soil or the beach's sand.
// crash_at: the wreck's xz; crash_out: the way back up the skid; crash_shape: the
// divot's radius, the skid's length, its half-width at the wreck, and its
// touch-down share (FlowTerrain's CRASH_BOWL, CRASH_GOUGE, CRASH_WIDE, CRASH_TOUCH).
uniform vec2 crash_at = vec2(0.0);
uniform vec2 crash_out = vec2(0.0);
uniform vec4 crash_shape = vec4(0.0);
uniform float churned_size = 2.6;
uniform vec3 churned_tint : source_color = vec3(0.78, 0.7, 0.62);

uniform sampler2D caustic_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float caustic_size = 15.0;
uniform float caustic_speed = 1.0;
uniform float caustic_strength : hint_range(0.0, 4.0) = 1.5;
// The mere's surface, world metres (SCRIPT_bridge.gd sets it).
uniform float mere_level = -1000.0;

global uniform float enviro_wetness;
global uniform vec4 enviro_ambient;
global uniform vec4 enviro_light_color;

// A surface's relief, 0 (crevice) to 1 (peak), from its colour before any tint.
float height_of(vec3 c) {
	return clamp(dot(c, vec3(0.45, 0.45, 0.1)) * 2.2, 0.0, 1.0);
}

#include "res://shaders/SHADERINC_ground_lay.gdshaderinc"

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 geo_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (!FRONT_FACING) {
		geo_n = -geo_n;
	}
	vec2 p = world_pos.xz;
	float dist = length(VERTEX);
	float detail = (1.0 - smoothstep(detail_distance * 0.5, detail_distance, dist)) * normal_strength;

	vec4 w = max(COLOR, vec4(0.0));
	w /= max(w.r + w.g + w.b + w.a, 1e-4);
	float forest = clamp(UV2.x, 0.0, 1.0);
	float trail = clamp(UV2.y, 0.0, 1.0);
	float river = clamp(-UV2.x, 0.0, 1.0);
	float macro = texture(macro_noise, p / 97.0).r;
	float macro2 = texture(macro_noise, p / 23.0 + 0.31).r;

	// Moss under trees gives way to needle litter in ragged patches.
	float litter_mix = clamp(forest * (0.25 + macro2 * 1.1) * smoothstep(0.25, 0.6, macro + macro2 * 0.5), 0.0, 1.0);
	vec2 pdx = dFdx(p);
	vec2 pdy = dFdy(p);
	// ONLY WHAT CAN SHOW HERE IS SAMPLED. Each surface laid stochastically is four
	// fetches, and seven of them at every pixel was three times what the ground
	// cost before; a pixel of meadow needs the meadow, a pixel of wood the moss and
	// the litter, and so on. (Safe in a branch: every fetch is given its derivatives.)
	float wood = smoothstep(0.15, 0.6, forest);
	float dryness = smoothstep(0.56, 0.8, macro + (macro2 - 0.5) * 0.5);
	bool has_ground = w.r > 0.003;
	bool has_earth = w.g > 0.003;
	vec3 moss_a = vec3(0.2); vec3 moss_n = vec3(0.0, 0.0, 1.0);
	vec3 soil_a = vec3(0.2); vec3 soil_n = vec3(0.0, 0.0, 1.0);
	vec3 litter_a = vec3(0.2); vec3 litter_n = vec3(0.0, 0.0, 1.0);
	vec3 trail_a = vec3(0.2); vec3 trail_n = vec3(0.0, 0.0, 1.0);
	vec3 sand_a = vec3(0.2); vec3 sand_n = vec3(0.0, 0.0, 1.0);
	vec3 meadow_a = vec3(0.2); vec3 meadow_n = vec3(0.0, 0.0, 1.0);
	vec3 dry_a = vec3(0.2); vec3 dry_n = vec3(0.0, 0.0, 1.0);
	if (has_ground && wood > 0.0) {
		lay(L_MOSS, p / moss_size, pdx / moss_size, pdy / moss_size, moss_a, moss_n);
	}
	if (has_earth || river > 0.0) {
		lay(L_SOIL, p / soil_size, pdx / soil_size, pdy / soil_size, soil_a, soil_n);
	}
	if (forest > 0.003 && (has_ground || has_earth)) {
		lay(L_LITTER, p / litter_size, pdx / litter_size, pdy / litter_size, litter_a, litter_n);
	}
	if (trail > 0.003 && has_earth) {
		lay(L_TRAIL, p / trail_size, pdx / trail_size, pdy / trail_size, trail_a, trail_n);
	}
	if (w.a > 0.003 || river > 0.0) {
		lay(L_SAND, p / sand_size, pdx / sand_size, pdy / sand_size, sand_a, sand_n);
	}
	if (has_ground && wood < 1.0 && dryness < 1.0) {
		lay(L_MEADOW, p / meadow_size, pdx / meadow_size, pdy / meadow_size, meadow_a, meadow_n);
	}
	if (has_ground && wood < 1.0 && dryness > 0.0) {
		lay(L_DRY, p / dry_size, pdx / dry_size, pdy / dry_size, dry_a, dry_n);
	}
	moss_a *= moss_tint;
	soil_a *= soil_tint;
	litter_a *= litter_tint;
	trail_a *= trail_tint;
	sand_a *= sand_tint;

	// OPEN GROUND IS MEADOW: lush grass, giving way in broad patches to dry; under
	// the trees, the wood's moss and its litter, as before.
	vec3 grass_a = mix(meadow_a * meadow_tint, dry_a * dry_tint, dryness);
	vec3 grass_n = mix(meadow_n, dry_n, dryness);
	vec3 ground_a = mix(grass_a, mix(moss_a, litter_a, litter_mix * 0.8), wood);
	vec3 ground_n = mix(grass_n, mix(moss_n, litter_n, litter_mix * 0.8), wood);
	// CLEARINGS in the wood: leaf-strewn floor, in patches of their own.
	float clearing = wood > 0.0 ? wood_clearing(p) * wood : 0.0;
	if (clearing > 0.0) {
		vec3 fl_a; vec3 fl_n;
		lay(L_FLOOR, p / floor_size, pdx / floor_size, pdy / floor_size, fl_a, fl_n);
		fl_a = mix(vec3(dot(fl_a, vec3(0.3, 0.55, 0.15))), fl_a, 0.4);
		ground_a = mix(ground_a, fl_a * floor_tint, clearing);
		ground_n = mix(ground_n, fl_n, clearing);
	}
	vec3 earth_a = mix(mix(soil_a, litter_a, forest), trail_a, trail);
	vec3 earth_n = mix(mix(soil_n, litter_n, forest), trail_n, trail);

	// Rock, from three sides, with the planes' gradients taken outside the branch.
	vec3 bw = pow(abs(geo_n), vec3(triplanar_sharpness));
	bw /= bw.x + bw.y + bw.z;
	vec3 rp = world_pos / rock_size;
	vec3 rock_a = vec3(0.0);
	vec3 rock_world_n = geo_n;
	vec2 dzy_x = dFdx(rp.zy); vec2 dzy_y = dFdy(rp.zy);
	vec2 dxz_x = dFdx(rp.xz); vec2 dxz_y = dFdy(rp.xz);
	vec2 dxy_x = dFdx(rp.xy); vec2 dxy_y = dFdy(rp.xy);
	// The riverbanks are rock too.
	float at = 3.0 * (1.0 - river);
	float bank_w = river > 0.0 ? smoothstep(0.7, 0.95, at) * (1.0 - smoothstep(1.7, 2.1, at)) : 0.0;
	float bed_w = river > 0.0 ? 1.0 - smoothstep(0.82, 1.0, at) : 0.0;
	float kind = floor((-UV.y - 1.0) / 10000.0);
	bool mere = kind > 1.5;
	if (mere) {
		bank_w = 0.0;
	}
	// THE CAUSEWAY'S SIDES, under the water, are cliff: wherever its bank stands
	// steep it is rock, not the sand of the bed stretched down a wall.
	float cw_side = 0.0;
	if (causeway_reach > 0.0) {
		vec2 cab = causeway.zw - causeway.xy;
		float ct = clamp(dot(p - causeway.xy, cab) / dot(cab, cab), 0.0, 1.0);
		float coff = length(p - causeway.xy - cab * ct);
		cw_side = (1.0 - smoothstep(0.55, 0.86, geo_n.y)) * (1.0 - smoothstep(causeway_reach, causeway_reach + 2.5, coff))
				* smoothstep(mere_level + 0.5, mere_level - 0.1, world_pos.y);
	}
	float rock_w = max(max(w.b, bank_w), cw_side);
	if (rock_w > 0.003) {
		rock_a = (textureGrad(ground_albedo, vec3(rp.zy, L_ROCK), dzy_x, dzy_y).rgb * bw.x
				+ textureGrad(ground_albedo, vec3(rp.xz, L_ROCK), dxz_x, dxz_y).rgb * bw.y
				+ textureGrad(ground_albedo, vec3(rp.xy, L_ROCK), dxy_x, dxy_y).rgb * bw.z) * rock_tint;
		vec3 tx = textureGrad(ground_normal, vec3(rp.zy, L_ROCK), dzy_x, dzy_y).xyz * 2.0 - 1.0;
		vec3 ty = textureGrad(ground_normal, vec3(rp.xz, L_ROCK), dxz_x, dxz_y).xyz * 2.0 - 1.0;
		vec3 tz = textureGrad(ground_normal, vec3(rp.xy, L_ROCK), dxy_x, dxy_y).xyz * 2.0 - 1.0;
		vec3 nx = vec3(tx.xy * detail + geo_n.zy, abs(tx.z) * geo_n.x);
		vec3 ny = vec3(ty.xy * detail + geo_n.xz, abs(ty.z) * geo_n.y);
		vec3 nz = vec3(tz.xy * detail + geo_n.xy, abs(tz.z) * geo_n.z);
		rock_world_n = normalize(nx.zyx * bw.x + ny.xzy * bw.y + nz.xyz * bw.z);
	}

	// HEIGHT-BASED BLENDING. Where two surfaces meet they do not cross-fade: the one
	// that stands higher at that texel wins, so stones poke through moss, litter
	// lies in the hollows of the soil, and every boundary takes the shape of what
	// is on either side of it. Each layer's height is read from its own colour
	// (pale = proud, dark = crevice), which is true enough of all these scans.
	vec4 hgt = vec4(height_of(ground_a / moss_tint), height_of(earth_a / soil_tint),
			height_of(rock_a / rock_tint) + 0.08, height_of(sand_a / sand_tint) - 0.05);
	vec4 lift = (w + hgt * blend_depth * 2.0) * step(vec4(0.004), w);
	float top = max(max(lift.r, lift.g), max(lift.b, lift.a)) - blend_depth;
	vec4 hw = max(lift - top, vec4(0.0));
	w = hw / max(hw.r + hw.g + hw.b + hw.a, 1e-4);
	vec3 albedo = ground_a * w.r + earth_a * w.g + rock_a * w.b + sand_a * w.a;
	vec3 flat_n = ground_n * w.r + earth_n * w.g + sand_n * w.a;
	float roughness = 0.94 * w.r + 0.9 * w.g + 0.82 * w.b + 0.88 * w.a;
	// SCREE: ground too steep for grass and not steep enough to be a wall, under
	// the walls, is broken stone.
	// (From about 30 degrees: the ramps between the levels stay grass.)
	float scree = smoothstep(0.87, 0.74, geo_n.y) * (1.0 - w.b) * (1.0 - wood * 0.6);
	// THE HEIGHTS: up on the high plateaus, rocky ground shows through the grass.
	float stony = smoothstep(stony_heights.x, stony_heights.y, world_pos.y)
			* smoothstep(0.45, 0.6, macro2 + (macro - 0.5) * 0.6) * (1.0 - wood) * w.r;
	if (scree + stony > 0.003) {
		vec3 sc_a; vec3 sc_n;
		lay(L_SCREE, p / scree_size, pdx / scree_size, pdy / scree_size, sc_a, sc_n);
		vec3 st_a; vec3 st_n;
		lay(L_STONY, p / stony_size, pdx / stony_size, pdy / stony_size, st_a, st_n);
		scree = smoothstep(0.3, 0.7, scree + (height_of(sc_a) - 0.5) * 0.6);
		albedo = mix(albedo, sc_a * scree_tint, scree);
		flat_n = mix(flat_n, sc_n, scree);
		stony = smoothstep(0.35, 0.65, stony + (height_of(st_a) - 0.5) * 0.8);
		albedo = mix(albedo, st_a * stony_tint, stony);
		flat_n = mix(flat_n, st_n, stony);
		roughness = mix(roughness, 0.9, max(scree, stony));
	}

	// The river: pebbles on the bed, rock on the banks, silt above them.
	float damp = 0.0;
	vec3 caustic = vec3(0.0);
	float detail_fade = 1.0 - smoothstep(detail_distance, detail_distance * 2.5, dist);
	if (river > 0.0) {
		vec3 bed_a; vec3 bed_nn;
		lay(L_BED, p / bed_size, pdx / bed_size, pdy / bed_size, bed_a, bed_nn);
		bed_a *= bed_tint;
		// Under the mere's surface, by height: the causeway stands in the middle of
		// the band and is dry.
		float under = 1.0;
		if (mere) {
			bed_a = mix(sand_a, bed_a, 0.35);
			under = smoothstep(mere_level + 0.12, mere_level - 0.3, world_pos.y);
			bed_w *= under;
		}
		float scour_w = smoothstep(1.7, 2.1, at) * (1.0 - smoothstep(2.5, 2.95, at)) * (1.0 - w.b);
		if (mere) {
			// THE MERE'S SHORES ARE SAND: pale and dry up the beach, darkening to wet
			// at the water's edge, with a ragged upper edge where the turf begins.
			float beach = smoothstep(0.0, 0.3, river + (macro2 - 0.5) * 0.12);
			float wet_line = smoothstep(mere_level + 0.7, mere_level + 0.05, world_pos.y);
			albedo = mix(albedo, sand_a * beach_tint * mix(1.0, 0.55, wet_line), beach);
			flat_n = mix(flat_n, sand_n, beach);
			roughness = mix(roughness, mix(0.9, 0.45, wet_line), beach);
			scour_w = 0.0;
		}
		albedo = mix(albedo, soil_a * 0.8, scour_w * 0.8);
		albedo = mix(albedo, rock_a, bank_w);
		albedo = mix(albedo, bed_a, bed_w);
		flat_n = mix(flat_n, bed_nn, bed_w) * (1.0 - bank_w);
		damp = clamp(bed_w + bank_w * 0.8 + scour_w * 0.6, 0.0, 1.0);
		roughness = mix(roughness, 0.55, damp);
		// CAUSTICS on the bed: the bright web that ripples throw down through clear
		// water. Two copies of a web slide over each other and only where both are
		// bright does light land, which is what makes it writhe; each colour is taken
		// a hair apart, for the fringe. It falls straight down: it does not know
		// where the sun is, only how bright the day is.
		float lit_bed = mere ? under : bed_w;
		if (lit_bed > 0.01 && caustic_strength > 0.0) {
			vec2 cp = p / caustic_size;
			float t = TIME * caustic_speed;
			vec3 web = vec3(0.0);
			for (int k = 0; k < 3; k++) {
				vec2 o = vec2(float(k) - 1.0) * 0.0015;
				// Each layer is smooth noise, warped by the other; its bright lines are
				// where it crosses its middle value: closed, wandering loops.
				float a1 = textureGrad(caustic_tex, cp + o + vec2(t * 0.031, t * 0.017), dFdx(cp), dFdy(cp)).r;
				float a2 = textureGrad(caustic_tex, cp * 1.37 - o + vec2(-t * 0.023, t * 0.029) + 0.41 + (a1 - 0.5) * 0.12,
						dFdx(cp) * 1.37, dFdy(cp) * 1.37).r;
				float l1 = pow(1.0 - abs(a1 * 2.0 - 1.0), 9.0);
				float l2 = pow(1.0 - abs(a2 * 2.0 - 1.0), 9.0);
				web[k] = l1 * 0.55 + l2 * 0.55 + l1 * l2 * 1.5;
			}
			// Sharpest in the shallows; in deep water the web blurs out and dims.
			float deep = mere ? clamp((mere_level - world_pos.y) / 14.0, 0.0, 1.0) : 0.0;
			caustic = web * caustic_strength * lit_bed * mix(1.0, 0.45, deep) * detail_fade;
		}
	}

	albedo = mix(albedo, rock_a, cw_side);
	// The web of light is thrown straight down: on a wall it would be drawn out
	// into streaks, so it thins as the ground steepens.
	caustic *= smoothstep(0.3, 0.8, geo_n.y);
	roughness = mix(roughness, 0.6, cw_side);
	float keep = 1.0 - max(max(w.b, bank_w), cw_side);
	vec3 world_n = normalize(geo_n + vec3(flat_n.x, 0.0, flat_n.y) * detail * keep);
	world_n = normalize(mix(world_n, rock_world_n, max(max(w.b, bank_w), cw_side)));

	if (causeway_half > 0.0) {
		vec2 ab = causeway.zw - causeway.xy;
		float t = clamp(dot(p - causeway.xy, ab) / dot(ab, ab), 0.0, 1.0);
		float off = length(p - causeway.xy - ab * t);
		// A ragged edge: the stones give out into the bank unevenly.
		float cw = 1.0 - smoothstep(causeway_half - 0.7, causeway_half + 0.7, off + (macro2 - 0.5) * 0.45);
		if (cw > 0.0) {
			// Laid ALONG the path: the texture's v runs down the causeway and its u
			// across, so the courses of stone follow the way you walk.
			vec2 run = normalize(ab);
			vec2 across = vec2(-run.y, run.x);
			vec2 rel = p - causeway.xy;
			vec2 cp = vec2(dot(rel, across), dot(rel, run)) / cobble_size;
			vec3 cob = textureGrad(ground_albedo, vec3(cp, L_COBBLE), dFdx(cp), dFdy(cp)).rgb;
			// The stones outlast their joints: the path ends in whole stones, not a blur.
			cw = smoothstep(0.42, 0.58, cw + (height_of(cob) - 0.5) * 0.7);
			albedo = mix(albedo, cob * cobble_tint, cw);
			vec3 cn = textureGrad(ground_normal, vec3(cp, L_COBBLE), dFdx(cp), dFdy(cp)).xyz * 2.0 - 1.0;
			vec2 tilt = across * cn.x + run * cn.y;          // the normal map, turned with it
			world_n = normalize(mix(world_n, normalize(geo_n + vec3(tilt.x, 0.0, tilt.y) * detail * 1.4), cw));
			roughness = mix(roughness, 0.8, cw);
		}
	}
	if (crash_shape.x > 0.0 && crash_out != vec2(0.0)) {
		// The same shapes FlowTerrain digs (crash_weight), reached out a little past
		// the cut onto the berms, with a ragged edge.
		vec2 d = p - crash_at;
		float far = length(d);
		float churn = 1.0 - smoothstep(crash_shape.x * 0.7, crash_shape.x * 1.25, far + (macro2 - 0.5) * 3.0);
		float along = dot(d, crash_out);
		if (along > -2.0 && along < crash_shape.y) {
			float t = clamp(along / crash_shape.y, 0.0, 1.0);
			float touch = smoothstep(1.0, 1.0 - crash_shape.w, t);
			float wide = mix(crash_shape.z, crash_shape.z * 0.6, t) * mix(0.35, 1.0, touch);
			float off = abs(dot(d, vec2(-crash_out.y, crash_out.x)) - 1.2 * sin(along * 0.16) - 2.0 * sin(along * 0.037));
			float edge = wide * 1.45 * mix(0.75, 1.15, macro2) + (macro - 0.5) * 1.5;
			churn = max(churn, (1.0 - smoothstep(edge * 0.75, edge, off)) * smoothstep(0.0, 0.25, touch + 0.05));
		}
		if (churn > 0.0) {
			vec2 mp = p / churned_size;
			vec3 mud = textureGrad(ground_albedo, vec3(mp, L_CHURN), dFdx(mp), dFdy(mp)).rgb * churned_tint;
			// Clods outlast the edge: it breaks up into lumps, not a blur.
			churn = smoothstep(0.35, 0.65, churn + (height_of(mud / churned_tint) - 0.5) * 0.8);
			// Under the water it is the bed's: only the shallows show it.
			churn *= smoothstep(mere_level - 2.5, mere_level + 0.2, world_pos.y);
			albedo = mix(albedo, mud, churn);
			vec3 mn = textureGrad(ground_normal, vec3(mp, L_CHURN), dFdx(mp), dFdy(mp)).xyz * 2.0 - 1.0;
			world_n = normalize(mix(world_n, normalize(geo_n + vec3(mn.x, 0.0, mn.y) * detail * 1.5), churn));
			roughness = mix(roughness, 0.92, churn);
			damp = max(damp, churn * 0.25);
		}
	}
	albedo *= mix(1.0, 0.62 + macro * 0.5 + macro2 * 0.26, macro_strength);
	// Wet ground is darker and shinier; rain soaks the hollows of the noise first.
	float wet = clamp(max(damp, enviro_wetness * (0.55 + macro2 * 0.9)), 0.0, 1.0);
	albedo *= mix(1.0, 0.6, wet);
	roughness = mix(roughness, 0.28, wet * 0.85);

	ALBEDO = albedo * brightness * (1.0 + caustic * 1.6);
	// Some of it as light of its own, so the web shows on a bed that is in shade.
	EMISSION = albedo * brightness * caustic * (enviro_ambient.rgb * 1.5 + enviro_light_color.rgb * 0.25);
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.4;
	NORMAL = normalize(mat3(VIEW_MATRIX) * world_n);
}
