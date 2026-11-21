// SMOOTH HAND-OVER BETWEEN LEVELS OF DETAIL. Two levels of a plant are both drawn
// through a band round the distance where one gives way to the other, and each
// keeps a complementary share of the screen's pixels: the nearer one thins out
// through a dither exactly as the farther one fills in, plant by plant, by that
// plant's own distance. No pixel is drawn twice and none is left empty, so there
// is no pop and no ghosting, and it costs no blending.
//
// SCRIPT_flora.gd sets the two distances on each MultiMeshInstance3D:
//   lod_in   where this level starts taking over from the nearer one (0: it is the nearest)
//   lod_out  where it hands over to the next, or fades out for good (0: never)
//
//   vertex():    lod_keep = lod_fade_window(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD);
//   fragment():  if (lod_fade_discard(FRAGCOORD.xy)) { discard; }
instance uniform float lod_in = 0.0;
instance uniform float lod_out = 0.0;

const float LOD_BAND = 0.12;       // half the band's width, as a share of the distance

varying flat vec2 lod_keep;        // a pixel is kept when lod_keep.x <= dither < lod_keep.y

// (A varying can only be assigned in vertex() itself, so this returns the window.)
vec2 lod_fade_window(vec3 root, vec3 camera) {
	float d = distance(root, camera);
	return vec2(
			lod_in > 0.0 ? 1.0 - smoothstep(lod_in * (1.0 - LOD_BAND), lod_in * (1.0 + LOD_BAND), d) : 0.0,
			lod_out > 0.0 ? 1.0 - smoothstep(lod_out * (1.0 - LOD_BAND), lod_out * (1.0 + LOD_BAND), d) : 1.0);
}

// True when nothing of this instance is drawn at this level: nearer than where
// the level takes over, or beyond where it hands on. A tile draws every level
// any of its plants need, so most instances at most levels are in this state,
// and the vertex shader folds them to a point (no triangle, nothing to shade)
// instead of drawing them and throwing every pixel away:
//   vertex():    if (lod_fade_gone(lod_keep)) { VERTEX = <the instance's root>; }
bool lod_fade_gone(vec2 keep) {
	return keep.x >= 1.0 || keep.y <= 0.0;
}

bool lod_fade_discard(vec2 pixel) {
	float dither = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
	return dither < lod_keep.x || dither >= lod_keep.y;
}
