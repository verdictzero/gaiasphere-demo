extends SceneTree

# HOW LONG DOES THE PLANTING TAKE? Starts the scene and reports the seconds between
# the terrain being ready and every plant being placed (what the loading screen
# waits for after the terrain), and how many of each there are.
#
#   godot --headless --path . --script res://tests/CHECK_planting.gd

var _scene: Node
var _world_done := -1


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_scene.get_node("GaiaSphere").connect(&"pregen_finished", func() -> void: _world_done = Time.get_ticks_msec())


func _process(_delta: float) -> bool:
	var flora := _scene.get_node("Flora")
	if _world_done < 0 or not flora._prefilled:
		return false
	print("check: planting took %.1f s after the terrain (%d tiles)" % [
			(Time.get_ticks_msec() - _world_done) / 1000.0, flora._prefill_jobs.size()])
	quit()
	return true
