// HOW THE GROUND'S SURFACES ARE LAID, shared by everything that draws the ground
// or has to match it: SHADER_terrain.gdshader, and SHADER_cliff_rock.gdshader for
// the tops of the rocks the ground runs on over. Include it after declaring
//   uniform sampler2DArray ground_albedo, ground_normal;
//   uniform sampler2D macro_noise;
//   uniform bool stochastic;  uniform float stochastic_scale;
// (The layer numbers are tools/build_ground_arrays.py's order.)

// THE WOOD'S CLEARINGS, worked out exactly as Flora works them out
// (SCRIPT_flora.gd's `wood_zones`, in the same 32-bit arithmetic), so the bare
// leafy floor is exactly where it leaves the ground bare.
float hash32(int x, int z, int salt) {
	uint h = (uint(x) * 73856093u) ^ (uint(z) * 19349663u) ^ (uint(salt) * 83492791u);
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return float(h & 0xFFFFFFu) / 16777216.0;
}

float noise32(vec2 q, int salt) {
	vec2 i = floor(q);
	vec2 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	int ix = int(i.x);
	int iz = int(i.y);
	return mix(mix(hash32(ix, iz, salt), hash32(ix + 1, iz, salt), f.x),
			mix(hash32(ix, iz + 1, salt), hash32(ix + 1, iz + 1, salt), f.x), f.y);
}

float wood_clearing(vec2 p) {
	return smoothstep(0.69, 0.77, noise32(p / 30.0, 82) * 0.75 + noise32(p / 9.0, 84) * 0.25);
}

// ONE SURFACE, LAID WITHOUT A REPEAT YOU CAN SEE (stochastic sampling, after
// Inigo Quilez's "texture repetition"): a slow noise picks, tile by tile, which
// of eight offset copies of the picture is laid, and two neighbouring copies are
// cross-faded where it changes, the seam following the picture's own light and
// dark. Colour into `a`, the unpacked normal into `n`. `dx`, `dy`: the uv's
// screen derivatives, taken outside any branch.
// FAR OFF IT IS LAID MORE CHEAPLY, in two ways, each with its own distance (0:
// never, laid in full everywhere):
//   `normal_reach`      past this the surface's normal map is not read at all.
//                       (The ground's relief has already faded out by its
//                       `detail_distance`, so at that distance nothing changes.)
//   `stochastic_reach`  past this one copy of the picture is laid, the one that
//                       has the larger share there, in place of two cross-faded:
//                       a repeat that far off is too small to see.
// `dist` is how far the pixel is from the eye, metres.
uniform float normal_reach = 140.0;
uniform float stochastic_reach = 90.0;

void lay(float layer, vec2 uv, vec2 dx, vec2 dy, float dist, out vec3 a, out vec3 n) {
	bool relief = normal_reach <= 0.0 || dist < normal_reach;
	n = vec3(0.0, 0.0, 1.0);
	if (!stochastic) {
		a = textureGrad(ground_albedo, vec3(uv, layer), dx, dy).rgb;
		if (relief) {
			n = textureGrad(ground_normal, vec3(uv, layer), dx, dy).xyz * 2.0 - 1.0;
		}
		return;
	}
	// (An explicit level: this is called inside branches, where a sampler's own
	// derivatives are undefined and would speckle the branch's edge.)
	float l = textureLod(macro_noise, uv / stochastic_scale + layer * 0.137, 0.0).r * 8.0;
	float ia = floor(l);
	float f = fract(l);
	vec2 oa = sin(vec2(3.0, 7.0) * ia);
	vec2 ob = sin(vec2(3.0, 7.0) * (ia + 1.0));
	if (stochastic_reach > 0.0 && dist >= stochastic_reach) {
		vec2 o = f < 0.5 ? oa : ob;
		a = textureGrad(ground_albedo, vec3(uv + o, layer), dx, dy).rgb;
		if (relief) {
			n = textureGrad(ground_normal, vec3(uv + o, layer), dx, dy).xyz * 2.0 - 1.0;
		}
		return;
	}
	vec3 ca = textureGrad(ground_albedo, vec3(uv + oa, layer), dx, dy).rgb;
	vec3 cb = textureGrad(ground_albedo, vec3(uv + ob, layer), dx, dy).rgb;
	float b = smoothstep(0.2, 0.8, f - 0.1 * dot(ca - cb, vec3(1.0)));
	a = mix(ca, cb, b);
	if (relief) {
		vec3 na = textureGrad(ground_normal, vec3(uv + oa, layer), dx, dy).xyz;
		vec3 nb = textureGrad(ground_normal, vec3(uv + ob, layer), dx, dy).xyz;
		n = mix(na, nb, b) * 2.0 - 1.0;
	}
}



// STRATA: the beds the island's rock is laid down in, drawn on its SIDES ONLY (a
// face that looks up or down has none), and GLOBAL: they are a function of where
// a point is in the world and nothing else, so a bed runs on unbroken from one
// block of cliff to the next and across the terrain's own rock between them.
// Each bed is `strata_bed` metres thick, has a tone of its own, a dark parting
// where it meets the next, and fine laminae within; the whole stack dips a
// little (`strata_dip`) and wanders (`strata_warp`, by a noise laid on from the
// two sides), so the lines are not ruled. Past a couple of hundred metres the
// partings and laminae fade (they would only shimmer) and the beds' tones stay.
uniform float strata_strength : hint_range(0.0, 1.5) = 0.85;
uniform float strata_bed = 1.9;
uniform float strata_warp = 1.6;
uniform vec2 strata_dip = vec2(0.035, 0.018);

// x: what to multiply the rock's colour by; y: how far to tip its normal up (+)
// or down (-) for the parting's groove.
vec2 strata_at(vec3 wp, vec3 n, float dist) {
	float side = 1.0 - smoothstep(0.45, 0.8, abs(n.y));
	if (side <= 0.0 || strata_strength <= 0.0) {
		return vec2(1.0, 0.0);
	}
	vec2 sw = n.xz * n.xz;
	sw /= sw.x + sw.y + 1e-4;
	float warp = textureLod(macro_noise, wp.zy / 41.0, 0.0).r * sw.x + textureLod(macro_noise, wp.xy / 41.0, 0.0).r * sw.y;
	float y = (wp.y + (warp - 0.5) * strata_warp + dot(wp.xz, strata_dip)) / strata_bed;
	float id = floor(y);
	float f = fract(y);
	float h = fract(sin(id * 12.9898) * 43758.5453);
	float fine = 1.0 - smoothstep(60.0, 220.0, dist);
	float parting = (1.0 - smoothstep(0.0, 0.05 + 0.09 * h, min(f, 1.0 - f))) * fine;
	float laminae = 0.5 + 0.5 * sin(y * 6.2832 * (5.0 + 4.0 * h) + h * 6.0);
	float tone = mix(0.78, 1.16, h) * mix(1.0, 0.9 + 0.1 * laminae, fine);
	float k = side * strata_strength;
	return vec2(mix(1.0, tone * (1.0 - parting * 0.55), k), (f < 0.5 ? 1.0 : -1.0) * parting * k * 0.8);
}


// COLOURED STRATA: a second set of beds, apart from the lines above and with a
// thickness of its own, that COLOUR the rock's sides: bands of rust, ochre,
// cream, plum and umber by height in the world, as in painted cliffs. Global
// and sides only, like the others, and following the same dip and wander, so
// the two sets lie parallel. The rock keeps its own light and dark; only its
// hue is taken toward the band's (`strata_colour` is how far).
uniform float strata_colour : hint_range(0.0, 1.0) = 0.5;
uniform float strata_colour_bed = 5.5;
uniform vec3 strata_colour_a : source_color = vec3(0.62, 0.27, 0.16);
uniform vec3 strata_colour_b : source_color = vec3(0.76, 0.56, 0.26);
uniform vec3 strata_colour_c : source_color = vec3(0.85, 0.78, 0.62);
uniform vec3 strata_colour_d : source_color = vec3(0.45, 0.36, 0.42);
uniform vec3 strata_colour_e : source_color = vec3(0.33, 0.22, 0.16);

vec3 strata_band(float id) {
	float h = fract(sin(id * 78.233 + 4.1) * 43758.5453) * 5.0;
	if (h < 1.0) { return strata_colour_a; }
	if (h < 2.0) { return strata_colour_b; }
	if (h < 3.0) { return strata_colour_c; }
	if (h < 4.0) { return strata_colour_d; }
	return strata_colour_e;
}

// The rock's colour `rock` with the coloured beds laid into it.
vec3 strata_coloured(vec3 rock, vec3 wp, vec3 n) {
	float side = 1.0 - smoothstep(0.45, 0.8, abs(n.y));
	if (side <= 0.0 || strata_colour <= 0.0) {
		return rock;
	}
	vec2 sw = n.xz * n.xz;
	sw /= sw.x + sw.y + 1e-4;
	float warp = textureLod(macro_noise, wp.zy / 41.0, 0.0).r * sw.x + textureLod(macro_noise, wp.xy / 41.0, 0.0).r * sw.y;
	// (Beds of uneven thickness: the height itself is bent a little as it climbs.)
	float y = (wp.y + (warp - 0.5) * strata_warp * 1.5 + dot(wp.xz, strata_dip)) / strata_colour_bed;
	y += 0.35 * sin(y * 1.7) + 0.2 * sin(y * 4.3 + 1.0);
	float id = floor(y);
	float f = fract(y);
	// One band into the next over a short, soft join.
	vec3 band = mix(strata_band(id), strata_band(id + 1.0), smoothstep(0.82, 1.0, f));
	float light = dot(rock, vec3(0.3, 0.55, 0.15));
	return mix(rock, band * light * 2.4, side * strata_colour);
}
