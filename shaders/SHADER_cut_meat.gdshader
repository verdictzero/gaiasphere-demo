// The face a blade leaves on a cow (SCRIPT_cow_slicing.gd): red marbled meat,
// and round its outer edge, where the cut came through the hide, the hide seen
// from its side: a thin dark line of skin, a band of pale fat under it, and a
// darker seam where the fat meets the meat.
//
// UV.x is how far a point is in from the edge of the face, in metres (0 on the
// hide). Faces left by earlier cuts keep theirs when they are cut again, so an
// edge where meat meets meat has no rind, which is right.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D marbling : source_color, filter_linear_mipmap, repeat_enable;
uniform float marble_size = 1.7;           // metres to one repeat of the marbling
uniform float skin_width = 0.02;           // the hide's own thickness
uniform float fat_width = 0.085;           // the fat under it
uniform vec3 skin_color : source_color = vec3(0.16, 0.11, 0.1);
uniform vec3 fat_color : source_color = vec3(0.96, 0.88, 0.76);
uniform vec3 seam_color : source_color = vec3(0.4, 0.04, 0.05);

varying vec3 at;
varying vec3 facing;

void vertex() {
	at = VERTEX;
	facing = NORMAL;
}

void fragment() {
	// The marbling laid flat on the face, whichever way the face lies.
	vec3 n = abs(normalize(facing));
	vec2 flat_uv = n.y > n.x && n.y > n.z ? at.xz : (n.x > n.z ? at.zy : at.xy);
	vec3 meat = texture(marbling, flat_uv / marble_size).rgb;
	float wobble = texture(marbling, flat_uv / (marble_size * 1.9) + 0.3).r;
	float d = UV.x;
	// The fat is not a ruled band: thicker here, thinner there.
	float fat_edge = skin_width + fat_width * (0.55 + 0.9 * wobble);
	float skin = 1.0 - smoothstep(skin_width * 0.7, skin_width, d);
	float fat = 1.0 - smoothstep(fat_edge * 0.85, fat_edge, d);
	float seam = (1.0 - smoothstep(fat_edge, fat_edge + 0.018, d)) * (1.0 - fat);
	vec3 color = mix(meat, seam_color, seam * 0.6);
	color = mix(color, fat_color * (0.9 + 0.1 * wobble), fat);
	color = mix(color, skin_color, skin);
	ALBEDO = color;
	// Meat is wet, fat is waxy, hide is dull.
	ROUGHNESS = mix(mix(0.32, 0.55, fat), 0.9, skin);
	SPECULAR = 0.6;
}
