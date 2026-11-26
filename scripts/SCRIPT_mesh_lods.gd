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


## A mesh taken down to about `triangles` (never more), by the same simplifier.
## Its vertices are welded by position first (their normals averaged): a mesh
## with split vertices is all borders to the simplifier, which will not move one.
static func reduced(mesh: ArrayMesh, triangles: int) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# (Its vertex colours, where it has them, are carried: averaged at each weld.)
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var wc := PackedColorArray()
	var wcount := PackedInt32Array()
	var where := {}
	var to := PackedInt32Array()
	to.resize(verts.size())
	var wv := PackedVector3Array()
	var wn := PackedVector3Array()
	for i in verts.size():
		var key := verts[i].snappedf(0.0005)
		if not where.has(key):
			where[key] = wv.size()
			wv.append(verts[i])
			wn.append(Vector3.ZERO)
			wc.append(Color(0, 0, 0, 0))
			wcount.append(0)
		to[i] = where[key]
		if i < colours.size():
			wc[to[i]] += colours[i]
			wcount[to[i]] += 1
		wn[to[i]] += normals[i] if i < normals.size() else Vector3.UP
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in wv.size():
		st.set_normal(wn[i].normalized())
		st.add_vertex(wv[i])
	for t in range(0, index.size(), 3):
		var a := to[index[t]]
		var b := to[index[t + 1]]
		var c := to[index[t + 2]]
		if a != b and b != c and a != c:
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
	var idx := st.generate_lod(1e9, triangles * 3)
	if idx.is_empty() or idx.size() >= index.size():
		return mesh
	# Only the vertices it still uses.
	var slot := {}
	var kv := PackedVector3Array()
	var kn := PackedVector3Array()
	var ki := PackedInt32Array()
	var kc := PackedColorArray()
	for i in idx:
		if not slot.has(i):
			slot[i] = kv.size()
			kv.append(wv[i])
			kn.append(wn[i].normalized())
			if not colours.is_empty():
				kc.append(wc[i] / float(maxi(wcount[i], 1)))
		ki.append(slot[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = kv
	out[Mesh.ARRAY_NORMAL] = kn
	out[Mesh.ARRAY_INDEX] = ki
	if not kc.is_empty():
		out[Mesh.ARRAY_COLOR] = kc
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m


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
