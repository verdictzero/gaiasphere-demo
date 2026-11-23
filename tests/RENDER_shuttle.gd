extends SceneTree

# THE CRASHED SHUTTLE: what the player sees on coming to inside it, then the
# wreck from up the slope behind its door, from the side with its bubbles, and
# from over the water.
#
#   godot --path . --script res://tests/RENDER_shuttle.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0
var _failed := false


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
	print("shuttle: ", name)


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var ship: CrashedShuttle = _scene.get_node("CrashedShuttle")
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 11.0
			enviro.set_weather("clear", 0.0)
			if not ship.settled:
				print("shuttle: FAILED, it was never placed")
				quit(1)
				return true
			_step = 0
			_wait = 45
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var t := ship.global_transform
	var up := Vector3.UP
	match _step:
		0:
			# Where the player is, a second or two after coming to: still inside?
			var local: Vector3 = t.affine_inverse() * (explorer.global_position as Vector3)
			var water: float = _scene.get_node("RiverWater").call(&"world_level_at", explorer.global_position)
			print("shuttle: the player is at %s in the hull's own metres, %.1f m under the surface" % [local, water - explorer.global_position.y])
			if absf(local.x) > 1.4 or local.z < -5.5 or local.z > 3.2 or local.y < -1.3 or local.y > 1.2:
				print("shuttle: FAILED, the player is not in the cabin")
				_failed = true
			_shot("0_coming_to")
			explorer.flying = true
			# Up the slope from the door, looking back down at it.
			_look(explorer, t * Vector3(1.5, 2.2, -11.0), t * Vector3(0, 0.2, -3.0))
			_wait = 40
		1:
			_shot("1_door_from_uphill")
			_look(explorer, t * Vector3(11.0, 2.5, 3.0) + up * 2.0, t * Vector3(0, 0.5, 0) + up * 2.5)
			_wait = 40
		2:
			_shot("2_side_and_bubbles")
			_look(explorer, t * Vector3(0, 0.3, -1.0), t * Vector3(0, 0.0, 4.0))
			_wait = 30
		3:
			_shot("3_cabin_to_the_nose")
			var above: Vector3 = t.origin
			var water: float = _scene.get_node("RiverWater").call(&"world_level_at", above)
			_look(explorer, Vector3(above.x + 14.0, water + 7.0, above.z + 14.0), Vector3(above.x, water, above.z))
			_wait = 40
		4:
			_shot("4_from_over_the_water")
			# From the shore, down the gouge it ploughed, to where it lies.
			var water2: float = _scene.get_node("RiverWater").call(&"world_level_at", t.origin)
			var back: Vector3 = -t.basis.z.normalized()
			back.y = 0.0
			back = back.normalized()
			_look(explorer, Vector3(t.origin.x, water2 + 9.0, t.origin.z) + back * 50.0, Vector3(t.origin.x, water2 - 4.0, t.origin.z) + back * 8.0)
			_wait = 40
		5:
			_shot("5_down_the_gouge")
			# And the divot and its rock piles, from in the water above them.
			_look(explorer, t.origin + Vector3(13.0, 9.0, 10.0), t.origin + Vector3(0, -1.0, 0))
			_wait = 40
		6:
			_shot("6_divot_and_rocks")
			print("shuttle: ok" if not _failed else "shuttle: FAILED")
			quit(1 if _failed else 0)
			return true
	_step += 1
	return false
