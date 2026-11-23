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
uniform float fat_width = 0.17;            // the fat under it
uniform vec3 skin_color : source_color = vec3(0.16, 0.11, 0.1);
uniform vec3 fat_color : source_color = vec3(0.96, 0.88, 0.76);
uniform vec3 seam_color : source_color = vec3(0.4, 0.04, 0.05);

uniform float cell_size = 0.042;           // metres across one cell of the rind
uniform vec3 pore_color : source_color = vec3(0.5, 0.09, 0.09);
uniform float pore_depth = 0.95;           // how dark the hollows of the cells are

varying vec3 at;
varying vec3 facing;

void vertex() {
	at = VERTEX;
	facing = NORMAL;
}

vec2 cell_point(vec2 cell) {
	return fract(sin(vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)))) * 43758.5453);
}

// CELLS, as in the inside of a bone: (how far to the nearest cell's middle, how
// near the wall between it and the next), both 0 to 1.
vec2 cells(vec2 p) {
	vec2 base = floor(p);
	float nearest = 8.0;
	float second = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = base + vec2(float(x), float(y));
			float d = distance(p, cell + cell_point(cell));
			if (d < nearest) {
				second = nearest;
				nearest = d;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return vec2(nearest, second - nearest);
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
	// THE RIND IS A HONEYCOMB, like marrow: pale walls round small dark hollows,
	// the hollows opening up toward the meat and closing to solid at the skin.
	vec2 c = cells(flat_uv / cell_size);
	float wall = 1.0 - smoothstep(0.1, 0.24, c.y);
	float into = smoothstep(skin_width, fat_edge, d);
	float hollow = (1.0 - wall) * smoothstep(0.0, 0.3, 0.7 - c.x) * mix(0.25, 1.0, into);
	vec3 rind = mix(fat_color * (0.9 + 0.1 * wobble), pore_color, hollow * pore_depth);
	color = mix(color, rind, fat);
	color = mix(color, skin_color, skin);
	ALBEDO = color;
	// Meat is wet, fat is waxy, hide is dull.
	ROUGHNESS = mix(mix(0.32, mix(0.6, 0.3, hollow), fat), 0.9, skin);
	SPECULAR = 0.6;
}
