class_name PowerKit
extends RefCounted

# THE POWER KIT'S PARTS, READY TO DRAW (assets/power: tools/build_power_kit.py,
# tools/build_power_impostors.py): the junction box, the light pole, the battery
# box, the plug, the solar panel and its box, actuator and support.
#
# Each has a chain of meshes, each about half the last (`lods`: the first few
# textured, the rest in their vertices' own colours with no texture), and after them
# one more level that is not a mesh of it at all: an IMPOSTOR, a single upright
# quad turned to the eye and drawn from eight baked pictures of the part
# (`impostor`: its mesh and its material). `distances` says where each level
# hands over to the next, for a part of that size.
#
# Nothing places these yet: this is what a builder of them will draw from.

const FOLDER := "res://assets/power/"

static var _manifest := {}
static var _lods := {}
static var _impostors := {}
static var _quad: QuadMesh
static var _flat: StandardMaterial3D


static func names() -> PackedStringArray:
	return PackedStringArray(_entries().keys())


static func _entries() -> Dictionary:
	if _manifest.is_empty():
		for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "manifest.json")):
			_manifest[String(entry["name"])] = entry
	return _manifest


## The part's own entry: its size, where its lowest corner is, its levels' triangles.
static func about(part: String) -> Dictionary:
	return _entries().get(part, {})


## Every mesh level of a part, finest first.
static func lods(part: String) -> Array:
	if not _lods.has(part):
		var out: Array = []
		for k in int(about(part).get("levels", 0)):
			var scene := (load("%s%s_lod%d.glb" % [FOLDER, part, k]) as PackedScene).instantiate()
			for mi in scene.find_children("*", "MeshInstance3D", true, false):
				var mesh := (mi as MeshInstance3D).mesh
				# (A level with no texture is drawn in its vertices' own colours.)
				for surface in mesh.get_surface_count():
					var was := mesh.surface_get_material(surface)
					if was != null and was.resource_name == "power_flat":
						mesh.surface_set_material(surface, _flat_material())
				out.append(mesh)
				break
			scene.free()
		_lods[part] = out
	return _lods[part]


static func _flat_material() -> StandardMaterial3D:
	if _flat == null:
		_flat = StandardMaterial3D.new()
		_flat.resource_name = "power_flat"
		_flat.vertex_color_use_as_albedo = true
		# (Darker than the colours alone: the textured levels are grimed and part
		# metal, and the plain ones must not jump out brighter as they take over.)
		_flat.albedo_color = Color(0.6, 0.6, 0.6)
		_flat.metallic = 0.45
		_flat.roughness = 0.6
		_flat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _flat


## The part's last level: [the quad, its material]. The same quad for every part;
## the material is the part's own.
static func impostor(part: String) -> Array:
	# (A part that lies flat has none: its last mesh is its last level.)
	if not about(part).has("impostor"):
		return []
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(2.0, 1.0)
	if not _impostors.has(part):
		var info: Dictionary = about(part).get("impostor", {})
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/SHADER_part_impostor.gdshader")
		mat.set_shader_parameter("albedo_tex", load("%s%s_impostor.png" % [FOLDER, part]))
		mat.set_shader_parameter("views", float(info.get("views", 8)))
		mat.set_shader_parameter("half_wide", float(info.get("half_wide", 1.0)))
		mat.set_shader_parameter("tall", float(info.get("tall", 1.0)))
		mat.set_shader_parameter("mid", float(info.get("mid", 0.0)))
		_impostors[part] = mat
	return [_quad, _impostors[part]]


## Where each level hands over to the next, metres: one distance for each mesh
## level (the last is where the impostor takes over), spread evenly by ratio from
## where the finest stops being worth it to where the part is small enough on
## screen to be a picture. By the part's size, so a plug steps down within a few
## metres and a light pole holds its shape a good way off.
static func distances(part: String) -> Array:
	var info := about(part)
	var size: Array = info.get("size_m", [1.0, 1.0, 1.0])
	var big := maxf(float(size[0]), maxf(float(size[1]), float(size[2])))
	var levels := int(info.get("levels", 0))
	var textured := clampi(int(info.get("textured", levels)), 1, levels)
	# The textured levels to where the part's texture can no longer be made out;
	# the plain ones from there to where the part is small enough to be a picture.
	var first := maxf(big * 2.5, 3.0)
	var plain := maxf(big * 9.0, 22.0)
	var last := maxf(clampf(big * 30.0, 45.0, 240.0), plain * 1.5)
	var out: Array = []
	for k in levels:
		if k < textured:
			out.append(first * pow(plain / first, float(k + 1) / float(textured)))
		else:
			out.append(plain * pow(last / plain, float(k - textured + 1) / float(maxi(levels - textured, 1))))
	return out
