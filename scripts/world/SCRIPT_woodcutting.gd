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
var _meshes := {}            # radius in cm -> ArrayMesh
var _bark: StandardMaterial3D
var _end: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _chip_quad: QuadMesh
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
	_fresh.albedo_color = Color(0.93, 0.8, 0.58)
	_fresh.albedo_texture = load("res://assets/log/log_end.jpg")
	_fresh.roughness = 0.75
	_fresh.cull_mode = BaseMaterial3D.CULL_DISABLED
	_chip_quad = QuadMesh.new()
	_chip_quad.size = Vector2(0.07, 0.035)
	call_deferred(&"_warm_up")


## A log and a burst of each colour, once, out of sight under the island while
## the loading screen is up: the first tree felled then has nothing to compile.
func _warm_up() -> void:
	var body := _log_body(0.2)
	body.freeze = true
	add_child(body)
	body.global_position = Vector3(0, -900, 0)
	get_tree().create_timer(2.0).timeout.connect(body.queue_free)
	_chips(Vector3(0, -900, 0), 4, CHIP)
	_chips(Vector3(0, -900, 0), 4, NEEDLE)
	# Every kind of tree sawn into its pieces now, not at the first swing at one.
	if _flora != null:
		for kind in Flora.FIRS.size():
			_pieces(kind)


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
	_chips(mouth, 30, CHIP)
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

## A kind of tree, sawn in three once and kept: the stump (everything below the
## band the axe works in), the top (everything above it), and where the trunk's
## middle is and how thick it is at the band's two edges. The band between is
## not part of the model: it is made here, bite by bite (`_band`).
func _pieces(kind: int) -> Dictionary:
	if _sawn.has(kind):
		return _sawn[kind]
	var mesh := _flora.tree_mesh(kind) as ArrayMesh
	var out := {"stump": ArrayMesh.new(), "top": ArrayMesh.new(), "bark": null,
		"c0": Vector3(0, BAND_LOW, 0), "c1": Vector3(0, BAND_HIGH, 0), "r0": 0.2, "r1": 0.2}
	if mesh != null:
		out["bark"] = mesh.surface_get_material(0)
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var format := mesh.surface_get_format(surface)
			for side in 2:
				var crossings := PackedVector3Array()
				var kept := _saw(arrays, BAND_HIGH if side == 1 else BAND_LOW, side == 1, crossings)
				if not kept.is_empty():
					var into: ArrayMesh = out["top" if side == 1 else "stump"]
					into.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, kept, [], {}, format)
					into.surface_set_material(into.get_surface_count() - 1, mesh.surface_get_material(surface))
				if surface == 0 and crossings.size() >= 3:
					# The trunk where the saw went through: the cluster of crossings
					# nearest the middle (a low branch crosses the plane too, far out).
					var dists: Array = []
					for q in crossings:
						dists.append(Vector2(q.x, q.z).length())
					dists.sort()
					var near := float(dists[dists.size() / 4]) * 1.8 + 0.02
					var mid := Vector3.ZERO
					var count := 0
					for q in crossings:
						if Vector2(q.x, q.z).length() <= near:
							mid += q
							count += 1
					mid /= float(maxi(count, 1))
					var r := 0.0
					for q in crossings:
						if Vector2(q.x, q.z).length() <= near:
							r += Vector2(q.x - mid.x, q.z - mid.z).length()
					out["c1" if side == 1 else "c0"] = mid
					out["r1" if side == 1 else "r0"] = maxf(r / float(maxi(count, 1)), 0.03)
	_sawn[kind] = out
	return out


## One surface's arrays cut by the level plane y = `at`, keeping what is above it
## (or below). Triangles wholly on the kept side keep their vertices; a triangle
## the plane crosses is cut, with new vertices (every attribute carried across)
## where its edges meet the plane. `crossings` collects those points.
func _saw(arrays: Array, at: float, above: bool, crossings: PackedVector3Array) -> Array:
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
	var sign := 1.0 if above else -1.0
	var keep := PackedInt32Array()
	for tri in range(0, idx.size(), 3):
		var ids := [idx[tri], idx[tri + 1], idx[tri + 2]]
		var d := [(v[ids[0]].y - at) * sign, (v[ids[1]].y - at) * sign, (v[ids[2]].y - at) * sign]
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


## THE BAND THE AXE WORKS IN: the half metre of trunk between the stump and the
## top, as two rings (below and above the middle of the cut) that meet at it.
## The notch is cut out of them as an axe cuts it: two flat faces going in from
## the bark on the side `toward`, meeting in a line `depth` into the trunk, the
## mouth `gape` tall. Bark is bark; what the axe has opened is fresh wood, and so
## is the face each half shows the other, which is what is seen when they part.
## Returns [lower half, upper half].
func _band(sawn: Dictionary, toward: Vector3, depth: float, gape: float) -> Array:
	var c0: Vector3 = sawn["c0"]
	var c1: Vector3 = sawn["c1"]
	var r0 := float(sawn["r0"])
	var r1 := float(sawn["r1"])
	var mid_y := (BAND_LOW + BAND_HIGH) * 0.5
	var sides := 28
	var halves: Array = []
	for half in 2:
		var rows: Array = []        # each a ring of [point, cut?]
		for step in 5:
			var y := lerpf(BAND_LOW, mid_y, float(step) / 4.0) if half == 0 else lerpf(mid_y, BAND_HIGH, float(step) / 4.0)
			var f := inverse_lerp(BAND_LOW, BAND_HIGH, y)
			var centre := c0.lerp(c1, f)
			centre.y = y
			var r := lerpf(r0, r1, f)
			# How far in from the bark the notch has reached at this height.
			var face := r - depth * maxf(0.0, 1.0 - absf(y - mid_y) / maxf(gape * 0.5, 0.001))
			var ring: Array = []
			for i in sides + 1:
				var a := TAU * float(i) / float(sides)
				var p := centre + Vector3(cos(a), 0.0, sin(a)) * r
				var out_by := (p - centre).dot(toward) - face
				var cut := out_by > 0.0005
				if cut:
					p -= toward * out_by
				ring.append([p, cut, Vector3(cos(a), 0.0, sin(a)), float(i) / float(sides)])
			rows.append(ring)
		var bark := SurfaceTool.new()
		bark.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wood := SurfaceTool.new()
		wood.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wraps := maxf(1.0, round(TAU * r0 / 1.3))
		var any_bark := false
		for row in 4:
			for i in sides:
				var quad: Array = [rows[row][i], rows[row][i + 1], rows[row + 1][i + 1], rows[row + 1][i]]
				var opened: bool = quad[0][1] or quad[1][1] or quad[2][1] or quad[3][1]
				for tri in [[0, 1, 2], [0, 2, 3]]:
					var pa: Vector3 = quad[tri[0]][0]
					var pb: Vector3 = quad[tri[1]][0]
					var pc: Vector3 = quad[tri[2]][0]
					if opened:
						var flat := (pc - pa).cross(pb - pa)
						if flat.length() < 1e-9:
							continue
						for k in tri:
							wood.set_normal(flat.normalized())
							wood.set_uv(Vector2((quad[k][0] as Vector3).x, (quad[k][0] as Vector3).z) * 1.5)
							wood.add_vertex(quad[k][0])
					else:
						any_bark = true
						for k in tri:
							bark.set_normal(quad[k][2])
							bark.set_uv(Vector2(float(quad[k][3]) * wraps, (quad[k][0] as Vector3).y / 1.3))
							bark.set_uv2(Vector2.ZERO)
							bark.add_vertex(quad[k][0])
		# The face at the middle of the cut: what is left of the trunk there.
		var face_ring: Array = rows[4] if half == 0 else rows[0]
		var hub := Vector3.ZERO
		for i in sides:
			hub += face_ring[i][0]
		hub /= float(sides)
		for i in sides:
			var tri: Array = [hub, face_ring[i][0], face_ring[i + 1][0]] if half == 0 else [hub, face_ring[i + 1][0], face_ring[i][0]]
			for q in tri:
				wood.set_normal(Vector3.UP if half == 0 else Vector3.DOWN)
				wood.set_uv(Vector2((q as Vector3).x, (q as Vector3).z) * 1.5)
				wood.add_vertex(q)
		var mesh := ArrayMesh.new()
		if any_bark:
			bark.generate_tangents()
			bark.commit(mesh)
			mesh.surface_set_material(0, sawn["bark"])
		wood.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _fresh)
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
	var mid_y := (BAND_LOW + BAND_HIGH) * 0.5
	var centre: Vector3 = (sawn["c0"] as Vector3).lerp(sawn["c1"], 0.5)
	centre.y = mid_y
	var cut := {"root": root, "top": top, "low": low, "high": high, "shape": cs, "sawn": sawn,
		"toward": Vector3(1, 0, 0), "taken": 0, "needed": bites_for(float(tree["radius"])),
		"centre": centre, "girth": (float(sawn["r0"]) + float(sawn["r1"])) * 0.5,
		"radius": float(tree["radius"]), "height": float(tree["height"]), "origin": origin}
	_carve(cut)
	_cuts.append(cut)
	return cut


## The band as deep as the bites taken so far have made it.
func _carve(cut: Dictionary) -> void:
	var share := clampf(float(cut["taken"]) / float(maxi(int(cut["needed"]), 1)), 0.0, 1.0)
	var halves := _band(cut["sawn"], cut["toward"], float(cut["girth"]) * 2.0 * 0.74 * share,
			(BAND_HIGH - BAND_LOW) * lerpf(0.5, 1.0, share))
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
		if _chip_flows.size() > 24:
			_chip_flows.clear()
		_chip_flows[flow_key] = m
	p.process_material = m
	var mat: StandardMaterial3D = _chip_mats.get(color)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_chip_mats[color] = mat
	p.draw_pass_1 = _chip_quad
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
