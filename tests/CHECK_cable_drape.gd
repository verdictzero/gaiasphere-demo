extends SceneTree

# A CABLE AND WHAT IS SOLID, by themselves (no island: quick): a floor, a wall
# standing on it, and a cable let fall across the wall from above. It must end
# lying over the wall's top, down both its faces and along the floor, none of it
# inside anything.
#
#   godot --headless --path . --script res://tests/CHECK_cable_drape.gd

var _power: Power
var _line: Power.Line
var _step := 0
var _wall := AABB(Vector3(-0.2, 0, -3), Vector3(0.4, 1.6, 6))


func _box(box: AABB) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	shape.shape = bs
	body.add_child(shape)
	root.add_child(body)
	body.global_position = box.get_center()


func _initialize() -> void:
	Engine.max_fps = 60
	_box(AABB(Vector3(-20, -1, -20), Vector3(40, 1, 40)))
	_box(_wall)
	_power = Power.new()
	root.add_child(_power)


func _process(_d: float) -> bool:
	_step += 1
	if _step == 3:
		_line = _power.call(&"_new_cable")
		_line.ends[0] = {"at": Transform3D(Basis(), Vector3(-4, 0.1, 0))}
		_line.ends[1] = {"at": Transform3D(Basis(Vector3.UP, PI), Vector3(4, 0.1, 0))}
		var p0: Vector3 = _power.call(&"_end_point", _line, 0)
		var p1: Vector3 = _power.call(&"_end_point", _line, 1)
		var n := int(ceil((p0.distance_to(p1) + 4.0) / Power.SEG))
		var pts := PackedVector3Array()
		for i in n:
			var t := float(i) / float(n - 1)
			pts.append(p0.lerp(p1, t) + Vector3(0, 3.0 * sin(PI * t), 0))
		_line.pts = pts
		_line.old = pts.duplicate()
	if _step == 480:
		var inside := 0
		var on_top := 0
		var under := 0
		for p: Vector3 in _line.pts:
			if _wall.grow(-0.01).has_point(p):
				inside += 1
			if p.y < -0.001:
				under += 1
			if absf(p.y - (_wall.end.y + Power.THICK)) < 0.1 and absf(p.x) < 0.4:
				on_top += 1
			if absf(p.x) < 0.7:
				print("drape:   %.2f across, %.2f up" % [p.x, p.y])
		print("drape: %s  %d inside the wall, %d under the floor, %d on the wall's top, set %s (age %.1f)" % [
				"ok" if inside == 0 and under == 0 and on_top > 0 else "FAIL", inside, under, on_top, not _line.live, _line.age])
		return true
	return false
