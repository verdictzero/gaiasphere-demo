class_name CliffRocks
extends Node3D

# ROCK AGAINST THE WALLS OF THE TABLELANDS (IslandField's mesa_*): mostly THE
# BLOCK (the user's own chunk of cliff, assets/cliff_block: one at every place
# along every wall, half in it, turned any way round and scaled a lot, so the
# tiers are built of stacked blocks as in the example it came from), with
# clusters of shards and now and then one of the old kit among them.
#
# (Of the shards, as first written:) SHARDS OF ROCK CROWDED AGAINST THE WALLS. A wall in a height field is a smooth sheet stretched between two
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
@export var search_step := 4.5
## How steep (rise over run) the ground must be to count as a wall.
@export var wall_slope := 1.05
## Shards to a place on the wall, (least, most).
@export var cluster := Vector2i(2, 4)
## Height against the wall's: the back row's, and the front row's.
@export var back_height := Vector2(0.95, 1.3)
@export var front_height := Vector2(0.45, 0.8)
## A shard's width against its height (it is tall and thin).
@export var aspect := Vector2(0.17, 0.28)
@export var solid_reach := 45.0
## The share of places on a wall that also get one of the old kit's masses.
@export var kit_share := 0.06

## How many different shards are made.
const SHARDS := 12
## AND THE OLD KIT, mixed in (the user: "keep the old kit though and mix it in as
## necessary"): buttresses, slabs and pillars from assets/cliff, made to hang from
## an island's rim, so their origin is at their top. Where a wall is tall enough,
## one place in `kit_share` gets one, faced out of the wall, with the shards
## wedged in round and in front of it. Numbered after the shards.
## name, (min, max) of the wall heights it suits, metres
const KIT := [
	["cliff_buttress_a", 8.0, 90.0],
	["cliff_buttress_b", 8.0, 90.0],
	["cliff_slab_a", 4.0, 45.0],
	["cliff_pillar_a", 14.0, 90.0],
	["cliff_pillar_b", 14.0, 90.0],
]
const TILE := 256.0
const LOD_BAND := 0.12
const CACHE_VERSION := 16   # (the layout; how it is drawn is not kept)
## Past this every rock in a square is drawn in ONE draw, as the simplest shard
## (at this distance one broken column is as good as another): a draw a square,
## not one for every kind of rock in it.
const FAR_AT := 600.0
## What a build ships (tests/BAKE_island.gd writes it), read before user://.
const BAKED := "res://data/bake/cliff_rocks.bake"
const CELL := 32.0
## (Baked by tools/bake_cliff_block.py: its vertex colour carries edge wear and
## crevice light for the shader.)
const BLOCK := "res://assets/cliff_block/cliff_block.glb"
## Triangles in the block's second level of detail.
const BLOCK_LOD1 := 700
## And in its first: the block as handed over is 6,724.
const BLOCK_LOD0 := 1000
## Of the places on a wall, the share that also get a few shards in front.
const SHARD_SHARE := 0.25

var _field: IslandField
var _meshes: Array = []    # shard -> [lod meshes]
var _lod_ends: Array = []  # shard -> [distances]
var _hulls := {}           # shard -> hull points of a coarse level
var _kit_size: Array = []  # kit -> size in metres, as made
var _kit_low: Array = []   # kit -> how far below its origin it reaches, as made
var _material: ShaderMaterial
var _rocks: Array = []     # [kind, Transform3D, Color: the ground beside it (see `_ground_at`)]
var _task := -1
var _result: Array = []
var _solid: StaticBody3D
var _solid_at := Vector3(1e9, 0, 0)
var _explorer: Node3D
var _cells := {}           # Vector2i (CELL metres) -> [indices into _rocks], for what is solid


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
	var sizes := {}
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://assets/cliff/manifest.json")):
		var sz: Array = entry["size_m"]
		sizes[entry["name"]] = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
	for kind in KIT:
		var lods: Array = MeshLods.chain(Flora._mesh_of("res://assets/cliff/%s/%s_lod0.gltf" % [kind[0], kind[0]]) as ArrayMesh)
		_meshes.append(lods)
		var size: Vector3 = sizes.get(kind[0], Vector3(16, 26, 11))
		_kit_size.append(size)
		_kit_low.append((lods[0] as Mesh).get_aabb().position.y)
		_lod_ends.append(MeshLods.distances(lods.size(), maxf(size.x, size.y) * 1.2))
	# THE BLOCK (assets/cliff_block, tools/bake_cliff_block.py): the user's own
	# chunk of cliff, the main thing the walls are built of. Numbered after the kit.
	var block := Flora._mesh_of(BLOCK) as ArrayMesh
	# ITS SECOND LEVEL IS 700 TRIANGLES (the user's figure), not the half the
	# simplifier's chain would give next: the whole block only within 30 m, then
	# straight to 700, then on down the chain from there.
	var halves: Array = MeshLods.chain(block, 24)
	# (And its first, the block itself, taken down to 1000: the user's figure too.)
	var chain: Array = [MeshLods.reduced(block, BLOCK_LOD0), MeshLods.reduced(block, BLOCK_LOD1)]
	for m: ArrayMesh in halves:
		if m.surface_get_array_index_len(0) / 3 < BLOCK_LOD1 * 0.8:
			chain.append(m)
	_meshes.append(chain)
	var box := block.get_aabb()
	_kit_size.append(box.size)
	_kit_low.append(box.position.y)
	_lod_ends.append(MeshLods.distances(chain.size(), 10.0, 1.7))
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/SHADER_cliff_rock.gdshader")
	var terrain := world.get(&"terrain_material") as ShaderMaterial
	if terrain != null:
		for p in ["ground_albedo", "ground_normal", "macro_noise", "rock_size", "rock_tint", "brightness",
				"macro_strength", "normal_strength", "triplanar_sharpness", "detail_distance",
				# (and what the tops are drawn with: the ground's own surfaces)
				"stochastic", "stochastic_scale", "moss_size", "soil_size", "litter_size", "sand_size",
				"meadow_size", "dry_size", "floor_size", "moss_tint", "soil_tint", "litter_tint", "sand_tint",
				"meadow_tint", "dry_tint", "floor_tint",
				"strata_strength", "strata_bed", "strata_warp", "strata_dip",
				"strata_colour", "strata_colour_bed", "strata_colour_a", "strata_colour_b", "strata_colour_c",
				"strata_colour_d", "strata_colour_e"]:
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
	# (Indexed, or the simplifier has nothing to work on and makes no levels.)
	st.index()
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
	# (Inside the middle only the cows' meadow's own walls: FlowTerrain's meadow.)
	var flows: FlowTerrain = field.flows_for(isl)
	var meadow := Vector2.INF
	if flows != null and flows.crash_site()[1] != Vector2.ZERO:
		meadow = flows._meadow_c
	for j in n:
		for i in n:
			var p := isl.center + Vector2(-reach + (float(i) + rng.randf()) * search_step,
					-reach + (float(j) + rng.randf()) * search_step)
			if p.distance_to(isl.center) < keep:
				continue
			# (No rock on the shuttle's path and its hill: the exception to the rule.)
			if flows != null and flows.crash_clear(p.x, p.y) < 130.0:
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
			# The ground at the wall's top, for the rocks' own tops to carry on.
			# (Read well back from the edge, on the level: at the lip itself the
			# ground is steep, and steep ground is bare of wood and half rock, which
			# is not what the plateau beside the rock is.)
			var turf := _ground_at(field, p - out_dir * 12.0).lerp(_ground_at(field, p - out_dir * 20.0), 0.5)
			# THE BLOCK, at every place: half in the wall, turned any way round, and
			# scaled a lot (the user: "just randomize its rotation and scale a lot"),
			# about as tall as the tier it stands against.
			var bsize: Vector3 = _kit_size[KIT.size()]
			var by := tall * rng.randf_range(0.85, 1.35) / bsize.y
			var bscale := Vector3(by * rng.randf_range(0.7, 1.9), by, by * rng.randf_range(0.7, 1.9))
			var bturn := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.14, 0.14)) \
					* Basis(Vector3.BACK, rng.randf_range(-0.14, 0.14))
			var bat := p - out_dir * rng.randf_range(0.0, 1.5) + along * rng.randf_range(-1.5, 1.5)
			# (Its middle a little under the wall's: its foot in the ground below.)
			var bmid := (foot + top) * 0.5 - (float(_kit_low[KIT.size()]) + bsize.y * 0.5) * by - rng.randf_range(0.3, 1.2)
			out.append([SHARDS + KIT.size(), Transform3D(bturn.scaled_local(bscale), Vector3(bat.x, bmid, bat.y)), turf])
			# Now and then one of the old kit's masses, in the wall, faced out of it.
			if rng.randf() < kit_share:
				var kit := _kit_for(rng, tall)
				if kit >= 0:
					var size: Vector3 = _kit_size[kit]
					var ks := tall * rng.randf_range(0.7, 1.15) / size.y
					var kx := ks * rng.randf_range(0.8, 1.2)
					var kz := ks * rng.randf_range(0.8, 1.15)
					var half := size.z * kz * 0.5
					var kat := p + out_dir * (half * (1.0 - 2.0 * 0.45))
					var kb := Basis(Vector3.UP, atan2(out_dir.x, out_dir.y) + rng.randf_range(-0.35, 0.35)) \
							* Basis(Vector3.RIGHT, rng.randf_range(-0.1, 0.1)) * Basis(Vector3.BACK, rng.randf_range(-0.12, 0.12))
					# (Stood on its underside: the kit hangs from its top.)
					var ky := foot - rng.randf_range(0.8, 2.5) - float(_kit_low[kit]) * ks
					out.append([SHARDS + kit, Transform3D(kb.scaled_local(Vector3(kx, ks, kz)), Vector3(kat.x, ky, kat.y)), turf])
			# And at some, a cluster of shards in front: the back of it in the wall and
			# over its top, the front shorter and leaning out, overlapping.
			if rng.randf() > SHARD_SHARE:
				continue
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
						Vector3(at.x, ground - rng.randf_range(0.3, 1.5), at.y)), turf])
	return out


## WHAT THE GROUND IS at a point, as the rocks' shader wants it (INSTANCE_CUSTOM):
## r the wood there (the field's forest), g b a the shares of ground, earth and
## sand in the terrain's own splat (its rock left out: this is for what is not).
func _ground_at(field: IslandField, at: Vector2) -> Color:
	var s := field.sample(at.x, at.y)
	var w: Color = s.get("weights", Color(1, 0, 0, 0))
	return Color(float(s.get("forest", 0.0)), w.r, w.g, w.a)


## One of the kit that suits a wall this tall, or -1.
func _kit_for(rng: RandomNumberGenerator, tall: float) -> int:
	var fits: Array = []
	for i in KIT.size():
		if tall >= float(KIT[i][1]) and tall <= float(KIT[i][2]):
			fits.append(i)
	return -1 if fits.is_empty() else int(fits[rng.randi_range(0, fits.size() - 1)])


# ------------------------------------------------------------------ kept

func _cache_path() -> String:
	var key := "%d|%s|%s|%s|%s|%s|%s|%s|%s|%d|%s|%s|%s|%s|%s|%s|%s" % [CACHE_VERSION, _field.world_seed, _field.mesa_height,
			_field.mesa_levels, _field.mesa_scale, _field.mesa_warp, _field.mesa_riser, _field.mesa_ramps,
			_field.canyon_width, SHARDS * 100 + KIT.size(), search_step, wall_slope, cluster, back_height, front_height, aspect,
			kit_share]
	return "user://cliff_rocks_%s.bin" % key.md5_text().substr(0, 12)


func _read_cache() -> Array:
	# What the build shipped, if it was made from this island as it is now.
	var b := FileAccess.open(BAKED, FileAccess.READ)
	if b != null:
		var held: Variant = b.get_var()
		if held is Dictionary and String(held.get("key", "")) == _cache_path() and held.get("rocks") is Array:
			return held["rocks"]
	var f := FileAccess.open(_cache_path(), FileAccess.READ)
	if f == null:
		return []
	var v: Variant = f.get_var()
	return v if v is Array else []


## For the bake (tests/BAKE_island.gd): true once the rocks are placed, and the
## layout written where a build will ship it.
func placed() -> bool:
	return _task < 0 and (not _rocks.is_empty() or _field == null or not _field.mesa_enabled)


func save_bake() -> int:
	var f := FileAccess.open(BAKED, FileAccess.WRITE)
	if f == null:
		return 0
	f.store_var({"key": _cache_path(), "rocks": _rocks})
	return _rocks.size()


func _write_cache(rocks: Array) -> void:
	var f := FileAccess.open(_cache_path(), FileAccess.WRITE)
	if f != null:
		f.store_var(rocks)


# ------------------------------------------------------------------ drawn

func _build() -> void:
	var tiles := {}            # Vector2i -> {kind: [transforms]}
	_cells.clear()
	for index in _rocks.size():
		var rock: Array = _rocks[index]
		var t: Transform3D = rock[1]
		var key := Vector2i(int(floor(t.origin.x / TILE)), int(floor(t.origin.z / TILE)))
		if not tiles.has(key):
			tiles[key] = {}
		var per: Dictionary = tiles[key]
		if not per.has(rock[0]):
			per[rock[0]] = []
		per[rock[0]].append([t, rock[2]])
		var cell := Vector2i(int(floor(t.origin.x / CELL)), int(floor(t.origin.z / CELL)))
		if not _cells.has(cell):
			_cells[cell] = PackedInt32Array()
		(_cells[cell] as PackedInt32Array).append(index)
	var half_diag := TILE * 0.71
	# The far stand-in is the block at its very simplest (a couple of dozen
	# triangles), put into each rock's own box.
	var far_mesh: Mesh = (_meshes[SHARDS + KIT.size()] as Array).back()
	var far_box := far_mesh.get_aabb()
	var boxes: Array = []
	for lods: Array in _meshes:
		boxes.append((lods[0] as Mesh).get_aabb())
	var draws := 0
	for key: Vector2i in tiles:
		var origin := Vector3((float(key.x) + 0.5) * TILE, 0.0, (float(key.y) + 0.5) * TILE)
		var far := PackedFloat32Array()        # every rock in the square, as the simplest shard
		for k: int in tiles[key]:
			var list: Array = tiles[key][k]
			var lods: Array = _meshes[k]
			var ends: Array = _lod_ends[k]
			for entry: Array in list:
				var t: Transform3D = entry[0]
				var turf: Color = entry[1]
				var b := t.basis
				var o := t.origin - origin
				if k != SHARDS + KIT.size():
					var box: AABB = boxes[k]
					var fit := b * Basis.from_scale(box.size / far_box.size)
					o += b * box.get_center() - fit * far_box.get_center()
					b = fit
				far.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
						turf.r, turf.g, turf.b, turf.a])
			for l in lods.size():
				var lo := float(ends[l - 1]) if l > 0 else 0.0
				if lo >= FAR_AT:
					break
				var hi := FAR_AT if l == lods.size() - 1 else minf(float(ends[l]), FAR_AT)
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_custom_data = true
				mm.mesh = lods[l]
				mm.instance_count = list.size()
				for i in list.size():
					var t: Transform3D = list[i][0]
					mm.set_instance_transform(i, Transform3D(t.basis, t.origin - origin))
					mm.set_instance_custom_data(i, list[i][1])
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.material_override = _material
				mmi.position = origin
				# Each rock's own hand-over is the shader's dither, by its own
				# distance; the square as a whole is only drawn while any of it may
				# need to be.
				mmi.set_instance_shader_parameter(&"lod_in", lo)
				mmi.set_instance_shader_parameter(&"lod_out", hi)
				mmi.visibility_range_begin = maxf(0.0, lo * (1.0 - LOD_BAND) - half_diag)
				mmi.visibility_range_end = hi * (1.0 + LOD_BAND) + half_diag
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if hi < 250.0 \
						else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mmi)
				draws += 1
		# ROCKS NEVER GO: past FAR_AT the whole square in one draw, at any distance.
		var fm := MultiMesh.new()
		fm.transform_format = MultiMesh.TRANSFORM_3D
		fm.use_custom_data = true
		fm.mesh = far_mesh
		fm.instance_count = far.size() / 16
		fm.buffer = far
		var fmi := MultiMeshInstance3D.new()
		fmi.multimesh = fm
		fmi.material_override = _material
		fmi.position = origin
		fmi.set_instance_shader_parameter(&"lod_in", FAR_AT)
		fmi.set_instance_shader_parameter(&"lod_out", 0.0)
		fmi.visibility_range_begin = maxf(0.0, FAR_AT * (1.0 - LOD_BAND) - half_diag)
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fmi)
	var count := [0, 0, 0]
	for rock in _rocks:
		var k := int(rock[0])
		count[0 if k < SHARDS else (1 if k < SHARDS + KIT.size() else 2)] += 1
	print("[cliffs] %d blocks, %d shards and %d of the old kit against the walls, in %d squares (%d near draws at most)" % [
			count[2], count[0], count[1], tiles.size(), draws])


## The shards round `here` made solid: a hull each, out to `solid_reach`.
func _make_solid(here: Vector3) -> void:
	_solid_at = here
	if _solid == null:
		_solid = StaticBody3D.new()
		_solid.name = "Solid"
		add_child(_solid)
	for c in _solid.get_children():
		c.queue_free()
	var near := PackedInt32Array()
	var c0 := Vector2i(int(floor((here.x - solid_reach) / CELL)), int(floor((here.z - solid_reach) / CELL)))
	var c1 := Vector2i(int(floor((here.x + solid_reach) / CELL)), int(floor((here.z + solid_reach) / CELL)))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			near.append_array(_cells.get(Vector2i(cx, cz), PackedInt32Array()))
	for index in near:
		var rock: Array = _rocks[index]
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
