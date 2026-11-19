// THE LENS: what a camera does to a picture after the world is drawn. A colour
// grade that cools the shadows and warms the highlights, a vignette, the faint
// colour fringing of glass toward the corners, and film grain. Drawn over the
// finished frame by SCRIPT_enviro.gd; every part can be turned to nothing.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float grade : hint_range(0.0, 1.0) = 0.55;
uniform vec3 shadow_tint : source_color = vec3(0.86, 0.98, 1.1);
uniform vec3 highlight_tint : source_color = vec3(1.1, 1.0, 0.86);
uniform float vignette : hint_range(0.0, 1.0) = 0.42;
uniform float fringe : hint_range(0.0, 0.01) = 0.0022;
uniform float grain : hint_range(0.0, 0.2) = 0.035;
// Black bars for a wide cinema frame: the picture's width over its height (0 = none).
uniform float letterbox_aspect = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	// Fringing grows toward the corners and is nothing in the middle.
	vec2 off = c * r2 * fringe * 4.0;
	vec3 col = vec3(texture(screen_tex, uv + off).r, texture(screen_tex, uv).g, texture(screen_tex, uv - off).b);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	// Split toning, and a gentle S-curve for contrast.
	vec3 toned = col * mix(shadow_tint, highlight_tint, smoothstep(0.05, 0.75, lum));
	toned = mix(toned, toned * toned * (3.0 - 2.0 * toned), 0.35);
	col = mix(col, toned, grade);
	col *= 1.0 - vignette * smoothstep(0.1, 0.62, r2);
	// Grain: finest in the mid-tones, where film shows it.
	vec2 px = uv / SCREEN_PIXEL_SIZE;
	float n = fract(sin(dot(px + fract(TIME) * 61.7, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	col += n * grain * (1.0 - abs(lum * 2.0 - 1.0) * 0.6);
	if (letterbox_aspect > 0.0) {
		float picture = (SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x) / letterbox_aspect;   // share of the height kept
		col *= step(abs(c.y), picture * 0.5);
	}
	COLOR = vec4(col, 1.0);
}
