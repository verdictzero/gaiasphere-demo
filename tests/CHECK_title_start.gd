extends SceneTree

# THE TITLE BY ITSELF, AND START FROM IT: the program's first scene has nothing of
# the island in it; a real click on START reads the game in, which opens by itself.
#
#   godot --path . --resolution 1280x720 --script res://tests/CHECK_title_start.gd
# (In a real window: headless, the window is 64 pixels square and no click lands in it.)

var _step := 0
var _clicked := false
var _began := 0


func _initialize() -> void:
	change_scene_to_file(String(ProjectSettings.get_setting("application/run/main_scene")))


func _click(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)


func _process(_d: float) -> bool:
	var scene := current_scene
	if scene == null:
		return false
	var title := scene.get_node_or_null("TitleMenu") as TitleMenu
	if title == null:
		return false
	_step += 1
	if not _clicked:
		if _step == 10:
			print("start: the title: %d nodes in the scene, island %s, menu up %s" % [scene.get_child_count(),
					"THERE" if scene.get_node_or_null("GaiaSphere") != null else "not loaded", TitleMenu.menu_open])
			var view: Control = title.get("_view")
			var r: Rect2 = title.call(&"_button_rect", 0, 5)
			_click(r.get_center() * Vector2(root.size) / view.size, true)
		if _step == 12:
			_clicked = true
			_began = Time.get_ticks_msec()
			print("start: START pressed: reading the game in: %s" % bool(title.get("_going")))
		return false
	if scene.get_node_or_null("GaiaSphere") == null:
		return false
	if not TitleMenu.menu_open:
		print("start: in the game after %.0f s, paused %s, explorer arrived %s" % [float(Time.get_ticks_msec() - _began) / 1000.0,
				paused, scene.get_node("Explorer").get("arrived")])
		return true
	return Time.get_ticks_msec() - _began > 1500000
