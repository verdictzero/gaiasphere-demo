class_name CrashedShuttle
extends Node3D

# THE SHUTTLE, WHERE IT CAME DOWN: under the mere, on the slope of its outer
# shelf, nose down the slope and its open rear door up it, flooded, its red
# lights still on and air still getting out of it. The game starts inside.
#
# IT IS WHERE THE PLAYER ARRIVES. The explorer asks its landing spot four things
# (`settled`, `pod()`, `hatch_spot()`, `hatch_facing()`, as SCRIPT_landing_spot.gd
# answers them) and this answers the same, with a place to stand in the aisle
# behind the seats, looking out of the door and up the slope to the light. You
# come to in the water: swim out and up.
#
# WHERE: on the shore side of the mere (the islet is the other way), at the foot
# of the shelf that falls from the shore to the bed, at a bearing looked for
# round it well away from the causeway. The hull lies along the fall of the
# ground, its tail up the shelf and its nose out on the bed, rolled a little to
# one side.
#
# The hull is solid (its own mesh, both faces), so its floor can be stood on and
# its walls stop you; what grew or lay on the bed under it is cleared.

@export var world_path: NodePath = ^"../GaiaSphere"
@export var water_path: NodePath = ^"../RiverWater"
@export var explorer_path: NodePath = ^"../Explorer"
## The model's size against how it was made (its aisle is 1.8 m high as made).
@export var size := 1.25
## Metres of water wanted over the bed where it lies.
@export var depth := Vector2(9.8, 10.9)
## Degrees it lies over to one side.
@export var roll := 7.0
## How many places on the hull leak air.
@export var leaks := 9

const MODEL := "res://assets/shuttle/shuttle.glb"
## In the model's own metres: where you come to (the aisle floor behind the
## seats), and the places air gets out (engines, seams along the top, the nose,
## the windscreen's edge, the door).
const STAND := Vector3(0.0, -0.88, -1.6)
const LEAKS := [Vector3(-2.6, 0.9, -4.6), Vector3(2.6, 0.9, -4.6), Vector3(0.0, 2.1, -2.2), Vector3(-1.4, 1.6, 0.4),
	Vector3(1.5, 1.5, 1.6), Vector3(0.0, 0.95, 4.4), Vector3(-1.9, 0.5, 3.4), Vector3(3.9, 0.2, -1.5),
	Vector3(-4.0, 0.2, -1.2), Vector3(0.0, 0.9, -5.0), Vector3(0.9, 1.9, -0.8)]

## True once it is placed. (The landing spot's flag, with its meaning.)
var settled := false
var _facing := Vector3.FORWARD
var _centre := Vector2.ZERO
var _heading := Vector2.RIGHT
var _level := 0.0
var _cleared := false


func _ready() -> void:
	var world := get_node_or_null(world_path)
	if world == null or not world.has_method(&"get_field"):
		return
	var field: IslandField = world.call(&"get_field")
	if field == null:
		return
	if not field._ready:
		field.prepare()
	var isl: Variant = field.island_in_cell(field.hub_cell())
	var flows: Variant = field.flows_for(isl) if isl != null else null
	if flows == null or not flows.has_lagoon():
		push_warning("crashed_shuttle: no mere to lie in")
		return
	_level = float(isl.base_y) + float(flows.lagoon_level())
	var middle: Vector2 = flows.lagoon_center()
	var ends: PackedVector2Array = flows.causeway_ends()
	var causeway := (ends[1] - ends[0]).angle()
	# Round the mere, and in from its outer shore, for the best place to lie.
	var best := 1e9
	var at := Vector2.ZERO
	var fall := Vector2.ZERO
	var steep := 0.0
	for i in 180:
		var th := TAU * float(i) / 180.0
		if absf(angle_difference(th, causeway)) < 0.5:
			continue
		var out := Vector2(cos(th), sin(th))
		var shores: Vector2 = flows.lagoon_shores(th)
		for step in 30:
			var r := shores.y - 3.0 - float(step) * 1.5
			if r < (shores.x + shores.y) * 0.5:
				break
			var p := middle + out * r
			var h := field.height_at(p.x, p.y, 1e9)
			var under := _level - h
			if under < depth.x or under > depth.y:
				continue
			var gx := field.height_at(p.x + 2.0, p.y, h) - field.height_at(p.x - 2.0, p.y, h)
			var gz := field.height_at(p.x, p.y + 2.0, h) - field.height_at(p.x, p.y - 2.0, h)
			var grade := Vector2(gx, gz) / 4.0
			var angle := rad_to_deg(atan(grade.length()))
			if angle < 8.0 or angle > 30.0:
				continue
			# Liked best: about 16 degrees, and opposite the causeway.
			var score := absf(angle - 16.0) + absf(absf(angle_difference(th, causeway)) - PI) * 6.0
			if score < best:
				best = score
				at = p
				fall = -grade.normalized()
				steep = atan(grade.length())
	if best >= 1e9:
		push_warning("crashed_shuttle: nowhere on the bed suits")
		return
	var ground := field.height_at(at.x, at.y, 0.0)
	# THE HULL IS LONGER THAN THE SLOPE IS EVEN: the shelf steepens above it and
	# flattens into the bed below. It lies on the two ends of itself, tail up the
	# shelf and nose out on the flat, at whatever pitch that comes to.
	var reach := 4.4 * size
	var tail := field.height_at(at.x - fall.x * reach, at.y - fall.y * reach, ground)
	var nose := field.height_at(at.x + fall.x * reach, at.y + fall.y * reach, ground)
	steep = atan2(tail - nose, reach * 2.0)
	ground = maxf((tail + nose) * 0.5, ground - 0.4)
	# Its nose (the model's +z) down the fall of the ground and along it; its
	# belly on the bed, a hand's depth into the sand.
	var along := Vector3(fall.x * cos(steep), -sin(steep), fall.y * cos(steep)).normalized()
	var up := Vector3(fall.x * sin(steep), cos(steep), fall.y * sin(steep)).normalized()
	var basis := Basis(up.cross(along).normalized(), up, along).rotated(along, deg_to_rad(roll))
	global_transform = Transform3D(basis.scaled(Vector3.ONE * size), Vector3(at.x, ground, at.y) + up * 1.3 * size)
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	add_child(model)
	make_solid(self, model)
	# Its lights are still on: red, and not steady.
	for z in [-2.6, 0.4]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.12, 0.1)
		lamp.light_energy = 1.6
		lamp.omni_range = 5.0
		lamp.position = Vector3(0, 0.55, z)
		# They throw shadows: the seats and the door frame cut the red light up.
		lamp.shadow_enabled = true
		lamp.shadow_bias = 0.06
		lamp.shadow_normal_bias = 1.2
		lamp.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		add_child(lamp)
		var flicker := FxFlicker.new()
		flicker.base = 1.6
		flicker.amount = 0.45
		lamp.add_child(flicker)
	_bubbles()
	var stand := global_transform * STAND
	_facing = -global_basis.z.normalized()               # out of the door, up the slope
	_facing.y = 0.0
	_facing = _facing.normalized()
	_centre = at
	_heading = Vector2(_facing.x, _facing.z)
	set_meta(&"stand", stand)
	settled = true
	print("[shuttle] on the bed at (%.0f, %.0f), %.1f m down, the ground falling %.0f degrees; you come to at %s" % [
		at.x, at.y, _level - ground, rad_to_deg(steep), stand])


func _process(_delta: float) -> void:
	if not settled:
		return
	var explorer := get_node_or_null(explorer_path) as Node3D
	if explorer == null or not bool(explorer.get("arrived")):
		return
	# IN THE CABIN THE WATER DOES NOT LIFT YOU. Left to float, a swimmer goes up
	# to the roof, along it (it slopes up to the door) and out, all in a few
	# seconds and without touching anything. Inside, they hang where they are.
	var inside: Vector3 = global_transform.affine_inverse() * explorer.global_position
	var in_cabin := absf(inside.x) < 1.25 and inside.y > -1.2 and inside.y < 0.9 and inside.z > -4.9 and inside.z < 3.3
	explorer.set(&"buoyancy", 0.0 if in_cabin else 1.0)
	if _cleared:
		return
	_cleared = true
	var flora := get_node_or_null(^"../Flora")
	if flora != null and flora.has_method(&"clear_ground"):
		var flat := Basis(Vector3.UP, atan2(global_basis.z.x, global_basis.z.z))
		flora.call(&"clear_ground", Transform3D(flat, global_position), Vector2(5.4, 6.4) * size)


## SOLID: every mesh of the model, as it is, both faces of it (you are inside as
## well as out). The triangles are put into `ship`'s own frame first, so the
## shapes themselves carry no scale: a scaled shape is not one every physics
## engine will stand for.
static func make_solid(ship: Node3D, model: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Hull"
	ship.add_child(body)
	var size := ship.global_basis.get_scale().x
	# (The body is set against the ship's scale, so it is plain metres inside.)
	body.scale = Vector3.ONE / size
	var into := body.global_transform.affine_inverse()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := mi as MeshInstance3D
		var faces := mesh_node.mesh.get_faces()
		if faces.is_empty():
			continue
		var to_body := into * mesh_node.global_transform
		for i in faces.size():
			faces[i] = to_body * faces[i]
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	return body


# ------------------------------------------------------------------ the landing spot's answers

func pod() -> Node3D:
	return self


func hatch_spot() -> Vector3:
	return get_meta(&"stand") if settled else Vector3.ZERO


func hatch_facing() -> Vector3:
	return _facing


func landing_centre() -> Vector2:
	return _centre


func landing_heading() -> Vector2:
	return _heading


# ------------------------------------------------------------------ air getting out

## A bubble: a thin bright rim, a faint body, and a glint high on one side.
static func bubble_texture() -> Texture2D:
	var side := 64
	var img := Image.create(side, side, true, Image.FORMAT_RGBA8)
	for y in side:
		for x in side:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(side) * 2.0 - Vector2.ONE
			var r := p.length()
			var rim := smoothstep(0.62, 0.9, r) * (1.0 - smoothstep(0.9, 1.0, r))
			var body := (1.0 - smoothstep(0.85, 0.97, r)) * 0.1
			var glint := 1.0 - smoothstep(0.0, 0.22, (p - Vector2(-0.34, -0.38)).length())
			var a := clampf(rim * 0.85 + body + glint * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.86, 0.95, 1.0, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _bubbles() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = bubble_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# CUT OUT, NOT BLENDED. Under water the whole view is redrawn from a copy of
	# the screen taken before anything see-through is drawn (SHADER_underwater, and
	# the water's own surface from above), so a blended bubble is painted over
	# and never seen. A cut-out one is solid where it is there at all, is in that
	# copy, and is seen: its rim and its glint, with the water showing through
	# its middle.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.38
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	quad.material = mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 8841
	for i in mini(leaks, LEAKS.size()):
		var from: Vector3 = global_transform * (LEAKS[i] as Vector3)
		var climb := maxf(_level - from.y - 0.15, 0.5)
		var p := GPUParticles3D.new()
		p.name = "Leak%d" % i
		# A steady string from most, a fat gout now and then from a few.
		var gout := i % 4 == 3
		p.amount = 70 if gout else 44
		var pace := 1.5 if gout else 1.15
		p.lifetime = climb / pace
		p.explosiveness = 0.75 if gout else 0.0
		p.randomness = 0.5
		p.preprocess = p.lifetime * rng.randf()
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = 0.16 if gout else 0.06
		m.direction = Vector3.UP
		m.spread = 6.0
		m.initial_velocity_min = pace * 0.9
		m.initial_velocity_max = pace * 1.1
		m.gravity = Vector3.ZERO
		# They wander as they climb, and swell a little as the water above thins.
		m.turbulence_enabled = true
		m.turbulence_noise_strength = 0.35
		m.turbulence_noise_scale = 2.2
		m.turbulence_influence_min = 0.03
		m.turbulence_influence_max = 0.09
		m.scale_min = 0.3 if not gout else 0.45
		m.scale_max = 0.95 if not gout else 1.8
		var swell := Curve.new()
		swell.add_point(Vector2(0.0, 0.55))
		swell.add_point(Vector2(1.0, 1.0))
		var swell_tex := CurveTexture.new()
		swell_tex.curve = swell
		m.scale_curve = swell_tex
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.03, 0.97, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var ramp := GradientTexture1D.new()
		ramp.gradient = g
		m.color_ramp = ramp
		p.process_material = m
		p.draw_pass_1 = quad
		p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, climb + 3.0, 6))
		add_child(p)
		p.global_transform = Transform3D(Basis(), from)
