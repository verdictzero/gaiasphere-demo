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
// The lens: a wide horizontal streak through the sun, a soft halo, and ghosts
// strung along the line from the sun through the middle of the frame.
uniform float flare = 0.0;
uniform vec3 flare_color : source_color = vec3(0.45, 0.65, 1.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	if (intensity <= 0.001 && flare <= 0.001) {
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
	// Squared and cubed: the shafts cut hard against the shade between them.
	vec3 col = ray_color * (shaft * shaft * 1.5 + shaft * shaft * shaft * 1.2 + shaft * 0.08) * intensity;
	if (flare > 0.001) {
		// How much of the sun's disc is clear of trees and hills: nine depth taps round it.
		float seen = 0.0;
		for (int k = 0; k < 9; k++) {
			vec2 o = vec2(float(k % 3) - 1.0, float(k / 3) - 1.0) * 0.006;
			vec2 su = light_uv + o / aspect;
			if (su.x > 0.0 && su.x < 1.0 && su.y > 0.0 && su.y < 1.0) {
				seen += step(texture(depth_tex, su).r, 0.000001);
			}
		}
		seen /= 9.0;
		vec2 d = (SCREEN_UV - light_uv) * aspect;
		// The anamorphic streak: very wide, very thin, with a brighter thin core.
		float streak = exp(-abs(d.y) * 55.0) / (1.0 + d.x * d.x * 5.0)
				+ 0.6 * exp(-abs(d.y) * 260.0) / (1.0 + d.x * d.x * 1.2);
		float halo = exp(-dot(d, d) * 22.0) * 0.5;
		vec3 lens = flare_color * streak + ray_color * halo;
		// Ghosts: soft discs mirrored through the centre of the frame.
		vec2 axis = (vec2(0.5) - light_uv) * aspect;
		vec2 here = (SCREEN_UV - vec2(0.5)) * aspect;
		float alongs[4] = float[4](0.35, 0.7, 1.25, 1.7);
		float sizes[4] = float[4](0.045, 0.02, 0.07, 0.11);
		for (int g = 0; g < 4; g++) {
			float along = alongs[g];
			float size = sizes[g];
			// 0 is on the sun, 1 the middle of the frame, 2 the sun mirrored through it.
			float r = length(here + axis * (1.0 - along));
			float disc = smoothstep(size, size * 0.6, r) * (0.5 + 0.5 * smoothstep(size * 0.4, size, r));
			lens += mix(flare_color, ray_color, float(g) / 3.0) * disc * 0.018;
		}
		col += lens * flare * seen;
	}
	ALBEDO = col;
}
