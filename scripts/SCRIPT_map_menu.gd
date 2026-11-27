class_name MapMenu
extends CanvasLayer

# THE COMPASS AND THE MAP.
#
# THE COMPASS is a strip at the top of the screen, always there: the bearings
# sliding by as the view turns, the one being faced under the mark in its middle
# and written out below it. North is the world's -Z, east its +X.
#
# THE MAP is a panel (M, or the MAP touch button; Escape or the same again shuts
# it): the island from straight above, north up, drawn from the island's own
# field (water, shore, meadow, wood, rock, the trails and the shuttle's skid, lit
# from the north-west so the hills show), with where you are and which way you
# face, and two things marked on it: the Uni-Truck and the Shuttle Wreckage.
#
# The picture is worked out once, on the worker threads behind everything else,
# from MAP_SIDE x MAP_SIDE looks at the field, and kept in user:// under the
# island's own signature, so it is only ever worked out again when the island
# changes. Until it is ready the panel says so.

const MAP_SIDE := 320
const PANEL := Color(0.075, 0.085, 0.1, 0.93)
const EDGE := Color(1, 1, 1, 0.14)
const ACCENT := Color(1.0, 0.86, 0.4)
const INK := Color(0.93, 0.95, 0.97)
const POINTS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

## True while the map is up: the sword stands down, as for the other panels.
static var menu_open := false

@export var world_path: NodePath = ^"../GaiaSphere"
@export var explorer_path: NodePath = ^"../Explorer"

var _view: Control
var _font: Font
var _field: IslandField
var _isl: IslandField.Island
var _reach := 1.0                 # half the map's side, metres
var _centre := Vector2.ZERO
var _level := -1e9
var _texture: ImageTexture
var _rows: Array = []             # each row's colours, as the workers finish them
var _task := -1
var _pool: Array = []
var _lock := Mutex.new()
var _was_captured := false
var _cache := ""


func _ready() -> void:
	layer = 34
	menu_open = false
	_font = load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	if not InputMap.has_action(&"wv_map"):
		InputMap.add_action(&"wv_map")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_M
		InputMap.action_add_event(&"wv_map", key)
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_gui_input)
	add_child(_view)
	var world := get_node_or_null(world_path)
	if world == null or not world.has_method(&"get_field"):
		return
	_field = world.call(&"get_field")
	if _field == null:
		return
	_isl = _field.island_in_cell(_field.hub_cell())
	if _isl == null:
		return
	_centre = _isl.center
	_reach = _field.island_extent(_isl) * 1.02
	var flows: Variant = _field.flows_for(_isl)
	if flows != null and flows.has_lagoon():
		_level = float(_isl.base_y) + float(flows.lagoon_level())
	_cache = "user://map_%s_%d.png" % [String(world.get("_bake_sig")).md5_text().substr(0, 12), MAP_SIDE]
	var held := Image.load_from_file(_cache) if FileAccess.file_exists(_cache) else null
	if held != null and held.get_width() == MAP_SIDE:
		_texture = ImageTexture.create_from_image(held)
		return
	_rows.resize(MAP_SIDE)
	_task = WorkerThreadPool.add_group_task(_row, MAP_SIDE, -1, false, "map")


func _exit_tree() -> void:
	menu_open = false
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)


# ------------------------------------------------------------------ the picture

## One row of the map, on a worker: what the ground is at each of its points.
func _row(j: int) -> void:
	_lock.lock()
	var f: IslandField = _pool.pop_back() if not _pool.is_empty() else null
	_lock.unlock()
	if f == null:
		f = _field.clone()
	var flows: Variant = f.flows_for(f.island_in_cell(_isl.cell))
	var out := PackedColorArray()
	out.resize(MAP_SIDE)
	var light := Vector3(-0.5, 0.72, -0.48).normalized()
	var z := _centre.y + ((float(j) + 0.5) / float(MAP_SIDE) - 0.5) * 2.0 * _reach
	for i in MAP_SIDE:
		var x := _centre.x + ((float(i) + 0.5) / float(MAP_SIDE) - 0.5) * 2.0 * _reach
		var s := f.sample(x, z)
		if not bool(s.get("on_land", false)):
			out[i] = Color(0, 0, 0, 0)
			continue
		var h := float(s["height"])
		var w: Color = s.get("weights", Color(1, 0, 0, 0))
		var forest := float(s.get("forest", 0.0))
		var c := Color(0.42, 0.56, 0.27).lerp(Color(0.17, 0.31, 0.17), clampf(forest * 1.15, 0.0, 1.0))
		c = c.lerp(Color(0.47, 0.38, 0.27), clampf(w.g, 0.0, 1.0) * (1.0 - forest * 0.8))
		c = c.lerp(Color(0.46, 0.46, 0.46), clampf(w.b * 1.2, 0.0, 1.0))
		c = c.lerp(Color(0.83, 0.74, 0.5), clampf(w.a, 0.0, 1.0))
		if String(s.get("zone", "")) == "path":
			c = c.lerp(Color(0.74, 0.62, 0.42), clampf(float(s.get("flatten", 0.0)) * 1.6, 0.0, 1.0))
		if flows != null:
			var crash: Vector2 = flows.crash_weight(x, z)
			c = c.lerp(Color(0.4, 0.29, 0.19), clampf(maxf(crash.x, crash.y) * 1.5, 0.0, 1.0))
		# Lit from the north-west, so the hills stand up off the page.
		var n: Vector3 = s.get("normal", Vector3.UP)
		c = c * clampf(0.55 + 0.75 * n.dot(light), 0.45, 1.25)
		# Water: the mere by its level, the rivers by their channels.
		var wet := smoothstep(0.55, 0.85, float(s.get("flow_weight", 0.0)))
		if h < _level:
			wet = 1.0
		if wet > 0.0:
			var deep := clampf((_level - h) / 9.0, 0.0, 1.0) if h < _level else 0.25
			c = c.lerp(Color(0.2, 0.47, 0.62).lerp(Color(0.07, 0.2, 0.36), deep), wet)
		out[i] = Color(c.r, c.g, c.b, 1.0)
	_lock.lock()
	_pool.append(f)
	_rows[j] = out
	_lock.unlock()


func _process(_delta: float) -> void:
	_view.queue_redraw()          # (the compass turns with the view)
	if _task < 0 or not WorkerThreadPool.is_group_task_completed(_task):
		return
	WorkerThreadPool.wait_for_group_task_completion(_task)
	_task = -1
	var image := Image.create(MAP_SIDE, MAP_SIDE, false, Image.FORMAT_RGBA8)
	for j in MAP_SIDE:
		var row: PackedColorArray = _rows[j]
		for i in MAP_SIDE:
			image.set_pixel(i, j, row[i])
	_rows.clear()
	_pool.clear()
	image.save_png(_cache)
	_texture = ImageTexture.create_from_image(image)


# ------------------------------------------------------------------ open and shut

func set_open(open: bool) -> void:
	if open == menu_open:
		return
	if open:
		for other_name in ["GraphicsMenu", "EnvironmentMenu", "OptionsMenu", "Inventory"]:
			var other := get_node_or_null("../" + other_name)
			if other != null and other.has_method(&"set_open"):
				other.call(&"set_open", false)
	menu_open = open
	_view.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if open:
		_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif _was_captured and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"wv_map"):
		set_open(not menu_open)
		get_viewport().set_input_as_handled()
	elif menu_open and event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if menu_open and mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not _panel_rect().has_point(mb.position):
		set_open(false)


# ------------------------------------------------------------------ drawing

func _k() -> float:
	return UiFit.scale(_view.size)


func _panel_rect() -> Rect2:
	var k := _k()
	var side := minf(_view.size.y - 90.0 * k, 900.0 * k)
	var size := Vector2(side + 330.0 * k, side)
	return Rect2((_view.size - size) * 0.5, size)


func _map_rect() -> Rect2:
	var k := _k()
	var p := _panel_rect()
	var side := p.size.y - 44.0 * k
	return Rect2(p.position + Vector2(22.0, 22.0) * k, Vector2(side, side))


func _box(r: Rect2, fill: Color, radius: float, edge := Color(0, 0, 0, 0), width := 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius * _k()))
	sb.corner_detail = 8
	sb.anti_aliasing = true
	if width > 0.0:
		sb.set_border_width_all(maxi(1, int(round(width * _k()))))
		sb.border_color = edge
	_view.draw_style_box(sb, r)


func _label(at: Vector2, text: String, px: float, color: Color, align := 0) -> void:
	var fs := int(px * _k())
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_view.draw_string(_font, at - Vector2(w * 0.5 * float(align), 0.0) + Vector2(1, 1) * _k(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0, 0, 0, color.a * 0.6))
	_view.draw_string(_font, at - Vector2(w * 0.5 * float(align), 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## The bearing being faced, degrees clockwise from north (the world's -Z).
func _bearing() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var ahead := -cam.global_basis.z
	return fposmod(rad_to_deg(atan2(ahead.x, -ahead.z)), 360.0)


func _to_map(world_xz: Vector2) -> Vector2:
	var m := _map_rect()
	return m.position + ((world_xz - _centre) / (2.0 * _reach) + Vector2(0.5, 0.5)) * m.size


func _draw_view() -> void:
	var explorer := get_node_or_null(explorer_path) as Node3D
	if explorer == null or not bool(explorer.get("arrived")):
		return
	var k := _k()
	var bearing := _bearing()
	if not (Inventory.menu_open or GraphicsMenu.menu_open or EnvironmentMenu.menu_open or OptionsMenu.menu_open or menu_open):
		_draw_compass(k, bearing)
	if not menu_open:
		return
	_view.draw_rect(Rect2(Vector2.ZERO, _view.size), Color(0.0, 0.01, 0.02, 0.5))
	var p := _panel_rect()
	_box(p.grow(10.0 * k), Color(0, 0, 0, 0.22), 34.0)
	_box(p, PANEL, 26.0, EDGE, 1.5)
	var m := _map_rect()
	_box(m, Color(0.05, 0.07, 0.1, 1.0), 10.0, EDGE, 1.5)
	if _texture == null:
		_label(m.get_center(), "DRAWING THE MAP ...", 24.0, Color(INK.r, INK.g, INK.b, 0.7), 1)
	else:
		_view.draw_texture_rect(_texture, m.grow(-2.0 * k), false)
	# What is where.
	var side := Vector2(m.end.x + 26.0 * k, m.position.y + 34.0 * k)
	_label(side, "MAP", 26.0, Color(INK.r, INK.g, INK.b, 0.92))
	_label(Vector2(p.end.x - 22.0 * k, m.position.y + 32.0 * k), "M to close", 18.0, Color(INK.r, INK.g, INK.b, 0.45), 2)
	var legend: Array = []
	var flows: Variant = _field.flows_for(_isl) if _field != null and _isl != null else null
	if flows != null and flows.has_method(&"crash_site"):
		var site: PackedVector2Array = flows.crash_site()
		if site[1] != Vector2.ZERO:
			legend.append(["Shuttle Wreckage", Color(1.0, 0.45, 0.3), site[0], "square"])
	var truck := get_node_or_null(^"../UniTruck")
	if truck != null and truck.get("body") != null:
		var at := (truck.get("body") as Node3D).global_position
		legend.append(["Uni-Truck", Color(0.45, 0.85, 1.0), Vector2(at.x, at.z), "square"])
	var line := 0
	for entry: Array in legend:
		var at := _to_map(entry[2])
		_mark(at, entry[1], String(entry[3]), 7.0 * k)
		if String(entry[0]) != "":
			var ly := side.y + (54.0 + 38.0 * float(line)) * k
			_mark(Vector2(side.x + 9.0 * k, ly - 7.0 * k), entry[1], String(entry[3]), 7.0 * k)
			_label(Vector2(side.x + 30.0 * k, ly), String(entry[0]), 20.0, Color(INK.r, INK.g, INK.b, 0.85))
			line += 1
	# You: an arrow the way you face, over everything.
	var me := Vector2(explorer.global_position.x, explorer.global_position.z)
	var here := _to_map(me)
	var turn := deg_to_rad(bearing)
	var ahead := Vector2(sin(turn), -cos(turn))
	var across := Vector2(-ahead.y, ahead.x)
	var arrow := PackedVector2Array([here + ahead * 15.0 * k, here - ahead * 9.0 * k + across * 9.0 * k, here - ahead * 4.0 * k,
			here - ahead * 9.0 * k - across * 9.0 * k])
	_view.draw_colored_polygon(arrow, ACCENT)
	_view.draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[3], arrow[0]]), Color(0, 0, 0, 0.85), 2.0 * k, true)
	var ly2 := side.y + (54.0 + 38.0 * float(line)) * k
	_view.draw_colored_polygon(PackedVector2Array([Vector2(side.x + 9.0 * k, ly2 - 16.0 * k), Vector2(side.x + 17.0 * k, ly2 + 1.0 * k),
			Vector2(side.x + 9.0 * k, ly2 - 4.0 * k), Vector2(side.x + 1.0 * k, ly2 + 1.0 * k)]), ACCENT)
	_label(Vector2(side.x + 30.0 * k, ly2), "You", 20.0, Color(INK.r, INK.g, INK.b, 0.85))
	# North, the scale, and where you stand.
	var north := Vector2(m.end.x - 34.0 * k, m.position.y + 62.0 * k)
	_view.draw_colored_polygon(PackedVector2Array([north + Vector2(0, -30) * k, north + Vector2(11, 6) * k, north + Vector2(0, -2) * k,
			north + Vector2(-11, 6) * k]), INK)
	_label(north + Vector2(0, 30) * k, "N", 22.0, INK, 1)
	var metres := 500.0
	var bar := metres / (2.0 * _reach) * m.size.x
	var b0 := Vector2(m.position.x + 22.0 * k, m.end.y - 24.0 * k)
	_view.draw_line(b0, b0 + Vector2(bar, 0), INK, 3.0 * k, true)
	_view.draw_line(b0 + Vector2(0, -6) * k, b0 + Vector2(0, 6) * k, INK, 2.0 * k)
	_view.draw_line(b0 + Vector2(bar, -6.0 * k), b0 + Vector2(bar, 6.0 * k), INK, 2.0 * k)
	_label(b0 + Vector2(bar * 0.5, -10.0 * k), "%d m" % int(metres), 18.0, INK, 1)
	var from_mid := me - _centre
	_label(Vector2(side.x, m.end.y - 64.0 * k), "Facing %s  %03d" % [POINTS[int(round(bearing / 45.0)) % 8], int(round(bearing)) % 360], 20.0,
			Color(INK.r, INK.g, INK.b, 0.85))
	_label(Vector2(side.x, m.end.y - 34.0 * k), "%d m %s, %d m %s" % [int(absf(from_mid.x)), "east" if from_mid.x >= 0.0 else "west",
			int(absf(from_mid.y)), "south" if from_mid.y >= 0.0 else "north"], 20.0, Color(INK.r, INK.g, INK.b, 0.85))
	_label(Vector2(side.x, m.end.y - 8.0 * k), "of the island's middle", 16.0, Color(INK.r, INK.g, INK.b, 0.5))


func _mark(at: Vector2, colour: Color, shape: String, r: float) -> void:
	match shape:
		"dot":
			_view.draw_circle(at, r * 0.75, Color(0, 0, 0, 0.85))
			_view.draw_circle(at, r * 0.5, colour)
		"diamond":
			var pts := PackedVector2Array([at + Vector2(0, -r * 1.2), at + Vector2(r * 1.2, 0), at + Vector2(0, r * 1.2), at + Vector2(-r * 1.2, 0)])
			_view.draw_colored_polygon(pts, colour)
			_view.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.85), maxf(1.5, r * 0.25), true)
		_:
			_view.draw_rect(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), colour)
			_view.draw_rect(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), Color(0, 0, 0, 0.85), false, maxf(1.5, r * 0.25))


## The strip at the top: sixty degrees either side of the way faced.
func _draw_compass(k: float, bearing: float) -> void:
	var edge := UiFit.insets(_view.size)
	var wide := minf(560.0 * k, _view.size.x * 0.42)
	var mid := Vector2(_view.size.x * 0.5, 30.0 * k + edge.y)
	var span := 60.0
	var back := Rect2(mid + Vector2(-wide * 0.5 - 14.0 * k, -19.0 * k), Vector2(wide + 28.0 * k, 38.0 * k))
	_box(back, Color(0.04, 0.05, 0.06, 0.42), 19.0, EDGE, 1.5)
	var first := int(floor((bearing - span) / 5.0)) * 5
	for deg in range(first, int(bearing + span) + 5, 5):
		var off := (float(deg) - bearing) / span
		if absf(off) > 1.0:
			continue
		var x := mid.x + off * wide * 0.5
		var fade := 1.0 - smoothstep(0.7, 1.0, absf(off))
		var d := posmod(deg, 360)
		if d % 45 == 0:
			var name: String = POINTS[d / 45]
			var main := d % 90 == 0
			_label(Vector2(x, mid.y + 8.0 * k), name, 24.0 if main else 18.0,
					Color(ACCENT.r, ACCENT.g, ACCENT.b, fade) if d == 0 else Color(INK.r, INK.g, INK.b, fade * (0.95 if main else 0.7)), 1)
		elif d % 15 == 0:
			_view.draw_line(Vector2(x, mid.y - 7.0 * k), Vector2(x, mid.y + 7.0 * k), Color(INK.r, INK.g, INK.b, 0.55 * fade), 2.0 * k)
		else:
			_view.draw_line(Vector2(x, mid.y - 3.0 * k), Vector2(x, mid.y + 3.0 * k), Color(INK.r, INK.g, INK.b, 0.3 * fade), 1.5 * k)
	# The mark in the middle, and the bearing under it.
	_view.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -15) * k, mid + Vector2(7, -24) * k, mid + Vector2(-7, -24) * k]), ACCENT)
	_label(Vector2(mid.x, mid.y + 40.0 * k), "%03d" % (int(round(bearing)) % 360), 17.0, Color(INK.r, INK.g, INK.b, 0.75), 1)
