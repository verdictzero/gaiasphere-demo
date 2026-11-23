extends SceneTree

# THE BERRY BUSH MODEL ON ITS OWN, from two sides.
#
#   godot --path . --resolution 1600x900 --script res://tests/RENDER_bush_model.gd -- --out=/some/folder

var _out := "user://"
var _frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.42, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.84, 0.9)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 52.0, 0.0)
	root.add_child(sun)
	for i in 2:
		var bush: Node3D = (load("res://assets/berry_bush/viburnum_bush.glb") as PackedScene).instantiate()
		bush.position = Vector3(-1.6 + 3.2 * i, 0, 0)
		bush.rotation.y = PI * 0.5 * i
		root.add_child(bush)
	# A torch held at the eye, as the player's is: what shows the cards up worst.
	var torch := SpotLight3D.new()
	torch.light_energy = 12.0
	torch.spot_range = 20.0
	torch.spot_angle = 38.0
	torch.position = Vector3(0.3, 1.5, 6.5)
	root.add_child(torch)
	torch.look_at(Vector3(0, 1.0, 0))
	env.ambient_light_energy = 0.12
	sun.light_energy = 0.05
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.6, 6.5), Vector3(0, 1.0, 0))
	cam.current = true


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 12:
		root.get_texture().get_image().save_png(_out.path_join("bush_model.png"))
		print("bush: saved")
		quit(0)
		return true
	return false
