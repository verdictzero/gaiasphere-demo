// A MODEL'S OWN PAINTED MATERIAL, WITH WEAR LAID OVER IT. Everything a glTF's
// metallic-roughness material carries (colour, metal, roughness, normal map), and
// on top of that a DETAIL layer: a small tile of grime and scratches
// (tools/build_detail_texture.py) projected onto the model from three sides in
// its own space, so it needs no unwrapping and sits still on the model as it
// moves. Multiplied into the colour, roughening where it is grimy, and its bumps
// added to the painted normal map's (whiteout blend), so close to, a surface
// the painted texture only has a pixel or two for has wear across it.
//
// SCRIPT_detail_layer.gd turns a model's StandardMaterial3Ds into this.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform float metallic = 0.0;
uniform float roughness = 1.0;
uniform sampler2D metallic_tex : hint_default_white, filter_linear_mipmap;
uniform vec4 metallic_channel = vec4(0.0, 0.0, 1.0, 0.0);
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap;
uniform vec4 roughness_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_scale = 1.0;

uniform sampler2D detail_grime : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Tiles of the detail per unit of the mesh's own space (SCRIPT_detail_layer.gd
// works it out from how big the mesh is drawn, so a tile is the same size in
// metres on every part).
uniform float detail_tiles = 2.0;
uniform float detail_strength : hint_range(0.0, 1.5) = 1.0;
uniform float detail_bump : hint_range(0.0, 2.0) = 0.6;
// The bumps are laid this many times finer than the grime: a fine, faint grain
// across the metal rather than dents you can pick out.
uniform float detail_normal_density = 8.0;
// Beyond this many metres the detail has faded to nothing (it would only shimmer).
uniform float detail_far = 40.0;

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	obj_pos = VERTEX * detail_tiles;
	obj_normal = NORMAL;
}

void fragment() {
	vec4 base = albedo_color * texture(albedo_tex, UV);
	float metal = metallic * dot(texture(metallic_tex, UV), metallic_channel);
	float rough = roughness * dot(texture(roughness_tex, UV), roughness_channel);
	vec3 painted = texture(normal_tex, UV).xyz * 2.0 - 1.0;
	painted.xy *= normal_scale;

	// Three projections, weighted by how squarely the surface faces each axis.
	vec3 w = pow(abs(obj_normal), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-5);
	float near = 1.0 - smoothstep(detail_far * 0.5, detail_far, length(VERTEX));
	float k = detail_strength * near;
	float grime = texture(detail_grime, obj_pos.zy).r * w.x
			+ texture(detail_grime, obj_pos.xz).r * w.y
			+ texture(detail_grime, obj_pos.xy).r * w.z;
	vec3 np = obj_pos * detail_normal_density;
	vec3 dn = (texture(detail_normal, np.zy).xyz * 2.0 - 1.0) * w.x
			+ (texture(detail_normal, np.xz).xyz * 2.0 - 1.0) * w.y
			+ (texture(detail_normal, np.xy).xyz * 2.0 - 1.0) * w.z;
	dn.xy *= detail_bump * near;

	ALBEDO = base.rgb * mix(1.0, grime, k);
	METALLIC = metal;
	ROUGHNESS = clamp(rough + (1.0 - grime) * 0.35 * k, 0.0, 1.0);
	// Whiteout: the two bumps added, neither flattening the other.
	vec3 n = normalize(vec3(painted.xy + dn.xy, painted.z * max(dn.z, 0.2)));
	NORMAL_MAP = n * 0.5 + 0.5;
}
