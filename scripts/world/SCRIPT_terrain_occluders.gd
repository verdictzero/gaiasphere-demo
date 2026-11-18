class_name TerrainOccluders
extends Node3D

# WHAT THE HILLS HIDE. Godot's occlusion culling skips anything wholly behind an
# occluder, but it needs occluders, and the terrain is generated, not baked. This
# lays a coarse copy of the ground under the real one as occluder meshes: a 32 m
# grid in 8 x 8 patches, each point the LOWEST ground near it and a little lower
# still, so the occluder is always inside the real hill and can never hide what
# the hill does not. Trees and fog are see-through and occlude nothing.
# (`rendering/occlusion_culling/use_occlusion_culling` is on in project.godot.)

@export var world_path: NodePath = ^"../IslandWorld"
@export var grid := 32.0
@export var sink := 1.5

const PATCH := 8


func _ready() -> void:
	var world := get_node_or_null(world_path)
	if world == null or not world.has_method(&"get_field"):
		return
	var field: IslandField = world.call(&"get_field")
	if not field._ready:
		field.prepare()
	var thread := Thread.new()
	thread.start(_build.bind(field.clone(), thread))


func _build(field: IslandField, thread: Thread) -> void:
	var isl: Variant = field.island_in_cell(field.hub_cell())
	var extent := float(field.island_extent(isl))
	var n := int(ceil(2.0 * extent / grid)) + 1
	var h := PackedFloat32Array()
	h.resize(n * n)
	for z in n:
		for x in n:
			var wx := float(x) * grid - extent
			var wz := float(z) * grid - extent
			var low := 1e9
			for o in [Vector2.ZERO, Vector2(grid, 0) * 0.5, Vector2(-grid, 0) * 0.5, Vector2(0, grid) * 0.5, Vector2(0, -grid) * 0.5]:
				low = minf(low, field.height_at(wx + o.x, wz + o.y, -1e9))
			h[z * n + x] = low - sink
	var patches: Array = []
	for pz in range(0, n - 1, PATCH):
		for px in range(0, n - 1, PATCH):
			var verts := PackedVector3Array()
			var idx := PackedInt32Array()
			var at := {}
			for z in range(pz, mini(pz + PATCH, n - 1)):
				for x in range(px, mini(px + PATCH, n - 1)):
					var corners := [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]
					# A cell with a corner off the island still occludes, from the corners
					# that are on it: the last ground before the edge is what hides the
					# rock hanging below the rim, so it must not be left out.
					var on_land := 0
					var low := 1e9
					for c in corners:
						if h[c.y * n + c.x] > -1e8:
							on_land += 1
							low = minf(low, h[c.y * n + c.x])
					if on_land < 3:
						continue
					for c in corners:
						if h[c.y * n + c.x] < -1e8:
							h[c.y * n + c.x] = low - 6.0
					var ids: Array = []
					for c in corners:
						if not at.has(c):
							at[c] = verts.size()
							verts.append(Vector3(float(c.x) * grid - extent, h[c.y * n + c.x], float(c.y) * grid - extent))
						ids.append(at[c])
					idx.append_array([ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]])
			if not idx.is_empty():
				patches.append([verts, idx])
	_install.call_deferred(patches, thread)


func _install(patches: Array, thread: Thread) -> void:
	thread.wait_to_finish()
	for p in patches:
		var occ := ArrayOccluder3D.new()
		occ.set_arrays(p[0], p[1])
		var inst := OccluderInstance3D.new()
		inst.occluder = occ
		add_child(inst)
	print("[occluders] %d terrain patches" % patches.size())
