shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/SHADERINC_island_light.gdshaderinc"

// THE RIVERS' WATER (island 006's; the user: "Give me spline based rivers with
// sandy bottoms and rocky edges, and beautiful but still retro looking water
// shaders"). Drawn on `RiverWater`'s surface (SCRIPT_river_water.gd), laid along
// each river's spline at its level over the bed the field carved under it
// (`FlowTerrain`, `IslandField.flow_water_mesh`); the terrain shader draws that
// bed, sand with caustics on it, and the rocky banks (`river_water_mesh`).
//
// BEAUTIFUL:
//   * CLEAR BY DEPTH. Over the deep middle it is jade, nearly opaque; it shelves
//     with the bed to turquoise at the shore and goes clear, so the sand and its
//     caustics show through (the surface's COLOR.r is the depth under it);
//   * IT RUNS. The ripples (TEX_tropical_water_ripples_256.png: R the ripples,
//     G the foam, B the glints, drawn in the river's frame) scroll down the
//     river, fastest in the middle and slow at the shore, in two phases half a
//     period apart, crossfaded, each reset when it is faded out, so the shear
//     between middle and shore never draws them into streaks. A still creek
//     barely drifts;
//   * AND RUNS DOWNHILL (the user: "Make water on hills much more faster moving,
//     or at least appear faster moving"). The ripples run down the reach's FLOW
//     TIME (`RiverWater`, CUSTOM0.x), which climbs a fifth as fast down a reach
//     five times as quick, so there they race, drawn out into streaks down the
//     flow; the steeper the reach (CUSTOM0.z) the more of it breaks white
//     (`rapids_foam`), the paler and more opaque the water churned through it
//     (`rapids_whiten`), and the harder its swell rolls. Streaks running along
//     themselves hardly seem to move, so over them the WHITE WATER, the ripples'
//     foam again at their own size, not drawn out, racing down every steep reach
//     at one speed (`rapids_speed`): one speed everywhere, so it scrolls without
//     a phase and never tears, and only as much of it as the reach is steep. A
//     still creek on a hill runs as a river does (UV2.y);
//   * IT CATCHES THE LIGHT. A normal from the ripples' slope lights it on the
//     island's model (`island_light`: the ambient and the banded sun), a
//     fresnel turns it to the haze at a low angle, as water mirrors the horizon,
//     and the sun's reflection glints off the ripples' facets;
//   * FOAM: white where the riffles break and in streaks down the flow, and a
//     line of it along the shore;
//   * AND IT IS BROKEN (the user: "vehicle --> water splashing rippling
//     interaction (performant retro aesthetic)"). Where a wheel ploughs it, a
//     craft's jets beat on it or something drops into it, RINGS run out over it
//     (`RiverWater.ripple`, up to `RIPPLES` at once in `ripples`): a crest with a
//     trough behind it, two sub-ripples off its middle by its own roll of the
//     dice, and a second, smaller ring after a hard splash, slowing
//     and broadening as they run and dying away. They tilt the normal, so they
//     catch the light and the haze as the ripples do; their crests are lit in
//     bands and the strongest break white; a fresh splash churns white in its
//     middle. NOTHING to pay where there are none: no rings, no loop, and outside
//     the box round the live ones (`ripple_box`), none either.
// RETRO:
//   * every pattern is read on the ground's texel grid, 21.3 texels a metre, so
//     the water is pixels the size of the sand's under it;
//   * it moves in whole steps (`step_rate` a second), like a sprite's frames,
//     the rings too, which are read on the same grid;
//   * the colour is banded (`color_steps`), the sun is banded, the glints are
//     on or off, the foam hard-edged and dithered at the shore;
//   * and the post pass takes all of it to the palette like everything else.
// The fog is the terrain's, number for number, so the water hazes out with the
// ground under it.

global uniform vec4 tod_haze_tint;

group_uniforms surface;
uniform sampler2D ripple_tex : hint_default_black, filter_nearest_mipmap, repeat_enable;
// Metres of river to one tile of the ripples, and how far they are drawn out
// down the flow.
uniform float ripple_scale = 12.0;
uniform float ripple_stretch = 1.8;
// The texels a metre every pattern is read on: the ground's own.
uniform float texel_density = 21.333;
// Metres a second down a moving river's middle, the share of it at the shore,
// and a still creek's drift.
uniform float flow_speed = 1.4;
uniform float edge_speed : hint_range(0.0, 1.0) = 0.3;
uniform float still_speed = 0.12;
// Seconds a flow phase runs before it is faded out and reset.
uniform float flow_period = 8.0;
// On the steepest reach (CUSTOM0.z 1): the foam's share of the ripples' foam
// channel, which breaks it white, and how far the water is paled toward foam.
uniform float rapids_foam : hint_range(0.0, 1.0) = 0.95;
uniform float rapids_whiten : hint_range(0.0, 1.0) = 0.3;
// The white water over a steep reach: metres a second it races at, and metres
// of river to one tile of it down the flow.
uniform float rapids_speed = 6.0;
uniform float rapids_tile = 9.0;
// The steps a second the surface moves in.
uniform float step_rate = 12.0;
// How tall the ripples stand, for their normal: metres over a tile's texel.
uniform float ripple_height = 0.06;
// A swell down a moving river's middle, metres: the surface breathes.
uniform float swell = 0.03;

group_uniforms colour;
uniform vec3 deep_color : source_color = vec3(0.04, 0.26, 0.27);
uniform vec3 mid_color : source_color = vec3(0.08, 0.45, 0.42);
uniform vec3 shallow_color : source_color = vec3(0.34, 0.76, 0.68);
uniform vec3 foam_color : source_color = vec3(0.93, 0.97, 0.95);
// The depth (metres) the water reads as deep at.
uniform float depth_full = 1.6;
uniform float alpha_shallow : hint_range(0.0, 1.0) = 0.22;
uniform float alpha_deep : hint_range(0.0, 1.0) = 0.86;
// How much brighter a ripple's crest is than its trough.
uniform float ripple_shade : hint_range(0.0, 1.0) = 0.3;
// Bands of colour per channel, before the palette's.
uniform float color_steps = 6.0;

group_uniforms light;
uniform float sun_bands : hint_range(0.0, 12.0) = 3.0;
uniform float sun_wrap : hint_range(0.0, 1.0) = 0.5;
uniform float fresnel_power = 4.0;
uniform float fresnel_gain : hint_range(0.0, 1.0) = 0.65;
// What a low look mirrors: the haze, lifted this much.
uniform float reflect_gain = 1.7;
uniform float glint_power = 48.0;
uniform float glint_gain = 1.8;

group_uniforms foam;
// The riffles' and streaks' foam on a moving river, and on a still creek.
uniform float flow_foam : hint_range(0.0, 1.0) = 0.75;
uniform float still_foam : hint_range(0.0, 1.0) = 0.1;
// Where the shore's line of foam begins, in half-widths, and how much of it is
// lit: a dither, re-rolled `foam_rate` times a second.
uniform float shore_foam_start = 0.82;
uniform float shore_foam_cover : hint_range(0.0, 1.0) = 0.55;
uniform float foam_rate = 4.0;
// Seen from under it (an eye in the water, SHADER_underwater): how much of it is
// drawn. Under the waterline the underwater pass draws the surface itself; this
// is the sky above it, through the top of a lens half out of the water.
uniform float underside_alpha : hint_range(0.0, 1.0) = 0.15;

group_uniforms wakes;
// The rings (`RiverWater.ripple`): each slot x, z in the water's own frame (the
// field's, so a rebase moves them with it), the clock it was made at, and twice
// its roll plus its strength (0 to 1). The first `ripple_count` are live; `ripple_now` is the
// clock; `ripple_box` the field-frame rectangle (x0, z0, x1, z1) every live ring
// reaches inside.
uniform vec4 ripples[64];
uniform int ripple_count = 0;
uniform float ripple_now = 0.0;
uniform vec4 ripple_box = vec4(0.0);
// Metres a second a ring runs out at, and seconds it runs, at full strength; a
// weak one runs slower and dies sooner, a droplet's under a second
// (`RiverWater.ring_life_of`, `ring_reach`, which must
// agree). How wide its crest is, metres, and how tall, for its normal.
uniform float ring_speed = 4.0;
uniform float ring_life = 2.2;
uniform float ring_width = 0.32;
uniform float ring_height = 0.5;
// How much a ring shows: its height times this, before it is banded, so a
// wheel's faint ring still draws a lit line for most of its life.
uniform float ring_gain = 2.2;
// The crest's band at and over which it breaks white (bands of thirds), and how
// far each band is paled toward the foam.
uniform float ring_foam : hint_range(0.0, 1.0) = 0.9;
uniform float ring_pale : hint_range(0.0, 1.0) = 0.45;

group_uniforms void_fog;
uniform bool fog_enabled = true;
uniform vec3 fog_color : source_color = vec3(0.3);
uniform float fog_top = -170.0;
uniform float fog_bottom = -320.0;
uniform float fog_curve : hint_range(0.25, 6.0) = 2.2;
uniform float fog_opacity_gain : hint_range(1.0, 6.0) = 1.6;
uniform float fog_distance_start : hint_range(0.0, 3000.0) = 850.0;
uniform float fog_distance_density : hint_range(0.0, 0.01) = 0.0012;
uniform float fog_distance_power : hint_range(1.0, 4.0) = 2.0;
group_uniforms;

varying vec3 world_pos;
// The vertex in the water's own frame, (x, z): where the rings are.
varying vec2 field_xz;
varying vec3 world_tan;
varying vec4 water;
// The reach (`RiverWater`, CUSTOM0): its flow time, its pace (flow time a metre),
// how steep it is.
varying vec3 reach;

// The shore's dither roll for a texel cell: Hoskins' `hash12`, as
// `SHADERINC_golf_wall.gdshaderinc` has it, on the cell wrapped to 4096.
//
// NOT the usual sine hash, the fraction of `sin(dot(c, k)) * 43758.5453`, which
// this was, and which turned the water WHITE ON MOBILE. The cells are world
// metres times 21.3, so the sine's argument runs to ~1e7; a phone's GPU reduces
// it in single precision (`fract(x / 2pi)` with a quarter of a unit left), so
// the sine comes out 0, 1, 0 or -1 and the roll 0 for most cells. And a roll of 0 passed the
// shore's test anywhere at all, the middle of the river included (`shore`, below):
// foam, everywhere. Desktop GPUs reduce the sine exactly, which is why it only
// showed on a phone. This takes no sine, and the wrap keeps every product small
// enough for single precision to keep its fraction.
float water_hash(vec2 c) {
	vec3 p3 = fract(vec3(mod(c, 4096.0), mod(c.x, 4096.0)) * 0.1031) + 0.371;
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// The ripples at river-frame metres `rp` (along, across) after `travel` metres
// of drift, one phase: (height, foam, glint) and the height one texel down and
// across the flow, for the slope.
vec4 ripple_phase(vec2 rp, float travel, vec2 off, out float hx, out float hz) {
	vec2 sc = vec2(1.0 / max(ripple_stretch, 1e-3), 1.0) / max(ripple_scale, 1e-3);
	vec2 u = (rp - vec2(travel, 0.0)) * sc + off;
	float th = 1.0 / float(textureSize(ripple_tex, 0).x);
	vec4 c = texture(ripple_tex, u);
	hx = texture(ripple_tex, u + vec2(th, 0.0)).r;
	hz = texture(ripple_tex, u + vec2(0.0, th)).r;
	return c;
}

// A ring's dice: four rolls, 0 to 1, off `k` (Hoskins' hash: no sine, so a
// phone's GPU rolls it as a desktop's does).
vec4 ring_dice(float k) {
	vec4 p4 = fract(vec4(k) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

// THE RINGS at field-frame metres `p` (a texel's middle): their height, about
// -1 to 1 (`.x`), their slope over x and z (`.yz`), and how much of a fresh
// splash's white middle covers `p` (`.w`). Each ring: a crest at its radius with a
// trough behind it, `exp(-x²)` both, stronger on one side than the other, and
// after a hard splash (strength half or more) a second at six tenths of its
// radius; dying as the square of the life left, broadening as it goes. And round
// each, TWO SUB-RIPPLES (the user: "more randomized sub ripples, clusters of
// ripples"): smaller rings off its middle, each at its own share of its radius
// and its own strength, all by the ring's roll, so no two rings break the water
// alike. A ring's slot carries its roll and its strength in one (`.w`: twice the
// roll, plus the strength). A weak ring (a droplet falling back in) runs slower,
// thinner and shorter than a strong one.
vec4 rings(vec2 p, float now) {
	vec4 o = vec4(0.0);
	int n = min(ripple_count, 64);
	for (int i = 0; i < n; i++) {
		vec4 rp = ripples[i];
		float k = floor(rp.w * 0.5);
		float s = rp.w - 2.0 * k;
		float life = ring_life * (0.3 + 0.7 * s);
		float age = now - rp.z;
		if (age < 0.0 || age >= life) {
			continue;
		}
		float speed = ring_speed * (0.15 + 1.15 * s);
		float spread = 0.15 + 0.45 * s;
		vec2 d = p - rp.xy;
		float dd = dot(d, d);
		float far = speed * life + 3.0 * ring_width + spread * 1.5;
		if (dd > far * far) {
			continue;
		}
		float u = age / life;
		float r = speed * age * (1.0 - 0.35 * u);
		float dist = sqrt(dd);
		float w = ring_width * (0.55 + 0.45 * s) * (1.0 + u);
		float amp = s * (1.0 - u) * (1.0 - u);
		vec4 dice = ring_dice(k + 1.0);
		vec2 nd = d / max(dist, 1e-3);
		// Lopsided: stronger toward one side, a different one each ring.
		vec2 lean = normalize(dice.xy - 0.5 + vec2(1e-3));
		float side = 0.7 + 0.4 * dot(nd, lean);
		float x = (dist - r) / w;
		float g = exp(-x * x);
		float xt = x + 1.4;
		float gt = exp(-xt * xt) * 0.55;
		float h = (g - gt) * side;
		float dh = (-2.0 * x * g + 2.0 * xt * gt) * side;
		if (s >= 0.5) {
			float x2 = (dist - r * 0.6) / w;
			float g2 = exp(-x2 * x2) * 0.6;
			h += g2;
			dh += -2.0 * x2 * g2;
		}
		o.x += h * amp;
		o.yz += nd * (dh / w) * amp;
		for (int j = 0; j < 2; j++) {
			vec4 e = ring_dice(k * 3.0 + float(j) + 7.0);
			vec2 ds = p - (rp.xy + (e.xy - 0.5) * 2.0 * spread);
			float dist_s = length(ds);
			float xs = (dist_s - r * (0.35 + 0.5 * e.z)) / (w * 0.6);
			float gs = exp(-xs * xs) * (0.3 + 0.4 * e.w);
			o.x += gs * amp;
			o.yz += ds / max(dist_s, 1e-3) * (-2.0 * xs * gs / (w * 0.6)) * amp;
		}
		// A splash's middle, while it is young: inside the ring, white, thinning
		// out over its first four tenths of a second at full strength. A
		// splash's only (strength seven tenths or more): a wake's rings come
		// too thick and fast to each churn white, and would lay a white road.
		float young = (1.0 - clamp(age / max(0.4 * s, 1e-3), 0.0, 1.0)) * step(0.7, s);
		o.w = max(o.w, young * step(dist, r * 0.8 + 0.25));
	}
	// Many rings over one spot (a wake at speed) add up, but not without end: the
	// sum eased off as it grows, so they still show as rings, each its own crest,
	// and only where they pile up thickest do they break white.
	o.x = o.x / (1.0 + 0.8 * abs(o.x));
	return o;
}

void vertex() {
	field_xz = VERTEX.xz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_tan = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
	water = COLOR;
	reach = CUSTOM0.xyz;
	// The swell: gone at the shore, so the edge never lifts off its bank. Down
	// the flow time, so it rolls as fast as the ripples run, and taller where it
	// is steep.
	float mid = 1.0 - smoothstep(0.3, 0.9, UV2.x);
	VERTEX.y += swell * (1.0 + reach.z) * mid * UV2.y * sin(reach.x * 0.9 - TIME * 2.6);
}

void fragment() {
	float at = UV2.x;
	float moving = UV2.y;
	float depth01 = clamp(water.r * 4.0 / max(depth_full, 1e-3), 0.0, 1.0);

	// ---- the flow: two phases, in whole steps, on the texel grid -----------
	float t = floor(TIME * step_rate) / max(step_rate, 1e-3);
	float v = mix(still_speed, flow_speed * mix(1.0, edge_speed, min(at * at, 1.0)), moving);
	float per = max(flow_period, 0.1);
	float ph0 = fract(t / per);
	float ph1 = fract(t / per + 0.5);
	// The texel's middle in the river's metres, and the flow time there: the
	// flow time here, moved by the metres to the middle at the reach's pace, so a
	// texel stays one colour however fast its reach.
	vec2 rp = (floor(UV * texel_density) + 0.5) / texel_density;
	rp.x = reach.x + (rp.x - UV.x) * reach.y;
	float steep = clamp(reach.z, 0.0, 1.0);
	float hx0;
	float hz0;
	float hx1;
	float hz1;
	vec4 r0 = ripple_phase(rp, ph0 * per * v, vec2(0.0), hx0, hz0);
	vec4 r1 = ripple_phase(rp, ph1 * per * v, vec2(0.31, 0.57), hx1, hz1);
	float k = 1.0 - abs(ph0 * 2.0 - 1.0);
	vec4 rt = mix(r1, r0, k);
	float hx = mix(hx1, hx0, k);
	float hz = mix(hz1, hz0, k);

	// ---- the normal, from the ripples' slope in the river's frame ----------
	vec3 tan_w = normalize(vec3(world_tan.x, 0.0, world_tan.z) + vec3(1e-5, 0.0, 0.0));
	// The river's left, looking downstream: positive across (`FlowTerrain`).
	vec3 left_w = vec3(-tan_w.z, 0.0, tan_w.x);
	float texel_m = max(ripple_scale, 1e-3) / float(textureSize(ripple_tex, 0).x);
	vec2 slope = vec2((hx - rt.r) * ripple_stretch, hz - rt.r) * ripple_height / texel_m;
	vec3 n = normalize(vec3(0.0, 1.0, 0.0) - tan_w * slope.x - left_w * slope.y);
	vec3 world_v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);

	// ---- the wakes' rings, on the same texel grid and in the same steps ----
	vec4 wk = vec4(0.0);
	if (ripple_count > 0 && field_xz.x > ripple_box.x && field_xz.y > ripple_box.y
			&& field_xz.x < ripple_box.z && field_xz.y < ripple_box.w) {
		vec2 fp = (floor(field_xz * texel_density) + 0.5) / texel_density;
		wk = rings(fp, floor(ripple_now * step_rate) / max(step_rate, 1e-3));
		n = normalize(n - vec3(wk.y, 0.0, wk.z) * ring_height);
	}
	// In bands of thirds: a crest lit, a trough shaded, never between.
	float ring_band = floor(clamp(wk.x * ring_gain, -1.0, 1.0) * 3.0 + 0.5) / 3.0;

	// ---- the colour by depth, the crests lighter --------------------------
	vec3 base = depth01 < 0.5 ? mix(shallow_color, mid_color, depth01 * 2.0)
			: mix(mid_color, deep_color, depth01 * 2.0 - 1.0);
	base *= 1.0 - ripple_shade * 0.5 + ripple_shade * rt.r;
	// Churned pale down a steep reach.
	base = mix(base, foam_color, steep * rapids_whiten * (0.6 + 0.4 * rt.r));
	// A ring's crest paled, its trough deepened.
	base = ring_band > 0.0 ? mix(base, foam_color, ring_band * ring_pale) : base * (1.0 + ring_band * 0.45);
	vec3 col = base * island_light(n, world_v, sun_bands, sun_wrap, 3.0, 0.0);

	// ---- the mirror: the haze at a low angle ------------------------------
	float fres = pow(1.0 - clamp(dot(n, world_v), 0.0, 1.0), fresnel_power);
	vec3 refl = fog_color * tod_haze_tint.rgb * reflect_gain;
	col = mix(col, refl, fres * fresnel_gain);

	// ---- the sun's glints: on the glint texels, on or off ----------------
	vec3 r = reflect(-tod_sun_dir, n);
	float g = pow(max(dot(r, world_v), 0.0), glint_power);
	float glint = step(0.35, g) * step(0.5, rt.b);
	col += tod_sun_color.rgb * glint * glint_gain;

	// ---- the foam ----------------------------------------------------------
	vec2 cell = floor(world_pos.xz * texel_density);
	float roll = water_hash(cell + floor(TIME * foam_rate) * vec2(17.0, 31.0));
	// The shore's foam, dithered: likelier the nearer the shore, so it frays into
	// the water instead of drawing a line along the bank. STRICTLY over the roll,
	// so where the cover is nothing (all of the river short of the shore) no roll,
	// 0 included, lights a texel; `step(roll, cover)` lit it at a roll of 0.
	float lit = shore_foam_cover * smoothstep(shore_foam_start, 1.05, at);
	float shore = lit > roll ? 1.0 : 0.0;
	float run = rt.g * mix(mix(still_foam, flow_foam, moving), rapids_foam, steep);
	// The white water: in the river's own metres, scrolled by a whole tile's
	// worth at most, so it is exact however long the game runs.
	if (steep > 0.0) {
		float tile = max(rapids_tile, 1e-3);
		vec2 sm = (floor(UV * texel_density) + 0.5) / texel_density;
		vec2 wu = vec2((sm.x - mod(t * rapids_speed, tile)) / tile,
				sm.y / max(ripple_scale, 1e-3)) + vec2(0.17, 0.43);
		vec4 wr = texture(ripple_tex, wu);
		run = max(run, wr.g * rapids_foam * steep * (1.0 - smoothstep(0.75, 1.0, at)));
	}
	// A ring breaks white at its crest, and a fresh splash in its middle,
	// dithered by the shore's roll so it frays as it thins.
	float wake = max(step(ring_foam, ring_band), wk.w > roll ? 1.0 : 0.0);
	float foam = step(0.5, max(max(run, shore), wake));
	vec3 foam_lit = foam_color * island_light(vec3(0.0, 1.0, 0.0), world_v, sun_bands, sun_wrap, 3.0, 0.0);
	col = mix(col, foam_lit, foam);

	// ---- banded, retro ----------------------------------------------------
	float steps = max(color_steps, 2.0);
	col = floor(col * steps + 0.5) / steps;

	float alpha = mix(alpha_shallow, alpha_deep, depth01);
	// White water is not clear.
	alpha = max(alpha, steep * rapids_whiten * 2.0);
	alpha = max(alpha, fres * fresnel_gain * 0.8);
	alpha = max(alpha, max(foam, glint));
	// A ring stands out of the clear shallows.
	alpha = max(alpha, abs(ring_band) * 0.9);
	// At the coast the channel eases out to the lip and the water with it
	// (COLOR.g), and an ending river fades out over its pool (COLOR.b).
	alpha *= clamp(water.g, 0.0, 1.0) * clamp(water.b, 0.0, 1.0);
	if (CAMERA_POSITION_WORLD.y < world_pos.y) {
		alpha *= underside_alpha;
	}

	// ---- the terrain's fog, number for number -----------------------------
	if (fog_enabled) {
		float ft = clamp((fog_top - world_pos.y) / max(fog_top - fog_bottom, 1e-3), 0.0, 1.0);
		float depth_t = clamp(pow(ft, 1.0 / max(fog_curve, 0.001)) * fog_opacity_gain, 0.0, 1.0);
		float d = max(length(VERTEX) - fog_distance_start, 0.0) * fog_distance_density;
		float dist_t = 1.0 - exp(-pow(d, fog_distance_power));
		float fog = 1.0 - (1.0 - depth_t) * (1.0 - dist_t);
		col = mix(col, fog_color * tod_haze_tint.rgb, fog);
	}

	ALBEDO = col;
	ALPHA = alpha;
}
