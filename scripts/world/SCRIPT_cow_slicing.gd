class_name CowSlicing
extends Node3D

# CUTTING COWS UP. A swing of the sword or the axe that lands on a cow cuts it
# in two along the line of the swing, clean through: two pieces of cow, each
# with a face of red meat where the blade went, that fall apart and tumble. A
# swing that lands on a piece cuts that in two the same way, and so on down,
# for as long as the pieces are big enough to hit. Time slows for a breath at
# every cut, so a run of them can be laid one after another across the same
# animal before any of it has reached the ground.
#
# THE BEEF COMES OUT OF THE CUTS: each one throws two or three cuts of raw beef
# clear, to lie in the grass and be walked up to (up to `beef_per_cow` from one
# animal, however fine it is cut). The chunks themselves are not for the bag:
# they lie a while and then go into the ground.
#
# HOW A CUT IS MADE. The cow's skin is a mesh; the cut is a plane (through where
# the swing landed, holding the line of sight and the line the blade travelled).
# Every triangle goes to the side of the plane it is on, and those the plane
# passes through are split along it; the points where it passed through the skin
# ring the cut, and a fan of triangles across that ring is the meat, with the
# hide's own edge showing round it: skin, then fat (SHADER_cut_meat). Each side
# becomes a body of its own, shaped by its own corners.

@export var herds_path: NodePath = ^"../CowHerds"
@export var explorer_path: NodePath = ^"../Explorer"
@export var inventory_path: NodePath = ^"../Inventory"
## How far a swing reaches, metres.
@export var reach := 3.4
## The most beef one cow gives.
@export var beef_per_cow := 12
## A piece smaller than this across cannot be cut again.
@export var smallest := 0.28
## How slow time runs at a cut, and for how long (real seconds).
@export var slow := 0.28
@export var slow_for := 0.4
@export var max_pieces := 70
## How many times over a cow struck by the blade's beam is cut (4: sixteen chunks).
@export var burst_cuts := 4
## Cuts of beef a single cut throws out (until the cow has given `beef_per_cow`).
@export var steaks_per_cut := Vector2i(2, 3)
## Seconds a chunk lies before it goes into the ground, and how long that takes.
@export var lie_for := 14.0
@export var sink_for := 3.5
@export var gather_radius := 1.5

var _herds: CowHerds
var _explorer: Node3D
var _bag: Node
var _pieces: Array = []       # each {"body", "skin": [verts, normals, uvs], "meat": [verts, normals, uvs], "age", "cow"}
var _meat: ShaderMaterial
var _steaks: Array = []       # each [body, seconds lain]
var _steak_quad: QuadMesh
var _steak_shape: SphereShape3D
var _given := {}              # cow number -> beef taken from it so far
var _cows := 0
var _slow_until := 0
var _rng := RandomNumberGenerator.new()
var _drop_mesh: SphereMesh
var _gib_mat: StandardMaterial3D
var _gib_quad: QuadMesh
var _gib_flow: ParticleProcessMaterial
var _drop_mat: StandardMaterial3D
var _drop_flow: ParticleProcessMaterial


func _ready() -> void:
	_herds = get_node_or_null(herds_path) as CowHerds
	_explorer = get_node_or_null(explorer_path)
	_bag = get_node_or_null(inventory_path)
	_rng.randomize()
	# Meat: red, marbled with fat, a little wet.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.045
	noise.seed = 4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(0.55, 0.06, 0.07), Color(0.72, 0.12, 0.12), Color(0.86, 0.36, 0.34), Color(0.96, 0.85, 0.78)])
	var marbled := NoiseTexture2D.new()
	marbled.noise = noise
	marbled.color_ramp = ramp
	marbled.width = 256
	marbled.height = 256
	marbled.seamless = true
	marbled.generate_mipmaps = true
	_meat = ShaderMaterial.new()
	_meat.shader = load("res://shaders/SHADER_cut_meat.gdshader")
	_meat.set_shader_parameter("marbling", marbled)
	# GIBS: sixteen photographs of torn meat (assets/chips/gib_atlas.png, cut from
	# one sheet by tools/build_chip_atlas.py), one to a particle, tumbling as they fly.
	_gib_mat = StandardMaterial3D.new()
	_gib_mat.albedo_texture = load("res://assets/chips/gib_atlas.png")
	_gib_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_gib_mat.alpha_scissor_threshold = 0.45
	_gib_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_gib_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_gib_mat.particles_anim_h_frames = 4
	_gib_mat.particles_anim_v_frames = 4
	_gib_mat.particles_anim_loop = false
	# Dull: no shine at all (a photograph of wet meat has its own highlights in it).
	_gib_mat.roughness = 1.0
	_gib_mat.metallic = 0.0
	_gib_mat.metallic_specular = 0.0
	_gib_quad = QuadMesh.new()
	_gib_quad.size = Vector2(0.2, 0.2)
	_gib_flow = ParticleProcessMaterial.new()
	_gib_flow.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_gib_flow.emission_sphere_radius = 0.25
	_gib_flow.direction = Vector3(0, 0, -1)
	_gib_flow.spread = 50.0
	_gib_flow.initial_velocity_min = 1.2
	_gib_flow.initial_velocity_max = 5.0
	_gib_flow.gravity = Vector3(0, -9.8, 0)
	_gib_flow.angle_max = 360.0
	_gib_flow.angular_velocity_min = -420.0
	_gib_flow.angular_velocity_max = 420.0
	_gib_flow.scale_min = 0.45
	_gib_flow.scale_max = 1.5
	_gib_flow.anim_offset_min = 0.0
	_gib_flow.anim_offset_max = 1.0
	_gib_flow.anim_speed_min = 0.0
	_gib_flow.anim_speed_max = 0.0
	_drop_mesh = SphereMesh.new()
	_drop_mesh.radius = 0.011
	_drop_mesh.height = 0.022
	_drop_mesh.radial_segments = 6
	_drop_mesh.rings = 3
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.albedo_color = Color(0.62, 0.05, 0.06)
	_drop_mat.roughness = 0.3
	_drop_flow = ParticleProcessMaterial.new()
	_drop_flow.direction = Vector3(0, 0, -1)
	_drop_flow.spread = 26.0
	_drop_flow.initial_velocity_min = 1.5
	_drop_flow.initial_velocity_max = 6.5
	_drop_flow.gravity = Vector3(0, -9.8, 0)
	_drop_flow.scale_min = 0.4
	_drop_flow.scale_max = 1.6
	add_to_group(Prewarm.GROUP)


## FIRST TIMES (SCRIPT_prewarm.gd): a cow cut in two (hide, and the meat of the
## cut), the gobbets and drops of a cut, a cut of beef lying, and the fire of
## the beam's burst.
func warm(stage: Node3D) -> void:
	var at := stage.global_position
	var before := get_child_count()
	var skin := {}
	if _herds != null:
		for herd in _herds._herds:
			for cow in herd["cows"]:
				var found: Array = (cow["node"] as Node).find_children("*", "MeshInstance3D", true, false)
				if not found.is_empty() and skin.is_empty():
					var mi := found[0] as MeshInstance3D
					skin = {"arrays": mi.mesh.surface_get_arrays(0), "material": mi.mesh.surface_get_material(0),
						"transform": Transform3D(mi.global_basis, at)}
	if not skin.is_empty():
		var whole := _whole(skin)
		_cows -= 1
		var body: RigidBody3D = whole["body"]
		var halves := _cut(whole, Plane(Vector3(1, 0, 0), Vector3.ZERO))
		for half in halves:
			_body(half, body.global_transform, 0, 1, whole["material"])
	_spray(at, -stage.global_basis.z)
	var card := MeshInstance3D.new()
	card.mesh = _steak_card()
	add_child(card)
	card.global_position = at + stage.global_basis.x * 0.4
	Fx.spawn(self, "explosion_small", to_local(at), 0.3)
	Prewarm.gather(self, before, stage)


# ------------------------------------------------------------------ the swing

## A swing from `from` along `dir`, the blade travelling across the view along
## `travel` (a direction in the world, square to `dir`). True if it cut a cow or
## a piece of one.
func slice(from: Vector3, dir: Vector3, travel: Vector3) -> bool:
	dir = dir.normalized()
	# A BLADE IS A LINE, NOT A POINT. The swing is tried along the line it is drawn
	# across the view, from its middle outward, and lands on the first cow or piece
	# of cow any of it meets. (The middle alone will not do: after one cut the gap
	# between the two halves is exactly where the middle of the next swing goes.)
	var space := get_world_3d().direct_space_state
	var skip: Array[RID] = []
	if _explorer is CollisionObject3D:
		skip.append((_explorer as CollisionObject3D).get_rid())
	var across := travel.normalized()
	var hit := {}
	for lean in [0.0, -0.07, 0.07, -0.14, 0.14, -0.22, 0.22, -0.3, 0.3]:
		var q := PhysicsRayQueryParameters3D.create(from, from + (dir + across * float(lean)).normalized() * reach)
		q.exclude = skip
		var met := space.intersect_ray(q)
		if not met.is_empty() and ((met["collider"] as Object).has_meta(&"cow_piece") or (met["collider"] as Object).has_meta(&"cow")):
			hit = met
			break
	if hit.is_empty():
		return false
	var struck: Object = hit["collider"]
	var normal := dir.cross(travel).normalized()
	if normal.length() < 0.5:
		normal = dir.cross(Vector3.UP).normalized()
	var plane := Plane(normal, hit["position"])
	var piece := {}
	if struck.has_meta(&"cow_piece"):
		for p in _pieces:
			if p["body"] == struck:
				piece = p
		if piece.is_empty():
			return false
		_pieces.erase(piece)
	elif _herds != null and struck.has_meta(&"cow"):
		var found := _herds.cow_of(struck)
		if found.is_empty():
			return false
		piece = _whole(_herds.butcher(found, from))
	else:
		return false
	var body: RigidBody3D = piece["body"]
	var halves := _cut(piece, body.global_transform.affine_inverse() * plane)
	if halves.is_empty():
		_pieces.append(piece)          # the blade only grazed it
		return true
	var carried := body.linear_velocity
	var spin := body.angular_velocity
	var where := body.global_transform
	body.queue_free()
	for side in 2:
		var half: Dictionary = halves[side]
		var away := normal * (1.0 if side == 0 else -1.0)
		var made := _body(half, where, int(piece["cow"]), int(piece["cuts"]) + 1, piece["material"])
		var push := away * _rng.randf_range(1.1, 2.0) + travel.normalized() * _rng.randf_range(0.3, 1.0) + Vector3.UP * _rng.randf_range(0.5, 1.4)
		(made["body"] as RigidBody3D).linear_velocity = carried + push
		(made["body"] as RigidBody3D).angular_velocity = spin + away.cross(dir) * _rng.randf_range(0.5, 1.6)
		_pieces.append(made)
	_spray(hit["position"], travel)
	# Every cut lets some beef go, until the cow has given all it has.
	var cow_no := int(piece["cow"])
	var gives := mini(_rng.randi_range(steaks_per_cut.x, steaks_per_cut.y), beef_per_cow - int(_given.get(cow_no, 0)))
	if gives > 0:
		_given[cow_no] = int(_given.get(cow_no, 0)) + gives
		_drop_steaks(hit["position"], normal, travel, gives)
	_hold_time()
	while _pieces.size() > max_pieces:
		((_pieces.pop_front() as Dictionary)["body"] as Node).queue_free()
	return true


# ------------------------------------------------------------------ the blade's beam

## THE BEAM THROWN OFF A CHARGED BLADE DOES NOT CUT A COW, IT BURSTS IT. `struck`
## is what the beam landed on (a cow, or a piece of one), `at` where, `heading`
## the way the beam was going. The cow is cut along a dozen planes at once into
## a heap of small chunks, each thrown out hard from the middle and on the way
## the beam was going, in a ball of fire with its light, a cloud of gobbets and
## drops, and all the beef it had left. True if there was a cow there.
func burst(struck: Object, at: Vector3, heading: Vector3) -> bool:
	if struck == null:
		return false
	var piece := {}
	if struck.has_meta(&"cow_piece"):
		for p in _pieces:
			if p["body"] == struck:
				piece = p
		if piece.is_empty():
			return false
		_pieces.erase(piece)
	elif _herds != null and struck.has_meta(&"cow"):
		var found := _herds.cow_of(struck)
		if found.is_empty():
			return false
		piece = _whole(_herds.butcher(found, at - heading * 3.0))
	else:
		return false
	var body: RigidBody3D = piece["body"]
	var where := body.global_transform
	var middle := where.origin
	# Cut and cut again: every part in two by a plane through its own middle, at
	# whatever angle, `burst_cuts` times over.
	var parts: Array = [{"skin": piece["skin"], "meat": piece["meat"]}]
	for round_ in burst_cuts:
		var next: Array = []
		for part in parts:
			var box := _box_of(part)
			var across := maxf(box.size.x, maxf(box.size.y, box.size.z))
			var normal := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
			var through := box.get_center() + box.size * Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(-0.15, 0.15), _rng.randf_range(-0.15, 0.15))
			var halves := _cut({"skin": part["skin"], "meat": part["meat"], "across": across}, Plane(normal, through))
			if halves.is_empty():
				next.append(part)
			else:
				next.append_array(halves)
		parts = next
	body.queue_free()
	var away := heading.normalized()
	for part in parts:
		var made := _body(part, where, int(piece["cow"]), int(piece["cuts"]) + burst_cuts, piece["material"])
		var chunk: RigidBody3D = made["body"]
		var out := (chunk.global_position - middle)
		out = out.normalized() if out.length() > 0.02 else Vector3.UP
		chunk.linear_velocity = out * _rng.randf_range(6.0, 11.0) + away * _rng.randf_range(2.0, 5.0) + Vector3.UP * _rng.randf_range(2.5, 6.5)
		chunk.angular_velocity = Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-9, 9), _rng.randf_range(-9, 9))
		_pieces.append(made)
	# Fire, and its light (the effects library's small explosion), and the gore.
	Fx.spawn(self, "explosion_small", to_local(middle - Vector3(0, 0.6, 0)), 0.9)
	for n in 4:
		_spray(middle + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.2, 0.5), _rng.randf_range(-0.4, 0.4)),
				(away + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.0, 1.0), _rng.randf_range(-1, 1))).normalized())
	var cow_no := int(piece["cow"])
	var gives := beef_per_cow - int(_given.get(cow_no, 0))
	if gives > 0:
		_given[cow_no] = beef_per_cow
		_drop_steaks(middle, away.cross(Vector3.UP).normalized(), away, gives)
	_hold_time()
	while _pieces.size() > max_pieces:
		((_pieces.pop_front() as Dictionary)["body"] as Node).queue_free()
	return true


func _box_of(part: Dictionary) -> AABB:
	var verts: PackedVector3Array = part["skin"][0]
	var meat: PackedVector3Array = part["meat"][0]
	var box := AABB(verts[0] if not verts.is_empty() else meat[0], Vector3.ZERO)
	for p in verts:
		box = box.expand(p)
	for p in meat:
		box = box.expand(p)
	return box


## Time slows for a breath at a cut; a run of cuts keeps it slow.
func _hold_time() -> void:
	Engine.time_scale = slow
	_slow_until = Time.get_ticks_msec() + int(slow_for * 1000.0)


## What flies off a cut: gobbets of meat, and a spray of drops, thrown the way the blade was going.
func _spray(at: Vector3, travel: Vector3) -> void:
	for pass_ in [[14, 1.3, _gib_flow, _gib_quad, _gib_mat], [34, 0.9, _drop_flow, _drop_mesh, _drop_mat]]:
		var p := GPUParticles3D.new()
		p.amount = int(pass_[0])
		p.lifetime = float(pass_[1])
		p.one_shot = true
		p.explosiveness = 0.95
		p.process_material = pass_[2]
		p.draw_pass_1 = pass_[3]
		p.material_override = pass_[4]
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3.ONE * -8.0, Vector3.ONE * 16.0)
		add_child(p)
		p.global_transform = Transform3D(Basis.looking_at(travel.normalized() + Vector3.UP * 0.35), at)
		p.emitting = true
		get_tree().create_timer(float(pass_[1]) + 0.8).timeout.connect(p.queue_free)


# ------------------------------------------------------------------ pieces

## A whole cow as the first piece: its skin in plain metres about its own middle.
func _whole(cow: Dictionary) -> Dictionary:
	var arrays: Array = cow["arrays"]
	var xf: Transform3D = cow["transform"]
	var size := xf.basis.get_scale()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(idx.size())
	normals.resize(idx.size())
	uvs.resize(idx.size())
	for i in idx.size():
		verts[i] = v[idx[i]] * size
		normals[i] = n[idx[i]]
		uvs[i] = uv[idx[i]]
	_cows += 1
	var where := Transform3D(xf.basis.orthonormalized(), xf.origin)
	return _body({"skin": [verts, normals, uvs], "meat": [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]},
			where, _cows, 0, cow["material"])


## A body for one piece: its mesh (skin, and meat where it has been cut), shaped
## by its own corners, hung at its own middle.
func _body(half: Dictionary, where: Transform3D, cow: int, cuts: int, material: Material) -> Dictionary:
	var skin: Array = half["skin"]
	var meat: Array = half["meat"]
	var verts: PackedVector3Array = skin[0]
	var meat_verts: PackedVector3Array = meat[0]
	var box := AABB(verts[0] if not verts.is_empty() else meat_verts[0], Vector3.ZERO)
	for p in verts:
		box = box.expand(p)
	for p in meat_verts:
		box = box.expand(p)
	var middle := box.get_center()
	for i in verts.size():
		verts[i] -= middle
	for i in meat_verts.size():
		meat_verts[i] -= middle
	skin[0] = verts
	meat[0] = meat_verts
	var mesh := ArrayMesh.new()
	for pair in [[skin, material], [meat, _meat]]:
		var part: Array = pair[0]
		if (part[0] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = part[0]
		arrays[Mesh.ARRAY_NORMAL] = part[1]
		arrays[Mesh.ARRAY_TEX_UV] = part[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	var body := RigidBody3D.new()
	body.set_meta(&"cow_piece", true)
	var across := box.size
	body.mass = maxf(180.0 * across.x * across.y * across.z, 2.0)
	body.angular_damp = 0.8
	var friction := PhysicsMaterial.new()
	friction.friction = 0.9
	friction.bounce = 0.15
	body.physics_material_override = friction
	# Its shape: a spread of its own corners (a hull needs no more than a few dozen).
	var points := PackedVector3Array()
	var every := maxi(verts.size() / 48, 1)
	for i in range(0, verts.size(), every):
		points.append(verts[i])
	for i in range(0, meat_verts.size(), maxi(meat_verts.size() / 16, 1)):
		points.append(meat_verts[i])
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	add_child(body)
	body.global_transform = Transform3D(where.basis, where * middle)
	return {"body": body, "skin": skin, "meat": meat, "age": 0.0, "cow": cow, "cuts": cuts, "material": material,
		"across": maxf(across.x, maxf(across.y, across.z))}


## Cut a piece in two by a plane (in the piece's own frame). Two halves, each
## {"skin", "meat"}; nothing if the piece is too small, or the plane misses all
## but a sliver of it.
func _cut(piece: Dictionary, plane: Plane) -> Array:
	if float(piece["across"]) < smallest:
		return []
	var sides := [[PackedVector3Array(), PackedVector3Array(), PackedVector2Array()], [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]]
	var meats := [[PackedVector3Array(), PackedVector3Array(), PackedVector2Array()], [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]]
	var ring := PackedVector3Array()
	_split(piece["skin"], plane, sides, ring)
	# Meat already showing from earlier cuts is cut too, and stays meat.
	var old_ring := PackedVector3Array()
	_split(piece["meat"], plane, meats, old_ring)
	ring.append_array(old_ring)
	if (sides[0][0] as PackedVector3Array).size() + (meats[0][0] as PackedVector3Array).size() < 9 \
			or (sides[1][0] as PackedVector3Array).size() + (meats[1][0] as PackedVector3Array).size() < 9 or ring.size() < 6:
		return []
	# THE NEW FACE: a fan across the ring of points where the blade came through.
	var centre := Vector3.ZERO
	for p in ring:
		centre += p
	centre /= float(ring.size())
	var u := plane.normal.cross(Vector3.UP if absf(plane.normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := plane.normal.cross(u)
	# THE OUTLINE of the cut is the hull of those points, not the points in order
	# round the middle: the blade goes through the mouth, the lips and the tongue
	# as well as the hide, and a fan through every one of those rings is a burst
	# of spikes. The hull is the hide's own outline, and the meat fills it flat.
	var flat: PackedVector2Array = []
	for p in ring:
		var rel := p - centre
		flat.append(Vector2(rel.dot(u), rel.dot(w)))
	var hull := Geometry2D.convex_hull(flat)
	if hull.size() < 4:
		return []
	var around: Array = []
	var mid := Vector2.ZERO
	for i in hull.size() - 1:          # (the hull comes back closed: its last point is its first)
		mid += hull[i]
	mid /= float(hull.size() - 1)
	centre += u * mid.x + w * mid.y
	for i in hull.size() - 1:
		around.append([0.0, centre + u * (hull[i].x - mid.x) + w * (hull[i].y - mid.y)])
	for side in 2:
		var face: Vector3 = -plane.normal if side == 0 else plane.normal          # each half's meat faces the other half
		var mv: PackedVector3Array = meats[side][0]
		var mn: PackedVector3Array = meats[side][1]
		var mu: PackedVector2Array = meats[side][2]
		for i in around.size():
			var a: Vector3 = around[i][1]
			var b: Vector3 = around[(i + 1) % around.size()][1]
			if a.distance_squared_to(b) < 1e-8:
				continue
			# How far the middle is in from this stretch of the edge: every point of
			# the triangle then knows its own distance in (SHADER_cut_meat's rind).
			var along := (b - a).normalized()
			var deep := ((centre - a) - along * (centre - a).dot(along)).length()
			for p in ([centre, a, b] if side == 0 else [centre, b, a]):
				mv.append(p)
				mn.append(face)
				mu.append(Vector2(deep if p == centre else 0.0, 0.0))
		meats[side] = [mv, mn, mu]
	return [{"skin": sides[0], "meat": meats[0]}, {"skin": sides[1], "meat": meats[1]}]


## Every triangle of `part` to the side of `plane` it is on (0 above, 1 below),
## split along it where it straddles; the points on the plane are added to `ring`.
func _split(part: Array, plane: Plane, into: Array, ring: PackedVector3Array) -> void:
	var v: PackedVector3Array = part[0]
	var n: PackedVector3Array = part[1]
	var uv: PackedVector2Array = part[2]
	# (Each side's three lists are held here by name while they grow, and handed
	# back at the end: a packed array reached through a list is a copy of it.)
	var v0: PackedVector3Array = into[0][0]
	var n0: PackedVector3Array = into[0][1]
	var u0: PackedVector2Array = into[0][2]
	var v1: PackedVector3Array = into[1][0]
	var n1: PackedVector3Array = into[1][1]
	var u1: PackedVector2Array = into[1][2]
	for t in range(0, v.size(), 3):
		var da := plane.distance_to(v[t])
		var db := plane.distance_to(v[t + 1])
		var dc := plane.distance_to(v[t + 2])
		var above := int(da >= 0.0) + int(db >= 0.0) + int(dc >= 0.0)
		if above == 3:
			for k in 3:
				v0.append(v[t + k]); n0.append(n[t + k]); u0.append(uv[t + k])
			continue
		if above == 0:
			for k in 3:
				v1.append(v[t + k]); n1.append(n[t + k]); u1.append(uv[t + k])
			continue
		# One corner is alone on its side: it keeps a small triangle, the other two
		# a four-sided piece.
		var d := [da, db, dc]
		var lone := 0
		for k in 3:
			if (float(d[k]) >= 0.0) == (above == 1):
				lone = k
		var a := t + lone
		var b := t + (lone + 1) % 3
		var c := t + (lone + 2) % 3
		var fb := float(d[lone]) / (float(d[lone]) - float(d[(lone + 1) % 3]))
		var fc := float(d[lone]) / (float(d[lone]) - float(d[(lone + 2) % 3]))
		var pb := v[a].lerp(v[b], fb)
		var pc := v[a].lerp(v[c], fc)
		var nb := n[a].lerp(n[b], fb)
		var nc := n[a].lerp(n[c], fc)
		var ub := uv[a].lerp(uv[b], fb)
		var uc := uv[a].lerp(uv[c], fc)
		ring.append(pb)
		ring.append(pc)
		if float(d[lone]) >= 0.0:
			v0.append(v[a]); v0.append(pb); v0.append(pc)
			n0.append(n[a]); n0.append(nb); n0.append(nc)
			u0.append(uv[a]); u0.append(ub); u0.append(uc)
			v1.append(pb); v1.append(v[b]); v1.append(v[c]); v1.append(pb); v1.append(v[c]); v1.append(pc)
			n1.append(nb); n1.append(n[b]); n1.append(n[c]); n1.append(nb); n1.append(n[c]); n1.append(nc)
			u1.append(ub); u1.append(uv[b]); u1.append(uv[c]); u1.append(ub); u1.append(uv[c]); u1.append(uc)
		else:
			v1.append(v[a]); v1.append(pb); v1.append(pc)
			n1.append(n[a]); n1.append(nb); n1.append(nc)
			u1.append(uv[a]); u1.append(ub); u1.append(uc)
			v0.append(pb); v0.append(v[b]); v0.append(v[c]); v0.append(pb); v0.append(v[c]); v0.append(pc)
			n0.append(nb); n0.append(n[b]); n0.append(n[c]); n0.append(nb); n0.append(n[c]); n0.append(nc)
			u0.append(ub); u0.append(uv[b]); u0.append(uv[c]); u0.append(ub); u0.append(uv[c]); u0.append(uc)
	into[0] = [v0, n0, u0]
	into[1] = [v1, n1, u1]


# ------------------------------------------------------------------ beef

func _process(delta: float) -> void:
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= _slow_until:
		Engine.time_scale = 1.0
	if _explorer == null:
		return
	var here := _explorer.global_position + Vector3(0, 0.9, 0)
	# THE CHUNKS ARE NOT FOR THE BAG. They lie where they fell for a while and then
	# go into the ground: sinking, and thinning away as they sink.
	for i in range(_pieces.size() - 1, -1, -1):
		var piece: Dictionary = _pieces[i]
		var body: RigidBody3D = piece["body"]
		piece["age"] = float(piece["age"]) + delta
		if body.global_position.y < -400.0:
			_pieces.remove_at(i)
			body.queue_free()
			continue
		if float(piece["age"]) < lie_for:
			continue
		_pieces.remove_at(i)
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
		var down := float(piece["across"]) * 0.9 + 0.15
		var gone := create_tween()
		gone.tween_property(body, "global_position:y", body.global_position.y - down, sink_for).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		gone.parallel().tween_property(body, "scale", Vector3(1.08, 0.35, 1.08), sink_for)
		gone.tween_callback(body.queue_free)
	# THE STEAKS ARE: each a cut of raw beef, taken by walking up to it.
	for i in range(_steaks.size() - 1, -1, -1):
		var entry: Array = _steaks[i]
		var steak: RigidBody3D = entry[0]
		entry[1] = float(entry[1]) + delta
		if steak.global_position.y < -400.0 or float(entry[1]) > 300.0:
			_steaks.remove_at(i)
			steak.queue_free()
			continue
		if float(entry[1]) < 1.2 or steak.global_position.distance_to(here) > gather_radius:
			continue
		if _bag == null or int(_bag.call(&"add", "beef", 1)) > 0:
			continue          # nowhere to put it
		_steaks.remove_at(i)
		steak.freeze = true
		steak.collision_layer = 0
		steak.collision_mask = 0
		var pull := create_tween()
		pull.tween_property(steak, "global_position", here, 0.16)
		pull.parallel().tween_property(steak, "scale", Vector3.ONE * 0.2, 0.16)
		pull.tween_callback(steak.queue_free)


## Cuts of raw beef thrown out of a cut: `count` of them, out to either side of
## the blade's line and up, to drop and lie in the grass.
func _drop_steaks(at: Vector3, normal: Vector3, travel: Vector3, count: int) -> void:
	_steak_card()
	for i in count:
		var body := RigidBody3D.new()
		body.mass = 0.4
		body.linear_damp = 0.4
		body.angular_damp = 3.0
		var soft := PhysicsMaterial.new()
		soft.friction = 1.0
		soft.bounce = 0.2
		body.physics_material_override = soft
		var cs := CollisionShape3D.new()
		cs.shape = _steak_shape
		body.add_child(cs)
		var card := MeshInstance3D.new()
		card.mesh = _steak_quad
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(card)
		add_child(body)
		body.global_position = at + Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(0.0, 0.3), _rng.randf_range(-0.2, 0.2))
		var side := normal * (1.0 if _rng.randf() < 0.5 else -1.0)
		body.linear_velocity = side * _rng.randf_range(0.8, 2.4) + travel.normalized() * _rng.randf_range(-0.6, 1.6) + Vector3.UP * _rng.randf_range(2.0, 4.0)
		_steaks.append([body, 0.0])
	while _steaks.size() > 60:
		(_steaks.pop_front()[0] as Node).queue_free()


## The card a cut of beef is drawn on (made the first time it is wanted).
func _steak_card() -> QuadMesh:
	if _steak_quad == null:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load("res://assets/ui/item_beef.png")
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.45
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.roughness = 1.0
		mat.metallic = 0.0
		mat.metallic_specular = 0.0
		_steak_quad = QuadMesh.new()
		_steak_quad.size = Vector2(0.3, 0.3)
		_steak_quad.material = mat
		_steak_shape = SphereShape3D.new()
		_steak_shape.radius = 0.1
	return _steak_quad


func _exit_tree() -> void:
	Engine.time_scale = 1.0
