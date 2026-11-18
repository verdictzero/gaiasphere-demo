class_name Causeway
extends Node3D

# THE CAUSEWAY TO THE ISLET. The land bridge itself is terrain
# (FlowTerrain.causeway_weight raises it out of the mere); this tells the terrain
# shader where it runs so it can cobble it, and tells the water where the middle
# of the mere is, so its waves can run outward from the islet.

@export var world_path: NodePath = ^"../IslandWorld"
@export var water_path: NodePath = ^"../RiverWater"

var start := Vector3.ZERO       # on the outer shore
var finish := Vector3.ZERO      # on the islet


func _ready() -> void:
	var world := get_node_or_null(world_path)
	if world == null or not world.has_method(&"get_field"):
		return
	var field: IslandField = world.call(&"get_field")
	if not field._ready:
		field.prepare()
	var isl: Variant = field.island_in_cell(field.hub_cell())
	var flows: Variant = field.flows_for(isl) if isl != null else null
	if flows == null or not flows.has_lagoon():
		return
	var ends: PackedVector2Array = flows.causeway_ends()
	finish = Vector3(ends[0].x, field.height_at(ends[0].x, ends[0].y, 0.0), ends[0].y)
	start = Vector3(ends[1].x, field.height_at(ends[1].x, ends[1].y, 0.0), ends[1].y)
	var ground := world.get(&"terrain_material") as ShaderMaterial
	if ground != null:
		ground.set_shader_parameter("cobble_albedo", load("res://textures/polyhaven/cobblestone_floor_04_basecolor.jpg"))
		ground.set_shader_parameter("cobble_normal", load("res://textures/polyhaven/cobblestone_floor_04_normal.jpg"))
		ground.set_shader_parameter("causeway", Vector4(ends[0].x, ends[0].y, ends[1].x, ends[1].y))
		ground.set_shader_parameter("causeway_half", flows.CAUSEWAY_HALF)
	var water := get_node_or_null(water_path)
	if water != null and water.get(&"material") is ShaderMaterial:
		var c: Vector2 = flows.lagoon_center()
		(water.get(&"material") as ShaderMaterial).set_shader_parameter("mere_centre", c)
	print("[causeway] %.0f m of causeway from %s to %s" % [start.distance_to(finish), start, finish])
