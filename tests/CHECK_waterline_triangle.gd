extends SceneTree

# The lens's waterline is drawn from the triangle of the lagoon's surface the eye
# is over: that there is one wherever the lagoon's level is found, and that the
# point asked about is inside it.
#
#   godot --headless --path . --script res://tests/CHECK_waterline_triangle.gd

var _scene: Node
var _frames := 0


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var water: RiverWater = _scene.get_node("RiverWater")
	var flows: FlowTerrain = water._flows
	var mid := flows.lagoon_center()
	var found := 0
	var asked := 0
	var widest := 0.0
	for k in 400:
		var th := float(k) * 2.399
		var sh := flows.lagoon_shores(th)
		var r := lerpf(sh.x + 1.0, sh.y - 1.0, fposmod(float(k) * 0.618, 1.0))
		var p := Vector3(mid.x + cos(th) * r, 0.0, mid.y + sin(th) * r) + water.global_position
		asked += 1
		var tri := water.lagoon_triangle(p)
		if tri.size() == 3 and Geometry2D.point_is_inside_triangle(Vector2(p.x, p.z), Vector2(tri[0].x, tri[0].z), Vector2(tri[1].x, tri[1].z), Vector2(tri[2].x, tri[2].z)):
			found += 1
			widest = maxf(widest, maxf(tri[0].distance_to(tri[1]), maxf(tri[1].distance_to(tri[2]), tri[2].distance_to(tri[0]))))
	var out := water.lagoon_triangle(Vector3(mid.x, 0, mid.y) + water.global_position + Vector3(4000, 0, 0))
	print("waterline: a triangle found for %d of %d points on the lagoon, the longest side %.1f m; none far outside it: %s" % [found, asked, widest, out.is_empty()])
	var ok := found == asked and out.is_empty()
	print("waterline: ok" if ok else "waterline: FAILED")
	quit(0 if ok else 1)
	return true
