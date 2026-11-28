extends SceneTree

# THE LASER TURRET AS A POWERED PART, by itself (no island: quick): stood on a
# floor beside a charged battery, with no cable it has no power and stands still;
# cabled, it is armed, draws the battery down, and its head sweeps round.
#
#   godot --headless --path . --script res://tests/CHECK_turret.gd

var _power: Power
var _turret: Power.Dev
var _battery: Power.Dev
var _step := 0
var _fails := 0
var _was := 0.0
var _turned := 0.0


func _check(what: String, ok: bool, detail := "") -> void:
	print("turret: %s %s %s" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_fails += 1


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


func _process(_d: float) -> bool:
	_step += 1
	if _step == 3:
		_turret = _power.set_down("laser_ciws", Transform3D(Basis(), Vector3.ZERO))
		_battery = _power.set_down("battery", Transform3D(Basis(), Vector3(4, 0, 0)), _power.capacity() * 0.5)
		_check("the turret has eight sockets, two a side", _turret.sockets.size() == 8)
		# THE EIGHT PORTS, where the model has their wells (measured from it: on each
		# side of the base two wells, a metre either way of the middle as it was made,
		# their floors 1.8 out from the centre): at half size, 0.9 out and 0.5 along,
		# half a metre up. And a plug goes into each of them.
		var want: Array = []
		for way: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
			for along: float in [-0.5, 0.5]:
				want.append(way * 0.9 + way.cross(Vector3.UP) * along + Vector3(0, 0.4985, 0))
		var found := 0
		for i in 8:
			var at: Vector3 = (_power.call(&"_socket_world", _turret, i) as Transform3D).origin
			for w: Vector3 in want:
				if at.distance_to(w) < 0.01:
					found += 1
			var cable: Power.Line = _power.call(&"_new_cable")
			_power.call(&"_plug", cable, 0, _turret, i)
			cable.pts = PackedVector3Array([at, at + Vector3(0, 0.1, 0)])
			cable.old = cable.pts.duplicate()
		_check("each port is where its well is, and takes a plug", found == 8 and int(_power.call(&"_in_use", _turret)) == 8, "(%d of 8 in place)" % found)
		for cable: Power.Line in _power.cables.duplicate():
			_power.coil(cable)
		var m := _power.muzzle(_turret)
		_check("its beam leaves the head some 2.3 m up, 0.7 m out, and goes on outward", absf(m.origin.y - 2.27) < 0.1
				and absf(Vector2(m.origin.x, m.origin.z).length() - 0.7) < 0.05 and (-m.basis.z).dot(Vector3(m.origin.x, 0, m.origin.z).normalized()) > 0.99,
				"(at %s, toward %s)" % [m.origin, -m.basis.z])
	if _step == 90:
		_check("no cable: no power, the head still", _turret.state == "no power" and _turret.turn.rotation.y == 0.0, "(%s)" % _turret.state)
		var cable: Power.Line = _power.call(&"_new_cable")
		_power.call(&"_plug", cable, 0, _turret, 0)
		_power.call(&"_plug", cable, 1, _battery, 1)
		var p0: Vector3 = _power.call(&"_end_point", cable, 0)
		var p1: Vector3 = _power.call(&"_end_point", cable, 1)
		var pts := PackedVector3Array()
		for i in 12:
			pts.append(p0.lerp(p1, float(i) / 11.0))
		cable.pts = pts
		cable.old = pts.duplicate()
		_was = _battery.charge
	if _step == 240:
		_check("cabled to a battery: armed, drawing it down, the head sweeping", _turret.state == "armed" and _battery.charge < _was
				and absf(_turret.turn.rotation.y) > 0.3, "(%s, battery %s, head turned %.2f)" % [_turret.state, _battery.state, _turret.turn.rotation.y])
		print("turret: %s" % ("ALL OK" if _fails == 0 else "%d FAILED" % _fails))
		return true
	return false
