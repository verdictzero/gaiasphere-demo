extends SceneTree

# A BERRY BUSH: in leaf, the cloud as it is stripped, and bare, with the bag.
#
#   godot --path . --script res://tests/RENDER_berries.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0
var _bush := Transform3D()
var _square := Vector2i.ZERO
var _found := false
var _had := 0


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
			if bushes._live[sq] == null:
				continue
			var b: Transform3D = bushes._live[sq]
			count += 1
			if not _found or b.origin.distance_to(here) < _bush.origin.distance_to(here):
				_bush = b
				_square = sq
				_found = true
		print("berries: %d bushes within %d m" % [count, int(bushes.view_range)])
		if not _found:
			push_error("berries: no bush near the start")
			quit(1)
			return true
		var back := here - _bush.origin
		back.y = 0.0
		back = back.normalized()
		explorer.flying = false
		explorer.global_position = _bush.origin + back * 3.0 + Vector3(0, 0.4, 0)
		var from: Vector3 = explorer.global_position + Vector3.UP * cam.position.y
		var d: Vector3 = _bush.origin + Vector3(0, 1.2, 0) - from
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
			# (Held there: put back to half every frame until the still is taken.)
			bushes.regrow_fade = 1e9
			bushes._growing[_square] = 0.5
			bushes._stale = true
			_wait = 6
		3:
			root.get_texture().get_image().save_png(_out.path_join("berry_3_growing.png"))
			# Hungry and winded, the berries in the hand, and one eaten.
			var vitals: Vitals = _scene.get_node("Vitals")
			vitals.hunger = 30.0
			vitals.stamina = 20.0
			for i in Inventory.HOTBAR:
				if bag.slots[i] != null and bag.slots[i][0] == "berry":
					bag.selected = i
			_had = bag.count_of("berry")
			_wait = 8
		4:
			root.get_texture().get_image().save_png(_out.path_join("berry_4_hungry.png"))
			Input.action_press(&"wv_attack")
			_wait = 3
		5:
			Input.action_release(&"wv_attack")
			var vitals2: Vitals = _scene.get_node("Vitals")
			var ate := _had - bag.count_of("berry") == 1 and vitals2.hunger > 40.0
			print("berries: %d left after eating, food %.0f; %s" % [bag.count_of("berry"), vitals2.hunger, "ok" if ate else "FAILED"])
			root.get_texture().get_image().save_png(_out.path_join("berry_5_eaten.png"))
			quit(0 if ate else 1)
			return true
	_step += 1
	return false
