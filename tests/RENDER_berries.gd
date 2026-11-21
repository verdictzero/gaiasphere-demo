extends SceneTree

# A BERRY BUSH: in leaf, the cloud as it is stripped, and bare, with the bag.
#
#   godot --path . --script res://tests/RENDER_berries.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0
var _bush: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var bushes: BerryBushes = _scene.get_node("BerryBushes")
	var bag: Inventory = _scene.get_node("Inventory")
	var cam := root.get_camera_3d()
	if _step < 0:
		if not explorer.arrived or _scene.has_node("LoadingCover"):
			return false
		var enviro := _scene.get_node("Enviro")
		enviro.advance = false
		enviro.hour = 10.0
		enviro.set_weather("clear", 0.0)
		# The nearest bush that stands, once the squares round the player are in.
		if not bushes._todo.is_empty() or bushes._live.is_empty():
			return false
		var here: Vector3 = explorer.global_position
		var count := 0
		for sq in bushes._live:
			var b: Node3D = bushes._live[sq]
			if b == null:
				continue
			count += 1
			if _bush == null or b.global_position.distance_to(here) < _bush.global_position.distance_to(here):
				_bush = b
		print("berries: %d bushes within %d m" % [count, int(bushes.view_range)])
		if _bush == null:
			push_error("berries: no bush near the start")
			quit(1)
			return true
		var back := here - _bush.global_position
		back.y = 0.0
		back = back.normalized()
		explorer.flying = false
		explorer.global_position = _bush.global_position + back * 3.0 + Vector3(0, 0.4, 0)
		var from: Vector3 = explorer.global_position + Vector3.UP * cam.position.y
		var d: Vector3 = _bush.global_position + Vector3(0, 1.2, 0) - from
		explorer.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
		cam.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
		_step = 0
		_wait = 50
		return false
	_wait -= 1
	if _wait > 0:
		return false
	match _step:
		0:
			root.get_texture().get_image().save_png(_out.path_join("berry_0_leafy.png"))
			if not bushes.strike(cam.global_position, -cam.global_basis.z):
				push_error("berries: the swing met no bush")
				quit(1)
				return true
			_wait = 2
		1:
			root.get_texture().get_image().save_png(_out.path_join("berry_1_cloud.png"))
			_wait = 14
		2:
			root.get_texture().get_image().save_png(_out.path_join("berry_2_bare.png"))
			var got := bag.count_of("berry")
			print("berries: %d in the bag; %s" % [got, "ok" if got >= bushes.berries.x else "FAILED"])
			if got < bushes.berries.x:
				quit(1)
				return true
			# Its leaves half way back, as they would be part way through growing in.
			var sq: Vector2i = _bush.get_meta(&"square")
			bushes._stripped.erase(sq)
			var leafy := _bush.get_node("Leafy") as MeshInstance3D
			leafy.set_instance_shader_parameter(&"grown", 0.5)
			leafy.visible = true
			_wait = 6
		3:
			root.get_texture().get_image().save_png(_out.path_join("berry_3_growing.png"))
			quit(0)
			return true
	_step += 1
	return false
