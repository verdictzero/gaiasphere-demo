class_name EnvironmentMenu
extends CanvasLayer

# THE TIME AND ENVIRONMENT PANEL: the clock, the moon, the weather and the look
# of the light. P or F8 (the ENV touch button) opens it.
#
# Every row is a property of the Enviro node (SCRIPT_enviro.gd), read from it
# while the panel is open, so the hour slider moves as time passes and the
# weather row follows the weather changing by itself. Nothing here is saved:
# the island starts each run the way its scene sets it.

# property, label, kind ("slide" | "step" | "tick"), low, high, step, how it is shown
const PER_COLUMN := 7
const ROWS := [
	["hour", "Time of day", "slide", 0.0, 24.0, 0.05, "clock"],
	["advance", "Time passes", "tick"],
	["day_minutes", "Length of a day", "slide", 2.0, 120.0, 1.0, "min"],
	["moon_phase", "Moon (0 new, 50 full)", "slide", 0.0, 1.0, 0.01, "%"],
	["latitude", "Sun's path tilt", "slide", 0.0, 70.0, 1.0, "deg"],
	["night_ambient", "Night brightness", "slide", 0.0, 20.0, 0.25, "x"],
	["letterbox", "Cinema bars", "tick"],
	["weather", "Weather", "step", 0.0, 6.0, 1.0, "names"],
	["auto_weather", "Weather changes by itself", "tick"],
	["spell", "Longest spell of weather", "slide", 1.0, 30.0, 0.5, "min"],
	["fog_warmth", "Golden fog at dusk", "slide", 0.0, 1.0, 0.05, "%"],
	["flare_strength", "Sun flare", "slide", 0.0, 2.0, 0.05, "%"],
	["cinematic_grade", "Film grade", "slide", 0.0, 1.0, 0.05, "%"],
	["spooky", "Cold cast", "slide", 0.0, 1.0, 0.05, "%"],
]
const BUTTONS := [["DAWN", 6.2], ["NOON", 12.5], ["GOLDEN HOUR", 17.3], ["DUSK", 19.4], ["MIDNIGHT", 0.0], ["DEFAULTS", -1.0]]

const PANEL := Color(0.075, 0.085, 0.1, 0.93)
const EDGE := Color(1, 1, 1, 0.14)
const ACCENT := Color(1.0, 0.8, 0.45)
const INK := Color(0.93, 0.95, 0.97)

## True while the panel is up: the sword stands down.
static var menu_open := false

@export var enviro_path: NodePath = ^"../Enviro"

var _enviro: Enviro
var _defaults := {}
var _view: Control
var _font: Font
var _drag := -1
var _was_captured := false


func _ready() -> void:
	layer = 36
	menu_open = false
	_enviro = get_node_or_null(enviro_path) as Enviro
	_font = load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	if _enviro != null:
		for row in ROWS:
			_defaults[row[0]] = _read(row[0])
	if not InputMap.has_action(&"wv_environment"):
		InputMap.add_action(&"wv_environment")
		for code in [KEY_P, KEY_F8]:
			var key := InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(&"wv_environment", key)
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_gui_input)
	add_child(_view)


func _exit_tree() -> void:
	menu_open = false


func _process(_delta: float) -> void:
	if menu_open:
		_view.queue_redraw()      # the clock and the weather move under it


# ------------------------------------------------------------------ the values

## A row's value as a number or a bool, whatever it is on the Enviro node.
func _read(key: String) -> Variant:
	match key:
		"weather":
			return float(maxi(Enviro.WEATHER_KEYS.find(_enviro.weather), 0))
		"spell":
			return _enviro.weather_minutes.y
	return _enviro.get(key)


func _write(key: String, value: Variant) -> void:
	match key:
		"weather":
			var name: String = Enviro.WEATHER_KEYS[clampi(int(round(float(value))), 0, Enviro.WEATHER_KEYS.size() - 1)]
			if name != _enviro.weather:
				_enviro.set_weather(name, 6.0)
		"spell":
			var longest := float(value)
			_enviro.weather_minutes = Vector2(minf(_enviro.weather_minutes.x, longest * 0.5), longest)
		_:
			_enviro.set(key, value)
			if key == "spooky" or key == "cinematic_grade" or key == "letterbox":
				_enviro.apply_look()


func set_open(open: bool) -> void:
	if open == menu_open or _enviro == null:
		return
	if open:
		for other_name in ["GraphicsMenu", "OptionsMenu", "Inventory", "MapMenu"]:
			var other := get_node_or_null("../" + other_name)
			if other != null and other.has_method(&"set_open"):
				other.call(&"set_open", false)
	menu_open = open
	_view.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if open:
		_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_drag = -1
		if _was_captured and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"wv_environment"):
		set_open(not menu_open)
		get_viewport().set_input_as_handled()
	elif menu_open and event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ layout

func _k() -> float:
	return UiFit.scale(_view.size)


func _panel_rect() -> Rect2:
	var k := _k()
	var size := Vector2(1560.0, 196.0 + 50.0 * float(PER_COLUMN)) * k
	# Low on the screen, so the sky it changes can be seen over it.
	return Rect2(Vector2((_view.size.x - size.x) * 0.5, _view.size.y - size.y - 40.0 * k), size)


func _row_rect(i: int) -> Rect2:
	var k := _k()
	var p := _panel_rect()
	var w := (p.size.x - 68.0 * k - 48.0 * k) * 0.5
	return Rect2(p.position + Vector2(34.0 * k + (w + 48.0 * k) * float(i / PER_COLUMN), (150.0 + 50.0 * float(i % PER_COLUMN)) * k),
			Vector2(w, 50.0 * k))


func _control_rect(i: int) -> Rect2:
	var k := _k()
	var r := _row_rect(i)
	if ROWS[i][2] == "tick":
		return Rect2(Vector2(r.end.x - 122.0 * k, r.position.y + 10.0 * k), Vector2(56.0, 30.0) * k)
	return Rect2(Vector2(r.position.x + 290.0 * k, r.position.y + 10.0 * k), Vector2(260.0, 30.0) * k)


func _button_rect(i: int) -> Rect2:
	var k := _k()
	var p := _panel_rect()
	var w := (p.size.x - 68.0 * k - 12.0 * k * float(BUTTONS.size() - 1)) / float(BUTTONS.size())
	return Rect2(p.position + Vector2(34.0 * k + (w + 12.0 * k) * float(i), 80.0 * k), Vector2(w, 46.0 * k))


# ------------------------------------------------------------------ input

func _slide(i: int, x: float) -> void:
	var row: Array = ROWS[i]
	var track := _control_rect(i)
	var t := clampf((x - track.position.x) / track.size.x, 0.0, 1.0)
	var v := clampf(snappedf(lerpf(float(row[3]), float(row[4]), t), float(row[5])), float(row[3]), float(row[4]))
	if row[0] == "hour":
		v = minf(v, 23.99)
	_write(row[0], v)
	_view.queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	if not menu_open:
		return
	if event is InputEventMouseMotion:
		if _drag >= 0:
			_slide(_drag, (event as InputEventMouseMotion).position.x)
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not mb.pressed:
		_drag = -1
		return
	for i in BUTTONS.size():
		if _button_rect(i).has_point(mb.position):
			if float(BUTTONS[i][1]) < 0.0:
				for key in _defaults:
					_write(key, _defaults[key])
			else:
				_enviro.hour = float(BUTTONS[i][1])
			return
	for i in ROWS.size():
		if not _row_rect(i).has_point(mb.position):
			continue
		if ROWS[i][2] == "tick":
			_write(ROWS[i][0], not bool(_read(ROWS[i][0])))
		elif _control_rect(i).grow(14.0 * _k()).has_point(mb.position):
			_drag = i
			_slide(i, mb.position.x)
		return
	if not _panel_rect().has_point(mb.position):
		set_open(false)


# ------------------------------------------------------------------ drawing

func _box(r: Rect2, fill: Color, radius: float, edge := Color(0, 0, 0, 0), width := 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius * _k()))
	sb.corner_detail = 10
	sb.anti_aliasing = true
	if width > 0.0:
		sb.set_border_width_all(maxi(1, int(round(width * _k()))))
		sb.border_color = edge
	_view.draw_style_box(sb, r)


func _label(at: Vector2, text: String, px: float, color: Color, align := 0) -> void:
	var fs := int(px * _k())
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_view.draw_string(_font, at - Vector2(w * 0.5 * float(align), 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _shown(row: Array) -> String:
	var v := float(_read(row[0]))
	match String(row[6]):
		"clock":
			return "%02d:%02d" % [int(v) % 24, int(fposmod(v, 1.0) * 60.0)]
		"min":
			return "%s min" % String.num(v, 1 if v < 10.0 else 0)
		"%":
			return "%d%%" % int(round(v * 100.0))
		"deg":
			return "%d deg" % int(round(v))
		"x":
			return "%.2fx" % v
	return String(Enviro.WEATHER_KEYS[clampi(int(round(v)), 0, Enviro.WEATHER_KEYS.size() - 1)]).replace("_", " ").to_upper()


func _draw_view() -> void:
	if not menu_open:
		return
	var k := _k()
	var p := _panel_rect()
	_box(p.grow(10.0 * k), Color(0, 0, 0, 0.22), 34.0)
	_box(p, PANEL, 26.0, EDGE, 1.5)
	_label(p.position + Vector2(34.0, 52.0) * k, "TIME AND ENVIRONMENT", 26.0, Color(INK.r, INK.g, INK.b, 0.92))
	_label(Vector2(p.end.x - 34.0 * k, p.position.y + 50.0 * k), "P or F8 to close", 19.0, Color(INK.r, INK.g, INK.b, 0.45), 2)
	for i in BUTTONS.size():
		var b := _button_rect(i)
		_box(b, Color(1, 1, 1, 0.07), 12.0, EDGE, 1.5)
		_label(Vector2(b.get_center().x, b.position.y + 31.0 * k), BUTTONS[i][0], 20.0, INK, 1)
	for i in ROWS.size():
		var row: Array = ROWS[i]
		var r := _row_rect(i)
		if i % PER_COLUMN > 0:
			_view.draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(1.0, k))), Color(1, 1, 1, 0.06))
		_label(r.position + Vector2(0.0, 33.0 * k), row[1], 21.0, Color(INK.r, INK.g, INK.b, 0.88))
		var c := _control_rect(i)
		if row[2] == "tick":
			var on := bool(_read(row[0]))
			_box(c, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85) if on else Color(1, 1, 1, 0.1), 15.0, EDGE, 1.5)
			var knob := Vector2(c.end.x - 15.0 * k if on else c.position.x + 15.0 * k, c.get_center().y)
			_view.draw_circle(knob, 11.0 * k, Color(0.04, 0.05, 0.06) if on else Color(INK.r, INK.g, INK.b, 0.8))
			_label(Vector2(r.end.x, r.position.y + 33.0 * k), "ON" if on else "OFF", 20.0, Color(INK.r, INK.g, INK.b, 0.7), 2)
			continue
		var t := clampf(inverse_lerp(float(row[3]), float(row[4]), float(_read(row[0]))), 0.0, 1.0)
		var track := Rect2(Vector2(c.position.x, c.get_center().y - 3.0 * k), Vector2(c.size.x, 6.0 * k))
		_box(track, Color(1, 1, 1, 0.12), 3.0)
		_box(Rect2(track.position, Vector2(track.size.x * t, track.size.y)), ACCENT, 3.0)
		_view.draw_circle(Vector2(track.position.x + track.size.x * t, c.get_center().y), 11.0 * k, INK)
		_label(Vector2(r.end.x, r.position.y + 33.0 * k), _shown(row), 20.0, Color(INK.r, INK.g, INK.b, 0.8), 2)
