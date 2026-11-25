extends SceneTree

# A FIR FELLED, seen from the side as it comes down: pictures just after the
# crown hits (fronds and needles thrown up) to renders/tree_fall_*.png.
#
#   godot --path . --script res://tests/RENDER_tree_fall.gd

var _scene: Node
var _n := -1
var _cam: Camera3D
var _crashed := -1
var _shot := 0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	var wood: Woodcutting = _scene.get_node("Woodcutting")
	if _n < 0:
		if not (ex.arrived and not _scene.has_node("LoadingCover")):
			return false
		var enviro := _scene.get_node("Enviro")
		enviro.advance = false
		enviro.hour = 11.0
		enviro.set_weather("clear", 0.0)
		var flora: Flora = _scene.get_node("Flora")
		var here: Vector3 = ex.global_position
		var tree := {}
		for i in 900:
			var ang := float(i) * 0.7
			var p := here + Vector3(cos(ang), 0.0, sin(ang)) * (6.0 + 0.2 * float(i)) + Vector3(0, 1.5, 0)
			var t := flora.tree_on(p, Vector3.ZERO, 0.0, 4.0)
			if not t.is_empty() and float(t["radius"]) > 0.25 and (t["origin"] as Vector3).y > 0.5:
				tree = t
				break
		var foot: Vector3 = tree["origin"]
		# Stand beside it, swing (felling) at it, and watch from off to the side.
		var from := foot + Vector3(float(tree["radius"]) + 1.6, 1.6, 0.0)
		ex.set("flying", true)
		ex.global_position = from - Vector3.UP * 1.6
		var dir := (foot + Vector3.UP * 0.8 - from).normalized()
		print("tree fall: felling at %s: %s" % [foot, wood.strike(from, dir, true)])
		_cam = Camera3D.new()
		_scene.add_child(_cam)
		_cam.make_current()
		_cam.global_position = foot + Vector3(4.0, 7.0, 22.0)
		_cam.look_at(foot + Vector3(-6.0, 3.0, 0.0))
		_n = 0
		return false
	_n += 1
	if _crashed < 0 and _n > 5 and wood._falls.is_empty():
		_crashed = _n
	if _crashed >= 0 and (_n - _crashed) in [2, 10, 22]:
		root.get_viewport().get_texture().get_image().save_png("res://renders/tree_fall_%d.png" % _shot)
		_shot += 1
	if _shot >= 3 or _n > 4000:
		print("tree fall: done (%d pictures)" % _shot)
		quit(0)
		return true
	return false
