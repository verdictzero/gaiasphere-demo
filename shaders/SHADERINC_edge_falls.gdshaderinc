// THE FALLS OFF THE EDGE: where a moving river runs off the island's edge it
// pours on down the shoulder and the cliff wall under it, streaming, spreading
// and thinning as it drops: molten lava glowing gold to red on island 004, a
// glacier's icefall white and blue and all but still on 005. Shared by the
// terrain shader (the shoulder, which is part of the walkable mesh) and
// SHADER_cliff_wall.gdshader (the wall under it), so the fall runs down across
// the handoff between the two as one.
//
// The falls are `FlowTerrain`'s moving rivers that reach the coast, handed over
// by `EdgeFalls` (SCRIPT_edge_falls.gd) in the field's frame: each is its mouth's
// bearing round the island's centre, its half-width, the lip's height and the
// mouth's distance out. The render frame is the field's less `edge_fall_origin`,
// which `EdgeFalls` keeps up through every rebase.
//
// A fall is placed by BEARING, not by distance to the mouth, because the wall
// tapers in under the island: a point on the wall below the mouth is nearer the
// island's middle than the mouth is, and only its bearing says it is under it.

uniform int edge_fall_count = 0;
// Per fall: x the mouth's bearing round `edge_fall_center` (radians), y its
// half-width (metres), z the lip's height (field frame), w the mouth's distance
// from the centre (metres).
uniform vec4 edge_falls[8];
uniform vec2 edge_fall_center = vec2(0.0);
uniform vec3 edge_fall_origin = vec3(0.0);
// Metres down the wall a fall pours before it has thinned away.
uniform float edge_fall_reach = 260.0;
// Metres a second the streaks run down it.
uniform float edge_fall_speed = 11.0;
uniform float edge_fall_glow = 2.4;
// How much wider it is for every 100 m it has dropped.
uniform float edge_fall_spread = 0.9;
uniform vec3 edge_fall_hot : source_color = vec3(1.0, 0.72, 0.22);
uniform vec3 edge_fall_cool : source_color = vec3(0.62, 0.10, 0.02);

float edge_fall_hash(vec2 c) {
	return fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453);
}

float edge_fall_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = edge_fall_hash(i);
	float b = edge_fall_hash(i + vec2(1.0, 0.0));
	float c = edge_fall_hash(i + vec2(0.0, 1.0));
	float d = edge_fall_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// The falls at a render-space point: rgb the light they give off (to add after
// the shading), w how much of the rock under them they cover (to darken it by).
//
// `inland_guard` is the terrain's: its mesh is the land as well as the shoulder,
// and a river runs out along much the bearing of its own mouth, so wherever its
// channel dipped under the lip's height the river itself would light up as a
// fall. With the guard a fall draws only out at its mouth and down the shoulder
// under it, which curls in no more than a metre and a half for every metre it
// drops. The wall is never inland and goes without.
vec4 edge_fall_light(vec3 world_pos, float time, bool inland_guard) {
	vec4 acc = vec4(0.0);
	if (edge_fall_count <= 0) {
		return acc;
	}
	vec3 fp = world_pos + edge_fall_origin;
	vec2 rel = fp.xz - edge_fall_center;
	float ang = atan(rel.y, rel.x);
	float rad = length(rel);
	for (int i = 0; i < 8; i++) {
		if (i >= edge_fall_count) {
			break;
		}
		vec4 f = edge_falls[i];
		float down = f.z - fp.y;
		if (down < -1.0 || down > edge_fall_reach) {
			continue;
		}
		if (inland_guard && rad < f.w - 4.0 - max(down, 0.0) * 1.5) {
			continue;
		}
		float da = abs(mod(ang - f.x + PI, TAU) - PI);
		float lat = da * rad;
		float hw = f.y * (1.0 + max(down, 0.0) * edge_fall_spread / 100.0);
		if (lat > hw) {
			continue;
		}
		float core = 1.0 - smoothstep(hw * 0.35, hw, lat);
		// Streams of it running down, fine and fast over broad and slower.
		float y = fp.y + time * edge_fall_speed;
		// The streams widen far less than the fall does, so a fall a long way
		// down is many threads rather than a few broad bands.
		float fine = edge_fall_noise(vec2(lat / (1.6 + hw * 0.08) + float(i) * 17.0, y / 7.0));
		float broad = edge_fall_noise(vec2(lat / (3.0 + hw * 0.25) + float(i) * 5.0,
				(fp.y + time * edge_fall_speed * 0.6) / 22.0));
		float drop = clamp(max(down, 0.0) / edge_fall_reach, 0.0, 1.0);
		float thin = 1.0 - smoothstep(0.35, 1.0, drop);
		float cover = core * thin * smoothstep(-1.0, 1.5, down);
		float heat = cover * (0.35 + 0.65 * fine) * (0.55 + 0.45 * broad);
		vec3 hue = mix(edge_fall_cool, edge_fall_hot, clamp(heat * (1.15 - drop), 0.0, 1.0));
		acc.rgb += hue * heat * edge_fall_glow;
		acc.w = max(acc.w, cover);
	}
	return acc;
}
