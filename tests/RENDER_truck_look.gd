extends SceneTree

# A look at the truck model by itself from four sides, to renders/truck_*.png.
#   godot --path . --script res://tests/RENDER_truck_look.gd

var _frames := 0
var _cam: Camera3D
var _shot := 0
const VIEWS := [Vector3(0, 3, 22), Vector3(22, 3, 0), Vector3(14, 10, -14), Vector3(-16, 2, 6)]

func _initialize() -> void:
	var root3 := Node3D.new()
	root.add_child(root3)
	var m := (load("res://assets/truck/uni_truck.glb") as PackedScene).instantiate()
	root3.add_child(m)
	# Each part tinted its own colour, to tell them apart.
	var tints := {"gyroscope": Color(0, 1, 0), "spring": Color(1, 1, 0), "suspension_shock_upper": Color(0, 0, 1),
			"suspension_shock_lower": Color(0, 1, 1), "super_spindle": Color(1, 0, 1), "wheel_hub_drive_motor_assy_000": Color(1, 0.5, 0)}
	for n in tints:
		var mi := m.find_child(n, true, false) as MeshInstance3D
		if mi == null:
			print("no ", n)
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tints[n]
		mi.material_override = mat
	for c in m.find_children("*", "Node3D", true, false):
		print(c.name, " ", c.position)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root3.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.6, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root3.add_child(env)
	_cam = Camera3D.new()
	root3.add_child(_cam)
	_cam.make_current()
	_place()

func _place() -> void:
	_cam.position = VIEWS[_shot]
	_cam.look_at(Vector3(0, 0, 0))

func _process(_d: float) -> bool:
	_frames += 1
	if _frames % 6 == 0:
		root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/-home-user-west-virginia/5717ac44-0521-53ef-9af2-b9db2802aeee/scratchpad/truck_%d.png" % _shot)
		_shot += 1
		if _shot >= VIEWS.size():
			return true
		_place()
	return false
