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
			ex.set("flying", true)
			_n = 0
		return false
	# [metres back up the skid, to one side, over the ground] the eye, then the same
	# for what it looks at.
	var views := [
		["crash_skid", Vector3(105, 6, 30), Vector3(40, 0, 0)],          # over the shore, down into the water
		["crash_skid_side", Vector3(70, -9, 2.2), Vector3(190, 0, 2)],   # on the skid, looking up it: the dust
		["crash_skid_under", Vector3(34, 9, 2.5), Vector3(2, 0, 1.5)],   # under water, down the trench to the wreck
		["crash_wreck", Vector3(9, 13, 3.5), Vector3(0, 0, 2.0)],          # close by the wreck, from one side
		["crash_wreck_weed", Vector3(-16, -22, 5.0), Vector3(0, 0, 1.5)],  # from out on the bed, over the weed
		["crash_bubbles", Vector3(-1.5, 5.0, 3.2), Vector3(0, 0, 3.4)],    # right by the hull: its bubbles
	]
	var side := Vector3(-_up.y, 0.0, _up.x)
	var back := Vector3(_up.x, 0.0, _up.y)
	var k := _n / 90
	if _n % 90 == 0 and k < views.size():
		var from: Vector3 = _wreck + back * views[k][1].x + side * views[k][1].y
		from.y = _ground(from) + views[k][1].z
		var to: Vector3 = _wreck + back * views[k][2].x + side * views[k][2].y
		to.y = _ground(to) + views[k][2].z
		_cam.global_position = from
		_cam.look_at(to)
		ex.global_position = from
	_n += 1
	if _n % 90 == 0:
		root.get_viewport().get_texture().get_image().save_png("res://renders/%s.png" % views[k][0])
		if k + 1 >= views.size():
			quit(0)
			return true
	return false
