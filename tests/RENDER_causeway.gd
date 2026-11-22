extends SceneTree

# THE CAUSEWAY: along its top, from the side over the water, and its bank from
# under the water.
#
#   godot --path . --script res://tests/RENDER_causeway.gd -- --out=/some/folder

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
			var cw: Causeway = _scene.get_node("Causeway")
			var a: Vector3 = cw.start
			var b: Vector3 = cw.finish
			var run := (b - a).normalized()
			var across := Vector3(-run.z, 0, run.x)
			var mid := (a + b) * 0.5
			var top: float = _scene.get_node("GaiaSphere").call(&"height_at", mid, mid.y)
			mid.y = top
			var level := top - FlowTerrain.CAUSEWAY_RISE
			print("causeway: %.0f m long, top %.2f, water %.2f" % [a.distance_to(b), top, level])
			explorer.flying = true
			_shots = [
				["0_along", a - run * 6.0 + Vector3(0, 7.0, 0), mid],
				["1_on_it", mid - run * 14.0 + Vector3(0, 1.7, 0), mid + run * 20.0 + Vector3(0, 0.5, 0)],
				["2_side", mid + across * 24.0 + Vector3(0, 6.0, 0), mid],
				["3_bank_under_water", mid + across * 11.0 + Vector3(0, -3.2, 0) - run * 6.0, mid + Vector3(0, -3.6, 0) + run * 6.0],
			]
			_step = 0
			_wait = 2
		return false
	_wait -= 1
	if _wait > 0:
		return false
	if _step % 2 == 0:
		var shot: Array = _shots[_step / 2]
		_look(explorer, shot[1], shot[2])
		_wait = 45
	else:
		var shot: Array = _shots[_step / 2]
		root.get_texture().get_image().save_png(_out.path_join(String(shot[0]) + ".png"))
		print("causeway: ", shot[0])
		if _step / 2 == _shots.size() - 1:
			quit(0)
			return true
	_step += 1
	return false
