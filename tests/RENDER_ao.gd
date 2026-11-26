extends SceneTree

# AMBIENT OCCLUSION, each way: one view among the cliff blocks with it off, then
# FAST, SSAO and HBAO (renders/ao_0..3.png), and the options panel open
# (renders/ao_menu.png). The time each method's frame took is printed.
#
#   godot --path . --script res://tests/RENDER_ao.gd

var _scene: Node
var _cam: Camera3D
var _n := -1
var _method := 0
var _t0 := 0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	var ao: AmbientOcclusion = _scene.get_node("AmbientOcclusion")
	if _n < 0:
		var cliffs := _scene.get_node_or_null("CliffRocks")
		if not (ex.arrived and not _scene.has_node("LoadingCover") and (cliffs == null or bool(cliffs.call(&"placed")))):
			return false
		var enviro := _scene.get_node("Enviro")
		enviro.advance = false
		enviro.hour = 10.0
		enviro.set_weather("clear", 0.0)
		ex.set("flying", true)
		var world := _scene.get_node("GaiaSphere")
		var from := Vector3(650, 0, -350)
		from.y = float(world.call(&"height_at", from, 0.0)) + 8.0
		var to := Vector3(900, 0, -700)
		to.y = float(world.call(&"height_at", to, 0.0)) + 30.0
		_cam = Camera3D.new()
		_cam.far = 4000.0
		_scene.add_child(_cam)
		_cam.make_current()
		_cam.global_position = from
		_cam.look_at(to)
		ex.global_position = from + Vector3.UP * 2.0
		ao.put("method", 0.0)
		_n = 0
		return false
	_n += 1
	if _n == 150 or (_method > 0 and _n == 12):
		root.get_viewport().get_texture().get_image().save_png("res://renders/ao_%d.png" % _method)
		print("ao: %s, %d ms a frame here" % [AmbientOcclusion.METHODS[_method], (Time.get_ticks_msec() - _t0)])
		_method += 1
		_n = 0
		if _method > 3:
			_scene.get_node("OptionsMenu").call(&"set_open", true)
			_method = 9
			return false
		ao.put("method", float(_method))
	if _method == 9 and _n == 4:
		root.get_viewport().get_texture().get_image().save_png("res://renders/ao_menu.png")
		quit(0)
		return true
	_t0 = Time.get_ticks_msec()
	return false
