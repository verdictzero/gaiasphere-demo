extends SceneTree

# THE SHUTTLE'S SKID: from the air over the meadow where it touched down, looking
# down the gouge to the wreck in the mere (renders/crash_skid.png), and from low
# beside the skid (renders/crash_skid_side.png).
#
#   godot --path . --script res://tests/RENDER_crash_skid.gd

var _scene: Node
var _cam: Camera3D
var _n := -1
var _wreck := Vector3.ZERO
var _up := Vector2.ZERO


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _ground(p: Vector3) -> float:
	return float(_scene.get_node("GaiaSphere").call(&"height_at", p, 0.0))


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	if _n < 0:
		if ex.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 10.5
			enviro.set_weather("clear", 0.0)
			_wreck = (_scene.get_node("CrashedShuttle") as Node3D).global_position
			var g := Flora.glade()
			_up = (Vector2(g.x, g.y) - Vector2(_wreck.x, _wreck.z)).normalized()
			_cam = Camera3D.new()
			_cam.far = 4000.0
			_scene.add_child(_cam)
			_cam.make_current()
			var from := _wreck + Vector3(_up.x, 0.0, _up.y) * 120.0
			from.y = _ground(from) + 32.0
			_cam.global_position = from
			_cam.look_at(_wreck + Vector3(_up.x, 0.0, _up.y) * 20.0)
			ex.set("flying", true)
			ex.global_position = from + Vector3.UP * 5.0
			_n = 0
		return false
	_n += 1
	if _n == 60:
		root.get_viewport().get_texture().get_image().save_png("res://renders/crash_skid.png")
		var side := Vector3(-_up.y, 0.0, _up.x)
		var mid := _wreck + Vector3(_up.x, 0.0, _up.y) * 45.0
		var from := mid + side * 18.0 + Vector3(_up.x, 0.0, _up.y) * 25.0
		from.y = _ground(from) + 6.0
		_cam.global_position = from
		ex.global_position = from + Vector3.UP * 5.0
		_cam.look_at(Vector3(_wreck.x, _ground(_wreck) + 1.0, _wreck.z))
	if _n == 120:
		root.get_viewport().get_texture().get_image().save_png("res://renders/crash_skid_side.png")
		quit(0)
		return true
	return false
