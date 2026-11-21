// WIND for anything that grows. The meshes carry what to move in UV2:
// x how far this vertex swings (0 at the root), y a phase so neighbours differ.
// Use with `render_mode world_vertex_coords` and call wind_offset() on VERTEX.
global uniform vec4 enviro_wind;      // xz direction x strength, strength, time

vec3 wind_offset(vec3 world_pos, vec2 sway, float bend, float flutter) {
	float t = enviro_wind.w;
	// A STORM IS STRONG, NOT FRANTIC. Past a stiff breeze the swing stops growing
	// in step with the wind: a tree in a gale leans and labours, it does not whip.
	float calm = 1.0 / (1.0 + 0.75 * max(enviro_wind.z - 0.7, 0.0));
	float ph = sway.y * 6.2832 + world_pos.x * 0.045 + world_pos.z * 0.061;
	float gust = 0.6 + 0.4 * sin(t * 0.37 + world_pos.x * 0.011 - world_pos.z * 0.013);
	float swing = sin(t * 1.1 + ph) * 0.6 + sin(t * 2.3 + ph * 1.7) * 0.3 + 0.35;
	vec3 push = vec3(enviro_wind.x, 0.0, enviro_wind.y) * (swing * gust * sway.x * bend * calm);
	// In a gale a plant does not only swing further: it is held over, leaning
	// downwind, and thrashes about that lean.
	float gale = smoothstep(0.7, 2.0, enviro_wind.z);
	push += vec3(enviro_wind.x, 0.0, enviro_wind.y) * gale * 0.3 * sway.x * bend * calm;
	push.y -= gale * 0.06 * sway.x * bend * enviro_wind.z * calm;
	float shiver = sin(t * 8.5 + world_pos.x * 2.3 + world_pos.y * 1.7 + world_pos.z * 1.9);
	push.y += shiver * flutter * sway.x * min(enviro_wind.z, 1.1) * (1.0 + gale * 0.35);
	return push;
}
