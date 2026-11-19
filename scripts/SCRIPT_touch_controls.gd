class_name TouchControls
extends Control

# ON-SCREEN CONTROLS FOR A TOUCHSCREEN. Left thumb: a stick that appears where
# the thumb lands, for walking (pushed to its edge, running). Right thumb: drag
# anywhere on the right half to look. Buttons on the right: JUMP (swim or fly
# up while held), DOWN (swim or fly down), RUN (a toggle) and FLY (a toggle).
#
# It drives the same `wv_*` input actions the keyboard and the controller do, so
# the explorer does not know which of them is in use. Shown only where there is
# a touchscreen (or with `force` on, to try it with a mouse). SWORD takes the sword
# at the stone, swings it, and held down charges it.

@export var explorer_path: NodePath = ^"../../Explorer"
@export var force := false
## Radians turned per pixel dragged, at a 1080-high screen.
@export var look_speed := 0.0045

const STICK_RADIUS := 110.0
const DEAD := 0.14
const BUTTONS := [
	# action, label, offset from the bottom-right corner (in button sizes), toggle
	[&"wv_up", "JUMP", Vector2(-1.3, -1.3), false],
	[&"wv_down", "DOWN", Vector2(-2.7, -0.9), false],
	[&"wv_run", "RUN", Vector2(-1.1, -2.9), true],
	[&"wv_fly", "FLY", Vector2(-2.7, -2.5), true],
	[&"wv_attack", "SWORD", Vector2(-4.1, -1.2), false],
]
const MOVES := [&"wv_left", &"wv_right", &"wv_forward", &"wv_back"]

var _explorer: Node
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick := Vector2.ZERO
var _look_touch := -1
var _held := {}            # touch index -> button index
var _on := {}              # toggles that are on


func _ready() -> void:
	_explorer = get_node_or_null(explorer_path)
	visible = force or DisplayServer.is_touchscreen_available()
	set_process_input(visible)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _scale() -> float:
	return size.y / 1080.0


func _button_rect(i: int) -> Rect2:
	var s := 150.0 * _scale()
	var c: Vector2 = size + (BUTTONS[i][2] as Vector2) * s
	return Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			for i in BUTTONS.size():
				if _button_rect(i).grow(12.0).has_point(t.position):
					_press(i, t.index)
					return
			if t.position.x < size.x * 0.45 and _stick_touch < 0:
				_stick_touch = t.index
				_stick_origin = t.position
				_stick = Vector2.ZERO
			elif _look_touch < 0:
				_look_touch = t.index
		else:
			if t.index == _stick_touch:
				_stick_touch = -1
				_set_stick(Vector2.ZERO)
			elif t.index == _look_touch:
				_look_touch = -1
			elif _held.has(t.index):
				var i: int = _held[t.index]
				_held.erase(t.index)
				if not BUTTONS[i][3]:
					Input.action_release(BUTTONS[i][0])
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_set_stick((d.position - _stick_origin) / (STICK_RADIUS * _scale()))
			queue_redraw()
		elif d.index == _look_touch and _explorer != null:
			_explorer.call(&"_look", d.relative * look_speed / _scale())


func _press(i: int, touch: int) -> void:
	var action: StringName = BUTTONS[i][0]
	if action == &"wv_fly":
		# The explorer toggles flying on the press itself.
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		Input.parse_input_event(ev)
		_on[i] = not _on.get(i, false)
	elif BUTTONS[i][3]:
		_on[i] = not _on.get(i, false)
		if _on[i]:
			Input.action_press(action)
		else:
			Input.action_release(action)
	else:
		_held[touch] = i
		Input.action_press(action)
	queue_redraw()


func _set_stick(v: Vector2) -> void:
	_stick = v.limit_length(1.0)
	var live := _stick if _stick.length() > DEAD else Vector2.ZERO
	var amounts := [maxf(-live.x, 0.0), maxf(live.x, 0.0), maxf(-live.y, 0.0), maxf(live.y, 0.0)]
	for i in 4:
		if amounts[i] > 0.0:
			Input.action_press(MOVES[i], amounts[i])
		else:
			Input.action_release(MOVES[i])


func _draw() -> void:
	var k := _scale()
	var ring := Color(1, 1, 1, 0.22)
	var fill := Color(1, 1, 1, 0.10)
	if _stick_touch >= 0:
		draw_circle(_stick_origin, STICK_RADIUS * k, fill)
		draw_arc(_stick_origin, STICK_RADIUS * k, 0.0, TAU, 48, ring, 3.0 * k, true)
		draw_circle(_stick_origin + _stick * STICK_RADIUS * k, 46.0 * k, Color(1, 1, 1, 0.35))
	else:
		# Where the stick will appear: a faint hint in the lower left.
		var hint := Vector2(230.0 * k, size.y - 230.0 * k)
		draw_arc(hint, STICK_RADIUS * k, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 3.0 * k, true)
	var font: Font = load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	var fs := int(26.0 * k)
	for i in BUTTONS.size():
		var r := _button_rect(i)
		var lit: bool = _on.get(i, false) or _held.values().has(i)
		draw_circle(r.get_center(), r.size.x * 0.5, Color(1, 1, 1, 0.32) if lit else fill)
		draw_arc(r.get_center(), r.size.x * 0.5, 0.0, TAU, 40, ring, 3.0 * k, true)
		var label: String = BUTTONS[i][1]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, r.get_center() + Vector2(-w * 0.5, fs * 0.35), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75))
