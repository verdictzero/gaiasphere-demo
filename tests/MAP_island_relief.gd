extends SceneTree

# THE ISLAND FROM DIRECTLY ABOVE, as numbers: the hub's ground sampled on a grid
# and written as a shaded relief map (renders/map_relief.png: hillshade, tinted by
# height, cliffs red, water blue) and a histogram of heights and slopes. Fast (no
# renderer), for judging the shape of the land.
#
#   godot --headless --path . --script res://tests/MAP_island_relief.gd -- [step=5]

const FIELD := "res://data/ISLANDFIELD_forest_003_r2.tres"


func _initialize() -> void:
	var step := 5.0
	for a in OS.get_cmdline_user_args():
		if a.is_valid_float():
			step = float(a)
	var field: IslandField = (load(FIELD) as IslandField).duplicate(true)
	field.prepare()
	var isl: IslandField.Island = field.island_in_cell(field.hub_cell())
	var flows: FlowTerrain = field.flows_for(isl)
	var reach := isl.radius * 1.2
	var n := int(reach * 2.0 / step)
	var h := PackedFloat32Array()
	h.resize(n * n)
	var lo := 1e9
	var hi := -1e9
	var t0 := Time.get_ticks_msec()
	for j in n:
		for i in n:
			var x := isl.center.x - reach + (float(i) + 0.5) * step
			var z := isl.center.y - reach + (float(j) + 0.5) * step
			var y := field.height_at(x, z, -200.0)
			h[j * n + i] = y
			if y > -150.0:
				lo = minf(lo, y)
				hi = maxf(hi, y)
	print("map: %dx%d samples at %.0f m in %.1f s; ground %.0f .. %.0f m" % [n, n, step, (Time.get_ticks_msec() - t0) / 1000.0, lo, hi])
	var water := flows.lagoon_level() + isl.base_y if flows != null and flows.has_lagoon() else -1e9
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var steep := 0
	var flat := 0
	var land := 0
	for j in n:
		for i in n:
			var y := h[j * n + i]
			if y < -150.0:
				img.set_pixel(i, j, Color(0.1, 0.12, 0.16))
				continue
			var yx := h[j * n + mini(i + 1, n - 1)] - h[j * n + maxi(i - 1, 0)]
			var yz := h[mini(j + 1, n - 1) * n + i] - h[maxi(j - 1, 0) * n + i]
			var grad := Vector2(yx, yz) / (2.0 * step)
			var slope := grad.length()
			land += 1
			if slope > 1.0:
				steep += 1
			if slope < 0.08:
				flat += 1
			var nrm := Vector3(-grad.x, 1.0, -grad.y).normalized()
			var shade := clampf(nrm.dot(Vector3(-0.5, 0.75, -0.45).normalized()), 0.0, 1.0)
			var tint := Color(0.35, 0.55, 0.25).lerp(Color(0.85, 0.75, 0.55), clampf((y - lo) / maxf(hi - lo, 1.0), 0.0, 1.0))
			if slope > 0.9:
				tint = Color(0.75, 0.3, 0.25)
			if y < water:
				tint = Color(0.2, 0.35, 0.6)
			img.set_pixel(i, j, tint * (0.35 + 0.75 * shade))
	img.save_png("res://renders/map_relief.png")
	print("map: of the land, %.0f%% flat (slope < 0.08), %.0f%% cliff (slope > 1)" % [100.0 * flat / land, 100.0 * steep / land])
	quit(0)
