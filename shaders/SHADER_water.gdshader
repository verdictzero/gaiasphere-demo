// WATER. One surface for the mere and the rivers, built from the pieces a good
// water system is made of:
//
//   depth      colour that runs from a clear shallow tint to a deep one, with the
//              red absorbed first, so the bed goes green, then blue, then dark
//   refraction what is under the surface is bent by the ripples, the colours a
//              hair apart at the edges
//   reflection Fresnel: looking down you see the bed, looking across the sky
//              and the sun's glitter (the engine's sky reflection and specular)
//   waves      a swell of separate peaks carried outward from the islet on the
//              mere, moving the surface itself; ripples in two layers on top,
//              growing with distance so the far water does not go flat
//   flow       on the rivers the ripples run downstream, faster on the hills
//   foam       where the water meets anything (shore, causeway, rock), lapping in
//              lines; on the crests of the swell; in streaks down the rapids
//   scatter    light coming through the crests toward you when the sun is low
//   edge       a soft blend where the water thins out to nothing
//
// The bright web on the bed (caustics) is drawn by the ground under it
// (SHADER_terrain), and the view from below by SHADER_underwater.
//
// What the mesh carries (SCRIPT_river_water.gd):
//   UV       metres down the river, signed metres across it
//   UV2      x: 0 mid-stream to 1 at the bank;  y: how much the water is running
//   COLOR    g fades the water out where a river leaves the island, b at its spring
//   TANGENT  downstream
//   CUSTOM0  y the share of a flat reach's pace this water covers a metre in
//            (1 over how many times faster it runs), z how fast it is going, 0..1
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, specular_schlick_ggx;

// No mipmaps on the screen: building them every frame is costly on a phone and
// this never reads below the top level.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

// Read by the mesher to lay the mere's rows out; kept so its numbers stand.
uniform float ripple_scale = 12.0;
uniform float ripple_stretch = 1.4;

group_uniforms depth_colour;
uniform vec3 shallow_color : source_color = vec3(0.07, 0.21, 0.19);
uniform vec3 deep_color : source_color = vec3(0.006, 0.04, 0.06);
// Metres of water you can see through.
uniform float clarity = 7.0;
// How fast each colour is lost with depth, red first.
uniform vec3 absorption = vec3(1.8, 0.95, 1.15);
// How much of the water's own colour hangs in it (0 = glass).
uniform float murk : hint_range(0.0, 1.0) = 0.5;

group_uniforms refraction;
uniform float refraction = 0.055;
uniform float chromatic : hint_range(0.0, 1.0) = 0.35;

group_uniforms ripples;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wave_size = 3.2;
uniform float wave_strength : hint_range(0.0, 2.0) = 0.6;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.03;
// Ripples are `1 + far_chop` times as strong by `far_distance` metres from the camera.
uniform float far_distance = 260.0;
uniform float far_chop = 0.5;
// Metres at which the ripples first double in size; they double again at each
// doubling of the distance.
uniform float far_step = 40.0;

group_uniforms swell;
// The middle of the mere (SCRIPT_bridge.gd sets it): the swell runs outward from it.
uniform vec2 mere_centre = vec2(0.0);
uniform sampler2D swell_noise : filter_linear_mipmap, repeat_enable;
uniform float wave_height = 0.42;
uniform float wave_length = 13.0;
uniform float wave_pace = 2.6;

group_uniforms flow;
uniform float flow_speed = 0.9;
// Seconds a copy of the ripples is carried before it starts again (see fragment).
uniform float flow_cycle : hint_range(1.0, 8.0) = 3.2;

group_uniforms foam;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 foam_color : source_color = vec3(0.86, 0.9, 0.88);
uniform float shore_foam = 1.6;         // metres of water the foam reaches out over
uniform float foam_strength : hint_range(0.0, 2.0) = 1.0;
uniform float crest_foam : hint_range(0.0, 1.0) = 0.75;
uniform float rapids_foam = 1.0;

group_uniforms scatter;
// Light through the crests, toward a low sun.
uniform vec3 scatter_color : source_color = vec3(0.1, 0.42, 0.33);
uniform float scatter_strength : hint_range(0.0, 3.0) = 1.1;
group_uniforms;

global uniform vec3 enviro_light_dir;
global uniform vec4 enviro_light_color;
global uniform vec4 enviro_ambient;
global uniform vec4 enviro_wind;
global uniform float enviro_wetness;
global uniform vec4 enviro_sky_zenith;
global uniform vec4 enviro_sky_horizon;

varying vec3 world_pos;
varying vec4 flow;

// Height of the swell at a point, 0..1 at a peak. A field of separate, irregular
// peaks (sharpened noise at two sizes) carried outward from the islet. The
// carrying is the flow-map trick: the field slides along the outward direction in
// two overlapping cycles, each fading out as it resets, so it moves for ever
// without stretching. A faint ring train under it keeps the sense of waves
// leaving the middle.
float swell(vec2 p, float t) {
	vec2 d = p - mere_centre;
	float r = length(d);
	vec2 dir = d / max(r, 0.001);
	float reach = wave_length * 2.2;
	float rate = wave_pace / reach;
	float ph0 = fract(t * rate);
	float ph1 = fract(t * rate + 0.5);
	vec2 q0 = (p - dir * ph0 * reach) / wave_length;
	vec2 q1 = (p - dir * ph1 * reach) / wave_length + vec2(0.37, 0.61);
	float n0 = textureLod(swell_noise, q0 * 0.21, 0.0).r * 0.65 + textureLod(swell_noise, q0 * 0.57 + 0.3, 0.0).r * 0.35;
	float n1 = textureLod(swell_noise, q1 * 0.21, 0.0).r * 0.65 + textureLod(swell_noise, q1 * 0.57 + 0.3, 0.0).r * 0.35;
	float n = mix(n0, n1, abs(1.0 - 2.0 * ph0));
	float peaks = pow(smoothstep(0.3, 0.85, n), 1.7);
	float ring = pow(sin(r * 6.2832 / (wave_length * 1.9) - t * wave_pace * 0.5) * 0.5 + 0.5, 2.0);
	return clamp(peaks * 0.85 + ring * 0.15 * (0.4 + n), 0.0, 1.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = CUSTOM0;
	float still = 1.0 - clamp(UV2.y, 0.0, 1.0);
	VERTEX.y += (swell(world_pos.xz, TIME) - 0.35) * wave_height * still * (0.6 + min(enviro_wind.z, 2.4));
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	vec4 p = inv_proj * vec4(uv * 2.0 - 1.0, texture(depth_tex, uv).r, 1.0);
	return -p.z / p.w;
}

void fragment() {
	float running = clamp(UV2.y, 0.0, 1.0);
	float still = 1.0 - running;
	float steep = clamp(flow.z, 0.0, 1.0) * running;
	float wind = enviro_wind.z;

	// ---- ripples: two layers of normal map, the river's in its own frame
	// FAR WATER HAS BIGGER RIPPLES, IN STEPS. The size doubles at fixed distances
	// and the two neighbouring sizes are cross-faded between them, the way mipmaps
	// are. (Scaling the pattern smoothly by each pixel's own distance made the whole
	// surface slide and shimmer whenever the camera moved: every pixel's scale was
	// changing under it.)
	float dist = length(VERTEX);
	float far = clamp(dist / far_distance, 0.0, 1.0);
	float level = max(log2(max(dist, 1.0) / far_step), 0.0);
	float size0 = exp2(floor(level));
	float size1 = size0 * 2.0;
	float blend = fract(level);
	float chop = wave_strength * (0.55 + 0.6 * wind + 0.9 * steep + 0.5 * enviro_wetness) * (1.0 + far_chop * far);
	// HOW FAST THIS WATER IS GOING, metres a second. The mesh carries the share of
	// a flat reach's pace it covers a metre in (CUSTOM0.y): a rapid at five times
	// the speed carries a fifth.
	float pace = flow_speed / clamp(flow.y, 0.12, 1.0);
	vec2 drift = enviro_wind.xy * TIME * 0.12;
	// THE RIPPLES ARE CARRIED DOWN THE RIVER AT THAT SPEED, WHICH CHANGES ALONG IT.
	// Sliding the pattern by speed x time does not survive that: where the speed
	// differs between two points the pattern between them is sheared a little more
	// every second, for ever, until a rapid is a smear. So it is carried the way a
	// flow map is: two copies, each sliding at the local speed for `flow_cycle`
	// seconds and then starting again, half a cycle apart, each faded out as it
	// resets. The shear is never more than half a cycle's worth, the pattern is
	// never stretched, and every stretch of water moves at its own speed.
	float cycle = TIME / flow_cycle + texture(foam_tex, world_pos.xz * 0.013).r * 0.6;
	float ph0 = fract(cycle);
	float ph1 = fract(cycle + 0.5);
	float keep0 = 1.0 - abs(1.0 - 2.0 * ph0);
	float slide0 = pace * (ph0 - 0.5) * flow_cycle;
	float slide1 = pace * (ph1 - 0.5) * flow_cycle;
	vec2 ru = vec2(UV.x - slide0, UV.y) / wave_size;
	vec2 rv = vec2(UV.x - slide1 + 5.3, UV.y + 2.9) / wave_size;
	vec2 ru2 = vec2(UV.x * 0.7 - slide0 * 1.6, UV.y * 0.7 + 3.1) / (wave_size * 0.43);
	vec2 rv2 = vec2(UV.x * 0.7 - slide1 * 1.6 + 1.7, UV.y * 0.7 + 6.4) / (wave_size * 0.43);
	vec2 su = (world_pos.xz + drift) / (wave_size * 1.7);
	vec2 su2 = (world_pos.zx * vec2(1.0, -1.0) - drift * 1.6) / (wave_size * 0.6);
	vec3 n_still = mix(texture(wave_a, su / size0).xyz + texture(wave_b, su2 / size0).xyz,
			texture(wave_a, su / size1).xyz + texture(wave_b, su2 / size1).xyz, blend);
	// (Running water is narrow and near: it takes the nearer ripple size only.)
	vec3 n_run = mix(texture(wave_a, rv / size0).xyz + texture(wave_b, rv2).xyz,
			texture(wave_a, ru / size0).xyz + texture(wave_b, ru2).xyz, keep0);
	vec3 n = mix(n_still, n_run, running) - 1.0;
	n = normalize(vec3(n.xy * chop, 1.0));

	// ---- the swell's own slope, by differences, and how near a crest this is
	float amp = wave_height * (0.6 + min(wind, 2.4)) * still;
	float h0 = swell(world_pos.xz, TIME);
	float hx = swell(world_pos.xz + vec2(0.35, 0.0), TIME);
	float hz = swell(world_pos.xz + vec2(0.0, 0.35), TIME);
	vec3 slope_w = normalize(vec3((h0 - hx) / 0.35 * amp, 1.0, (h0 - hz) / 0.35 * amp));
	vec3 lean = mat3(VIEW_MATRIX) * slope_w - mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0);
	float crest = smoothstep(0.5, 0.9, h0) * still;
	// WHITECAPS: the top of a peak breaks, and the foam it leaves trails down its
	// back (the side the wave has just passed, toward the islet).
	float tip = smoothstep(0.66, 0.92, h0) * still;
	vec2 back = normalize(mere_centre - world_pos.xz + vec2(1e-4));
	float trail = smoothstep(0.55, 0.9, swell(world_pos.xz - back * 1.6, TIME)) * still;

	// The surface's normal in view space: ripples in the mesh's frame, the swell on top.
	vec3 up = normalize(NORMAL);
	if (!FRONT_FACING) {
		up = -up;
	}
	vec3 nv = normalize(TANGENT * n.x + BINORMAL * n.y + up * n.z + lean * 1.3);
	vec3 view = normalize(VIEW);
	float facing = clamp(dot(nv, view), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);

	// ---- what is under the surface, bent by it
	float surface_z = -VERTEX.z;
	float thick = max(linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX) - surface_z, 0.0);
	vec2 bend = n.xy * refraction * clamp(thick, 0.0, 1.0) / (1.0 + surface_z * 0.08);
	vec2 bent = SCREEN_UV + bend;
	float thick_bent = linear_depth(bent, INV_PROJECTION_MATRIX) - surface_z;
	if (thick_bent < 0.0) {
		bent = SCREEN_UV;            // never pull something in front of the water into it
		bend = vec2(0.0);
	} else {
		thick = thick_bent;
	}
	vec3 behind = vec3(texture(screen_tex, bent + bend * chromatic).r,
			texture(screen_tex, bent).g, texture(screen_tex, bent - bend * chromatic).b);

	// ---- depth: absorption, and the water's own colour
	vec3 through = exp(-thick / clarity * absorption);
	float daylight = clamp(enviro_light_dir.y, 0.0, 1.0);
	vec3 light = enviro_ambient.rgb * 1.6 + enviro_light_color.rgb * daylight * 0.8;
	vec3 body = mix(deep_color, shallow_color, exp(-thick / (clarity * 0.6))) * light;
	vec3 under = behind * through + body * (1.0 - through) * murk;

	// ---- scatter: a low sun lights the crests from behind, toward the eye
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(view, 0.0)).xyz);
	vec3 sun_flat = normalize(vec3(enviro_light_dir.x, 0.0, enviro_light_dir.z) + vec3(1e-4));
	float through_crest = pow(max(dot(-view_w, sun_flat), 0.0), 3.0) * (0.25 + 0.75 * crest);
	under += scatter_color * enviro_light_color.rgb * through_crest * scatter_strength * (0.3 + h0) * still * 0.5;
	under *= 1.0 - fresnel * 0.85;
	// THE SKY IN THE WATER, worked out here: the colour of the sky in the direction
	// the surface throws the eye. (Not the engine's sky cubemap: see SCRIPT_enviro.gd.)
	vec3 n_w = normalize((INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz);
	vec3 thrown = reflect(-view_w, n_w);
	vec3 sky_seen = mix(enviro_sky_horizon.rgb, enviro_sky_zenith.rgb, pow(clamp(thrown.y, 0.0, 1.0), 0.45));
	under += sky_seen * fresnel * 0.9;

	// ---- foam
	float grain_run = mix(texture(foam_tex, vec2(UV.x * 0.5 - slide1 * 0.5 + 0.4, UV.y * 0.5 + 0.7)).r,
			texture(foam_tex, vec2(UV.x * 0.5 - slide0 * 0.5, UV.y * 0.5)).r, keep0);
	float grain = mix(texture(foam_tex, world_pos.xz * 0.35).r, grain_run, running);
	float fine = texture(foam_tex, world_pos.xz * 1.3 + vec2(TIME * 0.03, -TIME * 0.02)).r;
	// Where the water meets anything: a solid line at the very edge, then a broken
	// band behind it with lines that lap in and out. It comes from how little
	// water lies in front of what is behind the surface, so whatever stands in the
	// water gets it without being told.
	float near = 1.0 - smoothstep(0.0, shore_foam, thick);
	// Three bands come in to the shore one after another and die there; between
	// them the foam they left thins out into lace.
	float run_in = thick / shore_foam * 2.6 + TIME * 0.55 + grain * 0.9;
	float wave_in = pow(1.0 - abs(fract(run_in) * 2.0 - 1.0), 3.0);
	float wash = near * near * smoothstep(0.48, 0.7, fine * 0.55 + grain * 0.45 + near * 0.12);
	float band = near * wave_in * smoothstep(0.4, 0.68, fine * 0.7 + grain * 0.3 + near * 0.15);
	float line = 1.0 - smoothstep(0.0, shore_foam * 0.045, thick + (fine - 0.5) * 0.06);
	float shore = clamp((max(line, band) + wash * 0.6) * foam_strength, 0.0, 1.0);
	// White water: none on a gentle run, broken streaks as it quickens, and never a
	// solid sheet even flat out (the threshold the foam texture has to clear comes
	// down with the speed, it does not vanish).
	float white = smoothstep(0.3, 1.0, steep * rapids_foam);
	float rapids = white * 0.85 * smoothstep(mix(0.72, 0.5, white), mix(0.9, 0.78, white), grain);
	// On the crests: broken by the foam texture, a little always, more in a wind.
	float lace = smoothstep(0.38, 0.62, fine * 0.6 + grain * 0.4);        // foam is holes and strands, not a sheet
	// Gusts: whitecaps come in patches tens of metres across that drift, not everywhere.
	float gust = smoothstep(0.42, 0.68, texture(swell_noise, world_pos.xz * 0.006 + enviro_wind.xy * TIME * 0.004).r);
	float whitecap = crest_foam * (tip * smoothstep(0.25, 0.6, lace + tip * 0.5) + trail * 0.45 * lace) * (0.55 + 0.7 * wind) * (0.12 + 0.88 * gust);
	float foam = clamp(shore + rapids + whitecap, 0.0, 1.0);

	ALBEDO = foam_color * foam;
	EMISSION = under * (1.0 - foam);
	// Rougher with distance: a mirror-smooth surface of ripples too small to see
	// sparkles and crawls, worst of all at a phone's half resolution.
	ROUGHNESS = mix(surface_roughness + 0.22 * far, 0.75, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	NORMAL = nv;
	// A soft edge where the water meets the bank, and where a river ends.
	ALPHA = smoothstep(0.0, 0.02, thick) * clamp(COLOR.g, 0.0, 1.0) * clamp(COLOR.b, 0.0, 1.0);
}
