// THE SWELL ON STILL WATER, shared by the water's own surface (SHADER_water) and
// the lens that sits half in it (SHADER_underwater): both must put the surface at
// the same height, or the bed shows in a gap between the waterline and the water.
//
// Height of the swell at a point, 0..1 at a peak. A field of separate, irregular
// peaks (sharpened noise at two sizes) carried outward from the middle. The
// carrying is the flow-map trick: the field slides along the outward direction in
// two overlapping cycles, each fading out as it resets, so it moves for ever
// without stretching. A faint ring train under it keeps the sense of waves
// leaving the middle.
float swell_field(sampler2D noise, vec2 centre, float length_m, float pace, vec2 p, float t) {
	vec2 d = p - centre;
	float r = length(d);
	vec2 dir = d / max(r, 0.001);
	float reach = length_m * 2.2;
	float rate = pace / reach;
	float ph0 = fract(t * rate);
	float ph1 = fract(t * rate + 0.5);
	vec2 q0 = (p - dir * ph0 * reach) / length_m;
	vec2 q1 = (p - dir * ph1 * reach) / length_m + vec2(0.37, 0.61);
	float n0 = textureLod(noise, q0 * 0.21, 0.0).r * 0.65 + textureLod(noise, q0 * 0.57 + 0.3, 0.0).r * 0.35;
	float n1 = textureLod(noise, q1 * 0.21, 0.0).r * 0.65 + textureLod(noise, q1 * 0.57 + 0.3, 0.0).r * 0.35;
	float n = mix(n0, n1, abs(1.0 - 2.0 * ph0));
	float peaks = pow(smoothstep(0.3, 0.85, n), 1.7);
	float ring = pow(sin(r * 6.2832 / (length_m * 1.9) - t * pace * 0.5) * 0.5 + 0.5, 2.0);
	return clamp(peaks * 0.85 + ring * 0.15 * (0.4 + n), 0.0, 1.0);
}

// How far the surface stands over (or under) its level there, metres.
float swell_lift(float field, float height, float wind) {
	return (field - 0.35) * height * (0.6 + min(wind, 2.4));
}
