class_name ForestMushrooms
extends Node3D

# FLY AGARICS IN THE GIANT FOREST, island 003 (the user: "add patches fo these
# mushrooms too in the new forest"). Patches of the user's five fly agarics (cut
# off their green by tools/TOOL_cut_chroma_key.py, crunched to 64 px by
# SCRIPT_crunch_art.gd), placed once from `patch_seed` when the scene stands, in
# two kinds:
#
#   * ON THE VERGES of the trails, where they can be seen: the trails are the
#     only ground the ferns leave bare, so a patch out in the wood is half hidden
#     in them and a patch beside the path is the one you walk past. Every
#     `verge_every`th piece of trail rolls `verge_chance` for a patch on one side
#     of it, `verge_offset` out from its edge.
#   * IN THE WOOD: one try a `patch_cell`, `patch_chance` of them a patch.
#
# A patch is `per_patch` mushrooms within `patch_radius` of its middle, the
# biggest in the middle and smaller out to its edge (`edge_size`), each
# `height` metres tall at full size, each a picture of the five at random. A
# mushroom stands only on the land, off every hole and pad, off a ruin's
# footprint, and off a trail's tread (it may stand on its verge, which the
# plants leave bare). Every number is rolled for every try whatever the ground
# turns out to be, so one patch's ground never moves another patch.
#
# DRAWN as the island's ferns are: SHADER_veg_billboard on a duplicate of
# `material` (the fern material) a picture, lit and fogged as the ferns, each
# mushroom dithered away by its own distance toward `draw_range`. One MultiMesh a
# picture in each `block`-metre square, culled whole once all of it is past
# `draw_range`, so only the few blocks round the eye are ever submitted.
#
# A child of the scene's root, so the floating origin carries it.

const PICTURES: Array[Texture2D] = [
	preload("res://sprites/vegetation/SPRITE_fly_agaric_1_64.png"),
	preload("res://sprites/vegetation/SPRITE_fly_agaric_2_64.png"),
	preload("res://sprites/vegetation/SPRITE_fly_agaric_3_64.png"),
	preload("res://sprites/vegetation/SPRITE_fly_agaric_4_64.png"),
	preload("res://sprites/vegetation/SPRITE_fly_agaric_5_64.png"),
]
## How far into the ground a mushroom is set, metres: its foot buried, not on it.
const SINK := 0.03
## The heaviest a trail's weight may be where a mushroom stands: its verge, not
## its tread (`IslandField.zone_at`, 1 across the tread, falling over the bank).
const TREAD := 0.85

## The IslandWorld: its field and its ground.
@export var world_path: NodePath
## The material the ferns draw with; each picture gets a duplicate.
@export var material: ShaderMaterial

@export_group("Patches")
@export var patch_seed := 1520
## Metres between the tries in the wood.
@export var patch_cell := 55.0
## The share of tries in the wood that are patches.
@export_range(0.0, 1.0) var patch_chance := 0.5
## A wood patch's radius, metres, between these.
@export var patch_radius := Vector2(1.2, 3.2)
## Mushrooms a patch, between these.
@export var per_patch := Vector2i(5, 14)
## A mushroom's height at full size, metres, between these.
@export var height := Vector2(0.45, 0.95)
## How much smaller a mushroom is at a patch's edge than at its middle.
@export_range(0.0, 0.9) var edge_size := 0.4

@export_group("Verges")
## Every this many pieces of trail rolls for a patch beside it.
@export var verge_every := 3
@export_range(0.0, 1.0) var verge_chance := 0.45
## A verge patch's middle, metres out from the trail's edge, between these.
@export var verge_offset := Vector2(0.6, 2.4)
## A verge patch's radius, metres, between these.
@export var verge_radius := Vector2(0.7, 1.8)

@export_group("Drawing")
## Metres a side of the squares the mushrooms are drawn in.
@export var block := 256.0
## Metres from the eye past which a block is not drawn.
@export var draw_range := 110.0

var _world: Node = null
# [{"at": Vector2 (the field's frame), "radius", "count", "verge": bool}]
var _patches: Array[Dictionary] = []
var _count := 0
var _blocks: Array[MultiMeshInstance3D] = []
# Every mushroom's transform, in this node's frame (a headless renderer keeps no
# MultiMesh data to read back).
var _placed: Array[Transform3D] = []


func _ready() -> void:
	_world = get_node_or_null(world_path)
	_grow()


## The patches grown: [{"at" (the field's frame), "radius", "count", "verge"}].
func patches() -> Array[Dictionary]:
	return _patches


## Mushrooms standing, all told.
func mushroom_count() -> int:
	return _count


## The MultiMeshes they are drawn with, one a picture a block.
func blocks() -> Array[MultiMeshInstance3D]:
	return _blocks


## Every mushroom's transform, in this node's frame: what the MultiMeshes hold.
func mushrooms() -> Array[Transform3D]:
	return _placed


func _grow() -> void:
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
	var rng := RandomNumberGenerator.new()
	rng.seed = patch_seed
	var ruins := field.ruins_for(hub)
	var outer := field.ruin_outer_radius()
	var zi: Array = [IslandField.ZONE_ROUGH, 0.0, 0, 1e9, 0.0]
	# picture -> block key -> [Transform3D]
	var placed: Array[Dictionary] = []
	for _i in PICTURES.size():
		placed.append({})

	# On the verges of the trails.
	var trails := field.trails(hub)
	var girth := field.trail_width * (1.0 + field.zone_irregularity)
	for i in range(0, trails.size(), maxi(verge_every, 1)):
		var zn: IslandField.Zone = trails[i]
		var roll := rng.randf()
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var t := rng.randf()
		var out := girth + rng.randf_range(verge_offset.x, verge_offset.y)
		var r := rng.randf_range(verge_radius.x, verge_radius.y)
		var seed_ := rng.randi()
		var dir := (zn.b - zn.a).normalized()
		if roll >= verge_chance or dir == Vector2.ZERO:
			continue
		var c := zn.a.lerp(zn.b, t) + Vector2(-dir.y, dir.x) * side * out
		_patch(c, r, seed_, true, field, hub, ruins, outer, zi, placed)

	# And in the wood.
	var reach := hub.radius * (1.0 + field.coast_irregularity)
	var n := int(ceil(reach * 2.0 / patch_cell))
	for iz in n:
		for ix in n:
			var c := hub.center + Vector2(-reach, -reach) \
					+ (Vector2(ix, iz) + Vector2(rng.randf(), rng.randf())) * patch_cell
			var roll := rng.randf()
			var r := rng.randf_range(patch_radius.x, patch_radius.y)
			var seed_ := rng.randi()
			if roll >= patch_chance:
				continue
			_patch(c, r, seed_, false, field, hub, ruins, outer, zi, placed)

	_draw(placed)


func _patch(c: Vector2, r: float, seed_: int, verge: bool, field: IslandField,
		hub: IslandField.Island, ruins: Array, outer: float, zi: Array,
		placed: Array[Dictionary]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var want := rng.randi_range(per_patch.x, per_patch.y)
	var off := _offset()
	var grown := 0
	for i in want:
		# The first at the middle, the rest out to the edge.
		var d := 0.0 if i == 0 else r * sqrt(rng.randf())
		var q := c + Vector2.from_angle(rng.randf() * TAU) * d
		var h := rng.randf_range(height.x, height.y) * lerpf(1.0, 1.0 - edge_size, d / maxf(r, 0.01))
		var pic := rng.randi_range(0, PICTURES.size() - 1)
		if not stands(field, hub, q, ruins, outer, zi):
			continue
		var at := Vector3(q.x, 0.0, q.y) - off
		at.y = float(_world.call(&"height_at", at, -1e9))
		if at.y < -1e8:
			continue
		at.y -= SINK
		var key := Vector2i(floori(q.x / block), floori(q.y / block))
		var bucket: Dictionary = placed[pic]
		if not bucket.has(key):
			bucket[key] = []
		(bucket[key] as Array).append(Transform3D(Basis.from_scale(Vector3(h, h, h)), at))
		grown += 1
	if grown > 0:
		_patches.append({"at": c, "radius": r, "count": grown, "verge": verge})
		_count += grown


## May a mushroom stand at `q` (the field's frame): on the land, off every hole
## and pad, off every ruin's footprint, and off a trail's tread?
static func stands(field: IslandField, hub: IslandField.Island, q: Vector2, ruins: Array,
		outer: float, zi: Array) -> bool:
	if field.mask_for(hub, q.x, q.y) < 0.08:
		return false
	for s in ruins:
		if q.distance_to((s as IslandField.RuinSite).center) < outer + 2.0:
			return false
	var w := field.zone_at(q.x, q.y, field.zones_near(hub, q.x, q.y), zi)
	if int(zi[0]) == IslandField.ZONE_PATH:
		return w <= TREAD
	return w <= 0.02


func _offset() -> Vector3:
	if _world != null and _world.has_method(&"origin_offset"):
		var o: Vector3 = _world.call(&"origin_offset")
		return Vector3(o.x, 0.0, o.z)
	return Vector3.ZERO


func _draw(placed: Array[Dictionary]) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	# Standing on its foot, as the scatter's plants do.
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	for pi in PICTURES.size():
		var mat: ShaderMaterial = material.duplicate() if material != null else ShaderMaterial.new()
		mat.set_shader_parameter(&"albedo_tex", PICTURES[pi])
		# Each mushroom dithers away by its own distance over the last third of
		# `draw_range`; the block is culled whole once all of it is past that.
		mat.set_shader_parameter(&"far_start", draw_range * 0.7)
		mat.set_shader_parameter(&"far_end", draw_range)
		var bucket: Dictionary = placed[pi]
		for key in bucket:
			var xfs: Array = bucket[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			# The billboard reads INSTANCE_CUSTOM.x as a baked burn: 0, none.
			mm.use_custom_data = true
			mm.mesh = quad
			mm.instance_count = xfs.size()
			for i in xfs.size():
				var xf := global_transform.affine_inverse() * (xfs[i] as Transform3D)
				mm.set_instance_transform(i, xf)
				_placed.append(xf)
				mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "FlyAgaric%d_%d_%d" % [pi + 1, (key as Vector2i).x, (key as Vector2i).y]
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# The card turns to the eye, out of the quad's own flat bounds.
			mmi.extra_cull_margin = 1.0
			# Measured to the block's middle, so the reach of its corner past that.
			mmi.visibility_range_end = draw_range + block * 0.71
			add_child(mmi)
			_blocks.append(mmi)
