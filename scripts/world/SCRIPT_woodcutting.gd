class_name Woodcutting
extends Node3D

# FELLING TREES WITH THE SWORD, AND THE LOGS THEY BECOME.
#
# A swing of the axe or the sword that meets a trunk bites into it and leaves a
# notch of pale wood. A few bites (more for a bigger tree) and the tree goes
# over, away from whoever cut it, slowly and then fast; where it hits the ground
# it breaks into a run of logs laid along its length, and a stump is left
# standing. A charged crescent cuts whatever tree it strikes through at once. Logs are
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
## How far up the trunk the cut is made, metres.
const CUT_HEIGHT := 0.9
## The lean (radians from upright) at which a falling tree has reached the ground.
const DOWN := 1.5

var _flora: Flora
var _explorer: Node3D
var _inventory: Node
var _bites := {}             # tree origin -> swings taken
var _logs: Array = []        # [body, seconds lain]
var _notches := {}           # tree origin -> the scar on it
var _falls: Array = []       # trees on their way down
var _stumps: Array = []
var _notch_mesh: SphereMesh
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
	_notch_mesh = SphereMesh.new()
	_notch_mesh.radius = 0.5
	_notch_mesh.height = 1.0
	_notch_mesh.radial_segments = 14
	_notch_mesh.rings = 7
	var fresh := StandardMaterial3D.new()
	fresh.albedo_color = Color(0.86, 0.72, 0.5)
	fresh.albedo_texture = load("res://assets/log/log_end.jpg")
	fresh.uv1_triplanar = true
	fresh.uv1_scale = Vector3(2.5, 2.5, 2.5)
	fresh.roughness = 0.8
	_notch_mesh.material = fresh
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


## How many swings a tree of this girth takes.
static func bites_for(radius: float) -> int:
	return clampi(int(round(radius * 7.0)), 2, 6)


## A swing from `from` along `dir`. True if it met a tree. Each bite deepens the
## notch on the side it was struck from; the last one sends the tree over, away
## from whoever cut it.
func strike(from: Vector3, dir: Vector3, outright := false) -> bool:
	if _flora == null:
		return false
	var tree := _flora.tree_on(from, dir, reach)
	if tree.is_empty():
		return false
	var origin: Vector3 = tree["origin"]
	var radius := float(tree["radius"])
	var away := Vector3(origin.x - from.x, 0.0, origin.z - from.z)
	away = away.normalized() if away.length() > 0.01 else Vector3(dir.x, 0.0, dir.z).normalized()
	var cut_at := origin + Vector3.UP * CUT_HEIGHT - away * radius
	var taken := int(_bites.get(origin, 0)) + 1
	var needed := bites_for(radius)
	_chips(cut_at, 26, CHIP)
	if outright or taken >= needed:
		_bites.erase(origin)
		_drop_notch(origin)
		_topple(tree, away)
	else:
		_bites[origin] = taken
		_notch(origin, cut_at, away, radius, float(taken) / float(needed))
	return true


## Where a crescent burst: the tree there, if there is one, is cut through at a
## stroke and falls the way the crescent was going.
func blast(at: Vector3, heading := Vector3.ZERO) -> void:
	if _flora == null:
		return
	var tree := _flora.tree_on(at, Vector3.ZERO, 0.0, 1.1)
	if tree.is_empty():
		return
	var away := Vector3(heading.x, 0.0, heading.z)
	if away.length() < 0.01 and _explorer != null:
		away = (tree["origin"] as Vector3) - _explorer.global_position
		away.y = 0.0
	_bites.erase(tree["origin"])
	_drop_notch(tree["origin"])
	_topple(tree, away.normalized() if away.length() > 0.01 else Vector3.FORWARD)


# ------------------------------------------------------------------ the notch

## The cut, as far as it has got: a pale lens of fresh wood let into the trunk
## on the side being chopped, wider and deeper with every bite.
func _notch(origin: Vector3, at: Vector3, away: Vector3, radius: float, depth: float) -> void:
	var scar: MeshInstance3D = _notches.get(origin)
	if scar == null:
		scar = MeshInstance3D.new()
		scar.mesh = _notch_mesh
		scar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(scar)
		_notches[origin] = scar
	# A lens lying across the trunk, its middle pushed in from the bark.
	var across := away.cross(Vector3.UP).normalized()
	var wide := radius * lerpf(0.9, 1.9, depth)
	scar.global_transform = Transform3D(
			Basis(across * wide, Vector3.UP * radius * lerpf(0.35, 0.8, depth), away * radius * lerpf(0.5, 1.5, depth)),
			at + away * radius * lerpf(0.15, 0.55, depth))


func _drop_notch(origin: Vector3) -> void:
	var scar: MeshInstance3D = _notches.get(origin)
	if scar != null:
		scar.queue_free()
		_notches.erase(origin)


# ------------------------------------------------------------------ the fall

## The tree leaves the wood and stands on its own for the few seconds it takes
## to come down: hinged at the cut, tipping the way `away` points, slowly at
## first and then fast, the way a real one goes. A stump stays where it stood.
func _topple(tree: Dictionary, away: Vector3) -> void:
	var mesh := _flora.tree_mesh(int(tree["kind"]))
	_flora.fell(tree)
	var origin: Vector3 = tree["origin"]
	var basis: Basis = tree["basis"]
	var radius := float(tree["radius"])
	var height := float(tree["height"])
	_stump(origin, basis, radius)
	var hinge := Node3D.new()
	add_child(hinge)
	hinge.global_position = origin + Vector3.UP * CUT_HEIGHT * 0.5
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		hinge.add_child(mi)
		mi.global_transform = Transform3D(basis.scaled(Vector3.ONE * float(tree["size"])), origin)
		mi.extra_cull_margin = height
	# A tall tree is a long pendulum and goes over slowly; a sapling snaps down.
	var pull := clampf(3.0 * 9.8 / (2.0 * height) * 1.7, 0.55, 3.2)
	_falls.append({"hinge": hinge, "axis": Vector3.UP.cross(away).normalized(), "away": away, "angle": 0.05,
		"speed": 0.22, "pull": pull, "radius": radius, "height": height, "basis": basis})


func _stump(origin: Vector3, basis: Basis, radius: float) -> void:
	var body := StaticBody3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = CUT_HEIGHT
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var base: float = GIRTHS[0]
	for g in GIRTHS:
		if absf(g - radius) < absf(base - radius):
			base = g
	var mi := MeshInstance3D.new()
	mi.mesh = _log_mesh(base)
	mi.scale = Vector3(radius * 1.12 / base, CUT_HEIGHT / LOG_LENGTH, radius * 1.12 / base)
	body.add_child(mi)
	add_child(body)
	body.global_transform = Transform3D(basis, origin + basis.y * (CUT_HEIGHT * 0.5 - 0.1))
	_stumps.append(body)
	while _stumps.size() > 240:
		(_stumps.pop_front() as Node).queue_free()


func _fall_step(delta: float) -> void:
	for i in range(_falls.size() - 1, -1, -1):
		var f: Dictionary = _falls[i]
		f["speed"] = float(f["speed"]) + float(f["pull"]) * sin(float(f["angle"])) * delta
		f["angle"] = float(f["angle"]) + float(f["speed"]) * delta
		var hinge: Node3D = f["hinge"]
		if float(f["angle"]) < DOWN:
			hinge.global_basis = Basis(f["axis"], float(f["angle"]))
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
