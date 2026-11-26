class_name Mining
extends Node3D

# BREAKING BOULDERS WITH THE PICKAXE, AND THE STONE THEY BECOME.
#
# A swing of the pickaxe that lands on a boulder knocks grit and dust off it
# where the point struck, and now and then a stone. A boulder takes more blows
# the bigger it is; at the last one it comes apart into a heap of stones of its
# own rock, which tumble, settle, and are gathered into the inventory by
# walking up to them, as logs are (SCRIPT_woodcutting.gd).
#
# The boulder is taken out of Flora's own instance buffers (`Flora.quarry`), so
# it and its collider are gone for as long as this run lasts. Only the pickaxe
# does this: an axe or a sword does nothing to rock.

@export var flora_path: NodePath = ^"../Flora"
@export var explorer_path: NodePath = ^"../Explorer"
@export var inventory_path: NodePath = ^"../Inventory"
## How far a swing reaches, metres.
@export var reach := 3.2
@export var gather_radius := 2.3
@export var max_stones := 120

var _flora: Flora
var _explorer: Node3D
var _inventory: Node
var _blows := {}             # boulder origin -> blows landed
var _stones: Array = []      # [body, seconds lain]
var _rock: StandardMaterial3D
var _grit_mat: StandardMaterial3D
var _dust_mat: StandardMaterial3D
var _grit_flow: ParticleProcessMaterial
var _dust_flow: ParticleProcessMaterial
var _grit_mesh: Mesh
var _dust_mesh: QuadMesh
var _spark_flow: ParticleProcessMaterial
var _spark_mesh: QuadMesh
var _shapes := {}            # kind of boulder -> convex shape of its low mesh
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_flora = get_node_or_null(flora_path) as Flora
	_explorer = get_node_or_null(explorer_path)
	_inventory = get_node_or_null(inventory_path)
	_rng.randomize()
	# Broken stone: the boulders' own rock, with none of the moss that grew on
	# the outside, mapped through the world so no piece needs unwrapping.
	_rock = StandardMaterial3D.new()
	_rock.albedo_texture = load("res://textures/polyhaven/dark_rock_02_basecolor.jpg")
	_rock.albedo_color = Color(1.12, 1.1, 1.08)
	_rock.normal_enabled = true
	_rock.normal_texture = load("res://textures/polyhaven/dark_rock_02_normal.jpg")
	_rock.orm_texture = load("res://textures/polyhaven/dark_rock_02_orm.jpg")
	_rock.roughness = 1.0
	_rock.metallic_specular = 0.3
	_rock.uv1_triplanar = true
	_rock.uv1_scale = Vector3.ONE * 1.6
	# GRIT: sixteen photographs of broken stone (assets/chips/stone_atlas.png, cut
	# from one sheet by tools/build_chip_atlas.py), one to a particle, tumbling.
	_grit_mat = StandardMaterial3D.new()
	_grit_mat.albedo_texture = load("res://assets/chips/stone_atlas.png")
	_grit_mat.albedo_color = Color(0.82, 0.81, 0.8)
	_grit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_grit_mat.alpha_scissor_threshold = 0.45
	_grit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_grit_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_grit_mat.particles_anim_h_frames = 4
	_grit_mat.particles_anim_v_frames = 4
	_grit_mat.particles_anim_loop = false
	_grit_mat.roughness = 0.95
	var bit := QuadMesh.new()
	bit.size = Vector2(0.075, 0.075)
	_grit_mesh = bit
	_grit_flow = ParticleProcessMaterial.new()
	_grit_flow.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_grit_flow.emission_sphere_radius = 0.07
	_grit_flow.direction = Vector3(0, 0, -1)          # (the burst is turned to face out of the rock)
	_grit_flow.spread = 62.0
	_grit_flow.initial_velocity_min = 1.4
	_grit_flow.initial_velocity_max = 5.5
	_grit_flow.gravity = Vector3(0, -9.8, 0)
	_grit_flow.angle_max = 360.0
	_grit_flow.angular_velocity_min = -500.0
	_grit_flow.angular_velocity_max = 500.0
	_grit_flow.scale_min = 0.4
	_grit_flow.scale_max = 1.7
	_grit_flow.anim_offset_min = 0.0
	_grit_flow.anim_offset_max = 1.0
	_grit_flow.anim_speed_min = 0.0
	_grit_flow.anim_speed_max = 0.0
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_dust_mat.vertex_color_use_as_albedo = true
	_dust_mat.albedo_color = Color(0.46, 0.44, 0.41)
	_dust_mat.albedo_texture = _puff_texture()
	_dust_mesh = QuadMesh.new()
	_dust_mesh.size = Vector2(0.5, 0.5)
	_dust_flow = ParticleProcessMaterial.new()
	_dust_flow.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_dust_flow.emission_sphere_radius = 0.12
	_dust_flow.direction = Vector3(0, 0, -1)
	_dust_flow.spread = 80.0
	_dust_flow.initial_velocity_min = 0.3
	_dust_flow.initial_velocity_max = 1.3
	_dust_flow.gravity = Vector3(0, 0.25, 0)
	_dust_flow.damping_min = 1.2
	_dust_flow.damping_max = 2.0
	_dust_flow.angle_max = 360.0
	_dust_flow.scale_min = 0.6
	_dust_flow.scale_max = 1.5
	var swell := Curve.new()
	swell.add_point(Vector2(0.0, 0.35))
	swell.add_point(Vector2(1.0, 1.0))
	var swell_tex := CurveTexture.new()
	swell_tex.curve = swell
	_dust_flow.scale_curve = swell_tex
	var thin := Gradient.new()
	thin.set_color(0, Color(1, 1, 1, 0.26))
	thin.set_color(1, Color(1, 1, 1, 0.0))
	var thin_tex := GradientTexture1D.new()
	thin_tex.gradient = thin
	_dust_flow.color_ramp = thin_tex
	# SPARKS: steel on stone. Short hot streaks laid along the way they fly,
	# thrown out off the face, falling, and out in a third of a second.
	var spark := StandardMaterial3D.new()
	spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark.vertex_color_use_as_albedo = true
	spark.albedo_color = Color(2.6, 1.7, 0.7)
	spark.albedo_texture = _puff_texture()
	spark.cull_mode = BaseMaterial3D.CULL_DISABLED
	spark.disable_fog = true
	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2(0.014, 0.15)
	_spark_mesh.material = spark
	_spark_flow = ParticleProcessMaterial.new()
	_spark_flow.particle_flag_align_y = true
	_spark_flow.direction = Vector3(0, 0, -1)
	_spark_flow.spread = 62.0
	_spark_flow.initial_velocity_min = 2.5
	_spark_flow.initial_velocity_max = 9.0
	_spark_flow.gravity = Vector3(0, -9.0, 0)
	_spark_flow.damping_min = 1.0
	_spark_flow.damping_max = 3.0
	_spark_flow.scale_min = 0.45
	_spark_flow.scale_max = 1.3
	var cool := Gradient.new()
	cool.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	cool.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 0.75, 0.4, 1), Color(0.9, 0.25, 0.05, 0)])
	var cool_tex := GradientTexture1D.new()
	cool_tex.gradient = cool
	_spark_flow.color_ramp = cool_tex
	add_to_group(Prewarm.GROUP)


## A soft round blot for the dust.
func _puff_texture() -> Texture2D:
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = fade
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex


## FIRST TIMES (SCRIPT_prewarm.gd): a blow's grit and dust, its sparks and their
## flash, and a loose stone.
func warm(stage: Node3D) -> void:
	var at := stage.global_position
	var before := get_child_count()
	_burst(at, Vector3.UP, 4, 2)
	_sparks(at, stage.global_basis.z)
	if _flora != null and _flora.rock_mesh(0) != null:
		var body := _stone_body(0, 0.2)
		add_child(body)
		body.global_position = at - stage.global_basis.x * 0.5
	Prewarm.gather(self, before, stage)


## How many blows a boulder of this width (metres) takes.
static func blows_for(span: float) -> int:
	return clampi(int(round(span * 2.2)) + 2, 3, 12)


## How many stones a boulder of this width breaks into at the end.
static func yield_of(span: float) -> int:
	return clampi(int(round(span * span * 1.6)) + 1, 2, 14)


## What a swing from `from` along `dir` would land on: a boulder, or nothing.
func aimed(from: Vector3, dir: Vector3) -> bool:
	return _flora != null and not _flora.rock_on(from, dir, reach, _skip()).is_empty()


## How far along `dir` the boulder a swing would meet is, metres; -1 if none.
func rock_at(from: Vector3, dir: Vector3) -> float:
	if _flora == null:
		return -1.0
	var rock := _flora.rock_on(from, dir, reach, _skip())
	return from.distance_to(rock["at"]) if not rock.is_empty() else -1.0


## The point strikes fire: a spray of sparks off the face and a blink of light.
func _sparks(at: Vector3, out: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = _rng.randi_range(18, 30)
	p.lifetime = 0.34
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.6
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.process_material = _spark_flow
	p.draw_pass_1 = _spark_mesh
	p.visibility_aabb = AABB(Vector3.ONE * -6.0, Vector3.ONE * 12.0)
	add_child(p)
	p.global_transform = Transform3D(Basis.looking_at(out, Vector3.UP if absf(out.y) < 0.95 else Vector3.RIGHT), at + out * 0.03)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.72, 0.38)
	flash.light_energy = 2.4
	flash.omni_range = 3.5
	flash.shadow_enabled = false
	add_child(flash)
	flash.global_position = at + out * 0.2
	var fade := create_tween()
	fade.tween_property(flash, "light_energy", 0.0, 0.14)
	fade.tween_callback(flash.queue_free)


## A swing of the pickaxe from `from` along `dir`. True if it met a boulder.
func strike(from: Vector3, dir: Vector3) -> bool:
	if _flora == null:
		return false
	var rock := _flora.rock_on(from, dir, reach, _skip())
	if rock.is_empty():
		return false
	var at: Vector3 = rock["at"]
	var out: Vector3 = rock["normal"]
	var span := float(rock["span"])
	var origin: Vector3 = rock["origin"]
	var landed := int(_blows.get(origin, 0)) + 1
	var needed := blows_for(span)
	_burst(at, out, 22, 7)
	_sparks(at, out)
	if landed < needed:
		_blows[origin] = landed
		# Every other blow a stone comes away where the point went in.
		if landed % 2 == 0:
			_loose(int(rock["kind"]), at + out * 0.12, out * 2.2 + Vector3.UP * 1.6)
		return true
	# THE LAST BLOW: the boulder goes, and a heap of its own rock is left where
	# it sat, thrown a little outward from its middle.
	_blows.erase(origin)
	_flora.quarry(rock)
	var centre: Vector3 = rock["centre"]
	var half := span * 0.5
	_burst(centre, Vector3.UP, 60, 26, half * 0.7)
	for n in yield_of(span):
		var off := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 1), _rng.randf_range(-1, 1)).normalized() * half * _rng.randf_range(0.15, 0.7)
		_loose(int(rock["kind"]), centre + off + Vector3.UP * 0.1, off.normalized() * _rng.randf_range(0.8, 2.6) + Vector3.UP * _rng.randf_range(0.6, 2.2))
	return true


func _skip() -> Array[RID]:
	var skip: Array[RID] = []
	if _explorer is CollisionObject3D:
		skip.append((_explorer as CollisionObject3D).get_rid())
	for entry in _stones:
		skip.append((entry[0] as RigidBody3D).get_rid())
	return skip


## One stone, loose in the world and on its way.
func _loose(kind: int, at: Vector3, push: Vector3) -> void:
	while _stones.size() >= max_stones:
		(_stones.pop_front()[0] as Node).queue_free()
	var body := _stone_body(kind, _rng.randf_range(0.2, 0.34))
	add_child(body)
	body.global_transform = Transform3D(Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)), at)
	body.linear_velocity = push
	body.angular_velocity = Vector3(_rng.randf_range(-5, 5), _rng.randf_range(-5, 5), _rng.randf_range(-5, 5))
	_stones.append([body, 0.0])


## A stone `width` metres across: one of the boulders' own low meshes brought
## down to the hand, a little squashed so no two look alike.
func _stone_body(kind: int, width: float) -> RigidBody3D:
	var mesh := _flora.rock_mesh(kind)
	var box := mesh.get_aabb()
	var k := width / maxf(box.get_longest_axis_size(), 0.01)
	var squash := Vector3(_rng.randf_range(0.8, 1.15), _rng.randf_range(0.65, 1.0), _rng.randf_range(0.8, 1.15)) * k
	var body := RigidBody3D.new()
	body.mass = 2600.0 * width * width * width * 0.5
	body.angular_damp = 1.6
	body.linear_damp = 0.2
	var friction := PhysicsMaterial.new()
	friction.friction = 0.9
	friction.bounce = 0.12
	body.physics_material_override = friction
	if not _shapes.has(kind):
		_shapes[kind] = (mesh as ArrayMesh).create_convex_shape(true, true)
	var cs := CollisionShape3D.new()
	cs.shape = _shapes[kind]
	cs.transform = Transform3D(Basis.from_scale(squash), -box.get_center() * squash)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _rock
	mi.transform = cs.transform
	body.add_child(mi)
	return body


## Grit thrown out of the rock along `out`, and a breath of dust with it.
func _burst(at: Vector3, out: Vector3, grit: int, dust: int, wide := 0.0) -> void:
	var facing := Basis.looking_at(out, Vector3.UP if absf(out.y) < 0.95 else Vector3.RIGHT)
	for pass_ in [[grit, 0.9, _grit_flow, _grit_mesh, _grit_mat], [dust, 1.5, _dust_flow, _dust_mesh, _dust_mat]]:
		var p := GPUParticles3D.new()
		p.amount = int(pass_[0])
		p.lifetime = float(pass_[1])
		p.one_shot = true
		p.explosiveness = 0.94
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.process_material = pass_[2]
		p.draw_pass_1 = pass_[3]
		p.material_override = pass_[4]
		p.visibility_aabb = AABB(Vector3.ONE * -10.0, Vector3.ONE * 20.0)
		add_child(p)
		p.global_transform = Transform3D(facing.scaled(Vector3.ONE * (1.0 + wide * 3.0)), at)
		p.emitting = true
		get_tree().create_timer(float(pass_[1]) + 0.6).timeout.connect(p.queue_free)


## Stones that have had a moment to fall are gathered by walking up to them.
func _process(delta: float) -> void:
	if _stones.is_empty() or _explorer == null:
		return
	var here := _explorer.global_position + Vector3(0, 0.9, 0)
	for i in range(_stones.size() - 1, -1, -1):
		var entry: Array = _stones[i]
		var body: RigidBody3D = entry[0]
		entry[1] = float(entry[1]) + delta
		if body.global_position.y < -500.0:
			_stones.remove_at(i)
			body.queue_free()
			continue
		if float(entry[1]) < 0.9 or body.global_position.distance_to(here) > gather_radius:
			continue
		if _inventory == null or int(_inventory.call(&"add", "stone", 1)) > 0:
			continue          # nowhere to put it
		_stones.remove_at(i)
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
		var pull := create_tween()
		pull.tween_property(body, "global_position", here, 0.16)
		pull.parallel().tween_property(body, "scale", Vector3.ONE * 0.15, 0.16)
		pull.tween_callback(body.queue_free)
