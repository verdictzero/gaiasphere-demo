extends SceneTree

# POWER, end to end: a panel, a battery, a junction box and a light pole are stood
# near the start and cabled together; a cable is carried off by hand and seen to
# pay out, hang, lie on the ground and set; the day charges the battery, the night
# lights the pole from it; it is all saved, cleared and loaded back.
#
#   godot --headless --path . --script res://tests/CHECK_power.gd

var _scene: Node
var _step := 0
var _fails := 0
var _spot := Vector3.ZERO
var _line: Power.Line
var _was := 0.0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _check(what: String, ok: bool, detail := "") -> void:
	print("power: %s %s %s" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_fails += 1


func _stand(power: Power, kind: String, off: Vector3) -> Power.Dev:
	var at := _spot + off
	at.y = float(_scene.get_node("GaiaSphere").call(&"height_at", at))
	return power.set_down(kind, Transform3D(Basis(), at))


func _join(power: Power, a: Power.Dev, sa: int, b: Power.Dev, sb: int) -> Power.Line:
	var cable: Power.Line = power.call(&"_new_cable")
	power.call(&"_plug", cable, 0, a, sa)
	power.call(&"_plug", cable, 1, b, sb)
	var p0: Vector3 = power.call(&"_end_point", cable, 0)
	var p1: Vector3 = power.call(&"_end_point", cable, 1)
	var n := int(ceil(p0.distance_to(p1) * 1.15 / Power.SEG)) + 3
	var pts := PackedVector3Array()
	for i in n:
		pts.append(p0.lerp(p1, float(i) / float(n - 1)) + Vector3(0, 0.6 * sin(PI * float(i) / float(n - 1)), 0))
	cable["pts"] = pts
	cable["old"] = pts.duplicate()
	return cable


func _process(_d: float) -> bool:
	var ex: CharacterBody3D = _scene.get_node("Explorer")
	if not ex.arrived or _scene.has_node("LoadingCover"):
		return false
	var power: Power = _scene.get_node("Power")
	var enviro: Node = _scene.get_node("Enviro")
	var title: TitleMenu = _scene.get_node("TitleMenu")
	_step += 1
	if _step == 5:
		enviro.set("advance", false)
		enviro.set("hour", 12.0)
		_spot = ex.global_position
		var sun := _stand(power, "solar_panel", Vector3(8, 0, 0))
		var store := _stand(power, "battery", Vector3(8, 0, 8))
		var box := _stand(power, "junction", Vector3(14, 0, 4))
		var pole := _stand(power, "light_pole", Vector3(20, 0, 4))
		_join(power, sun, 0, box, 1)
		_join(power, store, 0, box, 3)
		_line = _join(power, box, 0, pole, 1)
		_check("four parts stand, three cables run", power.devices.size() == 4 and power.cables.size() == 3)
	if _step == 400:
		var set_all := true
		var under := 0
		for cable: Power.Line in power.cables:
			set_all = set_all and not bool(cable["live"])
			for p: Vector3 in cable["pts"]:
				if p.y < float(_scene.get_node("GaiaSphere").call(&"height_at", p)) - 0.02:
					under += 1
		_check("the cables have set", set_all)
		_check("none of a cable is under the ground", under == 0, "(%d points)" % under)
		var pts: PackedVector3Array = _line["pts"]
		var longest := 0.0
		for i in pts.size() - 1:
			longest = maxf(longest, pts[i].distance_to(pts[i + 1]))
		_check("a cable's points keep their distance", longest < Power.SEG * 1.2, "(longest %.2f of %.2f)" % [longest, Power.SEG])
		var battery: Power.Dev = power.devices[1]
		_check("noon: the battery charges", float(battery["charge"]) > 0.0, "(%s)" % battery["state"])
		_check("noon: the pole is dark", float(power.devices[3]["lit"]) == 0.0, "(%s)" % power.devices[3]["state"])
		print("power: panel %s, junction %s, one circuit %s" % [power.devices[0]["state"], power.devices[2]["state"],
				power.devices[0]["net"] == power.devices[3]["net"]])
		_was = float(battery["charge"])
		enviro.set("hour", 0.5)
	if _step == 520:
		var battery: Power.Dev = power.devices[1]
		_check("night: the pole is lit from the battery", float(power.devices[3]["lit"]) > 0.99 and float(battery["charge"]) < _was,
				"(%s, battery %s)" % [power.devices[3]["state"], battery["state"]])
		_check("the lamp shines", (power.devices[3]["lamp"] as OmniLight3D).light_energy > 3.0)
		# The pole's cable pulled out at the pole and carried off.
		power.call(&"_take_up", _line, 1)
		_check("a plug in hand", power.carrying())
	if _step == 560:
		_check("unplugged: the pole goes dark", float(power.devices[3]["lit"]) == 0.0, "(%s)" % power.devices[3]["state"])
		ex.global_position += Vector3(0, 0, 14)
	if _step == 700:
		var pts: PackedVector3Array = _line["pts"]
		_check("carried off: the cable has paid out", float(pts.size()) * Power.SEG > 12.0, "(%.1f m of cable, live %s)" % [float(pts.size()) * Power.SEG, _line["live"]])
		power.drop()
		_check("put down: nothing in hand", not power.carrying())
	if _step == 1150:
		_check("the dropped cable has set", not bool(_line["live"]))
		var data := title.save_game()
		_check("saved", data)
		_was = float(power.devices[1]["charge"])
		power.restore({})
		_check("cleared", power.devices.is_empty() and power.cables.is_empty())
		_check("loaded", title.load_game())
		_check("back: four parts, three cables, the charge", power.devices.size() == 4 and power.cables.size() == 3
				and absf(float(power.devices[1]["charge"]) - _was) < 0.01)
		var loose := 0
		for cable: Power.Line in power.cables:
			for e in 2:
				if cable["ends"][e].get("dev") == null:
					loose += 1
		_check("back: one loose end, as it was left", loose == 1)
		_check("the axe: a part comes down and its cables fall out", true)
		power.remove(power.devices[2])
		var held := 0
		for cable: Power.Line in power.cables:
			for e in 2:
				if cable["ends"][e].get("dev") != null:
					held += 1
		_check("with the junction gone, two plugs are still in sockets", held == 2, "(%d)" % held)
	if _step == 1160:
		print("power: %s" % ("ALL OK" if _fails == 0 else "%d FAILED" % _fails))
		return true
	return false
