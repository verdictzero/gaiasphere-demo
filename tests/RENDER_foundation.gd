extends SceneTree

# THE FOUNDATION BLOCKS, LOOKED AT: one on its own, a run of three with a wall
# stood on them, and the doorstep.
#
#   godot --path . --resolution 1600x900 --script res://tests/RENDER_foundation.gd -- --out=/some/folder

var _out := "user://"
var _frames := 0
var _cam: Camera3D
var _shots: Array = []


func _put(path: String, at: Vector3, turn := 0.0) -> void:
	var node: Node3D = (load(path) as PackedScene).instantiate()
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
	var kit := "res://assets/build/foundation/"
	_put(kit + "foundation_a_lod0.glb", Vector3(-4.0, 0, 0))
	for i in 3:
		_put(kit + "foundation_%s_lod0.glb" % "abc"[i], Vector3(0.0 + 2.0 * i, 0, 0))
		_put("res://assets/build/plank_kit/wall_%s_lod0.glb" % "abc"[i], Vector3(0.0 + 2.0 * i, 1.0, 1.0))
	_put(kit + "foundation_step_a_lod0.glb", Vector3(2.0, -0.8, 1.3))
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_cam.current = true
	_shots = [
		["foundation_one", Vector3(-1.2, 2.2, 4.2), Vector3(-4.0, 0.5, 0)],
		["foundation_run", Vector3(7.5, 2.6, 7.5), Vector3(2.0, 1.0, 0.5)],
		["foundation_close", Vector3(-2.6, 1.3, 2.0), Vector3(-3.4, 0.7, 1.0)],
	]


func _process(_dt: float) -> bool:
	_frames += 1
	var i := (_frames - 1) / 12
	if i >= _shots.size():
		quit(0)
		return true
	var shot: Array = _shots[i]
	_cam.look_at_from_position(shot[1], shot[2])
	if (_frames - 1) % 12 == 11:
		root.get_texture().get_image().save_png(_out.path_join(String(shot[0]) + ".png"))
		print("foundation: ", shot[0])
	return false
