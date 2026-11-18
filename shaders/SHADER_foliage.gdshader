// FOLIAGE: fir needles, fern fronds and grass. Lit, alpha-tested cards that sway.
// The cards are single-sided on purpose: their back faces are extra triangles on
// the same vertices, so both sides share one outward normal and the underside of
// a bough is never shaded black.
shader_type spatial;
render_mode cull_back, world_vertex_coords;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.38;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
// Light that comes through the leaf from behind.
uniform vec3 backlight : source_color = vec3(0.16, 0.2, 0.06);
// Metres the tips swing in a full wind, and how hard they shiver.
uniform float wind_bend = 0.5;
uniform float wind_flutter = 0.03;
// The texture holds this many plants side by side; INSTANCE_CUSTOM.x picks one.
uniform float atlas_columns = 1.0;
// Plants shrink into the ground between these distances (0 = never).
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;

#include "res://shaders/SHADERINC_wind.gdshaderinc"
global uniform float enviro_wetness;

varying vec3 shade;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	if (fade_end > 0.0) {
		float d = distance(root, CAMERA_POSITION_WORLD);
		float keep = 1.0 - smoothstep(fade_start, fade_end, d);
		VERTEX = root + (VERTEX - root) * keep;
	}
	VERTEX += wind_offset(VERTEX, UV2, wind_bend, wind_flutter);
	shade = COLOR.rgb;
	// Only an atlas has per-instance data; without it INSTANCE_CUSTOM is not defined.
	if (atlas_columns > 1.5) {
		UV.x = (UV.x + floor(INSTANCE_CUSTOM.x + 0.5)) / atlas_columns;
		shade *= 0.8 + 0.4 * INSTANCE_CUSTOM.y;
	}
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	// Thin cards lose coverage in the mipmaps; lean on the alpha with distance.
	float a = t.a * (1.0 + clamp(length(VERTEX) / 40.0, 0.0, 1.6));
	// A plain discard, not ALPHA + ALPHA_SCISSOR_THRESHOLD: on the Mobile renderer that
	// route shaded these cards black.
	if (a < alpha_cut) {
		discard;
	}
	ALBEDO = t.rgb * tint * shade * mix(1.0, 0.8, enviro_wetness);
	ROUGHNESS = mix(roughness, 0.3, enviro_wetness * 0.7);
	SPECULAR = 0.35;
	BACKLIGHT = backlight;
}
