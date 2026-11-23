extends SceneTree

# IS EVERY PLANT AT A LEVEL THAT WILL DRAW IT, however far the camera has gone
# since the plants were last sorted into levels? Ten thousand plants are sorted
# for a camera at one place (Flora._near_sort), the camera is then moved on, and
# every plant in range is looked for at every level the shader would show any of
# it at from there. A plant missing from one is a plant that has vanished.
#
#   godot --headless --path . --script res://tests/CHECK_lod_cover.gd

func _initialize() -> void:
	var flora := Flora.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var buf := PackedFloat32Array()
	for i in 10000:
		var p := Vector3(rng.randf_range(-200, 200), rng.randf_range(-2, 2), rng.randf_range(-200, 200))
		buf.append_array([1, 0, 0, p.x, 0, 1, 0, p.y, 0, 0, 1, p.z])
	var dists := [9.0, 18.0, 32.0, 55.0, 90.0]
	var radius := 140.0
	var los := PackedFloat32Array()
	var his := PackedFloat32Array()
	for lod in dists.size() + 1:
		los.append(0.0 if lod == 0 else float(dists[lod - 1]))
		his.append(radius if lod == dists.size() else float(dists[lod]))
	var ok := true
	for moved in [0.5, 2.0, 5.0, 9.0]:
		var line := "moved %.1f m:" % moved
		for slack in [0.0, moved + 0.5]:
			flora._near_sort(0, [[buf]], Vector3.ZERO, los, his, Flora.STRIDE, 1, slack)
			var packed: Array = flora._near_done[0]["packed"]
			var at := Vector3(moved, 0, 0)
			var missing := 0
			var held := 0
			for lod in los.size():
				var level: PackedFloat32Array = packed[0][lod]
				held += level.size() / Flora.STRIDE
				var there := {}
				for i in range(0, level.size(), Flora.STRIDE):
					there[Vector3(level[i + 3], level[i + 7], level[i + 11])] = true
				for i in range(0, buf.size(), Flora.STRIDE):
					var p := Vector3(buf[i + 3], buf[i + 7], buf[i + 11])
					var d := p.distance_to(at)
					# Shown at this level at all: inside where it fades in and out.
					var shown := d < his[lod] * (1.0 + Flora.LOD_BAND) and (lod == 0 or d > los[lod] * (1.0 - Flora.LOD_BAND))
					if shown and not there.has(p):
						missing += 1
			line += "   slack %.1f: %d missing (%d held)" % [slack, missing, held]
			if slack > 0.0 and missing > 0:
				ok = false
		print(line)
	print("lod cover: ok" if ok else "lod cover: FAILED")
	flora.free()
	quit(0 if ok else 1)
