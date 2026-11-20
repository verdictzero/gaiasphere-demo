class_name GraphicsMenu
extends CanvasLayer

# THE GRAPHICS MENU: how far things are drawn, how much of them, and which of
# the camera's effects are on. O or F10 (the GFX touch button) opens it.
#
# Every distance is a multiple of what this machine was given at start-up, so
# 1.0x on a phone is the phone's own baseline and not the desktop's. Changes
# apply as the slider moves and are kept in user://graphics.cfg.

const FILE := "user://graphics.cfg"

# key, label, kind ("slide" | "step" | "tick"), low, high, step, how it is shown
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const CAPS := [30, 60, 90, 120, 0]
## Rows per column: the display and the camera on the left, the world on the right.
const PER_COLUMN := 12
const ROWS := [
	["window_mode", "Window", "step", 0.0, 2.0, 1.0, "WINDOWED,BORDERLESS,FULLSCREEN"],
	["resolution", "Viewport resolution", "step", 0.0, 4.0, 1.0, "1280 x 720,1600 x 900,1920 x 1080,2560 x 1440,3840 x 2160"],
	["render_scale", "Rendering resolution", "slide", 0.25, 1.5, 0.05, "%"],
	["msaa", "Anti-aliasing (MSAA)", "step", 0.0, 2.0, 1.0, "OFF,2X,4X"],
	["fxaa", "Anti-aliasing (FXAA)", "tick"],
	["vsync", "V-sync", "tick"],
	["fps_cap", "Frame rate limit", "step", 0.0, 4.0, 1.0, "30,60,90,120,UNLIMITED"],
	["fov", "Field of view", "slide", 50.0, 110.0, 1.0, "deg"],
	["dof", "Depth of field", "tick"],
	["bloom", "Bloom", "tick"],
	["god_rays", "God rays", "tick"],
	["fps", "Show frame rate", "tick"],
	["veg_distance", "Vegetation draw distance", "slide", 0.5, 2.0, 0.05, "x"],
	["lod_distance", "Vegetation LOD distance", "slide", 0.5, 2.0, 0.05, "x"],
	["impostor_distance", "Tree impostor distance", "slide", 0.5, 2.0, 0.05, "x"],
	["grass_distance", "Grass distance", "slide", 0.4, 2.0, 0.05, "x"],
	["grass_density", "Grass density", "slide", 0.2, 1.0, 0.05, "%"],
	["veg_shadows", "Vegetation shadows", "tick"],
	["terrain_detail", "Terrain detail distance", "slide", 0.5, 1.5, 0.05, "x"],
	["shadow_distance", "Shadow distance", "slide", 40.0, 400.0, 10.0, "m"],
	["clouds", "Cloud quality", "step", 0.0, 2.0, 1.0, "LOW,MEDIUM,HIGH"],
]
# What each preset does to the multipliers and ticks (the rest are left alone).
const PRESETS := {
	"LOW": {"veg_distance": 0.6, "lod_distance": 0.6, "impostor_distance": 0.6, "grass_distance": 0.6,
		"grass_density": 0.5, "terrain_detail": 0.7, "shadow_distance": 90.0, "clouds": 0.0,
		"veg_shadows": false, "dof": false, "god_rays": false, "bloom": true},
	"MEDIUM": {"veg_distance": 1.0, "lod_distance": 1.0, "impostor_distance": 1.0, "grass_distance": 1.0,
		"grass_density": 0.8, "terrain_detail": 1.0, "shadow_distance": 160.0, "clouds": 1.0,
		"veg_shadows": true, "dof": false, "god_rays": true, "bloom": true},
	"HIGH": {"veg_distance": 1.3, "lod_distance": 1.3, "impostor_distance": 1.2, "grass_distance": 1.3,
		"grass_density": 1.0, "terrain_detail": 1.0, "shadow_distance": 240.0, "clouds": 1.0,
		"veg_shadows": true, "dof": true, "god_rays": true, "bloom": true},
	"ULTRA": {"veg_distance": 2.0, "lod_distance": 2.0, "impostor_distance": 2.0, "grass_distance": 2.0,
		"grass_density": 1.0, "terrain_detail": 1.5, "shadow_distance": 400.0, "clouds": 2.0,
		"veg_shadows": true, "dof": true, "god_rays": true, "bloom": true},
}
const BUTTONS := ["LOW", "MEDIUM", "HIGH", "ULTRA", "DEFAULTS"]

const PANEL := Color(0.075, 0.085, 0.1, 0.93)
const EDGE := Color(1, 1, 1, 0.14)
const ACCENT := Color(0.56, 0.86, 1.0)
const INK := Color(0.93, 0.95, 0.97)

## True while the menu is up: the sword stands down.
static var menu_open := false

@export var flora_path: NodePath = ^"../Flora"
@export var enviro_path: NodePath = ^"../Enviro"
@export var world_path: NodePath = ^"../GaiaSphere"

var values := {}
var _defaults := {}
var _flora: Flora
var _enviro: Node
var _world: Node
var _terrain_lods := PackedFloat32Array()
var _view: Control
var _font: Font
var _drag := -1
var _was_captured := false
var _fps: Label


func _ready() -> void:
	layer = 35
	menu_open = false
	_flora = get_node_or_null(flora_path) as Flora
	_enviro = get_node_or_null(enviro_path)
	_world = get_node_or_null(world_path)
	_font = load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	if _world != null:
		_terrain_lods = (_world.get("lod_distances") as PackedFloat32Array).duplicate()
	_defaults = {"veg_distance": 1.0, "lod_distance": 1.0, "impostor_distance": 1.0, "grass_distance": 1.0,
		"grass_density": 1.0, "terrain_detail": 1.0, "shadow_distance": 220.0, "render_scale": 1.0,
		"clouds": 1.0, "veg_shadows": true, "dof": true, "bloom": true, "god_rays": true, "fps": false,
		"window_mode": 0.0, "resolution": 2.0, "msaa": 0.0, "fxaa": false, "vsync": true, "fps_cap": 4.0, "fov": 75.0}
	if _enviro != null:
		_defaults.merge(_enviro.call(&"graphics_now"), true)
	# The display and the camera, as this machine started.
	var win := get_window()
	_defaults["window_mode"] = 2.0 if win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN \
			else (1.0 if win.borderless else 0.0)
	var nearest := 0
	for i in SIZES.size():
		if absi(SIZES[i].y - win.size.y) < absi(SIZES[nearest].y - win.size.y):
			nearest = i
	_defaults["resolution"] = float(nearest)
	_defaults["msaa"] = float(clampi(int(get_viewport().msaa_3d), 0, 2))
	_defaults["fxaa"] = get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA
	_defaults["vsync"] = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	_defaults["fps_cap"] = float(maxi(CAPS.find(Engine.max_fps), 0)) if Engine.max_fps > 0 else 4.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_defaults["fov"] = cam.fov
	values = _defaults.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(FILE) == OK:
		for key in values:
			if cfg.has_section_key("graphics", key) and typeof(cfg.get_value("graphics", key)) == typeof(values[key]):
				values[key] = cfg.get_value("graphics", key)
	if not InputMap.has_action(&"wv_graphics"):
		InputMap.add_action(&"wv_graphics")
		for code in [KEY_O, KEY_F10]:
			var key := InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(&"wv_graphics", key)
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_gui_input)
	add_child(_view)
	_fps = Label.new()
	_fps.position = Vector2(14, 10)
	_fps.add_theme_font_override(&"font", _font)
	_fps.add_theme_font_size_override(&"font_size", 22)
	_fps.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_fps.add_theme_constant_override(&"outline_size", 5)
	add_child(_fps)
	apply()


func _exit_tree() -> void:
	menu_open = false


func _process(_delta: float) -> void:
	_fps.visible = bool(values["fps"])
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


## Push every value to what it governs.
func apply() -> void:
	if _flora != null:
		_flora.apply_view(float(values["veg_distance"]), float(values["lod_distance"]), float(values["impostor_distance"]),
				float(values["grass_distance"]), float(values["grass_density"]), bool(values["veg_shadows"]))
	if _enviro != null:
		_enviro.call(&"apply_graphics", values)
	_apply_display()
	if _world != null and not _terrain_lods.is_empty():
		var scaled := PackedFloat32Array()
		for d in _terrain_lods:
			scaled.append(d * float(values["terrain_detail"]))
		_world.set("lod_distances", scaled)


## The window, the viewport and the camera. A phone has one window the size of
## its screen, so there only what is drawn inside it is touched.
var _window_was: Array[int] = [-1, -1]


func _apply_display() -> void:
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(round(float(values["msaa"]))), 0, 2)]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(values["fxaa"]) else Viewport.SCREEN_SPACE_AA_DISABLED
	Engine.max_fps = CAPS[clampi(int(round(float(values["fps_cap"]))), 0, CAPS.size() - 1)]
	var cam := vp.get_camera_3d()
	if cam != null:
		cam.fov = clampf(float(values["fov"]), 30.0, 120.0)
	if OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(values["vsync"]) else DisplayServer.VSYNC_DISABLED)
	# Only when one of them has moved: resizing the window on every slider tick
	# would fight the player's own dragging of it.
	var mode := clampi(int(round(float(values["window_mode"]))), 0, 2)
	var size_i := clampi(int(round(float(values["resolution"]))), 0, SIZES.size() - 1)
	if _window_was == [mode, size_i]:
		return
	var first: bool = _window_was[0] < 0
	_window_was = [mode, size_i]
	if first and values["window_mode"] == _defaults["window_mode"] and values["resolution"] == _defaults["resolution"]:
		return            # as the window already is: leave it exactly so
	var win := get_window()
	if mode == 2:
		win.mode = Window.MODE_FULLSCREEN
		return
	win.mode = Window.MODE_WINDOWED
	win.borderless = mode == 1
	var screen := DisplayServer.screen_get_usable_rect(win.current_screen)
	var want := Vector2i(mini(SIZES[size_i].x, screen.size.x), mini(SIZES[size_i].y, screen.size.y))
	win.size = want
	win.position = screen.position + (screen.size - want) / 2


func _save() -> void:
	var cfg := ConfigFile.new()
	for key in values:
		cfg.set_value("graphics", key, values[key])
	cfg.save(FILE)


func set_open(open: bool) -> void:
	if open == menu_open:
		return
	menu_open = open
	_view.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if open:
		var other := get_node_or_null(^"../EnvironmentMenu")
		if other != null and EnvironmentMenu.menu_open:
			other.call(&"set_open", false)
		_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_drag = -1
		_save()
		if _was_captured and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"wv_graphics"):
		set_open(not menu_open)
		get_viewport().set_input_as_handled()
	elif menu_open and event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ layout

func _k() -> float:
	return _view.size.y / 1080.0


func _panel_rect() -> Rect2:
	var k := _k()
	var size := Vector2(1560.0, 196.0 + 50.0 * float(PER_COLUMN)) * k
	return Rect2((_view.size - size) * 0.5, size)


func _row_rect(i: int) -> Rect2:
	var k := _k()
	var p := _panel_rect()
	var w := (p.size.x - 68.0 * k - 48.0 * k) * 0.5
	return Rect2(p.position + Vector2(34.0 * k + (w + 48.0 * k) * float(i / PER_COLUMN), (150.0 + 50.0 * float(i % PER_COLUMN)) * k),
			Vector2(w, 50.0 * k))


## Where a row's slider runs, or its tick box sits.
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
	var v := lerpf(float(row[3]), float(row[4]), t)
	v = clampf(snappedf(v, float(row[5])), float(row[3]), float(row[4]))
	if v != float(values[row[0]]):
		values[row[0]] = v
		apply()
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
			if BUTTONS[i] == "DEFAULTS":
				values = _defaults.duplicate()
			else:
				values.merge(PRESETS[BUTTONS[i]], true)
			apply()
			_view.queue_redraw()
			return
	for i in ROWS.size():
		if not _row_rect(i).has_point(mb.position):
			continue
		if ROWS[i][2] == "tick":
			values[ROWS[i][0]] = not bool(values[ROWS[i][0]])
			apply()
			_view.queue_redraw()
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
	var v := float(values[row[0]])
	match String(row[6]):
		"x":
			return "%.2fx" % v
		"%":
			return "%d%%" % int(round(v * 100.0))
		"m":
			return "%d m" % int(round(v))
		"deg":
			return "%d deg" % int(round(v))
	var names := String(row[6]).split(",")
	return names[clampi(int(round(v)), 0, names.size() - 1)]


func _draw_view() -> void:
	if not menu_open:
		return
	var k := _k()
	_view.draw_rect(Rect2(Vector2.ZERO, _view.size), Color(0.0, 0.01, 0.02, 0.5))
	var p := _panel_rect()
	_box(p.grow(10.0 * k), Color(0, 0, 0, 0.22), 34.0)
	_box(p, PANEL, 26.0, EDGE, 1.5)
	_label(p.position + Vector2(34.0, 52.0) * k, "GRAPHICS", 26.0, Color(INK.r, INK.g, INK.b, 0.92))
	_label(Vector2(p.end.x - 34.0 * k, p.position.y + 50.0 * k), "O or F10 to close", 19.0, Color(INK.r, INK.g, INK.b, 0.45), 2)
	for i in BUTTONS.size():
		var b := _button_rect(i)
		_box(b, Color(1, 1, 1, 0.07), 12.0, EDGE, 1.5)
		_label(Vector2(b.get_center().x, b.position.y + 31.0 * k), BUTTONS[i], 20.0, INK, 1)
	for i in ROWS.size():
		var row: Array = ROWS[i]
		var r := _row_rect(i)
		if i % PER_COLUMN > 0:
			_view.draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(1.0, k))), Color(1, 1, 1, 0.06))
		_label(r.position + Vector2(0.0, 33.0 * k), row[1], 21.0, Color(INK.r, INK.g, INK.b, 0.88))
		var c := _control_rect(i)
		if row[2] == "tick":
			var on := bool(values[row[0]])
			_box(c, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85) if on else Color(1, 1, 1, 0.1), 15.0, EDGE, 1.5)
			var knob := Vector2(c.end.x - 15.0 * k if on else c.position.x + 15.0 * k, c.get_center().y)
			_view.draw_circle(knob, 11.0 * k, Color(0.04, 0.05, 0.06) if on else Color(INK.r, INK.g, INK.b, 0.8))
			_label(Vector2(r.end.x, r.position.y + 33.0 * k), "ON" if on else "OFF", 20.0, Color(INK.r, INK.g, INK.b, 0.7), 2)
			continue
		var t := inverse_lerp(float(row[3]), float(row[4]), float(values[row[0]]))
		var track := Rect2(Vector2(c.position.x, c.get_center().y - 3.0 * k), Vector2(c.size.x, 6.0 * k))
		_box(track, Color(1, 1, 1, 0.12), 3.0)
		_box(Rect2(track.position, Vector2(track.size.x * t, track.size.y)), ACCENT, 3.0)
		_view.draw_circle(Vector2(track.position.x + track.size.x * t, c.get_center().y), 11.0 * k, INK)
		_label(Vector2(r.end.x, r.position.y + 33.0 * k), _shown(row), 20.0, Color(INK.r, INK.g, INK.b, 0.8), 2)
