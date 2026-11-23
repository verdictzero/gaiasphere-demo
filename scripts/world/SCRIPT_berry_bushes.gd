class_name BerryBushes
extends Node3D

# BERRY BUSHES: a viburnum in leaf and hung with red berries, here and there in
# the wood. Hit one (axe, sword, anything swung) and it is stripped: the leaves
# and berries go up in a cloud, the bare bush is left standing, and a handful of
# berries goes into the bag.
#
# THE BUSH IS TWO MODELS (assets/berry_bush): the viburnum in leaf and berry, and
# the same bush bare. Each stands as the first until it is hit and as the second
# after. The cloud between them is single leaves (the drawn leaf atlas).
#
# THEY ARE DRAWN AS TWO MULTIMESHES, however many there are: one of every bush
# in leaf, one of every bare one, each instance carrying how much of it is there
# (the leaves' fade back in). Both sway in the wind with the rest of the wood.
#
# ONLY THE ONES NEAR THE PLAYER EXIST. The island is divided into squares of
# `spacing` metres; a hash of the square says whether a bush stands in it and
# where, and the ground decides whether it may (grass or soil, not water, sand,
# rock, a steep slope or a path). Squares coming within `range` of the player get
# their bush; squares left behind lose it. What has been stripped is remembered
# by square, with the day it happened: three days on, once the player is not
# looking at it, its leaves dither back in.

@export var world_path: NodePath = ^"../GaiaSphere"
@export var explorer_path: NodePath = ^"../Explorer"
@export var inventory_path: NodePath = ^"../Inventory"
## The side of a square, metres: at most one bush in each.
@export var spacing := 34.0
## The share of squares that hold a bush where the ground allows.
@export_range(0.0, 1.0) var share := 0.32
## How far from the player bushes exist, metres.
@export var view_range := 130.0
## How near a swing has to come, metres.
@export var reach := 3.2
## Days (of the game's clock) before a stripped bush is in leaf and berry again.
## It never starts while the player is looking at it: only once the bush is out
## of view (`out_of_view` degrees or more off where the camera points) or too far
## away to exist. Then its leaves dither back in over `regrow_fade` seconds.
@export var regrow_days := 3.0
@export var out_of_view := 62.0
@export var regrow_fade := 3.5
## Berries a bush gives: fewest and most.
@export var berries := Vector2i(3, 7)
## Metres at which a bush in leaf steps down to its next coarser model (a phone
## steps down sooner).
@export var lod_distances: Array[float] = [8.0, 16.0, 28.0, 48.0, 80.0]

var _world: Node
var _field: IslandField
var _explorer: Node3D
var _inventory: Node
var _bare: Mesh
var _bare_mat: ShaderMaterial
var _leafy_mm: MultiMesh
var _bare_mm: MultiMesh
var _leafy_slot := {}            # square -> [level of detail, its instance in that level's MultiMesh]
var _leafy_mms: Array[MultiMesh] = []      # one to a level of detail
var _filled_at := Vector3(1e9, 0, 0)       # where the player was when the levels were last dealt out
var _stale := true               # the MultiMeshes need filling again
var _leafy: Mesh
var _leafy_mat: ShaderMaterial
var _growing := {}               # square -> how far its leaves have come back, 0..1
var _live := {}                  # square -> where its bush stands (a Transform3D), or null where none does
var _stripped := {}              # square -> the day (and part of a day) it was stripped
var _enviro: Node
var _days := 0.0                 # whole days gone by since the game began
var _hour_was := -1.0
var _regrow_check := 0.0
var _at_square := Vector2i(1 << 30, 0)
var _leaf_mat: StandardMaterial3D
var _leaf_puff: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _todo: Array = []            # squares still to look at


func _ready() -> void:
	_world = get_node_or_null(world_path)
	_explorer = get_node_or_null(explorer_path)
	_inventory = get_node_or_null(inventory_path)
	_enviro = get_node_or_null(^"../Enviro")
	if _world == null or not _world.has_method(&"get_field"):
		set_process(false)
		return
	_field = _world.call(&"get_field")
	_rng.randomize()
	_bare = _model("res://assets/berry_bush/viburnum_bush_bare.glb")
	_leafy = _model("res://assets/berry_bush/viburnum_bush.glb")
	_leafy_mat = _bush_material(_leafy)
	_bare_mat = _bush_material(_bare)
	# The bare twigs are a cool grey-violet in the photograph, which the sky's
	# light turns blue in shade: brought down to the brown of the wood round it.
	_bare_mat.set_shader_parameter("tint", Color(0.62, 0.5, 0.4))
	_bare_mat.set_shader_parameter("backlight", Color(0, 0, 0))
	_bare_mat.set_shader_parameter("wind_flutter", 0.015)
	# THE BUSH IN LEAF COMES AT SIX FINENESSES (tools/build_berry_bush_domes.py):
	# five thousand triangles of small domes close to, under a hundred of flat
	# cards far off. Each bush is drawn at the one its distance calls for, all the
	# bushes at a level in one MultiMesh, and all in the first one's material.
	_leafy_mm = _multimesh(_leafy, _leafy_mat, "Leafy")
	_leafy_mms = [_leafy_mm]
	for level in range(1, lod_distances.size() + 1):
		var path := "res://assets/berry_bush/viburnum_bush_lod%d.glb" % level
		if not ResourceLoader.exists(path):
			break
		_leafy_mms.append(_multimesh(_model(path), _leafy_mat, "Leafy%d" % level))
	if OS.has_feature("mobile"):
		for i in lod_distances.size():
			lod_distances[i] *= 0.65
	_bare_mm = _multimesh(_bare, _bare_mat, "Bare")
	_leaf_mat = _cutout(load("res://assets/leaves/berry_leaves_atlas.png"), Color(0.78, 0.9, 0.7))
	_leaf_mat.backlight_enabled = true
	_leaf_mat.backlight = Color(0.16, 0.24, 0.06)
	_leaf_puff = _leaf_mat.duplicate()
	_leaf_puff.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_leaf_puff.particles_anim_h_frames = 4
	_leaf_puff.particles_anim_v_frames = 4
	_leaf_puff.particles_anim_loop = false
	call_deferred(&"_warm_up")


static func _model(path: String) -> Mesh:
	var scene: Node = (load(path) as PackedScene).instantiate()
	var found: Mesh = null
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		found = (n as MeshInstance3D).mesh
		break
	scene.free()
	return found


## The model's own pictures in the bush shader (both sides, wind, the fade).
static func _bush_material(mesh: Mesh) -> ShaderMaterial:
	var as_made := mesh.surface_get_material(0) as StandardMaterial3D
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/SHADER_berry_bush.gdshader")
	m.set_shader_parameter("albedo_tex", as_made.albedo_texture)
	m.set_shader_parameter("normal_tex", as_made.normal_texture)
	m.set_shader_parameter("height", mesh.get_aabb().size.y)
	return m


func _multimesh(mesh: Mesh, mat: Material, called: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.name = called
	mmi.multimesh = mm
	mmi.material_override = mat
	# Never culled as one: its bushes are all round the player, wherever that is.
	mmi.extra_cull_margin = 16384.0
	add_child(mmi)
	return mm


## Both MultiMeshes filled from what stands and what state each is in.
func _fill() -> void:
	_stale = false
	var here := _explorer.global_position if _explorer != null else Vector3.ZERO
	_filled_at = here
	var levels: Array = []
	for i in _leafy_mms.size():
		levels.append([])
	var bare: Array = []
	_leafy_slot.clear()
	for sq in _live:
		if _live[sq] == null:
			continue
		var growing := _growing.has(sq)
		if not _stripped.has(sq) or growing:
			# Which fineness: by how far off it stands.
			var away := ((_live[sq] as Transform3D).origin - here).length()
			var level := 0
			while level < _leafy_mms.size() - 1 and level < lod_distances.size() and away > lod_distances[level]:
				level += 1
			_leafy_slot[sq] = [level, (levels[level] as Array).size()]
			(levels[level] as Array).append([_live[sq], float(_growing[sq]) if growing else 1.0])
		if _stripped.has(sq) or growing:
			bare.append([_live[sq], 1.0])
	var pairs: Array = [[_bare_mm, bare]]
	for i in _leafy_mms.size():
		pairs.append([_leafy_mms[i], levels[i]])
	for pair in pairs:
		var mm: MultiMesh = pair[0]
		var list: Array = pair[1]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_custom_data(i, Color(float(list[i][1]), 0, 0, 0))


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
	for zone in _cleared:
		var at: Vector3 = (zone[0] as Transform3D) * Vector3(x, (zone[2] as Vector3).y, z)
		if absf(at.x) <= (zone[1] as Vector2).x and absf(at.z) <= (zone[1] as Vector2).y:
			return null
	return Vector3(x, float(s["height"]) - 0.06, z)


var _cleared: Array = []


## Ground that has been built on (see Flora.clear_ground): no berry bush stands
## there from now on, and one that did is gone.
func clear_ground(frame: Transform3D, half: Vector2) -> void:
	var inv := frame.affine_inverse()
	_cleared.append([inv, half, frame.origin])
	for sq in _live.keys():
		if _live[sq] == null:
			continue
		var at: Vector3 = inv * Vector3((_live[sq] as Transform3D).origin.x, frame.origin.y, (_live[sq] as Transform3D).origin.z)
		if absf(at.x) <= half.x and absf(at.z) <= half.y:
			_live[sq] = null
			_stale = true


func _stand(square: Vector2i, at: Vector3) -> Transform3D:
	var seed_value := square.x * 92821 + square.y * 68917
	var scale_by := lerpf(0.75, 1.15, _rand(seed_value, 0, 44))
	return Transform3D(Basis(Vector3.UP, _rand(seed_value, 0, 45) * TAU).scaled(Vector3.ONE * scale_by), at)


## The day and the part of it gone, counted from the start of the game. The
## clock's hour runs 0 to 24 and starts again: each time it does is a day.
func today() -> float:
	return _days + (float(_enviro.get("hour")) / 24.0 if _enviro != null else 0.0)


func _process(delta: float) -> void:
	if _explorer == null:
		return
	var here := _explorer.global_position
	if _enviro != null:
		var hour := float(_enviro.get("hour"))
		if _hour_was >= 0.0 and hour < _hour_was - 12.0:
			_days += 1.0
		_hour_was = hour
	# REGROWTH, looked at once a second: a bush stripped `regrow_days` ago starts
	# to come back, but never while the player is looking at it.
	_regrow_check -= delta
	if _regrow_check <= 0.0 and not _stripped.is_empty():
		_regrow_check = 1.0
		var now := today()
		for sq in _stripped.keys():
			if _growing.has(sq) or now - float(_stripped[sq]) < regrow_days:
				continue
			var stands: Variant = _live.get(sq)
			if stands != null and _in_view((stands as Transform3D).origin + Vector3(0, 1.2, 0)):
				continue
			if stands != null:
				# Its leaves come in over the bare bush, which stays until they are whole.
				_growing[sq] = 0.0
				_stale = true
			else:
				_stripped.erase(sq)
	for sq in _growing.keys():
		if _live.get(sq) == null:
			_growing.erase(sq)
			_stripped.erase(sq)
			continue
		var grown := minf(float(_growing[sq]) + delta / maxf(regrow_fade, 0.01), 1.0)
		_growing[sq] = grown
		if grown >= 1.0:
			_growing.erase(sq)
			_stripped.erase(sq)
			_stale = true
		elif _leafy_slot.has(sq) and not _stale and _leafy_mm != null:
			_leafy_mms[int(_leafy_slot[sq][0])].set_instance_custom_data(int(_leafy_slot[sq][1]), Color(grown, 0, 0, 0))
	# Walked a few steps: the bushes are dealt out to their levels again.
	if here.distance_to(_filled_at) > 2.5:
		_stale = true
	if _stale and _leafy_mm != null:
		_fill()
	if _field == null:
		return
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
					_stale = true
				_live.erase(sq)
	# A few squares a frame: asking the ground what it is is not free.
	for i in mini(_todo.size(), 3):
		var sq: Vector2i = _todo.pop_front()
		if _live.has(sq):
			continue
		var at: Variant = _site(sq)
		_live[sq] = _stand(sq, at) if at != null else null
		if at != null:
			_stale = true
	if _stale:
		_fill()


## Whether the player is looking toward a point: within `out_of_view` degrees of
## where the camera points (the player's own facing, where there is no camera).
func _in_view(at: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye: Node3D = cam if cam != null else _explorer
	var to := at - eye.global_position
	if to.length() < 0.5:
		return true
	return (-eye.global_basis.z).dot(to.normalized()) > cos(deg_to_rad(out_of_view))


# ------------------------------------------------------------------ being hit

## A swing from `from` along `dir`. True if it met a bush. One in leaf is
## stripped: its leaves go in a cloud and its berries into the bag.
func strike(from: Vector3, dir: Vector3) -> bool:
	var a := Vector2(from.x, from.z)
	var d := Vector2(dir.x, dir.z)
	d = d.normalized() if d.length() > 0.001 else Vector2.ZERO
	for sq in _live:
		if _live[sq] == null:
			continue
		var bush: Transform3D = _live[sq]
		var size := bush.basis.get_scale().x
		var p := Vector2(bush.origin.x, bush.origin.z)
		var t := clampf((p - a).dot(d), 0.0, reach)
		if (a + d * t).distance_to(p) > 1.25 * size or absf(from.y - bush.origin.y - 1.2) > 2.6:
			continue
		if not _stripped.has(sq):
			_stripped[sq] = today()
			_stale = true
			_puff(bush.origin + Vector3(0, 1.3 * size, 0), size)
			if _inventory != null:
				_inventory.call(&"add", "berry", _rng.randi_range(berries.x, berries.y))
		return true
	return false


## The cloud a stripped bush leaves: its leaves thrown out and fluttering down.
func _puff(at: Vector3, size: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = 110
	p.lifetime = 2.6
	p.one_shot = true
	p.explosiveness = 0.95
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 1.05 * size
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 3.2
	# Leaves are held up by the air and come down slowly, turning.
	m.gravity = Vector3(0, -1.9, 0)
	m.damping_min = 1.2
	m.damping_max = 2.4
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
	quad.size = Vector2(0.2, 0.2)
	p.draw_pass_1 = quad
	p.material_override = _leaf_puff
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.6).timeout.connect(p.queue_free)
