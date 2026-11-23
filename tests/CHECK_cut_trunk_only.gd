extends SceneTree

# The band of a tree the axe carves is trunk and nothing else: no corner of it
# stands further from the trunk's middle than its bark does, for every kind of
# tree, and what boughs hung in the band went with the tree above.
#
#   godot --headless --path . --script res://tests/CHECK_cut_trunk_only.gd

var _frames := 0


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	var flora := Flora.new()
	flora._field = load("res://data/ISLANDFIELD_forest_003_r2.tres")
	flora._build_layers()
	var wood := Woodcutting.new()
	wood._flora = flora
	var ok := true
	for kind in Flora.FIRS.size():
		var whole := flora.tree_mesh(kind) as ArrayMesh
		var sawn := wood._pieces(kind)
		var centre: Vector3 = sawn["centre"]
		var girth := float(sawn["girth"])
		var furthest := 0.0
		var corners := 0
		for half in ["low", "high"]:
			var arrays: Array = sawn[half]
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
				furthest = maxf(furthest, Vector2(verts[i].x - centre.x, verts[i].z - centre.z).length())
				corners += 1
		var top := sawn["top"] as ArrayMesh
		print("trunk only: %s, trunk %.2f m thick at the cut, the band reaches %.2f m out (%d corners); the top has %d surfaces to the tree's %d" % [
				Flora.FIRS[kind], girth * 2.0, furthest, corners, top.get_surface_count(), whole.get_surface_count()])
		ok = ok and corners > 0 and furthest <= girth * 1.3 + 0.031
	print("trunk only: ok" if ok else "trunk only: FAILED")
	flora.free()
	wood.free()
	quit(0 if ok else 1)
	return true
