// GOD RAYS: light shafts from the sun or moon, drawn over the finished frame.
// For every pixel it walks toward the light's place on screen and counts how
// much open sky it crosses; trunks, branches and cliffs in the way cut the
// shafts. One depth read per step and nothing else. SCRIPT_enviro.gd places the
// light on screen and fades the pass out when it is behind the camera.
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled,
		shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec2 light_uv = vec2(0.5);
uniform vec3 ray_color : source_color = vec3(1.0, 0.85, 0.6);
uniform float intensity = 0.0;
uniform int samples = 24;
uniform float reach : hint_range(0.1, 1.0) = 0.95;
uniform float decay : hint_range(0.8, 1.0) = 0.97;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	if (intensity <= 0.001) {
		discard;
	}
	vec2 uv = SCREEN_UV;
	vec2 aspect = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	vec2 delta = (light_uv - uv) * reach / float(samples);
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	uv += delta * jitter;
	float lit = 0.0;
	float w = 1.0;
	for (int i = 0; i < samples; i++) {
		uv += delta;
		// Reversed depth: the sky is at 0.
		float open = step(texture(depth_tex, clamp(uv, vec2(0.001), vec2(0.999))).r, 0.000001);
		float near = 1.0 - smoothstep(0.0, 0.95, length((uv - light_uv) * aspect));
		lit += open * near * w;
		w *= decay;
	}
	// Squared: the shafts stand out from the general glow instead of washing the frame.
	float shaft = lit / float(samples);
	ALBEDO = ray_color * (shaft * shaft * 1.6 + shaft * 0.1) * intensity;
}
