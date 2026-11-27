extends SceneTree

# SAVING AND LOADING, there and back: a building of three pieces and a fire are
# put up, a tree felled, stones put in the bag, the player moved and the hour
# set; the game is saved; all of it is undone or changed; the save is loaded; and
# every one of them is looked at again.
#
#   godot --headless --path . --script res://tests/CHECK_save.gd

var _scene: Node
var _step := 0
var _fails := 0
var _felled := Vector3.ZERO
var _spot := Vector3.ZERO


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _check(what: String, ok: bool, detail := "") -> void:
	print("save: %s %s %s" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_fails += 1


func _pieces(building: Node) -> int:
	var n := 0
	for b: Dictionary in building.call(&"saved"):
		n += (b["pieces"] as Array).size()
	return n


func _process(_d: float) -> bool:
	var ex: CharacterBody3D = _scene.get_node("Explorer")
	if not ex.arrived or _scene.has_node("LoadingCover"):
		return false
	var title: TitleMenu = _scene.get_node("TitleMenu")
	var building: Node = _scene.get_node("Building")
	var cooking: Node = _scene.get_node("Cooking")
	var flora: Flora = _scene.get_node("Flora")
	var bag: Inventory = _scene.get_node("Inventory")
	var vitals: Node = _scene.get_node("Vitals")
	var enviro: Node = _scene.get_node("Enviro")
	_step += 1
	if _step == 5:
		_spot = ex.global_position + Vector3(6, 0, 4)
		var frame := Transform3D(Basis(), Vector3(_spot.x, _spot.y, _spot.z))
		var pieces: Array = []
		for i in 3:
			pieces.append({"item": "foundation", "key": "F:%d:0:1" % i, "at": frame * Transform3D(Basis(), Vector3(1.0 + 2.0 * i, 0, 1)),
				"other_hand": false})
		building.call(&"restore", [{"frame": frame, "pieces": pieces}])
		cooking.call(&"restore", [Transform3D(Basis(), _spot + Vector3(0, 0, 6))])
		# The nearest tree there is, felled.
		var layer: Dictionary = flora.call(&"_tree_layer")
		var best := 1e9
		var tree := {}
		for key: Vector2i in layer["cache"]:
			var bufs: Array = layer["cache"][key]
			for k in bufs.size():
				var buf: PackedFloat32Array = bufs[k]
				for i in range(0, buf.size(), 12):
					var at := Vector3(buf[i + 3], buf[i + 7], buf[i + 11])
					if at.distance_to(ex.global_position) < best:
						best = at.distance_to(ex.global_position)
						tree = {"key": key, "kind": k, "index": i, "origin": at}
		_felled = tree["origin"]
		flora.fell(tree)
		bag.add("stone", 7)
		vitals.set("hunger", 61.0)
		vitals.set("health", 83.0)
		enviro.set("hour", 16.5)
		ex.global_position = _spot + Vector3(0, 1.0, -3.0)
		ex.rotation.y = 1.25
		_check("three pieces built", _pieces(building) == 3, "(%d)" % _pieces(building))
		_check("saved", title.save_game())
	if _step == 10:
		# Everything changed.
		building.call(&"restore", [])
		cooking.call(&"restore", [])
		bag.take("stone", bag.count_of("stone"))
		vitals.set("hunger", 5.0)
		vitals.set("health", 12.0)
		enviro.set("hour", 3.0)
		ex.global_position += Vector3(40, 5, 40)
		ex.rotation.y = -2.0
		_check("nothing built before the load", _pieces(building) == 0)
		_check("loaded", title.load_game())
	if _step == 16:
		_check("three pieces built again", _pieces(building) == 3, "(%d)" % _pieces(building))
		_check("a fire again", (cooking.call(&"saved") as Array).size() == 1)
		_check("the planks", bag.count_of("stone") == 7, "(%d)" % bag.count_of("stone"))
		_check("hunger and health", absf(float(vitals.get("hunger")) - 61.0) < 1.0 and absf(float(vitals.get("health")) - 83.0) < 1.0,
				"(%.1f, %.1f)" % [float(vitals.get("hunger")), float(vitals.get("health"))])
		_check("the hour", absf(float(enviro.get("hour")) - 16.5) < 0.05, "(%.2f)" % float(enviro.get("hour")))
		_check("where you stand", ex.global_position.distance_to(_spot + Vector3(0, 1.0, -3.0)) < 0.5,
				"(%.2f m off)" % ex.global_position.distance_to(_spot + Vector3(0, 1.0, -3.0)))
		_check("which way you face", absf(ex.rotation.y - 1.25) < 0.01)
		_check("the felled tree on the list", (flora.get("taken") as Array).size() == 1)
		print("save: %s" % ("ALL AS IT WAS SAVED" if _fails == 0 else "%d THINGS WRONG" % _fails))
		quit(0 if _fails == 0 else 1)
		return true
	return false
