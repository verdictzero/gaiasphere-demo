// TOP-DOWN MOSS: a sub-shader any lit surface can wear. Moss settles on what faces
// the sky, in WORLD space, so a boulder (or a trunk, or a cliff ledge) keeps its
// moss on top however the instance is turned or scaled.
//
//   #include "res://shaders/SHADERINC_top_moss.gdshaderinc"
//   ...
//   top_moss(albedo, world_normal, roughness, ao, world_pos, geometry_world_normal, height);
//
// `height` is the host surface's relief, 0 (crevice) to 1 (peak): moss creeps along
// the crevices first, which is what breaks its edge up. Pass 0.5 if there is none.

uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// How much of the upward-facing surface is covered: 0 none, 1 everything but overhangs.
uniform float moss_amount : hint_range(0.0, 1.0) = 0.45;
// How hard the edge of the moss is.
uniform float moss_sharpness : hint_range(1.0, 32.0) = 9.0;
// Tiles per metre.
uniform float moss_scale = 0.45;
uniform vec3 moss_tint : source_color = vec3(0.30, 0.36, 0.17);
uniform float moss_roughness : hint_range(0.0, 1.0) = 0.93;
uniform float moss_normal_strength : hint_range(0.0, 2.0) = 0.8;
// Moss is a cushion: it hides this much of the relief beneath it.
uniform float moss_softness : hint_range(0.0, 1.0) = 0.7;

float top_moss_mask(vec3 world_pos, vec3 geo_n, float height) {
	// Two octaves of the moss texture itself, far below its own tiling, stand in
	// for a noise texture: patches a metre or two across with ragged edges.
	float patches = texture(moss_albedo, world_pos.xz * moss_scale * 0.07).g
			+ 0.5 * texture(moss_albedo, world_pos.zx * moss_scale * 0.23 + 0.37).g;
	float bias = (patches / 0.75 - 0.5) * 0.9 + (0.5 - height) * 0.45;
	float threshold = mix(1.25, -0.35, moss_amount);
	return clamp((geo_n.y + bias - threshold) * moss_sharpness * 0.5 + 0.5, 0.0, 1.0);
}

void top_moss(inout vec3 albedo, inout vec3 world_n, inout float roughness, inout float ao,
		vec3 world_pos, vec3 geo_n, float height) {
	float m = top_moss_mask(world_pos, geo_n, height);
	if (m <= 0.001) {
		return;
	}
	vec2 uv = world_pos.xz * moss_scale;
	vec3 col = texture(moss_albedo, uv).rgb * moss_tint;
	vec3 nt = texture(moss_normal, uv).xyz * 2.0 - 1.0;
	// The moss lies on a top-down projection: its tangent is +X, its bitangent +Z.
	vec3 base_n = normalize(mix(world_n, geo_n, moss_softness));
	vec3 moss_n = normalize(base_n + vec3(nt.x, 0.0, nt.y) * moss_normal_strength);
	albedo = mix(albedo, col, m);
	world_n = normalize(mix(world_n, moss_n, m));
	roughness = mix(roughness, moss_roughness, m);
	// A thin dark line where the moss begins reads as its thickness.
	ao *= 1.0 - 0.35 * m * (1.0 - m) * 4.0;
}
