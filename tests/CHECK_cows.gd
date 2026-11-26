extends SceneTree

# WHAT THE COWS DO WITH THEIR TIME: stands by the nearest herd for ten minutes of
# game time and counts what each cow chose to do and how long it spent in each
# state, to show that they differ and that nothing falls over.
#
#   godot --headless --fixed-fps 10 --path . --script res://tests/CHECK_cows.gd

var _scene: Node
var _herd := {}
var _frames := 0
var _did := {}          # per cow: {what: times chosen}
var _last := {}
var _spent := {}        # state -> seconds, all cows


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(delta: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	var cows: Node = _scene.get_node("CowHerds")
	if _herd.is_empty():
		var herds: Array = cows.get("_herds")
		if not bool(ex.get("arrived")) or herds.is_empty():
			return false
		var best := 1e9
		for h: Dictionary in herds:
			var c: Vector2 = h["centre"]
			var d := c.distance_to(Vector2(ex.global_position.x, ex.global_position.z))
			if d < best:
				best = d
				_herd = h
		ex.set("flying", true)
		return false
	# Stood a dozen metres off the herd's middle, wherever that has drifted to.
	var c: Vector2 = _herd["centre"]
	var g := float(_scene.get_node("GaiaSphere").call(&"height_at", Vector3(c.x + 12.0, 0, c.y), 0.0))
	ex.global_position = Vector3(c.x + 12.0, g + 1.0, c.y)
	_frames += 1
	var list: Array = _herd["cows"]
	for i in list.size():
		var cow: Dictionary = list[i]
		var state := String(cow["state"])
		_spent[state] = float(_spent.get(state, 0.0)) + delta
		var did := String(cow.get("did", ""))
		if did != String(_last.get(i, "")):
			_last[i] = did
			if not _did.has(i):
				_did[i] = {}
			_did[i][did] = int(_did[i].get(did, 0)) + 1
	if _frames < 6000:
		return false
	print("cows: %d in the herd, %.0f s watched" % [list.size(), float(_frames) * delta])
	for i in list.size():
		var cow: Dictionary = list[i]
		print("  cow %d  hungry %.2f restless %.2f nosy %.2f friendly %.2f idle %.2f  chose %s" % [i, float(cow["hungry"]),
				float(cow["restless"]), float(cow["nosy"]), float(cow["friendly"]), float(cow["idle"]), _did.get(i, {})])
	var total := 0.0
	for k in _spent:
		total += float(_spent[k])
	var shares := {}
	for k in _spent:
		shares[k] = "%d%%" % int(round(100.0 * float(_spent[k]) / total))
	print("  time spent: %s" % shares)
	quit(0)
	return true
