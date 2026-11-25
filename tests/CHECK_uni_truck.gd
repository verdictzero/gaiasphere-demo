extends SceneTree

# THE UNI-TRUCK, DRIVEN: it is found where it waits by the first herd, got into,
# driven ahead, turned both ways, braked, jumped and got out of, and at each
# stage what it did is printed: speed, how far it leans (and which way), how far
# the strut is pressed, whether the wheel is down, and the most it ever tipped.
#
#   godot --headless --path . --script res://tests/CHECK_uni_truck.gd
#   (with a renderer and SHOTS=1 in the environment it also saves pictures of
#   it to renders/truck_*.png)

var _scene: Node
var _truck: UniTruck
var _t := 0.0
var _stage := -1
var _stage_t := 0.0
var _worst_tip := 0.0
var _top := -1e9
var _jump_from := 0.0
var _trace := 0.0
var _shots := OS.get_environment("SHOTS") == "1"
var _shot := 0

const STAGES := [
	["settle", 2.0, []],
	["get in", 0.5, []],
	["ahead", 1.5, [&"wv_forward"]],
	["circle right", 5.0, [&"wv_forward", &"wv_right"]],
	["circle left", 5.0, [&"wv_forward", &"wv_left"]],
	["brake", 2.0, [&"wv_back"]],
	["jump standing", 2.5, [&"wv_up"]],
	["pivot on the spot", 2.0, [&"wv_right"]],
	["reverse", 2.0, [&"wv_back"]],
	["ahead + jump", 3.0, [&"wv_forward", &"wv_up"]],
	["brake again", 2.5, [&"wv_back"]],
	["let go", 3.0, []],
	["get out", 2.5, []],
]


func _initialize() -> void:
	_scene = (load("res://scenes/SCENE_gaiasphere_demo.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(delta: float) -> bool:
	_t += delta
	if _t > 900.0:
		print("truck: gave up waiting")
		quit(1)
		return true
	var explorer: Node3D = _scene.get_node("Explorer")
	_truck = _scene.get_node("UniTruck") as UniTruck
	if _stage < 0:
		if explorer.arrived and not _scene.has_node("LoadingCover") and _truck.body != null and _truck.body.freeze \
				and _truck._look_ground < 0.0:
			var enviro := _scene.get_node("Enviro")
			enviro.advance = false
			enviro.hour = 10.0
			(_scene.get_node("CowHerds") as Node).set_process(false)
			_truck.body.contact_monitor = true
			_truck.body.max_contacts_reported = 8
			print("truck: parked and settled at %s (strut %.3f m, upright %.3f)" % [
					_truck.body.global_position, _truck._d, _truck.body.global_basis.y.y])
			_next()
		return false
	_stage_t += delta
	var b := _truck.body
	if _truck._driver:
		_worst_tip = maxf(_worst_tip, rad_to_deg(b.global_basis.y.angle_to(Vector3.UP)))
		_top = maxf(_top, b.global_position.y)
	if OS.get_environment("TRACE") == "1":
		_trace += delta
		if _trace > 0.2:
			_trace = 0.0
			print("  t %.1f pos %s v %.1f up %s strut %+.3f %s" % [_stage_t, b.global_position.snapped(Vector3.ONE * 0.1),
					b.linear_velocity.length(), b.global_basis.y.snapped(Vector3.ONE * 0.01), _truck._d, "down" if _truck._grounded else "UP"])
	if _stage_t >= float(STAGES[_stage][1]):
		_report()
		_next()
	return false


func _next() -> void:
	if _stage >= 0:
		for a in STAGES[_stage][2]:
			Input.action_release(a)
	_stage += 1
	_stage_t = 0.0
	if _stage >= STAGES.size():
		print("truck: most it tipped while driven %.1f deg" % _worst_tip)
		print("truck: done")
		quit(0)
		return
	var name: String = STAGES[_stage][0]
	var explorer: Node3D = _scene.get_node("Explorer")
	if name == "get in":
		# Walk up to the driver's side and look at the cab.
		var b := _truck.body.global_transform
		var side := b.origin - b.basis.x * 3.5
		explorer.global_position = side
		var cam := explorer.get_node("Camera3D") if explorer.has_node("Camera3D") else _cam_of(explorer)
		var at := b.origin + Vector3.UP * 0.6
		explorer.call(&"_face", at - side)
		var eye: Vector3 = (cam as Node3D).global_position
		(cam as Node3D).look_at(at)
		var ok := _truck.can_use(eye, at - eye)
		print("truck: from the side, can it be got into? %s (label %s)" % [ok, _truck.use_label()])
		_truck.try_use(eye, at - eye)
		print("truck: driving %s, in %s" % [UniTruck.driving, explorer.get("driving") != null])
	if name.contains("jump"):
		_top = _truck.body.global_position.y
		_jump_from = _top
	if name == "get out":
		_truck.get_out()
		print("truck: out at %s, %.1f m from the truck, driving %s" % [explorer.global_position,
				explorer.global_position.distance_to(_truck.body.global_position), UniTruck.driving])
	for a in STAGES[_stage][2]:
		# (Round the circles at a little under half throttle.)
		Input.action_press(a, 0.45 if (name.begins_with("circle") and a == &"wv_forward") else 1.0)


func _cam_of(n: Node) -> Camera3D:
	for c in n.get_children():
		if c is Camera3D:
			return c
	return null


func _report() -> void:
	var b := _truck.body
	var v := b.linear_velocity
	var heading := -b.global_basis.z
	var right := b.global_basis.x
	# Lean: + to the right; pitch: + nose down.
	var lean := rad_to_deg(asin(clampf(right.y * -1.0, -1.0, 1.0)))
	var pitch := rad_to_deg(asin(clampf(-heading.y, -1.0, 1.0)))
	var extra := ""
	if String(STAGES[_stage][0]).begins_with("circle"):
		extra = "  (a lean of %.1f would balance the turn)" % rad_to_deg(atan(v.length() * -b.angular_velocity.y / 9.8))
	if String(STAGES[_stage][0]).contains("jump"):
		extra = "  highest %.2f m over where it left" % (_top - _jump_from)
	print("truck: %-18s speed %5.1f m/s  yaw %5.2f rad/s  lean %5.1f  pitch %5.1f  strut %+.3f  wheel %s  frozen %s%s" % [
			STAGES[_stage][0], v.length(), b.angular_velocity.y, lean, pitch, _truck._d,
			"down" if _truck._grounded else "UP", b.freeze, extra])
	if not _truck._grounded:
		print("   touching ", b.get_colliding_bodies().map(func(o: Node) -> String: return String(o.get_path())))
	if _shots:
		root.get_viewport().get_texture().get_image().save_png("res://renders/truck_%02d.png" % _shot)
		_shot += 1
