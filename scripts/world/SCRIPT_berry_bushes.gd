class_name BerryBushes
extends Node3D

# BERRY BUSHES: a viburnum in leaf and hung with red berries, here and there in
# the wood. Hit one (axe, sword, anything swung) and it is stripped: the leaves
# and berries go up in a cloud, the bare bush is left standing, and a handful of
# berries goes into the bag.
#
# THE BUSH IS TWO MODELS (assets/berry_bush): the viburnum in leaf and berry, and
# the same bush bare. Each stands as the first until it is hit and as the second
# after. The cloud between them is single leaves (the drawn leaf atlas) and
# berry clusters (the photograph the inventory icon is cut from).
#
# ONLY THE ONES NEAR THE PLAYER EXIST. The island is divided into squares of
# `spacing` metres; a hash of the square says whether a bush stands in it and
# where, and the ground decides whether it may (grass or soil, not water, sand,
# rock, a steep slope or a path). Squares coming within `range` of the player get
# their bush; squares left behind lose it. What has been stripped is remembered
# by square for the run.

@export var world_path: NodePath = ^"../GaiaSphere"
@export var explorer_path: NodePath = ^"../Explorer"
@export var inventory_path: NodePath = ^"../Inventory"
## The side of a square, metres: at most one bush in each.
@export var spacing := 34.0
## The share of squares that hold a bush where the ground allows.
@export_range(0.0, 1.0) var share := 0.5
## How far from the player bushes exist, metres.
@export var view_range := 130.0
## How near a swing has to come, metres.
@export var reach := 3.2
## Berries a bush gives: fewest and most.
@export var berries := Vector2i(3, 7)

var _world: Node
var _field: IslandField
var _explorer: Node3D
var _inventory: Node
var _bare: Mesh
var _bare_mat: StandardMaterial3D
var _leafy: Mesh
var _leafy_mat: StandardMaterial3D
var _live := {}                  # square -> the bush's node, or null where none stands
var _stripped := {}              # square -> true
var _at_square := Vector2i(1 << 30, 0)
var _leaf_mat: StandardMaterial3D
var _berry_mat: StandardMaterial3D
var _leaf_puff: StandardMaterial3D
var _berry_puff: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _todo: Array = []            # squares still to look at


func _ready() -> void:
	_world = get_node_or_null(world_path)
	_explorer = get_node_or_null(explorer_path)
	_inventory = get_node_or_null(inventory_path)
	if _world == null or not _world.has_method(&"get_field"):
		set_process(false)
		return
	_field = _world.call(&"get_field")
	_rng.randomize()
	_bare = _model("res://assets/berry_bush/viburnum_bush_bare.glb")
	_leafy = _model("res://assets/berry_bush/viburnum_bush.glb")
	_bare_mat = _both_sides(_bare)
	_leafy_mat = _both_sides(_leafy)
	_leafy_mat.backlight_enabled = true
	_leafy_mat.backlight = Color(0.14, 0.2, 0.05)
	_leaf_mat = _cutout(load("res://assets/leaves/berry_leaves_atlas.png"), Color(0.78, 0.9, 0.7))
	_leaf_mat.backlight_enabled = true
	_leaf_mat.backlight = Color(0.16, 0.24, 0.06)
	_berry_mat = _cutout(load("res://assets/berry_bush/berry_cluster.png"), Color(1, 1, 1))
	_berry_mat.roughness = 0.35
	_leaf_puff = _leaf_mat.duplicate()
	_leaf_puff.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_leaf_puff.particles_anim_h_frames = 4
	_leaf_puff.particles_anim_v_frames = 4
	_leaf_puff.particles_anim_loop = false
	_berry_puff = _berry_mat.duplicate()
	_berry_puff.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	call_deferred(&"_warm_up")


static func _model(path: String) -> Mesh:
	var scene: Node = (load(path) as PackedScene).instantiate()
	var found: Mesh = null
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		found = (n as MeshInstance3D).mesh
		break
	scene.free()
	return found


## The model's own material, seen from both sides (its cards are single faces).
static func _both_sides(mesh: Mesh) -> StandardMaterial3D:
	var m: StandardMaterial3D = (mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


func _cutout(tex: Texture2D, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.7
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


## A cloud of each kind once, out of sight, so the first bush stripped does not
## stall on setting them up.
func _warm_up() -> void:
	_puff(Vector3(0, -900, 0), 1.0)


static func _rand(seed_value: int, i: int, salt: int) -> float:
	var h := (seed_value * 73856093) ^ (i * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFFFF) / float(0x1000000)


# ------------------------------------------------------------------ where they stand

func _square_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / spacing)), int(floor(p.z / spacing)))


## Where the bush in a square would stand, and whether one stands there at all.
func _site(square: Vector2i) -> Variant:
	var seed_value := square.x * 92821 + square.y * 68917
	if _rand(seed_value, 0, 41) > share:
		return null
	var x := (float(square.x) + 0.15 + 0.7 * _rand(seed_value, 0, 42)) * spacing
	var z := (float(square.y) + 0.15 + 0.7 * _rand(seed_value, 0, 43)) * spacing
	var s := _field.sample(x, z)
	if not bool(s.get("on_land", false)):
		return null
	var surface := String(s.get("surface", ""))
	if surface == "rock" or surface == "sand" or float(s.get("slope", 0.0)) > 0.35 \
			or float(s.get("flatten", 0.0)) > 0.3 or float(s.get("flow_weight", 0.0)) > 0.25:
		return null
	if Vector2(x, z).distance_to(SwordStone.site(_field)) < SwordStone.MEADOW * 0.6:
		return null
	return Vector3(x, float(s["height"]) - 0.06, z)


func _stand(square: Vector2i, at: Vector3) -> Node3D:
	var seed_value := square.x * 92821 + square.y * 68917
	var bush := Node3D.new()
	var scale_by := lerpf(0.75, 1.15, _rand(seed_value, 0, 44))
	bush.transform = Transform3D(Basis(Vector3.UP, _rand(seed_value, 0, 45) * TAU).scaled(Vector3.ONE * scale_by), at)
	var bare := MeshInstance3D.new()
	bare.name = "Bare"
	bare.mesh = _bare
	bare.material_override = _bare_mat
	bare.visible = _stripped.has(square)
	bush.add_child(bare)
	var leafy := MeshInstance3D.new()
	leafy.name = "Leafy"
	leafy.mesh = _leafy
	leafy.material_override = _leafy_mat
	leafy.visible = not _stripped.has(square)
	bush.add_child(leafy)
	bush.set_meta(&"square", square)
	add_child(bush)
	return bush


func _process(_delta: float) -> void:
	if _explorer == null:
		return
	var here := _explorer.global_position
	var square := _square_of(here)
	if square != _at_square:
		_at_square = square
		var reach_squares := int(ceil(view_range / spacing))
		var wanted := {}
		for dz in range(-reach_squares, reach_squares + 1):
			for dx in range(-reach_squares, reach_squares + 1):
				var sq := square + Vector2i(dx, dz)
				if Vector2((float(sq.x) + 0.5) * spacing - here.x, (float(sq.y) + 0.5) * spacing - here.z).length() > view_range + spacing:
					continue
				wanted[sq] = true
				if not _live.has(sq) and not _todo.has(sq):
					_todo.append(sq)
		for sq in _live.keys():
			if not wanted.has(sq):
				if _live[sq] != null:
					(_live[sq] as Node).queue_free()
				_live.erase(sq)
	# A few squares a frame: asking the ground what it is is not free.
	for i in mini(_todo.size(), 3):
		var sq: Vector2i = _todo.pop_front()
		if _live.has(sq):
			continue
		var at: Variant = _site(sq)
		_live[sq] = _stand(sq, at) if at != null else null


# ------------------------------------------------------------------ being hit

## A swing from `from` along `dir`. True if it met a bush. One in leaf is
## stripped: its leaves go in a cloud and its berries into the bag.
func strike(from: Vector3, dir: Vector3) -> bool:
	var a := Vector2(from.x, from.z)
	var d := Vector2(dir.x, dir.z)
	d = d.normalized() if d.length() > 0.001 else Vector2.ZERO
	for sq in _live:
		var bush: Node3D = _live[sq]
		if bush == null:
			continue
		var p := Vector2(bush.global_position.x, bush.global_position.z)
		var t := clampf((p - a).dot(d), 0.0, reach)
		if (a + d * t).distance_to(p) > 1.25 * bush.scale.x or absf(from.y - bush.global_position.y - 1.2) > 2.6:
			continue
		var leafy := bush.get_node("Leafy") as MeshInstance3D
		if leafy.visible:
			leafy.visible = false
			(bush.get_node("Bare") as MeshInstance3D).visible = true
			_stripped[sq] = true
			_puff(bush.global_position + Vector3(0, 1.3 * bush.scale.y, 0), bush.scale.x)
			if _inventory != null:
				_inventory.call(&"add", "berry", _rng.randi_range(berries.x, berries.y))
		return true
	return false


## The cloud a stripped bush leaves: its leaves thrown out and fluttering down,
## its berries dropping through them.
func _puff(at: Vector3, size: float) -> void:
	for kind in 2:
		var p := GPUParticles3D.new()
		p.amount = 110 if kind == 0 else 22
		p.lifetime = 2.6 if kind == 0 else 1.4
		p.one_shot = true
		p.explosiveness = 0.95
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = 1.05 * size
		m.direction = Vector3.UP
		m.spread = 180.0
		m.initial_velocity_min = 0.6 if kind == 0 else 1.0
		m.initial_velocity_max = 3.2 if kind == 0 else 3.6
		# Leaves are held up by the air and come down slowly, turning; berries fall.
		m.gravity = Vector3(0, -1.9 if kind == 0 else -9.0, 0)
		m.damping_min = 1.2 if kind == 0 else 0.0
		m.damping_max = 2.4 if kind == 0 else 0.2
		m.angle_min = 0.0
		m.angle_max = 360.0
		m.angular_velocity_min = -260.0
		m.angular_velocity_max = 260.0
		m.scale_min = 0.6
		m.scale_max = 1.3
		m.anim_offset_min = 0.0
		m.anim_offset_max = 1.0
		p.process_material = m
		var quad := QuadMesh.new()
		quad.size = Vector2(0.2, 0.2) if kind == 0 else Vector2(0.16, 0.16)
		p.draw_pass_1 = quad
		p.material_override = _leaf_puff if kind == 0 else _berry_puff
		p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
		add_child(p)
		p.global_position = at
		p.emitting = true
		get_tree().create_timer(p.lifetime + 0.6).timeout.connect(p.queue_free)
