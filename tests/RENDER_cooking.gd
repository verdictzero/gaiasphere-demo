extends SceneTree

# COOKING: a fire set down in the meadow by the wreck, three cuts of raw beef put
# on it, and cooked beef in the bag at the end of it.
#
#   godot --path . --script res://tests/RENDER_cooking.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0
var _spot := Vector3.ZERO
var _failed := false
var _waited := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("cooking: ", name)


func _fail(what: String) -> void:
	_failed = true
	print("cooking: FAILED, ", what)


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var fires: Cooking = _scene.get_node("Cooking")
	var bag: Inventory = _scene.get_node("Inventory")
	var cam := root.get_camera_3d()
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 19.4
			enviro.set_weather("clear", 0.0)
			var glade := Flora.glade()
			_spot = Vector3(glade.x - 26.0, 0.0, glade.y + 8.0)
			_spot.y = float(_scene.get_node("GaiaSphere").call(&"height_at", _spot, 0.0))
			explorer.flying = false
			explorer.global_position = _spot + Vector3(0, 0.4, 0)
			explorer.rotation = Vector3.ZERO
			cam.rotation.x = -0.5
			bag.add("campfire", 1)
			bag.add("beef", 4)
			for i in Inventory.HOTBAR:
				if bag.slots[i] != null and String(bag.slots[i][0]) == "campfire":
					bag.selected = i
			_step = 0
			_wait = 60
		return false
	_wait -= 1
	if _wait > 0:
		return false
	match _step:
		0:
			if not fires.holding():
				_fail("the fire is not in hand")
			_shot("0_ghost")
			Input.action_press(&"wv_attack")
			_wait = 3
		1:
			Input.action_release(&"wv_attack")
			if fires._fires.size() != 1 or bag.count_of("campfire") != 0:
				_fail("the use button did not set the fire down (%d fires)" % fires._fires.size())
				quit(1)
				return true
			_wait = 30
		2:
			_shot("1_lit")
			for n in 4:
				fires.try_use(cam.global_position, -cam.global_basis.z)
			var on: int = (fires._fires[0]["cooking"] as Array).size()
			print("cooking: %d cuts on the fire, %d raw left in the bag" % [on, bag.count_of("beef")])
			if on != 3 or bag.count_of("beef") != 1:
				_fail("three cuts should be on and one left")
			_wait = 6
		3:
			_shot("2_cooking")
			_wait = 2
		4:
			_waited += 1
			if bag.count_of("steak") < 3 and _waited < 600:
				return false
			print("cooking: %d cooked in the bag after %d frames" % [bag.count_of("steak"), _waited])
			if bag.count_of("steak") != 3:
				_fail("the beef did not cook")
			_shot("3_done")
			# And the axe takes the fire down.
			if not fires.strike(cam.global_position, -cam.global_basis.z) or bag.count_of("campfire") != 1:
				_fail("the axe did not take the fire down")
			print("cooking: ok" if not _failed else "cooking: FAILED")
			quit(1 if _failed else 0)
			return true
	_step += 1
	return false
