extends SceneTree

# THE TIME AND ENVIRONMENT PANEL AT WORK: opened at the scene's own hour, then
# with the clock dragged to noon and the weather stepped to a storm.
#
#   godot --path . --script res://tests/RENDER_environment.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _row(key: String) -> int:
	for i in EnvironmentMenu.ROWS.size():
		if EnvironmentMenu.ROWS[i][0] == key:
			return i
	return 0


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var menu: EnvironmentMenu = _scene.get_node("EnvironmentMenu")
	var enviro: Enviro = _scene.get_node("Enviro")
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			menu.set_open(true)
			_step = 0
			_wait = 30
		return false
	_wait -= 1
	if _wait > 0:
		return false
	match _step:
		0:
			root.get_texture().get_image().save_png(_out.path_join("env_0_open.png"))
			# As a mouse would: the hour slider to its middle, the weather to its end.
			var hour := menu._control_rect(_row("hour"))
			menu._slide(_row("hour"), hour.position.x + hour.size.x * 0.52)
			menu._slide(_row("weather"), menu._control_rect(_row("weather")).end.x)
			menu._write("advance", false)
			menu._write("cinematic_grade", 0.0)
			print("environment: hour %.2f, weather %s, advance %s" % [enviro.hour, enviro.weather, enviro.advance])
			_wait = 60
		1:
			root.get_texture().get_image().save_png(_out.path_join("env_1_noon_storm.png"))
			var ok := absf(enviro.hour - 12.5) < 0.2 and enviro.weather == "storm" and not enviro.advance
			print("environment: %s" % ("ok" if ok else "FAILED"))
			quit(0 if ok else 1)
			return true
	_step += 1
	return false
