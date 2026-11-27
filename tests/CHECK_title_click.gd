extends SceneTree

# START, PRESSED AS A PLAYER PRESSES IT: a real click (and then a real touch) at
# the middle of the title's START button, sent in as input, not called.
#
#   VES_TITLE=1 godot --path . --resolution 1280x720 --script res://tests/CHECK_title_click.gd
# (In a real window: headless, the window is 64 pixels square and no click lands in it.)

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


func _move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)


func _touch(at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = down
	e.position = at
	Input.parse_input_event(e)


func _process(_d: float) -> bool:
	var title: TitleMenu = _scene.get_node("TitleMenu")
	if not bool(title.get("_ready_to_play")):
		return false
	_step += 1
	var view: Control = title.get("_view")
	var r: Rect2 = title.call(&"_button_rect", 0, 5)
	var at := r.get_center()
	match _step:
		5:
			print("click: window %s, view %s, START at %s, paused %s" % [root.size, view.size, r, paused])
			_click(at, true)
		7:
			_click(at, false)
		12:
			print("click: a mouse click on START while the game is stopped: %s" % ("STARTS" if not TitleMenu.menu_open else "NOTHING"))
			title.show_menu()
		16:
			_touch(at, true)
		18:
			_touch(at, false)
		24:
			print("click: a finger on RESUME while the game is stopped: %s" % ("RESUMES" if not TitleMenu.menu_open else "NOTHING"))
			print("click: done")
			quit(0)
			return true
	return false
