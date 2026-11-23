// A berry bush, in leaf or bare: the model's cards, cut out by their alpha, lit
// from both sides, with a little light coming through the leaves, moving in the
// wind like everything else that grows (the higher on the bush, the further).
//
// Drawn as a MultiMesh (SCRIPT_berry_bushes.gd): INSTANCE_CUSTOM.x is how much of
// this bush is there, 0 none to 1 all, faded through a screen-door dither, which
// is how a stripped bush's leaves come back.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, world_vertex_coords;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 backlight : source_color = vec3(0.14, 0.2, 0.05);
uniform float roughness = 1.0;
uniform float wind_bend = 0.3;
uniform float wind_flutter = 0.035;
// The model's height, metres: the top of the bush swings its full share.
uniform float height = 2.5;

#include "res://shaders/SHADERINC_wind.gdshaderinc"

varying float grown;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	grown = INSTANCE_CUSTOM.x;
	float up = clamp((VERTEX.y - root.y) / (height * length(MODEL_MATRIX[1].xyz)), 0.0, 1.0);
	// Each bush in its own time, and its outer twigs a little out of step with its middle.
	float phase = fract(root.x * 0.137 + root.z * 0.291) + 0.15 * fract(dot(VERTEX.xz - root.xz, vec2(0.71, 0.53)));
	VERTEX += wind_offset(VERTEX, vec2(up * up, phase), wind_bend, wind_flutter);
	if (grown <= 0.0) {
		VERTEX = root;          // none of it showing: no triangle at all
	}
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	// (A plain discard, not ALPHA with a scissor: that came out black on the Mobile renderer.)
	if (c.a < 0.5) {
		discard;
	}
	float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (dither >= grown) {
		discard;
	}
	ALBEDO = c.rgb * tint;
	NORMAL_MAP = texture(normal_tex, UV).xyz;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.0;          // leaves and berries: no shine
	BACKLIGHT = backlight;
}
