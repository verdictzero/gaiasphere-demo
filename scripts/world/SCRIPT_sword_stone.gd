class_name SwordStone
extends Node3D

# THE SWORD IN THE STONE, at the heart of the island: on the islet in the middle of
# the mere, in a meadow the forest leaves round it (SCRIPT_flora.gd reads `MEADOW`),
# under a single shaft of pale light that comes straight down from nowhere: a
# cone of light with no top (SHADER_light_beam) and a spotlight inside it that
# does the actual lighting. The model is assets/sword_in_stone, at the size it
# was made: the stone stands 1.4 m, the pommel a little under 3 m.

@export var world_path: NodePath = ^"../IslandWorld"
## Radius of the meadow round the stone, metres: grass, no trees.
const MEADOW := 21.0
@export var beam_height := 85.0
@export var beam_color := Color(0.72, 0.85, 1.0)
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
	_build_beam(model.position)
	print("[sword] in the stone at %s" % model.position)


func _build_beam(at: Vector3) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.45
	cone.bottom_radius = 2.1
	cone.height = beam_height
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var noise := NoiseTexture2D.new()
	noise.width = 128
	noise.height = 256
	noise.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	noise.noise = fn
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/SHADER_light_beam.gdshader")
	mat.set_shader_parameter("beam_color", beam_color)
	mat.set_shader_parameter("dust", noise)
	var shaft := MeshInstance3D.new()
	shaft.name = "Beam"
	shaft.mesh = cone
	shaft.material_override = mat
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.position = at + Vector3(0, beam_height * 0.5 - 0.3, 0)
	add_child(shaft)
	var lamp := SpotLight3D.new()
	lamp.name = "BeamLight"
	lamp.light_color = beam_color
	lamp.light_energy = 14.0
	lamp.spot_range = 46.0
	lamp.spot_angle = 5.5
	lamp.spot_angle_attenuation = 0.6
	lamp.spot_attenuation = 0.35
	lamp.shadow_enabled = true
	lamp.position = at + Vector3(0, 40.0, 0)
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	add_child(lamp)
