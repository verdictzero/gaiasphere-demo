class_name TouchControls
extends Control

# ON-SCREEN CONTROLS FOR A TOUCHSCREEN, laid out for two thumbs.
#
#   LEFT THUMB    a stick that appears where the thumb lands, for walking.
#   RIGHT THUMB   drag anywhere on the right to look. Round it, where the thumb
#                 rests, the things done all the time:
#                   the big one   what is in the hand: CHOP, SWING, EAT, or TAKE
#                                 at the stone (hold SWING to charge the sword)
#                   JUMP          (UP while flying or swimming, with DOWN beside it
#                                 then, and only then)
#                   RUN           a toggle
#   TOP RIGHT     the things done now and again, small and out of the way:
#                 BAG, LIGHT, FLY, and the two panels, GFX and ENV.
#   THE HOTBAR    is tapped directly.
#
# While the bag or a panel is open the thumbs' controls stand down (the panel
# takes the touches) and only the top row stays, to close it again.
#
# It drives the same `wv_*` input actions the keyboard and the controller do, so
# nothing else knows which is in use. Shown only where there is a touchscreen
# (or with `force` on, to try it with a mouse).

@export var explorer_path: NodePath = ^"../../Explorer"
@export var hand_path: NodePath = ^"../../SwordPlay"
@export var force := false
## Radians turned per pixel dragged, at a 1080-high screen.
@export var look_speed := 0.0045

const STICK_RADIUS := 115.0
const DEAD := 0.14
const ACCENT := Color(0.56, 0.86, 1.0)

# THE THUMB'S BUTTONS: action, centre from the bottom-right corner and radius (at
# a 1080-high screen), how it behaves ("hold" | "toggle"), when it shows.
const THUMB := [
	{"action": &"wv_attack", "at": Vector2(-190, -235), "r": 94.0, "kind": "hold", "label": "USE", "main": true},
	{"action": &"wv_up", "at": Vector2(-400, -150), "r": 70.0, "kind": "hold", "label": "JUMP"},
	{"action": &"wv_run", "at": Vector2(-150, -450), "r": 60.0, "kind": "toggle", "label": "RUN"},
	{"action": &"wv_down", "at": Vector2(-370, -330), "r": 60.0, "kind": "hold", "label": "DOWN", "aloft": true},
]
# THE TOP ROW, right to left: action and label. Each is a tap.
const ROW := [
	[&"wv_environment", "ENV"],
	[&"wv_graphics", "GFX"],
	[&"wv_fly", "FLY"],
	[&"wv_light", "LIGHT"],
	[&"wv_bag", "BAG"],
	[&"wv_turn", "TURN"],
]
const MOVES := [&"wv_left", &"wv_right", &"wv_forward", &"wv_back"]

var _explorer: Node
var _hand: Node
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick := Vector2.ZERO
var _look_touch := -1
var _held := {}            # touch index -> thumb button index
var _on := {}              # action -> toggled on
var _font: Font
var _tapped := {}          # row index -> seconds of its flash left


func _ready() -> void:
	_explorer = get_node_or_null(explorer_path)
	_hand = get_node_or_null(hand_path)
	_font = load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	visible = force or DisplayServer.is_touchscreen_available()
	set_process_input(visible)
	set_process(visible)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if visible and OS.has_feature("mobile"):
		call_deferred(&"_no_phantom_clicks")


## A phone turns every touch into a left click as well, for the menus' sake, and
## the left click is also "swing": without this, looking round would swing the
## axe. On a phone the buttons here are the only way to swing or charge.
func _no_phantom_clicks() -> void:
	for action in [&"wv_attack", &"wv_charge"]:
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				InputMap.action_erase_event(action, ev)


func _k() -> float:
	return size.y / 1080.0


func _menu_open() -> bool:
	return Inventory.menu_open or GraphicsMenu.menu_open or EnvironmentMenu.menu_open


## Flying or swimming: when there is an up and a down.
func _aloft() -> bool:
	if _explorer == null:
		return false
	return bool(_explorer.get("flying")) or float(_explorer.get("deep")) > 1.3


func _shown(i: int) -> bool:
	return not _menu_open() and (not THUMB[i].get("aloft", false) or _aloft())


func _thumb_centre(i: int) -> Vector2:
	return size + (THUMB[i]["at"] as Vector2) * _k()


func _row_rect(i: int) -> Rect2:
	var k := _k()
	var w := 128.0 * k
	return Rect2(Vector2(size.x - 24.0 * k - (w + 12.0 * k) * float(i) - w, 22.0 * k), Vector2(w, 60.0 * k))


## The strip along the bottom the hotbar and the bars live in: touches there are
## the hotbar's, not a look or a walk.
func _hotbar_zone(at: Vector2) -> bool:
	var k := _k()
	return at.y > size.y - 124.0 * k and absf(at.x - size.x * 0.5) < 84.0 * 4.6 * k


## What the big button does just now, said on it.
func _use_label() -> String:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		for thing in get_tree().get_nodes_in_group(&"usable"):
			if bool(thing.call(&"can_use", cam.global_position, -cam.global_basis.z)):
				return String(thing.call(&"use_label"))
	if _hand == null:
		return "USE"
	var prompt: Variant = _hand.get("_prompt")
	if prompt != null and (prompt as CanvasItem).visible:
		return "TAKE"
	var built := get_node_or_null(^"../../Building")
	if built != null and String(built.call(&"holding")) != "":
		return "PLACE"
	match String(_hand.get("tool")):
		"axe":
			return "CHOP"
		"pickaxe":
			return "MINE"
		"sword":
			return "SWING"
		"berry":
			return "EAT"
	return "USE"


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			for i in ROW.size():
				if _row_rect(i).grow(8.0 * _k()).has_point(t.position):
					_tap(i)
					return
			if _menu_open() or _hotbar_zone(t.position):
				return
			for i in THUMB.size():
				if _shown(i) and t.position.distance_to(_thumb_centre(i)) <= (float(THUMB[i]["r"]) + 14.0) * _k():
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
				Input.action_release(THUMB[i]["action"])
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_set_stick((d.position - _stick_origin) / (STICK_RADIUS * _k()))
			queue_redraw()
		elif d.index == _look_touch and _explorer != null and not _menu_open():
			_explorer.call(&"_look", d.relative * look_speed / _k())


func _press(i: int, touch: int) -> void:
	var action: StringName = THUMB[i]["action"]
	if THUMB[i]["kind"] == "toggle":
		_on[action] = not _on.get(action, false)
		if _on[action]:
			Input.action_press(action)
		else:
			Input.action_release(action)
	else:
		_held[touch] = i
		Input.action_press(action)
	queue_redraw()


## A top-row button: its action, pressed once, the way a key would be.
func _tap(i: int) -> void:
	var ev := InputEventAction.new()
	ev.action = ROW[i][0]
	ev.pressed = true
	Input.parse_input_event(ev)
	_tapped[i] = 0.18
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


func _process(delta: float) -> void:
	# A panel opening under a thumb: let go of whatever it was holding.
	if _menu_open() and (_stick_touch >= 0 or not _held.is_empty()):
		_stick_touch = -1
		_set_stick(Vector2.ZERO)
		for touch in _held:
			Input.action_release(THUMB[_held[touch]]["action"])
		_held.clear()
	for i in _tapped.keys():
		_tapped[i] = float(_tapped[i]) - delta
		if float(_tapped[i]) <= 0.0:
			_tapped.erase(i)
	queue_redraw()        # the labels and what shows follow the game


# ------------------------------------------------------------------ drawing

func _text(at: Vector2, text: String, px: float, color: Color) -> void:
	var fs := int(px * _k())
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, at + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw() -> void:
	var k := _k()
	var ring := Color(1, 1, 1, 0.26)
	var fill := Color(0.04, 0.05, 0.06, 0.34)
	var lit_fill := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.34)
	# The top row: small pills.
	for i in ROW.size():
		var r := _row_rect(i)
		var action: StringName = ROW[i][0]
		var on := _tapped.has(i)
		if action == &"wv_fly" and _explorer != null:
			on = on or bool(_explorer.get("flying"))
		elif action == &"wv_bag":
			on = on or Inventory.menu_open
		elif action == &"wv_graphics":
			on = on or GraphicsMenu.menu_open
		elif action == &"wv_environment":
			on = on or EnvironmentMenu.menu_open
		var sb := StyleBoxFlat.new()
		sb.bg_color = lit_fill if on else fill
		sb.set_corner_radius_all(int(r.size.y * 0.5))
		sb.set_border_width_all(maxi(1, int(2.0 * k)))
		sb.border_color = ACCENT if on else ring
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		_text(r.get_center(), ROW[i][1], 22.0, Color(1, 1, 1, 0.9))
	if _menu_open():
		return
	# The left thumb's stick, or a faint ring where it will appear.
	if _stick_touch >= 0:
		draw_circle(_stick_origin, STICK_RADIUS * k, fill)
		draw_arc(_stick_origin, STICK_RADIUS * k, 0.0, TAU, 56, ring, 3.0 * k, true)
		draw_circle(_stick_origin + _stick * STICK_RADIUS * k, 48.0 * k, Color(1, 1, 1, 0.4))
	else:
		var hint := Vector2(250.0 * k, size.y - 250.0 * k)
		draw_arc(hint, STICK_RADIUS * k, 0.0, TAU, 56, Color(1, 1, 1, 0.13), 3.0 * k, true)
		draw_circle(hint, 30.0 * k, Color(1, 1, 1, 0.08))
	# The right thumb's buttons.
	for i in THUMB.size():
		if not _shown(i):
			continue
		var b: Dictionary = THUMB[i]
		var c := _thumb_centre(i)
		var radius := float(b["r"]) * k
		var lit: bool = _on.get(b["action"], false) or _held.values().has(i)
		draw_circle(c, radius, lit_fill if lit else fill)
		draw_arc(c, radius, 0.0, TAU, 56, ACCENT if (lit or b.get("main", false)) else ring, (4.0 if b.get("main", false) else 3.0) * k, true)
		var label: String = b["label"]
		if b.get("main", false):
			label = _use_label()
		elif b["action"] == &"wv_up" and _aloft():
			label = "UP"
		_text(c, label, 30.0 if b.get("main", false) else 24.0, Color(1, 1, 1, 0.92))
