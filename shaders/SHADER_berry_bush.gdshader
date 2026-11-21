// A berry bush in leaf: the model's cards, cut out by their alpha, lit from both
// sides, with a little light coming through the leaves. `grown` fades the whole
// bush in through a screen-door dither (0 none of it, 1 all of it), which is how
// a stripped bush comes back: SCRIPT_berry_bushes.gd.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 backlight : source_color = vec3(0.14, 0.2, 0.05);
uniform float roughness = 0.75;
instance uniform float grown = 1.0;

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
	BACKLIGHT = backlight;
}
