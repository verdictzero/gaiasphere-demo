// A BUILT PART'S LAST LEVEL: one upright quad turned to the eye about the
// vertical, drawn from the part's own baked pictures (assets/power/*_impostor.png:
// `views` of them in a row, the first from the part's +Z, each next an eighth of
// a turn on toward its +X; tools/build_power_impostors.py). WHICH picture is by
// where the eye stands round the part IN THE PART'S OWN FRAME, so a part turned
// on its base shows the side that is really toward you.
// The quad's mesh is two units wide and one tall about its middle; the instance's
// scale is the part's, and `half_wide`, `tall` and `mid` are the part's own
// (assets/power/manifest.json).
shader_type spatial;
render_mode cull_disabled, skip_vertex_transform, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float views = 8.0;
uniform float half_wide = 1.0;
uniform float tall = 1.0;
uniform float mid = 0.0;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform vec3 tint : source_color = vec3(1.0);

#include "res://shaders/SHADERINC_lod_fade.gdshaderinc"

varying float view_at;

void vertex() {
	lod_keep = lod_fade_window(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - root;
	to_cam.y = 0.0;
	to_cam = normalize(to_cam + vec3(0.0, 0.0, 1e-5));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	// The eye's bearing round the part, in the part's own frame: 0 at its +Z,
	// a quarter turn at its +X.
	vec3 mx = MODEL_MATRIX[0].xyz / sx;
	vec3 mz = normalize(MODEL_MATRIX[2].xyz);
	float turn = atan(dot(to_cam, mx), dot(to_cam, mz)) / 6.2831853;
	view_at = mod(floor(turn * views + 0.5) + views, views);
	vec3 world = root + right * (VERTEX.x * half_wide * sx) + vec3(0.0, (mid + VERTEX.y * tall) * sy, 0.0);
	if (lod_fade_gone(lod_keep)) {
		world = root;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	// Lit as something upright that faces you, leaning up a little.
	NORMAL = normalize(mat3(VIEW_MATRIX) * normalize(to_cam * 0.8 + vec3(0.0, 0.6, 0.0)));
}

void fragment() {
	vec4 c = texture(albedo_tex, vec2((view_at + UV.x) / views, UV.y));
	if (c.a < alpha_cut || lod_fade_discard(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = c.rgb * tint;
	ROUGHNESS = 0.7;
	METALLIC = 0.0;
	SPECULAR = 0.2;
}
