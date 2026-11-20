extends SceneTree

# THE SWORD IN THE HAND AND WHAT IT MIRRORS: at the hour the scene starts with,
# then at noon and at night, each after the reflection has had time to retake.
#
#   godot --path . --script res://tests/RENDER_sword.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var enviro := _scene.get_node("Enviro")
	var refl: WorldReflection = _scene.get_node("WorldReflection")
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			var play := _scene.get_node("SwordPlay")
			enviro.advance = false
			enviro.set_weather("clear", 0.0)
			if not play._find_parts():
				push_error("sword: not found")
				quit(1)
				return true
			play._take()
			# Held up across the view so the flat of the blade faces the camera.
			_step = 0
			_wait = 90
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var play2 := _scene.get_node("SwordPlay")
	play2._pivot.rotation_degrees = Vector3(-8.0, 20.0, -52.0)
	play2._pivot.position = Vector3(0.1, -0.3, -0.75)
	match _step:
		0, 2, 4:
			_wait = 6
		1:
			root.get_texture().get_image().save_png(_out.path_join("sword_0_start.png"))
			print("sword: start, captures so far %d" % refl.captures)
			enviro.hour = 12.5
			_wait = 150
		3:
			root.get_texture().get_image().save_png(_out.path_join("sword_1_noon.png"))
			print("sword: noon, captures so far %d" % refl.captures)
			enviro.hour = 1.0
			_wait = 150
		5:
			root.get_texture().get_image().save_png(_out.path_join("sword_2_night.png"))
			print("sword: night, captures so far %d" % refl.captures)
			quit(0)
			return true
	_step += 1
	return false
