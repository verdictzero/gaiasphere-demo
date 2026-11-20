extends SceneTree

# THE GRAPHICS MENU AT WORK: the arrival view at the defaults, at LOW and at
# ULTRA, then the menu itself.
#
#   godot --path . --script res://tests/RENDER_graphics.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0
var _frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("graphics: ", name)


func _process(_dt: float) -> bool:
	_frames += 1
	var explorer := _scene.get_node("Explorer")
	var menu: GraphicsMenu = _scene.get_node("GraphicsMenu")
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			_step = 0
			_wait = 40
		return false
	_wait -= 1
	if _wait > 0:
		return false
	match _step:
		0:
			_shot("0_default")
			menu.values.merge(GraphicsMenu.PRESETS["LOW"], true)
			menu.apply()
			_wait = 30
		1:
			_shot("1_low")
			menu.values.merge(GraphicsMenu.PRESETS["ULTRA"], true)
			menu.apply()
			_wait = 30
		2:
			_shot("2_ultra")
			menu.values = menu._defaults.duplicate()
			menu.apply()
			menu.set_open(true)
			# A drag on the first slider, as a mouse would make it.
			menu._slide(0, menu._control_rect(0).end.x)
			print("graphics: vegetation distance now ", menu.values["veg_distance"])
			_wait = 20
		3:
			_shot("3_menu")
			menu.values = menu._defaults.duplicate()
			menu.apply()
			quit(0)
			return true
	_step += 1
	return false
