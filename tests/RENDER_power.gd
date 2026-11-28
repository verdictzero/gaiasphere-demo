extends SceneTree

# POWER, LOOKED AT: a panel, a battery, a junction box and a light pole stood near
# the start and cabled together, by day and by night, and a cable being carried.
#
#   godot --path . --script res://tests/RENDER_power.gd
# Writes renders/power_day.png, power_cable.png, power_night.png, power_carry.png.

var _scene: Node
var _cam: Camera3D
var _n := -1
var _shot := 0
var _spot := Vector3.ZERO
var _line: Power.Line


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _ground(p: Vector3) -> float:
	return float(_scene.get_node("GaiaSphere").call(&"height_at", p, 0.0))


func _stand(power: Power, kind: String, off: Vector3, turn := 0.0) -> Power.Dev:
	var at := _spot + off
	at.y = _ground(at)
	return power.set_down(kind, Transform3D(Basis(Vector3.UP, turn), at))


func _join(power: Power, a: Power.Dev, sa: int, b: Power.Dev, sb: int, slack := 1.25) -> Power.Line:
	var cable: Power.Line = power.call(&"_new_cable")
	power.call(&"_plug", cable, 0, a, sa)
	power.call(&"_plug", cable, 1, b, sb)
	var p0: Vector3 = power.call(&"_end_point", cable, 0)
	var p1: Vector3 = power.call(&"_end_point", cable, 1)
	var n := int(ceil(p0.distance_to(p1) * slack / Power.SEG)) + 3
	var pts := PackedVector3Array()
	for i in n:
		var t := float(i) / float(n - 1)
		pts.append(p0.lerp(p1, t) + Vector3(sin(t * 9.0) * 0.8 * sin(PI * t), 0.8 * sin(PI * t), cos(t * 7.0) * 0.8 * sin(PI * t)))
	cable.pts = pts
	cable.old = pts.duplicate()
	return cable


func _look(from: Vector3, to: Vector3) -> void:
	var f := _spot + from
	f.y = _ground(f) + from.y
	var t := _spot + to
	t.y = _ground(t) + to.y
	_cam.global_position = f
	_cam.look_at(t)


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	var power: Power = _scene.get_node("Power")
	var enviro := _scene.get_node("Enviro")
	if _n < 0:
		if ex.arrived and not _scene.has_node("LoadingCover"):
			enviro.advance = false
			enviro.hour = 14.0
			enviro.set_weather("clear", 0.0)
			# (The start is at the wreck, under the mere: by the truck, on the meadow.)
			_spot = (_scene.get_node("UniTruck").get("body") as Node3D).global_position + Vector3(14, 0, 6)
			ex.global_position = _spot + Vector3(0, 3, 0)
			ex.set("flying", true)
			_cam = Camera3D.new()
			_cam.far = 6000.0
			_scene.add_child(_cam)
			_cam.make_current()
			var sun := _stand(power, "solar_panel", Vector3(10, 0, -4), 0.3)
			var store := _stand(power, "battery", Vector3(10, 0, 6), 0.0)
			var box := _stand(power, "junction", Vector3(17, 0, 1), 0.2)
			var pole := _stand(power, "light_pole", Vector3(25, 0, 3), 0.0)
			_join(power, sun, 0, box, 1)
			_join(power, store, 0, box, 3, 1.5)
			_line = _join(power, box, 0, pole, 1)
			store.charge = power.capacity() * 0.6
			_look(Vector3(-2, 5, 12), Vector3(16, 2, 1))
			_n = 0
		return false
	_n += 1
	if _n < 260:
		return false
	_n = 0
	var names := ["power_day", "power_cable", "power_night", "power_carry"]
	root.get_viewport().get_texture().get_image().save_png("res://renders/%s.png" % names[_shot])
	_shot += 1
	match _shot:
		1:
			_look(Vector3(14.5, 1.7, 3.5), Vector3(17, 0.5, 1))
		2:
			enviro.hour = 23.5
			_look(Vector3(8, 4, 16), Vector3(22, 4, 2))
		3:
			# The pole's plug pulled out and carried off toward the eye.
			enviro.hour = 14.0
			power.call(&"_take_up", _line, 1)
			_look(Vector3(30, 1.8, 14), Vector3(20, 1.2, 4))
		4:
			quit(0)
			return true
	return false
