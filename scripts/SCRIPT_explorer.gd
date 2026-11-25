extends CharacterBody3D

# THE ONLY "GAME" IN THIS PROJECT: a body to walk the island with, and a free
# camera to look at it from the air. Nothing else is played here; the project is
# an example of the terrain and water engines and this is how you move through
# it.
#
# ON FOOT it walks, runs and jumps on the terrain's own collision, and SWIMS:
# where the water is over its chest it floats with its eyes just clear of the
# surface, and holding down takes it under, into the underwater view.
#
# IN THE AIR (F) it is a free camera with no collision, at a speed the mouse
# wheel scales from a crawl to crossing the island in seconds. F again and it
# drops back onto its feet from wherever it is.
#
# The streaming terrain (`GaiaSphere`), the vegetation scatters and the
# underwater view all read the viewport's active camera, which is this node's,
# so nothing has to be told where the player is.
#
# IN THE UNI-TRUCK (SCRIPT_uni_truck.gd) it rides in the cab and the truck is
# driven instead; looking swings the truck's view round.
#
# CONTROLS: WASD or the left stick to move, the mouse or the right stick to
# look, Space / A to jump (up, flying or swimming), Ctrl or C / B down, Shift /
# left stick click to run, F / Y to fly, the wheel or [ ] for flying speed,
# R / Back to return to the start, Esc frees the mouse, F11 is full screen.

@export var landing_spot_path: NodePath
@export var river_water_path: NodePath
@export var cloud_sea_path: NodePath

@export_group("On foot")
@export var walk_speed := 4.5
@export var run_speed := 9.0
@export var jump_velocity := 7.0
@export var gravity := 20.0
@export var eye_height := 1.6
@export var swim_speed := 3.0

@export_group("Flying")
## Metres a second at the wheel's middle; the wheel takes it from 1/16 to 16x.
@export var fly_speed := 30.0

@export_group("Looking")
@export var mouse_sensitivity := 0.0025
## Degrees a second at full stick.
@export var stick_look_speed := 150.0

## True while flying.
var flying := false
## Gone under the cloud sea, a moment before being put back at the start.
signal fell
## Whether there is the breath to run, and whether it is being done this frame.
var run_allowed := true
var running := false
## False until the loading cover puts the body down (`arrive`).
var arrived := false
## How hard the water lifts a swimmer to the surface: 1 as it is in open water,
## 0 to hang where they are (inside the flooded shuttle, SCRIPT_crashed_shuttle.gd,
## so they are not carried up its sloping roof and out of the door before they
## have looked about).
var buoyancy := 1.0
## How far the water stands over the feet, metres (0 on dry ground, and while
## flying). The head is under when it is over the eyes (SCRIPT_vitals.gd's air).
var deep := 0.0
## Afloat: out of its depth and off the bottom.
var swimming := false
## Swum out (SCRIPT_vitals.gd): no stamina left in the water, and slow for it.
var swim_tired := false
## The vehicle being driven (SCRIPT_uni_truck.gd), or null on foot. While there
## is one the body rides in it: the vehicle moves it, and looking swings the
## vehicle's view round.
var driving: Node = null

var _cam: Camera3D
var _pitch := 0.0
var _fly_scale := 1.0
var _spot: Node3D
var _water: Node
var _torch: SpotLight3D
var _sea: Node
var _under := 0.0
var _ripple := 0.0


func _ready() -> void:
	_actions()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_cam = Camera3D.new()
	_cam.position.y = eye_height
	_cam.near = 0.1
	_cam.far = 12000.0
	_cam.fov = 75.0
	add_child(_cam)
	_cam.make_current()
	# A FLASHLIGHT (L or V, d-pad up, the LIGHT button on a touchscreen): a warm
	# spot on the camera, a little off to one side like a held torch, off to start.
	_torch = SpotLight3D.new()
	_torch.name = "Flashlight"
	_torch.light_color = Color(1.0, 0.96, 0.9)
	# The beam's shape is the cookie's: a hot centre, the reflector's rings and a
	# dim spill out to the bezel. The cone itself is left nearly flat so the two do
	# not fall off twice.
	_torch.light_projector = load("res://assets/ui/flashlight_cookie.png")
	_torch.light_energy = 90.0
	# NOT ON WHAT IS IN THE HAND. A torch held beside a blade half a metre from
	# the eye lights it a hundred times brighter than anything it is pointed at,
	# and the blade blooms into a white smear. Hand-held things are drawn on a
	# layer of their own (SCRIPT_world_reflection.gd's MIRROR_LAYER) and the beam
	# leaves that layer alone; SCRIPT_sword_play.gd gives them a small light of
	# their own while the torch is on.
	_torch.light_cull_mask = 0xFFFFF & ~(1 << 9)
	_torch.spot_range = 60.0
	_torch.spot_angle = 38.0
	_torch.spot_angle_attenuation = 0.12
	_torch.spot_attenuation = 0.9
	_torch.shadow_enabled = not OS.has_feature("mobile")
	_torch.position = Vector3(0.22, -0.18, 0.0)
	_torch.visible = false
	_cam.add_child(_torch)
	add_to_group(Prewarm.GROUP)
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	_spot = get_node_or_null(landing_spot_path) as Node3D
	_water = get_node_or_null(river_water_path)
	_sea = get_node_or_null(cloud_sea_path)
	# Held over the landing spot while the world is built, so the terrain streams
	# (and lays its collision) round where the body is about to stand.
	global_position = _home() + Vector3.UP * 3.0
	_face(_home_facing())
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Put the body down at the start. The loading cover calls this once there is
## ground there to stand on.
func arrive() -> void:
	if driving != null:
		driving.call(&"get_out")
	global_position = _home() + Vector3.UP * 0.2
	velocity = Vector3.ZERO
	_face(_home_facing())
	flying = false
	arrived = true


func _home() -> Vector3:
	if _spot != null and _spot.has_method(&"hatch_spot"):
		return _spot.call(&"hatch_spot")
	return Vector3(0.0, 50.0, 0.0)


func _home_facing() -> Vector3:
	if _spot != null and _spot.has_method(&"hatch_facing"):
		return _spot.call(&"hatch_facing")
	return Vector3.FORWARD


func _face(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() > 1e-6:
		rotation = Vector3(0.0, atan2(-flat.x, -flat.z), 0.0)
	_pitch = 0.0
	_cam.rotation = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look((event as InputEventMouseMotion).relative * mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_fly_step(1.25)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_fly_step(0.8)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"wv_release"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed(&"wv_fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN \
				else Window.MODE_FULLSCREEN
	elif not arrived:
		return
	elif event.is_action_pressed(&"wv_light"):
		if driving != null:
			driving.call(&"lights")
		else:
			_torch.visible = not _torch.visible
	elif driving != null:
		if event.is_action_pressed(&"wv_home"):
			arrive()
	elif event.is_action_pressed(&"wv_fly"):
		flying = not flying
		velocity = Vector3.ZERO
	elif event.is_action_pressed(&"wv_home"):
		arrive()
	elif event.is_action_pressed(&"wv_faster"):
		_fly_step(1.25)
	elif event.is_action_pressed(&"wv_slower"):
		_fly_step(0.8)


func _fly_step(by: float) -> void:
	_fly_scale = clampf(_fly_scale * by, 1.0 / 16.0, 16.0)


func _look(by: Vector2) -> void:
	if driving != null:
		driving.call(&"look", by)
		return
	rotate_y(-by.x)
	_pitch = clampf(_pitch - by.y, -1.55, 1.55)
	_cam.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	var stick := Input.get_vector(&"wv_look_left", &"wv_look_right", &"wv_look_up", &"wv_look_down")
	if stick.length_squared() > 0.0:
		_look(stick * deg_to_rad(stick_look_speed) * delta)
	# The grass and the seaweed lean out of the way of the feet (SHADER_foliage's
	# push_bend); not while flying or riding.
	var brush := 0.0 if (flying or driving != null or not arrived) else 0.85
	RenderingServer.global_shader_parameter_set(&"plant_push_a", Vector4(global_position.x, global_position.y, global_position.z, brush))
	if not arrived:
		return
	if driving != null:
		velocity = Vector3.ZERO
		running = false
		deep = 0.0
		swimming = false
		return
	var move := Input.get_vector(&"wv_left", &"wv_right", &"wv_forward", &"wv_back")
	var rise := Input.get_axis(&"wv_down", &"wv_up")
	var fast := Input.is_action_pressed(&"wv_run")
	# On foot, running is the body's to allow (SCRIPT_vitals.gd): not out of breath.
	running = fast and run_allowed and not flying and move.length() > 0.2
	if not flying:
		fast = fast and run_allowed
	if flying:
		deep = 0.0
		swimming = false
		_fly(move, rise, fast, delta)
	else:
		_walk(move, rise, fast, delta)
	_fell_off(delta)


func _fly(move: Vector2, rise: float, fast: bool, delta: float) -> void:
	var b := _cam.global_basis
	var dir := b.x * move.x + b.z * move.y + Vector3.UP * rise
	var speed := fly_speed * _fly_scale * (4.0 if fast else 1.0)
	global_position += dir * speed * delta


func _walk(move: Vector2, rise: float, fast: bool, delta: float) -> void:
	var b := global_basis
	var want := b.x * move.x + b.z * move.y
	# How far the water stands over the feet, 0 on dry ground.
	deep = 0.0
	if _water != null and _water.has_method(&"world_level_at"):
		var level := float(_water.call(&"world_level_at", global_position))
		if not is_nan(level):
			deep = maxf(level - global_position.y, 0.0)
	swimming = deep > 1.3 and not (is_on_floor() and deep < 1.45)
	var speed := swim_speed * (0.5 if swim_tired else 1.0) if swimming else (run_speed if fast else walk_speed)
	if deep > 0.3 and not swimming:
		speed *= 0.7
	var flat := want * speed
	var grip := 10.0 if is_on_floor() or swimming else 3.0
	velocity.x = lerpf(velocity.x, flat.x, clampf(grip * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, flat.z, clampf(grip * delta, 0.0, 1.0))
	if swimming:
		# Buoyed to where the eyes stand a quarter of a metre clear; up and down
		# swim against it.
		var settle := clampf((deep - (eye_height - 0.25)) * 3.0, -1.5, 2.0) * buoyancy
		var aim := rise * 2.5 if absf(rise) > 0.1 else settle
		velocity.y = move_toward(velocity.y, aim, 14.0 * delta)
	else:
		if is_on_floor():
			if Input.is_action_just_pressed(&"wv_up"):
				velocity.y = jump_velocity
		else:
			velocity.y -= gravity * delta
	move_and_slide()
	# A ring on the water now and then while wading or swimming through it.
	if deep > 0.05 and _water != null and _water.has_method(&"ripple"):
		_ripple -= delta * (0.4 + Vector2(velocity.x, velocity.z).length())
		if _ripple <= 0.0:
			_ripple = 1.6
			_water.call(&"ripple", global_position, 0.35 if swimming else 0.2)


# Off the island's edge and into the cloud sea: back to the start after a
# moment under it. Flying is left alone; the sea is worth seeing from inside.
func _fell_off(delta: float) -> void:
	var sea := -45.0
	if _sea != null and _sea.has_method(&"surface_y"):
		sea = float(_sea.call(&"surface_y"))
	if flying or global_position.y > sea - 4.0:
		_under = 0.0
		return
	_under += delta
	if _under > 1.5:
		_under = 0.0
		fell.emit()
		arrive()


# The controls, registered here so the project file carries no input map.
func _actions() -> void:
	_key(&"wv_forward", [KEY_W, KEY_UP])
	_key(&"wv_back", [KEY_S, KEY_DOWN])
	_key(&"wv_left", [KEY_A, KEY_LEFT])
	_key(&"wv_right", [KEY_D, KEY_RIGHT])
	_key(&"wv_up", [KEY_SPACE])      # E is the sword (SCRIPT_sword_play.gd)
	_key(&"wv_down", [KEY_CTRL, KEY_C, KEY_Q])
	_key(&"wv_run", [KEY_SHIFT])
	_key(&"wv_fly", [KEY_F])
	_key(&"wv_light", [KEY_L, KEY_V])
	_button(&"wv_light", JOY_BUTTON_DPAD_UP)
	_key(&"wv_home", [KEY_R])
	_key(&"wv_faster", [KEY_BRACKETRIGHT])
	_key(&"wv_slower", [KEY_BRACKETLEFT])
	_key(&"wv_release", [KEY_ESCAPE])
	_key(&"wv_fullscreen", [KEY_F11])
	for a in [&"wv_look_left", &"wv_look_right", &"wv_look_up", &"wv_look_down"]:
		_key(a, [])
	_axis(&"wv_left", JOY_AXIS_LEFT_X, -1.0)
	_axis(&"wv_right", JOY_AXIS_LEFT_X, 1.0)
	_axis(&"wv_forward", JOY_AXIS_LEFT_Y, -1.0)
	_axis(&"wv_back", JOY_AXIS_LEFT_Y, 1.0)
	_axis(&"wv_look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis(&"wv_look_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis(&"wv_look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis(&"wv_look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_button(&"wv_up", JOY_BUTTON_A)
	_button(&"wv_down", JOY_BUTTON_B)
	_button(&"wv_fly", JOY_BUTTON_Y)
	_button(&"wv_run", JOY_BUTTON_LEFT_STICK)
	_button(&"wv_home", JOY_BUTTON_BACK)
	_button(&"wv_faster", JOY_BUTTON_RIGHT_SHOULDER)
	_button(&"wv_slower", JOY_BUTTON_LEFT_SHOULDER)


func _key(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _axis(action: StringName, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _button(action: StringName, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


## FIRST TIMES (SCRIPT_prewarm.gd): the torch is lit while the stage stands, so
## the first time it is switched on it has nothing to set up.
func warm(stage: Node3D) -> void:
	if _torch == null or _torch.visible:
		return
	_torch.visible = true
	stage.tree_exiting.connect(func() -> void: _torch.visible = false)
