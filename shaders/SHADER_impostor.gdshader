// IMPOSTORS: the far levels of detail of a tree or fern, drawn from baked views
// (assets/*/textures/impostors). With `billboard` off this is the crossed pair of
// planes; with it on, a single quad that turns about the vertical to face the
// camera. They are lit by their up-leaning vertex normals alone: the baked colour
// already holds the crown's own shading, and a normal map on two crossed planes
// lights one of them and blacks out the other.
shader_type spatial;
render_mode cull_back, skip_vertex_transform;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.33;
uniform bool billboard = false;

global uniform float enviro_wetness;

void vertex() {
	vec3 world;
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	if (billboard) {
		vec3 root = MODEL_MATRIX[3].xyz;
		vec3 to_cam = CAMERA_POSITION_WORLD - root;
		to_cam.y = 0.0;
		to_cam = normalize(to_cam);
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		world = root + right * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
		n = normalize(to_cam * 0.5 + vec3(0.0, 0.85, 0.0));
	} else {
		world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize(mat3(VIEW_MATRIX) * n);
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.a * 1.6 < alpha_cut) {
		discard;       // see SHADER_foliage: not the ALPHA scissor route
	}
	ALBEDO = c.rgb * tint * mix(1.0, 0.8, enviro_wetness);
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
}
