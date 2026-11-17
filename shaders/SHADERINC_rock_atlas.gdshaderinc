// THE ROCK CHANNEL AS AN ATLAS: three cliff faces in one texture, crossfaded on a
// slow world-space noise, sampled triplanar. Shared by `SHADER_terrain_splat_w2`
// and `SHADER_cliff_wall` so the shoulder and the wall under it draw the same
// face at the same place — the join between the two meshes is only invisible if
// both sides of it agree texel for texel.
//
// Off everywhere but island 002 (Malchut), whose cliffs are three sandstone faces
// packed by `tools/TOOL_build_cliff_atlas.py` into a 3 x 1 strip, and island 004,
// whose are three basalt faces drawn by `tools/TOOL_gen_lava_textures.py`. Three
// faces and not one so a cliff a kilometre round does not tile one picture on
// itself; one texture and not three for the sampler budget the road atlas
// already spells out.
//
// WHICH FACE is a value noise over world XZ, with Y folded in at a slant so the
// face also changes up a tall wall rather than only along it. The noise sits
// between about 0.25 and 0.75; across that the three cells hand over in turn, so
// most rock is one face and the crossfades are bands between.
//
// SIDE PROJECTIONS RUN Y DOWN THE PICTURE. The photographs are upright — the
// dark streaks are water that ran down the face — and a plain `world.zy` lookup
// puts higher ground lower in the image, which turns every streak into one that
// ran up the cliff.
//
// Gradients by hand, for `path_cell`'s reason: the cell coordinate jumps at every
// tile edge, and a mip chosen off that jump draws a seam down every one. Each
// projection's derivatives are taken once, unconditionally, before any branch.

float rock_atlas_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float rock_atlas_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = rock_atlas_hash(i);
	float b = rock_atlas_hash(i + vec2(1.0, 0.0));
	float c = rock_atlas_hash(i + vec2(0.0, 1.0));
	float d = rock_atlas_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 rock_atlas_cell(sampler2D atlas, vec2 uv, vec2 dx, vec2 dy, float cell) {
	vec2 size = vec2(1.0 / 3.0, 1.0);
	vec2 origin = vec2(cell * size.x, 0.0);
	vec2 inset = 0.5 / vec2(textureSize(atlas, 0));
	vec2 q = origin + clamp(fract(uv) * size, inset, size - inset);
	return textureGrad(atlas, q, dx * size, dy * size).rgb;
}

// One projection: the three faces, weighted, skipping any that contribute nothing.
vec3 rock_atlas_plane(sampler2D atlas, vec2 uv, vec2 dx, vec2 dy, vec3 cw) {
	vec3 c = vec3(0.0);
	if (cw.x > 0.0) { c += rock_atlas_cell(atlas, uv, dx, dy, 0.0) * cw.x; }
	if (cw.y > 0.0) { c += rock_atlas_cell(atlas, uv, dx, dy, 1.0) * cw.y; }
	if (cw.z > 0.0) { c += rock_atlas_cell(atlas, uv, dx, dy, 2.0) * cw.z; }
	return c;
}

// Triplanar rock off the atlas. `bw` is the caller's projection blend, `rs` its
// metres per tile, `vs` the variant noise's metres per cell.
vec3 rock_atlas_triplanar(sampler2D atlas, vec3 wp, vec3 bw, float rs, float vs) {
	vec2 ux = vec2(wp.z, -wp.y) / rs;
	vec2 uy = wp.xz / rs;
	vec2 uz = vec2(wp.x, -wp.y) / rs;
	vec2 dxx = dFdx(ux), dyx = dFdy(ux);
	vec2 dxy = dFdx(uy), dyy = dFdy(uy);
	vec2 dxz = dFdx(uz), dyz = dFdy(uz);
	float v = rock_atlas_noise((wp.xz + vec2(wp.y * 0.7, -wp.y * 0.4)) / max(vs, 1e-4));
	float t1 = smoothstep(0.36, 0.46, v);
	float t2 = smoothstep(0.54, 0.64, v);
	vec3 cw = vec3(1.0 - t1, t1 * (1.0 - t2), t2);
	vec3 c = vec3(0.0);
	if (bw.x > 0.01) { c += rock_atlas_plane(atlas, ux, dxx, dyx, cw) * bw.x; }
	if (bw.y > 0.01) { c += rock_atlas_plane(atlas, uy, dxy, dyy, cw) * bw.y; }
	if (bw.z > 0.01) { c += rock_atlas_plane(atlas, uz, dxz, dyz, cw) * bw.z; }
	return c / max((bw.x > 0.01 ? bw.x : 0.0) + (bw.y > 0.01 ? bw.y : 0.0)
			+ (bw.z > 0.01 ? bw.z : 0.0), 1e-5);
}
