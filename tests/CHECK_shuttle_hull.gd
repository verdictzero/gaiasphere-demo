extends SceneTree

# Is the shuttle's hull solid from the inside? Rays from the aisle, up, down and
# to each side, against the same shapes SCRIPT_crashed_shuttle.gd makes.
#
#   godot --headless --path . --script res://tests/CHECK_shuttle_hull.gd

var _frames := 0
var _ship: Node3D


func _build() -> void:
	_ship = Node3D.new()
	root.add_child(_ship)
	_ship.transform = Transform3D(Basis(Vector3(1, 0, 0), 0.3).scaled(Vector3.ONE * 1.25), Vector3(5, -3, 2))
	var model: Node3D = (load(CrashedShuttle.MODEL) as PackedScene).instantiate()
	_ship.add_child(model)
	CrashedShuttle.make_solid(_ship, model)


func _physics_process(_dt: float) -> bool:
	_frames += 1
	if _frames == 2:
		_build()          # (not in _initialize: nothing is in the tree yet there)
	if _frames < 6:
		return false
	var space := root.get_world_3d().direct_space_state
	var from := _ship.global_transform * CrashedShuttle.STAND + _ship.global_basis.y.normalized() * 1.0
	var ok := true
	for way in [["up", Vector3.UP], ["down", Vector3.DOWN], ["left", Vector3.LEFT], ["right", Vector3.RIGHT]]:
		var dir: Vector3 = (_ship.global_basis * (way[1] as Vector3)).normalized()
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 6.0))
		print("hull: %s -> %s" % [way[0], "%.2f m" % from.distance_to(hit["position"]) if not hit.is_empty() else "NOTHING"])
		ok = ok and not hit.is_empty()
	print("hull: ok" if ok else "hull: FAILED")
	quit(0 if ok else 1)
	return true
