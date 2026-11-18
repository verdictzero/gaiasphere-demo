class_name SwordStone
extends Node3D

# THE SWORD IN THE STONE, at the heart of the island: on the islet in the middle of
# the mere, in a small clearing the forest leaves round it (SCRIPT_flora.gd keeps
# trees `clearing` metres back). The model is assets/sword_in_stone, at the size it
# was made: the stone stands 1.4 m, the pommel a little under 3 m.

@export var world_path: NodePath = ^"../IslandWorld"
## Metres round the stone that are kept free of trees.
@export var clearing := 7.0
@export var yaw_degrees := 205.0


## Where the stone stands, in world metres: the middle of the mere's islet.
static func site(field: IslandField) -> Vector2:
	var isl: Variant = field.island_in_cell(field.hub_cell())
	if isl == null:
		return Vector2.ZERO
	var flows: Variant = field.flows_for(isl)
	if flows != null and flows.has_lagoon():
		return flows.lagoon_center()
	return Vector2(isl.center.x, isl.center.y)


func _ready() -> void:
	var world := get_node_or_null(world_path)
	if world == null or not world.has_method(&"get_field"):
		return
	var field: IslandField = world.call(&"get_field")
	if not field._ready:
		field.prepare()
	var at := site(field)
	var ground := field.height_at(at.x, at.y, 0.0)
	var model := (load("res://assets/sword_in_stone/sword_in_stone.gltf") as PackedScene).instantiate() as Node3D
	model.name = "SwordInStone"
	model.position = Vector3(at.x, ground - 0.14, at.y)       # the stone's foot sits in the earth
	model.rotation_degrees.y = yaw_degrees
	add_child(model)
	# Something to walk into, not through.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.95
	cyl.height = 1.5
	shape.shape = cyl
	shape.position.y = 0.7
	body.add_child(shape)
	model.add_child(body)
	print("[sword] in the stone at %s" % model.position)
