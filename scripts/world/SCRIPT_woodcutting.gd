class_name Woodcutting
extends Node3D

# FELLING TREES WITH THE SWORD, AND THE LOGS THEY BECOME.
#
# A swing of the axe or the sword that meets a trunk cuts a wedge out of it: a
# real notch, two flat faces of fresh wood, deeper with every bite. When it is
# most of the way through the tree goes over, hinged on what is left, away from
# the cut, slowly and then fast; where it hits the ground it breaks into a run
# of logs laid along its length. The stump is the tree's own: the model is sawn
# in three (stump, the band the axe works in, the rest) the first time it is
# struck, so what falls leaves exactly what it stood on. A charged crescent cuts whatever tree it strikes through at once. Logs are
# real bodies: they roll and settle, and walking up to one gathers it into the
# inventory.
#
# The tree is taken out of Flora's own instance buffers (`Flora.fell`), so it is
# gone at every level of detail and from the impostors too. The log is a mesh
# made here: the firs' bark round its side, the sawn end on both caps.

@export var flora_path: NodePath = ^"../Flora"
@export var explorer_path: NodePath = ^"../Explorer"
@export var inventory_path: NodePath = ^"../Inventory"
## How far a swing reaches, metres.
@export var reach := 3.1
@export var gather_radius := 2.3
@export var max_logs := 90

const LOG_LENGTH := 1.5
const GIRTHS := [0.12, 0.24, 0.48]
## The band of trunk the axe works in, metres up a tree of the model's own size:
## below it is the stump, above it the tree that falls.
const BAND_LOW := 0.55
const BAND_HIGH := 1.05
## The lean (radians from upright) at which a falling tree has reached the ground.
const DOWN := 1.5

var _flora: Flora
var _explorer: Node3D
var _inventory: Node
var _bites := {}             # tree origin -> swings taken
var _logs: Array = []        # [body, seconds lain]
var _cuts: Array = []        # trees standing with a cut in them
var _sawn := {}              # kind of tree -> its pieces (see _pieces)
var _falls: Array = []       # trees on their way down
var _stumps: Array = []
var _fresh: StandardMaterial3D
var _rings: StandardMaterial3D
var _meshes := {}            # radius in cm -> ArrayMesh
var _bark: StandardMaterial3D
var _end: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _chip_quad: QuadMesh
var _photo_quad: QuadMesh
var _chip_mats := {}         # colour -> material
var _chip_flows := {}        # box and life -> process material

const CHIP := Color(0.82, 0.66, 0.42)
const NEEDLE := Color(0.16, 0.3, 0.14)


func _ready() -> void:
	_flora = get_node_or_null(flora_path) as Flora
	_explorer = get_node_or_null(explorer_path)
	_inventory = get_node_or_null(inventory_path)
	_rng.randomize()
	_bark = StandardMaterial3D.new()
	_bark.albedo_texture = load("res://assets/fir/textures/pine_bark_basecolor.jpg")
	_bark.normal_enabled = true
	_bark.normal_texture = load("res://assets/fir/textures/pine_bark_normal.jpg")
	_bark.normal_scale = 1.6
	_bark.orm_texture = load("res://assets/fir/textures/pine_bark_orm.jpg")
	_bark.roughness = 1.0
	_bark.metallic_specular = 0.2
	_end = StandardMaterial3D.new()
	_end.albedo_texture = load("res://assets/log/log_end.jpg")
	_end.roughness = 0.85
	for g in GIRTHS:
		_log_mesh(g)
	_fresh = StandardMaterial3D.new()
	_fresh.albedo_color = Color(1.0, 0.94, 0.84)
	_fresh.albedo_texture = load("res://assets/log/log_end.jpg")
	_fresh.roughness = 0.82
	_fresh.vertex_color_use_as_albedo = true
	# The level face of a cut: the sawn end's own rings.
	_rings = StandardMaterial3D.new()
	_rings.albedo_texture = load("res://assets/log/log_end.jpg")
	_rings.albedo_color = Color(1.0, 0.94, 0.84)
	_rings.roughness = 0.85
	_rings.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fresh.cull_mode = BaseMaterial3D.CULL_DISABLED
	_chip_quad = QuadMesh.new()
	_chip_quad.size = Vector2(0.07, 0.035)
	_photo_quad = QuadMesh.new()
	_photo_quad.size = Vector2(0.15, 0.15)
	add_to_group(Prewarm.GROUP)
	call_deferred(&"_saw_all")


## Every kind of tree sawn into its pieces while the loading screen is up, not
## at the first swing at one.
func _saw_all() -> void:
	if _flora != null:
		for kind in Flora.FIRS.size():
			_pieces(kind)


## FIRST TIMES (SCRIPT_prewarm.gd): a log, a burst of chips and of needles, and
## every kind of tree as it stands once it has been cut into: stump, crown, the
## notched band with its fresh wood and its rings.
func warm(stage: Node3D) -> void:
	var at := stage.global_position
	var across := stage.global_basis.x
	var before := get_child_count()
	var body := _log_body(0.2)
	add_child(body)
	body.global_position = at
	_chips(at, 4, CHIP)
	_chips(at, 4, NEEDLE)
	if _flora != null:
		for kind in Flora.FIRS.size():
			var sawn := _pieces(kind)
			var root := Node3D.new()
			add_child(root)
			root.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.12),
					at + across * (float(kind) - Flora.FIRS.size() * 0.5) * 0.4 - Vector3.UP * 0.3)
			var halves := _carved(sawn, Vector3(1, 0, 0), float(sawn["girth"]) * 0.7, (BAND_HIGH - BAND_LOW) * 0.6)
			for mesh in [sawn["stump"], sawn["top"], halves[0], halves[1]]:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				root.add_child(mi)
	Prewarm.gather(self, before, stage)


## How many swings a tree of this girth takes.
static func bites_for(radius: float) -> int:
	return clampi(int(round(radius * 9.0)) + 1, 3, 8)


## A swing from `from` along `dir`. True if it met a tree. The first bite takes
## the tree out of the wood and stands it up as three pieces of its own (stump,
## the band the axe works in, and everything above); each bite after that deepens
## the wedge cut into the band; the last sends everything above the cut over.
func strike(from: Vector3, dir: Vector3, outright := false) -> bool:
	if _flora == null:
		return false
	var cut := _cut_on(from, dir)
	if cut.is_empty():
		var tree := _flora.tree_on(from, dir, reach)
		if tree.is_empty():
			return false
		cut = _begin(tree)
		# The notch opens on the side the first swing came from, and stays there.
		var root: Node3D = cut["root"]
		var toward := root.global_basis.inverse() * Vector3(from.x - root.global_position.x, 0.0, from.z - root.global_position.z)
		toward.y = 0.0
		cut["toward"] = toward.normalized() if toward.length() > 0.001 else Vector3(1, 0, 0)
	cut["taken"] = int(cut["needed"]) if outright else int(cut["taken"]) + 1
	_carve(cut)
	var root2: Node3D = cut["root"]
	var mouth: Vector3 = root2.to_global((cut["centre"] as Vector3) + (cut["toward"] as Vector3) * float(cut["girth"]))
	_chips(mouth, 20, CHIP)
	if int(cut["taken"]) >= int(cut["needed"]):
		_fall(cut)
	return true


## Where a crescent burst: the tree there, if there is one, is cut through at a
## stroke and falls the way the crescent was going.
func blast(at: Vector3, heading := Vector3.ZERO) -> void:
	if _flora == null:
		return
	var away := Vector3(heading.x, 0.0, heading.z)
	var cut := _cut_on(at, Vector3.ZERO, 0.0, 1.1)
	if cut.is_empty():
		var tree := _flora.tree_on(at, Vector3.ZERO, 0.0, 1.1)
		if tree.is_empty():
			return
		if away.length() < 0.01 and _explorer != null:
			away = (tree["origin"] as Vector3) - _explorer.global_position
			away.y = 0.0
		_topple(tree, away.normalized() if away.length() > 0.01 else Vector3.FORWARD)
		return
	cut["taken"] = cut["needed"]
	_carve(cut)
	_fall(cut)


## A tree straight over, whole: taken out of the wood, cut right through on the
## side away from `away`, and falling that way.
func _topple(tree: Dictionary, away: Vector3) -> void:
	var cut := _begin(tree)
	var root: Node3D = cut["root"]
	var toward := root.global_basis.inverse() * -away
	toward.y = 0.0
	cut["toward"] = toward.normalized() if toward.length() > 0.001 else Vector3(1, 0, 0)
	cut["taken"] = cut["needed"]
	_carve(cut)
	_fall(cut)


# ------------------------------------------------------------------ the pieces

## A kind of tree, sawn up once and kept: the stump (everything below the band
## the axe works in), the top (everything above it), and the band itself as the
## trunk's own bark in two halves, below and above the middle of the cut, which
## is what the notch is carved out of bite by bite (`_carved`).
func _pieces(kind: int) -> Dictionary:
	if _sawn.has(kind):
		return _sawn[kind]
	var mesh := _flora.tree_mesh(kind) as ArrayMesh
	var mid_y := (BAND_LOW + BAND_HIGH) * 0.5
	var out := {"stump": ArrayMesh.new(), "top": ArrayMesh.new(), "bark": null, "format": 0,
		"low": [], "high": [], "centre": Vector3(0, mid_y, 0), "girth": 0.2}
	if mesh != null:
		out["bark"] = mesh.surface_get_material(0)
		out["format"] = mesh.surface_get_format(0)
		var unused := PackedVector3Array()
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var format := mesh.surface_get_format(surface)
			var below := _saw(arrays, Plane(Vector3.DOWN, Vector3(0, BAND_LOW, 0)), unused)
			var above := _saw(arrays, Plane(Vector3.UP, Vector3(0, BAND_HIGH, 0)), unused)
			for piece in [["stump", below], ["top", above]]:
				if not (piece[1] as Array).is_empty():
					var into: ArrayMesh = out[piece[0]]
					into.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, piece[1], [], {}, format)
					into.surface_set_material(into.get_surface_count() - 1, mesh.surface_get_material(surface))
			# The band between the two levels.
			var band := _saw(arrays, Plane(Vector3.UP, Vector3(0, BAND_LOW, 0)), unused)
			if band.is_empty():
				continue
			band = _saw(band, Plane(Vector3.DOWN, Vector3(0, BAND_HIGH, 0)), unused)
			if band.is_empty():
				continue
			if surface != 0:
				# Needles hanging in the band are not cut either (they used to be left
				# out altogether, and a low bough lost a slice out of its middle): they
				# stay whole, with the tree above.
				var crown: ArrayMesh = out["top"]
				crown.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, band, [], {}, format)
				crown.surface_set_material(crown.get_surface_count() - 1, mesh.surface_get_material(surface))
				continue
			# The trunk at the middle of the cut: the crossings nearest the axis (a
			# low branch crosses the level too, far out), their middle, and how far
			# out the bark stands from it at most.
			var ring := PackedVector3Array()
			_saw(band, Plane(Vector3.DOWN, Vector3(0, mid_y, 0)), ring)
			var mid := Vector3.ZERO
			var girth := 0.03
			if ring.size() >= 3:
				var dists: Array = []
				for q in ring:
					dists.append(Vector2(q.x, q.z).length())
				dists.sort()
				var near := float(dists[dists.size() / 4]) * 1.8 + 0.02
				var count := 0
				for q in ring:
					if Vector2(q.x, q.z).length() <= near:
						mid += q
						count += 1
				mid /= float(maxi(count, 1))
				for q in ring:
					if Vector2(q.x, q.z).length() <= near:
						girth = maxf(girth, Vector2(q.x - mid.x, q.z - mid.z).length())
				out["centre"] = Vector3(mid.x, mid_y, mid.z)
				out["girth"] = girth
			# ONLY THE TRUNK IS CUT INTO. A short tree has boughs as low as the axe
			# works, and they are bark too: carved with the trunk, a bough was sliced
			# open in mid air with rings on its end. What of the band is not trunk (any
			# triangle with a corner further from the trunk's middle than its bark
			# stands) is left whole and goes with the tree above, to fall with it.
			var parts := _trunk_and_boughs(band, Vector2(mid.x, mid.z), girth * 1.3 + 0.03)
			if not (parts[1] as Array).is_empty():
				var top: ArrayMesh = out["top"]
				top.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, parts[1], [], {}, format)
				top.surface_set_material(top.get_surface_count() - 1, mesh.surface_get_material(surface))
			var trunk: Array = parts[0]
			if not trunk.is_empty():
				out["low"] = _saw(trunk, Plane(Vector3.DOWN, Vector3(0, mid_y, 0)), unused)
				out["high"] = _saw(trunk, Plane(Vector3.UP, Vector3(0, mid_y, 0)), unused)
	_sawn[kind] = out
	return out


## A surface's arrays as two: the triangles all of whose corners are within
## `reach` of the upright line through `axis` (the trunk), and the rest (boughs).
## The corners are shared; only the lists of triangles differ. Either may be [].
func _trunk_and_boughs(arrays: Array, axis: Vector2, reach: float) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var near := PackedInt32Array()
	var far := PackedInt32Array()
	for t in range(0, index.size(), 3):
		var inside := true
		for k in 3:
			var p := verts[index[t + k]]
			if Vector2(p.x, p.z).distance_to(axis) > reach:
				inside = false
		for k in 3:
			if inside:
				near.append(index[t + k])
			else:
				far.append(index[t + k])
	var out: Array = []
	for list in [near, far]:
		if (list as PackedInt32Array).is_empty():
			out.append([])
			continue
		var part := arrays.duplicate()
		part[Mesh.ARRAY_INDEX] = list
		out.append(part)
	return out


## One surface's arrays cut by `plane`, keeping what is on its positive side.
## Triangles wholly on that side keep their vertices; a triangle the plane
## crosses is cut, with new vertices (every attribute carried across) where its
## edges meet the plane. `crossings` collects those points.
func _saw(arrays: Array, plane: Plane, crossings: PackedVector3Array) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(v.size())
		for i in v.size():
			idx[i] = i
	var out := arrays.duplicate(true)
	var ov: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	var on: PackedVector3Array = out[Mesh.ARRAY_NORMAL] if out[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var ot: PackedFloat32Array = out[Mesh.ARRAY_TANGENT] if out[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var oc: PackedColorArray = out[Mesh.ARRAY_COLOR] if out[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var ou: PackedVector2Array = out[Mesh.ARRAY_TEX_UV] if out[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var ou2: PackedVector2Array = out[Mesh.ARRAY_TEX_UV2] if out[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var side := PackedFloat32Array()
	side.resize(v.size())
	for i in v.size():
		side[i] = plane.distance_to(v[i])
	var keep := PackedInt32Array()
	for tri in range(0, idx.size(), 3):
		var ids := [idx[tri], idx[tri + 1], idx[tri + 2]]
		var d := [side[ids[0]], side[ids[1]], side[ids[2]]]
		if d[0] >= 0.0 and d[1] >= 0.0 and d[2] >= 0.0:
			keep.append_array(PackedInt32Array(ids))
			continue
		if d[0] < 0.0 and d[1] < 0.0 and d[2] < 0.0:
			continue
		# Round the triangle, keeping the corners on the right side and adding a
		# corner wherever an edge goes through the plane.
		var poly: Array = []
		for e in 3:
			var i: int = ids[e]
			var j: int = ids[(e + 1) % 3]
			var di: float = d[e]
			var dj: float = d[(e + 1) % 3]
			if di >= 0.0:
				poly.append(i)
			if (di >= 0.0) != (dj >= 0.0):
				var t := di / (di - dj)
				ov.append(ov[i].lerp(ov[j], t))
				crossings.append(ov[ov.size() - 1])
				if not on.is_empty():
					on.append(on[i].lerp(on[j], t).normalized())
				if not ot.is_empty():
					for k in 3:
						ot.append(lerpf(ot[i * 4 + k], ot[j * 4 + k], t))
					ot.append(ot[i * 4 + 3])
				if not oc.is_empty():
					oc.append(oc[i].lerp(oc[j], t))
				if not ou.is_empty():
					ou.append(ou[i].lerp(ou[j], t))
				if not ou2.is_empty():
					ou2.append(ou2[i].lerp(ou2[j], t))
				poly.append(ov.size() - 1)
		for k in range(1, poly.size() - 1):
			keep.append_array(PackedInt32Array([poly[0], poly[k], poly[k + 1]]))
	if keep.is_empty():
		return []
	out[Mesh.ARRAY_VERTEX] = ov
	if not on.is_empty():
		out[Mesh.ARRAY_NORMAL] = on
	if not ot.is_empty():
		out[Mesh.ARRAY_TANGENT] = ot
	if not oc.is_empty():
		out[Mesh.ARRAY_COLOR] = oc
	if not ou.is_empty():
		out[Mesh.ARRAY_TEX_UV] = ou
	if not ou2.is_empty():
		out[Mesh.ARRAY_TEX_UV2] = ou2
	out[Mesh.ARRAY_INDEX] = keep
	return out


## A flat face of fresh wood closing a cut: the points where a plane went through
## the trunk, put in order round their middle and filled, facing `normal`.
## `rings` (the trunk's middle and its girth) lays the sawn end's growth rings on
## it; `deep` (a point on the wedge's inner line, the way out of it, its depth)
## darkens it toward that line, as the bottom of a notch is darker than its lip.
func _face(st: SurfaceTool, points: PackedVector3Array, normal: Vector3, rings := [], deep := []) -> void:
	if points.size() < 3:
		return
	var mid := Vector3.ZERO
	for q in points:
		mid += q
	mid /= float(points.size())
	var u := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := normal.cross(u)
	var ordered: Array = []
	for q in points:
		ordered.append([atan2((q - mid).dot(w), (q - mid).dot(u)), q])
	ordered.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in ordered.size():
		var pa: Vector3 = ordered[i][1]
		var pb: Vector3 = ordered[(i + 1) % ordered.size()][1]
		var tri: Array = [mid, pa, pb]
		# (Godot's front is clockwise: turn the triangle to face the way it is lit.)
		if (pb - mid).cross(pa - mid).dot(normal) < 0.0:
			tri = [mid, pb, pa]
		for q in tri:
			var at: Vector3 = q
			var shade := 1.0
			if not deep.is_empty():
				shade = lerpf(0.42, 1.0, clampf((at - (deep[0] as Vector3)).dot(deep[1]) / maxf(float(deep[2]), 0.001), 0.0, 1.0))
			st.set_color(Color(shade, shade, shade))
			st.set_normal(normal)
			if rings.is_empty():
				st.set_uv(Vector2(at.dot(u), at.dot(w)) * 1.2)
			else:
				var from_mid := at - (rings[0] as Vector3)
				st.set_uv(Vector2(0.5, 0.5) + Vector2(from_mid.x, from_mid.z) / (float(rings[1]) * 2.1))
			st.add_vertex(at)


## THE NOTCH, CUT OUT OF THE TRUNK ITSELF. The band's two halves of bark are each
## sawn again by one face of the wedge: two flat cuts going in from the bark on
## the side `toward`, meeting in a line `depth` into the trunk, the mouth `gape`
## tall. What each cut exposes is closed with fresh wood, and so is the level
## face each half shows the other, which is what is seen when they part.
## Returns [lower half, upper half] as meshes.
func _carved(sawn: Dictionary, toward: Vector3, depth: float, gape: float) -> Array:
	var centre: Vector3 = sawn["centre"]
	var girth := float(sawn["girth"])
	var edge := centre + toward * (girth - depth)          # the line the two faces meet in
	var halves: Array = []
	for half in 2:
		var mesh := ArrayMesh.new()
		var arrays: Array = sawn["high" if half == 1 else "low"]
		var up := Vector3.UP if half == 1 else Vector3.DOWN
		# This half's face of the wedge; what is kept lies behind and beyond it.
		var keep := (-toward * gape * 0.5 + up * maxf(depth, 0.0001)).normalized()
		var cut_points := PackedVector3Array()
		var bark: Array = [] if arrays.is_empty() else _saw(arrays, Plane(keep, edge), cut_points)
		if not bark.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bark, [], {}, int(sawn["format"]))
			mesh.surface_set_material(0, sawn["bark"])
		var wood := SurfaceTool.new()
		wood.begin(Mesh.PRIMITIVE_TRIANGLES)
		if depth > 0.001:
			# The same rings as the level face, laid from the trunk's middle straight
			# down through the cut, so they run on from one face into the other.
			_face(wood, cut_points, -keep, [centre, girth], [edge, toward, depth])
			wood.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _fresh)
		var end := SurfaceTool.new()
		end.begin(Mesh.PRIMITIVE_TRIANGLES)
		# The level face at the middle of the cut: the rim of what bark is left
		# there, and the ends of the line the wedge reached.
		var level := PackedVector3Array()
		if not bark.is_empty():
			var seen := {}
			var bv: PackedVector3Array = bark[Mesh.ARRAY_VERTEX]
			for i in (bark[Mesh.ARRAY_INDEX] as PackedInt32Array):
				if not seen.has(i) and absf(bv[i].y - centre.y) < 0.0008:
					seen[i] = true
					level.append(bv[i])
		if level.size() >= 3:
			_face(end, level, -up, [centre, girth])
			end.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _rings)
		halves.append(mesh)
	return halves


## Take a tree out of the wood and stand it up as its own pieces, uncut so far.
func _begin(tree: Dictionary) -> Dictionary:
	var sawn := _pieces(int(tree["kind"]))
	_flora.fell(tree)
	var origin: Vector3 = tree["origin"]
	var size := float(tree["size"])
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D((tree["basis"] as Basis).scaled(Vector3.ONE * size), origin)
	var stump := MeshInstance3D.new()
	stump.mesh = sawn["stump"]
	root.add_child(stump)
	var top := MeshInstance3D.new()
	top.mesh = sawn["top"]
	top.extra_cull_margin = float(tree["height"])
	root.add_child(top)
	var low := MeshInstance3D.new()
	var high := MeshInstance3D.new()
	root.add_child(low)
	root.add_child(high)
	# Something to walk into: the trunk while it stands, the stump once it is down.
	var body := StaticBody3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = float(tree["radius"]) / size
	shape.height = 8.0 / size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 4.0 / size, 0)
	body.add_child(cs)
	root.add_child(body)
	var cut := {"root": root, "top": top, "low": low, "high": high, "shape": cs, "sawn": sawn,
		"toward": Vector3(1, 0, 0), "taken": 0, "needed": bites_for(float(tree["radius"])),
		"centre": sawn["centre"], "girth": float(sawn["girth"]),
		"radius": float(tree["radius"]), "height": float(tree["height"]), "origin": origin}
	_carve(cut)
	_cuts.append(cut)
	return cut


## The band as deep as the bites taken so far have made it.
func _carve(cut: Dictionary) -> void:
	var share := clampf(float(cut["taken"]) / float(maxi(int(cut["needed"]), 1)), 0.0, 1.0)
	var halves := _carved(cut["sawn"], cut["toward"], float(cut["girth"]) * 2.0 * 0.74 * share,
			(BAND_HIGH - BAND_LOW) * lerpf(0.45, 0.92, share))
	(cut["low"] as MeshInstance3D).mesh = halves[0]
	(cut["high"] as MeshInstance3D).mesh = halves[1]


## A tree already being cut that a reach from `from` along `dir` meets, or {}.
func _cut_on(from: Vector3, dir: Vector3, far := -1.0, slack := 0.35) -> Dictionary:
	var a := Vector2(from.x, from.z)
	var d := Vector2(dir.x, dir.z)
	d = d.normalized() if d.length() > 0.001 else Vector2.ZERO
	var span := reach if far < 0.0 else far
	for cut in _cuts:
		var origin: Vector3 = cut["origin"]
		var p := Vector2(origin.x, origin.z)
		var t := clampf((p - a).dot(d), 0.0, span)
		if (a + d * t).distance_to(p) <= float(cut["radius"]) + slack \
				and from.y > origin.y - 1.0 and from.y < origin.y + float(cut["height"]):
			return cut
	return {}


# ------------------------------------------------------------------ the fall

## Cut through: everything above the middle of the cut hinges on the last of the
## wood at the back of the notch and goes over away from it, slowly at first and
## then fast, the way a real one goes. The stump and the lower half of the cut
## stay where they are.
func _fall(cut: Dictionary) -> void:
	_cuts.erase(cut)
	var root: Node3D = cut["root"]
	var toward: Vector3 = cut["toward"]
	var hinge := Node3D.new()
	root.add_child(hinge)
	hinge.position = (cut["centre"] as Vector3) - toward * float(cut["girth"]) * 0.8
	for part in [cut["top"], cut["high"]]:
		(part as Node3D).reparent(hinge, true)
	# The trunk's collider shrinks to the stump's.
	var cs: CollisionShape3D = cut["shape"]
	var mid_y := (BAND_LOW + BAND_HIGH) * 0.5
	(cs.shape as CylinderShape3D).height = mid_y
	cs.position = Vector3(0, mid_y * 0.5, 0)
	var height := float(cut["height"])
	# A tall tree is a long pendulum and goes over slowly; a sapling snaps down.
	var pull := clampf(3.0 * 9.8 / (2.0 * height) * 1.7, 0.55, 3.2)
	_falls.append({"hinge": hinge, "axis": Vector3.UP.cross(-toward).normalized(), "angle": 0.04, "speed": 0.2, "pull": pull,
		"away": (root.global_basis * -toward).normalized(), "radius": float(cut["radius"]), "height": height})
	_stumps.append(root)
	while _stumps.size() > 240:
		(_stumps.pop_front() as Node).queue_free()


func _fall_step(delta: float) -> void:
	for i in range(_falls.size() - 1, -1, -1):
		var f: Dictionary = _falls[i]
		var hinge: Node3D = f["hinge"]
		if not is_instance_valid(hinge):
			_falls.remove_at(i)
			continue
		f["speed"] = float(f["speed"]) + float(f["pull"]) * sin(float(f["angle"])) * delta
		f["angle"] = float(f["angle"]) + float(f["speed"]) * delta
		if float(f["angle"]) < DOWN:
			hinge.basis = Basis(f["axis"], float(f["angle"]))
			continue
		_falls.remove_at(i)
		_crash(f)
		hinge.queue_free()


## It hits the ground: the trunk breaks into its lengths where it lies, laid end
## to end along the fall, and the crown comes apart.
func _crash(f: Dictionary) -> void:
	var hinge: Node3D = f["hinge"]
	var away: Vector3 = f["away"]
	var radius := float(f["radius"])
	var height := float(f["height"])
	var foot := hinge.global_position
	foot.y -= 0.5
	# The trunk below the crown, sawn into lengths; the thin top is lost in the fall.
	var trunk := height * 0.62
	var count := clampi(int(round(trunk / 1.7)), 3, 10)
	var along := Basis(away.cross(Vector3.UP).normalized(), away, Vector3.UP)    # a log's length lies on Y
	for i in count:
		var t := float(i) / float(count)
		var r := maxf(radius * 1.25 * (1.0 - 0.65 * t), 0.1)
		var body := _log_body(r)
		add_child(body)
		var at := foot + away * (0.9 + (float(i) + 0.5) * trunk / float(count))
		at.y = _ground(at, foot.y) + r + 0.35
		body.global_transform = Transform3D(along * Basis(Vector3.UP, _rng.randf() * TAU), at)
		var side := away.cross(Vector3.UP) * _rng.randf_range(-1.0, 1.0)
		body.linear_velocity = side * _rng.randf_range(0.4, 1.8) + Vector3.UP * _rng.randf_range(1.0, 3.0)
		body.angular_velocity = Vector3(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-2.0, 2.0))
		_logs.append([body, 0.0])
	while _logs.size() > max_logs:
		(_logs.pop_front()[0] as Node).queue_free()
	_chips(foot + away * trunk * 0.5 + Vector3.UP * 0.5, 70, CHIP, Vector3(trunk * 0.3, 0.3, trunk * 0.3))
	# The crown, where it came down: needles thrown up along the top of the tree.
	_chips(foot + away * height * 0.68 + Vector3.UP * 1.0, 160, NEEDLE,
			Vector3(height * 0.2 + radius * 4.0, 1.2, height * 0.2 + radius * 4.0), 2.6)


## The ground under a point, by a ray down through it (the terrain has collision
## round the player), or `fallback` where nothing is hit.
func _ground(at: Vector3, fallback: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return fallback
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at - Vector3.UP * 60.0)
	var skip: Array[RID] = []
	for entry in _logs:
		skip.append((entry[0] as RigidBody3D).get_rid())
	q.exclude = skip
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else fallback


func _log_body(radius: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = maxf(8.0, 600.0 * radius * radius * LOG_LENGTH)
	body.angular_damp = 1.2
	body.linear_damp = 0.15
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = LOG_LENGTH
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# One of three meshes made at start-up, pulled to this girth: building a mesh
	# per log is what a felling used to stall on.
	var base: float = GIRTHS[0]
	for g in GIRTHS:
		if absf(g - radius) < absf(base - radius):
			base = g
	var mi := MeshInstance3D.new()
	mi.mesh = _log_mesh(base)
	mi.scale = Vector3(radius / base, 1.0, radius / base)
	body.add_child(mi)
	return body


## A log standing on Y: the bark wrapped round it (tiled to its girth so it is
## never stretched), the sawn end on each cap.
func _log_mesh(radius: float) -> ArrayMesh:
	var cm := int(round(radius * 100.0))
	if _meshes.has(cm):
		return _meshes[cm]
	var r := maxf(float(cm) / 100.0, 0.04)
	var half := LOG_LENGTH * 0.5
	var sides := 16 if r < 0.2 else 28
	var wraps := maxf(1.0, round(TAU * r / 1.3))
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sides:
		var quad: Array = []
		for step in [[i, -1.0], [i + 1, -1.0], [i + 1, 1.0], [i, 1.0]]:
			var a := TAU * float(step[0]) / float(sides)
			var n := Vector3(cos(a), 0.0, sin(a))
			quad.append([n * r + Vector3.UP * half * float(step[1]), n,
					Vector2(float(step[0]) / float(sides) * wraps, (1.0 - float(step[1])) * 0.5 * LOG_LENGTH / 1.3)])
		for j in [0, 1, 2, 0, 2, 3]:
			st.set_normal(quad[j][1])
			st.set_uv(quad[j][2])
			st.add_vertex(quad[j][0])
	st.generate_tangents()
	st.set_material(_bark)
	st.commit(mesh)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		var n := Vector3.UP * float(side)
		for i in sides:
			var ring: Array = [Vector3.ZERO]
			for s2 in [i, i + 1]:
				var a := TAU * float(s2) / float(sides)
				ring.append(Vector3(cos(a), 0.0, sin(a)))
			var order: Array = [0, 1, 2] if side > 0.0 else [0, 2, 1]
			for j in order:
				var v: Vector3 = ring[j]
				st.set_normal(n)
				st.set_uv(Vector2(0.5 + v.x * 0.5, 0.5 + v.z * 0.5))
				st.add_vertex(v * r + n * half)
	st.set_material(_end)
	st.commit(mesh)
	_meshes[cm] = mesh
	return mesh


## A one-shot burst of flat bits: chips at a bite, needles when the crown goes.
func _chips(at: Vector3, amount: int, color: Color, spread := Vector3(0.1, 0.1, 0.1), life := 1.1) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The materials are kept: a new one each burst is a new shader to set up.
	var flow_key := [spread, life]
	var m: ParticleProcessMaterial = _chip_flows.get(flow_key)
	if m == null:
		m = ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = spread
		m.direction = Vector3.UP
		m.spread = 180.0
		m.initial_velocity_min = 1.0
		m.initial_velocity_max = 4.2
		m.gravity = Vector3(0, -9.0, 0)
		m.angle_min = 0.0
		m.angle_max = 360.0
		m.angular_velocity_min = -400.0
		m.angular_velocity_max = 400.0
		m.scale_min = 0.5
		m.scale_max = 1.5
		# Each particle keeps one picture out of the chip atlas, picked at random.
		m.anim_offset_min = 0.0
		m.anim_offset_max = 1.0
		m.anim_speed_min = 0.0
		m.anim_speed_max = 0.0
		if _chip_flows.size() > 24:
			_chip_flows.clear()
		_chip_flows[flow_key] = m
	p.process_material = m
	var mat: StandardMaterial3D = _chip_mats.get(color)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		if color == CHIP:
			# WOOD CHIPS: sixteen photographs of splinters, shavings and chunks
			# (assets/chips, cut from one sheet by tools/build_chip_atlas.py), one to
			# a particle, tumbling as they fly.
			mat.albedo_texture = load("res://assets/chips/chips_atlas.png")
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.45
			mat.particles_anim_h_frames = 4
			mat.particles_anim_v_frames = 4
			mat.particles_anim_loop = false
			mat.roughness = 0.85
		else:
			mat.albedo_color = color
		_chip_mats[color] = mat
	p.draw_pass_1 = _photo_quad if color == CHIP else _chip_quad
	p.material_override = mat
	p.visibility_aabb = AABB(-spread - Vector3.ONE * 12.0, spread * 2.0 + Vector3.ONE * 24.0)
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)


## Logs that have had a moment to fall are gathered by walking up to them.
func _process(delta: float) -> void:
	_fall_step(delta)
	if _logs.is_empty() or _explorer == null:
		return
	var here := _explorer.global_position + Vector3(0, 0.9, 0)
	for i in range(_logs.size() - 1, -1, -1):
		var entry: Array = _logs[i]
		var body: RigidBody3D = entry[0]
		entry[1] = float(entry[1]) + delta
		if float(entry[1]) < 0.9 or body.global_position.distance_to(here) > gather_radius:
			continue
		if _inventory == null or int(_inventory.call(&"add", "log", 1)) > 0:
			continue          # nowhere to put it
		_logs.remove_at(i)
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
		var pull := create_tween()
		pull.tween_property(body, "global_position", here, 0.16)
		pull.parallel().tween_property(body, "scale", Vector3.ONE * 0.15, 0.16)
		pull.tween_callback(body.queue_free)
