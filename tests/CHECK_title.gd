extends SceneTree

# THE TITLE SCREEN AND THE PAUSE MENU, gone through: up at the start with the
# island loading behind it; the game stopped once it has loaded; START into the
# game; Escape's menu back over it and the game stopped again; each settings
# panel opened from OPTIONS and shut; RESUME.
#
#   VES_TITLE=1 godot --headless --path . --script res://tests/CHECK_title.gd

var _scene: Node
var _step := 0
var _fails := 0
var _waited := 0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _check(what: String, ok: bool, detail := "") -> void:
	print("title: %s %s %s" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_fails += 1


func _process(_d: float) -> bool:
	var title: TitleMenu = _scene.get_node("TitleMenu")
	if _step == 0:
		_check("up at the start", TitleMenu.menu_open and bool(title.get("_boot")))
		_check("START not yet to be had", not bool((title.call(&"_buttons") as Array)[0][2]))
		_step = 1
		return false
	if _step == 1:
		_waited += 1
		if not bool(title.get("_ready_to_play")):
			return false
		_step = 2
		return false
	_step += 1
	match _step:
		6:
			_check("the game stopped behind it once loaded", paused)
			_check("START to be had", bool((title.call(&"_buttons") as Array)[0][2]))
			_check("no SAVE on the title", not bool((title.call(&"_buttons") as Array)[1][2]))
			title.call(&"_press", "play")
		10:
			_check("START: into the game, running", not TitleMenu.menu_open and not paused)
			title.show_menu()
		14:
			_check("the menu over the game, the game stopped", TitleMenu.menu_open and paused and not bool(title.get("_boot")))
			_check("RESUME and SAVE", String((title.call(&"_buttons") as Array)[0][0]) == "RESUME" and bool((title.call(&"_buttons") as Array)[1][2]))
			_check("a save from the menu", title.save_game())
			title.call(&"_press", "options")
		18:
			var panes: Array = title.get("_panes")
			_check("OPTIONS: %d panels, the first open" % panes.size(), panes.size() >= 3 and GraphicsMenu.menu_open)
			title.call(&"_enter_options", 1)
		22:
			_check("the second tab", EnvironmentMenu.menu_open and not GraphicsMenu.menu_open)
			title.call(&"_enter_options", 2)
		26:
			_check("the third tab", OptionsMenu.menu_open and not EnvironmentMenu.menu_open)
			title.call(&"_leave_options")
		30:
			_check("BACK: the buttons again, still stopped", not OptionsMenu.menu_open and TitleMenu.menu_open and paused)
			_check("LOAD to be had now", bool((title.call(&"_buttons") as Array)[2][2]))
			title.call(&"_press", "load")
		34:
			_check("LOAD: into the game, running", not TitleMenu.menu_open and not paused)
			print("title: %s" % ("ALL WELL" if _fails == 0 else "%d THINGS WRONG" % _fails))
			quit(0 if _fails == 0 else 1)
			return true
	return false
