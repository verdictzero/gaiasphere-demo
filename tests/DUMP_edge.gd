extends SceneTree

# THE ISLAND'S EDGE FROM ABOVE, AS DATA: builds the terrain's coast chunks the way
# the game does and writes every wall and rim vertex above the cloud sea, plus the
# footprint of every rock mass CliffDressing would place, to a JSON file.
# tools/plot_edge.py draws it. It is how the rocks are lined up with the wall.
#
#   godot --headless --path . --script res://tests/DUMP_edge.gd -- --out=/some/file.json

func _initialize() -> void:
	var out := "user://edge.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var field: IslandField = load("res://data/ISLANDFIELD_forest_003_r2.tres")
	field.prepare()
	var isl: Variant = field.island_in_cell(field.hub_cell())
	var extent: float = field.island_extent(isl)
	var size := 128.0
	var n := int(ceil(2.0 * extent / size))
	var pivot := Vector3(isl.center.x, isl.base_y, isl.center.y)
	var wall: Array = []       # [x, y, z] of cliff vertices from the rim down to -50
	var top: Array = []        # [x, z] of walkable-surface vertices near the coast
	for cz in n:
		for cx in n:
			var c := Vector2((cx + 0.5) * size - extent, (cz + 0.5) * size - extent)
			if c.length() < isl.radius * 0.6 or c.length() > extent + size:
				continue
			var built: Dictionary = IslandChunkMesher.build(field, isl, isl.center.x - extent,
					isl.center.y - extent, cx, cz, size, 16, pivot)
			for band in built.get("cliff_bands", []):
				for v in (band["arrays"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
					if v.y > -160.0:
						wall.append([snappedf(v.x + pivot.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z + pivot.z, 0.1)])
			var t: Variant = built.get("top")
			if t != null and t is Array and (t as Array).size() > Mesh.ARRAY_VERTEX and t[Mesh.ARRAY_VERTEX] != null:
				for v in (t[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					top.append([snappedf(v.x + pivot.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z + pivot.z, 0.1)])
	var rocks: Array = CliffDressing.layout(field)
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"wall": wall, "top": top, "rocks": rocks}))
	f.close()
	print("edge: %d wall vertices, %d surface vertices, %d rocks -> %s" % [wall.size(), top.size(), rocks.size(), out])
	quit()
