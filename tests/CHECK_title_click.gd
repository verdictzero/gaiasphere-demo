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


func _move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
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
	var at := r.get_center()
	match _step:
		5:
			print("click: window %s, view %s, START at %s, paused %s, mouse mode %d" % [root.size, view.size, r, paused, Input.mouse_mode])
			_move(at)
		8:
			print("click: A  paused, under the pointer: %s; the title's hover %d" % [root.gui_get_hovered_control(), int(title.get("_hover"))])
			_click(at, true)
		10:
			_click(at, false)
		14:
			print("click: A  after a click: menu_open %s" % TitleMenu.menu_open)
			if TitleMenu.menu_open:
				paused = false
				title.set_process(false)          # (or it stops the game again at once)
				_move(at + Vector2(3, 0))
		17:
			print("click: B  not paused, under the pointer: %s; hover %d" % [root.gui_get_hovered_control(), int(title.get("_hover"))])
			_click(at, true)
		19:
			_click(at, false)
		23:
			print("click: B  after a click: menu_open %s" % TitleMenu.menu_open)
			print("click: done")
			quit(0)
			return true
	return false
