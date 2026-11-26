extends SceneTree

# How many rocks the hills take (CliffRocks, the tablelands off), and of what.
#   godot --headless --path . --script res://tests/CHECK_cliff_pepper.gd

var _scene: Node
var _t := 0.0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(delta: float) -> bool:
	_t += delta
	var cliffs := _scene.get_node_or_null("CliffRocks")
	if cliffs == null:
		print("no CliffRocks")
		quit(1)
		return true
	if not bool(cliffs.call(&"placed")):
		return false
	var rocks: Array = cliffs.get("_rocks")
	var kinds := {}
	for r in rocks:
		kinds[r[0]] = int(kinds.get(r[0], 0)) + 1
	print("cliff rocks on the hills: %d  by kind %s  after %.0f s" % [rocks.size(), kinds, _t])
	quit(0)
	return true
