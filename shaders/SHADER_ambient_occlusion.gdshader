// AMBIENT OCCLUSION, in screen space, as one pass over the finished frame: the
// Mobile renderer has none of its own. Everything is worked out from the depth
// buffer (there is no normal buffer on this renderer: normals are rebuilt from
// the depth's own slope), and the result MULTIPLIES what is on screen, so
// creases, the feet of things and the insides of cracks go darker.
//
// THREE WAYS OF DOING IT (`method`), cheapest first:
//   1  FAST   depth only: a ring of taps round the pixel; whatever stands nearer
//             the eye than the pixel does, within the radius, shuts it in.
//             A handful of depth reads and no geometry at all.
//   2  SSAO   points scattered over the hemisphere above the pixel's surface,
//             each tested against the depth there: the classic.
//   3  HBAO   horizon-based: marches out along a few directions on screen and
//             finds how high the horizon stands over the surface in each.
//             The most faithful, and the most reads.
// All three share the radius, intensity, contrast, bias, falloff and distance
// settings; SCRIPT_ambient_occlusion.gd sets them (the options panel's sliders).
shader_type spatial;
render_mode unshaded, blend_mul, depth_test_disabled, depth_draw_never, cull_disabled,
		shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform int method = 1;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
// Metres round a point that can shut it in, and how much that grows with every
// metre of distance (0: the same everywhere; more: broad shade far off).
uniform float radius = 1.0;
uniform float radius_growth = 0.02;
// Contrast: over 1 deepens the dark and clears the light.
uniform float power : hint_range(0.25, 6.0) = 1.5;
// How far (metres, at one metre off; it scales with distance) a thing must stand
// over the surface to count: stops flat ground shading itself.
uniform float bias = 0.03;
// How quickly something further off in depth than the radius stops counting.
uniform float falloff : hint_range(0.1, 4.0) = 1.0;
// Past this (metres) there is none, easing out over the last `fade` share of it.
uniform float max_distance = 160.0;
uniform float fade : hint_range(0.01, 1.0) = 0.35;
// The darkest it may make anything (0 black, 1 no effect), and the shade's tint.
uniform float floor_light : hint_range(0.0, 1.0) = 0.15;
uniform vec3 tint : source_color = vec3(0.0);
// Taps: FAST and SSAO take `samples`; HBAO `directions` x `steps`.
uniform int samples = 8;
uniform int directions = 6;
uniform int steps = 4;
// HBAO: the horizon must stand this far (sine) over the surface to count.
uniform float horizon_bias : hint_range(0.0, 0.5) = 0.1;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// 1 on the screen, 0 off it: a tap past the edge reads the edge's depth, which is
// no evidence of anything, and must not count.
float on_screen(vec2 uv) {
	return step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
}

vec3 view_at(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

void fragment() {
	if (method <= 0 || intensity <= 0.001) {
		discard;
	}
	vec2 uv = SCREEN_UV;
	float raw = textureLod(depth_tex, uv, 0.0).r;
	// (Reversed depth: the sky is at 0.)
	if (raw <= 0.000001) {
		discard;
	}
	vec3 p = view_at(uv, INV_PROJECTION_MATRIX);
	float dist = -p.z;
	float far = 1.0 - smoothstep(max_distance * (1.0 - fade), max_distance, dist);
	if (far <= 0.0) {
		discard;
	}
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float r = radius + radius_growth * dist;
	// The radius on screen, in uv.
	vec2 ruv = r * vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]) * 0.5 / max(dist, 0.05);
	float spin = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) * 6.2832;
	float shut = 0.0;

	if (method == 1) {
		// FAST: depth only. A tap counts by how far nearer the eye it stands than
		// the pixel, up to the radius, and not at all once it is well beyond it
		// (something in front of the scene, not round this point).
		float lean = bias * dist + 0.02;
		for (int i = 0; i < samples; i++) {
			float a = spin + float(i) * 2.39996;
			float t = (float(i) + 0.5) / float(samples);
			vec2 o = vec2(cos(a), sin(a)) * sqrt(t) * ruv;
			float nearer = dist + view_at(uv + o, INV_PROJECTION_MATRIX).z - lean;
			shut += clamp(nearer / r, 0.0, 1.0) * (1.0 - smoothstep(r, r * (1.0 + 2.0 / falloff), nearer)) * on_screen(uv + o);
		}
		shut = shut / float(samples) * 1.7;
	} else {
		// The surface's normal, from the depth round it: the shorter step each way,
		// so an edge does not smear the far side's slope into the near.
		vec3 px1 = view_at(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX) - p;
		vec3 px0 = p - view_at(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
		vec3 py1 = view_at(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX) - p;
		vec3 py0 = p - view_at(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
		vec3 dx = abs(px1.z) < abs(px0.z) ? px1 : px0;
		vec3 dy = abs(py1.z) < abs(py0.z) ? py1 : py0;
		vec3 n = normalize(cross(dx, dy));
		if (n.z < 0.0) {
			n = -n;
		}
		if (method == 2) {
			// SSAO: points over the hemisphere, nearer the surface more often.
			vec3 t1 = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
			vec3 t2 = cross(n, t1);
			for (int i = 0; i < samples; i++) {
				float t = (float(i) + 0.5) / float(samples);
				float a = spin + float(i) * 2.39996;
				float up = sqrt(1.0 - t);
				float out_ = sqrt(t);
				vec3 dir = t1 * (cos(a) * out_) + t2 * (sin(a) * out_) + n * up;
				vec3 s = p + dir * r * mix(0.25, 1.0, t * t);
				vec4 c = PROJECTION_MATRIX * vec4(s, 1.0);
				vec2 suv = c.xy / c.w * 0.5 + 0.5;
				float scene = view_at(suv, INV_PROJECTION_MATRIX).z;
				float range = smoothstep(0.0, 1.0, r * falloff / max(abs(p.z - scene), 0.0001));
				shut += step(s.z + bias * dist + 0.01, scene) * range * on_screen(suv);
			}
			shut = shut / float(samples) * 1.6;
		} else {
			// HBAO: the horizon's height over the surface, along each direction.
			for (int d = 0; d < directions; d++) {
				float a = spin + float(d) * 6.2832 / float(directions);
				vec2 along = vec2(cos(a), sin(a)) * ruv / float(steps);
				float top = horizon_bias;
				float seen = 0.0;
				for (int k = 1; k <= steps; k++) {
					vec2 huv = uv + along * (float(k) - 0.5 + fract(spin * 3.7) * 0.5);
					if (on_screen(huv) < 0.5) {
						break;
					}
					vec3 h = view_at(huv, INV_PROJECTION_MATRIX) - p;
					float len = length(h);
					float rise = dot(h, n) / max(len, 0.0001);
					if (rise > top) {
						float reach = clamp(1.0 - (len * len) / (r * r * (1.0 + 1.0 / falloff)), 0.0, 1.0);
						seen += (rise - top) * reach;
						top = rise;
					}
				}
				shut += seen;
			}
			shut = shut / float(directions) * 1.4;
		}
	}
	float ao = pow(clamp(1.0 - shut * intensity, 0.0, 1.0), power);
	ao = max(mix(1.0, ao, far), floor_light);
	// (The Mobile renderer keeps its picture at half brightness, to have room over
	// white, and halves whatever a shader writes: a multiplier of one has to be
	// written as two, or the pass dims the whole frame by half.)
	ALBEDO = mix(tint, vec3(1.0), ao) * 2.0;
}
