shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled,
		shadows_disabled, fog_disabled;

// UNDER THE WATER (the user: "Add underwater shader with waterline half in half
// out effect"). One quad over the whole screen (`UnderwaterView`,
// SCRIPT_underwater_view.gd), drawn after everything else in the world, while the
// eye is in a river, a crater lake or the lagoon (`RiverWater.world_level_at`)
// and near enough the surface, or under it, for any of the picture to be under.
//
// THE WATERLINE ON THE LENS. Each pixel is read at a plane `lens` metres in front
// of the eye, not at the eye: a pixel whose ray is under the water there is
// under. So the line between the two is where the surface cuts the lens, and it
// lies across the screen as the surface does, tilting as the eye rolls, rising
// as it looks down, and riding the waves (`wave_*`). With the eye at the surface
// the screen is half in and half out. Along the line, the water clinging to the
// lens: a thin, solid, ragged line of foam with froth beading just under it, and
// over it a hair of the colours split apart (`line_split`) where the film bends
// the light.
//
// UNDER IT, what the water does to light:
//   * REFRACTION: the picture is magnified (`magnify`, water's 1.33 and less),
//     about the middle of the screen, so a thing that crosses the waterline
//     breaks at it, and it wobbles (`wobble_*`), in whole pixels;
//   * DISPERSION: the red and the blue drawn apart toward the edges
//     (`aberration`);
//   * THE WATER BETWEEN: the scene's distance off the depth buffer, and the
//     water along it from where the ray enters (the eye, or the surface when the
//     eye is over it) takes the red first (`absorb`) and fogs to the water's
//     colour (`clarity`), darker the deeper the eye is (`depth_dark`);
//   * THE SURFACE FROM BELOW: where the ray reaches the surface before anything
//     else, inside SNELL'S WINDOW (`snell_cos`, a cone of 48.6 degrees round the
//     straight up) the world above shows through it, bright, and outside it the
//     surface is a mirror of the dark water under it, with a bright rim between;
//   * LIGHT SHAFTS slanting down through the water toward the sun (`shafts`).
// Every pattern moves in whole steps (`step_rate`), and the dither pass after
// takes all of it to the palette.

global uniform vec3 tod_sun_dir;
global uniform vec4 tod_sun_color;
global uniform vec4 tod_haze_tint;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

// The world height of the surface over the eye, set every frame by UnderwaterView.
uniform float water_y = 0.0;
// Metres in front of the eye the waterline is read at.
uniform float lens = 0.45;
uniform float step_rate = 12.0;

group_uniforms water;
uniform vec3 shallow_color : source_color = vec3(0.16, 0.56, 0.52);
uniform vec3 deep_color : source_color = vec3(0.02, 0.17, 0.2);
// Metres of water that fog the picture two thirds of the way to the water's colour.
uniform float clarity = 9.0;
// Per channel, how much a metre of water takes: red first.
uniform vec3 absorb = vec3(0.32, 0.07, 0.05);
// Metres under at which the water's colour is the deep one.
uniform float depth_dark = 5.0;

group_uniforms refraction;
uniform float magnify : hint_range(1.0, 1.5) = 1.2;
// The wobble, as a share of the screen's height, its cells across the screen, its speed.
uniform float wobble : hint_range(0.0, 0.02) = 0.005;
uniform float wobble_cells = 5.0;
uniform float wobble_speed = 1.2;
// The red and blue drawn apart at the screen's edge, as a share of its width.
uniform float aberration : hint_range(0.0, 0.02) = 0.006;

group_uniforms surface_from_below;
// The cosine of Snell's window's half angle (48.6 degrees).
uniform float snell_cos = 0.66;
uniform float window_gain = 1.3;
uniform float rim_gain = 0.6;

group_uniforms waterline;
// The meniscus, in pixels thick, its colour, and how far the colours split over it.
uniform float line_px = 1.6;
uniform vec3 line_color : source_color = vec3(0.86, 0.97, 0.96);
uniform float line_split = 2.5;
// How much froth hangs just under the line, and how far down (pixels).
uniform float foam_amount = 0.75;
uniform float foam_depth = 9.0;
// How far the foam stands over the line (pixels at 900 tall): enough to cover the
// film, where the bed shows through under the near edge of the water's surface.
uniform float foam_rise = 7.0;
// How far the surface rides up and down across the lens, metres, its waves across
// the screen, and how fast they run.
uniform float wave_height = 0.0;
uniform float wave_cells = 2.0;
uniform float wave_speed = 2.4;

group_uniforms shafts;
uniform float shafts : hint_range(0.0, 2.0) = 0.35;
uniform float shaft_bars = 16.0;
group_uniforms;

// THE SWELL of the still water the eye is in (SCRIPT_underwater_view.gd sets
// these): the three corners of the surface's own triangle over the lens, as the
// mesh has them, and the swell's settings copied from the water's material. A
// height of 0 where there is none.
uniform vec3 swell_a = vec3(0.0);
uniform vec3 swell_b = vec3(1.0, 0.0, 0.0);
uniform vec3 swell_c = vec3(0.0, 0.0, 1.0);
uniform vec2 swell_centre = vec2(0.0);
uniform sampler2D swell_noise : filter_linear_mipmap, repeat_enable;
uniform float swell_height = 0.0;
uniform float swell_length = 13.0;
uniform float swell_pace = 2.6;
global uniform vec4 enviro_wind;
#include "res://shaders/SHADERINC_swell.gdshaderinc"

// How far each corner of that triangle stands over the water's level just now.
varying flat vec3 corner_lift;

void vertex() {
	// The quad (2 m square, `UnderwaterView`) over the whole screen, wherever it is.
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
	corner_lift = vec3(0.0);
	if (swell_height > 0.0) {
		corner_lift = vec3(
				swell_lift(swell_field(swell_noise, swell_centre, swell_length, swell_pace, swell_a.xz, TIME), swell_height, enviro_wind.z),
				swell_lift(swell_field(swell_noise, swell_centre, swell_length, swell_pace, swell_b.xz, TIME), swell_height, enviro_wind.z),
				swell_lift(swell_field(swell_noise, swell_centre, swell_length, swell_pace, swell_c.xz, TIME), swell_height, enviro_wind.z));
	}
}

float uw_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float uw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(uw_hash(i), uw_hash(i + vec2(1.0, 0.0)), f.x),
			mix(uw_hash(i + vec2(0.0, 1.0)), uw_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The ray through a point of the screen, in the eye's frame.
vec3 eye_ray(vec2 suv, mat4 inv_proj) {
	vec4 v = inv_proj * vec4(suv * 2.0 - 1.0, 0.0, 1.0);
	return normalize(v.xyz / v.w);
}

// Metres from the eye to what the depth buffer holds at a point of the screen.
float scene_distance(vec2 suv, mat4 inv_proj) {
	float d = texture(depth_tex, suv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(suv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return length(v.xyz / v.w);
}

// The picture at a point, its red and blue drawn `split` apart (screen shares).
vec3 split_read(vec2 suv, vec2 split) {
	return vec3(texture(screen_tex, clamp(suv + split, vec2(0.0), vec2(1.0))).r,
			texture(screen_tex, clamp(suv, vec2(0.0), vec2(1.0))).g,
			texture(screen_tex, clamp(suv - split, vec2(0.0), vec2(1.0))).b);
}

void fragment() {
	vec2 px = VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	float t = floor(TIME * step_rate) / max(step_rate, 1.0);
	mat3 to_world = mat3(INV_VIEW_MATRIX);
	vec3 eye = CAMERA_POSITION_WORLD;
	vec3 ray_v = eye_ray(uv, INV_PROJECTION_MATRIX);
	vec3 ray = normalize(to_world * ray_v);

	// ---- the lens: under the water there, or not -----------------------------
	vec3 at_lens = eye + ray * (lens / max(-ray_v.z, 1e-3));
	// THE LINE IS WHERE THE WATER IS: straight across the lens, at the height the
	// water's own surface stands there, swell and all (worked from the corners of
	// the surface's triangle, as the surface is). No lapping of the line's own is
	// added: any difference between the two shows as a gap with the bed in it.
	float wave = 0.004;
	if (swell_height > 0.0) {
		// Where the lens is in the triangle, and so how high the surface is there.
		vec2 e0 = swell_b.xz - swell_a.xz;
		vec2 e1 = swell_c.xz - swell_a.xz;
		vec2 d = at_lens.xz - swell_a.xz;
		float den = e0.x * e1.y - e0.y * e1.x;
		float u = (d.x * e1.y - d.y * e1.x) / den;
		float v = (e0.x * d.y - e0.y * d.x) / den;
		wave += corner_lift.x * (1.0 - u - v) + corner_lift.y * u + corner_lift.z * v;
	}
	float h = at_lens.y - (water_y + wave);
	// The same in pixels, by how fast it changes across the screen.
	float hp = h / max(fwidth(h), 1e-6);

	// Over it, and clear of the film on the lens: the picture as it was.
	float rise = max(foam_rise * px.y / 900.0, line_px + line_split * 2.0 + 1.0);
	if (hp > rise * 1.5) {
		discard;
	}
	float day = clamp(tod_sun_dir.y * 2.0 + 0.3, 0.12, 1.0);
	vec3 sun = tod_sun_color.rgb * clamp(tod_sun_dir.y * 2.0, 0.0, 1.0);

	vec3 col;
	if (hp > 0.0) {
		// THE FILM over the line: the colours split up and down across it, most
		// at the line.
		float k = 1.0 - clamp((hp - line_px) / (line_split * 2.0), 0.0, 1.0);
		vec2 split = vec2(0.0, line_split * k / px.y);
		col = split_read(uv, split);
		col = mix(col, col * 1.08 + 0.03, k);
	} else {
		// ---- under: refracted, wobbling, in whole pixels ---------------------
		float aspect = px.x / max(px.y, 1.0);
		vec2 cell = vec2(uv.x * aspect, uv.y) * wobble_cells;
		vec2 wob = vec2(sin((cell.y + t * wobble_speed * 0.5) * 6.2832 + uw_noise(cell * 1.7) * 3.0),
				cos((cell.x * 0.8 - t * wobble_speed * 0.37) * 6.2832 + uw_noise(cell * 1.3 + 7.0) * 3.0));
		vec2 uv2 = 0.5 + (uv - 0.5) / max(magnify, 1.0) + wob * wobble * vec2(1.0 / aspect, 1.0);
		uv2 = (floor(uv2 * px) + 0.5) / px;
		vec2 off_mid = uv2 - 0.5;
		vec2 split = off_mid * aberration * 2.0;
		vec3 scene = split_read(uv2, split);
		vec3 ray2 = normalize(to_world * eye_ray(uv2, INV_PROJECTION_MATRIX));
		float t_scene = scene_distance(uv2, INV_PROJECTION_MATRIX);

		// Where the ray is in the water: from the eye if it is under, else from
		// where the ray goes in.
		float t_in = 0.0;
		if (eye.y > water_y) {
			t_in = ray2.y < -1e-4 ? (eye.y - water_y) / -ray2.y : t_scene;
		}
		vec3 e = eye + ray2 * t_in;
		float under = max(water_y - e.y, 0.0);
		float t_surf = ray2.y > 1e-4 ? max(water_y - e.y, 0.0) / ray2.y : 1e9;
		float path;
		if (t_surf < t_scene - t_in) {
			// THE SURFACE FROM BELOW: Snell's window, and the mirror round it.
			vec3 hit = e + ray2 * t_surf;
			// Its ripples, seen less the further off they are.
			float rip = (uw_noise(floor(hit.xz * 6.0) / 6.0 * 1.5 + t * 0.9) - 0.5)
					* exp(-t_surf / 6.0);
			float c = ray2.y + rip * 0.12;
			float window = smoothstep(snell_cos - 0.03, snell_cos + 0.03, c);
			vec3 above = scene * window_gain * (1.0 + rip * 0.3);
			vec3 mirror = deep_color * day * (0.75 + rip * 0.5);
			col = mix(mirror, above, window);
			col += line_color * rim_gain * day * (1.0 - abs(window * 2.0 - 1.0));
			path = t_surf;
		} else {
			col = scene;
			path = max(t_scene - t_in, 0.0);
		}
		// ---- the water between ---------------------------------------------
		vec3 water_c = mix(shallow_color, deep_color,
				clamp((under + max(-ray2.y, 0.0) * min(path, 20.0)) / max(depth_dark, 0.01), 0.0, 1.0))
				* (vec3(dot(tod_haze_tint.rgb, vec3(0.333))) * day * 1.6);
		col *= exp(-absorb * path);
		col = mix(col, water_c, 1.0 - exp(-path / max(clarity, 0.01)));
		// Light shafts, slanting down toward the sun, brighter looking up.
		vec2 sd = tod_sun_dir.xz;
		vec3 sv = normalize(transpose(to_world) * vec3(sd.x, 0.0, sd.y) + vec3(1e-4));
		float slant = clamp(sv.x, -0.8, 0.8) * 0.6;
		float bars = uw_noise(vec2((uv.x + (1.0 - uv.y) * slant) * shaft_bars + t * 0.12, t * 0.05));
		float shaft = smoothstep(0.62, 0.95, bars) * smoothstep(-0.4, 0.5, ray2.y)
				* (1.0 - exp(-path / max(clarity, 0.01)));
		col += sun * shafts * shaft * water_c * 2.0;
		// ---- the dark lip under the film on the lens -------------------------
		col *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, line_px * 3.0, -hp));
		// ---- froth clinging under the line: small bright beads, thick at the
		// line and gone a few pixels down, never still.
		vec2 bead = floor(vec2(uv.x * px.x, -hp) / 2.0);
		float beads = uw_noise(bead * vec2(0.9, 1.3) + vec2(t * 1.7, -t * 2.3));
		float under_line = 1.0 - smoothstep(0.0, foam_depth, -hp);
		float froth = smoothstep(1.0 - foam_amount * under_line, 1.0, beads) * under_line;
		col = mix(col, line_color * mix(vec3(0.75), sun + vec3(0.45), 0.5), froth);
	}
	// ---- the meniscus ----------------------------------------------------------
	// A thin line of foam, solid (nothing shows through it), ragged: thicker and
	// thinner along its length, and that moving.
	float ragged = line_px * (0.55 + 1.3 * uw_noise(vec2(floor(uv.x * px.x / 3.0) * 0.6 + t * 1.3, t * 0.7)));
	float line = 1.0 - smoothstep(ragged * 0.6, ragged, abs(hp));
	// Over the line it stands thick: a band of foam that covers the film whole
	// (never thinner than `rise`), its top lumpy, bubbles shading it a little.
	float lump = uw_noise(vec2(floor(uv.x * px.x / 4.0) * 0.45 - t * 0.9, t * 0.5));
	float top = rise * (1.0 + 0.45 * lump);
	float band = hp > 0.0 ? 1.0 - step(top, hp) : 0.0;
	line = max(line, band);
	float bubbly = uw_noise(floor(vec2(uv.x * px.x, hp) / 2.0) * vec2(0.8, 1.1) + vec2(t * 1.1, -t * 0.6));
	vec3 foam = line_color * mix(vec3(0.8), sun + vec3(0.5), 0.5) * mix(0.86, 1.0, bubbly);
	if (hp > rise * 1.5 - 0.01 || (hp > 0.0 && band < 0.5 && hp > line_px + line_split * 2.0)) {
		discard;
	}
	col = mix(col, foam, line);

	ALBEDO = col;
	ALPHA = 1.0;
}
