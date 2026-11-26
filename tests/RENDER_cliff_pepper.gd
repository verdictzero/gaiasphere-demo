extends SceneTree

# THE CLIFF MODELS ON THE HILLS' STEEP FACES: a look at a few of them where they
# stand (the rock face under them should be the same rock), to
# renders/cliff_pepper_*.png.
#
#   godot --path . --script res://tests/RENDER_cliff_pepper.gd

var VIEWS := []

var _scene: Node
var _cam: Camera3D
var _n := -1
var _view := 0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _ground(p: Vector3) -> float:
	return float(_scene.get_node("GaiaSphere").call(&"height_at", p, 0.0))


func _place() -> void:
	var v: Array = VIEWS[_view]
	var from: Vector3 = v[0]
	var to: Vector3 = v[1]
	_cam.global_position = from
	_cam.look_at(to)
	var ex: Node3D = _scene.get_node("Explorer")
	ex.global_position = from + Vector3.UP * 2.0


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	if _n < 0:
		var cliffs := _scene.get_node_or_null("CliffRocks")
		if ex.arrived and not _scene.has_node("LoadingCover") and (cliffs == null or bool(cliffs.call(&"placed"))):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 10.0
			enviro.set_weather("clear", 0.0)
			ex.set("flying", true)
			_cam = Camera3D.new()
			_cam.far = 6000.0
			_scene.add_child(_cam)
			_cam.make_current()
			# Three of the blocks, spread through the list, each from 45 m off down its
			# slope and from 16 m off beside it.
			var rocks: Array = cliffs.get("_rocks")
			var blocks: Array = []
			for r in rocks:
				if int(r[0]) == CliffRocks.SHARDS + CliffRocks.KIT.size():
					blocks.append((r[1] as Transform3D).origin)
			for share in [0.2, 0.5, 0.8]:
				var at: Vector3 = blocks[int(blocks.size() * share)]
				var best := Vector3.ZERO
				for a in 16:
					var off := Vector3(cos(a * TAU / 16.0), 0, sin(a * TAU / 16.0)) * 45.0
					var g := _ground(at + off)
					if best == Vector3.ZERO or g < best.y:
						best = Vector3(at.x + off.x, g, at.z + off.z)
				VIEWS.append([best + Vector3.UP * 6.0, at + Vector3.UP * 3.0])
				var near := at + (best - at).normalized() * 16.0
				VIEWS.append([Vector3(near.x, _ground(near) + 2.0, near.z), at + Vector3.UP * 2.0])
			_place()
			_n = 0
		return false
	_n += 1
	if _n == 160:
		root.get_viewport().get_texture().get_image().save_png("res://renders/cliff_pepper_%d.png" % _view)
		_view += 1
		_n = 0
		if _view >= VIEWS.size():
			quit(0)
			return true
		_place()
	return false
