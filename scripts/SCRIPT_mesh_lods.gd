class_name MeshLods
extends RefCounted

# MANY LEVELS OF DETAIL FROM ONE MESH. Godot's own simplifier (the one the
# importer runs: ImporterMesh.generate_lods) takes a mesh down by halves, and
# each step is kept here as a mesh of its own, so a rock can be handed down
# through as many levels as there are, each drawn only where its triangles are
# still worth drawing:
#
#     MeshLods.chain(mesh)          # [the mesh, ~1/2, ~1/4, ... down to 20 triangles]
#
# The levels share the mesh's vertices and differ in which they use. Kept per
# mesh, so asking twice costs nothing.

static var _made := {}


static func chain(mesh: ArrayMesh, fewest := 20) -> Array:
	if mesh == null:
		return []
	if _made.has(mesh):
		return _made[mesh]
	var out: Array = [mesh]
	if mesh.get_surface_count() == 1:
		var arrays := mesh.surface_get_arrays(0)
		var material := mesh.surface_get_material(0)
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		im.generate_lods(60.0, 0.0, [])
		for i in im.get_surface_lod_count(0):
			var idx := im.get_surface_lod_indices(0, i)
			if idx.size() / 3 < fewest:
				break
			var a := arrays.duplicate()
			a[Mesh.ARRAY_INDEX] = idx
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			if material != null:
				m.surface_set_material(0, material)
			out.append(m)
	_made[mesh] = out
	return out


## Hand-over distances for a chain of `levels` meshes of a thing `size` metres
## across: each level held until the thing is about as many pixels across as
## its triangles can afford, stepping out by `step` times each time. `levels - 1`
## distances (the last level has no end: it is drawn as far as anything is).
static func distances(levels: int, size: float, step := 1.75) -> Array:
	var out: Array = []
	var d := size * 3.0
	for i in levels - 1:
		out.append(d)
		d *= step
	return out
