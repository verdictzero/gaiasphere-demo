class_name DetailLayer
extends RefCounted

# WEAR LAID OVER A MODEL'S OWN TEXTURES (SHADER_detailed.gdshader): every opaque
# StandardMaterial3D under a node is swapped for the detailed shader with the
# same colour, metal, roughness and normal map, plus the detail tile
# (assets/detail/textures, made by tools/build_detail_texture.py) projected
# onto it from three sides in each mesh's own space.
#
#     DetailLayer.apply(model)                   # a tile 0.5 m across
#     DetailLayer.apply(model, 0.8, 0.7)         # bigger, and fainter
#
# The tile is the same size in metres on every part, whatever scale each mesh is
# drawn at. Converted materials are shared between meshes drawn at the same scale.

const SHADER := "res://shaders/SHADER_detailed.gdshader"
const GRIME := "res://assets/detail/textures/detail_grime.jpg"
const NORMAL := "res://assets/detail/textures/detail_normal.png"

static var _made := {}       # [source material, tiles] -> ShaderMaterial

## THE LOOK, live (SCRIPT_options_menu.gd's sliders): how many times finer the
## bumps are than the grime, how deep they are, and how strongly the grime shows.
static var grain := 8.0
static var depth := 0.6
static var grime := 1.0


## Every detailed material there is, and every one made from now on, to this look.
static func set_look(new_grain: float, new_depth: float, new_grime: float) -> void:
	grain = new_grain
	depth = new_depth
	grime = new_grime
	for m: ShaderMaterial in _made.values():
		_look(m)


static func _look(m: ShaderMaterial) -> void:
	m.set_shader_parameter("detail_normal_density", grain)
	m.set_shader_parameter("detail_bump", depth)
	m.set_shader_parameter("detail_strength", float(m.get_meta(&"strength", 1.0)) * grime)


static func apply(root: Node, tile_metres := 0.5, strength := 1.0) -> void:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		# Metres per unit of this mesh's own space.
		var scale := (mi.global_basis.get_scale() if mi.is_inside_tree() else _scale_to(root, mi)).x
		var tiles := scale / maxf(tile_metres, 0.01)
		for s in mi.mesh.get_surface_count():
			var src := mi.get_surface_override_material(s)
			if src == null:
				src = mi.mesh.surface_get_material(s)
			var std := src as StandardMaterial3D
			if std == null or std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			mi.set_surface_override_material(s, _detailed(std, tiles, strength))


## The scale a mesh is drawn at under `root`, before either is in the tree.
static func _scale_to(root: Node, mi: Node3D) -> Vector3:
	var t := Transform3D.IDENTITY
	var n: Node = mi
	while n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		if n == root:
			break
		n = n.get_parent()
	return t.basis.get_scale()


static func _detailed(std: StandardMaterial3D, tiles: float, strength: float) -> ShaderMaterial:
	var key := [std.get_instance_id(), snappedf(tiles, 0.001), strength]
	if _made.has(key):
		return _made[key]
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("albedo_color", std.albedo_color)
	if std.albedo_texture != null:
		m.set_shader_parameter("albedo_tex", std.albedo_texture)
	m.set_shader_parameter("metallic", std.metallic)
	m.set_shader_parameter("roughness", std.roughness)
	if std.metallic_texture != null:
		m.set_shader_parameter("metallic_tex", std.metallic_texture)
		m.set_shader_parameter("metallic_channel", _channel(std.metallic_texture_channel))
	if std.roughness_texture != null:
		m.set_shader_parameter("roughness_tex", std.roughness_texture)
		m.set_shader_parameter("roughness_channel", _channel(std.roughness_texture_channel))
	if std.normal_enabled and std.normal_texture != null:
		m.set_shader_parameter("normal_tex", std.normal_texture)
		m.set_shader_parameter("normal_scale", std.normal_scale)
	m.set_shader_parameter("detail_grime", load(GRIME))
	m.set_shader_parameter("detail_normal", load(NORMAL))
	m.set_shader_parameter("detail_tiles", tiles)
	m.set_meta(&"strength", strength)
	_look(m)
	_made[key] = m
	return m


static func _channel(c: BaseMaterial3D.TextureChannel) -> Vector4:
	match c:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return Vector4(1, 0, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0, 0, 0, 1)
	return Vector4(0.299, 0.587, 0.114, 0)
