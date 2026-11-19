// BARK: trunks and limbs. Lit PBR from the scanned bark, swaying with the foliage
// it carries, with moss on the weather side as rain soaks it darker.
shader_type spatial;
render_mode cull_back, world_vertex_coords;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.5, 0.45, 0.4);
uniform float wind_bend = 0.5;
uniform float normal_strength : hint_range(0.0, 6.0) = 3.0;

#include "res://shaders/SHADERINC_wind.gdshaderinc"
#include "res://shaders/SHADERINC_lod_fade.gdshaderinc"
global uniform float enviro_wetness;

void vertex() {
	lod_fade_vertex(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD);
	VERTEX += wind_offset(VERTEX, UV2, wind_bend, 0.0);
}

void fragment() {
	if (lod_fade_discard(FRAGCOORD.xy)) {
		discard;
	}
	vec3 orm = texture(orm_tex, UV).rgb;
	ALBEDO = texture(albedo_tex, UV).rgb * tint * mix(1.0, 0.7, enviro_wetness);
	NORMAL_MAP = texture(normal_tex, UV).xyz;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = mix(orm.g, 0.4, enviro_wetness * 0.6);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	METALLIC = 0.0;
}
