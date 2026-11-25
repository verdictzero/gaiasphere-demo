extends SceneTree

# GRASS BRUSHED ASIDE: the player stood in the meadow by the first herd, seen
# from a camera a few metres off, once pushing the grass (renders/plant_push_on.png)
# and once not (plant_push_off.png, the player "flying" in the same place).
#
#   godot --path . --script res://tests/RENDER_plant_push.gd

var _scene: Node
var _cam: Camera3D
var _n := -1


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	if _n < 0:
		if ex.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 11.0
			enviro.set_weather("clear", 0.0)
			var g := Flora.glade()
			var at := Vector3(g.x + 12.0, 0.0, g.y + 6.0)
			at.y = float(_scene.get_node("GaiaSphere").call(&"height_at", at, 0.0))
			ex.global_position = at + Vector3.UP * 0.3
			_cam = Camera3D.new()
			_scene.add_child(_cam)
			_cam.make_current()
			_cam.global_position = at + Vector3(2.6, 1.3, 1.2)
			_cam.look_at(at + Vector3.UP * 0.3)
			_n = 0
		return false
	_n += 1
	if _n == 40:
		root.get_viewport().get_texture().get_image().save_png("res://renders/plant_push_on.png")
		ex.set("flying", true)
	if _n == 70:
		root.get_viewport().get_texture().get_image().save_png("res://renders/plant_push_off.png")
		quit(0)
		return true
	return false
