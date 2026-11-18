extends SceneTree

# DOES THE GAME READ THE BAKE? Starts the scene, waits for the island, and reports
# where the terrain came from and how long it took.
#
#   godot --headless --path . --script res://tests/CHECK_bake.gd [-- --as-exported]

var _scene: Node
var _t0 := 0
var _done := false


func _initialize() -> void:
	# --as-exported: answer the code hashes from the shipped table alone, as a build
	# without the script sources has to. It is the check that the bake an export
	# carries is the bake it will go looking for.
	if OS.get_cmdline_user_args().has("--as-exported"):
		BakeStore.read_as_exported(JSON.parse_string(FileAccess.get_file_as_string(BakeStore.DIGEST_TABLE)))
	_t0 = Time.get_ticks_msec()
	_scene = (load("res://scenes/SCENE_west_virginia.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_scene.get_node("IslandWorld").connect(&"pregen_finished", func() -> void: _done = true)


func _process(_delta: float) -> bool:
	if not _done:
		return false
	var world := _scene.get_node("IslandWorld")
	print("check: island ready in %.1f s, bake source '%s', store %s" % [
			(Time.get_ticks_msec() - _t0) / 1000.0, world.get("bake_source"), root.get_node("TerrainBake").stats()])
	quit()
	return true
