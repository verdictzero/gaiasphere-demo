extends SceneTree

# THE PLANK KIT'S WALLS, LOOKED AT: the four assembled panels in a row, one close
# with the light raking across it (for the normal map), edge-on, from behind, and
# the three levels of detail of one side by side.
#
#   godot --path . --resolution 1600x900 --script res://tests/RENDER_plank_kit.gd -- --out=/some/folder

var _out := "user://"
var _frames := 0
var _cam: Camera3D
var _sun: DirectionalLight3D
var _shots: Array = []


func _put(file: String, at: Vector3, turn := 0.0) -> void:
	var node: Node3D = (load("res://assets/build/plank_kit/%s.glb" % file) as PackedScene).instantiate()
	node.position = at
	node.rotation.y = turn
	root.add_child(node)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.42, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.76, 0.86)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-38.0, 52.0, 0.0)
	_sun.light_energy = 1.6
	_sun.shadow_enabled = true
	root.add_child(_sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.3, 0.27, 0.22)
	plane.material = dirt
	ground.mesh = plane
	root.add_child(ground)
	for i in 4:
		_put("wall_%s_lod0" % "abcd"[i], Vector3(-3.3 + 2.2 * i, 0, 0))
	for lod in 3:
		_put("wall_a_lod%d" % lod, Vector3(-2.4 + 2.4 * lod, 0, -9.0))
	# A run of wall and a corner, panels butted edge to edge.
	for i in 5:
		_put("wall_%s_lod0" % "abcda"[i], Vector3(-4.0 + 2.0 * i, 0, -18.0))
	_put("wall_c_lod0", Vector3(5.0, 0, -17.0), -PI * 0.5)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_cam.current = true
	_shots = [
		["kit_walls", Vector3(0.0, 1.5, 9.0), Vector3(0.0, 1.0, 0), Vector3(-38, 52, 0)],
		["kit_close", Vector3(-2.6, 1.3, 2.7), Vector3(-3.3, 1.05, 0), Vector3(-20, 82, 0)],
		["kit_edge", Vector3(-5.0, 1.3, 1.5), Vector3(-3.3, 1.0, 0), Vector3(-38, 52, 0)],
		["kit_back", Vector3(-1.0, 1.5, -5.6), Vector3(-1.1, 1.0, 0), Vector3(-38, 200, 0)],
		["kit_lods", Vector3(0.0, 1.4, -2.4), Vector3(0.0, 1.0, -9.0), Vector3(-38, 52, 0)],
		["kit_run", Vector3(-5.5, 1.8, -11.5), Vector3(1.0, 1.0, -18.0), Vector3(-38, 52, 0)],
	]


func _process(_dt: float) -> bool:
	_frames += 1
	var i := (_frames - 1) / 12
	if i >= _shots.size():
		quit(0)
		return true
	if (_frames - 1) % 12 == 0:
		_cam.look_at_from_position(_shots[i][1], _shots[i][2])
		_sun.rotation_degrees = _shots[i][3]
	elif (_frames - 1) % 12 == 11:
		root.get_texture().get_image().save_png(_out.path_join(String(_shots[i][0]) + ".png"))
	return false
