extends SceneTree

# THE TABLELANDS UP CLOSE: a wall and the rock masses set into it, from 30 m and
# from 80 m; the fallen rock at a wall's foot; a drift of ferns and a clearing in
# the wood; the meadow's grass. To renders/cliff_close_*.png.
#
#   godot --path . --script res://tests/RENDER_cliff_close.gd

var _scene: Node
var _cam: Camera3D
var _n := -1
var _views: Array = []      # [from, look at]
var _view := 0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _ground(p: Vector3) -> float:
	return float(_scene.get_node("GaiaSphere").call(&"height_at", p, 0.0))


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	var rocks: CliffRocks = _scene.get_node("CliffRocks")
	if _n < 0:
		if not (ex.arrived and not _scene.has_node("LoadingCover") and not rocks._rocks.is_empty()):
			return false
		var enviro := _scene.get_node("Enviro")
		enviro.advance = false
		enviro.hour = 10.5
		enviro.set_weather("clear", 0.0)
		ex.set("flying", true)
		# A big rock some way out from the middle: looked at square on, near and far.
		var pick: Transform3D = Transform3D.IDENTITY
		for r in rocks._rocks:
			var t: Transform3D = r[1]
			if t.basis.get_scale().y > 1.2 and Vector2(t.origin.x, t.origin.z).length() > 700.0:
				pick = t
				break
		var face := (pick.basis.z * Vector3(1, 0, 1)).normalized()
		var mid := pick.origin + Vector3.UP * 10.0
		for back in [30.0, 85.0]:
			var from: Vector3 = mid + face * back
			from.y = maxf(from.y, _ground(from) + 2.0)
			_views.append([from, mid])
		# Its foot, where the fallen rock lies.
		var foot := pick.origin + face * 14.0
		foot.y = _ground(foot)
		_views.append([foot + face * 10.0 + Vector3.UP * 3.0, foot])
		# The wood: a drift of ferns, then a clearing, found by the same arithmetic.
		var flora: Flora = _scene.get_node("Flora")
		var field: IslandField = _scene.get_node("GaiaSphere").call(&"get_field")
		var found := [Vector3.INF, Vector3.INF]
		for i in 4000:
			var a := float(i) * 0.37
			var p := Vector2(cos(a), sin(a)) * (480.0 + float(i) * 0.15)
			var s := field.sample(p.x, p.y)
			if float(s.get("forest", 0.0)) < 0.7:
				continue
			var z := Flora.wood_zones(p.x, p.y)
			if z.x > 0.8 and found[0] == Vector3.INF:
				found[0] = Vector3(p.x, float(s["height"]), p.y)
			if z.y > 0.9 and found[1] == Vector3.INF:
				found[1] = Vector3(p.x, float(s["height"]), p.y)
		for f in found:
			if f != Vector3.INF:
				_views.append([f + Vector3(7.0, 4.0, 7.0), f])
		# The cows' meadow.
		var g := Flora.glade()
		var gp := Vector3(g.x, 0.0, g.y)
		gp.y = _ground(gp)
		_views.append([gp + Vector3(10.0, 2.2, 6.0), gp + Vector3(-15.0, 0.0, -10.0)])
		_cam = Camera3D.new()
		_cam.far = 4000.0
		_scene.add_child(_cam)
		_cam.make_current()
		_place()
		_n = 0
		return false
	_n += 1
	if _n == 150:
		root.get_viewport().get_texture().get_image().save_png("res://renders/cliff_close_%d.png" % _view)
		_view += 1
		_n = 0
		if _view >= _views.size():
			print("close: done, %d views" % _views.size())
			quit(0)
			return true
		_place()
	return false


func _place() -> void:
	var v: Array = _views[_view]
	_cam.global_position = v[0]
	_cam.look_at(v[1])
	(_scene.get_node("Explorer") as Node3D).global_position = (v[0] as Vector3) + Vector3.UP * 3.0
