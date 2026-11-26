class_name OptionsMenu
extends CanvasLayer

# THE OPTIONS PANEL: the things that are for trying things out rather than for
# how the game looks on a given machine. F9 or K (the OPT touch button) opens it.
#
#   God mode       nothing hurts, building is free (Vitals.debug; F3 too)
#   Detail grain   how much finer the detail layer's bumps are laid than its
#                  grime, on the truck and the shuttle (SCRIPT_detail_layer.gd)
#   Detail depth   how deep those bumps are
#   Detail grime   how strongly its grime and wear darken the paint
#   Strata ...     the beds drawn on the sides of the cliff's rock: how strong,
#                  how thick a bed, how far the lines wander, how much they dip
#   Cliff edge wear / crevice dark   the baked wear and cracks on the cliff block
#   Ambient occlusion ...   the screen-space shade in creases: off, or one of three
#                  methods, and its dozen settings (SCRIPT_ambient_occlusion.gd)
#
# Nothing here is saved: each run starts from the defaults.

# key, label, kind ("slide" | "tick"), low, high, step, how it is shown
const ROWS := [
	["god", "God mode", "tick"],
	["grain", "Detail grain", "slide", 1.0, 16.0, 0.5, "x"],
	["depth", "Detail depth", "slide", 0.0, 2.0, 0.05, "%"],
	["grime", "Detail grime", "slide", 0.0, 1.5, 0.05, "%"],
	# The cliff's rock (SHADER_cliff_rock.gdshader, and the terrain's own rock for
	# the strata): each is a shader setting of the same name.
	["strata_strength", "Strata strength", "slide", 0.0, 1.5, 0.05, "%"],
	["strata_bed", "Strata bed thickness", "slide", 0.3, 6.0, 0.1, "m"],
	["strata_warp", "Strata wander", "slide", 0.0, 6.0, 0.1, "m"],
	["strata_dip", "Strata dip", "slide", 0.0, 0.3, 0.005, "slope"],
	["strata_colour", "Coloured strata", "slide", 0.0, 1.0, 0.05, "%"],
	["strata_colour_bed", "Coloured bed thickness", "slide", 0.5, 20.0, 0.25, "m"],
	["edge_wear", "Cliff edge wear", "slide", 0.0, 1.5, 0.05, "%"],
	["crevice", "Cliff crevice dark", "slide", 0.0, 1.0, 0.05, "%"],
	# The ground laid more cheaply far off (SHADERINC_ground_lay's normal_reach and
	# stochastic_reach): each a tick, and how far off it begins.
	["far_normals", "Far ground: no normal maps", "tick"],
	["normal_reach", "... beyond", "slide", 20.0, 400.0, 5.0, "m"],
	["far_single", "Far ground: no stochastic", "tick"],
	["stochastic_reach", "... beyond", "slide", 10.0, 400.0, 5.0, "m"],
	# How the cliff's rocks are drawn by distance (SCRIPT_cliff_rocks.gd's `view`).
	["cliff_lod", "Cliff detail distance", "slide", 0.25, 4.0, 0.05, "x"],
	["cliff_far", "Cliff merged past", "slide", 100.0, 2000.0, 25.0, "m"],
	["cliff_reach", "Cliff drawn out to", "slide", 200.0, 6000.0, 50.0, "reach"],
	["cliff_shadow", "Cliff shadows out to", "slide", 0.0, 800.0, 10.0, "m"],
	["cliff_occlusion", "Cliff hidden by ground culled", "tick"],
	# Ambient occlusion over the whole frame (SCRIPT_ambient_occlusion.gd): each
	# "ao_" row is the setting of that name without the prefix.
	["ao_method", "Ambient occlusion", "slide", 0.0, 3.0, 1.0, "ao"],
	["ao_intensity", "AO intensity", "slide", 0.0, 4.0, 0.05, "%"],
	["ao_radius", "AO radius", "slide", 0.1, 5.0, 0.05, "m2"],
	["ao_radius_growth", "AO radius grows with distance", "slide", 0.0, 0.15, 0.005, "slope"],
	["ao_power", "AO contrast", "slide", 0.25, 6.0, 0.05, "x"],
	["ao_bias", "AO bias (self-shading)", "slide", 0.0, 0.2, 0.005, "m2"],
	["ao_falloff", "AO depth falloff", "slide", 0.1, 4.0, 0.05, "x"],
	["ao_max_distance", "AO reaches", "slide", 20.0, 600.0, 5.0, "m"],
	["ao_floor_light", "AO darkest allowed", "slide", 0.0, 1.0, 0.05, "%"],
	["ao_samples", "AO samples (Fast, SSAO)", "slide", 2.0, 32.0, 1.0, "n"],
	["ao_directions", "HBAO directions", "slide", 2.0, 12.0, 1.0, "n"],
	["ao_steps", "HBAO steps", "slide", 2.0, 10.0, 1.0, "n"],
]
const PER_COLUMN := 17
## The rock's settings as the shaders have them to begin with.
const ROCK := {"strata_strength": 0.85, "strata_bed": 1.9, "strata_warp": 1.6, "strata_dip": 0.035,
	"strata_colour": 0.5, "strata_colour_bed": 5.5,
	"normal_reach": 140.0, "stochastic_reach": 90.0,
	"edge_wear": 1.1, "crevice": 0.7}

const PANEL := Color(0.075, 0.085, 0.1, 0.93)
const EDGE := Color(1, 1, 1, 0.14)
const ACCENT := Color(0.6, 0.9, 0.75)
const INK := Color(0.93, 0.95, 0.97)

## True while the panel is up: the sword stands down.
static var menu_open := false

var _defaults := {}
var _rock := ROCK.duplicate()
var _far := {"far_normals": true, "far_single": true}
var _view: Control
var _font: Font
var _drag := -1
var _was_captured := false


func _ready() -> void:
	layer = 36
	menu_open = false
	_font = load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	for row in ROWS:
		_defaults[row[0]] = _read(row[0])
	if not InputMap.has_action(&"wv_options"):
		InputMap.add_action(&"wv_options")
		for code in [KEY_F9, KEY_K]:
			var key := InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(&"wv_options", key)
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
		_view.queue_redraw()      # (god mode can be flipped by its key as well)


func _read(key: String) -> Variant:
	match key:
		"god":
			return Vitals.debug
		"grain":
			return DetailLayer.grain
		"depth":
			return DetailLayer.depth
		"grime":
			return DetailLayer.grime
	if _far.has(key):
		return _far[key]
	if key.begins_with("cliff_"):
		var cliffs := get_node_or_null(^"../CliffRocks") as CliffRocks
		return cliffs.view[key.substr(6)] if cliffs != null else (true if key == "cliff_occlusion" else 1.0)
	if key.begins_with("ao_"):
		var ao := get_node_or_null(^"../AmbientOcclusion") as AmbientOcclusion
		return float(ao.values[key.substr(3)]) if ao != null else float(AmbientOcclusion.DEFAULTS[key.substr(3)])
	return _rock.get(key, 0.0)


func _write(key: String, value: Variant) -> void:
	match key:
		"god":
			Vitals.debug = bool(value)
		"grain":
			DetailLayer.set_look(float(value), DetailLayer.depth, DetailLayer.grime)
		"depth":
			DetailLayer.set_look(DetailLayer.grain, float(value), DetailLayer.grime)
		"grime":
			DetailLayer.set_look(DetailLayer.grain, DetailLayer.depth, float(value))
		_:
			if _far.has(key):
				_far[key] = bool(value)
				_set_rock("normal_reach", float(_rock["normal_reach"]))
				_set_rock("stochastic_reach", float(_rock["stochastic_reach"]))
			elif key.begins_with("cliff_"):
				var cliffs := get_node_or_null(^"../CliffRocks") as CliffRocks
				if cliffs != null:
					cliffs.set_view(key.substr(6), value)
			elif key.begins_with("ao_"):
				var ao := get_node_or_null(^"../AmbientOcclusion") as AmbientOcclusion
				if ao != null:
					ao.put(key.substr(3), float(value))
			elif _rock.has(key):
				_rock[key] = float(value)
				_set_rock(key, float(value))


## A setting of the rock's, onto the cliff rocks' material and the terrain's (the
## strata are on both). The dip is one number here: the beds tilt that much one
## way and half as much across.
func _set_rock(key: String, value: float) -> void:
	var mats: Array = []
	var cliffs := get_node_or_null(^"../CliffRocks")
	if cliffs != null and cliffs.get("_material") is ShaderMaterial:
		mats.append(cliffs.get("_material"))
	var world := get_node_or_null(^"../GaiaSphere")
	if world != null and world.get(&"terrain_material") is ShaderMaterial:
		mats.append(world.get(&"terrain_material"))
	for m: ShaderMaterial in mats:
		if key == "strata_dip":
			m.set_shader_parameter(key, Vector2(value, value * 0.5))
		elif key == "normal_reach":
			# (0 is "never": the tick off.)
			m.set_shader_parameter(key, value if bool(_far["far_normals"]) else 0.0)
		elif key == "stochastic_reach":
			m.set_shader_parameter(key, value if bool(_far["far_single"]) else 0.0)
		else:
			m.set_shader_parameter(key, value)


func set_open(open: bool) -> void:
	if open == menu_open:
		return
	if open:
		for other_name in ["GraphicsMenu", "EnvironmentMenu", "Inventory"]:
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
	if event.is_action_pressed(&"wv_options"):
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
	var columns := ceili(float(ROWS.size()) / float(PER_COLUMN))
	var size := Vector2(48.0 + 786.0 * float(columns), 200.0 + 46.0 * float(mini(ROWS.size(), PER_COLUMN))) * k
	return Rect2((_view.size - size) * 0.5, size)


func _row_rect(i: int) -> Rect2:
	var k := _k()
	var p := _panel_rect()
	return Rect2(p.position + Vector2((34.0 + 786.0 * float(i / PER_COLUMN)) * k, (96.0 + 46.0 * float(i % PER_COLUMN)) * k),
			Vector2(752.0 * k, 46.0 * k))


func _control_rect(i: int) -> Rect2:
	var k := _k()
	var r := _row_rect(i)
	if ROWS[i][2] == "tick":
		return Rect2(Vector2(r.end.x - 122.0 * k, r.position.y + 8.0 * k), Vector2(56.0, 30.0) * k)
	return Rect2(Vector2(r.position.x + 330.0 * k, r.position.y + 8.0 * k), Vector2(290.0, 30.0) * k)


func _defaults_rect() -> Rect2:
	var k := _k()
	var p := _panel_rect()
	return Rect2(Vector2(p.position.x + 34.0 * k, p.end.y - 82.0 * k), Vector2(220.0, 48.0) * k)


# ------------------------------------------------------------------ input

func _slide(i: int, x: float) -> void:
	var row: Array = ROWS[i]
	var track := _control_rect(i)
	var t := clampf((x - track.position.x) / track.size.x, 0.0, 1.0)
	_write(row[0], clampf(snappedf(lerpf(float(row[3]), float(row[4]), t), float(row[5])), float(row[3]), float(row[4])))
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
		for key in _defaults:
			_write(key, _defaults[key])
		_view.queue_redraw()
		return
	for i in ROWS.size():
		if not _row_rect(i).has_point(mb.position):
			continue
		if ROWS[i][2] == "tick":
			_write(ROWS[i][0], not bool(_read(ROWS[i][0])))
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
	var v := float(_read(row[0]))
	if String(row[6]) == "ao":
		return AmbientOcclusion.METHODS[clampi(int(round(v)), 0, AmbientOcclusion.METHODS.size() - 1)]
	if String(row[6]) == "reach":
		return "ALWAYS" if v >= CliffRocks.ALL_REACH else "%d m" % int(v)
	if String(row[6]) == "n":
		return "%d" % int(round(v))
	if String(row[6]) == "m2":
		return "%.2f m" % v
	if String(row[6]) == "x":
		return "%.1fx" % v
	if String(row[6]) == "m":
		return "%.1f m" % v
	if String(row[6]) == "slope":
		return "%.1f%%" % (v * 100.0)
	return "%d%%" % int(round(v * 100.0))


func _draw_view() -> void:
	if not menu_open:
		return
	var k := _k()
	var p := _panel_rect()
	_box(p.grow(10.0 * k), Color(0, 0, 0, 0.22), 34.0)
	_box(p, PANEL, 26.0, EDGE, 1.5)
	_label(p.position + Vector2(34.0, 60.0) * k, "OPTIONS", 26.0, Color(INK.r, INK.g, INK.b, 0.92))
	_label(Vector2(p.end.x - 34.0 * k, p.position.y + 58.0 * k), "F9 or K to close", 19.0, Color(INK.r, INK.g, INK.b, 0.45), 2)
	for i in ROWS.size():
		var row: Array = ROWS[i]
		var r := _row_rect(i)
		if i % PER_COLUMN > 0:
			_view.draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(1.0, k))), Color(1, 1, 1, 0.06))
		_label(r.position + Vector2(0.0, 31.0 * k), row[1], 21.0, Color(INK.r, INK.g, INK.b, 0.88))
		var c := _control_rect(i)
		if row[2] == "tick":
			var on := bool(_read(row[0]))
			_box(c, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85) if on else Color(1, 1, 1, 0.1), 15.0, EDGE, 1.5)
			var knob := Vector2(c.end.x - 15.0 * k if on else c.position.x + 15.0 * k, c.get_center().y)
			_view.draw_circle(knob, 11.0 * k, Color(0.04, 0.05, 0.06) if on else Color(INK.r, INK.g, INK.b, 0.8))
			_label(Vector2(r.end.x, r.position.y + 31.0 * k), "ON" if on else "OFF", 20.0, Color(INK.r, INK.g, INK.b, 0.7), 2)
			continue
		var t := clampf(inverse_lerp(float(row[3]), float(row[4]), float(_read(row[0]))), 0.0, 1.0)
		var track := Rect2(Vector2(c.position.x, c.get_center().y - 3.0 * k), Vector2(c.size.x, 6.0 * k))
		_box(track, Color(1, 1, 1, 0.12), 3.0)
		_box(Rect2(track.position, Vector2(track.size.x * t, track.size.y)), ACCENT, 3.0)
		_view.draw_circle(Vector2(track.position.x + track.size.x * t, c.get_center().y), 11.0 * k, INK)
		_label(Vector2(r.end.x, r.position.y + 31.0 * k), _shown(row), 20.0, Color(INK.r, INK.g, INK.b, 0.8), 2)
	var d := _defaults_rect()
	_box(d, Color(1, 1, 1, 0.07), 12.0, EDGE, 1.5)
	_label(Vector2(d.get_center().x, d.position.y + 32.0 * k), "DEFAULTS", 20.0, INK, 1)
