// CLIFF ROCK THAT IS THE TERRAIN'S OWN ROCK. The rock masses stood along the
// island's walls (SCRIPT_cliff_rocks.gd) and the terrain's steep ground meet
// with no seam because this draws exactly what the terrain shader draws where
// it is rock (SHADER_terrain.gdshader's rock branch): the same texture, laid on
// from three sides in WORLD space at the same size, the same tint, the same
// large soft patches over it, the same wetness and the same brightness. A rock
// pushed into a wall continues the wall's grain across the join.
//
// SCRIPT_cliff_rocks.gd copies every one of those values off the terrain's own
// material, so changing the terrain's rock changes these with it.
shader_type spatial;
render_mode cull_back;

// The terrain's own ground arrays, and the rock's layer in them.
uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_layer = 9.0;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float rock_size = 5.0;
uniform vec3 rock_tint : source_color = vec3(0.85, 0.88, 0.86);
uniform float brightness = 1.7;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.45;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 6.0;
uniform float detail_distance = 140.0;

// THE GROUND RUNS ON OVER THE ROCK'S TOP. Where a rock faces up it is drawn as the
// ground beside it is: the same surfaces, laid from above in world metres with
// the same stochastic sampling, the same tints, the same patches of dry grass
// and clearing, so the turf carries straight across from the terrain onto the
// rock. WHICH ground (meadow, wood, soil, sand) is the rock's own to say: looked
// up where it stands when it was placed (SCRIPT_cliff_rocks.gd) and carried in
// INSTANCE_CUSTOM: x the wood there (the field's forest), y z w the shares of
// ground, earth and sand. The edge of it is broken by the rock's own relief:
// turf in the cracks first.
// EDGE WEAR AND CREVICES, baked into the mesh's vertex colour
// (tools/bake_cliff_block.py) and laid over the rock's texture: COLOR.r is
// 1 - wear (the block's proud edges and corners), COLOR.g the sky a point sees
// (toward 0 down a crack). A mesh with no baked colour is white: nothing added.
// The rock's own grain breaks the worn edge up, so it is chipped, not airbrushed.
uniform float edge_wear : hint_range(0.0, 1.5) = 1.1;      // how much paler and smoother a worn edge is
uniform vec3 wear_tint : source_color = vec3(1.0, 0.97, 0.9);
uniform float crevice : hint_range(0.0, 1.0) = 0.7;         // how dark the bottom of a crack
uniform float top_start : hint_range(0.0, 1.0) = 0.62;   // how upward a face must look (normal.y) to begin to be ground
uniform float top_full : hint_range(0.0, 1.0) = 0.86;    // and to be all ground
uniform bool stochastic = true;
uniform float stochastic_scale = 22.0;
uniform float moss_size = 3.2;
uniform float soil_size = 2.6;
uniform float litter_size = 2.8;
uniform float sand_size = 2.4;
uniform float meadow_size = 2.4;
uniform float dry_size = 2.6;
uniform float floor_size = 3.0;
uniform vec3 moss_tint : source_color = vec3(0.5, 0.66, 0.3);
uniform vec3 soil_tint : source_color = vec3(0.8, 0.78, 0.72);
uniform vec3 litter_tint : source_color = vec3(0.85, 0.8, 0.72);
uniform vec3 sand_tint : source_color = vec3(0.7, 0.68, 0.62);
uniform vec3 meadow_tint : source_color = vec3(0.68, 0.95, 0.5);
uniform vec3 dry_tint : source_color = vec3(0.62, 0.95, 0.42);
uniform vec3 floor_tint : source_color = vec3(0.4, 0.38, 0.33);
const float L_MEADOW = 0.0;
const float L_DRY = 1.0;
const float L_MOSS = 2.0;
const float L_LITTER = 3.0;
const float L_FLOOR = 4.0;
const float L_SOIL = 5.0;
const float L_SAND = 7.0;

#include "res://shaders/SHADERINC_ground_lay.gdshaderinc"

#include "res://shaders/SHADERINC_lod_fade.gdshaderinc"
global uniform float enviro_wetness;

varying vec3 w_pos;
varying vec3 w_nrm;
varying vec4 ground_here;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ground_here = INSTANCE_CUSTOM;
	lod_keep = lod_fade_window(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	if (lod_fade_gone(lod_keep)) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (lod_fade_discard(FRAGCOORD.xy)) {
		discard;
	}
	vec3 geo_n = normalize(w_nrm);
	vec2 p = w_pos.xz;
	float dist = length(VERTEX);
	float detail = (1.0 - smoothstep(detail_distance * 0.5, detail_distance, dist)) * normal_strength;
	float macro = texture(macro_noise, p / 97.0).r;
	float macro2 = texture(macro_noise, p / 23.0 + 0.31).r;

	// (The terrain's rock branch, line for line.)
	vec3 bw = pow(abs(geo_n), vec3(triplanar_sharpness));
	bw /= bw.x + bw.y + bw.z;
	vec3 rp = w_pos / rock_size;
	vec2 dzy_x = dFdx(rp.zy); vec2 dzy_y = dFdy(rp.zy);
	vec2 dxz_x = dFdx(rp.xz); vec2 dxz_y = dFdy(rp.xz);
	vec2 dxy_x = dFdx(rp.xy); vec2 dxy_y = dFdy(rp.xy);
	vec3 albedo = (textureGrad(ground_albedo, vec3(rp.zy, rock_layer), dzy_x, dzy_y).rgb * bw.x
			+ textureGrad(ground_albedo, vec3(rp.xz, rock_layer), dxz_x, dxz_y).rgb * bw.y
			+ textureGrad(ground_albedo, vec3(rp.xy, rock_layer), dxy_x, dxy_y).rgb * bw.z) * rock_tint;
	vec3 tx = textureGrad(ground_normal, vec3(rp.zy, rock_layer), dzy_x, dzy_y).xyz * 2.0 - 1.0;
	vec3 ty = textureGrad(ground_normal, vec3(rp.xz, rock_layer), dxz_x, dxz_y).xyz * 2.0 - 1.0;
	vec3 tz = textureGrad(ground_normal, vec3(rp.xy, rock_layer), dxy_x, dxy_y).xyz * 2.0 - 1.0;
	vec3 nx = vec3(tx.xy * detail + geo_n.zy, abs(tx.z) * geo_n.x);
	vec3 ny = vec3(ty.xy * detail + geo_n.xz, abs(ty.z) * geo_n.y);
	vec3 nz = vec3(tz.xy * detail + geo_n.xy, abs(tz.z) * geo_n.z);
	vec3 world_n = normalize(nx.zyx * bw.x + ny.xzy * bw.y + nz.xyz * bw.z);
	float roughness = 0.82;

	// THE BEDS IT IS LAID DOWN IN, on its sides (SHADERINC_ground_lay's strata).
	vec2 beds = strata_at(w_pos, geo_n, dist);
	albedo *= beds.x;
	world_n = normalize(world_n + vec3(0.0, beds.y, 0.0));

	// WEAR ON THE EDGES, DARK IN THE CRACKS (the bake, over the texture).
	float grain = clamp(dot(albedo / rock_tint, vec3(0.45, 0.45, 0.1)) * 2.2, 0.0, 1.0);
	float worn = (1.0 - COLOR.r) * edge_wear;
	worn = smoothstep(0.25, 0.75, worn + (grain - 0.5) * 0.5) * clamp(worn * 2.0, 0.0, 1.0);
	albedo = mix(albedo, (mix(albedo, vec3(dot(albedo, vec3(0.33))), 0.35) * 1.5 + 0.02) * wear_tint, worn);
	roughness = mix(roughness, 0.7, worn);
	float shut = (1.0 - COLOR.g) * crevice;
	albedo *= 1.0 - shut * 0.75;
	roughness = mix(roughness, 0.95, shut);
	world_n = normalize(mix(world_n, geo_n, worn * 0.5));

	// THE TOP: the ground beside it, carried on over (the terrain's own blend).
	float top = smoothstep(top_start, top_full, geo_n.y);
	if (top > 0.0) {
		float forest = clamp(ground_here.x, 0.0, 1.0);
		vec3 share = max(ground_here.yzw, vec3(0.0));
		float sum = share.x + share.y + share.z;
		share = sum > 0.01 ? share / sum : vec3(1.0, 0.0, 0.0);
		vec2 pdx = dFdx(p);
		vec2 pdy = dFdy(p);
		float wood = smoothstep(0.15, 0.6, forest);
		float dryness = smoothstep(0.56, 0.8, macro + (macro2 - 0.5) * 0.5);
		vec3 a0; vec3 n0;
		vec3 ground_a = vec3(0.0);
		vec3 ground_n = vec3(0.0, 0.0, 1.0);
		if (share.x > 0.003) {
			vec3 grass_a = vec3(0.0);
			vec3 grass_n = vec3(0.0, 0.0, 1.0);
			if (wood < 1.0) {
				lay(L_MEADOW, p / meadow_size, pdx / meadow_size, pdy / meadow_size, a0, n0);
				grass_a = a0 * meadow_tint;
				grass_n = n0;
				if (dryness > 0.0) {
					lay(L_DRY, p / dry_size, pdx / dry_size, pdy / dry_size, a0, n0);
					grass_a = mix(grass_a, a0 * dry_tint, dryness);
					grass_n = mix(grass_n, n0, dryness);
				}
			}
			ground_a = grass_a;
			ground_n = grass_n;
			if (wood > 0.0) {
				float litter_mix = clamp(forest * (0.25 + macro2 * 1.1) * smoothstep(0.25, 0.6, macro + macro2 * 0.5), 0.0, 1.0);
				vec3 moss_a; vec3 moss_n;
				lay(L_MOSS, p / moss_size, pdx / moss_size, pdy / moss_size, moss_a, moss_n);
				lay(L_LITTER, p / litter_size, pdx / litter_size, pdy / litter_size, a0, n0);
				ground_a = mix(grass_a, mix(moss_a * moss_tint, a0 * litter_tint, litter_mix * 0.8), wood);
				ground_n = mix(grass_n, mix(moss_n, n0, litter_mix * 0.8), wood);
				float clearing = wood_clearing(p) * wood;
				if (clearing > 0.0) {
					lay(L_FLOOR, p / floor_size, pdx / floor_size, pdy / floor_size, a0, n0);
					a0 = mix(vec3(dot(a0, vec3(0.3, 0.55, 0.15))), a0, 0.4);
					ground_a = mix(ground_a, a0 * floor_tint, clearing);
					ground_n = mix(ground_n, n0, clearing);
				}
			}
		}
		vec3 top_a = ground_a * share.x;
		vec3 top_n = ground_n * share.x;
		if (share.y > 0.003) {
			lay(L_SOIL, p / soil_size, pdx / soil_size, pdy / soil_size, a0, n0);
			top_a += a0 * soil_tint * share.y;
			top_n += n0 * share.y;
		}
		if (share.z > 0.003) {
			lay(L_SAND, p / sand_size, pdx / sand_size, pdy / sand_size, a0, n0);
			top_a += a0 * sand_tint * share.z;
			top_n += n0 * share.z;
		}
		// A ragged edge: the turf takes the rock's hollows (its dark) first.
		float relief = clamp(dot(albedo / rock_tint, vec3(0.45, 0.45, 0.1)) * 2.2, 0.0, 1.0);
		top = smoothstep(0.3, 0.7, top + (0.5 - relief) * 0.5);
		albedo = mix(albedo, top_a, top);
		world_n = normalize(mix(world_n, normalize(geo_n + vec3(top_n.x, 0.0, top_n.y) * detail), top));
		roughness = mix(roughness, 0.93, top);
	}

	// (And the terrain's finish over every layer.)
	albedo *= mix(1.0, 0.62 + macro * 0.5 + macro2 * 0.26, macro_strength);
	float wet = clamp(enviro_wetness * (0.55 + macro2 * 0.9), 0.0, 1.0);
	albedo *= mix(1.0, 0.6, wet);
	roughness = mix(roughness, 0.28, wet * 0.85);

	ALBEDO = albedo * brightness;
	AO = 1.0 - shut * 0.6;
	AO_LIGHT_AFFECT = 0.35;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.4;
	NORMAL = normalize(mat3(VIEW_MATRIX) * world_n);
}
