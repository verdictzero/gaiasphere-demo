// THE CLEARINGS ROUND WHAT IS PRINTED (docs/DOC_build_printer.md, "The clearing";
// the user: "in game add vegetation removal with a nice shoulder radius when stuff
// is built"). Every printed structure's footprint, published by BuildClearing
// (SCRIPT_build_clearing.gd) in RENDER space -- re-published on every floating-
// origin shift, the contract veg_burn_front and the buggy's pill keep -- as a
// column of a float texture: row 0 the footprint's rect (min x, min z, max x,
// max z), row 1 how far its clearing has come in (0 none, 1 whole: it grows in
// as the printer comes down, and out again after the structure is taken down).
//
// `build_clearing(p)` is how much of a plant standing at `p` (its foot, x and z)
// stays: 0 inside a footprint and for `build_clear_band.x` metres round it, 1
// past `build_clear_band.y`, and a smooth SHOULDER between. A vegetation shader
// takes it per INSTANCE, off the plant's undisplaced anchor, never per vertex:
//   * thinned: a plant stays whole or goes whole, with the shoulder's chance,
//     by a hash of where it stands, so the edge of a clearing is ragged and
//     natural rather than a ring;
//   * and shrunk: what is small (grass, ferns, bushes) stands lower the nearer
//     the footprint it is, as if trodden; trees are only thinned.
// No structures (`build_clear_count` 0, the rest state) is a single test.
global uniform sampler2D build_clear_rects : filter_nearest;
global uniform int build_clear_count;
global uniform vec4 build_clear_bounds;
global uniform vec2 build_clear_band;

const int BUILD_CLEAR_MAX = 64;

float build_clearing(vec2 p) {
	if (build_clear_count <= 0 || p.x < build_clear_bounds.x || p.y < build_clear_bounds.y
			|| p.x > build_clear_bounds.z || p.y > build_clear_bounds.w) {
		return 1.0;
	}
	float keep = 1.0;
	for (int i = 0; i < BUILD_CLEAR_MAX; i++) {
		if (i >= build_clear_count) {
			break;
		}
		vec4 r = texelFetch(build_clear_rects, ivec2(i, 0), 0);
		float s = texelFetch(build_clear_rects, ivec2(i, 1), 0).x;
		vec2 h = max((r.zw - r.xy) * 0.5, vec2(0.0));
		vec2 q = abs(p - (r.xy + r.zw) * 0.5) - h;
		// Signed distance to the footprint: negative inside it.
		float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
		keep = min(keep, mix(1.0, smoothstep(build_clear_band.x, build_clear_band.y, d), clamp(s, 0.0, 1.0)));
	}
	return keep;
}

// Whether a plant of clearing `keep` stays at all: by a hash of where it stands.
float build_clear_stays(vec2 p, float keep) {
	if (keep >= 1.0) {
		return 1.0;
	}
	float h = fract(sin(dot(p, vec2(41.37, 17.93))) * 43758.5453);
	return h < keep ? 1.0 : 0.0;
}

// How far a plant `height` metres tall that stays is shrunk: small ones lower
// the nearer they are, trees not at all.
float build_clear_shrink(float keep, float height) {
	return mix(mix(0.45, 1.0, keep), 1.0, smoothstep(2.5, 5.0, height));
}
