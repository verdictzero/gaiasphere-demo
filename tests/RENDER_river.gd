extends SceneTree

# THE RIVERS ON THEIR HILLS: the fastest reach on the island seen from above its
# head looking down it, then where a river runs out into still water.
#
#   godot --path . --script res://tests/RENDER_river.gd -- --out=/some/folder

var _scene: Node
var _out := "user://"
var _step := -1
var _wait := 0
var _mouth := Vector3.ZERO
var _mouth_from := Vector3.ZERO


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _look(explorer: Node3D, from: Vector3, target: Vector3) -> void:
	var cam := root.get_camera_3d()
	explorer.flying = true
	explorer.global_position = from - Vector3.UP * cam.position.y
	var d := target - from
	explorer.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	cam.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _process(_dt: float) -> bool:
	var explorer := _scene.get_node("Explorer")
	var water := _scene.get_node("RiverWater")
	if _step < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover"):
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 10.5
			enviro.set_weather("clear", 0.0)
			# The fastest water on the island, and the slowest end of a moving river.
			var best := -1.0
			var at := Vector3.ZERO
			var down := Vector3.FORWARD
			var report := ""
			for entry in water.surfaces():
				var r: Variant = entry["river"]
				var steep: PackedFloat32Array = entry["steep"]
				var levels: PackedFloat32Array = entry["levels"]
				var top := 0.0
				for i in steep.size():
					top = maxf(top, steep[i])
					if steep[i] > best and i + 4 < steep.size() and i > 4:
						best = steep[i]
						at = Vector3(r.points[i].x, levels[i], r.points[i].y)
						var ahead: Vector2 = r.points[i + 4] - r.points[i]
						down = Vector3(ahead.x, 0.0, ahead.y).normalized()
				report += "%.2f " % top
				var n: int = steep.size()
				if r.moving and n > 12 and steep[n - 1] < 0.02 and _mouth == Vector3.ZERO:
					_mouth = Vector3(r.points[n - 1].x, levels[n - 1], r.points[n - 1].y)
					var back: Vector2 = r.points[n - 12] - r.points[n - 1]
					_mouth_from = _mouth + Vector3(back.x, 0.0, back.y).normalized() * 26.0 + Vector3(0, 9, 0)
			print("river: fastest water on each river %s; the fastest of all %.2f at %s" % [report, best, at])
			_look(explorer, at - down * 16.0 + Vector3(0, 7.5, 0), at + down * 10.0)
			_step = 0
			_wait = 40
		return false
	_wait -= 1
	if _wait > 0:
		return false
	match _step:
		0:
			root.get_texture().get_image().save_png(_out.path_join("river_0_rapid.png"))
			_wait = 25
		1:
			root.get_texture().get_image().save_png(_out.path_join("river_1_rapid_later.png"))
			if _mouth == Vector3.ZERO:
				print("river: no river ends in still water")
				quit(0)
				return true
			_look(explorer, _mouth_from, _mouth)
			_wait = 40
		2:
			root.get_texture().get_image().save_png(_out.path_join("river_2_mouth.png"))
			print("river: ok")
			quit(0)
			return true
	_step += 1
	return false
