// THE CLOUD SEA: a slab of cloud marched in the fragment shader, lit by the same
// sun, moon and sky as the island (SCRIPT_enviro.gd's globals), and banked up
// against the island so the foot of its wall is lost in it.
//
// `island_prox` is a soft map of where the land is (SCRIPT_cloud_sea.gd builds
// it): 0.5 at the coast, falling to 0 a hundred-odd metres out. The cloud top
// rises by `rise` where it is high, so the sea climbs the cliff. The march stops
// at whatever solid thing the depth buffer holds, so rock goes into the cloud
// softly instead of along a line.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

const int MAX_STEPS = 40;

uniform float sea_top = -45.0;
uniform float thickness = 175.0;
uniform float rise = 16.0;
uniform float max_march = 6000.0;
uniform int steps : hint_range(4, 40) = 20;

uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D island_prox : filter_linear, repeat_disable, hint_default_black;
// Half the side of the square of world the proximity map covers, centred on the origin.
uniform float prox_extent = 1800.0;
uniform float scale_a = 1400.0;
uniform float scale_b = 520.0;
uniform float bump_amp = 70.0;
uniform float top_round = 26.0;
uniform float bottom_round = 90.0;
uniform float density_gain = 0.05;
uniform vec3 cloud_albedo : source_color = vec3(0.86, 0.88, 0.9);
uniform float horizon_fade_start = 3800.0;
uniform float horizon_fade_end = 5200.0;
uniform float rim_fade_start = 5600.0;
uniform float rim_fade_end = 5960.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

global uniform vec3 enviro_light_dir;
global uniform vec4 enviro_light_color;
global uniform vec4 enviro_ambient;
global uniform vec4 enviro_fog_color;
global uniform vec4 enviro_wind;
global uniform float enviro_flash;

float density_at(vec3 wp) {
	float sea_bottom = sea_top - thickness;
	if (wp.y < sea_bottom) {
		return 0.0;
	}
	vec2 drift = enviro_wind.xy * enviro_wind.w * 6.0;
	float ta = texture(cloud_noise, (wp.xz + drift) / scale_a).r;
	float tb = texture(cloud_noise, (wp.xz - drift * 1.7) / scale_b + 0.31).r;
	float f = clamp((ta - tb * 0.5) * 1.6 + 0.2, 0.0, 1.0);
	float prox = texture(island_prox, wp.xz / (2.0 * prox_extent) + 0.5).r;
	float bank = smoothstep(0.02, 0.5, prox);
	// Against the island the sea stands higher and its top is ragged with wisps.
	float surface_y = sea_top - (1.0 - f) * bump_amp * (1.0 - 0.6 * bank) + rise * bank
			+ (tb - 0.5) * 12.0 * bank;
	if (wp.y > surface_y) {
		return 0.0;
	}
	return smoothstep(0.0, top_round, surface_y - wp.y)
			* smoothstep(0.0, bottom_round, wp.y - sea_bottom);
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(wp - ro);
	float top = sea_top + rise + 12.0;
	float bottom = sea_top - thickness;
	float t_enter;
	float t_exit;
	if (abs(rd.y) < 1e-4) {
		if (ro.y < bottom || ro.y > top) {
			discard;
		}
		t_enter = 0.0;
		t_exit = max_march;
	} else {
		float t_top = (top - ro.y) / rd.y;
		float t_bot = (bottom - ro.y) / rd.y;
		t_enter = max(min(t_top, t_bot), 0.0);
		t_exit = min(max(t_top, t_bot), max_march);
	}
	// Stop at the first solid thing along the ray.
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float scene = length(up.xyz / up.w);
	if (raw > 0.0000001) {
		t_exit = min(t_exit, scene);
	}
	if (t_exit <= t_enter) {
		discard;
	}

	int n = clamp(steps, 1, MAX_STEPS);
	float dt = (t_exit - t_enter) / float(n);
	float jitter = fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 light_dir = normalize(enviro_light_dir);
	float cosang = dot(rd, light_dir);
	float g = 0.45;
	float phase = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cosang, 1.5) * 0.5;
	vec3 sun = enviro_light_color.rgb;
	vec3 sky = enviro_ambient.rgb + vec3(0.7, 0.75, 1.0) * enviro_flash;

	float trans = 1.0;
	vec3 acc = vec3(0.0);
	for (int i = 0; i < MAX_STEPS; i++) {
		if (i >= n) {
			break;
		}
		float t = t_enter + (float(i) + jitter) * dt;
		vec3 sp = ro + rd * t;
		float dens = density_at(sp) * density_gain;
		if (dens > 0.0002) {
			// One tap toward the light says how much cloud stands in its way.
			float shade = density_at(sp + light_dir * 34.0) + density_at(sp + light_dir * 90.0) * 0.6;
			float lit = exp(-shade * 1.7);
			float h = clamp((sp.y - bottom) / (top - bottom), 0.0, 1.0);
			vec3 c = cloud_albedo * (sky * (0.3 + 0.6 * h * h) + sun * lit * (0.16 + 0.2 * min(phase, 2.0)));
			float far = 1.0 - exp(-t * 0.00022);
			c = mix(c, enviro_fog_color.rgb, far);
			float a = 1.0 - exp(-dens * dt);
			acc += c * a * trans;
			trans *= 1.0 - a;
			if (trans < 0.02) {
				break;
			}
		}
	}
	float alpha = 1.0 - trans;
	vec3 col = alpha > 1e-4 ? acc / alpha : enviro_fog_color.rgb;
	float d = distance(wp.xz, ro.xz);
	float hz = smoothstep(horizon_fade_start, horizon_fade_end, d);
	if (raw <= 0.0000001) {
		col = mix(col, enviro_fog_color.rgb, hz);
		alpha = mix(alpha, 1.0, hz);
	}
	alpha *= 1.0 - smoothstep(rim_fade_start, rim_fade_end, d);
	if (alpha < 0.004) {
		discard;
	}
	ALBEDO = col;
	ALPHA = alpha;
}
