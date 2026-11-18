// WATER: the rivers and the mere. A lit surface that reflects the sky and the
// sun, lets the bed show through where it is shallow, darkens and tints with
// depth, bends what is under it, and foams along the shore and down the rapids.
//
// What the mesh carries (SCRIPT_river_water.gd):
//   UV       metres down the river, signed metres across it
//   UV2      x: 0 mid-stream to 1 at the bank;  y: how much the water is running
//   COLOR    g fades the water out where a river leaves the island, b at its spring
//   TANGENT  downstream
//   CUSTOM0  x flow time, z steepness
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;

// Read by the mesher to lay the mere's rows out; kept so its numbers stand.
uniform float ripple_scale = 12.0;
uniform float ripple_stretch = 1.4;

uniform vec3 shallow_color : source_color = vec3(0.10, 0.17, 0.13);
uniform vec3 deep_color : source_color = vec3(0.012, 0.035, 0.032);
// Metres of water you can see through.
uniform float clarity = 2.6;
uniform float refraction = 0.035;
uniform float wave_size = 3.2;
uniform float wave_strength : hint_range(0.0, 2.0) = 0.55;
uniform float flow_speed = 0.9;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.06;
uniform vec3 foam_color : source_color = vec3(0.82, 0.86, 0.84);
uniform float shore_foam = 0.22;        // metres of water under the shore's foam line
uniform float rapids_foam = 1.0;

global uniform vec3 enviro_light_dir;
global uniform vec4 enviro_light_color;
global uniform vec4 enviro_ambient;
global uniform vec4 enviro_wind;
global uniform float enviro_wetness;

varying vec3 world_pos;
varying vec4 flow;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = CUSTOM0;
	float still = 1.0 - clamp(UV2.y, 0.0, 1.0);
	VERTEX.y += sin(world_pos.x * 0.21 + TIME * 0.7) * cos(world_pos.z * 0.17 - TIME * 0.5)
			* 0.025 * still * (0.4 + enviro_wind.z);
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	vec4 p = inv_proj * vec4(uv * 2.0 - 1.0, texture(depth_tex, uv).r, 1.0);
	return -p.z / p.w;
}

void fragment() {
	float running = clamp(UV2.y, 0.0, 1.0);
	float steep = clamp(flow.z, 0.0, 1.0) * running;
	float chop = wave_strength * (0.55 + 0.6 * enviro_wind.z + 0.9 * steep + 0.5 * enviro_wetness);

	// Running water carries its ripples downstream in the river's own frame;
	// still water drifts them with the wind over the world.
	float pace = flow_speed * (1.0 + 2.5 * steep);
	vec2 r1 = vec2(UV.x - TIME * pace, UV.y) / wave_size;
	vec2 r2 = vec2(UV.x * 0.7 - TIME * pace * 1.6, UV.y * 0.7 + 3.1) / (wave_size * 0.43);
	vec2 wind = enviro_wind.xy * TIME * 0.12;
	vec2 s1 = (world_pos.xz + wind) / (wave_size * 1.7);
	vec2 s2 = (world_pos.zx * vec2(1.0, -1.0) - wind * 1.6) / (wave_size * 0.6);
	vec3 n = mix(texture(wave_a, s1).xyz + texture(wave_b, s2).xyz,
			texture(wave_a, r1).xyz + texture(wave_b, r2).xyz, running) - 1.0;
	n = normalize(vec3(n.xy * chop, 1.0));

	// How much water lies between the surface and what is behind it.
	float surface_z = -VERTEX.z;
	float thick = max(linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX) - surface_z, 0.0);
	vec2 bent = SCREEN_UV + n.xy * refraction * clamp(thick, 0.0, 1.0) / (1.0 + surface_z * 0.08);
	float thick_bent = linear_depth(bent, INV_PROJECTION_MATRIX) - surface_z;
	if (thick_bent < 0.0) {
		bent = SCREEN_UV;            // never pull something in front of the water into it
	} else {
		thick = thick_bent;
	}
	vec3 behind = texture(screen_tex, bent).rgb;

	// Depth takes the red first, then everything: the bed goes green, then dark.
	vec3 through = exp(-thick / clarity * vec3(1.7, 1.0, 1.25));
	float daylight = clamp(enviro_light_dir.y, 0.0, 1.0);
	vec3 light = enviro_ambient.rgb * 1.6 + enviro_light_color.rgb * daylight * 0.8;
	vec3 body = mix(deep_color, shallow_color, exp(-thick / (clarity * 0.7))) * light;
	vec3 under = behind * through + body * (1.0 - through);

	// Foam: a ragged line at the shore, and streaks where the river falls fast.
	float grain = texture(foam_tex, mix(world_pos.xz * 0.35, vec2(UV.x * 0.5 - TIME * pace * 0.5, UV.y * 0.5), running)).r;
	float shore = (1.0 - smoothstep(0.0, shore_foam, thick)) * smoothstep(0.25, 0.75, grain + 0.25);
	float rapids = smoothstep(0.35, 0.9, steep * rapids_foam) * smoothstep(0.4, 0.75, grain);
	float foam = clamp(shore * 0.75 + rapids, 0.0, 1.0);

	ALBEDO = foam_color * foam;
	EMISSION = under * (1.0 - foam);
	ROUGHNESS = mix(surface_roughness, 0.7, foam);
	METALLIC = 0.0;
	SPECULAR = 0.4;
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	// A soft edge where the water meets the bank, and where a river ends.
	ALPHA = smoothstep(0.0, 0.05, thick) * clamp(COLOR.g, 0.0, 1.0) * clamp(COLOR.b, 0.0, 1.0);
}
