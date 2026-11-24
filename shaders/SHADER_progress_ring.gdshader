// A RING THAT FILLS, turned to the eye: how far along something is (a cut of beef
// on the fire, SCRIPT_cooking.gd). It fills clockwise from the top. Cut out, not
// blended, so it shows whatever is behind it and under water too.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

instance uniform float progress = 0.0;
uniform vec3 full_color : source_color = vec3(1.0, 0.72, 0.22);
uniform vec3 done_color : source_color = vec3(0.45, 0.95, 0.4);
uniform vec3 empty_color : source_color = vec3(0.3, 0.3, 0.32);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r < 0.56 || r > 0.98) {
		discard;
	}
	float turn = fract(atan(p.x, -p.y) / 6.2832 + 1.0);
	bool rim = r < 0.63 || r > 0.91;
	vec3 fill = progress >= 0.999 ? done_color : full_color;
	ALBEDO = rim ? vec3(0.0) : (turn < progress ? fill : empty_color);
}
