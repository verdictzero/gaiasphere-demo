extends SceneTree

# A CABLE AND THE PART IT IS PLUGGED INTO, by themselves (no island: quick): a
# junction box on a floor, and a cable that comes to it from one side and is
# plugged into the socket on the FAR side, and then into the socket at right
# angles. Neither at once nor after it has settled may any of it be inside the
# box, nor any length of it pass through.
#
#   godot --headless --path . --script res://tests/CHECK_cable_round.gd

var _power: Power
var _box: Power.Dev
var _lines: Array = []
var _step := 0
var _fails := 0


func _initialize() -> void:
	Engine.max_fps = 60
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	shape.shape = bs
	body.add_child(shape)
	root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)
	_power = Power.new()
	root.add_child(_power)


## How many of a cable's points are inside the part's box, and how many of its
## lengths pass through it (the first two points, in the socket, aside).
func _through(line: Power.Line) -> Vector2i:
	var box := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1, 1, 1)).grow(-0.02)
	var inside := 0
	var across := 0
	for i in range(2, line.pts.size()):
		if box.has_point(line.pts[i]):
			inside += 1
		if i + 1 < line.pts.size() and box.intersects_segment(line.pts[i], line.pts[i + 1]) != null:
			across += 1
	return Vector2i(inside, across)


func _lay(socket: int) -> Power.Line:
	# From 5 m out on +X along the floor to a hand just short of the box, as it
	# would be carried up to it.
	var line: Power.Line = _power.call(&"_new_cable")
	var pts := PackedVector3Array()
	var n := int(4.2 / Power.SEG)
	for i in n:
		pts.append(Vector3(5.0 - float(i) * Power.SEG, 0.05 + 1.0 * float(i) / float(n), 0.15 * float(socket)))
	line.pts = pts
	line.old = pts.duplicate()
	line.ends[0] = {"at": Transform3D(Basis(Vector3.UP, PI), Vector3(5.2, 0.1, 0.15 * float(socket)))}
	_power.call(&"_plug", line, 1, _box, socket)
	return line


func _process(_d: float) -> bool:
	_step += 1
	if _step == 3:
		_box = _power.set_down("junction", Transform3D(Basis(), Vector3.ZERO))
		# Socket 1 faces -X (the far side from where the cable comes); 2 faces +Z.
		for socket: int in [1, 2]:
			var line := _lay(socket)
			_lines.append(line)
			var t := _through(line)
			print("round: %s  plugged into the socket facing %s: at once, %d points inside the box, %d lengths through it (%d points of cable)" % [
					"ok" if t == Vector2i.ZERO else "FAIL", "away" if socket == 1 else "sideways", t.x, t.y, line.pts.size()])
			if t != Vector2i.ZERO:
				_fails += 1
	if _step == 420:
		for line: Power.Line in _lines:
			var t := _through(line)
			var longest := 0.0
			for i in line.pts.size() - 1:
				longest = maxf(longest, line.pts[i].distance_to(line.pts[i + 1]))
			print("round: %s  settled: %d inside, %d through, set %s, longest length %.2f of %.2f" % [
					"ok" if t == Vector2i.ZERO and longest < Power.SEG * 1.3 else "FAIL", t.x, t.y, not line.live, longest, Power.SEG])
			if t != Vector2i.ZERO or longest >= Power.SEG * 1.3:
				_fails += 1
		print("round: %s" % ("ALL OK" if _fails == 0 else "%d FAILED" % _fails))
		return true
	return false
