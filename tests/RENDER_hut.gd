extends SceneTree

# THE HUT BY THE START: seen from where the player arrives, then from in front of
# its door shut, the door worked with the use button, and from the doorway.
#
#   godot --path . --script res://tests/RENDER_hut.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _walked := 0
var _step := -1
var _wait := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _look(explorer: Node3D, from: Vector3, target: Vector3) -> void:
	var cam := root.get_camera_3d()
	explorer.global_position = from - Vector3.UP * cam.position.y
	explorer.velocity = Vector3.ZERO
	var d := target - from
	explorer.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	cam.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var hut: PlankHut = _scene.get_node("PlankHut")
	var cam := root.get_camera_3d()
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover") and hut._placed:
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 10.5
			enviro.set_weather("clear", 0.0)
			explorer.flying = true
			var start: Vector3 = explorer.global_position
			print("hut: stands %.1f m from the start, floor %.2f m %s the start's ground" % [
					Vector2(hut.global_position.x - start.x, hut.global_position.z - start.z).length(),
					absf(hut.global_position.y - start.y), "above" if hut.global_position.y > start.y else "below"])
			_look(explorer, start + Vector3(0, 1.7, 0), hut.global_position + Vector3(0, 1.5, 0))
			_step = 0
			_wait = 40
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var door: Door = null
	for c in hut.get_children():
		if c is Door:
			door = c
	var front := door.to_global(Vector3(0.3, 1.6, 2.5))
	match _step:
		0:
			root.get_texture().get_image().save_png(_out.path_join("hut_0_from_start.png"))
			_look(explorer, front, door.to_global(Vector3(0, 1.1, 0)))
			_wait = 30
		1:
			root.get_texture().get_image().save_png(_out.path_join("hut_1_door_shut.png"))
			Input.action_press(&"wv_attack")
			_wait = 3
		2:
			Input.action_release(&"wv_attack")
			print("hut: the use button %s the door" % ("opened" if door.open else "DID NOT OPEN"))
			if not door.open:
				quit(1)
				return true
			_wait = 30
		3:
			root.get_texture().get_image().save_png(_out.path_join("hut_2_door_open.png"))
			_look(explorer, door.to_global(Vector3(0.0, 1.6, 0.9)), door.to_global(Vector3(1.6, 1.3, -1.6)))
			_wait = 20
		4:
			root.get_texture().get_image().save_png(_out.path_join("hut_3_inside.png"))
			# Now on foot: stood outside the door, and walked at it.
			explorer.flying = false
			_look(explorer, door.to_global(Vector3(0.0, 1.9, 2.4)), door.to_global(Vector3(0.0, 1.9, -2.0)))
			_wait = 25
		5:
			Input.action_press(&"wv_forward")
			_walked += 1
			var at := door.to_local(explorer.global_position)
			if at.z < -0.45:
				Input.action_release(&"wv_forward")
				print("hut: walked in through the door (%d frames), standing %.2f m above the hut's foot" % [_walked, at.y])
			elif _walked > 150:
				Input.action_release(&"wv_forward")
				print("hut: COULD NOT WALK IN, stopped at ", at)
				root.get_texture().get_image().save_png(_out.path_join("hut_4_stuck.png"))
				quit(1)
				return true
			else:
				return false
			_wait = 10
		6:
			root.get_texture().get_image().save_png(_out.path_join("hut_4_walked_in.png"))
			_look(explorer, door.to_global(Vector3(2.6, 2.3, 3.2)), door.to_global(Vector3(0.6, 1.2, 0.0)))
			_wait = 20
		7:
			root.get_texture().get_image().save_png(_out.path_join("hut_5_corner.png"))
			print("hut: ok")
			quit(0)
			return true
	_step += 1
	return false
