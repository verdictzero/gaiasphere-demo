// FOLIAGE: fir needles, fern fronds and grass. Lit, alpha-tested cards that sway.
// DOUBLE-SIDED: every card is drawn from both faces. The engine turns the normal
// round on a back face, which would shade the underside of a bough black; the
// fragment shader turns it back, so both faces are lit by the card's one outward
// normal.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.38;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float specular : hint_range(0.0, 1.0) = 0.35;
// SUBSURFACE LIGHT: the colour a leaf passes when lit from behind, and how much.
// Done in light() below, so it is shadowed like any other light.
uniform vec3 backlight : source_color = vec3(0.16, 0.2, 0.06);
uniform float sss_strength : hint_range(0.0, 8.0) = 4.5;
// How far round the back of a leaf the light wraps (0 = hard, like stone).
uniform float wrap : hint_range(0.0, 1.0) = 0.45;
// Metres the tips swing in a full wind, and how hard they shiver.
uniform float wind_bend = 0.5;
uniform float wind_flutter = 0.03;
// The texture holds this many plants side by side; INSTANCE_CUSTOM.x picks one.
uniform float atlas_columns = 1.0;
// GRASS LEAVES THE PICTURE IN TWO STAGES (0 = neither). First it thins: between
// `thin_start` and `thin_end` each clump drops out at its own distance, set by a
// random number it carries, until only `thin_keep` of them are left. Then what
// remains dissolves through a screen-door dither between `fade_start` and
// `fade_end`, where the tiles stop being drawn. Nothing pops and nothing shrinks.
uniform float thin_start = 0.0;
uniform float thin_end = 0.0;
uniform float thin_keep : hint_range(0.0, 1.0) = 0.3;
// The share of the clumps drawn at all (the graphics menu's grass density).
uniform float keep_share : hint_range(0.0, 1.0) = 1.0;
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;
// A PLANT THE PLAYER WALKS INTO GETS OUT OF THE WAY: it dissolves through a dither
// as the camera comes within `near_solid` metres of its root and is gone (every
// pixel culled) by `near_gone`. 0 = stays solid.
uniform float near_gone = 0.0;
uniform float near_solid = 0.0;

#include "res://shaders/SHADERINC_wind.gdshaderinc"
#include "res://shaders/SHADERINC_lod_fade.gdshaderinc"
global uniform float enviro_wetness;

varying vec3 shade;
varying float dissolve;
varying float near_keep;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	lod_keep = lod_fade_window(root, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	dissolve = 0.0;
	near_keep = near_solid > 0.0 ? smoothstep(near_gone, near_solid, distance(root.xz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz.xz)) : 1.0;
	if (fade_end > 0.0) {
		float d = distance(root, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
		dissolve = smoothstep(fade_start, fade_end, d);
		// INSTANCE_CUSTOM.z is the clump's lot: low numbers go first.
		float gone = smoothstep(thin_start, thin_end, d) * (1.0 - thin_keep);
		if (INSTANCE_CUSTOM.z < gone || INSTANCE_CUSTOM.y > keep_share) {
			VERTEX = root;          // every vertex on one point: no triangle is drawn
		}
	}
	VERTEX += wind_offset(VERTEX, UV2, wind_bend, wind_flutter);
	shade = COLOR.rgb;
	// Only an atlas has per-instance data; without it INSTANCE_CUSTOM is not defined.
	if (atlas_columns > 1.5) {
		// The whole part of the mesh's U is that card's own picture; the plant's
		// variant shifts every card along by the same number of columns.
		UV.x = (mod(floor(UV.x) + floor(INSTANCE_CUSTOM.x + 0.5), atlas_columns) + fract(UV.x)) / atlas_columns;
		shade *= 0.8 + 0.4 * INSTANCE_CUSTOM.y;
	}
	if (lod_fade_gone(lod_keep)) {
		VERTEX = root;
	}
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	// Thin cards lose coverage in the mipmaps; lean on the alpha with distance.
	float a = t.a * (1.0 + clamp(length(VERTEX) / 40.0, 0.0, 1.6));
	// A plain discard, not ALPHA + ALPHA_SCISSOR_THRESHOLD: on the Mobile renderer that
	// route shaded these cards black.
	if (a < alpha_cut || lod_fade_discard(FRAGCOORD.xy)) {
		discard;
	}
	if (near_keep < 1.0) {
		float door = fract(52.9829189 * fract(dot(FRAGCOORD.xy + 17.0, vec2(0.06711056, 0.00583715))));
		if (door >= near_keep) {
			discard;
		}
	}
	if (dissolve > 0.0) {
		float screen = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (dissolve > screen) {
			discard;
		}
	}
	ALBEDO = t.rgb * tint * shade * mix(1.0, 0.8, enviro_wetness);
	ROUGHNESS = mix(roughness, 0.3, enviro_wetness * 0.7);
	SPECULAR = specular;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}


// LEAVES ARE NOT OPAQUE. Three things a plain surface does not do:
//   wrap      light creeps past the edge of the lit side, so foliage never has the
//             hard terminator of a solid
//   through   a leaf lit from behind glows on the side you see, in the colour of
//             what it is made of
//   toward    looking at the sun through a crown, the leaves between you and it
//             light up: the bright rim on a backlit tree
// All of it is multiplied by the shadow, so a branch in the shade of another
// stays dark.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float through = clamp(-ndl, 0.0, 1.0) * 0.5;
	float toward = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0);
	vec3 passed = backlight * sss_strength * (through + toward * 1.4);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (vec3(lit) + passed) / PI;
}
