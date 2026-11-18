// THE ISLAND'S WALL: the boulder shader with both faces drawn, because the wall's
// bands are not wound one way. Keep the two in step.
// A BOULDER: lit rock, textured in world space on three planes so any instance
// scale or rotation keeps the same texel density, with moss on what faces the sky
// (SHADERINC_top_moss). The meshes are assets/boulder/*.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// R ambient occlusion, G roughness, B metallic (Poly Haven's "arm").
uniform sampler2D rock_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Tiles per metre.
uniform float rock_scale = 0.3;
uniform vec3 rock_tint : source_color = vec3(1.0);
uniform float rock_normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 5.0;
// Breaks up the tiling on big rock: light and dark patches several tiles across.
uniform float macro_variation : hint_range(0.0, 1.0) = 0.5;
// Darkens the foot of the boulder where it sits in the ground: metres above the origin.
// 0 turns it off (cliff chunks, whose origin is at their top).
uniform float ground_occlusion_height = 0.35;

#include "res://shaders/SHADERINC_top_moss.gdshaderinc"

varying vec3 w_pos;
varying vec3 w_nrm;
varying float foot;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	foot = w_pos.y - MODEL_MATRIX[3].y;
}

void fragment() {
	vec3 n = normalize(w_nrm);
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 w = pow(abs(n), vec3(triplanar_sharpness));
	w /= w.x + w.y + w.z;
	vec3 p = w_pos * rock_scale;

	vec3 albedo = texture(rock_albedo, p.zy).rgb * w.x + texture(rock_albedo, p.xz).rgb * w.y
			+ texture(rock_albedo, p.xy).rgb * w.z;
	vec3 orm = texture(rock_orm, p.zy).rgb * w.x + texture(rock_orm, p.xz).rgb * w.y
			+ texture(rock_orm, p.xy).rgb * w.z;
	// Each plane's normal map, swung into world space and blended ("whiteout").
	vec3 tx = texture(rock_normal, p.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(rock_normal, p.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(rock_normal, p.xy).xyz * 2.0 - 1.0;
	tx.xy *= rock_normal_strength;
	ty.xy *= rock_normal_strength;
	tz.xy *= rock_normal_strength;
	vec3 nx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	vec3 ny = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	vec3 nz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 world_n = normalize(nx.zyx * w.x + ny.xzy * w.y + nz.xyz * w.z);

	float macro = texture(rock_albedo, (w_pos.xy + w_pos.zy * 0.83) * rock_scale * 0.11).g
			+ texture(rock_albedo, (w_pos.zx + w_pos.yx * 0.71) * rock_scale * 0.037).g;
	// The same rock again at a third the scale, mixed in: no single tile repeats.
	vec3 q = w_pos * rock_scale * 0.31 + 0.37;
	vec3 wide = texture(rock_albedo, q.zy).rgb * w.x + texture(rock_albedo, q.xz).rgb * w.y
			+ texture(rock_albedo, q.xy).rgb * w.z;
	albedo = mix(albedo, wide, 0.55);
	albedo *= rock_tint * mix(1.0, 0.45 + macro * 1.1, macro_variation);
	float roughness = orm.g;
	float ao = orm.r;
	float height = dot(albedo, vec3(0.333)) * 1.6;      // pale rock stands proud, dark is crevice
	top_moss(albedo, world_n, roughness, ao, w_pos, n, clamp(height, 0.0, 1.0));

	if (ground_occlusion_height > 0.0) {
		ao *= mix(0.45, 1.0, smoothstep(0.0, ground_occlusion_height, foot));
	}
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;
	NORMAL = normalize(mat3(VIEW_MATRIX) * world_n);
}
