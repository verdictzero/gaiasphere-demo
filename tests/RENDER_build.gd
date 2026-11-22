extends SceneTree

# BUILDING A HUT BY HAND: a foundation set down where the player points, a second
# snapped beside it, then walls, a doorway, floors, gables, a roof and steps on
# the same grid; the door opened and walked through; a wall taken down with the axe.
#
#   godot --path . --script res://tests/RENDER_build.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0
var _failed := false
var _walked := 0
var _frame: Transform3D
var _door: Door


func _look(explorer: Node3D, from: Vector3, target: Vector3) -> void:
	var cam := root.get_camera_3d()
	explorer.global_position = from - Vector3.UP * cam.position.y
	var d := target - from
	explorer.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	cam.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("build: ", name)


func _fail(what: String) -> void:
	push_error("build: " + what)
	print("build: FAILED, ", what)
	_failed = true


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var built: Building = _scene.get_node("Building")
	var bag: Inventory = _scene.get_node("Inventory")
	var cam := root.get_camera_3d()
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 9.5
			enviro.set_weather("clear", 0.0)
			for item in ["foundation", "wall", "doorway", "floor", "roof", "gable", "steps"]:
				bag.add(item, 8)
			# The foundations are the third thing in the hotbar (after the axe and the pickaxe).
			for i in Inventory.HOTBAR:
				if bag.slots[i] != null and String(bag.slots[i][0]) == "foundation":
					bag.selected = i
			explorer.flying = false
			cam.rotation.x = -0.42
			_step = 0
			_wait = 40
		return false
	_wait -= 1
	if _wait > 0:
		return false
	match _step:
		0:
			if built.holding() != "foundation":
				_fail("not holding a foundation but '%s'" % built.holding())
			var plan := built.aim("foundation", cam.global_position, -cam.global_basis.z)
			if plan.is_empty() or not bool(plan["free"]):
				_fail("nowhere to put the first foundation")
				quit(1)
				return true
			_shot("0_ghost")
			# Set down as the hand does it: the use button.
			Input.action_press(&"wv_attack")
			_wait = 3
		1:
			Input.action_release(&"wv_attack")
			if built._buildings.size() != 1 or bag.count_of("foundation") != 7:
				_fail("the use button did not set the foundation down (%d buildings, %d left)" % [built._buildings.size(), bag.count_of("foundation")])
				quit(1)
				return true
			_frame = built._buildings[0]["frame"]
			# The same spot again is taken.
			var again := built.aim("foundation", cam.global_position, -cam.global_basis.z)
			print("build: pointing at the foundation's near side again: ", "free" if bool(again.get("free", false)) else "taken", " ", again.get("key", ""))
			var south := Vector3(0, 0, 1)
			var north := Vector3(0, 0, -1)
			var ok := true
			ok = built.put(0, "foundation", Vector3(3, -0.3, 1), north) != null and ok
			ok = built.put(0, "foundation", Vector3(3, -0.3, 1), north) == null and ok          # taken
			_door = built.put(0, "doorway", Vector3(1, 0.05, 1.9), north) as Door
			ok = _door != null and ok
			ok = built.put(0, "wall", Vector3(3, 0.05, 1.9), north) != null and ok
			ok = built.put(0, "wall", Vector3(1, 0.05, 0.1), north) != null and ok
			ok = built.put(0, "wall", Vector3(3, 0.05, 0.1), north) != null and ok
			ok = built.put(0, "wall", Vector3(0.1, 0.05, 1), north) != null and ok
			ok = built.put(0, "wall", Vector3(3.9, 0.05, 1), north) != null and ok
			ok = built.put(0, "floor", Vector3(1, 0.0, 1), north) != null and ok
			ok = built.put(0, "floor", Vector3(3, 0.0, 1), north) != null and ok
			ok = built.put(0, "gable", Vector3(1, 2.0, 1.9), north, 0) != null and ok
			ok = built.put(0, "gable", Vector3(3, 2.0, 1.9), north, 2) != null and ok
			ok = built.put(0, "gable", Vector3(1, 2.0, 0.1), north, 2) != null and ok
			ok = built.put(0, "gable", Vector3(3, 2.0, 0.1), north, 0) != null and ok
			ok = built.put(0, "roof", Vector3(1, 2.0, 1), Vector3(1, 0, 0)) != null and ok
			ok = built.put(0, "roof", Vector3(3, 2.0, 1), Vector3(-1, 0, 0)) != null and ok
			ok = built.put(0, "steps", Vector3(1, -0.3, 3), north) != null and ok
			if not ok:
				_fail("a piece would not go where it was put")
			print("build: %d pieces standing" % (built._buildings[0]["slots"] as Dictionary).size())
			explorer.flying = true
			_look(explorer, _frame * Vector3(-2.5, 2.6, 7.0), _frame * Vector3(2.0, 1.4, 1.0))
			_wait = 30
		2:
			_shot("1_built")
			_look(explorer, _frame * Vector3(7.0, 3.4, -3.5), _frame * Vector3(2.0, 1.6, 1.0))
			_wait = 20
		3:
			_shot("2_built_behind")
			# On foot, up the steps and in.
			explorer.flying = false
			_look(explorer, _frame * Vector3(1.0, 1.9, 5.2), _frame * Vector3(1.0, 1.4, 0.0))
			_wait = 25
		4:
			if not _door.try_use(cam.global_position, -cam.global_basis.z):
				# (Too far to reach from the foot of the steps: opened by hand.)
				_door.try_use(_door.to_global(Vector3(0, 1.4, 2.0)), -_door.global_basis.z)
			if not _door.open:
				_fail("the door would not open")
			_wait = 30
		5:
			Input.action_press(&"wv_forward")
			_walked += 1
			var at: Vector3 = _frame.affine_inverse() * (explorer.global_position as Vector3)
			if at.z < 1.2:
				Input.action_release(&"wv_forward")
				print("build: walked up the steps and in (%d frames), standing %.2f m above the foundation" % [_walked, at.y])
			elif _walked > 160:
				Input.action_release(&"wv_forward")
				_fail("could not walk in, stopped at %s" % at)
				_shot("3_stuck")
				quit(1)
				return true
			else:
				return false
			_wait = 10
		6:
			_shot("3_inside")
			# Outside again, and the end wall taken down with the axe.
			_look(explorer, _frame * Vector3(6.2, 1.6, 1.0), _frame * Vector3(4.0, 1.2, 1.0))
			_wait = 15
		7:
			var had := bag.count_of("wall")
			if not built.strike(cam.global_position, -cam.global_basis.z):
				_fail("the axe met nothing built")
			elif bag.count_of("wall") != had + 1:
				_fail("the wall did not come back to the bag")
			else:
				print("build: a wall taken down and back in the bag")
			_wait = 15
		8:
			_shot("4_wall_down")
			print("build: ok" if not _failed else "build: FAILED")
			quit(1 if _failed else 0)
			return true
	_step += 1
	return false
