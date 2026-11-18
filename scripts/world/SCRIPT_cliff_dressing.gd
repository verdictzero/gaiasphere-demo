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
@export var spacing := 52.0
@export var chunk_seed := 152

# name, how often, how far below the rim its top sits (min, max), scale (min, max)
const KINDS := [
	["cliff_buttress_a", 0.20, 0.5, 3.0, 0.8, 1.5],
	["cliff_buttress_b", 0.17, 0.5, 2.5, 0.8, 1.4],
	["cliff_pillar_a", 0.14, 0.0, 3.5, 0.8, 1.6],
	["cliff_pillar_b", 0.10, 1.0, 5.0, 0.7, 1.3],
	["cliff_slab_a", 0.12, 0.5, 3.0, 0.8, 1.5],
	["cliff_shelf_a", 0.10, 7.0, 22.0, 0.8, 1.6],
	["cliff_fang_a", 0.10, 16.0, 40.0, 0.8, 1.5],
	["cliff_fang_b", 0.07, 22.0, 46.0, 0.7, 1.2],
]
const LOD_ENDS := [140.0, 380.0, 950.0, 0.0]


func _ready() -> void:
	var world := get_node_or_null(world_path)
	if world == null or not world.has_method(&"get_field"):
		return
	var field: IslandField = world.call(&"get_field")
	if not field._ready:
		field.prepare()
	var isl: Variant = field.island_in_cell(field.hub_cell())
	if isl == null:
		return
	var centre := Vector2(isl.center.x, isl.center.y)
	var reach := float(field.island_extent(isl)) + 60.0
	var mat: Material = load("res://materials/MAT_cliff_chunk.tres")
	var meshes := {}
	for kind in KINDS:
		var lods: Array = []
		for i in 4:
			var m := Flora._mesh_of("res://assets/cliff/%s/%s_lod%d.gltf" % [kind[0], kind[0], i])
			m.surface_set_material(0, mat)
			lods.append(m)
		meshes[kind[0]] = lods

	var rng := RandomNumberGenerator.new()
	rng.seed = chunk_seed
	var count := int(TAU * float(isl.radius) / spacing)
	var placed := 0
	for i in count:
		var theta := (float(i) + rng.randf_range(-0.35, 0.35)) / float(count) * TAU
		var dir := Vector2(cos(theta), sin(theta))
		# The coast on this bearing: the outermost land, found by halving.
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
		# Sunk into the wall by a third of its depth, top a little under the rim.
		# Standing out from the wall: only its back third is in the rock.
		# The wall stands a dozen metres outside the walkable coast (the terrain's shoulder).
		var at := centre + dir * (lo + 12.0 + 3.0 * size)
		var holder := Node3D.new()
		holder.position = Vector3(at.x, rim - rng.randf_range(float(kind[2]), float(kind[3])), at.y)
		holder.basis = Basis(Vector3.UP, atan2(dir.x, dir.y) + rng.randf_range(-0.45, 0.45)) \
				.scaled(Vector3(size * rng.randf_range(0.85, 1.2), size, size * rng.randf_range(0.85, 1.15)))
		add_child(holder)
		var lods: Array = meshes[kind[0]]
		for l in 4:
			var mi := MeshInstance3D.new()
			mi.mesh = lods[l]
			mi.visibility_range_begin = 0.0 if l == 0 else float(LOD_ENDS[l - 1])
			mi.visibility_range_end = float(LOD_ENDS[l])
			mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if l < 2
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			holder.add_child(mi)
		placed += 1
		if placed == 1:
			print("[cliffs] first: ", kind[0], " at ", holder.global_position, " scale ", holder.scale,
					" mesh ", lods[0], " aabb ", (lods[0] as Mesh).get_aabb())
	print("[cliffs] %d rock masses along the edge" % placed)
