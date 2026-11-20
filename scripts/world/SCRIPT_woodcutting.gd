class_name Woodcutting
extends Node3D

# FELLING TREES WITH THE SWORD, AND THE LOGS THEY BECOME.
#
# A swing that meets a trunk bites into it; a few bites (more for a bigger tree)
# and the tree bursts into a run of logs, as many as it was tall, tumbling where
# it stood. A charged crescent fells whatever tree it strikes outright. Logs are
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

var _flora: Flora
var _explorer: Node3D
var _inventory: Node
var _bites := {}             # tree origin -> swings taken
var _logs: Array = []        # [body, seconds lain]
var _meshes := {}            # radius in cm -> ArrayMesh
var _bark: StandardMaterial3D
var _end: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


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
	_end = StandardMaterial3D.new()
	_end.albedo_texture = load("res://assets/log/log_end.jpg")
	_end.roughness = 0.85


## How many swings a tree of this girth takes.
static func bites_for(radius: float) -> int:
	return clampi(int(round(radius * 7.0)), 1, 5)


## A swing from `from` along `dir`. True if it met a tree.
func strike(from: Vector3, dir: Vector3, outright := false) -> bool:
	if _flora == null:
		return false
	var tree := _flora.tree_on(from, dir, reach)
	if tree.is_empty():
		return false
	var origin: Vector3 = tree["origin"]
	var at := Vector3(origin.x, clampf(from.y - 0.3, origin.y + 0.4, origin.y + float(tree["height"])), origin.z)
	var taken := int(_bites.get(origin, 0)) + 1
	if outright or taken >= bites_for(float(tree["radius"])):
		_bites.erase(origin)
		_fell(tree)
	else:
		_bites[origin] = taken
		_chips(at - Vector3(dir.x, 0.0, dir.z).normalized() * float(tree["radius"]), 26, Color(0.82, 0.66, 0.42))
	return true


## Where a crescent burst: the tree there, if there is one, comes down at once.
func blast(at: Vector3) -> void:
	if _flora == null:
		return
	var tree := _flora.tree_on(at, Vector3.ZERO, 0.0, 1.1)
	if not tree.is_empty():
		_bites.erase(tree["origin"])
		_fell(tree)


func _fell(tree: Dictionary) -> void:
	_flora.fell(tree)
	var origin: Vector3 = tree["origin"]
	var basis: Basis = tree["basis"]
	var up := basis.y
	var height := float(tree["height"])
	var radius := float(tree["radius"])
	# The trunk below the crown, sawn into lengths; the thin top is lost in the fall.
	var trunk := height * 0.62
	var count := clampi(int(round(trunk / 2.3)), 2, 9)
	for i in count:
		var f := float(i) / float(count)
		var r := maxf(radius * (1.0 - 0.72 * f), 0.07)
		var body := _log_body(r)
		add_child(body)
		body.global_transform = Transform3D(basis * Basis(Vector3.UP, _rng.randf() * TAU),
				origin + up * (0.5 + (float(i) + 0.5) * trunk / float(count)))
		var away := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
		body.linear_velocity = away * _rng.randf_range(1.2, 3.4) + Vector3.UP * _rng.randf_range(0.5, 2.6)
		body.angular_velocity = Vector3(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-3.0, 3.0))
		_logs.append([body, 0.0])
	while _logs.size() > max_logs:
		(_logs.pop_front()[0] as Node).queue_free()
	_chips(origin + up * 1.0, 60, Color(0.82, 0.66, 0.42))
	# The crown, coming apart: needles shed down the whole height of the tree.
	_chips(origin + up * height * 0.55, 220, Color(0.16, 0.3, 0.14), Vector3(radius * 5.0 + 1.0, height * 0.4, radius * 5.0 + 1.0), 3.2)


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
	var mi := MeshInstance3D.new()
	mi.mesh = _log_mesh(radius)
	body.add_child(mi)
	return body


## A log standing on Y: the bark wrapped round it (tiled to its girth so it is
## never stretched), the sawn end on each cap.
func _log_mesh(radius: float) -> ArrayMesh:
	var cm := int(round(radius * 100.0 / 4.0)) * 4
	if _meshes.has(cm):
		return _meshes[cm]
	var r := maxf(float(cm) / 100.0, 0.04)
	var half := LOG_LENGTH * 0.5
	var sides := 14 if r < 0.3 else 20
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
		for j in [0, 2, 1, 0, 3, 2]:
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
			var order: Array = [0, 2, 1] if side > 0.0 else [0, 1, 2]
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
	var m := ParticleProcessMaterial.new()
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
	p.process_material = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.035)
	quad.material = mat
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(-spread - Vector3.ONE * 12.0, spread * 2.0 + Vector3.ONE * 24.0)
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)


## Logs that have had a moment to fall are gathered by walking up to them.
func _process(delta: float) -> void:
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
