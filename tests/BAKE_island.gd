extends SceneTree

# BAKE THE ISLAND: build every terrain chunk at every level of detail once, here,
# and write them to res://data/bake so a shipped build reads them back instead of
# generating the island on the player's device at every launch.
#
#   godot --headless --path . --script res://tests/BAKE_island.gd
#
# Writes data/bake/terrain_<signature>.bake and data/bake/CODE_DIGESTS.json (the
# hashes of the generating scripts, which an exported build cannot compute for
# itself: see SCRIPT_bake_store.gd). The signature covers the island's settings
# and the generating code, so a bake that no longer matches is simply not found
# and the game generates as before. Run it again after changing either;
# tools/build.sh does.

var _scene: Node
var _done := false


func _initialize() -> void:
	var bake := root.get_node("TerrainBake")
	bake.record_arrays = true
	_scene = (load("res://scenes/SCENE_west_virginia.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_scene.get_node("IslandWorld").connect(&"pregen_finished", func() -> void: _done = true)


func _process(_delta: float) -> bool:
	if not _done:
		return false
	# The planting next: every plant on the island, placed once and written out
	# beside the terrain (see Flora.save_bake).
	var flora := _scene.get_node_or_null("Flora")
	if flora != null and not bool(flora.call(&"prefill_step")):
		return false
	var bake := root.get_node("TerrainBake")
	var world := _scene.get_node("IslandWorld")
	var sig := String(world.get("_bake_sig"))
	if sig == "":
		push_error("bake: the world has no bake signature")
		quit(1)
		return true
	var dir := "res://data/bake"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for old in DirAccess.get_files_at(dir):
		if old.ends_with(".bake"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(old)))
	var path := dir.path_join(BakeStore.file_name(bake.STORE_NAME, sig))
	var n: int = bake.save_to(path)
	var table := {}
	for src in bake._SOURCES:
		table[String(src)] = FileAccess.get_sha256(String(src))
	if flora != null:
		for src in flora.SOURCES:
			table[String(src)] = FileAccess.get_sha256(String(src))
		var fpath := dir.path_join(BakeStore.file_name(flora.BAKE_STORE, String(flora.call(&"bake_signature"))))
		var tiles: int = flora.save_bake(fpath)
		print("bake: %d planted tiles -> %s (%.1f MB)" % [tiles, fpath, FileAccess.get_file_as_bytes(fpath).size() / 1048576.0])
		if tiles <= 0:
			quit(1)
			return true
	var f := FileAccess.open(BakeStore.DIGEST_TABLE, FileAccess.WRITE)
	f.store_string(JSON.stringify(table, "\t"))
	f.close()
	var size := FileAccess.get_file_as_bytes(path).size() if n > 0 else 0
	print("bake: %d chunks -> %s (%.1f MB)" % [n, path, size / 1048576.0])
	quit(0 if n > 0 else 1)
	return true
