extends SceneTree

# THE PLANK KIT, LOOKED AT: a hut put together from its panels (walls, floor,
# gables, a 45 degree roof), then one of each kind stood apart, every wall
# variant in a row, and the inside of the hut.
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
	# A HUT, four metres by two: walls, a floor, gables on the two long sides and a
	# roof of two panels meeting at a ridge. Everything on a two-metre grid.
	for x in [-1.0, 1.0]:
		_put("wall_a_lod0" if x < 0 else "wall_c_lod0", Vector3(x, 0, 1.0))                 # front
		_put("wall_e_lod0" if x < 0 else "wall_g_lod0", Vector3(x, 0, -1.0), PI)            # back
		_put("floor_a_lod0" if x < 0 else "floor_b_lod0", Vector3(x, 0.02, 1.0))
	_put("wall_b_lod0", Vector3(-2.0, 0, 0), -PI * 0.5)
	_put("wall_d_lod0", Vector3(2.0, 0, 0), PI * 0.5)
	_put("gable_right_a_lod0", Vector3(-1.0, 2.0, 1.0))
	_put("gable_left_a_lod0", Vector3(1.0, 2.0, 1.0))
	_put("gable_left_b_lod0", Vector3(-1.0, 2.0, -1.0), PI)
	_put("gable_right_b_lod0", Vector3(1.0, 2.0, -1.0), PI)
	_put("roof_a_lod0", Vector3(-2.0, 2.0, 0), -PI * 0.5)
	_put("roof_b_lod0", Vector3(2.0, 2.0, 0), PI * 0.5)
	# One of each kind stood apart, and the levels of detail of a roof.
	_put("roof_c_lod0", Vector3(-9.0, 0, 0))
	_put("floor_c_lod0", Vector3(-6.5, 0.2, 1.0))
	_put("gable_left_a_lod0", Vector3(7.0, 0, 0))
	_put("gable_right_a_lod0", Vector3(9.5, 0, 0))
	for i in 8:
		_put("wall_%s_lod0" % "abcdefgh"[i], Vector3(-7.7 + 2.2 * i, 0, -9.0))
	for lod in 3:
		_put("roof_a_lod%d" % lod, Vector3(-2.6 + 2.6 * lod, 0, -17.0))
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_cam.current = true
	_shots = [
		["kit_hut", Vector3(6.5, 3.4, 8.0), Vector3(0.0, 1.9, 0), Vector3(-38, 52, 0)],
		["kit_hut_end", Vector3(-7.5, 2.6, 4.5), Vector3(0.0, 2.0, 0), Vector3(-32, -60, 0)],
		["kit_hut_gable", Vector3(0.5, 2.6, 7.5), Vector3(0.0, 2.3, 0), Vector3(-30, 40, 0)],
		["kit_hut_above", Vector3(3.5, 9.0, 5.0), Vector3(0.0, 2.0, 0), Vector3(-50, 30, 0)],
		["kit_parts", Vector3(-7.8, 2.2, 7.0), Vector3(-7.8, 1.0, 0), Vector3(-38, 52, 0)],
		["kit_gables", Vector3(8.2, 1.5, 6.0), Vector3(8.2, 1.0, 0), Vector3(-38, 52, 0)],
		["kit_walls", Vector3(0.0, 1.6, 2.0), Vector3(0.0, 1.0, -9.0), Vector3(-38, 52, 0)],
		["kit_inside", Vector3(1.4, 1.5, 0.5), Vector3(-2.0, 2.4, -0.6), Vector3(-38, 52, 0)],
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
