extends SceneTree

# THE COMPASS AND THE MAP: the view with the compass over it (renders/hud_compass.png),
# then the map opened (renders/map_menu.png).
#
#   godot --path . --script res://tests/RENDER_map.gd

var _scene: Node
var _n := -1


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	var map: MapMenu = _scene.get_node("MapMenu")
	if _n < 0:
		if ex.arrived and not _scene.has_node("LoadingCover") and map.get("_texture") != null:
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 11.0
			ex.set("flying", true)
			var g := Flora.glade()
			var ground := float(_scene.get_node("GaiaSphere").call(&"height_at", Vector3(g.x, 0, g.y), 0.0))
			ex.global_position = Vector3(g.x, ground + 3.0, g.y)
			ex.rotation = Vector3(0.0, deg_to_rad(-40.0), 0.0)
			_n = 0
		return false
	_n += 1
	if _n == 60:
		root.get_viewport().get_texture().get_image().save_png("res://renders/hud_compass.png")
		map.set_open(true)
	if _n == 80:
		root.get_viewport().get_texture().get_image().save_png("res://renders/map_menu.png")
		quit(0)
		return true
	return false
