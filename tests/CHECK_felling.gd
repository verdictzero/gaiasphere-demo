extends SceneTree

# HOW LONG A FELLING TAKES: loads the island, sends a run of trees over one a
# frame, and prints the main-thread cost of each (the call itself, not the frame).
#
#   godot --headless --path . --script res://tests/CHECK_felling.gd

var _scene: Node
var _costs: Array = []
var _wait := 0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	if not explorer.arrived or _scene.has_node("LoadingCover"):
		return false
	_wait += 1
	if _wait < 30:
		return false
	var flora: Flora = _scene.get_node("Flora")
	var wood: Woodcutting = _scene.get_node("Woodcutting")
	var here: Vector3 = explorer.global_position
	var tree := flora.tree_on(here + Vector3(0, 1, 0), Vector3.ZERO, 0.0, 60.0)
	if tree.is_empty() or _costs.size() >= 12:
		_costs.sort()
		print("felling: %d trees, main-thread ms each: first %.2f, median %.2f, worst %.2f" % [
				_costs.size(), _costs[0] if false else _first, _costs[_costs.size() / 2], _costs[-1]])
		quit(0 if not _costs.is_empty() else 1)
		return true
	var t := Time.get_ticks_usec()
	wood._topple(tree, Vector3(1, 0, 0))
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	if _costs.is_empty():
		_first = ms
	_costs.append(ms)
	return false


var _first := 0.0
