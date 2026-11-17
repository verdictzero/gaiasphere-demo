class_name ForestFog
extends Node3D

# THE FOG OF THE GIANT FOREST, island 003 (the user: "i want a 'giant foggy forest
# biome' really lean into fog, ok, if sky becomes a dark neutral color accompanying
# / complimenting the fog so the fog fades into it, think dark, foggy, ancient,
# huge forest"; and "make soft edge noise based fog particles and have areas of
# fog particles to compliment the fog"). Two things, neither a node per particle:
#
#   * THE FOG ITSELF, everywhere and always: the desert storm's dust wall
#     (SHADER_weather_dust, DesertWeather's) turned to a dark neutral and never
#     cleared. One quad over the screen, drawn first of the transparent pass, laying
#     fog over everything opaque already drawn by how far off it is — the ground,
#     the trees, the golf machines, the foes, the sky — thick at the ground and
#     thinning with height (`height_falloff`), so the crowns of the giants stand up
#     out of the thickest of it and the sky overhead shows through, dark, while
#     the horizon is all fog. Slow billows roll through it (`billow`, `wind`).
#     Its colour is the haze family's, the neutral 0.30 times `tod_haze_tint`:
#     what the island's sky cycle (SKYCYCLE_003_forest.tres) makes dark grey, so
#     the fog and the sky are one colour where they meet.
#
#   * FOG BANKS, here and there: soft-edged clouds of noise standing in the wood
#     (SHADER_fog_bank), a bank a few dozen puffs drifting together. Placed once,
#     from `bank_seed`: one try a `bank_cell`, `bank_chance` of them a bank of
#     `bank_radius`, its puffs `puff_spacing` apart, `puff_size` across and
#     `puff_height` over the ground under them. A bank is one MultiMesh, drawn
#     within `bank_range` of the eye.
#
# A child of the scene's root, so the floating origin carries the banks and the
# surface's hold (underground, in a fight) hides all of it.

const WALL_SHADER := preload("res://shaders/SHADER_weather_dust.gdshader")
const BANK_SHADER := preload("res://shaders/SHADER_fog_bank.gdshader")

## The IslandWorld: the ground under the camera and under every bank.
@export var world_path: NodePath

@export_group("The fog")
## Extinction per metre at the ground: you see about 3 / this far.
@export var density := 0.015
## Metres over which it thins by e going up.
@export var height_falloff := 65.0
## Its colour before the haze tint: the neutral every fog here is pinned to.
@export var color := Color(0.3, 0.3, 0.3)
## How much the billows move it about, 0 smooth.
@export_range(0.0, 1.0) var billow := 0.45
## The billows' drift, metres a second.
@export var wind := Vector3(0.7, 0.0, 0.3)

@export_group("Fog banks")
@export var bank_seed := 152
## Metres between the tries.
@export var bank_cell := 180.0
## The share of tries that are banks.
@export_range(0.0, 1.0) var bank_chance := 0.5
## A bank's radius, metres, between these.
@export var bank_radius := Vector2(22.0, 55.0)
## Metres between a bank's puffs.
@export var puff_spacing := 9.0
## A puff's width, metres, between these.
@export var puff_size := Vector2(10.0, 22.0)
## A puff's middle over the ground, metres, between these.
@export var puff_height := Vector2(1.5, 8.0)
## Metres from the eye past which a bank is not drawn.
@export var bank_range := 240.0

@export_group("Fog bank look")
## SHADER_fog_bank.gdshader's numbers, per island; the defaults are island 003's
## wisps standing in the wood.
## Opacity at a puff's thickest. Lower, and the overlap of many is what thickens a
## bank, so it reads as one cloud rather than a heap of balls.
@export_range(0.0, 1.0) var puff_opacity := 0.42
## The colour over the fog's neutral and the haze tint.
@export var puff_tint := Color(1.18, 1.18, 1.2)
## Where a puff's edge starts falling off (share of its radius) and how much
## the noise rags it; how wide its body's ramp from clear to thick is.
@export_range(0.0, 0.9) var puff_edge_inner := 0.25
@export_range(0.0, 0.6) var puff_edge_ragged := 0.35
@export_range(0.05, 0.5) var puff_body_width := 0.25
## Width over height: over 1, low wide billows rather than balls.
@export_range(0.5, 4.0) var puff_aspect := 1.0
## Metres over which a puff thins away where it meets the ground behind it.
@export var puff_soft_depth := 3.0
## Whole nearer than x, gone past y, metres from the eye.
@export var puff_far_fade := Vector2(140.0, 210.0)
## Gone nearer than x and whole past y TIMES ITS WIDTH from a puff's middle (0:
## off), so a puff big enough to walk into thins round you rather than cutting
## the view with its card.
@export var puff_near_scale := Vector2.ZERO
## Drawn after everything at a lower priority. THE CLOUD SEA is at 0 and sorts
## as the nearest thing there is (its quad hangs under the eye), so a bank at 0
## standing at the coast had the sea drawn over it: 1 puts every bank in front.
## (It cannot be the other way: no bank stands under the deck.)
@export var bank_priority := 1

var _wall: MeshInstance3D = null
var _wall_mat: ShaderMaterial = null
var _bank_mat: ShaderMaterial = null
var _world: Node = null
var _ground := 0.0
var _ground_ok := false
var _drift := Vector3.ZERO
var _banks: Array[MultiMeshInstance3D] = []
# Every puff's transform, in this node's frame (a headless renderer keeps no
# MultiMesh data to read back).
var _puffs: Array[Transform3D] = []


func _ready() -> void:
	_world = get_node_or_null(world_path)
	_build_wall()
	_build_banks()


## The fog banks standing, one MultiMesh each.
func banks() -> Array[MultiMeshInstance3D]:
	return _banks


## Every puff's transform, in this node's frame: what the banks' MultiMeshes hold.
func puffs() -> Array[Transform3D]:
	return _puffs


## The fog's material, for a harness.
func wall_material() -> ShaderMaterial:
	return _wall_mat


## The banks' material, for a harness.
func bank_material() -> ShaderMaterial:
	return _bank_mat


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _wall == null:
		return
	var at := cam.global_position
	_wall.global_position = at
	if _world != null and _world.has_method(&"height_at"):
		var h := float(_world.call(&"height_at", at, at.y - 2.0))
		_ground = h if not _ground_ok else lerpf(_ground, h, 0.1)
		_ground_ok = true
	_drift += wind * delta
	_wall_mat.set_shader_parameter(&"ground_y", _ground)
	_wall_mat.set_shader_parameter(&"drift", _drift)
	_wall_mat.set_shader_parameter(&"sky_distance", minf(cam.far, 4000.0))


func apply_origin_shift(shift: Vector3) -> void:
	_ground += shift.y


func _build_wall() -> void:
	_wall_mat = ShaderMaterial.new()
	_wall_mat.shader = WALL_SHADER
	_wall_mat.render_priority = -1
	_wall_mat.set_shader_parameter(&"amount", 1.0)
	_wall_mat.set_shader_parameter(&"density", density)
	_wall_mat.set_shader_parameter(&"height_falloff", height_falloff)
	_wall_mat.set_shader_parameter(&"base_color", Vector3(color.r, color.g, color.b))
	_wall_mat.set_shader_parameter(&"tint", Vector3.ONE)
	_wall_mat.set_shader_parameter(&"billow", billow)
	_wall_mat.set_shader_parameter(&"sun_glow", 0.0)
	_wall_mat.set_shader_parameter(&"light", 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	_wall = MeshInstance3D.new()
	_wall.name = "FogWall"
	_wall.mesh = quad
	_wall.material_override = _wall_mat
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.top_level = true
	add_child(_wall)


func _build_banks() -> void:
	if _world == null or not _world.has_method(&"get_field"):
		return
	var field: IslandField = _world.call(&"get_field")
	if field == null:
		return
	if not field._ready:
		field.prepare()
	var hub: IslandField.Island = field.island_in_cell(field.hub_cell())
	if hub == null:
		return
	_bank_mat = ShaderMaterial.new()
	_bank_mat.shader = BANK_SHADER
	_bank_mat.render_priority = bank_priority
	_bank_mat.set_shader_parameter(&"base_color", Vector3(color.r, color.g, color.b))
	_bank_mat.set_shader_parameter(&"opacity", puff_opacity)
	_bank_mat.set_shader_parameter(&"tint", Vector3(puff_tint.r, puff_tint.g, puff_tint.b))
	_bank_mat.set_shader_parameter(&"edge_inner", puff_edge_inner)
	_bank_mat.set_shader_parameter(&"edge_ragged", puff_edge_ragged)
	_bank_mat.set_shader_parameter(&"body_width", puff_body_width)
	_bank_mat.set_shader_parameter(&"aspect", puff_aspect)
	_bank_mat.set_shader_parameter(&"soft_depth", puff_soft_depth)
	_bank_mat.set_shader_parameter(&"far_fade", puff_far_fade)
	_bank_mat.set_shader_parameter(&"near_scale", puff_near_scale)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = bank_seed
	var reach := hub.radius * (1.0 + field.coast_irregularity)
	var n := int(ceil(reach * 2.0 / bank_cell))
	for iz in n:
		for ix in n:
			# Every number rolled for every cell, so one cell's ground never moves
			# another's bank.
			var c := hub.center + Vector2(-reach, -reach) \
					+ (Vector2(ix, iz) + Vector2(rng.randf(), rng.randf())) * bank_cell
			var roll := rng.randf()
			var r := rng.randf_range(bank_radius.x, bank_radius.y)
			var seed_ := rng.randi()
			if roll >= bank_chance or field.mask_for(hub, c.x, c.y) < 0.1:
				continue
			_bank(c, r, seed_, quad, field, hub)


func _offset() -> Vector3:
	if _world != null and _world.has_method(&"origin_offset"):
		var o: Vector3 = _world.call(&"origin_offset")
		return Vector3(o.x, 0.0, o.z)
	return Vector3.ZERO


func _bank(c: Vector2, r: float, seed_: int, quad: QuadMesh, field: IslandField,
		hub: IslandField.Island) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var count := clampi(int(PI * r * r / (puff_spacing * puff_spacing)), 6, 48)
	var xfs: Array[Transform3D] = []
	var custom: Array[Color] = []
	for i in count:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf())
		var size := rng.randf_range(puff_size.x, puff_size.y)
		var lift := rng.randf_range(puff_height.x, puff_height.y)
		var seed_f := rng.randf()
		var thick := rng.randf()
		if field.mask_for(hub, p.x, p.y) < 0.05:
			continue
		# The field's frame to the render frame: the island's origin offset, if
		# the world has been rebased before the banks stood.
		var at := Vector3(p.x, 0.0, p.y) - _offset()
		at.y = float(_world.call(&"height_at", at, 0.0)) + lift
		xfs.append(Transform3D(Basis.from_scale(Vector3.ONE * size), to_local(at)))
		custom.append(Color(seed_f, thick, 0.0, 0.0))
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_custom_data(i, custom[i])
	_puffs.append_array(xfs)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FogBank%d" % _banks.size()
	mmi.multimesh = mm
	mmi.material_override = _bank_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = puff_size.y * maxf(puff_aspect, 1.0) + 3.0
	mmi.visibility_range_end = bank_range
	add_child(mmi)
	_banks.append(mmi)
