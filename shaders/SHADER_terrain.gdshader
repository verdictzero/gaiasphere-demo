// THE GROUND: a lit, physically shaded blend of scanned surfaces. The mesher
// (SCRIPT_chunk_mesher.gd) writes what the ground is made of into each vertex:
//
//   COLOR   r moss and grass, g soil, b rock, a sand
//   UV2.x   +forest litter   or   -river band (1 at the middle of the bed)
//   UV2.y   +trail
//   UV.y    the river's code; kind 2 is the mere, whose shores are beaches
//
// There are no texture coordinates: every layer is laid from above in world
// metres, and rock, which lives on the steep faces, from three sides.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trail_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bed_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bed_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Large soft patches: breaks the tiling and varies how damp the ground looks.
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

// Metres covered by one tile of each layer.
uniform float moss_size = 3.2;
uniform float soil_size = 2.6;
uniform float litter_size = 2.8;
uniform float trail_size = 3.0;
uniform float sand_size = 2.4;
uniform float bed_size = 2.2;
uniform float rock_size = 5.0;
uniform vec3 moss_tint : source_color = vec3(0.5, 0.66, 0.3);
uniform vec3 soil_tint : source_color = vec3(0.8, 0.78, 0.72);
uniform vec3 litter_tint : source_color = vec3(0.85, 0.8, 0.72);
uniform vec3 trail_tint : source_color = vec3(0.8, 0.76, 0.7);
uniform vec3 sand_tint : source_color = vec3(0.7, 0.68, 0.62);
uniform vec3 bed_tint : source_color = vec3(0.6, 0.62, 0.58);
// Dry sand on the mere's beaches, as a multiple of the (damp, dark) sand scan.
uniform vec3 beach_tint : source_color = vec3(2.3, 2.05, 1.6);
uniform vec3 rock_tint : source_color = vec3(0.85, 0.88, 0.86);
// The scans are dark; this lifts the whole ground.
uniform float brightness = 1.7;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 6.0;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.45;
// Detail normals fade out by this distance: they are noise beyond it.
uniform float detail_distance = 140.0;

// The causeway across the mere: a line (xz to xz) and half its cobbled width.
uniform sampler2D cobble_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 causeway = vec4(0.0);
uniform float causeway_half = 0.0;
uniform float cobble_size = 2.2;
uniform vec3 cobble_tint : source_color = vec3(0.9, 0.9, 0.86);

global uniform float enviro_wetness;

vec3 udn(sampler2D tex, vec2 uv) {
	return texture(tex, uv).xyz * 2.0 - 1.0;
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 geo_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (!FRONT_FACING) {
		geo_n = -geo_n;
	}
	vec2 p = world_pos.xz;
	float dist = length(VERTEX);
	float detail = (1.0 - smoothstep(detail_distance * 0.5, detail_distance, dist)) * normal_strength;

	vec4 w = max(COLOR, vec4(0.0));
	w /= max(w.r + w.g + w.b + w.a, 1e-4);
	float forest = clamp(UV2.x, 0.0, 1.0);
	float trail = clamp(UV2.y, 0.0, 1.0);
	float river = clamp(-UV2.x, 0.0, 1.0);
	float macro = texture(macro_noise, p / 97.0).r;
	float macro2 = texture(macro_noise, p / 23.0 + 0.31).r;

	// Moss under trees gives way to needle litter in ragged patches.
	float litter_mix = clamp(forest * (0.25 + macro2 * 1.1) * smoothstep(0.25, 0.6, macro + macro2 * 0.5), 0.0, 1.0);
	vec3 moss_a = texture(moss_albedo, p / moss_size).rgb * moss_tint;
	vec3 soil_a = texture(soil_albedo, p / soil_size).rgb * soil_tint;
	vec3 litter_a = texture(litter_albedo, p / litter_size).rgb * litter_tint;
	vec3 trail_a = texture(trail_albedo, p / trail_size).rgb * trail_tint;
	vec3 sand_a = texture(sand_albedo, p / sand_size).rgb * sand_tint;
	vec3 moss_n = udn(moss_normal, p / moss_size);
	vec3 soil_n = udn(soil_normal, p / soil_size);
	vec3 litter_n = udn(litter_normal, p / litter_size);
	vec3 trail_n = udn(trail_normal, p / trail_size);
	vec3 sand_n = udn(sand_normal, p / sand_size);

	vec3 ground_a = mix(moss_a, litter_a, litter_mix * 0.8);
	vec3 ground_n = mix(moss_n, litter_n, litter_mix * 0.8);
	vec3 earth_a = mix(mix(soil_a, litter_a, forest), trail_a, trail);
	vec3 earth_n = mix(mix(soil_n, litter_n, forest), trail_n, trail);

	// Rock, from three sides, with the planes' gradients taken outside the branch.
	vec3 bw = pow(abs(geo_n), vec3(triplanar_sharpness));
	bw /= bw.x + bw.y + bw.z;
	vec3 rp = world_pos / rock_size;
	vec3 rock_a = vec3(0.0);
	vec3 rock_world_n = geo_n;
	vec2 dzy_x = dFdx(rp.zy); vec2 dzy_y = dFdy(rp.zy);
	vec2 dxz_x = dFdx(rp.xz); vec2 dxz_y = dFdy(rp.xz);
	vec2 dxy_x = dFdx(rp.xy); vec2 dxy_y = dFdy(rp.xy);
	// The riverbanks are rock too.
	float at = 3.0 * (1.0 - river);
	float bank_w = river > 0.0 ? smoothstep(0.7, 0.95, at) * (1.0 - smoothstep(1.7, 2.1, at)) : 0.0;
	float bed_w = river > 0.0 ? 1.0 - smoothstep(0.82, 1.0, at) : 0.0;
	float kind = floor((-UV.y - 1.0) / 10000.0);
	bool mere = kind > 1.5;
	if (mere) {
		bank_w = 0.0;
	}
	float rock_w = max(w.b, bank_w);
	if (rock_w > 0.003) {
		rock_a = (textureGrad(rock_albedo, rp.zy, dzy_x, dzy_y).rgb * bw.x
				+ textureGrad(rock_albedo, rp.xz, dxz_x, dxz_y).rgb * bw.y
				+ textureGrad(rock_albedo, rp.xy, dxy_x, dxy_y).rgb * bw.z) * rock_tint;
		vec3 tx = textureGrad(rock_normal, rp.zy, dzy_x, dzy_y).xyz * 2.0 - 1.0;
		vec3 ty = textureGrad(rock_normal, rp.xz, dxz_x, dxz_y).xyz * 2.0 - 1.0;
		vec3 tz = textureGrad(rock_normal, rp.xy, dxy_x, dxy_y).xyz * 2.0 - 1.0;
		vec3 nx = vec3(tx.xy * detail + geo_n.zy, abs(tx.z) * geo_n.x);
		vec3 ny = vec3(ty.xy * detail + geo_n.xz, abs(ty.z) * geo_n.y);
		vec3 nz = vec3(tz.xy * detail + geo_n.xy, abs(tz.z) * geo_n.z);
		rock_world_n = normalize(nx.zyx * bw.x + ny.xzy * bw.y + nz.xyz * bw.z);
	}

	vec3 albedo = ground_a * w.r + earth_a * w.g + rock_a * w.b + sand_a * w.a;
	vec3 flat_n = ground_n * w.r + earth_n * w.g + sand_n * w.a;
	float roughness = 0.94 * w.r + 0.9 * w.g + 0.82 * w.b + 0.88 * w.a;

	// The river: pebbles on the bed, rock on the banks, silt above them.
	float damp = 0.0;
	if (river > 0.0) {
		vec2 bp = p / bed_size;
		vec3 bed_a = textureGrad(bed_albedo, bp, dFdx(bp), dFdy(bp)).rgb * bed_tint;
		vec3 bed_nn = textureGrad(bed_normal, bp, dFdx(bp), dFdy(bp)).xyz * 2.0 - 1.0;
		if (mere) {
			bed_a = mix(sand_a, bed_a, 0.35);
		}
		float scour_w = smoothstep(1.7, 2.1, at) * (1.0 - smoothstep(2.5, 2.95, at)) * (1.0 - w.b);
		if (mere) {
			// THE MERE'S SHORES ARE SAND: pale and dry up the beach, darkening to wet
			// at the water's edge, with a ragged upper edge where the turf begins.
			float beach = smoothstep(0.0, 0.3, river + (macro2 - 0.5) * 0.12);
			float wet_line = smoothstep(0.45, 0.75, river);
			albedo = mix(albedo, sand_a * beach_tint * mix(1.0, 0.55, wet_line), beach);
			flat_n = mix(flat_n, sand_n, beach);
			roughness = mix(roughness, mix(0.9, 0.45, wet_line), beach);
			scour_w = 0.0;
		}
		albedo = mix(albedo, soil_a * 0.8, scour_w * 0.8);
		albedo = mix(albedo, rock_a, bank_w);
		albedo = mix(albedo, bed_a, bed_w);
		flat_n = mix(flat_n, bed_nn, bed_w) * (1.0 - bank_w);
		damp = clamp(bed_w + bank_w * 0.8 + scour_w * 0.6, 0.0, 1.0);
		roughness = mix(roughness, 0.55, damp);
	}

	float keep = 1.0 - max(w.b, bank_w);
	vec3 world_n = normalize(geo_n + vec3(flat_n.x, 0.0, flat_n.y) * detail * keep);
	world_n = normalize(mix(world_n, rock_world_n, max(w.b, bank_w)));

	if (causeway_half > 0.0) {
		vec2 ab = causeway.zw - causeway.xy;
		float t = clamp(dot(p - causeway.xy, ab) / dot(ab, ab), 0.0, 1.0);
		float off = length(p - causeway.xy - ab * t);
		// A ragged edge: the stones give out into the bank unevenly.
		float cw = 1.0 - smoothstep(causeway_half - 0.5, causeway_half + 0.9, off + (macro2 - 0.5) * 1.6);
		if (cw > 0.0) {
			// Laid ALONG the path: the texture's v runs down the causeway and its u
			// across, so the courses of stone follow the way you walk.
			vec2 run = normalize(ab);
			vec2 across = vec2(-run.y, run.x);
			vec2 rel = p - causeway.xy;
			vec2 cp = vec2(dot(rel, across), dot(rel, run)) / cobble_size;
			albedo = mix(albedo, textureGrad(cobble_albedo, cp, dFdx(cp), dFdy(cp)).rgb * cobble_tint, cw);
			vec3 cn = textureGrad(cobble_normal, cp, dFdx(cp), dFdy(cp)).xyz * 2.0 - 1.0;
			vec2 tilt = across * cn.x + run * cn.y;          // the normal map, turned with it
			world_n = normalize(mix(world_n, normalize(geo_n + vec3(tilt.x, 0.0, tilt.y) * detail * 1.4), cw));
			roughness = mix(roughness, 0.8, cw);
		}
	}
	albedo *= mix(1.0, 0.62 + macro * 0.5 + macro2 * 0.26, macro_strength);
	// Wet ground is darker and shinier; rain soaks the hollows of the noise first.
	float wet = clamp(max(damp, enviro_wetness * (0.55 + macro2 * 0.9)), 0.0, 1.0);
	albedo *= mix(1.0, 0.6, wet);
	roughness = mix(roughness, 0.28, wet * 0.85);

	ALBEDO = albedo * brightness;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.4;
	NORMAL = normalize(mat3(VIEW_MATRIX) * world_n);
}
