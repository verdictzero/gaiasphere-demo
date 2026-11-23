extends SceneTree

# THE SHUTTLE ON ITS OWN: from the four sides and above, and from inside its cabin.
#
#   godot --path . --resolution 1600x900 --script res://tests/RENDER_shuttle_model.gd -- --out=/some/folder

var _out := "user://"
var _frames := 0
var _cam: Camera3D
var _shots := [
	["front_left", Vector3(-12, 5, 14), Vector3(0, 0.5, 0), 40.0],
	["back_right", Vector3(12, 5, -14), Vector3(0, 0.5, 0), 40.0],
	["side", Vector3(18, 1.0, 0), Vector3(0, 0.5, 0), 40.0],
	["top", Vector3(0.01, 22, 0), Vector3(0, 0, 0), 40.0],
	["under", Vector3(6, -8, 8), Vector3(0, 0, 0), 40.0],
	["inside_fwd", Vector3(0, -0.2, 0.5), Vector3(0, -0.2, 6), 80.0],
	["inside_back", Vector3(0, -0.2, 2.6), Vector3(0, -0.2, -6), 80.0],
	["inside_side", Vector3(0.3, -0.2, 1.5), Vector3(-6, -0.2, 1.5), 80.0],
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.42, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.84, 0.9)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 52.0, 0.0)
	root.add_child(sun)
	root.add_child((load("res://assets/shuttle/shuttle.glb") as PackedScene).instantiate())
	_cam = Camera3D.new()
	_cam.near = 0.02
	root.add_child(_cam)
	_cam.current = true


func _process(_dt: float) -> bool:
	_frames += 1
	var i := (_frames - 1) / 10
	if i >= _shots.size():
		quit(0)
		return true
	var shot: Array = _shots[i]
	_cam.fov = shot[3]
	_cam.look_at_from_position(shot[1], shot[2], Vector3.UP if String(shot[0]) != "top" else Vector3(0, 0, 1))
	if (_frames - 1) % 10 == 9:
		root.get_texture().get_image().save_png(_out.path_join("shuttle_%s.png" % shot[0]))
	return false
