extends SceneTree

# A cow cut in two, the halves stood apart with their cut faces to the camera.
#
#   godot --path . --resolution 1600x900 --script res://tests/RENDER_cut_face.gd -- --out=/some/folder

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
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 20.0, 0.0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.2, 6.5), Vector3(0, 0.1, 0))
	cam.current = true


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 3:
		var slicing := CowSlicing.new()
		root.add_child(slicing)
		var model: Node3D = (load(CowHerds.MODEL) as PackedScene).instantiate()
		var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
		var whole := slicing._whole({"arrays": mi.mesh.surface_get_arrays(0), "material": mi.mesh.surface_get_material(0), "transform": Transform3D()})
		var halves := slicing._cut(whole, Plane(Vector3(0.25, 0.2, 1).normalized(), 0.1))
		(whole["body"] as Node).queue_free()
		model.free()
		for side in 2:
			# Each half turned so its cut face looks at the camera.
			var turn := Basis(Vector3.UP, 0.0 if side == 1 else PI) * Basis(Vector3(1, 0, 0), -0.15)
			var made := slicing._body(halves[side], Transform3D(turn, Vector3(-1.6 + 3.2 * side, 0, 0)), 1, 1, whole["material"])
			(made["body"] as RigidBody3D).freeze = true
	if _frames == 16:
		root.get_texture().get_image().save_png(_out.path_join("cut_face.png"))
		quit(0)
		return true
	return false
