extends SceneTree

# THE TABLELANDS FROM THE AIR AND THE GROUND: a few views across the plateaus,
# walls and canyons, to renders/tablelands_*.png.
#
#   godot --path . --script res://tests/RENDER_tablelands.gd

# [from (relative to the island's middle, y over the ground there), look at (y likewise)]
const VIEWS := [
	[Vector3(0, 260, 380), Vector3(0, 0, -700)],
	[Vector3(-700, 60, 200), Vector3(-1000, 20, -200)],
	[Vector3(650, 8, -350), Vector3(900, 30, -700)],
	[Vector3(-150, 30, -420), Vector3(-170, 10, -260)],
]

var _scene: Node
var _cam: Camera3D
var _n := -1
var _view := 0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _ground(p: Vector3) -> float:
	return float(_scene.get_node("GaiaSphere").call(&"height_at", p, 0.0))


func _place() -> void:
	var v: Array = VIEWS[_view]
	var from: Vector3 = v[0]
	var to: Vector3 = v[1]
	from.y += _ground(from)
	to.y += _ground(to)
	_cam.global_position = from
	_cam.look_at(to)
	var ex: Node3D = _scene.get_node("Explorer")
	ex.global_position = from + Vector3.UP * 2.0


func _process(_d: float) -> bool:
	var ex: Node3D = _scene.get_node("Explorer")
	if _n < 0:
		if ex.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 10.0
			enviro.set_weather("clear", 0.0)
			ex.set("flying", true)
			_cam = Camera3D.new()
			_cam.far = 6000.0
			_scene.add_child(_cam)
			_cam.make_current()
			_place()
			_n = 0
		return false
	_n += 1
	if _n == 160:
		root.get_viewport().get_texture().get_image().save_png("res://renders/tablelands_%d.png" % _view)
		_view += 1
		_n = 0
		if _view >= VIEWS.size():
			quit(0)
			return true
		_place()
	return false
