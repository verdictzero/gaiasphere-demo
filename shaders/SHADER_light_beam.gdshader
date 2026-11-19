// A SHAFT OF LIGHT standing on the sword in the stone: a tall, narrow cone drawn
// additively, bright along its axis and gone at its edges, thinning away upward
// so that it has no visible source, with dust drifting slowly down it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 beam_color : source_color = vec3(0.75, 0.86, 1.0);
uniform float intensity = 0.45;
uniform sampler2D dust : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

void fragment() {
	// Looking through the middle of the cone crosses the most light.
	float through = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(through, 4.0);
	// UV.y runs 0 at the top to 1 at the ground.
	float rise = smoothstep(0.0, 0.75, UV.y) * (1.0 - smoothstep(0.96, 1.0, UV.y));
	float motes = texture(dust, vec2(UV.x * 3.0, UV.y * 2.0 - TIME * 0.012)).r;
	float flicker = 0.92 + 0.08 * sin(TIME * 0.7);
	// Soft where it meets the stone, the ground and the trees.
	vec4 p = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	float soft = clamp((-p.z / p.w + VERTEX.z) / 2.5, 0.0, 1.0);
	ALBEDO = beam_color * intensity * core * rise * (0.55 + 0.75 * motes) * flicker * soft;
}
