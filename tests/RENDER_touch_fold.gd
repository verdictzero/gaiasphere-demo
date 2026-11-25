extends SceneTree

# THE TOUCH CONTROLS ON A FOLDING PHONE OPENED OUT: the game at about 6:5 with
# the touchscreen controls forced on, to renders/touch_fold.png, to see that the
# thumb's buttons stand clear of the bars and hotbar.
#
#   godot --path . --resolution 1320x1100 --script res://tests/RENDER_touch_fold.gd

var _scene: Node
var _n := -1


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	(_scene.get_node("TouchLayer/TouchControls")).set("force", true)
	root.add_child(_scene)


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	if _n < 0:
		if ex.arrived and not _scene.has_node("LoadingCover"):
			_n = 0
		return false
	_n += 1
	if _n == 20:
		root.get_viewport().get_texture().get_image().save_png("res://renders/touch_fold.png")
		quit(0)
		return true
	return false
