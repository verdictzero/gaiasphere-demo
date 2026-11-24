extends SceneTree

# BREAKING A BOULDER: the pickaxe in the hand, a blow landing, the boulder gone
# and its stones lying where it sat, and the stones in the bag.
#
#   godot --path . --script res://tests/RENDER_mine.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _tries := 0
var _wait := 0
var _failed := false
var _rock := Vector3.ZERO
var _span := 1.0
var _stood := Vector3.ZERO


func _look(explorer: Node3D, target: Vector3) -> void:
	var cam := root.get_camera_3d()
	var from := explorer.global_position + Vector3.UP * cam.position.y
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
	print("mine: ", name)


func _fail(what: String) -> void:
	push_error("mine: " + what)
	print("mine: FAILED, ", what)
	_failed = true


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var flora: Flora = _scene.get_node("Flora")
	var mine: Mining = _scene.get_node("Mining")
	var play: SwordPlay = _scene.get_node("SwordPlay")
	var bag: Inventory = _scene.get_node("Inventory")
	var cam := root.get_camera_3d()
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 9.5
			enviro.set_weather("clear", 0.0)
			# The nearest boulder about a metre across that is not under water.
			var here: Vector3 = explorer.global_position
			var layer := flora._rock_layer()
			var best := 1e9
			for key in layer["cache"]:
				var bufs: Array = layer["cache"][key]
				for k in bufs.size():
					var buf: PackedFloat32Array = bufs[k]
					for i in range(0, buf.size(), Flora.STRIDE):
						var size := Vector3(buf[i + 1], buf[i + 5], buf[i + 9]).length()
						var p := Vector3(buf[i + 3], buf[i + 7], buf[i + 11])
						if size < 0.7 or size > 1.3 or p.y < 1.0 or p.distance_to(here) > best:
							continue
						best = p.distance_to(here)
						_rock = p
						_span = size
			if best > 1e8:
				_fail("no boulder found")
				quit(1)
				return true
			var back := here - _rock
			back.y = 0.0
			back = back.normalized()
			explorer.flying = false
			_stood = _rock + back * 2.6 + Vector3(0, 1.2, 0)
			explorer.global_position = _stood
			print("mine: a boulder %.0f m off, scale %.2f" % [best, _span])
			_step = 0
			_wait = 50
		return false
	_wait -= 1
	if _wait > 0:
		return false
	match _step:
		0:
			# The pickaxe is the second thing in the hotbar.
			for i in Inventory.HOTBAR:
				if bag.slots[i] != null and String(bag.slots[i][0]) == "pickaxe":
					bag.selected = i
			_look(explorer, _rock + Vector3(0, 0.25, 0))
			_wait = 30
		1:
			# (Under --fixed-fps frames outrun the clock: wait on the boulders'
			# collision itself, which is made in its own time.)
			if not mine.aimed(cam.global_position, -cam.global_basis.z) and _tries < 400:
				_tries += 1
				return false
			if play.tool != "pickaxe":
				_fail("the hand holds '%s', not the pickaxe" % play.tool)
			_shot("0_pickaxe_in_hand")
			var wood: Woodcutting = _scene.get_node("Woodcutting")
			if wood.strike(cam.global_position, -cam.global_basis.z):
				_fail("there is a tree in the way")
			if not mine.aimed(cam.global_position, -cam.global_basis.z):
				_fail("the swing would meet no boulder")
			var rock := flora.rock_on(cam.global_position, -cam.global_basis.z, mine.reach, mine._skip())
			print("mine: %.2f m across, %d blows, %d stones" % [rock.get("span", 0.0), Mining.blows_for(float(rock.get("span", 0.0))),
					Mining.yield_of(float(rock.get("span", 0.0)))])
			mine.strike(cam.global_position, -cam.global_basis.z)
			# And one swung by the hand: stopped on the rock, sparks, thrown back.
			# (Run with --fixed-fps 30: the blow lands 0.29 s in, the picture is
			# taken two frames after.)
			play._cut(false)
			_wait = 11
		2:
			_shot("1_blow")
			var n := 0
			while mine.strike(cam.global_position, -cam.global_basis.z) and n < 40:
				n += 1
			print("mine: %d more blows before nothing was left to hit" % n)
			if mine._stones.size() < 2:
				_fail("no stones came of it")
			# Stood back a little so they are not gathered before the picture.
			explorer.global_position = _stood + (_stood - _rock).normalized() * 1.2
			_look(explorer, _rock + Vector3(0, 0.1, 0))
			_wait = 14
		3:
			_shot("2_rubble")
			print("mine: %d stones lying" % mine._stones.size())
			explorer.global_position = _rock + Vector3(0, 1.0, 0)
			_wait = 30
		4:
			var got := bag.count_of("stone")
			print("mine: %d stones in the bag" % got)
			if got < 1:
				_fail("no stone reached the bag")
			_shot("3_gathered")
			bag.set_open(true)
			_wait = 6
		5:
			_shot("4_bag")
			print("mine: ok" if not _failed else "mine: FAILED")
			quit(1 if _failed else 0)
			return true
	_step += 1
	return false
