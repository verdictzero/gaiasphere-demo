class_name ForestMotes
extends Node3D

# WHAT HANGS IN THE AIR OF A WOOD: pollen and dust drifting slowly, catching the
# light, and small insects that dart and hover among them. Two particle clouds
# that follow the camera; each speck is a soft unlit dot, coloured every frame by
# the sun and sky (SCRIPT_enviro.gd), so they glow gold in the low sun and go dim
# in shade and at night. Hidden under water and high above the island.

@export var enviro_path: NodePath = ^"../Enviro"
@export var world_path: NodePath = ^"../IslandWorld"
@export var pollen_count := 520
@export var bug_count := 90

var _enviro: Enviro
var _world: Node
var _pollen: GPUParticles3D
var _bugs: GPUParticles3D
var _pollen_mat: StandardMaterial3D
var _bug_mat: StandardMaterial3D
var _fireflies: GPUParticles3D
var _fly_mat: StandardMaterial3D


func _ready() -> void:
	_enviro = get_node_or_null(enviro_path) as Enviro
	_world = get_node_or_null(world_path)
	var few := 0.4 if OS.has_feature("mobile") else 1.0
	_pollen_mat = _dot(Color.WHITE)
	_bug_mat = _dot(Color.WHITE)
	# Pollen: slow, everywhere, lifted and turned by the air.
	_pollen = _cloud(int(pollen_count * few), 11.0, Vector3(16, 5, 16), 0.035, _pollen_mat)
	var pm := _pollen.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0.3, 0.2, 0.2)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.22
	pm.gravity = Vector3(0.05, -0.012, 0.03)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.14
	pm.scale_min = 0.4
	pm.scale_max = 1.7
	# Insects: few, quick, erratic, low among the plants.
	_bugs = _cloud(int(bug_count * few), 5.0, Vector3(12, 2.2, 12), 0.022, _bug_mat)
	var bm := _bugs.process_material as ParticleProcessMaterial
	bm.direction = Vector3(1, 0.2, 0)
	bm.spread = 180.0
	bm.initial_velocity_min = 0.5
	bm.initial_velocity_max = 1.8
	bm.gravity = Vector3.ZERO
	bm.turbulence_enabled = true
	bm.turbulence_noise_strength = 4.0
	bm.turbulence_noise_scale = 1.1
	bm.turbulence_noise_speed_random = 1.5
	bm.turbulence_influence_min = 0.35
	bm.turbulence_influence_max = 0.8
	bm.scale_min = 0.6
	bm.scale_max = 1.2
	# FIREFLIES, at night: slow wandering lights low over the plants, each blinking
	# on and off several times in its life.
	_fly_mat = _dot(Color(0.75, 1.0, 0.25))
	_fireflies = _cloud(int(150 * few), 9.0, Vector3(22, 2.6, 22), 0.085, _fly_mat)
	var fm := _fireflies.process_material as ParticleProcessMaterial
	fm.direction = Vector3(1, 0.3, 0)
	fm.spread = 180.0
	fm.initial_velocity_min = 0.1
	fm.initial_velocity_max = 0.45
	fm.gravity = Vector3(0, 0.02, 0)
	fm.turbulence_enabled = true
	fm.turbulence_noise_strength = 1.2
	fm.turbulence_noise_scale = 2.0
	fm.turbulence_influence_min = 0.1
	fm.turbulence_influence_max = 0.3
	fm.scale_min = 0.6
	fm.scale_max = 1.3
	var blink := Gradient.new()
	blink.offsets = PackedFloat32Array([0.0, 0.08, 0.2, 0.3, 0.42, 0.56, 0.66, 0.8, 0.9, 1.0])
	blink.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.05),
			Color(1, 1, 1, 1), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.05), Color(1, 1, 1, 1), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0)])
	var blink_ramp := GradientTexture1D.new()
	blink_ramp.gradient = blink
	fm.color_ramp = blink_ramp
	_fireflies.emitting = false


func _dot(c: Color) -> StandardMaterial3D:
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(0.5, 0.0)
	glow.width = 32
	glow.height = 32
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	glow.gradient = g
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = glow
	m.albedo_color = c
	m.proximity_fade_enabled = true          # never a hard dot against the lens
	m.proximity_fade_distance = 0.6
	return m


func _cloud(amount: int, life: float, half: Vector3, size: float, mat: StandardMaterial3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.preprocess = life
	p.randomness = 1.0
	p.local_coords = false
	p.visibility_aabb = AABB(-half * 2.0, half * 4.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = half
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.18, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	return p


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _enviro == null:
		return
	var at := cam.global_position
	var ground := at.y - 1.6
	if _world != null:
		ground = float(_world.call(&"height_at", at, at.y - 1.6))
	var here: bool = not _enviro.submerged and at.y - ground < 40.0
	_pollen.emitting = here
	_bugs.emitting = here
	_pollen.global_position = Vector3(at.x, maxf(at.y, ground + 2.5), at.z)
	_bugs.global_position = Vector3(at.x, ground + 1.6, at.z)
	# Fireflies come out as the light goes, and stay in in the rain.
	var night := 1.0 - _enviro.daylight()
	_fireflies.emitting = here and night > 0.55 and _enviro.wetness < 0.3
	_fireflies.global_position = Vector3(at.x, ground + 1.8, at.z)
	_fly_mat.albedo_color = Color(0.75 * 2.4, 1.0 * 2.4, 0.25 * 2.4, 1.0)
	# Lit by the sun and the sky; less of both in rain.
	var sun := _enviro.light_color
	var dry := 1.0 - _enviro.wetness
	var lit := Color(sun.r * 1.1 + 0.08, sun.g * 1.05 + 0.08, sun.b * 0.9 + 0.08) * dry
	_pollen_mat.albedo_color = Color(lit.r, lit.g, lit.b, 1.0)
	_bug_mat.albedo_color = Color(lit.r * 0.75, lit.g * 0.7, lit.b * 0.5, 1.0)
