extends SceneTree

# The face a cut leaves on a cow: is it one flat convex piece, the size of the
# cow's own section there, on each half?
#
#   godot --headless --path . --script res://tests/CHECK_slice_face.gd

var _frames := 0


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	var slicing := CowSlicing.new()
	root.add_child(slicing)
	var model: Node3D = (load(CowHerds.MODEL) as PackedScene).instantiate()
	root.add_child(model)
	var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	print("face: mesh %s, skin %s, its node at %s scale %s" % [mi.mesh.get_aabb(), mi.skin != null, mi.global_transform.origin, mi.global_transform.basis.get_scale()])
	var piece := slicing._whole({"arrays": mi.mesh.surface_get_arrays(0), "material": null, "transform": mi.global_transform})
	var ok := true
	for plane in [Plane(Vector3(0, 1, 0), 0.1), Plane(Vector3(0.3, 1, 0.2).normalized(), 0.0), Plane(Vector3(1, 0.4, 0).normalized(), 0.2)]:
		var halves := slicing._cut(piece, plane)
		if halves.is_empty():
			print("face: no cut for ", plane)
			ok = false
			continue
		for side in 2:
			var meat: PackedVector3Array = halves[side]["meat"][0]
			var skin: PackedVector3Array = halves[side]["skin"][0]
			var off := 0.0
			var area := 0.0
			var box := AABB(meat[0], Vector3.ZERO)
			for i in range(0, meat.size(), 3):
				area += (meat[i + 1] - meat[i]).cross(meat[i + 2] - meat[i]).length() * 0.5
				for k in 3:
					off = maxf(off, absf(plane.distance_to(meat[i + k])))
					box = box.expand(meat[i + k])
			var hide := AABB(skin[0], Vector3.ZERO)
			for p in skin:
				hide = hide.expand(p)
			print("face: side %d, %d triangles of meat, area %.2f m2, %.4f m off the plane at most, spans %s; its hide spans %s" % [
					side, meat.size() / 3, area, off, box.size, hide.size])
			ok = ok and off < 0.01 and area > 1.0
	print("face: ok" if ok else "face: FAILED")
	quit(0 if ok else 1)
	return true
