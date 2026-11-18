class_name StoneBridge
extends Node3D

# THE BRIDGE TO THE ISLET: a cobbled stone bridge across the mere where it is
# narrowest, from the outer shore to the islet the sword stands on. A gently
# arched deck between low parapets, on piers that go down to the bed, running a
# little way inland at each end so it meets the ground. Built once from the
# field, with collision, and textured in world space so no stone is stretched.

@export var world_path: NodePath = ^"../IslandWorld"
@export var deck_width := 4.6
@export var arch := 2.4
@export var parapet := Vector2(0.45, 0.8)     # thickness, height
@export var pier_spacing := 15.0
@export var inland := 9.0

var start := Vector3.ZERO       # on the outer shore
var finish := Vector3.ZERO      # on the islet


func _ready() -> void:
	var world := get_node_or_null(world_path)
	if world == null or not world.has_method(&"get_field"):
		return
	var field: IslandField = world.call(&"get_field")
	if not field._ready:
		field.prepare()
	var isl: Variant = field.island_in_cell(field.hub_cell())
	var flows: Variant = field.flows_for(isl) if isl != null else null
	if flows == null or not flows.has_lagoon():
		return
	var centre: Vector2 = flows.lagoon_center()
	# The narrowest crossing.
	var best_th := 0.0
	var best := 1e9
	for i in 96:
		var th := TAU * float(i) / 96.0
		var sh: Vector2 = flows.lagoon_shores(th)
		if sh.y - sh.x < best:
			best = sh.y - sh.x
			best_th = th
	var shores: Vector2 = flows.lagoon_shores(best_th)
	var dir := Vector2(cos(best_th), sin(best_th))
	var a := centre + dir * (shores.y + inland)
	var b := centre + dir * (shores.x - inland)
	var level := float(isl.base_y) + float(flows.lagoon_level())
	var ha := maxf(field.height_at(a.x, a.y, level), level + 0.4)
	var hb := maxf(field.height_at(b.x, b.y, level), level + 0.4)
	start = Vector3(a.x, ha, a.y)
	finish = Vector3(b.x, hb, b.y)
	var length := a.distance_to(b)
	var along := Vector3(b.x - a.x, 0.0, b.y - a.y).normalized()
	var side := along.cross(Vector3.UP)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := maxi(8, int(length / 3.0))
	var line: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / float(segs)
		# Level with the ground at each end, well clear of the water between.
		var y := lerpf(ha, hb, t) + sin(t * PI) * arch
		y = maxf(y, lerpf(ha, hb, t))
		line.append(Vector3(lerpf(a.x, b.x, t), y, lerpf(a.y, b.y, t)))
	var half := deck_width * 0.5
	_ribbon(st, line, side, -half, half, -0.9, 0.0)                               # the deck
	_ribbon(st, line, side, -half - parapet.x, -half, -0.9, parapet.y)           # parapets
	_ribbon(st, line, side, half, half + parapet.x, -0.9, parapet.y)
	var piers := maxi(1, int((length - 2.0 * inland) / pier_spacing))
	for k in piers + 1:
		var t := (inland + (length - 2.0 * inland) * float(k) / float(piers)) / length
		var p := line[clampi(int(round(t * segs)), 0, segs)]
		var bed := field.height_at(p.x, p.z, level - 12.0) - 1.5
		_box(st, Vector3(p.x, (p.y - 0.9 + bed) * 0.5, p.z), along * 1.3, side * (half + parapet.x + 0.35),
				Vector3.UP * ((p.y - 0.9 - bed) * 0.5))
		# A cutwater's worth of extra stone at the waterline.
		_box(st, Vector3(p.x, level - 0.2, p.z), along * 1.7, side * (half + parapet.x + 0.75), Vector3.UP * 0.9)
	st.generate_normals()
	var mesh := st.commit()

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://textures/polyhaven/mossy_cobblestone_basecolor.jpg")
	mat.normal_enabled = true
	mat.normal_texture = load("res://textures/polyhaven/mossy_cobblestone_normal.jpg")
	mat.orm_texture = load("res://textures/polyhaven/mossy_cobblestone_orm.jpg")
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.4
	mat.uv1_triplanar_sharpness = 4.0
	mat.albedo_color = Color(0.85, 0.85, 0.82)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Bridge"
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.create_trimesh_collision()
	print("[bridge] %.0f m of bridge from %s to %s" % [length, start, finish])


## A box-section strip along `line`: from `s0` to `s1` across, `y0` to `y1` about the line.
func _ribbon(st: SurfaceTool, line: Array[Vector3], side: Vector3, s0: float, s1: float, y0: float, y1: float) -> void:
	for i in line.size() - 1:
		var p := line[i]
		var q := line[i + 1]
		var c := [p + side * s0 + Vector3.UP * y0, p + side * s1 + Vector3.UP * y0,
				p + side * s1 + Vector3.UP * y1, p + side * s0 + Vector3.UP * y1,
				q + side * s0 + Vector3.UP * y0, q + side * s1 + Vector3.UP * y0,
				q + side * s1 + Vector3.UP * y1, q + side * s0 + Vector3.UP * y1]
		for f in [[3, 2, 6, 7], [1, 0, 4, 5], [0, 3, 7, 4], [2, 1, 5, 6]]:
			_quad(st, c[f[0]], c[f[1]], c[f[2]], c[f[3]])
	var n := line.size() - 1
	for cap in [[line[0], false], [line[n], true]]:
		var p: Vector3 = cap[0]
		var c := [p + side * s0 + Vector3.UP * y0, p + side * s1 + Vector3.UP * y0,
				p + side * s1 + Vector3.UP * y1, p + side * s0 + Vector3.UP * y1]
		if cap[1]:
			_quad(st, c[1], c[0], c[3], c[2])
		else:
			_quad(st, c[0], c[1], c[2], c[3])


func _box(st: SurfaceTool, centre: Vector3, hx: Vector3, hy: Vector3, hz: Vector3) -> void:
	for axis in [[hx, hy, hz], [hy, hz, hx], [hz, hx, hy]]:
		for sgn in [1.0, -1.0]:
			var o: Vector3 = centre + axis[0] * sgn
			var u: Vector3 = axis[1] * sgn
			var v: Vector3 = axis[2]
			_quad(st, o - u - v, o + u - v, o + u + v, o - u + v)


## The material draws both faces, so the winding does not have to be tracked.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		for v in tri:
			st.add_vertex(v)
