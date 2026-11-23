extends SceneTree

# Can a piece of cow be hit again? A cow is cut, the halves are held where they
# are, and a ray is sent at each: it must land on that piece, and cut it.
#
#   godot --headless --path . --script res://tests/CHECK_slice_again.gd

var _frames := 0
var _slicing: CowSlicing


func _physics_process(_dt: float) -> bool:
	_frames += 1
	if _frames == 2:
		_slicing = CowSlicing.new()
		root.add_child(_slicing)
		var model: Node3D = (load(CowHerds.MODEL) as PackedScene).instantiate()
		var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
		var whole := _slicing._whole({"arrays": mi.mesh.surface_get_arrays(0), "material": null, "transform": Transform3D()})
		var halves := _slicing._cut(whole, Plane(Vector3(0.2, 1, 0.1).normalized(), 0.0))
		(whole["body"] as Node).free()
		model.free()
		for side in 2:
			var made := _slicing._body(halves[side], Transform3D(Basis(), Vector3(0, 3.0 * side, 0)), 1, 1, null)
			(made["body"] as RigidBody3D).freeze = true
			_slicing._pieces.append(made)
	if _frames < 6:
		return false
	var ok := true
	for side in 2:
		var piece: Dictionary = _slicing._pieces[0]
		var body: RigidBody3D = piece["body"]
		var at := body.global_position
		var space := root.get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, 0, 3.0), at))
		var shape := (body.get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D
		print("again: piece %d, %d corners in its shape, ray %s" % [side, shape.points.size(),
				"lands on it" if (not hit.is_empty() and hit["collider"] == body) else ("lands on something else" if not hit.is_empty() else "MEETS NOTHING")])
		var before := _slicing._pieces.size()
		var cut := _slicing.slice(at + Vector3(0, 0, 3.0), Vector3(0, 0, -1), Vector3(1, 0.3, 0))
		print("again:   slice %s, %d -> %d pieces" % [cut, before, _slicing._pieces.size()])
		ok = ok and cut and _slicing._pieces.size() == before + 1
	Engine.time_scale = 1.0
	print("again: ok" if ok else "again: FAILED")
	quit(0 if ok else 1)
	return true
