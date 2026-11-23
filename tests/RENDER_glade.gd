extends SceneTree

# THE MEADOW BY THE WRECK: from over the water looking up the shore into it, and
# standing in it among the herd.
#
#   godot --path . --script res://tests/RENDER_glade.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0
var _shots: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _look(explorer: Node3D, from: Vector3, target: Vector3) -> void:
	var cam := root.get_camera_3d()
	explorer.global_position = from - Vector3.UP * cam.position.y
	var d := target - from
	explorer.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	cam.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 11.0
			enviro.set_weather("clear", 0.0)
			var glade := Flora.glade()
			var world := _scene.get_node("GaiaSphere")
			var mid := Vector3(glade.x, 0.0, glade.y)
			mid.y = world.call(&"height_at", mid, 0.0)
			var wreck: Vector3 = _scene.get_node("CrashedShuttle").global_position
			var up := (mid - wreck)
			up.y = 0.0
			var far := up.length()
			up = up.normalized()
			var cows := 0
			for herd in _scene.get_node("CowHerds")._herds:
				if (herd["home"] as Vector2).distance_to(Vector2(glade.x, glade.y)) < 1.0:
					cows = (herd["cows"] as Array).size()
			print("glade: %.0f m up the shore from the wreck, %.0f m across, ground at %.2f, %d cows in it" % [far, glade.z * 2.0, mid.y, cows])
			explorer.flying = true
			var shore := wreck + up * 12.0
			_shots = [
				["0_from_the_water", Vector3(shore.x, 3.0, shore.z), mid + Vector3(0, 1.5, 0)],
				["1_from_above", mid - up * 70.0 + Vector3(0, 45.0, 0), mid],
				["2_in_it", mid - up * 16.0 + Vector3(0, 1.8, 0), mid + Vector3(0, 1.5, 0)],
			]
			_step = 0
			_wait = 2
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var shot: Array = _shots[_step / 2]
	if _step % 2 == 0:
		_look(explorer, shot[1], shot[2])
		_wait = 60
	else:
		root.get_texture().get_image().save_png(_out.path_join(String(shot[0]) + ".png"))
		print("glade: ", shot[0])
		if _step / 2 == _shots.size() - 1:
			quit(0)
			return true
	_step += 1
	return false
