// ============================================================================
//  SHADERINC_weather_shelter.gdshaderinc  —  no weather inside what is built
// ============================================================================
// THE WEATHER STOPS AT A ROOM'S WALLS (docs/DOC_build_interiors.md, "Weather";
// the user: "rain snow sandstorm stoppage / repeatable system for masking future
// interior weather"). The rooms BuildInteriors finds in what is built
// (SHADERINC_build_rooms) are where it does not snow, blow sand, or fog. Every
// weather shader asks one of two things:
//
//   weather_open(p)            how much weather there is at the point `p`: 1 out
//                              in it, 0 inside a room. For anything placed at a
//                              point: a flake, a grain, a puff, a raindrop. Take
//                              it once per particle, at its middle, in vertex(),
//                              and multiply the particle's alpha by it.
//
//   weather_open_length(o, d, len)
//                              of the view ray from `o` along unit `d` for `len`
//                              metres, how many metres are out in the weather.
//                              For anything that builds up along the ray (the
//                              dust wall, a fog): integrate over that many
//                              metres, not `len`. From inside a room looking at
//                              its wall it is 0; out through a window to the
//                              hills it is all of it bar the room.
//
// A room's shelter comes up with its light (BuildPrint.room_strength): while a
// print settles the snow inside it thins out with the sky's light. Rooms are
// grown by WEATHER_SHELTER_GROW so a flake in the wall's thickness, which nothing
// shows anyway, is not counted out in it.
//
// A NEW WEATHER (rain, say) is three lines: include this, call weather_open at
// each drop's middle, multiply its alpha. Scripts that need the same answer on
// the CPU (a splash, a sound) ask BuildInteriors.open_at(tree, p).

#ifndef WEATHER_SHELTER_INCLUDED
#define WEATHER_SHELTER_INCLUDED

#include "res://shaders/SHADERINC_build_rooms.gdshaderinc"

const float WEATHER_SHELTER_GROW = 0.25;

// How much weather there is at `p`: 1 out in it, 0 inside a room.
float weather_open(vec3 p) {
	int b = build_room_at(p, WEATHER_SHELTER_GROW);
	return b < 0 ? 1.0 : 1.0 - build_room_strength(b);
}

// Of the ray from `o` along unit `d` for `len` metres, the metres out in the
// weather: `len` less what of it runs through rooms (each as much as it is one).
float weather_open_length(vec3 o, vec3 d, float len) {
	if (build_interior_count <= 0) {
		return len;
	}
	vec3 inv = 1.0 / mix(d, vec3(1e-6), lessThan(abs(d), vec3(1e-6)));
	float inside = 0.0;
	for (int i = 0; i < BUILD_INTERIOR_BOXES; i++) {
		if (i >= build_interior_count) {
			break;
		}
		vec3 lo = bi_fetch(i, 0).xyz - WEATHER_SHELTER_GROW;
		vec3 hi = bi_fetch(i, 1).xyz + WEATHER_SHELTER_GROW;
		vec3 t0 = (lo - o) * inv;
		vec3 t1 = (hi - o) * inv;
		vec3 tmin = min(t0, t1);
		vec3 tmax = max(t0, t1);
		float a = max(max(max(tmin.x, tmin.y), tmin.z), 0.0);
		float b = min(min(min(tmax.x, tmax.y), tmax.z), len);
		if (b > a) {
			inside += (b - a) * build_room_strength(i);
		}
	}
	return max(len - inside, 0.0);
}

#endif
