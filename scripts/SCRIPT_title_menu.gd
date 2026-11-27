class_name TitleMenu
extends CanvasLayer

# THE TITLE SCREEN, which is also the pause menu.
#
# AT THE START it stands over everything, a photograph of the island's forest
# behind it (branding/title_bg.jpg: the game's own picture, at its highest
# settings, the sun coming through the firs) and the game's name on it, while
# the island loads behind; START and LOAD are greyed until it has. Escape (or
# the MENU touch button) in the game brings it back over the game itself, which
# stops while it is up: START reads RESUME then, and SAVE can be used.
#
#   START / RESUME   into the game
#   SAVE             writes the game to user://save.dat (one save)
#   LOAD             reads it back
#   OPTIONS          the game's settings panels, one tab for each there is
#                    (graphics, environment, options: whichever are in the
#                    scene), drawn as themselves with the tabs across the top
#   QUIT             (not on a phone, which has its own way out)
#
# WHAT A SAVE HOLDS: where you stand and which way you face; health, hunger,
# stamina and breath; the bag and what is in hand; the hour and the weather;
# EVERYTHING BUILT (every piece of every building, and every cooking fire); every
# tree felled and rock quarried; where the truck is. Not the cows (a herd is made
# up again overnight anyway) nor what is cooking on a fire.
# A load takes down what is built and builds what the save has. One thing it
# cannot do is stand a felled tree back up: trees felled since the save stay
# felled until the game is started afresh.

const SAVE := "user://save.dat"
const SAVE_VERSION := 1
const PANEL := Color(0.075, 0.085, 0.1, 0.9)
const EDGE := Color(1, 1, 1, 0.16)
const ACCENT := Color(0.24, 0.73, 0.76)
const INK := Color(0.95, 0.96, 0.98)
## The settings panels there may be, and what each tab says.
const PANES := [["GraphicsMenu", "GRAPHICS"], ["EnvironmentMenu", "ENVIRONMENT"], ["OptionsMenu", "OPTIONS"]]

## True while it is up: nothing in the game takes input.
static var menu_open := false

var _view: Control
var _tabs: CanvasLayer
var _tab_view: Control
var _font: Font
var _logo: Texture2D
var _photo: Texture2D
var _boot := true                 # the title, before the game has been entered
var _ready_to_play := false
var _options := false
var _pane := 0
var _panes: Array = []            # [node, label] of those in the scene
var _hover := -1
var _note := ""
var _note_left := 0.0
var _was_captured := false
var _pane_layers := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 210
	menu_open = true
	_font = load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	_logo = load("res://branding/logo.png")
	if ResourceLoader.exists("res://branding/title_bg.jpg"):
		_photo = load("res://branding/title_bg.jpg")
	if not InputMap.has_action(&"wv_menu"):
		InputMap.add_action(&"wv_menu")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event(&"wv_menu", key)
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_gui_input)
	add_child(_view)
	# The tabs go over the panels they choose between.
	_tabs = CanvasLayer.new()
	_tabs.layer = layer + 2
	_tabs.visible = false
	add_child(_tabs)
	_tab_view = Control.new()
	_tab_view.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tab_view.custom_minimum_size = Vector2(0, 80)
	_tab_view.mouse_filter = Control.MOUSE_FILTER_PASS
	_tab_view.draw.connect(_draw_tabs)
	_tab_view.gui_input.connect(_on_tab_input)
	_tabs.add_child(_tab_view)
	for entry: Array in PANES:
		var node := get_node_or_null("../" + String(entry[0]))
		if node != null and node.has_method(&"set_open"):
			node.process_mode = Node.PROCESS_MODE_ALWAYS
			_panes.append([node, String(entry[1])])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# RUN BY A SCRIPT (the bake, the tests, the renders: `godot --script ...`), there
	# is nobody to press START: it stands aside, and comes up only if asked for.
	# (VES_TITLE in the environment: a test of the title itself, which wants it.)
	if get_tree().get_script() != null and not OS.has_environment("VES_TITLE"):
		menu_open = false
		_boot = false
		_view.visible = false
		_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer = 60
		_tabs.layer = 62


func _exit_tree() -> void:
	menu_open = false
	get_tree().paused = false


func _loaded() -> bool:
	var explorer := get_node_or_null(^"../Explorer")
	return explorer != null and bool(explorer.get("arrived")) and not get_parent().has_node(^"LoadingCover")


func _process(delta: float) -> void:
	_note_left = maxf(_note_left - delta, 0.0)
	if not _ready_to_play and _loaded():
		_ready_to_play = true
	if menu_open:
		# The game stands still behind it, once there is a game to stand still.
		if _ready_to_play and not get_tree().paused:
			get_tree().paused = true
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# A panel shut from inside itself (its own key, a click beside it): back to
		# the buttons, unless another has been opened.
		if _options and not _pane_open():
			_leave_options()
	_view.queue_redraw()
	_tab_view.queue_redraw()


func _pane_open() -> bool:
	for entry: Array in _panes:
		if bool((entry[0] as Node).get(&"menu_open")):
			return true
	return false


# ------------------------------------------------------------------ in and out

func show_menu() -> void:
	if menu_open:
		return
	menu_open = true
	_boot = false
	layer = 60
	_tabs.layer = 62
	_view.visible = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func play() -> void:
	if not _ready_to_play:
		return
	_leave_options()
	menu_open = false
	_boot = false
	_view.visible = false
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = false
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _enter_options(pane: int) -> void:
	if _panes.is_empty():
		return
	_options = true
	_pane = clampi(pane, 0, _panes.size() - 1)
	_tabs.visible = true
	for i in _panes.size():
		var node: CanvasLayer = _panes[i][0]
		if not _pane_layers.has(node):
			_pane_layers[node] = node.layer
		node.layer = layer + 1
		node.call(&"set_open", i == _pane)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _leave_options() -> void:
	if not _options:
		return
	_options = false
	_tabs.visible = false
	for entry: Array in _panes:
		var node: CanvasLayer = entry[0]
		if bool(node.get(&"menu_open")):
			node.call(&"set_open", false)
		if _pane_layers.has(node):
			node.layer = int(_pane_layers[node])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"wv_menu"):
		return
	if menu_open:
		if _options:
			_leave_options()
			get_viewport().set_input_as_handled()
		elif not _boot:
			play()
			get_viewport().set_input_as_handled()
		return
	# In the game: Escape shuts whatever panel is up first (theirs to do), and
	# brings this up only when none is.
	if Inventory.menu_open or GraphicsMenu.menu_open or EnvironmentMenu.menu_open or OptionsMenu.menu_open or MapMenu.menu_open:
		return
	if _ready_to_play:
		show_menu()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ the buttons

func _buttons() -> Array:
	var out: Array = [["START" if _boot else "RESUME", "play", _ready_to_play]]
	out.append(["SAVE", "save", _ready_to_play and not _boot])
	out.append(["LOAD", "load", _ready_to_play and FileAccess.file_exists(SAVE)])
	out.append(["OPTIONS", "options", not _panes.is_empty()])
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		out.append(["QUIT", "quit", true])
	return out


func _k() -> float:
	return UiFit.scale(_view.size)


func _button_rect(i: int, n: int) -> Rect2:
	var k := _k()
	var size := Vector2(380.0, 64.0) * k
	var top := _view.size.y * 0.47
	return Rect2(Vector2((_view.size.x - size.x) * 0.5, top + (size.y + 16.0 * k) * float(i)), size)


func _on_gui_input(event: InputEvent) -> void:
	if not menu_open or _options:
		return
	if event is InputEventMouseMotion:
		_hover = -1
		var list := _buttons()
		for i in list.size():
			if _button_rect(i, list.size()).has_point((event as InputEventMouseMotion).position):
				_hover = i
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var buttons := _buttons()
	for i in buttons.size():
		if _button_rect(i, buttons.size()).has_point(mb.position) and bool(buttons[i][2]):
			_press(String(buttons[i][1]))
			return


func _press(what: String) -> void:
	match what:
		"play":
			play()
		"save":
			_say("SAVED" if save_game() else "COULD NOT SAVE")
		"load":
			if load_game():
				play()
			else:
				_say("NO SAVE THAT CAN BE READ")
		"options":
			_enter_options(_pane)
		"quit":
			get_tree().quit()


func _say(text: String) -> void:
	_note = text
	_note_left = 2.5


# ------------------------------------------------------------------ the tabs

func _tab_rect(i: int) -> Rect2:
	var k := _k()
	var n := _panes.size() + 1                # and BACK
	var w := 230.0 * k
	var gap := 12.0 * k
	var total := w * float(n) + gap * float(n - 1)
	return Rect2(Vector2((_view.size.x - total) * 0.5 + (w + gap) * float(i), 12.0 * k), Vector2(w, 46.0 * k))


func _on_tab_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for i in _panes.size() + 1:
		if _tab_rect(i).has_point(mb.position):
			if i == _panes.size():
				_leave_options()
			else:
				_enter_options(i)
			_tab_view.accept_event()
			return


func _draw_tabs() -> void:
	if not _options:
		return
	var k := _k()
	_tab_view.custom_minimum_size = Vector2(0, 70.0 * k)
	for i in _panes.size() + 1:
		var r := _tab_rect(i)
		var on := i == _pane and i < _panes.size()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85) if on else Color(0.06, 0.07, 0.09, 0.92)
		sb.set_corner_radius_all(int(12.0 * k))
		sb.set_border_width_all(maxi(1, int(1.5 * k)))
		sb.border_color = ACCENT if on else EDGE
		sb.anti_aliasing = true
		_tab_view.draw_style_box(sb, r)
		var text: String = "BACK" if i == _panes.size() else String(_panes[i][1])
		var fs := int(21.0 * k)
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_tab_view.draw_string(_font, Vector2(r.get_center().x - w * 0.5, r.position.y + 31.0 * k), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0.03, 0.04, 0.05) if on else INK)


# ------------------------------------------------------------------ drawing

func _label(at: Vector2, text: String, px: float, color: Color, align := 1) -> void:
	var fs := int(px * _k())
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_view.draw_string(_font, at - Vector2(w * 0.5 * float(align), 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw_view() -> void:
	if not menu_open:
		return
	var k := _k()
	var full := Rect2(Vector2.ZERO, _view.size)
	if _boot:
		# The photograph, filling the screen whatever its shape.
		_view.draw_rect(full, Color(0.02, 0.04, 0.03))
		if _photo != null:
			var ps := Vector2(_photo.get_size())
			var fit := maxf(full.size.x / ps.x, full.size.y / ps.y)
			var size := ps * fit
			_view.draw_texture_rect(_photo, Rect2((full.size - size) * 0.5, size), false)
		# Darker toward the foot, where the buttons are, and a little all over.
		for band in 12:
			var t := float(band) / 12.0
			_view.draw_rect(Rect2(0, full.size.y * t, full.size.x, full.size.y / 12.0 + 1.0), Color(0, 0, 0, 0.12 + 0.4 * t * t))
	else:
		_view.draw_rect(full, Color(0.0, 0.01, 0.02, 0.62))
	if _options:
		return
	# The name.
	var lw := minf(full.size.x * 0.62, 900.0 * k)
	var lh := lw * float(_logo.get_height()) / float(_logo.get_width())
	_view.draw_texture_rect(_logo, Rect2(Vector2((full.size.x - lw) * 0.5, full.size.y * 0.42 - lh - 26.0 * k), Vector2(lw, lh)), false)
	var buttons := _buttons()
	for i in buttons.size():
		var r := _button_rect(i, buttons.size())
		var live := bool(buttons[i][2])
		var hot := live and i == _hover
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.9) if hot else PANEL
		sb.set_corner_radius_all(int(14.0 * k))
		sb.set_border_width_all(maxi(1, int(2.0 * k)))
		sb.border_color = ACCENT if live else EDGE
		sb.anti_aliasing = true
		_view.draw_style_box(sb, r)
		var ink := Color(0.03, 0.04, 0.05) if hot else (INK if live else Color(INK.r, INK.g, INK.b, 0.35))
		_label(Vector2(r.get_center().x, r.position.y + 42.0 * k), String(buttons[i][0]), 28.0, ink)
	var foot := Vector2(full.size.x * 0.5, full.size.y - 34.0 * k)
	if _note_left > 0.0:
		_label(foot, _note, 24.0, Color(1.0, 0.86, 0.4, minf(_note_left, 1.0)))
	elif not _ready_to_play:
		_label(foot, "THE ISLAND IS LOADING ...", 22.0, Color(INK.r, INK.g, INK.b, 0.7))
	else:
		_label(foot, "%s" % String(ProjectSettings.get_setting("application/config/version", "")), 18.0, Color(INK.r, INK.g, INK.b, 0.45))


# ------------------------------------------------------------------ saving and loading

func save_game() -> bool:
	var root := get_parent()
	var explorer := root.get_node_or_null(^"Explorer") as Node3D
	if explorer == null:
		return false
	var truck := root.get_node_or_null(^"UniTruck")
	# (Saved from the driver's seat, you are saved standing beside the truck.)
	var data := {
		"version": SAVE_VERSION,
		"player": {"at": explorer.global_position, "yaw": explorer.rotation.y, "pitch": float(explorer.get("_pitch")),
			"flying": bool(explorer.get("flying"))},
	}
	var vitals := root.get_node_or_null(^"Vitals")
	if vitals != null:
		data["vitals"] = {"health": vitals.get("health"), "hunger": vitals.get("hunger"), "stamina": vitals.get("stamina"),
			"oxygen": vitals.get("oxygen"), "god": Vitals.debug}
	var bag := root.get_node_or_null(^"Inventory")
	if bag != null:
		data["bag"] = {"slots": (bag.get("slots") as Array).duplicate(true), "selected": bag.get("selected")}
	var enviro := root.get_node_or_null(^"Enviro")
	if enviro != null:
		data["sky"] = {"hour": enviro.get("hour"), "weather": enviro.get("weather")}
	var building := root.get_node_or_null(^"Building")
	if building != null and building.has_method(&"saved"):
		data["built"] = building.call(&"saved")
	var cooking := root.get_node_or_null(^"Cooking")
	if cooking != null and cooking.has_method(&"saved"):
		data["fires"] = cooking.call(&"saved")
	var flora := root.get_node_or_null(^"Flora")
	if flora != null:
		data["taken"] = (flora.get("taken") as Array).duplicate(true)
	if truck != null and truck.get("body") != null:
		data["truck"] = (truck.get("body") as Node3D).global_transform
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data)
	f.close()
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE):
		return false
	var f := FileAccess.open(SAVE, FileAccess.READ)
	if f == null:
		return false
	var got: Variant = f.get_var()
	f.close()
	if not (got is Dictionary) or int((got as Dictionary).get("version", 0)) != SAVE_VERSION:
		return false
	var data: Dictionary = got
	var root := get_parent()
	var explorer := root.get_node_or_null(^"Explorer") as CharacterBody3D
	if explorer == null:
		return false
	var truck := root.get_node_or_null(^"UniTruck")
	if truck != null and UniTruck.driving:
		truck.call(&"get_out")
	# The world first, then you into it.
	var flora := root.get_node_or_null(^"Flora")
	if flora != null and data.has("taken"):
		flora.call(&"take_again", data["taken"])
	var building := root.get_node_or_null(^"Building")
	if building != null and data.has("built"):
		building.call(&"restore", data["built"])
	var cooking := root.get_node_or_null(^"Cooking")
	if cooking != null and data.has("fires"):
		cooking.call(&"restore", data["fires"])
	if truck != null and data.has("truck") and truck.get("body") != null:
		var body := truck.get("body") as RigidBody3D
		body.global_transform = data["truck"]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	var enviro := root.get_node_or_null(^"Enviro")
	if enviro != null and data.has("sky"):
		enviro.set("hour", float(data["sky"]["hour"]))
		enviro.call(&"set_weather", String(data["sky"]["weather"]), 0.0)
	var bag := root.get_node_or_null(^"Inventory")
	if bag != null and data.has("bag"):
		bag.set("slots", (data["bag"]["slots"] as Array).duplicate(true))
		bag.set("selected", int(data["bag"]["selected"]))
	var vitals := root.get_node_or_null(^"Vitals")
	if vitals != null and data.has("vitals"):
		for key in ["health", "hunger", "stamina", "oxygen"]:
			vitals.set(key, float(data["vitals"][key]))
		Vitals.debug = bool(data["vitals"].get("god", false))
	var player: Dictionary = data["player"]
	explorer.global_position = player["at"]
	explorer.velocity = Vector3.ZERO
	explorer.rotation = Vector3(0.0, float(player["yaw"]), 0.0)
	explorer.set("_pitch", float(player["pitch"]))
	var cam := explorer.get("_cam") as Camera3D
	if cam != null:
		cam.rotation.x = float(player["pitch"])
	explorer.set("flying", bool(player.get("flying", false)))
	return true
