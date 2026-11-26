class_name CliffRocks
extends Node3D

# SHARDS OF ROCK CROWDED AGAINST THE WALLS OF THE TABLELANDS (IslandField's
# mesa_*). A wall in a height field is a smooth sheet stretched between two
# levels; from any distance it reads as a ramp painted grey. So the walls are
# lined with rock, the way a real escarpment is: TALL, JAGGED SHARDS (the user:
# "more jagged, layered, almost no gaps, they can overlap, think tall aspect
# ratio shards"), several deep, the back ones pressed into the wall and standing
# to its top or over it, the front ones shorter and leaning out, all of them
# overlapping, so the wall disappears behind broken columns of stone.
#
# THE SHARDS are made here, not modelled (`shard_mesh`): an irregular five- to
# eight-sided column about five times as tall as it is wide, WIDER AT THE TOP THAN
# THE FOOT (the user: "wider at the top as a rule"), stepped out and in as it rises
# like stacked strata, drifting off true, its top broken off on a jagged slant,
# every face flat so every edge is sharp. A dozen of them, each
# handed down through every level of detail the simplifier makes (MeshLods). Their
# surface is the terrain's own rock (SHADER_cliff_rock.gdshader, with every value
# copied off the terrain's material), so where a shard goes into the wall the
# grain runs on across the join.
#
# WHERE: the island is searched once on a fine grid for wall; wherever it is one
# (not the island's outer edge, nor the middle the tablelands leave alone) a
# cluster of shards goes. That runs on a worker thread with its own copy of the
# field, and its answer is kept in user:// (keyed by everything that shapes it).
#
# DRAWN as MultiMeshes, one per shard and level of detail in each 256 m square,
# handed over by distance through a dither (SHADERINC_lod_fade); the last level
# at any distance: rocks never go. SOLID where the player is: a hull for each
# shard within `solid_reach`, gathered again as the player moves.

@export var world_path: NodePath = ^"../GaiaSphere"
@export var explorer_path: NodePath = ^"../Explorer"
## Metres between the points the walls are searched at.
@export var search_step := 3.5
## How steep (rise over run) the ground must be to count as a wall.
@export var wall_slope := 1.05
## Shards to a place on the wall, (least, most).
@export var cluster := Vector2i(3, 5)
## Height against the wall's: the back row's, and the front row's.
@export var back_height := Vector2(0.95, 1.3)
@export var front_height := Vector2(0.45, 0.8)
## A shard's width against its height (it is tall and thin).
@export var aspect := Vector2(0.17, 0.28)
@export var solid_reach := 60.0

## How many different shards are made.
const SHARDS := 12
const TILE := 256.0
const LOD_BAND := 0.12
const CACHE_VERSION := 9

var _field: IslandField
var _meshes: Array = []    # shard -> [lod meshes]
var _lod_ends: Array = []  # shard -> [distances]
var _hulls := {}           # shard -> hull points of a coarse level
var _material: ShaderMaterial
var _rocks: Array = []     # [shard, Transform3D]
var _task := -1
var _result: Array = []
var _solid: StaticBody3D
var _solid_at := Vector3(1e9, 0, 0)
var _explorer: Node3D


func _ready() -> void:
	var world := get_node_or_null(world_path)
	_explorer = get_node_or_null(explorer_path) as Node3D
	if world == null or not world.has_method(&"get_field"):
		return
	_field = world.call(&"get_field")
	if _field == null or not _field.mesa_enabled:
		set_process(false)
		return
	add_to_group(Prewarm.GROUP)
	for i in SHARDS:
		var lods: Array = MeshLods.chain(shard_mesh(i), 16)
		_meshes.append(lods)
		# A shard of the usual size, 25 m by 5: its finest level held to 25 m or so.
		_lod_ends.append(MeshLods.distances(lods.size(), 9.0, 1.7))
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/SHADER_cliff_rock.gdshader")
	var terrain := world.get(&"terrain_material") as ShaderMaterial
	if terrain != null:
		for p in ["ground_albedo", "ground_normal", "macro_noise", "rock_size", "rock_tint", "brightness",
				"macro_strength", "normal_strength", "triplanar_sharpness", "detail_distance"]:
			var v: Variant = terrain.get_shader_parameter(p)
			if v != null:
				_material.set_shader_parameter(p, v)
	var cached := _read_cache()
	if not cached.is_empty():
		_rocks = cached
		_build()
		return
	var copy := _field.clone()
	_task = WorkerThreadPool.add_task(func() -> void: _result = _layout(copy), false, "cliff rocks")


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_rocks = _result
		_write_cache(_rocks)
		_build()
	if _rocks.is_empty() or _explorer == null:
		return
	var here := _explorer.global_position
	if here.distance_to(_solid_at) > solid_reach * 0.4:
		_make_solid(here)


# ------------------------------------------------------------------ the shards

## Shard number `which`: a column one unit tall and about one across, its foot a
## little below 0 (it stands in the ground) and its broken tip about 1. Flat
## faces throughout. Made the same way every time for the same number.
static func shard_mesh(which: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5A4D + which * 7919
	var sides := rng.randi_range(5, 8)
	# The outline: uneven sides, uneven radii.
	var angles: Array = []
	for i in sides:
		angles.append((float(i) + rng.randf_range(-0.3, 0.3)) / float(sides) * TAU)
	var radii: Array = []
	for i in sides:
		radii.append(rng.randf_range(0.55, 1.0) * 0.34)     # (narrow at the foot: it widens upward)
	# The rings it rises through: narrowing, drifting, and here and there stepped
	# in (a stratum's ledge) or out (the next one standing proud).
	var rings: Array = []          # [y, scale, offset]
	var levels := rng.randi_range(7, 10)
	var scale := 1.0
	var off := Vector2.ZERO
	var drift := Vector2(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05))
	for k in levels:
		var t := float(k) / float(levels - 1)
		var y := lerpf(-0.08, 0.86, t) + (rng.randf_range(-0.02, 0.02) if k > 0 and k < levels - 1 else 0.0)
		if k > 0:
			# WIDER AT THE TOP, as a rule (the user's): it flares as it rises, a
			# stratum standing out over the one below now and then, and now and
			# then one tucked in under it.
			scale *= rng.randf_range(1.02, 1.08)
			if rng.randf() < 0.3:
				scale *= rng.randf_range(1.08, 1.18)        # a band standing out over the last
			elif rng.randf() < 0.15:
				scale *= rng.randf_range(0.9, 0.96)         # one tucked in under the next
			off += drift + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03))
		rings.append([y, scale, off, []])
	# Each ring's points, a little roughened.
	for ring: Array in rings:
		var pts: Array = ring[3]
		for i in sides:
			var r := float(radii[i]) * float(ring[1]) * rng.randf_range(0.92, 1.06)
			var a := float(angles[i]) + rng.randf_range(-0.05, 0.05)
			pts.append(Vector3(cos(a) * r + (ring[2] as Vector2).x, float(ring[0]), sin(a) * r + (ring[2] as Vector2).y))
	# The top broken off on a slant, up to a point set off the middle.
	var top: Array = rings[rings.size() - 1][3]
	var tilt := Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
	for i in sides:
		var q: Vector3 = top[i]
		top[i] = Vector3(q.x, q.y + tilt.dot(Vector2(q.x, q.z)) + rng.randf_range(-0.03, 0.03), q.z)
	var centre := Vector3.ZERO
	for q: Vector3 in top:
		centre += q
	centre /= float(sides)
	# (Broken off, not sharpened: a low point, the top a jagged slant.)
	var apex := centre + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.02, 0.08), rng.randf_range(-0.12, 0.12))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in rings.size() - 1:
		var lo: Array = rings[k][3]
		var hi: Array = rings[k + 1][3]
		var axis := Vector3((rings[k][2] as Vector2).x, 0.0, (rings[k][2] as Vector2).y)
		for i in sides:
			var j := (i + 1) % sides
			var out: Vector3 = ((lo[i] + lo[j] + hi[i]) / 3.0 - axis) * Vector3(1, 0, 1)
			_tri(st, lo[i], hi[i], lo[j], out)
			_tri(st, lo[j], hi[i], hi[j], out)
	for i in sides:
		_tri(st, top[i], apex, top[(i + 1) % sides], Vector3.UP)
	var base: Array = rings[0][3]
	var bottom := Vector3(0.0, -0.08, 0.0)
	for i in sides:
		_tri(st, base[(i + 1) % sides], bottom, base[i], Vector3.DOWN)
	return st.commit()


## One flat triangle, wound to face `outward` (roughly: away from the shard).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	# (Wound so the geometric normal points out, as Godot draws a SurfaceTool's
	# triangles: checked by eye, tests/RENDER_shards.gd.)
	if n.dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	for v: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


# ------------------------------------------------------------------ where

## Every shard: [which, transform]. A pure function of the field.
func _layout(field: IslandField) -> Array:
	var out: Array = []
	var isl: IslandField.Island = field.island_in_cell(field.hub_cell())
	if isl == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = field.world_seed ^ 0xC11FF
	var reach := isl.radius * 1.15
	var n := int(reach * 2.0 / search_step)
	var keep := field.mesa_keep + field.mesa_keep_ease * 0.3
	for j in n:
		for i in n:
			var p := isl.center + Vector2(-reach + (float(i) + rng.randf()) * search_step,
					-reach + (float(j) + rng.randf()) * search_step)
			if p.distance_to(isl.center) < keep:
				continue
			var m := field.mask_for(isl, p.x, p.y)
			if m < field.mesa_shore * 1.5:
				continue          # the island's own edge: its wall is not a tableland's
			var h := field.height_at(p.x, p.y, -1e9)
			var hx := field.height_at(p.x + 2.0, p.y, h)
			var hz := field.height_at(p.x, p.y + 2.0, h)
			var grad := Vector2(hx - h, hz - h) / 2.0
			if grad.length() < wall_slope:
				continue
			var out_dir := -grad.normalized()          # down the wall: the way it looks
			var along := Vector2(-out_dir.y, out_dir.x)
			var top := field.height_at(p.x - out_dir.x * 12.0, p.y - out_dir.y * 12.0, h)
			var foot := field.height_at(p.x + out_dir.x * 12.0, p.y + out_dir.y * 12.0, h)
			var tall := top - foot
			if tall < 3.0:
				continue
			# A cluster, a few deep: the back of it in the wall and over its top,
			# the front shorter and leaning out, every one overlapping the next.
			for c in rng.randi_range(cluster.x, cluster.y):
				var row := rng.randf()                  # 0 at the wall, 1 at the front
				var hr := lerpf(rng.randf_range(back_height.x, back_height.y),
						rng.randf_range(front_height.x, front_height.y), row)
				var height := tall * hr
				var width := clampf(height * rng.randf_range(aspect.x, aspect.y), 1.0, 9.0)
				# WEDGED IN TOGETHER (the user's): the rows pushed into one another and
				# each shard into its neighbours, so no daylight shows between them.
				var at := p + out_dir * lerpf(-width * 0.7, width * 0.55, row) \
						+ along * rng.randf_range(-search_step * 0.5, search_step * 0.5)
				var ground := foot if row > 0.4 else lerpf(foot, h, 0.3)
				var basis := Basis(Vector3.UP, rng.randf() * TAU)
				# Leaning out from the wall a little, more in front; never straight.
				var lean_axis := Vector3(along.x, 0.0, along.y)
				basis = Basis(lean_axis, rng.randf_range(-0.05, 0.08 + 0.12 * row)) \
						* Basis(Vector3(out_dir.x, 0.0, out_dir.y), rng.randf_range(-0.07, 0.07)) * basis
				var depth := width * rng.randf_range(0.7, 1.1)
				out.append([rng.randi_range(0, SHARDS - 1),
						Transform3D(basis.scaled_local(Vector3(width, height, depth)),
						Vector3(at.x, ground - rng.randf_range(0.3, 1.5), at.y))])
	return out


# ------------------------------------------------------------------ kept

func _cache_path() -> String:
	var key := "%d|%s|%s|%s|%s|%s|%s|%s|%s|%d|%s|%s|%s|%s|%s|%s" % [CACHE_VERSION, _field.world_seed, _field.mesa_height,
			_field.mesa_levels, _field.mesa_scale, _field.mesa_warp, _field.mesa_riser, _field.mesa_ramps,
			_field.canyon_width, SHARDS, search_step, wall_slope, cluster, back_height, front_height, aspect]
	return "user://cliff_rocks_%s.bin" % key.md5_text().substr(0, 12)


func _read_cache() -> Array:
	var f := FileAccess.open(_cache_path(), FileAccess.READ)
	if f == null:
		return []
	var v: Variant = f.get_var()
	return v if v is Array else []


func _write_cache(rocks: Array) -> void:
	var f := FileAccess.open(_cache_path(), FileAccess.WRITE)
	if f != null:
		f.store_var(rocks)


# ------------------------------------------------------------------ drawn

func _build() -> void:
	var tiles := {}            # Vector2i -> {shard: [transforms]}
	for rock in _rocks:
		var t: Transform3D = rock[1]
		var key := Vector2i(int(floor(t.origin.x / TILE)), int(floor(t.origin.z / TILE)))
		if not tiles.has(key):
			tiles[key] = {}
		var per: Dictionary = tiles[key]
		if not per.has(rock[0]):
			per[rock[0]] = []
		per[rock[0]].append(t)
	var half_diag := TILE * 0.71
	for key: Vector2i in tiles:
		var origin := Vector3((float(key.x) + 0.5) * TILE, 0.0, (float(key.y) + 0.5) * TILE)
		for k: int in tiles[key]:
			var list: Array = tiles[key][k]
			var lods: Array = _meshes[k]
			var ends: Array = _lod_ends[k]
			for l in lods.size():
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = lods[l]
				mm.instance_count = list.size()
				for i in list.size():
					var t: Transform3D = list[i]
					mm.set_instance_transform(i, Transform3D(t.basis, t.origin - origin))
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.material_override = _material
				mmi.position = origin
				var last := l == lods.size() - 1
				var lo := float(ends[l - 1]) if l > 0 else 0.0
				var hi := 0.0 if last else float(ends[l])
				# Each shard's own hand-over is the shader's dither, by its own
				# distance; the square as a whole is only drawn while any of it may
				# need to be, and the last level always (0: no end).
				mmi.set_instance_shader_parameter(&"lod_in", lo)
				mmi.set_instance_shader_parameter(&"lod_out", hi)
				mmi.visibility_range_begin = maxf(0.0, lo * (1.0 - LOD_BAND) - half_diag)
				mmi.visibility_range_end = 0.0 if last else hi * (1.0 + LOD_BAND) + half_diag
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if hi > 0.0 and hi < 250.0 \
						else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mmi)
	print("[cliffs] %d shards of rock against the tablelands' walls" % _rocks.size())


## The shards round `here` made solid: a hull each, out to `solid_reach`.
func _make_solid(here: Vector3) -> void:
	_solid_at = here
	if _solid == null:
		_solid = StaticBody3D.new()
		_solid.name = "Solid"
		add_child(_solid)
	for c in _solid.get_children():
		c.queue_free()
	for rock in _rocks:
		var t: Transform3D = rock[1]
		if Vector2(t.origin.x - here.x, t.origin.z - here.z).length() > solid_reach:
			continue
		var k := int(rock[0])
		if not _hulls.has(k):
			var chain: Array = _meshes[k]
			_hulls[k] = ((chain[mini(2, chain.size() - 1)] as ArrayMesh).create_convex_shape(true, true) as ConvexPolygonShape3D).points
		# (Its scale put into the hull's points: a shape is not to be scaled unevenly.)
		var scale := t.basis.get_scale()
		var pts := PackedVector3Array()
		for q: Vector3 in _hulls[k]:
			pts.append(q * scale)
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = hull
		cs.transform = Transform3D(t.basis.orthonormalized(), t.origin)
		_solid.add_child(cs)


## FIRST TIMES (SCRIPT_prewarm.gd): one shard drawn behind the loading screen, so
## the shader is built before the first wall comes into view.
func warm(stage: Node3D) -> void:
	if _material == null or _meshes.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = (_meshes[0] as Array).back()
	mi.material_override = _material
	mi.scale = Vector3.ONE * 0.01
	stage.add_child(mi)
