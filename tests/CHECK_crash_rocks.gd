extends SceneTree

# THE SHUTTLE'S DEBRIS BREAKS: the rock heaped round its divot and along its
# skid is the island's own boulders (Flora's layer), so one of the big ones is
# walked up to and struck with the pickaxe until it comes apart, and what that
# left is printed.
#
#   godot --headless --path . --script res://tests/CHECK_crash_rocks.gd

var _scene: Node
var _step := -1
var _wait := 0
var _target: Array = []
var _blows := 0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	var flora: Flora = _scene.get_node("Flora")
	var mine: Mining = _scene.get_node("Mining")
	if _step < 0:
		if not (ex.arrived and not _scene.has_node("LoadingCover")):
			return false
		var field: IslandField = _scene.get_node("GaiaSphere").call(&"get_field")
		var all: Array = flora._crash_debris(field)
		print("crash rocks: %d in the debris" % all.size())
		# A big one well up the skid, on dry land.
		for d in all:
			var t: Transform3D = d[1]
			if t.basis.get_scale().x > 1.0 and t.origin.y > 2.0:
				_target = d
				break
		if _target.is_empty():
			_target = all[0]
		var t: Transform3D = _target[1]
		ex.set("flying", true)
		ex.global_position = t.origin + Vector3(1.9, 0.2, 0.0)
		_step = 0
		_wait = 30
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var t: Transform3D = _target[1]
	var cam := ex.get_viewport().get_camera_3d()
	var aim := t.origin + Vector3.UP * 0.3 * t.basis.get_scale().x
	var from := cam.global_position
	var dir := (aim - from).normalized()
	if _step == 0:
		print("crash rocks: the pickaxe would land on it: %s (%.2f m off)" % [mine.aimed(from, dir), mine.rock_at(from, dir)])
		_step = 1
	if mine.strike(from, dir):
		_blows += 1
		_wait = 6
		if _blows < 40:
			return false
	var left := not flora.rock_on(from, dir, 3.2).is_empty()
	print("crash rocks: %d blows landed, still there: %s, stones loose: %d" % [_blows, left, mine._stones.size()])
	print("crash rocks: done")
	quit(0)
	return true
