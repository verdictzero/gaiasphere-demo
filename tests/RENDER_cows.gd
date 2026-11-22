extends SceneTree

# THE COW HERDS: the nearest herd looked at from a little way off, twice a few
# seconds apart, and what each cow in it was doing.
#
#   godot --path . --script res://tests/RENDER_cows.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0
var _herd := {}


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


func _doing() -> String:
	var said := []
	for cow in _herd["cows"]:
		said.append("%s/%s" % [cow["state"], cow["now"]])
	return ", ".join(said)


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var cows: CowHerds = _scene.get_node("CowHerds")
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover") and not cows._herds.is_empty():
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 10.0
			enviro.set_weather("clear", 0.0)
			var here: Vector3 = explorer.global_position
			var best := 1e9
			for herd in cows._herds:
				var c: Vector2 = herd["centre"]
				if c.distance_to(Vector2(here.x, here.z)) < best:
					best = c.distance_to(Vector2(here.x, here.z))
					_herd = herd
			var in_wood := 0
			for herd in cows._herds:
				for cow in herd["cows"]:
					var at: Vector3 = (cow["node"] as Node3D).global_position
					if Flora.meadow(at.x, at.z) < 0.6:
						in_wood += 1
			print("cows: %d standing outside a meadow" % in_wood)
			print("cows: %d herds; the nearest %.0f m off with %d cows" % [cows._herds.size(), best, (_herd["cows"] as Array).size()])
			explorer.flying = true
			_step = 0
			_wait = 2
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var c: Vector2 = _herd["centre"]
	var first: Vector3 = (_herd["cows"][0]["node"] as Node3D).global_position
	var mid := Vector3(c.x, first.y, c.y)
	match _step:
		0:
			_look(explorer, mid + Vector3(13.0, 3.0, 9.0), mid)
			_wait = 40
		1:
			root.get_texture().get_image().save_png(_out.path_join("cows_0.png"))
			print("cows: ", _doing())
			_wait = 30
		2:
			root.get_texture().get_image().save_png(_out.path_join("cows_1.png"))
			print("cows: ", _doing())
			_look(explorer, first + Vector3(3.2, 0.4, 2.6), first)
			_wait = 12
		3:
			root.get_texture().get_image().save_png(_out.path_join("cows_2_close.png"))
			print("cows: ", _doing())
			print("cows: ok")
			quit(0)
			return true
	_step += 1
	return false
