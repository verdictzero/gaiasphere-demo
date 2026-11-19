class_name SwordStone
extends Node3D

# THE SWORD IN THE STONE, at the heart of the island: on the islet in the middle of
# the mere, in a meadow the forest leaves round it (SCRIPT_flora.gd reads `MEADOW`),
# under a single shaft of pale light that comes straight down from nowhere: a
# cone of light with no top (SHADER_light_beam) and a spotlight inside it that
# does the actual lighting. The model is assets/sword_in_stone, at the size it
# was made: the altar stands 1.8 m, the pommel 2.3 m. SCRIPT_sword_play.gd lets
# the player draw the sword out of it.

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
	model.position = Vector3(at.x, ground - 0.06, at.y)       # level ground now: just bedded in
	model.rotation_degrees.y = yaw_degrees
	add_child(model)
	# Something to walk into, not through.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.25
	cyl.height = 1.8
	shape.shape = cyl
	shape.position.y = 0.9
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
	# MOTES: slow specks of light adrift in the shaft, rising and turning, each
	# fading in and out. Unlit and additive, so they glow like the beam does.
	var motes := GPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = 140
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.randomness = 1.0
	motes.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 16, 8))
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.5, 5.5, 1.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.16
	pm.gravity = Vector3(0, 0.012, 0)
	pm.orbit_velocity_min = -0.03
	pm.orbit_velocity_max = 0.03
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.35
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.1
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.75, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	motes.process_material = pm
	var speck := QuadMesh.new()
	speck.size = Vector2(0.045, 0.045)
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(0.5, 0.0)
	glow.width = 32
	glow.height = 32
	var dot := Gradient.new()
	dot.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	dot.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	glow.gradient = dot
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = glow
	sm.albedo_color = Color(beam_color.r * 2.6, beam_color.g * 2.6, beam_color.b * 2.6, 1.0)
	sm.disable_fog = true
	speck.material = sm
	motes.draw_pass_1 = speck
	motes.position = at + Vector3(0, 5.6, 0)
	add_child(motes)
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
