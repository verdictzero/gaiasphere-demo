extends SceneTree

# THE WALL PANEL, LOOKED AT: three-quarter front, edge-on, the back, and a short
# run of them as a wall, with the three levels of detail side by side.
#
#   godot --path . --resolution 1600x900 --script res://tests/RENDER_wall_panel.gd -- --out=/some/folder

var _out := "user://"
var _frames := 0
var _cam: Camera3D
var _shots: Array = []


func _panel(lod: int, at: Vector3, turn := 0.0) -> Node3D:
	var node: Node3D = (load("res://assets/build/wall_plank/wall_plank_lod%d.glb" % lod) as PackedScene).instantiate()
	node.position = at
	node.rotation.y = turn
	root.add_child(node)
	return node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.42, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.76, 0.86)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 52.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.3, 0.27, 0.22)
	plane.material = dirt
	ground.mesh = plane
	root.add_child(ground)
	# One of each level, then a wall of four.
	for lod in 3:
		_panel(lod, Vector3(-2.6 + 2.6 * lod, 0, 0))
	for i in 4:
		_panel(0, Vector3(-3.0 + 2.0 * i, 0, -8.0))
	_panel(0, Vector3(4.0, 0, -7.0), -PI * 0.5)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_cam.current = true
	_shots = [
		["panel_front", Vector3(-1.4, 1.5, 5.4), Vector3(-2.6, 1.0, 0)],
		["panel_edge", Vector3(-4.1, 1.3, 1.6), Vector3(-2.6, 1.0, 0)],
		["panel_back", Vector3(-1.2, 1.5, -4.6), Vector3(-2.6, 1.0, 0)],
		["panel_lods", Vector3(0.0, 1.4, 8.6), Vector3(0.0, 1.0, 0)],
		["panel_wall", Vector3(-4.5, 1.7, -2.2), Vector3(1.0, 1.0, -8.0)],
	]


func _process(_dt: float) -> bool:
	_frames += 1
	var i := (_frames - 1) / 12
	if i >= _shots.size():
		quit(0)
		return true
	if (_frames - 1) % 12 == 0:
		_cam.look_at_from_position(_shots[i][1], _shots[i][2])
	elif (_frames - 1) % 12 == 11:
		root.get_texture().get_image().save_png(_out.path_join(String(_shots[i][0]) + ".png"))
	return false
