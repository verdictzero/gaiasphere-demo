extends SceneTree

# A LOOK ROUND, UNATTENDED: runs the project's own scene, waits for the loading
# cover to put the explorer down, and saves a few stills. It is how the project
# is checked on a machine with no one at it.
#
#   godot --path . --script res://tests/RENDER_tour.gd -- --out=/some/folder
#
# The stills: the arrival, the same spot from the air, the mere from its shore,
# half in the water, and the island from far off.

var _out := "user://tour"
var _scene: Node
var _explorer: CharacterBody3D
var _frames := 0
var _step := -1
var _wait := 0
var _fail := false
var _fast := false
var _quick := false
var _moon := false
var _nightfall := false
var _night_shot := false
var _torch_shot := false
var _moon_done := false
var _hour := -1.0
var _weather := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--nightfall":
			_nightfall = true	# after the first still, turn the clock to night and take it again
		elif a == "--moon":
			_moon = true		# stop after the shots toward the light
		elif a == "--quick":
			_quick = true		# only the first two stills
		elif a == "--fast":
			_fast = true		# a software renderer: wait a sixth as many frames
		elif a.begins_with("--hour="):
			_hour = float(a.substr(7))
		elif a.begins_with("--weather="):
			_weather = a.substr(10)
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = (load("res://scenes/SCENE_west_virginia.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_explorer = _scene.get_node("Explorer")
	var enviro := _scene.get_node_or_null("Enviro")
	if enviro != null:
		enviro.advance = false
		if _hour >= 0.0:
			enviro.hour = _hour
		if _weather != "":
			enviro.set_weather(_weather, 0.01)


func _process(_delta: float) -> bool:
	_frames += 1
	if _step < 0:
		if _explorer.arrived and not _scene.has_node("LoadingCover"):
			print("tour: arrived after %d frames at %s" % [_frames, _explorer.global_position])
			_step = 0
			_wait = _frames_for(90)
		elif _frames > 60 * 60 * 20:
			push_error("tour: the explorer never arrived")
			return true
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var cam := root.get_camera_3d()
	var water := _scene.get_node("RiverWater")
	var world := _scene.get_node("IslandWorld")
	match _step:
		0:
			var on_floor := _explorer.is_on_floor()
			print("tour: standing on the ground: %s (y %.2f, terrain %.2f)" % [on_floor,
					_explorer.global_position.y, world.height_at(_explorer.global_position)])
			if not on_floor:
				_fail = true
			_shot("0_arrival")
			if _nightfall:
				_scene.get_node("Enviro").hour = 23.5
				_nightfall = false
				_night_shot = true
				_wait = _frames_for(160)
				return false
			if _night_shot:
				_shot("0b_nightfall")
				# and with the flashlight on
				var torch := _explorer.find_child("Flashlight", true, false) as SpotLight3D
				if torch != null:
					torch.visible = true
				_night_shot = false
				_torch_shot = true
				_wait = _frames_for(60)
				return false
			if _torch_shot:
				_shot("0c_flashlight")
				print("tour: ok")
				quit(0)
				return true
			_explorer.flying = true
			_explorer.global_position += Vector3.UP * 120.0
			_look_at(Vector3.ZERO)
			_wait = _frames_for(60)
		1:
			_shot("1_from_the_air")
			if _quick:
				print("tour: ok")
				quit(0)
				return true
			# The mere's shore: walk in from the middle's islet until there is water.
			var at := Vector3.ZERO
			for i in 400:
				var p := Vector3(float(i) * 1.0 + 150.0, 0.0, 0.0)
				if not is_nan(float(water.world_level_at(p))):
					at = p
					break
			var level := float(water.world_level_at(at))
			print("tour: water at %s, level %.2f" % [at, level])
			if is_nan(level):
				_fail = true
			_explorer.global_position = Vector3(at.x - 6.0, maxf(world.height_at(at), level) + 3.0, 0.0)
			_look_at(Vector3(at.x + 60.0, level, 30.0))
			_wait = _frames_for(120)
		2:
			_shot("2_mere")
			var p := _explorer.global_position + Vector3(14.0, 0.0, 0.0)
			var level := float(water.world_level_at(p))
			_explorer.global_position = Vector3(p.x, level - 0.02 - cam.position.y, p.z)
			_look_at(_explorer.global_position + Vector3(40.0, cam.position.y, 10.0))
			_wait = _frames_for(60)
		3:
			_shot("3_waterline")
			_explorer.global_position = Vector3(1900.0, 650.0, 1200.0)
			_look_at(Vector3.ZERO)
			_wait = _frames_for(240)
		4:
			_shot("4_island")
			if _moon:
				# (falls through to the next step: the shot toward the light, which at night is the moon)
				pass
			# Into the low sun through the trees, from where the tour began: the shafts.
			var enviro := _scene.get_node_or_null("Enviro")
			_explorer.flying = false
			_explorer.call("arrive")
			if enviro != null:
				var sun: Vector3 = enviro.light_dir
				_look_at(_explorer.global_position + Vector3(sun.x, sun.y * 0.5 + 0.05, sun.z) * 100.0)
			_wait = _frames_for(240)
		5:
			_shot("5_into_the_sun")
			if _moon:
				# and once more, looking straight up the moon's beams
				var e2 := _scene.get_node("Enviro")
				_look_at(_explorer.global_position + (e2.light_dir as Vector3) * 100.0)
				_moon = false
				_moon_done = true
				_wait = _frames_for(120)
				return false
			if _moon_done:
				_shot("5b_at_the_moon")
				print("tour: ok")
				quit(0)
				return true
			# The island's edge from just off it: the rock set into the wall, and the cloud at its foot.
			var coast := 1600.0
			while coast > 200.0 and not world.is_land(Vector3(coast, 0.0, 0.0)):
				coast -= 10.0
			_explorer.flying = true
			# Looking at one of the rock masses set into the wall, from just off it.
			var rock := _scene.get_node("CliffDressing").get_child(0) as Node3D
			var out := Vector3(rock.global_position.x, 0.0, rock.global_position.z).normalized()
			_explorer.global_position = rock.global_position + out * 70.0 + out.cross(Vector3.UP) * 45.0 + Vector3(0, 8, 0)
			_look_at(rock.global_position + Vector3(0, -12, 0))
			print("tour: rock at %s, children %d, visible %s" % [rock.global_position, rock.get_child_count(), rock.is_visible_in_tree()])
			_wait = _frames_for(240)
		6:
			_shot("6_edge")
			# The sword in the stone, in its clearing on the islet.
			var stone := _scene.get_node_or_null("SwordStone/SwordInStone") as Node3D
			if stone == null:
				push_error("tour: no sword in the stone")
				_fail = true
			else:
				_explorer.flying = false
				# From the sunward side, so the lit faces are the ones in view.
				var sun_side: Vector3 = _scene.get_node("Enviro").light_dir
				sun_side.y = 0.0
				_explorer.global_position = stone.global_position + sun_side.normalized().rotated(Vector3.UP, 0.5) * 9.0 + Vector3(0, 0.4, 0)
				_look_at(stone.global_position + Vector3(0.0, 4.0, 0.0))
			_wait = _frames_for(240)
		7:
			_shot("7_sword")
			# The bridge, from the outer shore beside it.
			var bridge := _scene.get_node_or_null("Causeway")
			if bridge != null and bridge.start != Vector3.ZERO:
				var run: Vector3 = (bridge.finish - bridge.start).normalized()
				_explorer.flying = true
				# Side-on from over the water, sun behind the camera, to see the arches.
				var off: Vector3 = run.cross(Vector3.UP)
				if off.dot(_scene.get_node("Enviro").light_dir) < 0.0:
					off = -off
				# From the shore end, a little to one side and above, looking along it.
				_explorer.global_position = bridge.start - run * 10.0 + off * 9.0 + Vector3(0, 7.0, 0)
				_look_at(bridge.start.lerp(bridge.finish, 0.55))
			_wait = _frames_for(240)
		8:
			_shot("8_bridge")
			# Down into the shallows beside the causeway: the bed through the water.
			var cw := _scene.get_node_or_null("Causeway")
			if cw != null and cw.start != Vector3.ZERO:
				var along: Vector3 = (cw.finish - cw.start).normalized()
				var at: Vector3 = cw.start.lerp(cw.finish, 0.12)
				_explorer.flying = true
				_explorer.global_position = at + Vector3(0, 1.2, 0)
				_look_at(at + along.cross(Vector3.UP) * 9.0 + along * 5.0 + Vector3(0, -2.5, 0))
			_wait = _frames_for(240)
		9:
			_shot("9_shallows")
			# The sword in the hand, and the crescent it throws.
			var play := _scene.get_node_or_null("SwordPlay")
			var stone2 := _scene.get_node_or_null("SwordStone/SwordInStone") as Node3D
			if play == null or stone2 == null:
				_fail = true
			else:
				_explorer.flying = false
				_explorer.global_position = stone2.global_position + Vector3(2.4, 0.3, 0.0)
				_look_at(stone2.global_position + Vector3(-30.0, 3.0, 12.0))
				if not play._find_parts():
					push_error("tour: the sword could not be found in the stone")
					_fail = true
				else:
					play._take()
			_wait = _frames_for(160)
		10:
			_shot("10_sword_in_hand")
			var play2 := _scene.get_node_or_null("SwordPlay")
			if play2 != null and play2.held:
				play2.blast_speed = 1.5        # slow, so a still can catch it
				Input.action_press(&"wv_charge")
			else:
				_fail = true
			_wait = 45
		11:
			if Input.is_action_pressed(&"wv_charge"):
				# Charged: the motes gathering into the blade. Then let it go.
				_shot("10b_charging")
				Input.action_release(&"wv_charge")
				_wait = 16
				return false
			_shot("11_crescent")
			# Under the mere: the weed and the rocks on its bed.
			var flora := _scene.get_node_or_null("Flora")
			var mid: Vector3 = _scene.get_node("SwordStone/SwordInStone").global_position
			var best := Vector3.ZERO
			if flora != null:
				# The first good clump in the deep water: rings from the islet's shore out.
				var found := false
				for ring in 9:
					for i in 360:
						var ang := TAU * float(i) / 360.0
						var rr := 175.0 + 18.0 * float(ring)
						var p := Vector3(mid.x + cos(ang) * rr, 0.0, mid.z + sin(ang) * rr)
						var c: Vector3 = Flora.clump_at(p.x, p.z)
						if c.y > 5.0 and c.x < 2.0 and float(world.height_at(p)) < float(flora._mere_level) - 5.0:
							best = p
							found = true
							break
					if found:
						break
				if not found:
					push_error("tour: no seaweed clump found in deep water")
					_fail = true
			_explorer.flying = true
			# (The mere's level from Flora: the water's own query answers NAN off its mesh,
			# and a NAN position poisons the whole frame.)
			var level2 := float(flora._mere_level) if flora != null else 0.0
			var bed := float(world.height_at(best))
			_explorer.global_position = Vector3(best.x + 8.0, minf(level2 - 1.2, bed + 2.4) - cam.position.y, best.z + 4.0)
			_look_at(Vector3(best.x, bed + 1.5, best.z))
			print("tour: clump at %s, bed %.1f, level %.1f" % [best, bed, level2])
			_wait = _frames_for(240)
		12:
			_shot("12_seaweed")
			# A tree to fell: the first one found in the islet's wood.
			var flora2 := _scene.get_node_or_null("Flora")
			var mid2: Vector3 = _scene.get_node("SwordStone/SwordInStone").global_position
			var tree := {}
			for i in 720:
				var ang := TAU * float(i) / 90.0
				var rr := 26.0 + 0.12 * float(i)
				var p := Vector3(mid2.x + cos(ang) * rr, mid2.y + 3.0, mid2.z + sin(ang) * rr)
				tree = flora2.tree_on(p, Vector3.ZERO, 0.0, 5.0)
				if not tree.is_empty():
					break
			if tree.is_empty():
				push_error("tour: no tree found to fell")
				_fail = true
			else:
				var foot: Vector3 = tree["origin"]
				var back := (mid2 - foot)
				back.y = 0.0
				back = back.normalized()
				_explorer.flying = false
				_explorer.global_position = foot + back * 2.6 + Vector3(0, 0.6, 0)
				_look_at(foot + Vector3(0, 1.6, 0))
				print("tour: a tree %.1f m tall, trunk %.2f m, at %s" % [tree["height"], tree["radius"], foot])
			_wait = _frames_for(120)
		13:
			_shot("13_tree")
			var wood := _scene.get_node_or_null("Woodcutting")
			if wood == null or not bool(wood.strike(cam.global_position, -cam.global_basis.z, true)):
				push_error("tour: the swing met no tree")
				_fail = true
			_wait = 70
		14:
			_shot("14_logs")
			var wood2 := _scene.get_node_or_null("Woodcutting")
			var bag := _scene.get_node_or_null("Inventory")
			print("tour: %d logs lying, %d gathered" % [wood2._logs.size(), bag.count_of("log")])
			if wood2._logs.size() + bag.count_of("log") < 2:
				_fail = true
			bag.add("log", 7)
			bag.add("planks", 12)
			bag.add("sticks", 8)
			bag.set_open(true)
			bag.slots[Inventory.BAG] = ["log", 3]
			var made: Variant = bag.crafted()
			if made == null or made[0] != "planks" or int(made[1]) != 4:
				push_error("tour: a log in the grid did not make planks")
				_fail = true
			bag._take_result(true)
			if bag.count_of("planks") != 24:
				push_error("tour: crafting all gave %d planks, not 24" % bag.count_of("planks"))
				_fail = true
			bag.slots[Inventory.BAG] = ["log", 2]
			bag.slots[Inventory.BAG + 1] = ["sticks", 2]
			bag.slots[Inventory.BAG + 2] = ["log", 1]
			bag.slots[Inventory.BAG + 3] = ["sticks", 1]
			if bag.crafted() == null or bag.crafted()[0] != "campfire":
				push_error("tour: logs and sticks did not make a campfire")
				_fail = true
			_wait = 6
		15:
			_shot("15_bag")
			print("tour: %s" % ("FAILED" if _fail else "ok"))
			quit(1 if _fail else 0)
			return true
	_step += 1
	return false


func _frames_for(n: int) -> int:
	return maxi(14, n / 4) if _fast else n


func _look_at(target: Vector3) -> void:
	var cam := root.get_camera_3d()
	var from := _explorer.global_position + Vector3.UP * cam.position.y
	var d := target - from
	_explorer.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	cam.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	print("tour: ", path)
