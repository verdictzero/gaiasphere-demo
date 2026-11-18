// A BANK OF FOG: one soft camera-facing sheet of a drifting patch of mist. Lit by
// hand from the same sun and sky as everything else, glowing when the sun is
// behind it, and fading out where it meets the ground or the camera so it never
// shows an edge. SCRIPT_fog_patches.gd scatters them.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
uniform float soft_depth = 9.0;      // metres over which it fades into what it touches
uniform float near_fade = 14.0;
uniform float far_start = 260.0;
uniform float far_end = 360.0;

global uniform vec3 enviro_light_dir;
global uniform vec4 enviro_light_color;
global uniform vec4 enviro_ambient;
global uniform vec4 enviro_fog_color;
global uniform vec4 enviro_wind;

varying float seed;
varying vec3 world_centre;

void vertex() {
	seed = INSTANCE_CUSTOM.x;
	world_centre = MODEL_MATRIX[3].xyz;
	// Face the camera about the vertical, keeping the instance's size.
	vec3 to_cam = CAMERA_POSITION_WORLD - world_centre;
	to_cam.y = 0.0;
	to_cam = normalize(to_cam);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 drift = vec3(enviro_wind.x, 0.0, enviro_wind.y) * sin(enviro_wind.w * 0.05 + seed * 6.28) * 6.0;
	vec3 world = world_centre + drift + right * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float body = (1.0 - smoothstep(0.25, 1.0, abs(c.x))) * (1.0 - smoothstep(0.1, 1.0, abs(c.y)));
	vec2 flow = vec2(enviro_wind.w * 0.004, 0.0);
	float n = texture(noise_tex, UV * vec2(1.3, 0.6) + seed * 7.3 + flow).r
			* 0.65 + texture(noise_tex, UV * vec2(3.1, 1.4) - seed * 3.1 - flow * 1.7).r * 0.35;
	float a = body * smoothstep(0.28, 0.72, n) * opacity;

	// Fade into whatever solid thing is behind it, and out as the camera walks in.
	vec4 p = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	float behind = -p.z / p.w;
	float here = -VERTEX.z;
	a *= clamp((behind - here) / soft_depth, 0.0, 1.0);
	a *= smoothstep(0.0, near_fade, here) * (1.0 - smoothstep(far_start, far_end, here));
	if (a < 0.004) {
		discard;
	}
	// Fog between the eye and the sun glows; fog with the sun behind the eye is flat.
	vec3 view = normalize((INV_VIEW_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	float toward = max(dot(view, normalize(enviro_light_dir)), 0.0);
	// THE SUN ON IT. The top of a bank stands in the light and its foot in the shade
	// of the trees and of itself; thin wisps let more through than the dense middle;
	// and all of it takes the sun's colour, so at golden hour the fog is gold.
	float height = 1.0 - UV.y;
	float thin = 1.0 - smoothstep(0.35, 0.8, n) * body;
	float sunlit = (0.25 + 0.75 * smoothstep(0.1, 0.85, height)) * (0.55 + 0.45 * thin);
	vec3 shade = enviro_fog_color.rgb * 0.55 + enviro_ambient.rgb * 0.25;
	vec3 col = shade + enviro_light_color.rgb * sunlit * (0.2 + 0.85 * pow(toward, 3.0));
	ALBEDO = col;
	ALPHA = a;
}
