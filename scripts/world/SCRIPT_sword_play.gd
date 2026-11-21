class_name SwordPlay
extends Node3D

# WHAT IS IN THE HAND: THE AXE, THE SWORD, AND WHAT THE SWORD THROWS.
#
# The player starts with an axe. It and the sword are items in the hotbar, and
# whichever of them the selected slot holds is the one in the hand; any other
# slot and the hand is empty. Both swing the same way and both cut trees
# (SCRIPT_woodcutting.gd); only the sword charges.
#
#   near the stone:  attack (left mouse / E / right trigger / the touch button) draws it
#   holding it:      left mouse swings, a different cut each time
#                    hold right mouse (left trigger) to charge: motes of light
#                    gather into the blade; release to swing and throw a crescent
#                    of light along the cut
#                    with one button only (touch, E, pad X): tap to swing, hold
#                    to charge
#
# The sword is the stone's own `sword` mesh, lifted out and hung on the explorer's
# camera. The crescent flies straight, lights what it passes, and bursts on the
# first solid thing it meets.

@export var stone_path: NodePath = ^"../SwordStone"
@export var explorer_path: NodePath = ^"../Explorer"
## Metres from the stone within which the sword can be taken.
@export var reach := 3.4
## Seconds of holding before a swing throws a crescent.
@export var charge_time := 0.7
@export var blast_speed := 42.0
@export var blast_life := 2.4
@export var blast_color := Color(0.55, 0.85, 1.0)

# Where the grip is on the model (metres up the stone's frame), and how the blade
# is held: at rest, drawn back to charge, and at the end of the cut.
const GRIP := Vector3(0.0, 2.12, 0.0)
const HAND := Vector3(0.36, -0.42, -0.62)
const REST := Vector3(-24.0, 0.0, -14.0)
const DRAWN := Vector3(38.0, 0.0, -34.0)
const CUT := Vector3(-118.0, 0.0, 38.0)
# The axe model: metres per unit, and where on it (its own units) the hand closes.
const AXE_SCALE := 0.054
const AXE_GRIP := Vector3(0.29, 0.0, 10.6)
# THE CUTS: where the blade starts, where it ends, and how the crescent it throws
# is canted (degrees about the look). One is picked each swing, never the one
# before, and every angle is nudged, so no two swings are the same.
const CUTS := [
	[Vector3(38.0, 0.0, -34.0), Vector3(-118.0, 0.0, 38.0), -62.0],     # down, right to left
	[Vector3(42.0, 8.0, 44.0), Vector3(-112.0, -6.0, -52.0), 62.0],     # down, left to right
	[Vector3(-74.0, -62.0, -18.0), Vector3(-80.0, 68.0, 14.0), -6.0],   # flat sweep to the left
	[Vector3(-80.0, 64.0, 16.0), Vector3(-72.0, -66.0, -16.0), 8.0],    # flat sweep back
	[Vector3(58.0, 0.0, -4.0), Vector3(-126.0, 0.0, 6.0), 90.0],        # overhead chop
	[Vector3(-128.0, 10.0, 34.0), Vector3(34.0, -8.0, -28.0), -48.0],   # rising cut
]

var held := false
var _stone: Node3D
var _explorer: Node3D
var _cam: Camera3D
var _sword: MeshInstance3D
var _pivot: Node3D
var _glow: StandardMaterial3D
var _light: OmniLight3D
var _prompt: Label
var _charge := 0.0
var _charging := false
var _motes: GPUParticles3D
var _last_cut := -1
var _cant := -62.0
var _rng := RandomNumberGenerator.new()
var _swing: Tween
var _axe: Node3D
var _bob: Node3D
var _stride := 0.0           # where in the step the walk is, radians
var _gait := 0.0             # 0 standing .. 1 at a run, eased
var _lag := Vector2.ZERO     # how far the hand trails a turn of the head
var _drop := 0.0             # the hand left behind by a jump or a fall
var _look_was := Basis()
var _bag: Inventory
## What is in the hand now: "axe", "sword" or "".
var tool := ""
var _blasts: Array = []        # [node, velocity, seconds left]


func _ready() -> void:
	_stone = get_node_or_null(stone_path)
	_explorer = get_node_or_null(explorer_path)
	if not InputMap.has_action(&"wv_attack"):
		InputMap.add_action(&"wv_attack", 0.3)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(&"wv_attack", click)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		InputMap.action_add_event(&"wv_attack", key)
		var trigger := InputEventJoypadMotion.new()
		trigger.axis = JOY_AXIS_TRIGGER_RIGHT
		trigger.axis_value = 1.0
		InputMap.action_add_event(&"wv_attack", trigger)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_X
		InputMap.action_add_event(&"wv_attack", pad)
	if not InputMap.has_action(&"wv_charge"):
		InputMap.add_action(&"wv_charge", 0.3)
		var rmb := InputEventMouseButton.new()
		rmb.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(&"wv_charge", rmb)
		var lt := InputEventJoypadMotion.new()
		lt.axis = JOY_AXIS_TRIGGER_LEFT
		lt.axis_value = 1.0
		InputMap.action_add_event(&"wv_charge", lt)
	_rng.randomize()
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_prompt = Label.new()
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 0.68
	_prompt.anchor_bottom = 0.74
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_override(&"font", load("res://branding/fonts/RobotoCondensed-Regular.ttf"))
	_prompt.add_theme_font_size_override(&"font_size", 24)
	_prompt.add_theme_color_override(&"font_color", Color(0.8, 0.95, 1.0))
	_prompt.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override(&"outline_size", 6)
	_prompt.text = "TAKE THE SWORD"
	_prompt.visible = false
	layer.add_child(_prompt)


func _find_parts() -> bool:
	if _sword != null and _cam != null:
		return true
	if _stone == null or _explorer == null:
		return false
	_sword = _stone.find_child("sword", true, false) as MeshInstance3D
	_cam = get_viewport().get_camera_3d()
	return _sword != null and _cam != null


func _process(delta: float) -> void:
	_fly_blasts(delta)
	if not _find_parts():
		return
	_ensure_hand()
	_sway(delta)
	if Inventory.menu_open or GraphicsMenu.menu_open or EnvironmentMenu.menu_open:
		return
	if not held:
		var near: bool = _explorer.global_position.distance_to(_stone.get_child(0).global_position) < reach
		_prompt.visible = near
		if near and Input.is_action_just_pressed(&"wv_attack") and _mouse_ready():
			_take()
			return
	# The hand follows the hotbar.
	var now := ""
	if _bag != null and _bag.slots[_bag.selected] != null:
		now = String(_bag.slots[_bag.selected][0])
	if now != "axe" and not (now == "sword" and held):
		now = ""
	if now != tool:
		tool = now
		_charging = false
		_charge = 0.0
		if _swing != null:
			_swing.kill()
		_pivot.rotation_degrees = REST
		# The new one comes up into the hand from below.
		_pivot.position = HAND + Vector3(0, -0.5, 0.15)
		create_tween().tween_property(_pivot, "position", HAND, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_axe.visible = tool == "axe"
	if held:
		_sword.visible = tool == "sword"
	if tool == "":
		_light.light_energy = 0.0
		_motes.emitting = false
		return
	var hold := Input.is_action_pressed(&"wv_charge") and tool == "sword"
	if not _swinging() and not _charging:
		if hold and Input.is_action_just_pressed(&"wv_charge"):
			_charging = true
			_charge = 0.0
		elif Input.is_action_just_pressed(&"wv_attack") and _mouse_ready():
			if tool == "axe" or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not DisplayServer.is_touchscreen_available()):
				_cut(false)          # the mouse has a button of its own for charging
			else:
				_charging = true
				_charge = 0.0
	if _charging:
		hold = hold or Input.is_action_pressed(&"wv_attack")
		_charge = minf(_charge + delta / charge_time, 1.0)
		# Drawn back as it charges, with a tremble when it is full.
		var pose := REST.lerp(DRAWN, smoothstep(0.0, 1.0, _charge))
		if _charge >= 1.0:
			pose += Vector3(sin(Time.get_ticks_msec() * 0.05), 0.0, cos(Time.get_ticks_msec() * 0.043)) * 1.2
		_pivot.rotation_degrees = pose
		if not hold:
			_charging = false
			_cut(_charge >= 1.0)
	var lit := _charge if _charging else move_toward(_glow.albedo_color.a, 0.0, delta * 3.0)
	_glow.albedo_color = Color(blast_color.r, blast_color.g, blast_color.b, lit)
	_light.light_energy = lit * 3.0
	# Motes are drawn in from all round while it charges, thicker as it fills.
	_motes.emitting = _charging
	_motes.amount_ratio = clampf(0.25 + _charge * 0.75, 0.0, 1.0)
	_motes.speed_scale = 0.8 + _charge * 0.9


## WHAT IS HELD MOVES WITH WHOEVER HOLDS IT. Walking rocks it side to side and
## dips it twice a stride; turning the head leaves it a little behind; a jump or
## a drop leaves it behind too; and standing still it rises and falls with a
## breath. All of it small: felt more than seen.
func _sway(delta: float) -> void:
	var body := _explorer as CharacterBody3D
	var flat := Vector2.ZERO
	var rising := 0.0
	var afoot := false
	if body != null:
		flat = Vector2(body.velocity.x, body.velocity.z)
		rising = body.velocity.y
		afoot = body.is_on_floor() and not bool(body.get("flying"))
	var pace := flat.length()
	_gait = lerpf(_gait, clampf(pace / 6.0, 0.0, 1.0) if afoot else 0.0, 1.0 - exp(-delta * 8.0))
	_stride = fposmod(_stride + delta * (5.5 + pace * 0.9) * (1.0 if afoot else 0.0), TAU)
	# How far the view has turned since the last frame, in the camera's own frame.
	var turn := _look_was.inverse() * _cam.global_basis
	_look_was = _cam.global_basis
	var yaw := atan2(turn.z.x, turn.z.z)
	var pitch := -asin(clampf(turn.z.y, -1.0, 1.0))
	_lag = (_lag + Vector2(yaw, pitch) * 0.9).limit_length(0.12)
	_lag = _lag.lerp(Vector2.ZERO, 1.0 - exp(-delta * 9.0))
	_drop = lerpf(_drop, clampf(-rising * 0.006, -0.05, 0.05) if not afoot else 0.0, 1.0 - exp(-delta * 7.0))
	var breath := sin(Time.get_ticks_msec() * 0.0016)
	_bob.position = Vector3(
			sin(_stride) * 0.014 * _gait + _lag.x * 0.22,
			-absf(cos(_stride)) * 0.02 * _gait + breath * 0.0035 + _drop + _lag.y * 0.2,
			_gait * 0.012)
	_bob.rotation = Vector3(
			-_lag.y * 0.7 + cos(_stride * 2.0) * 0.012 * _gait,
			-_lag.x * 0.8,
			sin(_stride) * 0.03 * _gait + _lag.x * 0.5)


## A click that is only capturing the mouse is not a swing.
func _mouse_ready() -> bool:
	return DisplayServer.is_touchscreen_available() or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _swinging() -> bool:
	return _swing != null and _swing.is_running()


## The hand itself, the axe in it, and the axe in the bag: made once, as soon
## as there is a camera to hang them on.
func _ensure_hand() -> void:
	if _pivot != null:
		return
	_bag = get_node_or_null(^"../Inventory") as Inventory
	_pivot = Node3D.new()
	_pivot.name = "Hand"
	_pivot.position = HAND
	_pivot.rotation_degrees = REST
	# The hand hangs from a node of its own that carries the sway of walking, so
	# the swings (which move the hand itself) and the bob never fight over it.
	_bob = Node3D.new()
	_bob.name = "HandBob"
	_cam.add_child(_bob)
	_bob.add_child(_pivot)
	_look_was = _cam.global_basis
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow.albedo_color = Color(blast_color.r, blast_color.g, blast_color.b, 0.0)
	_light = OmniLight3D.new()
	_light.light_color = blast_color
	_light.light_energy = 0.0
	_light.omni_range = 7.0
	_light.position = Vector3(0, 0.8, 0)
	_pivot.add_child(_light)
	_motes = _gather_motes()
	_motes.position = Vector3(0, 0.75, 0)
	_pivot.add_child(_motes)
	# THE AXE. The model lies along its handle (the head at one end, the blade
	# out to one side) and is fifteen units long: stood up on its grip, the blade
	# turned to face away from the player, and brought down to 85 cm.
	_axe = Node3D.new()
	_axe.name = "Axe"
	var model: Node3D = (load("res://assets/axe/axe.glb") as PackedScene).instantiate()
	var stand := Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)).scaled(Vector3.ONE * AXE_SCALE)
	model.transform = Transform3D(stand, -(stand * AXE_GRIP))
	_axe.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as MeshInstance3D).layers = 1 << (WorldReflection.MIRROR_LAYER - 1)      # the steel mirrors the world too
	_axe.visible = false
	# The blade leads, away from whoever holds it, turned a little across the view
	# so some of the head's flat shows; and the whole axe is brought in towards the
	# eye, where an arm would carry it.
	_axe.rotation_degrees = Vector3(0.0, 28.0, 0.0)
	_axe.position = Vector3(-0.05, 0.02, 0.2)
	_pivot.add_child(_axe)
	if _bag != null and _bag.count_of("axe") == 0:
		_bag.add("axe", 1)


func _take() -> void:
	held = true
	_prompt.visible = false
	_ensure_hand()
	_sword.get_parent().remove_child(_sword)
	_pivot.add_child(_sword)
	# Turned over so the blade stands up out of the hand, the grip at the pivot.
	_sword.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(GRIP.x, GRIP.y, GRIP.z))
	_sword.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sword.material_overlay = _glow
	# Into the bag, and into the hand: its slot becomes the one selected.
	if _bag != null:
		if _bag.count_of("sword") == 0:
			_bag.add("sword", 1)
		for i in Inventory.HOTBAR:
			if _bag.slots[i] != null and _bag.slots[i][0] == "sword":
				_bag.selected = i


## Sparks born on a shell round the blade and pulled into it, shrinking as they
## arrive. They live in the hand's space, so they stay with the sword.
func _gather_motes() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 140
	p.lifetime = 0.62
	p.emitting = false
	p.local_coords = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	m.emission_sphere_radius = 0.62
	m.gravity = Vector3.ZERO
	m.radial_velocity_min = -1.05
	m.radial_velocity_max = -0.85
	m.orbit_velocity_min = -0.6
	m.orbit_velocity_max = 0.6
	m.scale_min = 0.5
	m.scale_max = 1.3
	var size := Curve.new()
	size.add_point(Vector2(0.0, 0.0))
	size.add_point(Vector2(0.18, 1.0))
	size.add_point(Vector2(1.0, 0.15))
	var size_tex := CurveTexture.new()
	size_tex.curve = size
	m.scale_curve = size_tex
	p.process_material = m
	var dot := GradientTexture2D.new()
	dot.width = 32
	dot.height = 32
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = g
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = dot
	mat.albedo_color = Color(blast_color.r * 1.6, blast_color.g * 1.6, blast_color.b * 1.6, 1.0)
	mat.disable_fog = true
	mat.no_depth_test = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.028, 0.028)
	quad.material = mat
	p.draw_pass_1 = quad
	return p


func _cut(charged: bool) -> void:
	var pick := _rng.randi_range(0, CUTS.size() - 1)
	if pick == _last_cut:
		pick = (pick + 1 + _rng.randi_range(0, CUTS.size() - 2)) % CUTS.size()
	_last_cut = pick
	var nudge := func(v: Vector3, by: float) -> Vector3:
		return v + Vector3(_rng.randf_range(-by, by), _rng.randf_range(-by, by), _rng.randf_range(-by, by))
	var from: Vector3 = nudge.call(CUTS[pick][0], 7.0)
	var to: Vector3 = nudge.call(CUTS[pick][1], 9.0)
	_cant = float(CUTS[pick][2]) + _rng.randf_range(-9.0, 9.0)
	var wind := _rng.randf_range(0.07, 0.11) if not charged else 0.06
	var fall := _rng.randf_range(0.095, 0.14)
	var back := _rng.randf_range(0.28, 0.42)
	# The arm goes with the blade: reaching along the cut, then settling back.
	var reach_to := HAND + Vector3(_rng.randf_range(-0.12, 0.06), _rng.randf_range(-0.06, 0.08), _rng.randf_range(-0.26, -0.12))
	_swing = create_tween()
	_swing.tween_property(_pivot, "rotation_degrees", from, wind).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_swing.parallel().tween_property(_pivot, "position", HAND + Vector3(0.04, 0.05, 0.08), wind)
	_swing.tween_property(_pivot, "rotation_degrees", to, fall).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_swing.parallel().tween_property(_pivot, "position", reach_to, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing.tween_callback(_bite)
	if charged:
		_swing.tween_callback(_throw)
	# Carried a little past the end of the cut before it comes home.
	_swing.tween_property(_pivot, "rotation_degrees", to + (to - from).normalized() * _rng.randf_range(5.0, 11.0), 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_swing.tween_property(_pivot, "rotation_degrees", REST + nudge.call(Vector3.ZERO, 2.0), back).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_swing.parallel().tween_property(_pivot, "position", HAND, back).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The cut lands: a tree in reach takes a bite (SCRIPT_woodcutting.gd).
func _bite() -> void:
	var wood := get_node_or_null(^"../Woodcutting")
	if wood != null:
		wood.call(&"strike", _cam.global_position, -_cam.global_basis.z)


# ------------------------------------------------------------------ the crescent

## A crescent: an arc bulging forward, standing up as a band so it is seen from
## behind as well as from the side (a flat arc would be edge-on to whoever threw
## it). Widest in the middle, pointed at the horns, bright along its middle line
## and fading to both edges; drawn additively, unlit.
func _crescent_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 28
	var rows: Array = []
	for i in steps + 1:
		var f := float(i) / float(steps)
		var a := lerpf(-1.2, 1.2, f)                          # along the arc, radians
		var half := 0.34 * pow(sin(f * PI), 0.75)             # half the band's height here
		var p := Vector3(sin(a) * 1.5, 0.0, 1.5 - cos(a) * 1.5)   # the leading point at the origin
		rows.append([p + Vector3.UP * half, p, p - Vector3.UP * half])
	for i in steps:
		for band in [[0, 1, 0.0, 1.0], [1, 2, 1.0, 0.0]]:
			var a0: Vector3 = rows[i][band[0]]
			var a1: Vector3 = rows[i + 1][band[0]]
			var b0: Vector3 = rows[i][band[1]]
			var b1: Vector3 = rows[i + 1][band[1]]
			for v in [[a0, band[2]], [a1, band[2]], [b1, band[3]], [a0, band[2]], [b1, band[3]], [b0, band[3]]]:
				st.set_color(Color(1, 1, 1, v[1]))
				st.add_vertex(v[0])
	return st.commit()


func _throw() -> void:
	var blast := MeshInstance3D.new()
	blast.mesh = _crescent_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(blast_color.r * 1.3, blast_color.g * 1.3, blast_color.b * 1.3, 1.0)
	mat.disable_fog = true
	blast.material_override = mat
	blast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lamp := OmniLight3D.new()
	lamp.light_color = blast_color
	lamp.light_energy = 2.5
	lamp.omni_range = 16.0
	blast.add_child(lamp)
	add_child(blast)
	# Along the look, canted with the cut (down and across).
	var forward := -_cam.global_basis.z
	blast.global_basis = _cam.global_basis * Basis(Vector3.FORWARD, deg_to_rad(_cant))
	blast.global_position = _cam.global_position + forward * 1.4 - _cam.global_basis.y * 0.15
	_blasts.append([blast, forward * blast_speed, blast_life])


func _fly_blasts(delta: float) -> void:
	if _blasts.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for i in range(_blasts.size() - 1, -1, -1):
		var b: Array = _blasts[i]
		var node: MeshInstance3D = b[0]
		var from := node.global_position
		var to: Vector3 = from + (b[1] as Vector3) * delta
		var q := PhysicsRayQueryParameters3D.create(from, to)
		if _explorer is CollisionObject3D:
			q.exclude = [(_explorer as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q) if space != null else {}
		b[2] = float(b[2]) - delta
		if not hit.is_empty() or float(b[2]) <= 0.0:
			_burst(hit.get("position", to), not hit.is_empty(), (b[1] as Vector3).normalized())
			node.queue_free()
			_blasts.remove_at(i)
			continue
		node.global_position = to
		# It widens as it goes and thins out at the end of its life.
		node.scale = Vector3.ONE * (1.0 + (blast_life - float(b[2])) * 0.55)
		(node.material_override as StandardMaterial3D).albedo_color.a = clampf(float(b[2]) / 0.5, 0.0, 1.0)


func _burst(at: Vector3, solid: bool, heading := Vector3.ZERO) -> void:
	if not solid:
		return
	var wood := get_node_or_null(^"../Woodcutting")
	if wood != null:
		wood.call(&"blast", at, heading)
	var flash := OmniLight3D.new()
	flash.light_color = blast_color
	flash.light_energy = 14.0
	flash.omni_range = 22.0
	add_child(flash)
	flash.global_position = at
	var out := create_tween()
	out.tween_property(flash, "light_energy", 0.0, 0.45)
	out.tween_callback(flash.queue_free)
