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
void lay(float layer, vec2 uv, vec2 dx, vec2 dy, out vec3 a, out vec3 n) {
	if (!stochastic) {
		a = textureGrad(ground_albedo, vec3(uv, layer), dx, dy).rgb;
		n = textureGrad(ground_normal, vec3(uv, layer), dx, dy).xyz * 2.0 - 1.0;
		return;
	}
	// (An explicit level: this is called inside branches, where a sampler's own
	// derivatives are undefined and would speckle the branch's edge.)
	float l = textureLod(macro_noise, uv / stochastic_scale + layer * 0.137, 0.0).r * 8.0;
	float ia = floor(l);
	float f = fract(l);
	vec2 oa = sin(vec2(3.0, 7.0) * ia);
	vec2 ob = sin(vec2(3.0, 7.0) * (ia + 1.0));
	vec3 ca = textureGrad(ground_albedo, vec3(uv + oa, layer), dx, dy).rgb;
	vec3 cb = textureGrad(ground_albedo, vec3(uv + ob, layer), dx, dy).rgb;
	float b = smoothstep(0.2, 0.8, f - 0.1 * dot(ca - cb, vec3(1.0)));
	a = mix(ca, cb, b);
	vec3 na = textureGrad(ground_normal, vec3(uv + oa, layer), dx, dy).xyz;
	vec3 nb = textureGrad(ground_normal, vec3(uv + ob, layer), dx, dy).xyz;
	n = mix(na, nb, b) * 2.0 - 1.0;
}

