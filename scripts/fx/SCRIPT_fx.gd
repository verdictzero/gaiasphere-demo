class_name Fx
extends RefCounted

# THE EFFECTS LIBRARY: fire, smoke and explosions by name.
#
#   Fx.spawn(self, "campfire", Vector3(10, 0, 4))           a fire that burns until freed
#   Fx.spawn(self, "explosion_large", hit_point, 1.5)       goes off once and frees itself
#   Fx.stop(node)                                           put a burning one out gently
#   Fx.names()                                              every effect there is
#
# What there is to spawn is written in assets/fx/fx_catalogue.json (by
# tools/build_fx_library.py, which also writes docs/FX_CATALOGUE.md for people):
# the textures (flipbooks, each with its grid of frames) and the effects, each a
# list of LAYERS. A layer is either a light or a set of particles drawing one of
# the textures, and everything a layer can say is read in `_particles` and
# `_light` below. Nothing is loaded until it is first asked for, and what is
# loaded is kept: a second campfire costs no more loading than the first did.
#
# An effect is a Node3D with its layers as children: put it anywhere, turn it,
# scale it, move it (layers marked `world` leave their particles behind as it
# goes, which is what makes a fireball's tail).

const CATALOGUE := "res://assets/fx/fx_catalogue.json"
const FOLDER := "res://assets/fx/"

static var _data := {}
static var _materials := {}
static var _quads := {}


static func _catalogue() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(CATALOGUE)
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		_data = parsed if parsed is Dictionary else {"textures": {}, "effects": {}}
	return _data


## Every effect's name.
static func names() -> PackedStringArray:
	var out := PackedStringArray((_catalogue()["effects"] as Dictionary).keys())
	out.sort()
	return out


## What the catalogue says of one effect: {"loop", "seconds", "about", "layers"}, or {}.
static func describe(effect: String) -> Dictionary:
	return (_catalogue()["effects"] as Dictionary).get(effect, {})


## Make `effect` under `parent` at `at` (in the parent's own space), `size` times
## its written size. One-shots free themselves when they are done; a looping one
## is yours to free, or to `stop`. Null if there is no such effect.
static func spawn(parent: Node, effect: String, at := Vector3.ZERO, size := 1.0) -> Node3D:
	var made := describe(effect)
	if made.is_empty():
		push_warning("Fx: no effect called '%s'" % effect)
		return null
	var root := Node3D.new()
	root.name = "Fx_" + effect
	root.position = at
	root.scale = Vector3.ONE * size
	root.set_meta(&"fx", effect)
	for layer in made["layers"]:
		var node: Node3D = _light(layer) if String(layer["type"]) == "light" else _particles(layer, bool(made["loop"]))
		if node != null:
			root.add_child(node)
	parent.add_child(root)
	if not bool(made["loop"]):
		# Long enough for the last particle let go to finish.
		var longest := float(made.get("seconds", 1.0))
		for layer in made["layers"]:
			if String(layer["type"]) == "particles":
				longest = maxf(longest, float(layer.get("lifetime", 1.0)) * (1.0 if bool(layer.get("one_shot", true)) else 2.0))
		root.get_tree().create_timer(longest + 0.4).timeout.connect(root.queue_free)
	return root


## Put a looping effect out: nothing new is let go, its lights die down, and it
## is freed once what is in the air has gone.
static func stop(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var longest := 0.5
	for child in node.get_children():
		if child is GPUParticles3D:
			(child as GPUParticles3D).emitting = false
			longest = maxf(longest, (child as GPUParticles3D).lifetime)
		elif child is OmniLight3D:
			child.set_meta(&"dying", true)
			child.create_tween().tween_property(child, "light_energy", 0.0, 0.6)
	node.get_tree().create_timer(longest + 0.2).timeout.connect(node.queue_free)


# ------------------------------------------------------------------ a layer of particles

## WHAT A PARTICLE LAYER CAN SAY (all but `texture` have a default):
##   texture   which flipbook                    amount, lifetime
##   play      "through": each particle plays the book once over its life
##             "pick": each shows one frame, chosen at random     "one": the first frame
##   size      metres across, at its birth       grow: times that size by its death
##   blend     "mix" (default) or "add"          lit: takes the world's light (smoke) rather than glowing
##   color     [r, g, b] or [r, g, b, a]         fade: "in_out", "out", or none
##   lift      metres above the node it is born  spread: radius it is born within
##   line      born along x over this length     column: born up y over this height
##   rise      speed upward                      drift: sideways wander
##   burst     thrown outward at this speed      gravity: pulled down by this
##   wind      [x, y, z] steady push             turn: degrees a second it spins, either way
##   flat      lies on the ground, not facing the eye (rings)
##   align     "x": drawn lying along the node's x, not turned to the eye (trails, flashes)
##   world     particles stay where they were born as the node moves
##   one_shot  let go all at once and not again (the default for effects that do not loop)
static func _particles(layer: Dictionary, looping: bool) -> GPUParticles3D:
	var name := String(layer["texture"])
	var tex_info: Dictionary = (_catalogue()["textures"] as Dictionary).get(name, {})
	if tex_info.is_empty():
		return null
	var cols := int(tex_info["cols"])
	var rows := int(tex_info["rows"])
	var play := String(layer.get("play", "through"))
	var add := String(layer.get("blend", "mix")) == "add"
	var lit := bool(layer.get("lit", false))
	var flat := bool(layer.get("flat", false))
	var align := String(layer.get("align", ""))
	var p := GPUParticles3D.new()
	p.name = name
	p.amount = int(layer.get("amount", 1))
	p.lifetime = float(layer.get("lifetime", 1.0))
	var once := bool(layer.get("one_shot", not looping))
	p.one_shot = once
	p.explosiveness = 1.0 if once else 0.0
	p.randomness = 0.0 if p.amount == 1 else 0.6
	# A fire that has been burning is already burning: a looping layer starts as
	# if it had been going for a lifetime, not from its first particle.
	p.preprocess = 0.0 if once else p.lifetime
	p.fixed_fps = 0
	p.interpolate = true
	p.local_coords = not bool(layer.get("world", false))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position.y = float(layer.get("lift", 0.0))
	# ---- how they move
	var m := ParticleProcessMaterial.new()
	var spread := float(layer.get("spread", 0.0))
	if layer.has("line"):
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(float(layer["line"]) * 0.5, 0.02, maxf(spread, 0.02))
	elif layer.has("column"):
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(maxf(spread, 0.3), float(layer["column"]) * 0.5, maxf(spread, 0.3))
		p.position.y += float(layer["column"]) * 0.5
	elif spread > 0.0:
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = spread
	var rise := float(layer.get("rise", 0.0))
	var burst := float(layer.get("burst", 0.0))
	var drift := float(layer.get("drift", 0.0))
	if burst > 0.0:
		m.direction = Vector3.UP
		m.spread = 80.0
		m.initial_velocity_min = burst * 0.35
		m.initial_velocity_max = burst
	elif rise > 0.0:
		m.direction = Vector3.UP
		m.spread = rad_to_deg(atan2(drift, rise)) if drift > 0.0 else 0.0
		m.initial_velocity_min = rise * 0.7
		m.initial_velocity_max = rise * 1.2
	else:
		m.initial_velocity_min = 0.0
		m.initial_velocity_max = 0.0
		m.spread = 180.0
	var wind: Array = layer.get("wind", [0.0, 0.0, 0.0])
	m.gravity = Vector3(float(wind[0]), float(wind[1]) - float(layer.get("gravity", 0.0)), float(wind[2]))
	if burst > 0.0 and not layer.has("gravity"):
		m.damping_min = burst * 0.6
		m.damping_max = burst * 1.1
	var turn := float(layer.get("turn", 0.0))
	if turn > 0.0 and align == "" and not flat:
		m.angle_min = 0.0
		m.angle_max = 360.0
		m.angular_velocity_min = -turn
		m.angular_velocity_max = turn
	# ---- how big, and how it comes and goes
	var grow := float(layer.get("grow", 1.0))
	m.scale_min = 0.85 if p.amount > 1 else 1.0
	m.scale_max = 1.2 if p.amount > 1 else 1.0
	if not is_equal_approx(grow, 1.0):
		# (The quad is cut at the size it ends at, or starts at if it shrinks, and
		# the particle is scaled down from that.)
		var swell := Curve.new()
		swell.add_point(Vector2(0.0, 1.0 / grow if grow >= 1.0 else 1.0))
		swell.add_point(Vector2(1.0, 1.0 if grow >= 1.0 else grow))
		var swell_tex := CurveTexture.new()
		swell_tex.curve = swell
		m.scale_curve = swell_tex
	var fade := String(layer.get("fade", ""))
	if fade != "":
		var g := Gradient.new()
		if fade == "in_out":
			g.offsets = PackedFloat32Array([0.0, 0.18, 0.6, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
		else:
			g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
		var ramp := GradientTexture1D.new()
		ramp.gradient = g
		m.color_ramp = ramp
	# ---- which frame of the book
	if play == "through":
		m.anim_speed_min = 1.0
		m.anim_speed_max = 1.0
		if p.amount > 1 and looping:
			m.anim_offset_max = 0.0
	elif play == "pick":
		m.anim_speed_min = 0.0
		m.anim_speed_max = 0.0
		m.anim_offset_min = 0.0
		m.anim_offset_max = 1.0
	p.process_material = m
	# ---- what is drawn
	var cell := Vector2(float(tex_info["cell_w"]), float(tex_info["cell_h"]))
	var size := float(layer.get("size", 1.0)) * maxf(grow, 1.0)
	var quad_size := Vector2(size, size * cell.y / cell.x) if cell.x >= cell.y else Vector2(size * cell.x / cell.y, size)
	var quad_key := [quad_size, flat, align]
	var quad: QuadMesh = _quads.get(quad_key)
	if quad == null:
		quad = QuadMesh.new()
		quad.size = quad_size
		if flat:
			quad.orientation = PlaneMesh.FACE_Y
		_quads[quad_key] = quad
	p.draw_pass_1 = quad
	var col: Array = layer.get("color", [1.0, 1.0, 1.0, 1.0])
	var color := Color(float(col[0]), float(col[1]), float(col[2]), float(col[3]) if col.size() > 3 else 1.0)
	var mat_key := [name, add, lit, flat, align, color, play]
	var mat: StandardMaterial3D = _materials.get(mat_key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_texture = load(FOLDER + String(tex_info["file"]))
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_receive_shadows = true
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if not flat and align == "":
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			mat.billboard_keep_scale = true
		if cols * rows > 1:
			mat.particles_anim_h_frames = cols
			mat.particles_anim_v_frames = rows
			mat.particles_anim_loop = false
			if flat or align != "":
				# (The frames of a book are only read out by the billboard path.)
				mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
				mat.billboard_keep_scale = true
		_materials[mat_key] = mat
	p.material_override = mat
	var reach := size * 2.0 + (rise + burst) * p.lifetime + spread + float(layer.get("line", 0.0)) + float(layer.get("column", 0.0)) + 2.0
	p.visibility_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * reach * 2.0)
	p.emitting = true
	return p


# ------------------------------------------------------------------ a light

## A light layer: `color`, `energy`, `range`, and either `flicker` (0 to 1: how
## restless a steady light is) or `flash` (seconds over which it dies to nothing).
static func _light(layer: Dictionary) -> OmniLight3D:
	var light := OmniLight3D.new()
	var col: Array = layer.get("color", [1.0, 0.6, 0.3])
	light.light_color = Color(float(col[0]), float(col[1]), float(col[2]))
	light.light_energy = float(layer.get("energy", 2.0))
	light.omni_range = float(layer.get("range", 8.0))
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position.y = 0.6
	if layer.has("flash"):
		light.ready.connect(func() -> void:
			light.create_tween().tween_property(light, "light_energy", 0.0, float(layer["flash"])).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD))
	elif float(layer.get("flicker", 0.0)) > 0.0:
		var flicker := FxFlicker.new()
		flicker.base = light.light_energy
		flicker.amount = float(layer["flicker"])
		light.add_child(flicker)
	return light
