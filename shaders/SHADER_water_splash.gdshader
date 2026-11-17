shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque, skip_vertex_transform;

// THE WATER A VEHICLE THROWS UP (`WaterWakes`, SCRIPT_water_wakes.gd; the user:
// "vehicle --> water splashing rippling interaction (performant retro
// aesthetic)"; and later: "driving water particles need to be smaller, more
// randomized, more detailed; hover jet water particles should use point particle
// fountains same water particles as car, as proximity to water based vapor cloud
// particles"). Every one of them is a quad of one MultiMesh, turned to the eye:
// one draw for all of them. Three kinds (INSTANCE_CUSTOM.z):
//
//   0 A DROPLET: round, the quad `drop_pixels` pixels a side, the pixels inside
//     its round hard-edged; lit up and to the left of its middle, shaded down
//     and to the right, a ball of water.
//   1 A STREAK: the same water drawn out along the way it flies, as long as the
//     instance's second column says (its flight over a few hundredths of a
//     second), its head as wide as a droplet and thinning to a tail, which the
//     dither eats first.
//   2 VAPOUR: big and thin, its outline lumpy, white, on a finer grid than a
//     droplet's (`vapour_pixels`): drawn from the start with only some of its
//     pixels (`vapour_cover`), most in its middle and fewer to its edge, and fewer
//     as it goes, so it reads as a cloud through which the world shows; a screen
//     door, the way transparency was done when nothing could blend.
//
// RETRO, AND CHEAP: NOTHING IS BLENDED. Thrown up, water is the foam's white, and
// it turns the water's colour as it falls, in bands (`color_steps`). It goes by
// DISSOLVING: a 4x4 Bayer dither on its own pixels eats it as its life runs out,
// and it shrinks. So it is drawn in the opaque pass, tested and written to depth
// like the ground, and never sorted.
//
// INSTANCE_CUSTOM: x how much of its life is gone, 0 to 1; y a roll of its own,
// which shifts its dither and its outline; z its kind.

global uniform vec4 tod_water_tint;

uniform vec3 foam_color : source_color = vec3(0.93, 0.97, 0.95);
uniform vec3 water_color : source_color = vec3(0.34, 0.76, 0.68);
// Pixels across a droplet's quad (a streak's width), and a vapour cloud's.
uniform float drop_pixels = 5.0;
uniform float vapour_pixels = 24.0;
// The share of a vapour cloud's pixels drawn when it is new.
uniform float vapour_cover : hint_range(0.0, 1.0) = 0.5;
uniform float color_steps = 6.0;

varying vec3 drop;
// A streak's length over its width.
varying float aspect;

// A 4x4 ordered dither's threshold for pixel `a`, 1/32 to 31/32, without a table.
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(a * 0.5) * 0.25 + bayer2(a) + 0.03125;
}

float cell_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	drop = INSTANCE_CUSTOM.xyz;
	// Turned to the eye, `sc` across; a streak drawn out along its flight as the
	// eye sees it.
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec2 ax = vec2(sc, 0.0);
	vec2 ay = vec2(0.0, sc);
	aspect = 1.0;
	if (drop.z > 0.5 && drop.z < 1.5) {
		vec2 fly = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xy;
		float l = length(fly);
		if (l > sc) {
			vec2 dir = fly / l;
			ay = dir * l;
			ax = vec2(dir.y, -dir.x) * sc;
			aspect = l / sc;
		}
	}
	VERTEX = c + vec3(VERTEX.x * ax + VERTEX.y * ay, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float gone = clamp(drop.x, 0.0, 1.0);
	bool vapour = drop.z > 1.5;
	bool streak = drop.z > 0.5 && !vapour;
	float px = vapour ? max(vapour_pixels, 2.0) : max(drop_pixels, 2.0);
	vec2 cells = vec2(px, streak ? px * clamp(aspect, 1.0, 8.0) : px);
	vec2 cell = floor(UV * cells);
	// The pixel's middle, -1 to 1 across the quad, +y down (a streak's tail).
	vec2 q = (cell + 0.5) / cells * 2.0 - 1.0;
	float dither = bayer4(cell + floor(drop.y * 4.0));
	vec3 c;
	if (vapour) {
		// Lumpy: each pixel of the outline in or out by a roll of its own.
		float rad = mix(1.0, 0.8, gone) * (0.82 + 0.18 * cell_hash(cell + drop.y * 97.0));
		if (length(q) > rad) {
			discard;
		}
		// Thick in its middle, thinning to its edge: a cloud, not a disc.
		float keep = vapour_cover * (1.0 - gone) * (1.0 - gone) * (1.0 - 0.75 * dot(q, q) / (rad * rad));
		if (dither > keep) {
			discard;
		}
		c = foam_color;
		if (dot(q, vec2(-0.7071, -0.7071)) > 0.5) {
			c = mix(c, vec3(1.0), 0.5);
		}
	} else if (streak) {
		// Head first, the way it flies (q.y -1), thinning to its tail.
		float t = q.y * 0.5 + 0.5;
		if (abs(q.x) > mix(0.95, 0.2, t)) {
			discard;
		}
		if (dither > (1.0 - 0.75 * t) * (1.0 - smoothstep(0.4, 1.0, gone))) {
			discard;
		}
		c = mix(foam_color, water_color, clamp(t * 0.5 + gone * 0.6, 0.0, 1.0));
		if (t < 0.25) {
			c = mix(c, vec3(1.0), 0.5);
		}
	} else {
		float rad = mix(1.0, 0.55, gone);
		float r = length(q);
		if (r > rad) {
			discard;
		}
		if (dither > 1.0 - smoothstep(0.5, 1.0, gone)) {
			discard;
		}
		c = mix(foam_color, water_color, smoothstep(0.1, 0.6, gone));
		// Lit from up and to the left.
		float lit = dot(q / rad, vec2(-0.7071, -0.7071));
		if (lit > 0.45) {
			c = mix(c, vec3(1.0), 0.6);
		} else if (lit < -0.35) {
			c *= 0.72;
		}
	}
	float steps = max(color_steps, 2.0);
	c = floor(c * steps + 0.5) / steps;
	ALBEDO = c * tod_water_tint.rgb;
}
