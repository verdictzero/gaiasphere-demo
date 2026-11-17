// ============================================================================
//  SHADERINC_build_rooms.gdshaderinc  —  where the rooms of what is built are
// ============================================================================
// THE ROOMS AS PUBLISHED (BuildInteriors, scripts/SCRIPT_build_interiors.gd: its
// header has the texture's rows), and the two questions every user of them asks:
// which box is a point in, and how much is that box's room a room (0 while a
// print's light is still to come up, 1 once it has; BuildPrint.room_strength).
//
// Shared by the light inside (SHADERINC_build_interior) and the weather's shelter
// (SHADERINC_weather_shelter). Guarded, so a shader may include both.

#ifndef BUILD_ROOMS_INCLUDED
#define BUILD_ROOMS_INCLUDED

global uniform sampler2D build_interior_data : filter_nearest;
global uniform int build_interior_count;
global uniform vec4 build_interior_bounds;

const int BUILD_INTERIOR_BOXES = 64;

vec4 bi_fetch(int x, int row) {
	return texelFetch(build_interior_data, ivec2(x, row), 0);
}

// The box `q` is in, each box grown by `slack` metres, or -1.
int build_room_at(vec3 q, float slack) {
	if (build_interior_count <= 0 || q.x < build_interior_bounds.x || q.z < build_interior_bounds.y
			|| q.x > build_interior_bounds.z || q.z > build_interior_bounds.w) {
		return -1;
	}
	for (int i = 0; i < BUILD_INTERIOR_BOXES; i++) {
		if (i >= build_interior_count) {
			break;
		}
		vec3 lo = bi_fetch(i, 0).xyz - slack;
		vec3 hi = bi_fetch(i, 1).xyz + slack;
		if (all(greaterThanEqual(q, lo)) && all(lessThanEqual(q, hi))) {
			return i;
		}
	}
	return -1;
}

// How much box `b`'s room is a room, 0 to 1.
float build_room_strength(int b) {
	return clamp(bi_fetch(int(bi_fetch(b, 0).w + 0.5), 8).x, 0.0, 1.0);
}

#endif
