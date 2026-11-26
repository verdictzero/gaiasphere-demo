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

#include "res://shaders/SHADERINC_lod_fade.gdshaderinc"
global uniform float enviro_wetness;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

	// (And the terrain's finish over every layer.)
	albedo *= mix(1.0, 0.62 + macro * 0.5 + macro2 * 0.26, macro_strength);
	float wet = clamp(enviro_wetness * (0.55 + macro2 * 0.9), 0.0, 1.0);
	albedo *= mix(1.0, 0.6, wet);
	roughness = mix(roughness, 0.28, wet * 0.85);

	ALBEDO = albedo * brightness;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.4;
	NORMAL = normalize(mat3(VIEW_MATRIX) * world_n);
}
