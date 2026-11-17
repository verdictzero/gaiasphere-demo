shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
	fog_disabled, skip_vertex_transform;

// A PUFF OF A FOG BANK in the giant forest (island 003, SCRIPT_forest_fog.gd): one
// card of a MultiMesh of them, turned to the eye, drawn as a soft-edged cloud of
// noise (the user: "soft edge noise based fog particles and have areas of fog
// particles to compliment the fog"). A bank is a few dozen of them standing in
// the wood together, slowly drifting, over the fog that is everywhere.
//
// SOFT EVERY WAY, so a card is never seen as a card:
//   * its edge is a ragged falloff of the noise, not a circle;
//   * where it passes into the ground or a trunk it thins away over `soft_depth`
//     metres of the depth behind it (soft particles), so it never cuts a line;
//   * it thins away close to the eye (`near_fade`), so walking into a bank is
//     walking into thicker air, not into a grey wall;
//   * and far off (`far_fade`), where the fog wall has the world anyway.
//
// ITS COLOUR IS THE FOG'S: the neutral 0.30 every fog here is pinned to, times
// `tod_haze_tint`, times `tint` — a shade lighter than the fog round it, so a bank
// reads as the fog gathered rather than as smoke.
//
// EACH PUFF ITS OWN: INSTANCE_CUSTOM.x seeds its noise and its drift and .y how
// thick it is, so neighbours never repeat and a rebase moves nothing.

#include "res://shaders/SHADERINC_weather_shelter.gdshaderinc"
global uniform vec4 tod_haze_tint;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 base_color : source_color = vec3(0.30, 0.30, 0.30);
uniform vec3 tint : source_color = vec3(1.18, 1.18, 1.2);
// Opacity at a puff's thickest.
uniform float opacity : hint_range(0.0, 1.0) = 0.42;
// Noise blobs across a card, and how fast they churn.
uniform float noise_scale = 2.6;
uniform float churn = 0.025;
// Metres a puff wanders off its place, and how fast.
uniform float drift_amp = 2.5;
uniform float drift_speed = 0.06;
uniform float soft_depth = 3.0;
// Fully gone nearer than x, whole past y, metres from the eye.
uniform vec2 near_fade = vec2(2.5, 9.0);
// And, for puffs big enough to walk into, gone nearer than x and whole past y
// TIMES THE PUFF'S WIDTH from its middle (0 leaves it to `near_fade`): a card
// tens of metres across stands in front of the eye long before its corners
// come near, and would cut the view with a flat plane.
uniform vec2 near_scale = vec2(0.0, 0.0);
// Whole nearer than x, gone past y.
uniform vec2 far_fade = vec2(140.0, 210.0);
// THE EDGE: where the falloff starts, as a share of the card's radius, and how
// far the noise pushes it in and out. Low and little is a soft cloud that runs
// out to nothing; the defaults are island 003's ragged wisps.
uniform float edge_inner : hint_range(0.0, 0.9) = 0.25;
uniform float edge_ragged : hint_range(0.0, 0.6) = 0.35;
// THE BODY: half the width of the noise's ramp from clear to thick. Wider is
// smoother, fewer holes through it.
uniform float body_width : hint_range(0.05, 0.5) = 0.25;
// Width over height: over 1 a puff is a low, wide billow lying along the ground
// rather than a ball.
uniform float aspect : hint_range(0.5, 4.0) = 1.0;

varying float v_seed;
varying float v_thick;
varying float v_dist;
varying float v_near;

float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return noise2(p) * 0.55 + noise2(p * 2.07 + 11.3) * 0.3 + noise2(p * 4.31 + 23.9) * 0.15;
}

void vertex() {
	v_seed = INSTANCE_CUSTOM.x;
	v_thick = INSTANCE_CUSTOM.y;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 centre = MODEL_MATRIX[3].xyz;
	float ph = v_seed * 6.2831;
	centre += vec3(sin(TIME * drift_speed + ph), 0.0, cos(TIME * drift_speed * 0.8 + ph * 1.7)) * drift_amp;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = centre + (right * VERTEX.x * aspect + up * VERTEX.y) * s;
	v_dist = length(world - INV_VIEW_MATRIX[3].xyz);
	v_near = near_scale.y > 0.0
			? smoothstep(near_scale.x * s, near_scale.y * s, length(centre - INV_VIEW_MATRIX[3].xyz))
			: 1.0;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	vec2 q = UV * noise_scale + vec2(v_seed * 37.0, v_seed * 91.0);
	float n = fbm(q + vec2(TIME * churn, -TIME * churn * 0.7));
	float n2 = fbm(q * 1.7 - vec2(TIME * churn * 0.6, TIME * churn));
	// A ragged edge: the falloff pushed in and out by the noise.
	float edge = 1.0 - smoothstep(edge_inner + edge_ragged * n, 0.95, r + (n2 - 0.5) * 0.35);
	float body = smoothstep(0.5 - body_width, 0.5 + body_width, n * 0.7 + n2 * 0.5);
	float a = edge * body * opacity * mix(0.6, 1.0, v_thick);

	// Soft where it meets what is behind it.
	float d = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
#endif
	vec4 v = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_z = -v.z / v.w;
	float frag_z = -VERTEX.z;
	a *= clamp((scene_z - frag_z) / max(soft_depth, 0.01), 0.0, 1.0);
	a *= smoothstep(near_fade.x, near_fade.y, v_dist) * v_near;
	a *= 1.0 - smoothstep(far_fade.x, far_fade.y, v_dist);
	// None of it inside a room, per pixel: a puff is metres across, and the part of
	// it that reaches into a room goes while the rest stays (SHADERINC_weather_shelter).
	a *= weather_open((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);

	ALBEDO = base_color * tod_haze_tint.rgb * tint * (0.92 + 0.16 * n);
	ALPHA = clamp(a, 0.0, 1.0);
}
