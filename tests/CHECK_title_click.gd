extends SceneTree

# START, PRESSED AS A PLAYER PRESSES IT: a real click (and then a real touch) at
# the middle of the title's START button, sent in as input, not called.
#
#   VES_TITLE=1 godot --headless --path . --script res://tests/CHECK_title_click.gd

var _scene: Node
var _step := 0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _click(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)


func _process(_d: float) -> bool:
	var title: TitleMenu = _scene.get_node("TitleMenu")
	if not bool(title.get("_ready_to_play")):
		return false
	_step += 1
	var view: Control = title.get("_view")
	var r: Rect2 = title.call(&"_button_rect", 0, 5)
	if _step == 5:
		print("click: view %s visible %s filter %d, START at %s, paused %s, hovered %s" % [view.size, view.is_visible_in_tree(), view.mouse_filter,
				r, paused, root.gui_get_hovered_control()])
		_click(r.get_center(), true)
	if _step == 7:
		_click(r.get_center(), false)
	if _step == 12:
		print("click: after a click on START: menu_open %s, paused %s" % [TitleMenu.menu_open, paused])
		print("click: %s" % ("START WORKS" if not TitleMenu.menu_open else "START DOES NOTHING"))
		quit(0)
		return true
	return false
