class_name GraphicsMenu
extends CanvasLayer

# THE GRAPHICS MENU: how far things are drawn, how much of them, which of the
# camera's effects are on, the ambient occlusion, how the cliffs are drawn and
# the far ground's short cuts. O or F10 (the GFX touch button) opens it. Two
# rows of presets head it, one for desktops and one for phones, six levels each
# (`PRESET_TABLE`); a preset is lit while everything it sets is as it sets it.
#
# Every distance is a multiple of what this machine was given at start-up, so
# 1.0x on a phone is the phone's own baseline and not the desktop's. Changes
# apply as the slider moves and are kept in user://graphics.cfg.

const FILE := "user://graphics.cfg"

# key, label, kind ("slide" | "step" | "tick"), low, high, step, how it is shown
## The sizes a window can be set to.
const SIZES := [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160)]
## The heights the 3D view can be drawn at, whatever the size of the window or
## the screen it is shown on (0: the window's own).
const VIEW_HEIGHTS := [0, 360, 540, 720, 900, 1080, 1440, 2160]
const CAPS := [30, 60, 90, 120, 0]
## Rows per column: the display and the camera on the left, the world in the
## middle, and on the right the ambient occlusion, the cliffs and the far ground.
const PER_COLUMN := 15
const ROWS := [
	["window_mode", "Window", "step", 0.0, 2.0, 1.0, "WINDOWED,BORDERLESS,FULLSCREEN"],
	["window_size", "Window size (windowed)", "step", 0.0, 6.0, 1.0,
		"960 x 540,1280 x 720,1366 x 768,1600 x 900,1920 x 1080,2560 x 1440,3840 x 2160"],
	["view_height", "Viewport resolution", "step", 0.0, 7.0, 1.0, "NATIVE,360p,540p,720p,900p,1080p,1440p,2160p"],
	["render_scale", "Rendering scale", "slide", 0.25, 1.5, 0.05, "%"],
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
	["shadows", "Shadows", "tick"],
	["shadow_quality", "Shadow quality", "step", 0.0, 2.0, 1.0, "LOW,MEDIUM,HIGH"],
	["veg_shadows", "Vegetation shadows", "tick"],
	["terrain_detail", "Terrain detail distance", "slide", 0.5, 1.5, 0.05, "x"],
	["shadow_distance", "Shadow distance", "slide", 40.0, 400.0, 10.0, "m"],
	["clouds", "Cloud quality", "step", 0.0, 2.0, 1.0, "LOW,MEDIUM,HIGH"],
	# THE FAR GROUND'S SHORT CUTS (SHADERINC_ground_lay's normal_reach and
	# stochastic_reach, on the terrain and the cliffs): each a tick, and where from.
	["far_normals", "Far ground: no normal maps", "tick"],
	["normal_reach", "Dist. threshold", "slide", 20.0, 400.0, 5.0, "m"],
	["far_single", "Far ground: no stochastic", "tick"],
	["stochastic_reach", "Dist. threshold", "slide", 10.0, 400.0, 5.0, "m"],
	# HOW THE CLIFFS' ROCKS ARE DRAWN BY DISTANCE (SCRIPT_cliff_rocks.gd's `view`:
	# each "cliff_" row is the setting of that name without the prefix).
	["cliff_lod", "Cliff detail distance", "slide", 0.25, 4.0, 0.05, "x"],
	["cliff_far", "Cliffs merged past", "slide", 100.0, 2000.0, 25.0, "m"],
	# (--- the third column ---)
	["cliff_reach", "Cliffs drawn out to", "slide", 200.0, 6000.0, 50.0, "reach"],
	["cliff_shadow", "Cliff shadows out to", "slide", 0.0, 800.0, 10.0, "m"],
	["cliff_occlusion", "Cliffs behind ground culled", "tick"],
	# AMBIENT OCCLUSION over the whole frame (SCRIPT_ambient_occlusion.gd): each
	# "ao_" row is the setting of that name without the prefix.
	["ao_method", "Ambient occlusion", "step", 0.0, 3.0, 1.0, "OFF,FAST,SSAO,HBAO"],
	["ao_intensity", "AO intensity", "slide", 0.0, 4.0, 0.05, "%"],
	["ao_radius", "AO radius", "slide", 0.1, 5.0, 0.05, "m2"],
	["ao_radius_growth", "AO radius grows far off", "slide", 0.0, 0.15, 0.005, "pc"],
	["ao_power", "AO contrast", "slide", 0.25, 6.0, 0.05, "x"],
	["ao_bias", "AO bias", "slide", 0.0, 0.2, 0.005, "m2"],
	["ao_falloff", "AO depth falloff", "slide", 0.1, 4.0, 0.05, "x"],
	["ao_max_distance", "AO reaches", "slide", 20.0, 600.0, 5.0, "m"],
	["ao_floor_light", "AO darkest allowed", "slide", 0.0, 1.0, 0.05, "%"],
	["ao_samples", "AO samples (Fast, SSAO)", "slide", 2.0, 32.0, 1.0, "n"],
	["ao_directions", "HBAO directions", "slide", 2.0, 12.0, 1.0, "n"],
	["ao_steps", "HBAO steps", "slide", 2.0, 10.0, 1.0, "n"],
]
# THE PRESETS: six levels, and a row of them for each kind of machine. A level
# sets the multipliers, the ticks and the quality steps below and leaves the rest
# (the window, the frame limit, the field of view) alone. Each list runs
# VERY LOW, LOW, MEDIUM, HIGH, VERY HIGH, ULTRA.
#
# The two rows are not the same six a notch apart. A phone draws far more pixels
# than it has the graphics for and has little to spare for shadows and the
# passes over the whole frame, so its row drops the rendering scale first, keeps
# shadows short and cheap, and comes to depth of field, SSAO and MSAA only at the
# top; a desktop's keeps its full resolution from MEDIUM and spends on distance.
const LEVELS := ["VERY LOW", "LOW", "MEDIUM", "HIGH", "VERY HIGH", "ULTRA"]
const KINDS := ["DESKTOP", "MOBILE"]
const PRESET_TABLE := {
	"DESKTOP": {
		"render_scale": [0.6, 0.8, 1.0, 1.0, 1.0, 1.0],
		"msaa": [0.0, 0.0, 0.0, 1.0, 2.0, 2.0],
		"veg_distance": [0.5, 0.7, 1.0, 1.3, 1.6, 2.0],
		"lod_distance": [0.5, 0.7, 1.0, 1.3, 1.6, 2.0],
		"impostor_distance": [0.5, 0.7, 1.0, 1.2, 1.6, 2.0],
		"grass_distance": [0.4, 0.6, 1.0, 1.3, 1.6, 2.0],
		"grass_density": [0.3, 0.5, 0.8, 1.0, 1.0, 1.0],
		"terrain_detail": [0.5, 0.7, 1.0, 1.0, 1.25, 1.5],
		"shadows": [false, true, true, true, true, true],
		"shadow_quality": [0.0, 0.0, 1.0, 1.0, 2.0, 2.0],
		"shadow_distance": [60.0, 90.0, 160.0, 240.0, 320.0, 400.0],
		"veg_shadows": [false, false, true, true, true, true],
		"clouds": [0.0, 0.0, 1.0, 1.0, 2.0, 2.0],
		"bloom": [false, true, true, true, true, true],
		"god_rays": [false, false, true, true, true, true],
		"dof": [false, false, false, true, true, true],
		"ao_method": [0.0, 0.0, 1.0, 2.0, 3.0, 3.0],
		"ao_samples": [4.0, 6.0, 8.0, 10.0, 12.0, 16.0],
		"ao_max_distance": [60.0, 100.0, 160.0, 200.0, 260.0, 320.0],
		"far_normals": [true, true, true, true, true, false],
		"normal_reach": [40.0, 80.0, 140.0, 200.0, 300.0, 400.0],
		"far_single": [true, true, true, true, true, false],
		"stochastic_reach": [30.0, 60.0, 90.0, 140.0, 220.0, 400.0],
		"cliff_lod": [0.4, 0.6, 1.0, 1.3, 2.0, 3.0],
		"cliff_far": [250.0, 400.0, 600.0, 800.0, 1200.0, 2000.0],
		"cliff_reach": [1200.0, 2500.0, 6000.0, 6000.0, 6000.0, 6000.0],
		"cliff_shadow": [0.0, 80.0, 250.0, 300.0, 500.0, 800.0],
	},
	"MOBILE": {
		"render_scale": [0.5, 0.6, 0.75, 0.85, 1.0, 1.0],
		"msaa": [0.0, 0.0, 0.0, 0.0, 1.0, 2.0],
		"veg_distance": [0.5, 0.6, 0.8, 1.0, 1.2, 1.5],
		"lod_distance": [0.5, 0.6, 0.8, 1.0, 1.2, 1.5],
		"impostor_distance": [0.5, 0.6, 0.8, 1.0, 1.2, 1.5],
		"grass_distance": [0.4, 0.5, 0.7, 1.0, 1.2, 1.5],
		"grass_density": [0.25, 0.4, 0.6, 0.8, 1.0, 1.0],
		"terrain_detail": [0.5, 0.6, 0.8, 1.0, 1.0, 1.25],
		"shadows": [false, false, true, true, true, true],
		"shadow_quality": [0.0, 0.0, 0.0, 1.0, 1.0, 2.0],
		"shadow_distance": [40.0, 60.0, 100.0, 140.0, 200.0, 280.0],
		"veg_shadows": [false, false, false, true, true, true],
		"clouds": [0.0, 0.0, 0.0, 1.0, 1.0, 2.0],
		"bloom": [false, false, true, true, true, true],
		"god_rays": [false, false, false, true, true, true],
		"dof": [false, false, false, false, false, true],
		"ao_method": [0.0, 0.0, 0.0, 1.0, 1.0, 2.0],
		"ao_samples": [4.0, 4.0, 6.0, 8.0, 8.0, 12.0],
		"ao_max_distance": [40.0, 60.0, 80.0, 120.0, 160.0, 200.0],
		"far_normals": [true, true, true, true, true, true],
		"normal_reach": [30.0, 50.0, 80.0, 120.0, 180.0, 300.0],
		"far_single": [true, true, true, true, true, true],
		"stochastic_reach": [20.0, 40.0, 60.0, 90.0, 140.0, 220.0],
		"cliff_lod": [0.3, 0.5, 0.7, 1.0, 1.3, 2.0],
		"cliff_far": [200.0, 300.0, 400.0, 600.0, 800.0, 1200.0],
		"cliff_reach": [800.0, 1500.0, 2500.0, 4000.0, 6000.0, 6000.0],
		"cliff_shadow": [0.0, 0.0, 60.0, 150.0, 250.0, 400.0],
	},
}


## What level `level` of `kind` sets: key -> value.
static func preset(kind: String, level: int) -> Dictionary:
	var out := {}
	var table: Dictionary = PRESET_TABLE[kind]
	for key in table:
		out[key] = (table[key] as Array)[level]
	return out


const COLUMNS := 3
const ROW_H := 46.0

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
		"shadows": true, "shadow_quality": 1.0,
		"window_mode": 0.0, "window_size": 4.0, "view_height": 0.0, "msaa": 0.0, "fxaa": false, "vsync": true, "fps_cap": 4.0, "fov": 75.0,
		"far_normals": true, "normal_reach": 140.0, "far_single": true, "stochastic_reach": 90.0}
	# The cliffs' and the ambient occlusion's, as those begin.
	var cliffs := get_node_or_null(^"../CliffRocks") as CliffRocks
	var view: Dictionary = cliffs.view if cliffs != null else {"lod": 1.0, "far": CliffRocks.FAR_AT,
			"reach": CliffRocks.ALL_REACH, "shadow": 250.0, "occlusion": true}
	for key in view:
		_defaults["cliff_" + String(key)] = view[key]
	for key in AmbientOcclusion.DEFAULTS:
		_defaults["ao_" + String(key)] = float(AmbientOcclusion.DEFAULTS[key])
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
	_defaults["window_size"] = float(nearest)
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
	_apply_view_height()          # (the window may have been dragged to another size)
	_apply_extra()                # (whatever of it had nothing to be set on yet)
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
	_apply_view_height()
	if _world != null and not _terrain_lods.is_empty():
		var scaled := PackedFloat32Array()
		for d in _terrain_lods:
			scaled.append(d * float(values["terrain_detail"]))
		_world.set("lod_distances", scaled)
	_apply_extra()


## THE REST: the far ground's short cuts (shader settings on the terrain's and
## the cliffs' materials), how the cliffs are drawn, and the ambient occlusion.
## Each is sent only when it has changed, and counted as sent only once what it
## is set on is there (the cliffs' material comes late), so this is asked again
## every frame and costs nothing when there is nothing to do.
var _sent := {}


func _apply_extra() -> void:
	var cliffs := get_node_or_null(^"../CliffRocks") as CliffRocks
	var ao := get_node_or_null(^"../AmbientOcclusion") as AmbientOcclusion
	var mats: Array = []
	if _world != null and _world.get(&"terrain_material") is ShaderMaterial:
		mats.append(_world.get(&"terrain_material"))
	var cliff_mat: Variant = cliffs.get("_material") if cliffs != null else null
	if cliff_mat is ShaderMaterial:
		mats.append(cliff_mat)
	# (0 is "never": the tick off.)
	var reaches := {
		"normal_reach": float(values["normal_reach"]) if bool(values["far_normals"]) else 0.0,
		"stochastic_reach": float(values["stochastic_reach"]) if bool(values["far_single"]) else 0.0,
	}
	for key in reaches:
		var mark := [reaches[key], mats.size()]
		if _sent.get(key) != mark and not mats.is_empty():
			for m: ShaderMaterial in mats:
				m.set_shader_parameter(key, reaches[key])
			# (Both there: done. Only the terrain's yet: sent again when the cliffs' comes.)
			_sent[key] = mark
	for key in values:
		var name := String(key)
		if name.begins_with("cliff_") and cliffs != null and _sent.get(name) != values[key]:
			cliffs.set_view(name.substr(6), values[key])
			_sent[name] = values[key]
		elif name.begins_with("ao_") and ao != null and ao.is_node_ready() and _sent.get(name) != values[key]:
			ao.put(name.substr(3), float(values[key]))
			_sent[name] = values[key]


## THE VIEWPORT'S RESOLUTION: the 3D view drawn at a chosen number of lines
## (720p, 1080p ...) whatever the window or the screen is, and scaled to fit;
## the panels and the text over it stay at the window's own sharpness. "Rendering
## scale" multiplies it, for a size in between. Worked out again whenever the
## window changes size, since it is a share of that.
var _view_was := Vector3(-1, -1, -1)


func _apply_view_height() -> void:
	var vp := get_viewport()
	var lines := float(VIEW_HEIGHTS[clampi(int(round(float(values["view_height"]))), 0, VIEW_HEIGHTS.size() - 1)])
	var tall := float(get_window().size.y)
	var now := Vector3(lines, tall, float(values["render_scale"]))
	if now == _view_was:
		return
	_view_was = now
	var share := lines / maxf(tall, 1.0) if lines > 0.0 else 1.0
	vp.scaling_3d_scale = clampf(share * float(values["render_scale"]), 0.1, 2.0)


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
	var size_i := clampi(int(round(float(values["window_size"]))), 0, SIZES.size() - 1)
	if _window_was == [mode, size_i]:
		return
	var first: bool = _window_was[0] < 0
	_window_was = [mode, size_i]
	if first and values["window_mode"] == _defaults["window_mode"] and values["window_size"] == _defaults["window_size"]:
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
		for other_name in ["EnvironmentMenu", "OptionsMenu"]:
			var other := get_node_or_null("../" + other_name)
			if other != null and other.has_method(&"set_open"):
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
	return UiFit.scale(_view.size)


func _panel_rect() -> Rect2:
	var k := _k()
	var size := Vector2(1860.0, 222.0 + ROW_H * float(PER_COLUMN)) * k
	return Rect2((_view.size - size) * 0.5, size)


func _row_rect(i: int) -> Rect2:
	var k := _k()
	var p := _panel_rect()
	var w := (p.size.x - 68.0 * k - 40.0 * k * float(COLUMNS - 1)) / float(COLUMNS)
	return Rect2(p.position + Vector2(34.0 * k + (w + 40.0 * k) * float(i / PER_COLUMN), (196.0 + ROW_H * float(i % PER_COLUMN)) * k),
			Vector2(w, ROW_H * k))


## Where a row's slider runs, or its tick box sits.
func _control_rect(i: int) -> Rect2:
	var k := _k()
	var r := _row_rect(i)
	if ROWS[i][2] == "tick":
		return Rect2(Vector2(r.end.x - 122.0 * k, r.position.y + 8.0 * k), Vector2(56.0, 30.0) * k)
	return Rect2(Vector2(r.position.x + 262.0 * k, r.position.y + 8.0 * k), Vector2(196.0, 30.0) * k)


## The presets: a row for each kind of machine, six levels across, with the
## kind's name before it and DEFAULTS standing at the end of both.
func _preset_rect(kind: int, level: int) -> Rect2:
	var k := _k()
	var p := _panel_rect()
	var left := 34.0 * k + 130.0 * k
	var w := (p.size.x - 68.0 * k - 130.0 * k - 190.0 * k - 10.0 * k * float(LEVELS.size() - 1)) / float(LEVELS.size())
	return Rect2(p.position + Vector2(left + (w + 10.0 * k) * float(level), (76.0 + 50.0 * float(kind)) * k), Vector2(w, 42.0 * k))


func _defaults_rect() -> Rect2:
	var k := _k()
	var p := _panel_rect()
	return Rect2(Vector2(p.end.x - 34.0 * k - 176.0 * k, p.position.y + 76.0 * k), Vector2(176.0, 92.0) * k)


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
	if _defaults_rect().has_point(mb.position):
		values = _defaults.duplicate()
		apply()
		_view.queue_redraw()
		return
	for kind in KINDS.size():
		for level in LEVELS.size():
			if _preset_rect(kind, level).has_point(mb.position):
				values.merge(preset(KINDS[kind], level), true)
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
		"n":
			return "%d" % int(round(v))
		"m2":
			return "%.2f m" % v
		"pc":
			return "%.1f%%" % (v * 100.0)
		"reach":
			return "ALWAYS" if v >= CliffRocks.ALL_REACH else "%d m" % int(v)
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
	for kind in KINDS.size():
		var first := _preset_rect(kind, 0)
		_label(Vector2(p.position.x + 34.0 * k, first.position.y + 28.0 * k), KINDS[kind], 19.0, Color(INK.r, INK.g, INK.b, 0.6))
		for level in LEVELS.size():
			var b := _preset_rect(kind, level)
			# (Lit when everything it sets is as it sets it.)
			var on := true
			var want := preset(KINDS[kind], level)
			for key in want:
				if typeof(values[key]) == TYPE_BOOL:
					on = on and bool(values[key]) == bool(want[key])
				else:
					on = on and is_equal_approx(float(values[key]), float(want[key]))
			_box(b, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.28) if on else Color(1, 1, 1, 0.07), 12.0,
					ACCENT if on else EDGE, 1.5)
			_label(Vector2(b.get_center().x, b.position.y + 28.0 * k), LEVELS[level], 19.0, INK, 1)
	var db := _defaults_rect()
	_box(db, Color(1, 1, 1, 0.07), 12.0, EDGE, 1.5)
	_label(Vector2(db.get_center().x, db.get_center().y + 7.0 * k), "DEFAULTS", 19.0, INK, 1)
	for i in ROWS.size():
		var row: Array = ROWS[i]
		var r := _row_rect(i)
		if i % PER_COLUMN > 0:
			_view.draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(1.0, k))), Color(1, 1, 1, 0.06))
		_label(r.position + Vector2(0.0, 31.0 * k), row[1], 19.0, Color(INK.r, INK.g, INK.b, 0.88))
		var c := _control_rect(i)
		if row[2] == "tick":
			var on := bool(values[row[0]])
			_box(c, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85) if on else Color(1, 1, 1, 0.1), 15.0, EDGE, 1.5)
			var knob := Vector2(c.end.x - 15.0 * k if on else c.position.x + 15.0 * k, c.get_center().y)
			_view.draw_circle(knob, 11.0 * k, Color(0.04, 0.05, 0.06) if on else Color(INK.r, INK.g, INK.b, 0.8))
			_label(Vector2(r.end.x, r.position.y + 31.0 * k), "ON" if on else "OFF", 18.0, Color(INK.r, INK.g, INK.b, 0.7), 2)
			continue
		var t := inverse_lerp(float(row[3]), float(row[4]), float(values[row[0]]))
		var track := Rect2(Vector2(c.position.x, c.get_center().y - 3.0 * k), Vector2(c.size.x, 6.0 * k))
		_box(track, Color(1, 1, 1, 0.12), 3.0)
		_box(Rect2(track.position, Vector2(track.size.x * t, track.size.y)), ACCENT, 3.0)
		_view.draw_circle(Vector2(track.position.x + track.size.x * t, c.get_center().y), 11.0 * k, INK)
		_label(Vector2(r.end.x, r.position.y + 31.0 * k), _shown(row), 18.0, Color(INK.r, INK.g, INK.b, 0.8), 2)
