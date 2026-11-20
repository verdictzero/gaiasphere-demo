extends SceneTree

# CUTTING A TREE DOWN: the axe in the hand, the notch after two bites, the tree
# on its way over, and the logs where it landed.
#
#   godot --path . --script res://tests/RENDER_chop.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0
var _fell_at := 0
var _failed := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("chop: ", name)


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var flora: Flora = _scene.get_node("Flora")
	var wood: Woodcutting = _scene.get_node("Woodcutting")
	var play: SwordPlay = _scene.get_node("SwordPlay")
	var cam := root.get_camera_3d()
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 15.0
			enviro.set_weather("clear", 0.0)
			# The nearest tree of some size, and a place to stand at its foot.
			var here: Vector3 = explorer.global_position
			var tree := {}
			for i in 400:
				var ang := float(i) * 0.7
				var p := here + Vector3(cos(ang), 0.0, sin(ang)) * (6.0 + 0.2 * float(i)) + Vector3(0, 1.5, 0)
				var t := flora.tree_on(p, Vector3.ZERO, 0.0, 4.0)
				if not t.is_empty() and float(t["radius"]) > 0.2:
					tree = t
					break
			if tree.is_empty():
				push_error("chop: no tree found")
				quit(1)
				return true
			var foot: Vector3 = tree["origin"]
			var back := (here - foot)
			back.y = 0.0
			back = back.normalized()
			explorer.flying = false
			explorer.global_position = foot + back * (float(tree["radius"]) + 2.0) + Vector3(0, 0.4, 0)
			explorer.look_at(Vector3(foot.x, explorer.global_position.y, foot.z))
			print("chop: a tree %.1f m tall, trunk %.2f m, %d bites" % [tree["height"], tree["radius"],
					Woodcutting.bites_for(float(tree["radius"]))])
			_step = 0
			_wait = 60
		return false
	_wait -= 1
	if _wait > 0:
		return false
	match _step:
		0:
			if play.tool != "axe":
				push_error("chop: the hand holds '%s', not the axe" % play.tool)
				_failed = true
			_shot("0_axe_in_hand")
			for i in 2:
				if not wood.strike(cam.global_position, -cam.global_basis.z):
					push_error("chop: the swing met no tree")
					_failed = true
			_wait = 20
		1:
			_shot("1_notch")
			for i in 8:
				if wood._falls.is_empty():
					wood.strike(cam.global_position, -cam.global_basis.z)
			if wood._falls.is_empty():
				push_error("chop: the tree did not go over")
				_failed = true
			_fell_at = Time.get_ticks_msec()
			_wait = 2
		2:
			# Part way down.
			if not wood._falls.is_empty() and float(wood._falls[0]["angle"]) < 0.7:
				return false
			_shot("2_falling")
		3:
			if not wood._falls.is_empty():
				return false
			print("chop: down in %.1f s, %d logs" % [(Time.get_ticks_msec() - _fell_at) / 1000.0, wood._logs.size()])
			if wood._logs.size() < 3:
				_failed = true
			_wait = 40
		4:
			_shot("3_logs")
			print("chop: %s" % ("FAILED" if _failed else "ok"))
			quit(1 if _failed else 0)
			return true
	_step += 1
	return false
