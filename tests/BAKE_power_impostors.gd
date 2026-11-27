extends SceneTree

# THE POWER KIT'S IMPOSTORS, BAKED: each piece (its finest level) pictured from
# EIGHT sides round the upright, square on, under a soft even light, on nothing,
# at twice the size it will be kept at; tools/build_power_impostors.py packs
# the pictures into the piece's atlas and writes its last level, a single quad.
#
#   godot --path . --script res://tests/BAKE_power_impostors.gd
#   python3 tools/build_power_impostors.py
#
# Writes renders/power_bake/<piece>_<view>.png and renders/power_bake/sizes.json.

const VIEWS := 8
const TALLEST := 256            # texels along a piece's longer side, as kept
const OVER := 2                 # baked this many times that

var _pieces: Array = []
var _i := 0
var _view := 0
var _port: SubViewport
var _cam: Camera3D
var _model: Node3D
var _wait := 0
var _sizes := {}


func _initialize() -> void:
	_pieces = JSON.parse_string(FileAccess.get_file_as_string("res://assets/power/manifest.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders/power_bake"))
	_port = SubViewport.new()
	_port.own_world_3d = true
	_port.transparent_bg = true
	_port.msaa_3d = Viewport.MSAA_4X
	_port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_port)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_port.add_child(we)
	# A little light from above and before the eye, for the form; no shadows.
	var key := DirectionalLight3D.new()
	key.light_energy = 0.55
	key.shadow_enabled = false
	_port.add_child(key)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_port.add_child(_cam)
	_cam.add_child(Node3D.new())
	key.name = "Key"
	_next()


func _next() -> void:
	if _model != null:
		_model.queue_free()
		_model = null
	if _i >= _pieces.size():
		return
	var piece: Dictionary = _pieces[_i]
	_model = (load("res://assets/power/%s_lod0.glb" % piece["name"]) as PackedScene).instantiate()
	_port.add_child(_model)
	# How far it reaches from its own upright, and how tall it stands.
	var reach := 0.0
	var low := 1e9
	var high := -1e9
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = (mi as MeshInstance3D).transform * v
				reach = maxf(reach, Vector2(p.x, p.z).length())
				low = minf(low, p.y)
				high = maxf(high, p.y)
	reach *= 1.03
	var tall := (high - low) * 1.03
	var mid := (high + low) * 0.5
	var per := float(TALLEST) / maxf(reach * 2.0, tall)
	var cell := Vector2i(maxi(int(ceil(reach * 2.0 * per)), 8), maxi(int(ceil(tall * per)), 8))
	_port.size = cell * OVER
	# (Orthogonal, its size the view's height in metres.)
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = float(cell.y) / per
	_cam.near = 0.05
	_cam.far = reach * 4.0 + 10.0
	_sizes[String(piece["name"])] = {"cell": [cell.x, cell.y], "half_wide": float(cell.x) / per * 0.5, "tall": float(cell.y) / per,
		"mid": mid, "views": VIEWS}
	_model.set_meta(&"reach", reach)
	_model.set_meta(&"mid", mid)
	_view = 0
	_aim()


func _aim() -> void:
	var a := TAU * float(_view) / float(VIEWS)
	var reach := float(_model.get_meta(&"reach"))
	var mid := float(_model.get_meta(&"mid"))
	var from := Vector3(sin(a), 0.0, cos(a))
	_cam.position = Vector3(0, mid, 0) + from * (reach * 2.0 + 2.0)
	_cam.look_at(Vector3(0, mid, 0))
	var key := _port.get_node("Key") as DirectionalLight3D
	key.look_at_from_position(from * 2.0 + Vector3.UP * 2.0, Vector3.ZERO)
	_wait = 4


func _process(_d: float) -> bool:
	if _i >= _pieces.size():
		var f := FileAccess.open("res://renders/power_bake/sizes.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(_sizes, " "))
		f.close()
		print("impostors: %d pieces baked" % _pieces.size())
		quit(0)
		return true
	_wait -= 1
	if _wait > 0:
		return false
	_port.get_texture().get_image().save_png("res://renders/power_bake/%s_%d.png" % [_pieces[_i]["name"], _view])
	_view += 1
	if _view >= VIEWS:
		_i += 1
		_next()
	else:
		_aim()
	return false
