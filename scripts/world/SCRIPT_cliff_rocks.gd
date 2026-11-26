class_name CliffRocks
extends Node3D

# ROCK MASSES STOOD AGAINST THE WALLS OF THE TABLELANDS (IslandField's mesa_*).
# A wall in a height field is a smooth sheet stretched between two levels; from
# any distance it reads as a ramp painted grey. So, as Xenoblade does, real rock
# is set into it: buttresses, slabs and pillars (assets/cliff), each pushed back
# into the wall until only its front stands proud, as tall as the wall is, turned
# to face out of it, a little askew. Their surface is the terrain's own rock
# (SHADER_cliff_rock.gdshader, with every value copied off the terrain's
# material), so where a rock goes into the wall the grain runs on across the join.
#
# WHERE: the island is searched once on a coarse grid for steep ground; wherever
# it is a wall (and not the island's outer edge, nor inside the middle the
# tablelands leave alone), a rock goes, no closer to the last than its width.
# That search runs on a worker thread with its own copy of the field, and its
# answer is kept in user:// (keyed by everything that shapes it), so after the
# first run it is read back at once.
#
# DRAWN as MultiMeshes, one per kind of rock and level of detail in each 256 m
# square, handed over by distance through a dither (SHADERINC_lod_fade). SOLID
# where the player is: the rocks within `solid_reach` get a hull each, gathered
# again as the player moves.

@export var world_path: NodePath = ^"../GaiaSphere"
@export var explorer_path: NodePath = ^"../Explorer"
## Metres between the points the walls are searched at.
@export var search_step := 9.0
## How steep (rise over run) the ground must be to count as a wall.
@export var wall_slope := 1.05
## How much of a wall's height a rock stands, (least, most).
@export var cover := Vector2(0.55, 1.0)
## How much of a rock's depth is pushed back into the wall.
@export var buried := 0.62
@export var solid_reach := 70.0

# name, how often, (min, max) of the wall heights it suits, metres
const KINDS := [
	["cliff_buttress_a", 0.3, 8.0, 80.0],
	["cliff_buttress_b", 0.3, 8.0, 80.0],
	["cliff_slab_a", 0.25, 4.0, 40.0],
	["cliff_pillar_a", 0.1, 14.0, 80.0],
	["cliff_pillar_b", 0.05, 14.0, 80.0],
]
## Where each level of detail hands over to the next (MeshLods.distances: a
## dozen or so metres for the finest, stepping out), per kind; the last level is
## drawn however far away the rock is: rocks never go.
var _lod_ends := {}        # kind -> [distances]
const TILE := 256.0
const LOD_BAND := 0.12
const CACHE_VERSION := 3

var _field: IslandField
var _sizes := {}           # kind -> Vector3 size in metres, as made
var _meshes := {}          # kind -> [lod meshes]
var _hulls := {}           # kind -> convex shape of its coarsest mesh
var _material: ShaderMaterial
var _rocks: Array = []     # [kind index, Transform3D]
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
	_read_manifest()
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


func _read_manifest() -> void:
	var list: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cliff/manifest.json"))
	for entry in list:
		var s: Array = entry["size_m"]
		_sizes[entry["name"]] = Vector3(float(s[0]), float(s[1]), float(s[2]))
	for kind in KINDS:
		# Every level the simplifier makes, from the finest of the kit's own.
		var lods: Array = MeshLods.chain(Flora._mesh_of("res://assets/cliff/%s/%s_lod0.gltf" % [kind[0], kind[0]]) as ArrayMesh)
		_meshes[kind[0]] = lods
		var size: Vector3 = _sizes.get(kind[0], Vector3.ONE * 16.0)
		_lod_ends[kind[0]] = MeshLods.distances(lods.size(), maxf(size.x, size.y) * 1.2)


# ------------------------------------------------------------------ where

## Every rock: [kind index, transform]. A pure function of the field.
func _layout(field: IslandField) -> Array:
	var out: Array = []
	var isl: IslandField.Island = field.island_in_cell(field.hub_cell())
	if isl == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = field.world_seed ^ 0xC11FF
	var reach := isl.radius * 1.15
	var n := int(reach * 2.0 / search_step)
	var taken := {}            # coarse cell -> [Vector2 centre, radius]
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
			var out_dir := -grad.normalized()          # down the wall: the way the face looks
			var top := field.height_at(p.x - out_dir.x * 14.0, p.y - out_dir.y * 14.0, h)
			var foot := field.height_at(p.x + out_dir.x * 14.0, p.y + out_dir.y * 14.0, h)
			var tall := top - foot
			if tall < 4.0:
				continue
			var k := _pick(rng, tall)
			if k < 0:
				continue
			var size: Vector3 = _sizes[KINDS[k][0]]
			var s := tall * rng.randf_range(cover.x, cover.y) / size.y
			var sx := s * rng.randf_range(0.8, 1.25)
			var sz := s * rng.randf_range(0.8, 1.2)
			var width := size.x * sx
			# Room: none closer than their widths allow.
			var cell := Vector2i(int(floor(p.x / 24.0)), int(floor(p.y / 24.0)))
			var crowded := false
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					for other in taken.get(cell + Vector2i(dx, dz), []):
						if (other[0] as Vector2).distance_to(p) < (float(other[1]) + width * 0.5) * 0.7:
							crowded = true
			if crowded:
				continue
			if not taken.has(cell):
				taken[cell] = []
			taken[cell].append([p, width * 0.5])
			# Stood with its foot at the wall's foot, its face out of the wall, and
			# `buried` of its depth behind the wall's face.
			var half := size.z * sz * 0.5
			var at := p + out_dir * (half * (1.0 - 2.0 * buried))
			var yaw := atan2(out_dir.x, out_dir.y) + rng.randf_range(-0.35, 0.35)
			var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12)) \
					* Basis(Vector3.BACK, rng.randf_range(-0.15, 0.15))
			var y := foot - rng.randf_range(1.0, 3.0)
			out.append([k, Transform3D(basis.scaled_local(Vector3(sx, s, sz)), Vector3(at.x, y, at.y))])
	return out


func _pick(rng: RandomNumberGenerator, tall: float) -> int:
	var total := 0.0
	for kind in KINDS:
		if tall >= float(kind[2]) and tall <= float(kind[3]):
			total += float(kind[1])
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	for i in KINDS.size():
		var kind: Array = KINDS[i]
		if tall < float(kind[2]) or tall > float(kind[3]):
			continue
		roll -= float(kind[1])
		if roll <= 0.0:
			return i
	return -1


# ------------------------------------------------------------------ kept

func _cache_path() -> String:
	var key := "%d|%s|%s|%s|%s|%s|%s|%s|%s|%d|%s|%s|%s" % [CACHE_VERSION, _field.world_seed, _field.mesa_height,
			_field.mesa_levels, _field.mesa_scale, _field.mesa_warp, _field.mesa_riser, _field.mesa_ramps,
			_field.canyon_width, KINDS.size(), search_step, wall_slope, cover]
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
	var tiles := {}            # Vector2i -> {kind index: [transforms]}
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
			var lods: Array = _meshes[KINDS[k][0]]
			var ends: Array = _lod_ends[KINDS[k][0]]
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
				# Each rock's own hand-over is the shader's dither, by its own distance;
				# the square as a whole is only drawn while any of it may need to be,
				# and the last level always (0: no end).
				mmi.set_instance_shader_parameter(&"lod_in", lo)
				mmi.set_instance_shader_parameter(&"lod_out", hi)
				mmi.visibility_range_begin = maxf(0.0, lo * (1.0 - LOD_BAND) - half_diag)
				mmi.visibility_range_end = 0.0 if last else hi * (1.0 + LOD_BAND) + half_diag
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if hi > 0.0 and hi < 400.0 \
						else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mmi)
	print("[cliffs] %d rock masses against the tablelands' walls" % _rocks.size())


## The rocks round `here` made solid: a hull each, out to `solid_reach`.
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
		var name: String = KINDS[int(rock[0])][0]
		if not _hulls.has(name):
			var chain: Array = _meshes[name]
			_hulls[name] = ((chain[mini(4, chain.size() - 1)] as ArrayMesh).create_convex_shape(true, true) as ConvexPolygonShape3D).points
		# (Its scale put into the hull's points: a shape is not to be scaled unevenly.)
		var scale := t.basis.get_scale()
		var pts := PackedVector3Array()
		for q: Vector3 in _hulls[name]:
			pts.append(q * scale)
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = hull
		cs.transform = Transform3D(t.basis.orthonormalized(), t.origin)
		_solid.add_child(cs)


## FIRST TIMES (SCRIPT_prewarm.gd): one rock drawn behind the loading screen, so
## the shader is built before the first wall comes into view.
func warm(stage: Node3D) -> void:
	if _material == null or _meshes.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = (_meshes[KINDS[0][0]] as Array).back()
	mi.material_override = _material
	mi.scale = Vector3.ONE * 0.01
	stage.add_child(mi)
