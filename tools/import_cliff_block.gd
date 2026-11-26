extends SceneTree

# THE CLIFF BLOCK, out of the example it was handed over in: the first mesh of a
# .glb (every block in the example is the same mesh), saved by itself as
# assets/cliff_block/cliff_block.res for SCRIPT_cliff_rocks.gd, which takes it
# down through its levels of detail (MeshLods) and textures it as the terrain's
# rock. Its own material is dropped.
#
#   godot --headless --path . --script res://tools/import_cliff_block.gd -- /path/to/example.glb

func _initialize() -> void:
	var src := ""
	for a in OS.get_cmdline_user_args():
		src = a
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if src == "" or doc.append_from_file(src, st) != OK:
		push_error("usage: -- /path/to/example.glb")
		quit(1)
		return
	var scene := doc.generate_scene(st)
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not String(mi.name).begins_with("cliff"):
			continue
		var arrays := mi.mesh.surface_get_arrays(0)
		# Position, normal and index are all the rock shader reads.
		var keep := []
		keep.resize(Mesh.ARRAY_MAX)
		keep[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
		keep[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		keep[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, keep)
		ResourceSaver.save(m, "res://assets/cliff_block/cliff_block.res", ResourceSaver.FLAG_COMPRESS)
		print("cliff block: %d triangles, %s" % [(keep[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, m.get_aabb()])
		break
	scene.free()
	quit(0)
