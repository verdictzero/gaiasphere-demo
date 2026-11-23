extends SceneTree

# The mere's bed along a few bearings: how deep, and how steep, going in from
# the outer shore. For choosing where things can lie on it.
#
#   godot --headless --path . --script res://tests/CHECK_mere_bed.gd

func _initialize() -> void:
	var field: IslandField = load("res://data/ISLANDFIELD_forest_003_r2.tres")
	field.prepare()
	var isl: Variant = field.island_in_cell(field.hub_cell())
	var flows: Variant = field.flows_for(isl)
	var level := float(isl.base_y) + float(flows.lagoon_level())
	var middle: Vector2 = flows.lagoon_center()
	print("mere: level %.2f, middle %s, base %.2f" % [level, middle, isl.base_y])
	for th_deg in [0, 90, 180, 270]:
		var th := deg_to_rad(float(th_deg))
		var out := Vector2(cos(th), sin(th))
		var shores: Vector2 = flows.lagoon_shores(th)
		var line := "bearing %d shores %.0f..%.0f:" % [th_deg, shores.x, shores.y]
		for step in 16:
			var r := shores.y + 4.0 - float(step) * 3.0
			var p := middle + out * r
			var h := field.height_at(p.x, p.y, 1e9)
			var g := (field.height_at(p.x + out.x * 2.0, p.y + out.y * 2.0, h) - field.height_at(p.x - out.x * 2.0, p.y - out.y * 2.0, h)) / 4.0
			line += "  %.0f:%.1f/%.0f" % [shores.y - r, level - h, rad_to_deg(atan(absf(g)))]
		print(line)
	quit(0)
