shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled,
	shadows_disabled, fog_disabled;

// THE DUST WALL. One quad over the whole screen (`DesertWeather` hangs it in
// front of the camera), drawn first of the transparent pass: it reads the depth
// of everything opaque already drawn and lays sand over it by how far away it is,
// so the world thickens into dust at whatever distance the weather asks for. The
// sky (nothing there, depth at the far plane) takes the full amount.
//
// The dust is thick near the ground and thins with height (`height_falloff`), so
// from a VTOL a few hundred metres up a storm is a brown sea with the sun over it.
// Two layers of wind-blown noise, sampled where the view ray passes 25 m and 80 m
// out, roll billows through it at the wind's speed (`drift`).
//
// Its colour is the haze family's own: the neutral 0.30 every fog here is pinned
// to, times `tod_haze_tint`, times this storm's `tint`. So it is tan at noon and
// red in the nightmare night without being told.

#include "res://shaders/SHADERINC_weather_shelter.gdshaderinc"
global uniform vec4 tod_haze_tint;
global uniform vec3 tod_sun_dir;
global uniform vec4 tod_sun_color;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Extinction per metre at the ground: visibility is about 3 / density.
uniform float density = 0.02;
// Metres over which the density falls by e going up from `ground_y`.
uniform float height_falloff = 90.0;
uniform float ground_y = 0.0;
uniform vec3 base_color : source_color = vec3(0.30, 0.30, 0.30);
uniform vec3 tint : source_color = vec3(1.45, 1.5, 1.65);
// How much the billows move the dust about, 0 = smooth.
uniform float billow : hint_range(0.0, 1.0) = 0.6;
uniform float billow_scale = 0.03;
uniform vec3 drift = vec3(0.0);
// The sun's glow through the dust, toward it.
uniform float sun_glow = 0.5;
// What the sky counts as: this far away.
uniform float sky_distance = 4000.0;
// The light on the dust: a storm thick enough to take the sun is darker in itself.
uniform float light = 1.0;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return 0.6 * noise3(p) + 0.4 * noise3(p * 2.3 + 7.1);
}

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
#endif
	vec4 v = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 view = v.xyz / v.w;
	float dist = length(view);
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(view, 0.0)).xyz);
	if (d >= 0.99999) {
		dist = sky_distance;
	}
	dist = min(dist, sky_distance);

	// Height fog, integrated along the ray: density * exp(-(y - ground) / H).
	float h = max(height_falloff, 1.0);
	float y0 = cam.y - ground_y;
	float dy = dir.y * dist;
	float k = exp(-y0 / h);
	float optical;
	if (abs(dy) < 0.01) {
		optical = density * k * dist;
	} else {
		optical = density * k * dist * h * (1.0 - exp(-dy / h)) / dy;
	}

	// Billows: the dust's thickness at two depths along the ray, blown downwind.
	vec3 p1 = cam + dir * min(dist, 25.0) - drift;
	vec3 p2 = cam + dir * min(dist, 80.0) - drift * 0.8;
	float n1 = fbm(p1 * billow_scale * vec3(1.0, 2.2, 1.0) * 2.5);
	float n2 = fbm(p2 * billow_scale * vec3(1.0, 2.0, 1.0));
	float n = mix(n2, n1, 0.45);
	optical *= mix(1.0, 0.35 + 1.3 * n, billow);

	// Only what of the ray is out in the weather: none of it inside a room, and
	// from inside one, only past its walls (SHADERINC_weather_shelter).
	optical *= weather_open_length(cam, dir, dist) / max(dist, 1e-3);
	float fog = (1.0 - exp(-max(optical, 0.0))) * amount;

	vec3 col = base_color * tod_haze_tint.rgb * tint;
	// Thicker rolls are a shade darker, the thin between them a shade lighter.
	col *= mix(1.0, 0.62 + 0.62 * (1.0 - n1) * (1.0 - 0.4 * n2), billow) * light;
	float toward = max(dot(dir, normalize(tod_sun_dir)), 0.0);
	col += tod_sun_color.rgb * tint * pow(toward, 6.0) * sun_glow * 0.25;
	ALBEDO = col;
	ALPHA = clamp(fog, 0.0, 1.0);
}
