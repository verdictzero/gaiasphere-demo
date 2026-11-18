class_name CliffDressing
extends Node3D

# ROCK ALONG THE ISLAND'S EDGE. The generated wall under the rim is one smooth
# band that follows the coastline exactly, so from any distance the island reads
# as an outline pushed straight down. This walks the coast once and sinks big
# separate rock masses (assets/cliff) into it: buttresses and pillars that stand
# a little above the rim and break the outline, shelves part-way down, and fangs
# hanging lower where the wall goes into the cloud.
#
# Each chunk is four MeshInstance3Ds, one per level of detail, handed over by
# distance with Godot's visibility ranges; nothing here runs after _ready.

@export var world_path: NodePath = ^"../IslandWorld"
## Metres of coast per chunk, on average.
@export var spacing := 19.0
@export var chunk_seed := 152

# name, how often, how far below the rim its top sits (min, max), scale (min, max)
const KINDS := [
	["cliff_buttress_a", 0.20, 4.0, 9.0, 0.8, 1.5],
	["cliff_buttress_b", 0.17, 4.0, 9.0, 0.8, 1.4],
	["cliff_pillar_a", 0.14, 3.0, 9.0, 0.8, 1.6],
	["cliff_pillar_b", 0.10, 4.0, 10.0, 0.7, 1.3],
	["cliff_slab_a", 0.12, 4.0, 9.0, 0.8, 1.5],
	["cliff_shelf_a", 0.10, 7.0, 22.0, 0.8, 1.6],
	["cliff_fang_a", 0.10, 16.0, 40.0, 0.8, 1.5],
	["cliff_fang_b", 0.07, 22.0, 46.0, 0.7, 1.2],
]
const LOD_ENDS := [140.0, 380.0, 950.0, 0.0]


## THE WALL IS NOT UNDER THE COAST. Below the walkable edge the terrain's shoulder
## slopes outward, and the wall proper begins 20 m down and stands this far out,
## measured along the coast's own normal (9.0 to 10.8 m all the way round; see
## tests/DUMP_edge.gd and tools/plot_edge.py, which draw it from above).
const WALL_OUT := 9.8
## How much of a rock's depth is behind the wall's face (0 = just touching, 1 = all of it).
const BURIED := 0.22
# Half-depths of the meshes, metres, front to back (assets/cliff/manifest.json).
const HALF_DEPTH := {"cliff_buttress_a": 5.5, "cliff_buttress_b": 6.0, "cliff_pillar_a": 3.5,
	"cliff_pillar_b": 4.5, "cliff_slab_a": 2.5, "cliff_shelf_a": 6.0, "cliff_fang_a": 4.0,
	"cliff_fang_b": 5.5}


## Where every rock goes: [{name, x, y, z, yaw, sx, sy, sz, half_depth, half_width}].
## One function, used by _ready and by the edge dump, so the picture is of the game.
static func layout(field: IslandField, spacing_m := 19.0, seed_value := 152) -> Array:
	var out: Array = []
	var isl: Variant = field.island_in_cell(field.hub_cell())
	if isl == null:
		return out
	var centre := Vector2(isl.center.x, isl.center.y)
	var reach := float(field.island_extent(isl)) + 60.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := int(TAU * float(isl.radius) / spacing_m)
	for i in count:
		var theta := (float(i) + rng.randf_range(-0.35, 0.35)) / float(count) * TAU
		var dir := Vector2(cos(theta), sin(theta))
		var lo := 0.0
		var hi := reach
		for _k in 14:
			var mid := (lo + hi) * 0.5
			if field.is_land(centre.x + dir.x * mid, centre.y + dir.y * mid):
				lo = mid
			else:
				hi = mid
		if lo < 50.0:
			continue
		# The coast's outward normal here, from the coast a few metres either side.
		var side: Array[Vector2] = []
		for dth in [-0.006, 0.006]:
			var d2 := Vector2(cos(theta + dth), sin(theta + dth))
			var l2 := lo - 40.0
			var h2 := lo + 40.0
			for _k in 12:
				var m2 := (l2 + h2) * 0.5
				if field.is_land(centre.x + d2.x * m2, centre.y + d2.y * m2):
					l2 = m2
				else:
					h2 = m2
			side.append(centre + d2 * l2)
		var along := (side[1] - side[0]).normalized()
		var normal := Vector2(along.y, -along.x)
		if normal.dot(dir) < 0.0:
			normal = -normal
		var roll := rng.randf()
		var kind: Array = KINDS[KINDS.size() - 1]
		for k in KINDS:
			roll -= float(k[1])
			if roll <= 0.0:
				kind = k
				break
		var size := rng.randf_range(float(kind[4]), float(kind[5]))
		var inland := centre + dir * (lo - 5.0)
		var rim := field.height_at(inland.x, inland.y, 0.0)
		var drop := rng.randf_range(float(kind[2]), float(kind[3]))
		var yaw_jitter := rng.randf_range(-0.45, 0.45)
		var sx := size * rng.randf_range(0.85, 1.2)
		var sz := size * rng.randf_range(0.85, 1.15)
		var half := float(HALF_DEPTH[kind[0]]) * sz
		# Its middle sits so that BURIED of its depth is behind the wall's face.
		var at := centre + dir * lo + normal * (WALL_OUT + half * (1.0 - 2.0 * BURIED))
		out.append({"name": kind[0], "x": at.x, "y": rim - drop, "z": at.y,
				"yaw": atan2(normal.x, normal.y) + yaw_jitter * 0.5, "sx": sx, "sy": size, "sz": sz,
				"half_depth": half, "coast": lo, "dx": dir.x, "dz": dir.y, "nx": normal.x, "nz": normal.y})
	return out


func _ready() -> void:
	var world := get_node_or_null(world_path)
	if world == null or not world.has_method(&"get_field"):
		return
	var field: IslandField = world.call(&"get_field")
	if not field._ready:
		field.prepare()
	var mat: Material = load("res://materials/MAT_cliff_chunk.tres")
	var meshes := {}
	for kind in KINDS:
		var lods: Array = []
		for i in 4:
			var m := Flora._mesh_of("res://assets/cliff/%s/%s_lod%d.gltf" % [kind[0], kind[0], i])
			m.surface_set_material(0, mat)
			lods.append(m)
		meshes[kind[0]] = lods
	var rocks := layout(field, spacing, chunk_seed)
	for rock in rocks:
		var holder := Node3D.new()
		holder.position = Vector3(rock["x"], rock["y"], rock["z"])
		holder.basis = Basis(Vector3.UP, rock["yaw"]).scaled(Vector3(rock["sx"], rock["sy"], rock["sz"]))
		add_child(holder)
		var lods: Array = meshes[rock["name"]]
		for l in 4:
			var mi := MeshInstance3D.new()
			mi.mesh = lods[l]
			mi.visibility_range_begin = 0.0 if l == 0 else float(LOD_ENDS[l - 1])
			mi.visibility_range_end = float(LOD_ENDS[l])
			mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if l < 2
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			holder.add_child(mi)
	print("[cliffs] %d rock masses along the edge" % rocks.size())
