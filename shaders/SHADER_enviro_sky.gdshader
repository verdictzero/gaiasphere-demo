// THE SKY: atmosphere gradient, sun, moon with a phase, stars, and a raymarched
// volumetric cloud layer lit by whichever of the sun and moon is up. Everything it
// needs is written each frame by scripts/world/SCRIPT_enviro.gd.
//
// The clouds are marched in the half-resolution pass and composited in the full
// one; the radiance cubemap (ambient light, reflections) gets a cheap stand-in.
shader_type sky;
render_mode use_half_res_pass;

uniform vec3 zenith_color : source_color = vec3(0.1, 0.25, 0.6);
uniform vec3 horizon_color : source_color = vec3(0.5, 0.65, 0.8);
uniform vec3 ground_color : source_color = vec3(0.2, 0.22, 0.25);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0);
uniform float sun_energy = 1.0;
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.6, 0.3);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 moon_color : source_color = vec3(0.6, 0.7, 1.0);
uniform float moon_energy = 0.0;
uniform float moon_phase = 0.5;          // 0 new, 0.5 full, 1 new
uniform float stars = 0.0;

uniform sampler3D cloud_shape : repeat_enable, filter_linear;
uniform sampler2D cloud_weather : repeat_enable, filter_linear;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_density = 0.035;
uniform float cloud_base = 850.0;
uniform float cloud_top = 3000.0;
uniform vec3 cloud_wind = vec3(0.0);      // metres the field has drifted
uniform vec3 cloud_light_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 cloud_light_color : source_color = vec3(1.0);
uniform vec3 cloud_ambient : source_color = vec3(0.4, 0.45, 0.55);
uniform int cloud_steps = 80;
uniform int cloud_light_steps = 3;
uniform float flash = 0.0;
// How much the cloud opens toward the sun (0 none): set when the sun is low.
uniform float sun_gap = 0.0;                // lightning

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float cloud_at(vec3 p, bool cheap) {
	float h = (p.y - cloud_base) / (cloud_top - cloud_base);
	if (h <= 0.0 || h >= 1.0) {
		return 0.0;
	}
	vec3 q = p + cloud_wind;
	float weather = texture(cloud_weather, q.xz / 14000.0).r * 0.65
			+ texture(cloud_weather, q.xz / 4300.0 + 0.37).r * 0.35;
	float shape = texture(cloud_shape, q / 3100.0).r;
	// Flat bases, rounded tops.
	float profile = smoothstep(0.0, 0.1, h) * smoothstep(1.0, 0.35, h);
	// The deck breaks toward the low sun, far out, so it shines in under the cloud.
	float toward = dot(normalize(p.xz), normalize(sun_dir.xz + vec2(1e-4)));
	float gap = smoothstep(0.55, 0.97, toward) * smoothstep(2500.0, 9000.0, length(p.xz)) * sun_gap;
	float d = (weather * 0.62 + shape * 0.38) - (1.0 - (cloud_coverage - gap * 0.5) * 1.08);
	d = clamp(d * 1.5, 0.0, 1.0);
	d = d * d * (3.0 - 2.0 * d) * profile;
	if (!cheap && d > 0.0) {
		float detail = texture(cloud_shape, q / 620.0 + cloud_wind / 2600.0).r;
		d = clamp(d - detail * 0.34 * (1.0 - d), 0.0, 1.0);
	}
	return d * cloud_density;
}

vec3 atmosphere(vec3 dir) {
	float up = max(dir.y, 0.0);
	vec3 col = mix(horizon_color, zenith_color, pow(up, 0.42));
	col = mix(col, ground_color, smoothstep(0.0, -0.18, dir.y));
	float sd = max(dot(dir, sun_dir), 0.0);
	// Haze round the sun: wide and warm near the horizon.
	float low = 1.0 - smoothstep(0.0, 0.45, abs(dir.y));
	col += sun_glow_color * sun_energy * (pow(sd, 6.0) * 0.22 * low + pow(sd, 64.0) * 0.35);
	return col;
}

vec3 bodies(vec3 dir) {
	vec3 col = vec3(0.0);
	float sd = dot(dir, sun_dir);
	col += sun_color * sun_energy * 40.0 * smoothstep(0.99985, 0.99993, sd);
	float md = dot(dir, moon_dir);
	if (md > 0.9993 && moon_energy > 0.0) {
		// The disc as a little lit sphere: the phase moves its terminator.
		vec3 right = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)));
		vec3 upv = cross(right, moon_dir);
		vec2 disc = vec2(dot(dir, right), dot(dir, upv)) / 0.0374;
		float r2 = dot(disc, disc);
		if (r2 < 1.0) {
			vec3 n = vec3(disc, sqrt(1.0 - r2));
			float a = moon_phase * 6.28318;
			float lit = smoothstep(-0.05, 0.15, dot(n, vec3(sin(a), 0.0, -cos(a))));
			float maria = 0.75 + 0.25 * hash13(floor(n * 9.0));
			col += moon_color * (0.02 + lit) * maria * 3.5 * moon_energy * smoothstep(1.0, 0.9, r2);
		}
	}
	if (stars > 0.01 && dir.y > 0.02) {
		vec3 cell = floor(dir * 260.0);
		float h = hash13(cell);
		if (h > 0.9965) {
			vec3 centre = (cell + 0.5) / 260.0;
			float glint = smoothstep(0.0012, 0.0, length(dir - normalize(centre)) - 0.0004);
			float twinkle = 0.7 + 0.3 * sin(TIME * (2.0 + h * 40.0) + h * 100.0);
			col += vec3(0.8, 0.9, 1.0) * glint * twinkle * stars * (h - 0.9965) * 900.0;
		}
	}
	return col;
}

vec4 clouds(vec3 origin, vec3 dir, float jitter) {
	if (dir.y < 0.015 || cloud_coverage < 0.01) {
		return vec4(0.0);
	}
	float t0 = max((cloud_base - origin.y) / dir.y, 0.0);
	float t1 = min((cloud_top - origin.y) / dir.y, 42000.0);
	if (t1 <= t0) {
		return vec4(0.0);
	}
	float n = float(cloud_steps);
	float dt = (t1 - t0) / n;
	// A little jitter hides the slices; a lot of it is the speckle.
	float t = t0 + dt * (0.25 + 0.5 * jitter);
	float trans = 1.0;
	vec3 light = vec3(0.0);
	float cosang = dot(dir, cloud_light_dir);
	// Two lobes: a bright forward one (the silver lining) and a soft back one.
	float g1 = 0.72;
	float g2 = -0.25;
	float phase = mix((1.0 - g2 * g2) / pow(1.0 + g2 * g2 - 2.0 * g2 * cosang, 1.5),
			(1.0 - g1 * g1) / pow(1.0 + g1 * g1 - 2.0 * g1 * cosang, 1.5), 0.55) * 0.25;
	float lstep = (cloud_top - cloud_base) * 0.5 / float(cloud_light_steps);
	for (int i = 0; i < cloud_steps; i++) {
		vec3 p = origin + dir * t;
		float d = cloud_at(p, false);
		if (d > 0.0) {
			float shade = 0.0;
			for (int j = 1; j <= cloud_light_steps; j++) {
				shade += cloud_at(p + cloud_light_dir * lstep * float(j), true);
			}
			float sun_t = exp(-shade * lstep * 0.45);
			float powder = 1.0 - exp(-d * dt * 2.0);
			float h = (p.y - cloud_base) / (cloud_top - cloud_base);
			vec3 amb = cloud_ambient * (0.45 + 0.75 * h) + vec3(0.7, 0.75, 1.0) * flash * 2.5;
			vec3 s = cloud_light_color * sun_t * min(phase, 1.4) * (0.6 + 1.2 * powder) * 1.5 + amb;
			float a = 1.0 - exp(-d * dt);
			light += s * a * trans;
			trans *= 1.0 - a;
			if (trans < 0.03) {
				break;
			}
		}
		t += dt;
	}
	// Far cloud sinks into the haze.
	float far = exp(-t0 * 0.00006);
	float alpha = (1.0 - trans) * far * smoothstep(0.015, 0.09, dir.y);
	return vec4(light / max(1.0 - trans, 1e-4), alpha);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	if (AT_HALF_RES_PASS) {
		// White noise, not a pattern: the half-resolution pass is filtered on the way
		// up, which turns a regular dither into stripes.
		vec3 j3 = fract(vec3(SCREEN_UV.xyx) * vec3(443.897, 441.423, 437.195));
		j3 += dot(j3, j3.yzx + 19.19);
		float jitter = fract((j3.x + j3.y) * j3.z);
		vec4 c = clouds(POSITION, dir, jitter);
		COLOR = c.rgb;
		ALPHA = c.a;
	} else if (AT_CUBEMAP_PASS) {
		// What lights the world: the sky, greyed by however much cloud covers it.
		vec3 col = atmosphere(dir);
		float cover = smoothstep(0.25, 0.9, cloud_coverage) * smoothstep(0.0, 0.3, dir.y);
		col = mix(col, cloud_ambient * 1.3, cover * 0.8);
		COLOR = col;
	} else {
		vec3 col = atmosphere(dir) + bodies(dir);
		vec4 c = HALF_RES_COLOR;
		col = mix(col, c.rgb, clamp(c.a, 0.0, 1.0));
		COLOR = col;
	}
}
