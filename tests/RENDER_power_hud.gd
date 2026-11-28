extends SceneTree

# THE POWER METERS AND THE PLUG'S GHOST, LOOKED AT (no island: a floor, a light):
# a panel, a battery and a turret cabled up, a second cable in hand, the eye on a
# free socket of the turret. To renders/power_hud.png.
#
#   godot --path . --resolution 1280x720 --script res://tests/RENDER_power_hud.gd

var _power: Power
var _n := 0


func _initialize() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.65, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	shape.shape = bs
	body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.42, 0.3)
	bm.material = mat
	floor_mesh.mesh = bm
	body.add_child(floor_mesh)
	root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)
	var me := Node3D.new()
	me.name = "Explorer"
	root.add_child(me)
	me.global_position = Vector3(0, 0, 4.5)
	_power = Power.new()
	_power.explorer_path = NodePath("../Explorer")
	root.add_child(_power)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(0.3, 1.7, 4.5)
	cam.look_at(Vector3(0.5, 0.5, 1.0))
	cam.make_current()


func _join(a: Power.Dev, sa: int, b: Power.Dev, sb: int) -> void:
	var cable: Power.Line = _power.call(&"_new_cable")
	_power.call(&"_plug", cable, 0, a, sa)
	var p0: Vector3 = _power.call(&"_end_point", cable, 0)
	var q: Transform3D = _power.call(&"_socket_world", b, sb)
	var p1: Vector3 = q.origin + q.basis.x * 0.8
	var pts := PackedVector3Array()
	var n := int(ceil(p0.distance_to(p1) * 1.2 / Power.SEG)) + 3
	for i in n:
		pts.append(p0.lerp(p1, float(i) / float(n - 1)) + Vector3(0, 0.3 * sin(PI * float(i) / float(n - 1)), 0))
	cable.pts = pts
	cable.old = pts.duplicate()
	_power.call(&"_plug", cable, 1, b, sb)


func _process(_d: float) -> bool:
	_n += 1
	if _n == 3:
		var turret := _power.set_down("laser_ciws", Transform3D(Basis(), Vector3.ZERO))
		var store := _power.set_down("battery", Transform3D(Basis(), Vector3(4, 0, 0)), _power.capacity() * 0.62)
		var sun := _power.set_down("solar_panel", Transform3D(Basis(), Vector3(-4, 0, 1)))
		_join(store, 1, turret, 0)
		_join(sun, 0, turret, 3)
		# A second cable from the battery, its other end in hand.
		var cable: Power.Line = _power.call(&"_new_cable")
		_power.call(&"_plug", cable, 0, store, 0)
		_power.call(&"_take_up", cable, 1)
		var start: Vector3 = _power.call(&"_end_point", cable, 0)
		cable.pts = PackedVector3Array([start, start])
		cable.old = cable.pts.duplicate()
	if _n == 200:
		root.get_viewport().get_texture().get_image().save_png("res://renders/power_hud.png")
		return true
	return false
