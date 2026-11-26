extends SceneTree

# THE CRASH IN SECTION: the ground's height along the shuttle's path, from out in
# the mere, over the wreck, up the shore and across the meadow, as CSV on the
# output (tools/plot_crash_section.py draws it).
#   godot --headless --path . --script res://tests/DUMP_crash_section.gd

func _initialize() -> void:
	var field: IslandField = load("res://data/ISLANDFIELD_forest_003_r2.tres")
	field.prepare()
	var isl: IslandField.Island = field.island_in_cell(field.hub_cell())
	var flows: FlowTerrain = field.flows_for(isl)
	var site := flows.crash_site()
	var level := float(isl.base_y) + float(flows.lagoon_level())
	print("META level=%f bowl=%f gouge=%f meadow_up=%f meadow_r=%f meadow_ramp=%f crash_in=%f" % [level, FlowTerrain.CRASH_BOWL,
			FlowTerrain.CRASH_GOUGE, FlowTerrain.MEADOW_UP, FlowTerrain.MEADOW_R, FlowTerrain.MEADOW_RAMP, FlowTerrain.CRASH_IN])
	var side := Vector2(-site[1].y, site[1].x)
	var d := -70.0
	while d <= 330.0:
		# (The skid wanders: its own middle, and the ground 25 m to one side of it.)
		var wander := 1.2 * sin(d * 0.16) + 2.0 * sin(d * 0.037) if d > 0.0 else 0.0
		var p := site[0] + site[1] * d + side * wander
		var q := site[0] + site[1] * d + side * 25.0
		print("ROW %f,%f,%f" % [d, field.height_at(p.x, p.y, 0.0), field.height_at(q.x, q.y, 0.0)])
		d += 1.0
	quit(0)
