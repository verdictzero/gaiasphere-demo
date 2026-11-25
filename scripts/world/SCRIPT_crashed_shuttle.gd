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
# WHERE: on the shore side of the mere, straight across from the causeway, at
# the foot of the shelf that falls from the shore to the bed, in the divot it
# dug there, with the gouge it ploughed down the beach and the shelf behind it
# (both are terrain: FlowTerrain's crash). The hull lies along the gouge, tail
# up it and nose out on the bed, a little sunk in the sand, rolled a little to
# one side, with heaps of the rock it turned up round the divot's rim and
# either side of the gouge (`debris`: laid down by SCRIPT_flora.gd as boulders,
# so the pickaxe breaks them).
#
# The hull is solid (its own mesh, both faces), so its floor can be stood on and
# its walls stop you; what grew or lay on the bed under it is cleared.

@export var world_path: NodePath = ^"../GaiaSphere"
@export var water_path: NodePath = ^"../RiverWater"
@export var explorer_path: NodePath = ^"../Explorer"
## The model's size against how it was made (its aisle is 1.8 m high as made).
@export var size := 1.25
## Metres its belly is sunk into the sand of its divot.
@export var sunk := 0.4
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
	# The ground has the place dug into it already (FlowTerrain's crash: a divot at
	# the foot of the shelf, and the gouge it ploughed coming down the shore).
	var site: PackedVector2Array = flows.crash_site()
	if site[1] == Vector2.ZERO:
		push_warning("crashed_shuttle: the mere has no crash dug in it")
		return
	var at: Vector2 = site[0]
	var fall: Vector2 = -site[1]
	var steep := 0.0
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
	# A little sunk into the sand of its divot.
	global_transform = Transform3D(basis.scaled(Vector3.ONE * size), Vector3(at.x, ground, at.y) + up * (1.3 * size - sunk))
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	add_child(model)
	# Wear laid over its paint, close to (SCRIPT_detail_layer.gd).
	DetailLayer.apply(model, 0.5)
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


# ------------------------------------------------------------------ what it threw up

## ROCK PILES round the divot and along the gouge: what the hull turned up out of
## the bed and the hill and shouldered aside, in heaps of a few each. They are the
## island's own boulders, laid down with the rest by SCRIPT_flora.gd from this
## list, so they are drawn, solid and broken with the pickaxe like any other
## (SCRIPT_mining.gd). Each is [kind (Flora.BOULDERS), where]: plain metres.
static func debris(field: IslandField, at: Vector2, back: Vector2) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 60317
	var side := Vector2(-back.y, back.x)
	# Heaps: [where, how many, how far they spread, how big the biggest].
	var heaps: Array = []
	# ROUND THE DIVOT, at no regular spacing, some on the rim and some thrown well
	# out past it, none in the mouth of the skid.
	for i in rng.randi_range(7, 12):
		var dir := back.rotated(rng.randf_range(0.5, TAU - 0.5))
		var out := FlowTerrain.CRASH_BOWL * (rng.randf_range(0.85, 1.25) if rng.randf() < 0.7 else rng.randf_range(1.3, 2.0))
		heaps.append([at + dir * out, rng.randi_range(1, 7), rng.randf_range(0.8, 2.8), rng.randf_range(0.5, 1.6)])
	# ALONG THE SKID: wherever it threw them, mostly onto the berms, now and then
	# far out to one side, and a few left lying in the trench itself.
	var along := rng.randf_range(10.0, 16.0)
	while along < FlowTerrain.CRASH_GOUGE * 0.9:
		var wander := 1.2 * sin(along * 0.16) + 2.0 * sin(along * 0.037)
		var wide := lerpf(FlowTerrain.CRASH_WIDE, FlowTerrain.CRASH_WIDE * 0.6, along / FlowTerrain.CRASH_GOUGE)
		var roll := rng.randf()
		var off: float
		if roll < 0.15:
			off = rng.randf_range(-0.5, 0.5) * wide                        # in the trench
		elif roll < 0.8:
			off = (1.0 if rng.randf() < 0.5 else -1.0) * wide * rng.randf_range(0.95, 1.6)   # on a berm
		else:
			off = (1.0 if rng.randf() < 0.5 else -1.0) * wide * rng.randf_range(1.8, 3.5)    # flung
		# Fewer and smaller the further back up the hill, where it hit softest.
		var spent := 1.0 - along / FlowTerrain.CRASH_GOUGE
		heaps.append([at + back * along + side * (wander + off), rng.randi_range(1, 3 + int(5.0 * spent)),
				rng.randf_range(0.5, 2.4), rng.randf_range(0.35, 0.7 + 0.9 * spent)])
		along += rng.randf_range(3.0, 13.0)
	var out: Array = []
	for heap: Array in heaps:
		var centre: Vector2 = heap[0]
		var count: int = heap[1]
		for n in count:
			# Sizes fall away steeply: a few big ones, many small.
			var width := lerpf(0.2, float(heap[3]), pow(rng.randf(), 2.2)) if n > 0 else float(heap[3]) * rng.randf_range(0.8, 1.1)
			var p := centre + Vector2.from_angle(rng.randf() * TAU) * float(heap[2]) * sqrt(rng.randf()) * (0.0 if n == 0 else 1.0)
			var ground := field.height_at(p.x, p.y, 0.0)
			var kind := rng.randi_range(0, Flora.BOULDERS.size() - 1)
			var turn := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)))
			# Not quite round: squashed or stretched a little, each its own way.
			var shape := Vector3(rng.randf_range(0.8, 1.2), rng.randf_range(0.7, 1.1), rng.randf_range(0.8, 1.2)) * width
			out.append([kind, Transform3D(turn * Basis.from_scale(shape), Vector3(p.x, ground - 0.15 * width, p.y))])
	return out


# ------------------------------------------------------------------ air getting out

## A bubble, baked as a ball for a light to work on. Three layers: [0] its colour,
## with how much of it is there (a faint body, more toward the edge where a real
## one turns the light back, and the very thinnest ring of solid wall round the
## rim); [1] a ball's normals, the whole of it, so the sun, the torch and the
## wreck's lamps put their own shine on it where they would; [2] roughness in red
## and metalness in green. No shine is painted on.
static func bubble_layers() -> Array:
	var side := 128
	var colour := Image.create(side, side, true, Image.FORMAT_RGBA8)
	var lie := Image.create(side, side, true, Image.FORMAT_RGBA8)
	var feel := Image.create(side, side, true, Image.FORMAT_RGBA8)
	for y in side:
		for x in side:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(side) * 2.0 - Vector2.ONE
			var r := p.length()
			var inside := 1.0 - smoothstep(0.965, 0.995, r)
			# The body: all but clear face on (a speckle of it, no more), thickening
			# only close to the edge.
			var body := (0.05 + 0.6 * pow(clampf(r, 0.0, 1.0), 9.0)) * inside
			# The wall: a hair's breadth, right at the rim.
			var wall := smoothstep(0.925, 0.95, r) * inside
			colour.set_pixel(x, y, Color(0.97, 1.0, 1.0, clampf(maxf(body, wall), 0.0, 1.0)))
			var flat := p.limit_length(0.985)
			var n := Vector3(flat.x, -flat.y, sqrt(maxf(1.0 - flat.length_squared(), 0.0))).normalized()
			lie.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))
			# Glassy all over, and a little of a mirror.
			feel.set_pixel(x, y, Color(0.12, 0.1, 0.0, 1.0))
	var out: Array = []
	for img: Image in [colour, lie, feel]:
		img.generate_mipmaps()
		out.append(ImageTexture.create_from_image(img))
	return out


func _bubbles() -> void:
	var layers := bubble_layers()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = layers[0]
	mat.normal_enabled = true
	mat.normal_texture = layers[1]
	mat.roughness = 1.0
	mat.roughness_texture = layers[2]
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.metallic = 1.0
	mat.metallic_texture = layers[2]
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	# NOT BLENDED. Under water the whole view is redrawn from a copy of the screen
	# taken before anything see-through is drawn (SHADER_underwater, and the
	# water's own surface from above), so a blended bubble is painted over and
	# never seen. This one is drawn solid, pixel by pixel, as many of its pixels
	# as it is opaque there (a screen-door): it is in that copy, takes light and
	# shadow like anything solid, and still lets the water show through its body.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	mat.alpha_hash_scale = 1.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
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
		# All sizes, from beads to a fist: a string of small ones with the odd big
		# one among them, a gout the other way about.
		m.scale_min = 0.1 if not gout else 0.18
		m.scale_max = 1.25 if not gout else 2.3
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
