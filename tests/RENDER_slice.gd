extends SceneTree

# CUTTING A COW UP: stood at a cow, one swing, then three more across the
# pieces while they are still in the air, and the beef gathered.
#
#   godot --path . --script res://tests/RENDER_slice.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0
var _failed := false
var _spot := Vector3.ZERO


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _look(explorer: Node3D, from: Vector3, target: Vector3) -> void:
	var cam := root.get_camera_3d()
	explorer.global_position = from - Vector3.UP * cam.position.y
	var d := target - from
	explorer.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	cam.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("slice: ", name)


func _fail(what: String) -> void:
	print("slice: FAILED, ", what)
	_failed = true


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var cows: CowHerds = _scene.get_node("CowHerds")
	var slicing: CowSlicing = _scene.get_node("CowSlicing")
	var bag: Inventory = _scene.get_node("Inventory")
	var cam := root.get_camera_3d()
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover") and not cows._herds.is_empty():
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 10.0
			enviro.set_weather("clear", 0.0)
			# The katana in hand.
			for i in Inventory.HOTBAR:
				if bag.slots[i] != null and String(bag.slots[i][0]) == "katana":
					bag.selected = i
			# The cows are held still for this: they would be off as soon as anyone came near.
			cows.set_process(false)
			var cow: Dictionary = cows._herds[0]["cows"][0]
			_spot = (cow["node"] as Node3D).global_position
			explorer.flying = true
			_look(explorer, _spot + Vector3(2.6, 0.5, 1.2), _spot)
			_step = 0
			_wait = 40
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var dir := -cam.global_basis.z
	match _step:
		0:
			var play: SwordPlay = _scene.get_node("SwordPlay")
			if play.tool != "katana":
				_fail("the hand holds '%s', not the katana" % play.tool)
			_shot("0_the_cow")
			var before := (cows._herds[0]["cows"] as Array).size()
			if not slicing.slice(cam.global_position, dir, cam.global_basis * Vector3(1, 0.35, 0)):
				_fail("the swing met no cow")
			if (cows._herds[0]["cows"] as Array).size() != before - 1:
				_fail("the cow is still in its herd")
			print("slice: one cut, %d pieces" % slicing._pieces.size())
			_wait = 3
		1:
			_shot("1_in_two")
			# Three more, each across whatever is in front of the blade now.
			var made := 0
			for tilt in [Vector3(0.2, 1, 0), Vector3(1, -0.6, 0), Vector3(1, 0.9, 0)]:
				if slicing.slice(cam.global_position, dir, cam.global_basis * tilt):
					made += 1
			print("slice: %d more cuts landed, %d pieces" % [made, slicing._pieces.size()])
			if slicing._pieces.size() < 3:
				_fail("it did not come apart further")
			_wait = 4
		2:
			_shot("2_in_pieces")
			_wait = 40
		3:
			_shot("3_on_the_ground")
			var faces := 0
			for piece in slicing._pieces:
				faces += (piece["meat"][0] as PackedVector3Array).size() / 3
			print("slice: %d triangles of meat showing on %d pieces; time runs at %.2f" % [faces, slicing._pieces.size(), Engine.time_scale])
			if faces == 0:
				_fail("no meat on any piece")
			explorer.flying = false
			explorer.global_position = _spot + Vector3(0, 0.3, 0)
			_wait = 60
		4:
			var got := bag.count_of("beef")
			print("slice: %d beef in the bag, %d pieces left lying" % [got, slicing._pieces.size()])
			if got < 1:
				_fail("no beef was gathered")
			print("slice: ok" if not _failed else "slice: FAILED")
			quit(1 if _failed else 0)
			return true
	_step += 1
	return false
