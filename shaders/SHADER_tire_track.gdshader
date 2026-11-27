// A TYRE'S TRACK ON THE GROUND (SCRIPT_uni_truck.gd): a ribbon laid where the
// wheel ran, darkening the ground under it in the tread's own pattern. UV.x is
// across the track, UV.y metres along it; COLOR.a how fresh it is (it fades).
// Drawn a hair nearer the eye than it lies, so the ground under it never shows
// through it.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

uniform vec3 tint : source_color = vec3(0.07, 0.055, 0.04);
uniform float strength : hint_range(0.0, 1.0) = 0.6;
// Metres from one tread block to the next along the track.
uniform float block = 0.42;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// (Depth runs backwards: nearer is greater.)
	POSITION.z += 0.00004 * POSITION.w;
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	// Chevrons: bars swept back from the middle to both edges, a groove between.
	float bar = smoothstep(0.2, 0.32, abs(fract(UV.y / block - across * 0.55) - 0.5));
	// A rib down the middle and a clean edge either side, soft at the very rim.
	float rib = 1.0 - smoothstep(0.05, 0.1, across);
	float edge = 1.0 - smoothstep(0.82, 1.0, across);
	float pressed = max(bar * 0.85 + 0.15, rib) * edge;
	ALBEDO = tint;
	ALPHA = pressed * strength * COLOR.a;
}
