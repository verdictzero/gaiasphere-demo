extends SceneTree

# THE TITLE SCREEN'S PHOTOGRAPH: the forest from among its trees, looking toward
# a low sun so its light comes through the firs in shafts, at the highest
# settings, with nothing of the game's own drawn over it. Several places and
# hours, to renders/title_bg_<n>.png: the best is made branding/title_bg.jpg.
#
#   godot --path . --resolution 1920x1080 --script res://tests/RENDER_title_bg.gd

const HOURS := [7.6, 8.4, 17.2, 7.9, 16.6, 8.8]

var _scene: Node
var _cam: Camera3D
var _n := -1
var _shot := 0
var _spots: Array = []


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _ground(x: float, z: float) -> float:
	return float(_scene.get_node("GaiaSphere").call(&"height_at", Vector3(x, 0, z), 0.0))


func _place() -> void:
	var enviro := _scene.get_node("Enviro")
	enviro.set("hour", HOURS[_shot % HOURS.size()])
	var at: Vector2 = _spots[_shot]
	var eye := Vector3(at.x, _ground(at.x, at.y) + 1.75, at.y)
	_cam.global_position = eye
	(_scene.get_node("Explorer") as Node3D).global_position = eye
	_n = 0


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	if _n < 0 and _spots.is_empty():
		if not ex.arrived or _scene.has_node("LoadingCover"):
			return false
		var enviro := _scene.get_node("Enviro")
		enviro.advance = false
		enviro.set_weather("clear", 0.0)
		var menu: GraphicsMenu = _scene.get_node("GraphicsMenu")
		menu.values.merge(GraphicsMenu.preset("DESKTOP", 5), true)
		menu.values["god_rays"] = true
		menu.values["dof"] = false
		menu.apply()
		for hidden in ["Vitals", "Inventory", "MapMenu", "Watermark", "TouchLayer", "UniTruck"]:
			var node := _scene.get_node_or_null(hidden)
			if node != null:
				node.set("visible", false)
		ex.set("flying", true)
		# Deep wood on easy ground, well in from the edge, a way apart from each other.
		var field: IslandField = _scene.get_node("GaiaSphere").call(&"get_field")
		var isl: IslandField.Island = field.island_in_cell(field.hub_cell())
		var rng := RandomNumberGenerator.new()
		rng.seed = 2027
		while _spots.size() < HOURS.size():
			var a := rng.randf() * TAU
			var p := isl.center + Vector2(cos(a), sin(a)) * rng.randf_range(520.0, 900.0)
			var s := field.sample(p.x, p.y)
			if not bool(s.get("on_land", false)) or float(s.get("forest", 0.0)) < 0.97 or float(s.get("slope", 1.0)) > 0.03 \
					or float(s.get("flow_weight", 0.0)) > 0.05 or float(s.get("flatten", 0.0)) > 0.05:
				continue
			var near := false
			for q: Vector2 in _spots:
				near = near or q.distance_to(p) < 150.0
			if not near:
				_spots.append(p)
		_cam = Camera3D.new()
		_cam.far = 6000.0
		_cam.fov = 62.0
		_scene.add_child(_cam)
		_cam.make_current()
		_place()
		return false
	_n += 1
	if _n == 6:
		# Toward the sun, now the hour has it where it will be: a little to one
		# side of it and a little up, so it stands behind the trees and not in the
		# middle of the picture.
		var sun: Vector3 = _scene.get_node("Enviro").get("sun_dir")
		var flat := Vector3(sun.x, 0.0, sun.z).normalized().rotated(Vector3.UP, 0.22)
		_cam.look_at(_cam.global_position + flat + Vector3.UP * 0.2)
	if _n == 110:
		root.get_viewport().get_texture().get_image().save_png("res://renders/title_bg_%d.png" % _shot)
		print("title: shot %d at %s, %.1f h" % [_shot, _spots[_shot], HOURS[_shot % HOURS.size()]])
		_shot += 1
		if _shot >= _spots.size():
			quit(0)
			return true
		_place()
	return false
