class_name SwordPlay
extends Node3D

# TAKING THE SWORD, SWINGING IT, AND WHAT IT THROWS.
#
#   near the stone:  attack (left mouse / E / right trigger / the touch button) draws it
#   holding it:      tap attack to swing
#                    hold attack to charge (the blade lights), release to swing and
#                    throw a crescent of light along the cut
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
var _swing: Tween
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
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_prompt = Label.new()
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 0.68
	_prompt.anchor_bottom = 0.74
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override(&"font_size", 26)
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
	if not held:
		var near: bool = _explorer.global_position.distance_to(_stone.get_child(0).global_position) < reach
		_prompt.visible = near
		if near and Input.is_action_just_pressed(&"wv_attack") and _mouse_ready():
			_take()
		return
	if Input.is_action_just_pressed(&"wv_attack") and _mouse_ready() and not _swinging():
		_charging = true
		_charge = 0.0
	if _charging:
		_charge = minf(_charge + delta / charge_time, 1.0)
		# Drawn back as it charges, with a tremble when it is full.
		var pose := REST.lerp(DRAWN, smoothstep(0.0, 1.0, _charge))
		if _charge >= 1.0:
			pose += Vector3(sin(Time.get_ticks_msec() * 0.05), 0.0, cos(Time.get_ticks_msec() * 0.043)) * 1.2
		_pivot.rotation_degrees = pose
		if not Input.is_action_pressed(&"wv_attack"):
			_charging = false
			_cut(_charge >= 1.0)
	var lit := _charge if _charging else move_toward(_glow.albedo_color.a, 0.0, delta * 3.0)
	_glow.albedo_color = Color(blast_color.r, blast_color.g, blast_color.b, lit)
	_light.light_energy = lit * 3.0


## A click that is only capturing the mouse is not a swing.
func _mouse_ready() -> bool:
	return DisplayServer.is_touchscreen_available() or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _swinging() -> bool:
	return _swing != null and _swing.is_running()


func _take() -> void:
	held = true
	_prompt.visible = false
	_pivot = Node3D.new()
	_pivot.name = "SwordHand"
	_pivot.position = HAND
	_pivot.rotation_degrees = REST
	_cam.add_child(_pivot)
	_sword.get_parent().remove_child(_sword)
	_pivot.add_child(_sword)
	# Turned over so the blade stands up out of the hand, the grip at the pivot.
	_sword.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(GRIP.x, GRIP.y, GRIP.z))
	_sword.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow.albedo_color = Color(blast_color.r, blast_color.g, blast_color.b, 0.0)
	_sword.material_overlay = _glow
	_light = OmniLight3D.new()
	_light.light_color = blast_color
	_light.light_energy = 0.0
	_light.omni_range = 7.0
	_light.position = Vector3(0, 0.8, 0)
	_pivot.add_child(_light)
	# Lifted out: it comes up into the hand from below.
	_pivot.position = HAND + Vector3(0, -0.6, 0.2)
	var draw := create_tween()
	draw.tween_property(_pivot, "position", HAND, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _cut(charged: bool) -> void:
	_swing = create_tween()
	_swing.tween_property(_pivot, "rotation_degrees", CUT, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if charged:
		_swing.tween_callback(_throw)
	_swing.tween_property(_pivot, "rotation_degrees", REST, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ the crescent

## A crescent in the XY plane, horns up and down the cut, bright along its leading
## edge and fading back; drawn additively, unlit.
func _crescent_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 28
	var rows: Array = []
	for i in steps + 1:
		var f := float(i) / float(steps)
		var a := lerpf(-1.25, 1.25, f)                       # along the arc, radians
		var thick := 0.42 * pow(sin(f * PI), 0.75)           # fat in the middle, pointed at the horns
		var out := Vector3(sin(a), 0.0, -cos(a))             # bulging forward (-Z)
		rows.append([out * 1.5, out * (1.5 - thick), out * (1.5 - thick * 0.45)])
	for i in steps:
		for band in [[0, 2, 1.0, 0.55], [2, 1, 0.55, 0.0]]:
			var a0: Vector3 = rows[i][band[0]]
			var a1: Vector3 = rows[i + 1][band[0]]
			var b0: Vector3 = rows[i][band[1]]
			var b1: Vector3 = rows[i + 1][band[1]]
			for v in [[a0, band[2]], [a1, band[2]], [b1, band[3]], [a0, band[2]], [b1, band[3]], [b0, band[3]]]:
				st.set_color(Color(1, 1, 1, v[1]))
				st.add_vertex(v[0] + Vector3(0, 0, 1.5))        # the leading edge at the origin
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
	mat.albedo_color = Color(blast_color.r * 3.0, blast_color.g * 3.0, blast_color.b * 3.0, 1.0)
	mat.disable_fog = true
	blast.material_override = mat
	blast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lamp := OmniLight3D.new()
	lamp.light_color = blast_color
	lamp.light_energy = 5.0
	lamp.omni_range = 16.0
	blast.add_child(lamp)
	add_child(blast)
	# Along the look, canted with the cut (down and across).
	var forward := -_cam.global_basis.z
	blast.global_basis = _cam.global_basis * Basis(Vector3.FORWARD, deg_to_rad(-62.0))
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
			_burst(hit.get("position", to), not hit.is_empty())
			node.queue_free()
			_blasts.remove_at(i)
			continue
		node.global_position = to
		# It widens as it goes and thins out at the end of its life.
		node.scale = Vector3.ONE * (1.0 + (blast_life - float(b[2])) * 0.55)
		(node.material_override as StandardMaterial3D).albedo_color.a = clampf(float(b[2]) / 0.5, 0.0, 1.0)


func _burst(at: Vector3, solid: bool) -> void:
	if not solid:
		return
	var flash := OmniLight3D.new()
	flash.light_color = blast_color
	flash.light_energy = 14.0
	flash.omni_range = 22.0
	add_child(flash)
	flash.global_position = at
	var out := create_tween()
	out.tween_property(flash, "light_energy", 0.0, 0.45)
	out.tween_callback(flash.queue_free)
