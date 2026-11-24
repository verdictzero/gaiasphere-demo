extends SceneTree

# THE FIRST TIME ANYTHING HAPPENS: each thing the player can set off (the
# blade's beam bursting a cow, a cut through a cow, a bite out of a tree, a
# tree felled, a blow on a rock, a cooking fire set down) is done twice, at two
# different places, and for each the longest frame that followed and the shader
# pipelines that had to be built while drawing (each a stall) are counted. The
# first time should cost no more than the second.
#
#   godot --path . --script res://tests/CHECK_first_use.gd
#
# (Needs a real renderer: headless compiles nothing.) The first times are got
# over behind the loading screen (SCRIPT_prewarm.gd): every "#1" here should
# build next to nothing, as its "#2" does.

var _scene: Node
var _step := -1
var _wait := 0
var _last := 0
var _watch := ""
var _frames := 0
var _worst := 0.0
var _count0 := {}
var _report: Array = []
var _trees: Array = []
var _rocks: Array = []
var _cows: Array = []

const WATCH_FRAMES := 40
const COUNTERS := {
	"draw": Performance.PIPELINE_COMPILATIONS_DRAW,
	"surface": Performance.PIPELINE_COMPILATIONS_SURFACE,
	"mesh": Performance.PIPELINE_COMPILATIONS_MESH,
	"special": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
}


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _counts() -> Dictionary:
	var out := {}
	for k in COUNTERS:
		out[k] = int(Performance.get_monitor(COUNTERS[k]))
	return out


func _look(from: Vector3, target: Vector3) -> void:
	var explorer: Node3D = _scene.get_node("Explorer")
	var cam := root.get_camera_3d()
	explorer.global_position = from - Vector3.UP * cam.position.y
	var d := target - from
	explorer.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	cam.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _begin(what: String) -> void:
	_watch = what
	_frames = 0
	_worst = 0.0
	_count0 = _counts()


func _hold(id: String) -> void:
	for i in Inventory.HOTBAR:
		var bag: Inventory = _scene.get_node("Inventory")
		if bag.slots[i] != null and String(bag.slots[i][0]) == id:
			bag.selected = i


func _find_targets() -> void:
	var flora: Flora = _scene.get_node("Flora")
	var here: Vector3 = _scene.get_node("LandingSpot").call(&"hatch_spot")
	for i in 900:
		var ang := float(i) * 0.7
		var p := here + Vector3(cos(ang), 0.0, sin(ang)) * (6.0 + 0.2 * float(i)) + Vector3(0, 1.5, 0)
		var t := flora.tree_on(p, Vector3.ZERO, 0.0, 4.0)
		if t.is_empty() or float(t["radius"]) < 0.2:
			continue
		var dup := false
		for o in _trees:
			if (o["origin"] as Vector3).distance_to(t["origin"]) < 8.0:
				dup = true
		if not dup:
			_trees.append(t)
		if _trees.size() >= 4:
			break
	var layer := flora._rock_layer()
	for key in layer["cache"]:
		for buf: PackedFloat32Array in layer["cache"][key]:
			for i in range(0, buf.size(), Flora.STRIDE):
				var size := Vector3(buf[i + 1], buf[i + 5], buf[i + 9]).length()
				var p := Vector3(buf[i + 3], buf[i + 7], buf[i + 11])
				if size < 0.7 or size > 1.3 or p.y < 1.0 or p.distance_to(here) > 400.0:
					continue
				var far := true
				for o in _rocks:
					if (o as Vector3).distance_to(p) < 10.0:
						far = false
				if far and _rocks.size() < 2:
					_rocks.append(p)
	var herds: CowHerds = _scene.get_node("CowHerds")
	for herd in herds._herds:
		for cow in herd["cows"]:
			_cows.append(cow["node"])


func _process(_dt: float) -> bool:
	var now := Time.get_ticks_usec()
	var took := float(now - _last) / 1000.0
	_last = now
	var explorer := _scene.get_node("Explorer")
	var cam := root.get_camera_3d()
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 10.0
			enviro.set_weather("clear", 0.0)
			(_scene.get_node("CowHerds") as Node).set_process(false)
			explorer.flying = true
			_find_targets()
			print("first use: %d trees, %d rocks, %d cows" % [_trees.size(), _rocks.size(), _cows.size()])
			_step = 0
			_wait = 90
		return false
	if _watch != "":
		_frames += 1
		_worst = maxf(_worst, took)
		if _frames >= WATCH_FRAMES:
			var c := _counts()
			var line := "first use: %-16s worst frame %6.0f ms   pipelines built while drawing %d (surface %d, mesh %d, special %d)" % [
					_watch, _worst, c["draw"] - _count0["draw"], c["surface"] - _count0["surface"],
					c["mesh"] - _count0["mesh"], c["special"] - _count0["special"]]
			print(line)
			_report.append(line)
			_watch = ""
			_wait = 20
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var wood: Woodcutting = _scene.get_node("Woodcutting")
	var mine: Mining = _scene.get_node("Mining")
	var slicing: CowSlicing = _scene.get_node("CowSlicing")
	var play: SwordPlay = _scene.get_node("SwordPlay")
	var dir := -cam.global_basis.z
	match _step:
		0:
			_begin("idle")
		1, 2:
			# The beam: the katana charged and thrown at a cow six metres off.
			_hold("katana")
			var cow: Node3D = _cows[_step - 1]
			var at := cow.global_position + Vector3(0, 0.8, 0)
			_look(at + Vector3(6.0, 0.6, 0.0), at)
			_wait = 8
			_step += 10
			return false
		11, 12:
			play._throw()
			_begin("beam #%d" % (_step - 10))
			_step -= 10
		3, 4:
			_hold("katana")
			var cow: Node3D = _cows[_step - 1]
			var at := cow.global_position + Vector3(0, 0.8, 0)
			_look(at + Vector3(2.4, 0.5, 1.0), at)
			_wait = 4
			_step += 10
			return false
		13, 14:
			slicing.slice(cam.global_position, dir, cam.global_basis * Vector3(1, 0.35, 0))
			_begin("cut cow #%d" % (_step - 12))
			_step -= 10
		5, 6:
			_hold("axe")
			var t: Dictionary = _trees[_step - 5]
			var foot: Vector3 = t["origin"]
			_look(foot + Vector3(float(t["radius"]) + 1.8, 1.6, 0.0), foot + Vector3(0, 0.8, 0))
			_wait = 6
			_step += 10
			return false
		15, 16:
			if not wood.strike(cam.global_position, dir):
				print("first use: (the swing met no tree)")
			_begin("tree bite #%d" % (_step - 14))
			_step -= 10
		7, 8:
			if not wood.strike(cam.global_position, dir, true):
				print("first use: (the felling swing met no tree)")
			_begin("tree fell #%d" % (_step - 6))
		9, 10:
			_hold("pickaxe")
			var r: Vector3 = _rocks[mini(_step - 9, _rocks.size() - 1)]
			_look(r + Vector3(2.4, 1.0, 0.0), r + Vector3(0, 0.25, 0))
			_wait = 6
			_step += 20
			return false
		29, 30:
			if not mine.strike(cam.global_position, dir):
				print("first use: (the blow met no rock)")
			_begin("rock blow #%d" % (_step - 28))
			_step = 9 if _step == 29 else 49
		50:
			(cam.get_node("Flashlight") as Light3D).visible = true
			_begin("torch on #1")
		51:
			(cam.get_node("Flashlight") as Light3D).visible = false
			var cooking: Cooking = _scene.get_node("Cooking")
			cooking.set_down(Transform3D(Basis(), cam.global_position + Vector3(dir.x, 0, dir.z).normalized() * 3.0 - Vector3.UP * 1.6))
			_begin("cooking fire")
		52:
			(cam.get_node("Flashlight") as Light3D).visible = true
			_begin("torch on #2")
		_:
			print("first use: done")
			quit(0)
			return true
	_step += 1
	if _step == 7 or _step == 8:
		# The felling swings go back to the trees just bitten.
		var t: Dictionary = _trees[_step - 7]
		var foot: Vector3 = t["origin"]
		_look(foot + Vector3(float(t["radius"]) + 1.8, 1.6, 0.0), foot + Vector3(0, 0.8, 0))
	return false
