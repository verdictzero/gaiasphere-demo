extends SceneTree

# THE COW CUBE ON ITS OWN: front-quarter and side, in the middle of each of its
# animations.
#
#   godot --path . --resolution 1600x900 --script res://tests/RENDER_cow_model.gd -- --out=/some/folder

var _out := "user://"
var _frames := 0
var _cows: Array = []


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
	var names := ["Idle_Float", "Move_Float", "Eat", "Chew", "Moo", "Idle_Breathe", "Chomp"]
	for i in names.size():
		var cow: Node3D = (load("res://assets/cow/cow.glb") as PackedScene).instantiate()
		cow.position = Vector3(-9.0 + 3.0 * i, 1.0, 0)
		cow.rotation.y = 0.6
		root.add_child(cow)
		var player := cow.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if i == 0:
			print("cow: animations ", player.get_animation_list())
			for n in player.get_animation_list():
				var anim := player.get_animation(n)
				var tracks := []
				for t in anim.get_track_count():
					tracks.append(str(anim.track_get_path(t)).get_slice(":", 1) + "/" + str(anim.track_get_type(t)))
				print("cow:   ", n, " ", anim.length, " loop=", anim.loop_mode, " ", tracks)
		player.play(names[i])
		player.seek(player.get_animation(names[i]).length * 0.5, true)
		player.pause()
		_cows.append(cow)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 3.0, 16.0), Vector3(0, 1.0, 0))
	cam.current = true


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 12:
		root.get_texture().get_image().save_png(_out.path_join("cow_model.png"))
		print("cow: saved")
		quit(0)
		return true
	return false
