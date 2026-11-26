class_name UniTruck
extends Node3D

# THE UNI-TRUCK: a truck on ONE wheel, held upright by a pair of gyroscopes, that
# can be got into and driven (and jumped). It waits up on the high ground by the
# first herd, the meadow by the wreck, nose pointing down the hill.
#
# HOW IT STAYS UP. One wheel under the middle of a long body is a pendulum
# standing on its head: left to itself it falls over in about a second. Two
# CONTROL-MOMENT GYROS in the bed (the model's `gyroscope`, two flywheels fore
# and aft) keep it up the way real ones do: each flywheel spins hard about its
# upright axis, and tipping its gimbal turns that spin into a torque on the body.
# Here that is a stiff, damped controller with a limit on how much torque it may
# have (`gyro_authority`), aiming the body's "up" at:
#   - straight up, standing still or in the air (so it lands level);
#   - leaned INTO a turn by just the angle the turn calls for (`tan = v·yaw/g`),
#     as a bike leans, so the tyre is not thrown off its contact patch;
#   - tipped a little forward when the hub motor pulls and back when it brakes,
#     as anything balanced on one wheel must.
# The two gimbals are drawn tipping opposite ways (a scissored pair) as hard as
# the torque they are giving.
#
# THE WHEEL is a sphere swept down the strut each physics step (not a collision
# shape): where it meets the ground the coilover pushes back (a preloaded spring
# and a damper, with a bump stop at the end of its travel) and the tyre grips —
# drive and brake along it, sideways grip across it, both inside one friction
# circle, so it slides when asked for more than the ground has. The strut on the
# model follows it: the lower tube, the spindle, the hub and the tyre ride up and
# down inside the upper tube and the spring between them shortens and lengthens.
# The tyre turns as fast as it rolls.
#
# STEERING is the gyros too: a single in-line wheel has nothing to turn, so the
# gyros yaw the body and the tyre's grip swings the truck round after it.
#
# GETTING IN: look at it within a few metres and USE (E / click / the big
# button). Driving: forward and back to drive and brake (and reverse), left and
# right to steer, JUMP (Space / A) to kick the strut and jump, RUN (Shift) for
# more power, the light key for the headlights, USE to get out. JUMP HELD burns
# the four JET BOOSTERS under the corners of the bed (the model's `booster`): the
# jump goes off with them lit, they carry it up for as long as the button is held
# and there is burn in the tank (`burn_time`; it fills again on the ground), and
# they can be lit again in the air to hold a fall off or clear a gap. Each jet
# is a blue-white core in an orange plume, with a light under the truck, and
# near the ground they throw up a ring and dust. The view is from
# behind and above, swung round with the mouse or the right stick, and drifts
# back behind the truck once it is moving and left alone.
#
# Parked and settled, the body is frozen (it costs nothing, and does not creep).

@export var explorer_path: NodePath = ^"../Explorer"
@export var world_path: NodePath = ^"../GaiaSphere"
@export var herds_path: NodePath = ^"../CowHerds"
@export var flora_path: NodePath = ^"../Flora"
@export var cloud_sea_path: NodePath = ^"../CloudSea"

@export_group("Body")
## Model units to metres: the modelled wheel is 2.52 across the radius (at
## 0.42, a wheel a metre across the radius on a truck 6.8 m long and 5 m high).
## Everything that goes by its size (the suspension's travel, the view's
## distance, the room it needs to park and to be got out of) follows this.
@export var model_scale := 0.42
@export var mass := 1400.0

@export_group("Suspension")
## Metres the wheel can ride up above where it hangs at rest, and drop below it.
@export var bump_travel := 0.3
@export var droop_travel := 0.18
## Newtons a metre, and of damping a metre a second.
@export var spring_rate := 60000.0
@export var damping := 12000.0

@export_group("Drive")
@export var top_speed := 24.0
@export var boost_speed := 34.0
@export var drive_accel := 11.0
@export var boost_accel := 16.0
@export var brake_accel := 18.0
## Tyre on the ground: the most it can push, as a fraction of the load on it.
@export var grip := 1.6
## Radians a second of turn at a standstill, and at top speed.
@export var turn_rate := Vector2(1.7, 0.75)
## How hard the jump kicks, metres a second straight up.
@export var jump_speed := 7.5

@export_group("Boosters")
## Seconds of burn in the tank, and seconds of burn it gets back each second on
## the ground.
@export var burn_time := 1.8
@export var burn_refill := 0.9
## The four jets' push together, as a multiple of the truck's weight: over 1 it
## climbs on them, and the more over the faster.
@export var burn_lift := 1.9

@export_group("Gyros")
## Stiffness (1/s) of the upright hold.
@export var gyro_rate := 6.5
@export_range(0.1, 2.0) var gyro_damping := 0.85
## The most angular acceleration the gyros can give, radians a second squared.
@export var gyro_authority := 40.0
## Furthest it leans into a turn or into the throttle, degrees.
@export var max_lean := 42.0

@export_group("View")
@export var chase_distance := 14.0
@export var chase_height := 2.8

## True while someone is driving (anything that reads the hand and the hotbar
## stands down: SCRIPT_sword_play.gd, SCRIPT_building.gd, SCRIPT_cooking.gd).
static var driving := false

const MODEL := "res://assets/truck/uni_truck.glb"
# Where things are, in model units (the model's own frame: the cab is toward -Z).
const AXLE_Y := -3.5864                 # the hub's centre, hanging at rest
const WHEEL_R := 2.5226                 # tyre radius
const SEAT := Vector3(-1.4, 3.6, -4.6)  # the driver's eye, in the cab
const COM := Vector3(0.0, 1.2, 0.0)     # where the weight is: over the wheel
const GYRO_Z := 4.065                   # the two flywheels, fore and aft of the middle
const NOZZLE := Vector3(1.975, -0.61, 6.3)  # a booster's mouth: one at each (+-x, y, +-z)
const GLOW := "res://assets/fx/glow_soft_01.webp"

var body: RigidBody3D

var _explorer: Node3D
var _world: Node
var _herds: Node
var _flora: Node
var _sea: Node
var _model: Node3D
var _cam: Camera3D
var _prompt: Label
var _hint: Label
var _hint_left := 0.0
var _lights: Array[SpotLight3D] = []
var _sphere := SphereShape3D.new()
var _cast := PhysicsShapeQueryParameters3D.new()

# The strut's moving parts and where they hang at rest.
var _lower: Node3D
var _lower_rest := 0.0
var _upper_k := 1.0               # metres per unit of the upper tube's own frame
var _spring: Node3D
var _spring_pos := 0.0
var _spring_scale := 1.0
var _spring_top := 0.0
var _spring_bot := 0.0
var _tire: Node3D
var _gimbals: Array[Node3D] = []

var _home := Transform3D.IDENTITY
var _placed := false
var _look_ground := 0.0
var _driver := false
var _entered_at := 0
var _old_layers := Vector2i.ZERO
var _solid_again := 0

# Wheel and suspension state.
var _d := 0.0                     # metres the wheel rides above its rest (+ up)
var _d_was := 0.0
var _grounded := false
var _contact := Vector3.ZERO
var _normal := Vector3.UP
var _load := 0.0
var _spin := 0.0                  # the tyre's turn, radians
var _spin_rate := 0.0
var _gimbal := 0.0
var _jump_wait := 0.0
var _burn := 0.0                  # seconds of burn left in the tank
var _burning := false
var _jets: Array[GPUParticles3D] = []
var _jet_light: OmniLight3D
var _jet_dust := 0.0
var _tank: ProgressBar
var _still := 0.0
var _under := 0.0
var _g := 9.8

# The view.
var _cam_yaw := 0.0               # swung round from behind, radians
var _cam_pitch := -0.2
var _cam_heading := 0.0
var _cam_idle := 10.0
var _cam_pivot := Vector3.ZERO


func _ready() -> void:
	_explorer = get_node_or_null(explorer_path) as Node3D
	_world = get_node_or_null(world_path)
	_herds = get_node_or_null(herds_path)
	_flora = get_node_or_null(flora_path)
	_sea = get_node_or_null(cloud_sea_path)
	_g = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	driving = false
	add_to_group(&"usable")
	add_to_group(Prewarm.GROUP)
	_make_prompts()


# ------------------------------------------------------------------ the truck

func _build(at: Transform3D) -> void:
	var s := model_scale
	body = RigidBody3D.new()
	body.name = "Body"
	body.mass = mass
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = COM * s
	# A box of a truck: 2.5 wide, 1.9 high, 4.5 long (about its middle).
	var w := 9.0 * s
	var h := 6.8 * s
	var l := 16.1 * s
	body.inertia = Vector3(mass / 12.0 * (h * h + l * l), mass / 12.0 * (w * w + l * l), mass / 12.0 * (w * w + h * h))
	body.linear_damp = 0.05
	body.angular_damp = 0.5
	body.can_sleep = false
	body.continuous_cd = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	add_child(body)
	body.global_transform = at
	_model = (load(MODEL) as PackedScene).instantiate() as Node3D
	_model.scale = Vector3.ONE * s
	body.add_child(_model)
	# What it bumps into the world with: the bed and the frame under it, the cab
	# over the front of it, and the spindle's fork round the hub (the tyre itself
	# is the swept sphere; a smaller ball in it is the last stop on a hard landing).
	_box(Vector3(-4.4, -0.45, -7.65), Vector3(4.4, 2.9, 8.55))
	_box(Vector3(-3.6, 2.9, -7.65), Vector3(3.6, 6.25, -0.6))
	_box(Vector3(-2.1, -4.25, -3.55), Vector3(1.45, -0.45, 3.55), 0.9)
	var stop := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	# (Big enough that, resting on it, the swept wheel still starts clear of the
	# ground and finds it.)
	ball.radius = WHEEL_R * s - bump_travel + 0.03
	stop.shape = ball
	stop.position = Vector3(0, AXLE_Y * s, 0)
	body.add_child(stop)
	_strut()
	_split_gyros()
	# Wear laid over its paint, close to: grime, pitting, scratches and dents in a
	# half-metre tile, projected on in each part's own space (SCRIPT_detail_layer.gd).
	DetailLayer.apply(_model, 0.5)
	for side in [-1.0, 1.0]:
		var lamp := SpotLight3D.new()
		lamp.light_color = Color(1.0, 0.95, 0.85)
		lamp.light_energy = 6.0
		lamp.spot_range = 55.0
		lamp.spot_angle = 28.0
		lamp.spot_attenuation = 0.8
		lamp.shadow_enabled = false
		lamp.position = Vector3(2.9 * side, 1.7, -7.9) * s
		lamp.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
		lamp.visible = false
		body.add_child(lamp)
		_lights.append(lamp)
	_make_jets(body, s)
	_burn = burn_time
	_cast.shape = _sphere
	_sphere.radius = WHEEL_R * s
	_cast.collision_mask = 1
	_cam = Camera3D.new()
	_cam.name = "ChaseCam"
	_cam.top_level = true
	_cam.near = 0.15
	_cam.far = 12000.0
	_cam.cull_mask = 0xFFFFF & ~(1 << (WorldReflection.MIRROR_LAYER - 1))
	add_child(_cam)
	body.freeze = true


## How big it is against the size it was first made at (0.28 to the metre).
func _k() -> float:
	return model_scale / 0.28


func _box(lo: Vector3, hi: Vector3, shrink := 1.0) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (hi - lo) * model_scale * shrink
	cs.shape = box
	cs.position = (lo + hi) * 0.5 * model_scale
	body.add_child(cs)


## The strut's parts, found by name, and where they hang at rest.
func _strut() -> void:
	var upper := _model.find_child("suspension_shock_upper", true, false) as Node3D
	_lower = _model.find_child("suspension_shock_lower", true, false) as Node3D
	_spring = _model.find_child("spring", true, false) as Node3D
	_tire = _model.find_child("wheel_tire_assy*", true, false) as Node3D
	if upper == null or _lower == null:
		push_warning("uni_truck: no strut in the model")
		return
	# Metres of the body's frame per unit of the upper tube's own frame.
	var rel := body.global_transform.affine_inverse() * upper.global_transform
	_upper_k = rel.basis.y.length()
	_lower_rest = _lower.position.y
	if _spring != null and _spring is MeshInstance3D:
		var box := (_spring as MeshInstance3D).get_aabb()
		_spring_pos = _spring.position.y
		_spring_scale = _spring.scale.y
		_spring_top = _spring_pos + _spring_scale * box.end.y
		_spring_bot = _spring_pos + _spring_scale * box.position.y


## The model's `gyroscope` is both flywheels in one mesh: it is cut in two, fore
## and aft, so each can hang in a gimbal of its own and tip.
func _split_gyros() -> void:
	var gyro := _model.find_child("gyroscope", true, false) as MeshInstance3D
	if gyro == null or gyro.mesh == null:
		return
	var src := gyro.mesh
	for half in [-1.0, 1.0]:
		var mesh := ArrayMesh.new()
		for surf in src.get_surface_count():
			var arrays := src.surface_get_arrays(surf)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var keep := PackedInt32Array()
			if idx.is_empty():
				for i in verts.size():
					idx.append(i)
			for t in range(0, idx.size(), 3):
				var z := verts[idx[t]].z + verts[idx[t + 1]].z + verts[idx[t + 2]].z
				if signf(z) == half:
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			arrays[Mesh.ARRAY_INDEX] = keep
			# Each half about its own middle, so it tips in place.
			var moved := PackedVector3Array()
			moved.resize(verts.size())
			for i in verts.size():
				moved[i] = verts[i] - Vector3(0, 0, GYRO_Z * half)
			arrays[Mesh.ARRAY_VERTEX] = moved
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1,
					gyro.get_surface_override_material(surf) if gyro.get_surface_override_material(surf) != null else src.surface_get_material(surf))
		var pivot := Node3D.new()
		pivot.name = "Gimbal%s" % ("Aft" if half > 0.0 else "Fore")
		pivot.position = Vector3(0, 0, GYRO_Z * half)
		gyro.add_child(pivot)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		pivot.add_child(mi)
		_gimbals.append(pivot)
	gyro.mesh = null


# ------------------------------------------------------------------ where it waits

## Up on the high ground by the first herd (the meadow by the wreck): the highest
## open, fairly level spot a short way out from the middle of their pasture, clear
## of trees and boulders, facing down towards where the game starts.
func _find_home() -> bool:
	if _world == null or _herds == null or not bool(_explorer.get("arrived")):
		return false
	var herds: Array = _herds.get("_herds")
	if herds == null or herds.is_empty():
		return false
	var start: Vector3 = _explorer.global_position
	var home: Vector2 = herds[0]["home"]
	var field: IslandField = _world.call(&"get_field")
	var best := -1e9
	var spot := Vector3.ZERO
	for r in [26.0, 32.0, 38.0, 44.0]:
		for k in 32:
			var a := TAU * float(k) / 32.0
			var p: Vector2 = home + Vector2(cos(a), sin(a)) * r
			if Flora.meadow(p.x, p.y) < 0.85:
				continue
			var s := field.sample(p.x, p.y) if field != null else {}
			if not bool(s.get("on_land", true)) or float(s.get("slope", 0.0)) > 0.2 \
					or float(s.get("flow_weight", 0.0)) > 0.1:
				continue
			var y := _ground(p)
			# Level enough to stand on: the ground a truck's length round about.
			var worst := 0.0
			for j in 6:
				var q := p + Vector2.from_angle(TAU * float(j) / 6.0) * 3.0 * _k() * _k()
				worst = maxf(worst, absf(_ground(q) - y))
			if worst > 0.9 or _cluttered(Vector3(p.x, y, p.y)):
				continue
			var score := y - worst * 2.0
			if score > best:
				best = score
				spot = Vector3(p.x, y, p.y)
	if best <= -1e9:
		# Nowhere clear: the middle of the meadow itself.
		spot = Vector3(home.x, _ground(home), home.y)
	var face := Vector3(start.x - spot.x, 0.0, start.z - spot.z)
	if face.length() < 0.1:
		face = Vector3.FORWARD
	var basis := Basis.looking_at(face.normalized(), Vector3.UP)
	var rest := -(AXLE_Y - WHEEL_R) * model_scale
	_home = Transform3D(basis, spot + Vector3.UP * (rest + 0.15))
	print("[truck] waiting on the hill by the herd at %s, %.0f m up" % [spot, spot.y])
	return true


func _ground(p: Vector2) -> float:
	return float(_world.call(&"height_at", Vector3(p.x, 0.0, p.y), 0.0))


## A tree or a boulder within a truck's length of here.
func _cluttered(at: Vector3) -> bool:
	if _flora == null:
		return false
	if _flora.has_method(&"tree_on") and not (_flora.call(&"tree_on", at + Vector3.UP * 1.5, Vector3.ZERO, 0.0, 5.0 * _k()) as Dictionary).is_empty():
		return true
	if _flora.has_method(&"_rock_layer"):
		var layer: Dictionary = _flora.call(&"_rock_layer")
		for key in layer.get("cache", {}):
			for buf: PackedFloat32Array in layer["cache"][key]:
				for i in range(0, buf.size(), Flora.STRIDE):
					if Vector2(buf[i + 3] - at.x, buf[i + 11] - at.z).length() < 5.5 * _k():
						return true
	return false


# ------------------------------------------------------------------ getting in and out

## Someone at `from` looking along `dir` is close to it and looking at it.
func can_use(from: Vector3, dir: Vector3) -> bool:
	if body == null or _driver or not _placed:
		return false
	if from.distance_to(body.global_position) > 7.5 * _k():
		return false
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * 5.0 * _k())
	if _explorer is CollisionObject3D:
		q.exclude = [(_explorer as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == body


func use_label() -> String:
	return "DRIVE"


func try_use(from: Vector3, dir: Vector3) -> bool:
	if not can_use(from, dir):
		return false
	get_in()
	return true


func get_in() -> void:
	if _driver or body == null:
		return
	_driver = true
	driving = true
	_entered_at = Time.get_ticks_msec()
	body.freeze = false
	_still = 0.0
	_explorer.set("driving", self)
	_explorer.set("velocity", Vector3.ZERO)
	var co := _explorer as CollisionObject3D
	_old_layers = Vector2i(co.collision_layer, co.collision_mask)
	co.collision_layer = 0
	co.collision_mask = 0
	var torch: Light3D = null
	for c in _explorer.get_children():
		if c is Camera3D:
			_cam.fov = (c as Camera3D).fov
			torch = c.get_node_or_null(^"Flashlight") as Light3D
	if torch != null:
		torch.visible = false
	# The view starts where the player was looking from, swung round behind.
	var heading := _heading()
	_cam_heading = atan2(-heading.x, -heading.z)
	_cam_yaw = 0.0
	_cam_pitch = -0.2
	_cam_idle = 10.0
	_cam_pivot = body.global_position + Vector3.UP * chase_height
	_cam.make_current()
	_seat()
	_hint_left = 7.0
	_prompt.visible = false


## Out, onto the ground beside the cab (or wherever round it there is room).
func get_out() -> void:
	if not _driver:
		return
	_driver = false
	driving = false
	_explorer.set("driving", null)
	var co := _explorer as CollisionObject3D
	var b := body.global_transform
	var heading := _heading()
	var right := heading.cross(Vector3.UP).normalized()
	var spot := b.origin + Vector3.UP * 3.0 * _k()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.exclude = [co.get_rid()]
	for off in [-right * 2.4, right * 2.4, heading * 3.6, -heading * 3.6, -right * 3.4, right * 3.4]:
		off *= _k()
		var p: Vector3 = b.origin + off
		p.y = _ground(Vector2(p.x, p.z))
		q.transform = Transform3D(Basis(), p + Vector3.UP * 1.0)
		if get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			spot = p + Vector3.UP * 0.05
			break
	_explorer.global_position = spot
	_explorer.set("velocity", Vector3.ZERO)
	# Solid again only once it is out: made solid in the cab and then moved, the
	# body is swept out through the truck in one step and throws it off the hill.
	_solid_again = 2
	if _explorer.has_method(&"_face"):
		_explorer.call(&"_face", heading)
	for c in _explorer.get_children():
		if c is Camera3D:
			(c as Camera3D).make_current()
	for lamp in _lights:
		lamp.visible = false
	_hint.visible = false


## The driver sits in the cab while it is driven (the cows, the water and the
## rest still know where the player is).
func _seat() -> void:
	_explorer.global_position = body.global_transform * (SEAT * model_scale) - Vector3.UP * 1.6


## The light key, while driving: the headlights.
func lights() -> void:
	var on := _lights.is_empty() or not _lights[0].visible
	for lamp in _lights:
		lamp.visible = on


## The mouse or the right stick, while driving: the view swung round the truck.
func look(by: Vector2) -> void:
	_cam_yaw = wrapf(_cam_yaw - by.x, -PI, PI)
	_cam_pitch = clampf(_cam_pitch - by.y, -1.2, 0.45)
	_cam_idle = 0.0


# ------------------------------------------------------------------ driving

func _heading() -> Vector3:
	var f := -body.global_basis.z
	f.y = 0.0
	if f.length_squared() < 1e-4:
		f = body.global_basis.y * signf(body.global_basis.y.y) if absf(body.global_basis.y.y) < 0.5 else Vector3.FORWARD
		f.y = 0.0
	return f.normalized()


func _physics_process(delta: float) -> void:
	if _solid_again > 0:
		_solid_again -= 1
		if _solid_again == 0 and not _driver:
			(_explorer as CollisionObject3D).collision_layer = _old_layers.x
			(_explorer as CollisionObject3D).collision_mask = _old_layers.y
	if not _placed:
		if _find_home():
			_build(_home)
			_placed = true
			# Not let go until there is ground under it to land on.
			_look_ground = 0.0
		return
	if body.freeze and not _driver:
		if _look_ground >= 0.0:
			_look_ground += delta
			var q := PhysicsRayQueryParameters3D.create(body.global_position, body.global_position + Vector3.DOWN * 6.0)
			q.exclude = [body.get_rid()]
			if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				# Ground: let it settle onto its wheel, then it freezes again.
				_look_ground = -1.0
				body.freeze = false
			return
		return
	var throttle := 0.0
	var steer := 0.0
	var boost := false
	if _driver:
		throttle = Input.get_axis(&"wv_back", &"wv_forward")
		steer = Input.get_axis(&"wv_left", &"wv_right")
		boost = Input.is_action_pressed(&"wv_run")
		if _menus():
			throttle = 0.0
			steer = 0.0
	_wheel(delta)
	_drive(throttle, steer, boost, delta)
	_gyros(throttle, steer, delta)
	if _driver:
		_jump_wait = maxf(_jump_wait - delta, 0.0)
		var pressed := Input.is_action_just_pressed(&"wv_up") and not _menus()
		var lit := false
		if pressed and _grounded and _jump_wait <= 0.0:
			_jump_wait = 0.6
			var kick := (body.global_basis.y + _normal).normalized()
			body.apply_central_impulse(kick * mass * jump_speed)
			lit = true
			_blast()
		# The jets: lit by the jump or by a press in the air, and burning for as
		# long as the button is held and the tank has anything in it.
		if (pressed and not _grounded and _burn > 0.15) or lit:
			_burning = true
		if _burning and (not Input.is_action_pressed(&"wv_up") or _burn <= 0.0 or _menus()):
			_burning = false
		if _burning:
			_burn = maxf(_burn - delta, 0.0)
			body.apply_central_force(body.global_basis.y * mass * _g * burn_lift)
			_jet_dust -= delta
			if _jet_dust <= 0.0:
				_jet_dust = 0.22
				_blast(false)
		elif _grounded:
			_burn = minf(_burn + burn_refill * delta, burn_time)
		_seat()
	else:
		_burning = false
		_burn = minf(_burn + burn_refill * delta, burn_time)
		_settle(delta)
	_show_jets(delta)
	_fell_off(delta)


## The wheel: a sphere swept down the strut from the top of its travel to the
## bottom; where it stops is how far the spring is pressed.
func _wheel(delta: float) -> void:
	var s := model_scale
	var up := body.global_basis.y
	var rest := body.global_transform * Vector3(0, AXLE_Y * s, 0)
	var top := rest + up * bump_travel
	var travel := bump_travel + droop_travel
	_cast.transform = Transform3D(Basis(), top)
	_cast.motion = -up * travel
	_cast.exclude = [body.get_rid(), (_explorer as CollisionObject3D).get_rid()]
	var space := get_world_3d().direct_space_state
	var r := space.cast_motion(_cast)
	_d_was = _d
	if r.is_empty() or (r[0] >= 1.0 and not space.get_rest_info(_cast).is_empty()):
		# Started in the ground (sunk onto the bump stop): as far up as it goes.
		r = [0.0, 0.0]
	if r[0] >= 1.0:
		_grounded = false
		_load = 0.0
		_d = move_toward(_d, -droop_travel, delta * 3.0)
		return
	_grounded = true
	_d = bump_travel - travel * float(r[0])
	var at := top - up * travel * float(r[1])
	_cast.transform = Transform3D(Basis(), at)
	_cast.motion = Vector3.ZERO
	var info := space.get_rest_info(_cast)
	if info.is_empty():
		_normal = up
		_contact = at - up * _sphere.radius
	else:
		_normal = info["normal"]
		_contact = info["point"]
	# The grass and the seaweed lean out of the wheel's way (SHADER_foliage's push_bend).
	RenderingServer.global_shader_parameter_set(&"plant_push_b", Vector4(_contact.x, _contact.y, _contact.z, 1.5 * _k()))
	# The coilover: preloaded to carry the truck at rest, stiffer as it is pressed,
	# a damper on how fast it moves, and the bump stop at the end of the travel.
	var speed := (_d - _d_was) / delta
	# (Damped harder on the way back out than on the way in, as a real shock is,
	# so a landing is soaked up and not thrown back into the air.)
	var push := mass * _g + spring_rate * _d + damping * speed * (1.6 if speed < 0.0 else 1.0)
	if _d > bump_travel * 0.8:
		push += (spring_rate * 8.0 * (_d - bump_travel * 0.8)) * (0.4 if speed < 0.0 else 1.0)
	push = clampf(push, 0.0, mass * _g * 8.0)
	_load = push * maxf(up.dot(_normal), 0.0)
	# The ground pushes back square to itself, at the tyre's contact: leaning, that
	# push is to one side of the weight and tips it further over, as on anything
	# that balances, and it is what a lean into a turn sets against the tyre's
	# grip (at the right lean the two cancel and the gyros have nothing to do).
	body.apply_force(_normal * _load, _contact - body.global_position)


func _drive(throttle: float, steer: float, boost: bool, delta: float) -> void:
	var v := body.linear_velocity
	var fwd := -body.global_basis.z
	var n := _normal if _grounded else body.global_basis.y
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var right := fwd.cross(n).normalized()
	var along := v.dot(fwd)
	var across := v.dot(right)
	var radius := WHEEL_R * model_scale
	if not _grounded:
		# Off the ground the hub spins up (or down) to what the throttle asks.
		_spin_rate = move_toward(_spin_rate, throttle * (boost_speed if boost else top_speed) / radius, delta * 30.0)
		_spin += _spin_rate * delta
		return
	# THE HUB MOTOR: toward the speed asked for, as hard as it is allowed; braking
	# (against the way it is going) harder than driving. Let go, it rolls to a stop
	# under the motor's drag, and parked it holds.
	var want := throttle * (boost_speed if boost else top_speed)
	var limit := boost_accel if boost else drive_accel
	if absf(throttle) < 0.05:
		want = 0.0
		limit = 2.5 if _driver else brake_accel
	elif signf(want) != signf(along) and absf(along) > 0.5:
		limit = brake_accel
	var pull := clampf((want - along) * 4.0, -limit, limit) * mass
	# Sideways, the tyre will not slide unless pushed past its grip.
	var hold := -across * mass * 18.0
	var most := grip * _load
	var total := Vector2(pull, hold)
	if total.length() > most:
		total = total.normalized() * most
	var force := fwd * total.x + right * total.y
	# The push is had at the tyre, below the weight: the lean and the gyros take
	# the tip it gives.
	body.apply_force(force, _contact - body.global_position)
	_spin_rate = along / radius
	_spin += _spin_rate * delta
	_last_pull = total.x / mass
	_last_steer = steer


var _last_pull := 0.0
var _last_steer := 0.0


## THE GYROS: the body's up held to where it should point, and the yaw to the
## turn asked for, within what the flywheels can give.
func _gyros(throttle: float, steer: float, delta: float) -> void:
	var b := body.global_basis
	var up := b.y
	var w := body.angular_velocity
	var heading := _heading()
	var v := body.linear_velocity
	var along := v.dot(heading)
	# The turn asked for: quicker standing still than at speed, and the other way
	# round in reverse, as a car's.
	var rate := lerpf(turn_rate.x, turn_rate.y, clampf(absf(along) / top_speed, 0.0, 1.0))
	# No quicker than a lean of about 45 degrees will balance at this speed (the
	# tyre could hold more; the truck would be on its ear).
	rate = minf(rate, 0.9 * minf(grip, 1.15) * _g / maxf(absf(along), 0.1))
	var yaw_want := -steer * rate * (-1.0 if along < -1.0 else 1.0)
	if not _grounded:
		yaw_want *= 0.6
	var yaw_now := w.dot(Vector3.UP)
	# Where up should be: leaned into the turn and into the pull.
	var want_up := Vector3.UP * _g
	if _grounded:
		var turning := Vector3.UP * yaw_now
		want_up += turning.cross(v)
		want_up += heading * _last_pull * 0.2
	else:
		# In the air: level, tipped a little by the stick to meet a slope.
		want_up += heading * throttle * 2.0
	want_up = want_up.normalized()
	var lean := deg_to_rad(max_lean)
	var tilt := Vector3.UP.angle_to(want_up)
	if tilt > lean:
		want_up = Vector3.UP.slerp(want_up, lean / tilt)
	var axis := up.cross(want_up)
	var sn := axis.length()
	var angle := atan2(sn, up.dot(want_up))
	if sn < 1e-5:
		axis = b.x if angle > 1.0 else Vector3.ZERO
	else:
		axis /= sn
	var k := gyro_rate * gyro_rate
	var c := 2.0 * gyro_damping * gyro_rate
	var tip := w - up * w.dot(up)
	var accel := axis * angle * k - tip * c
	if accel.length() > gyro_authority:
		accel = accel.normalized() * gyro_authority
	var roll_part := accel.dot(heading)
	accel += up * clampf((yaw_want - yaw_now) * 6.0, -8.0, 8.0)
	# Torque = I·α, in the body's own axes.
	var local := b.inverse() * accel
	body.apply_torque(b * (local * body.inertia))
	# The gimbals tip as hard as the gyros are working (and back as they ease off).
	_gimbal = lerpf(_gimbal, clampf(roll_part / gyro_authority, -1.0, 1.0), clampf(delta * 8.0, 0.0, 1.0))


## Nobody in it: once it has come to rest on its wheel, it is frozen where it is.
func _settle(delta: float) -> void:
	if _grounded and body.linear_velocity.length() < 0.15 and body.angular_velocity.length() < 0.15:
		_still += delta
	else:
		_still = 0.0
	var far := _explorer.global_position.distance_to(body.global_position) > 1000.0
	if _still > 1.5 or (far and _grounded):
		body.freeze = true
		_still = 0.0


## Off the island and into the cloud sea: the truck waits on its hill again, and
## whoever was in it goes back to the start as if they had fallen on foot.
func _fell_off(delta: float) -> void:
	var sea := -45.0
	if _sea != null and _sea.has_method(&"surface_y"):
		sea = float(_sea.call(&"surface_y"))
	if body.global_position.y > sea - 4.0:
		_under = 0.0
		return
	_under += delta
	if _under < 1.5:
		return
	_under = 0.0
	if _driver:
		get_out()
		_explorer.emit_signal(&"fell")
		_explorer.call(&"arrive")
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = _home
	body.freeze = true
	_look_ground = 0.0


func _menus() -> bool:
	return Inventory.menu_open or GraphicsMenu.menu_open or EnvironmentMenu.menu_open or OptionsMenu.menu_open


# ------------------------------------------------------------------ the boosters

## A jet at each booster's mouth (two layers: the hot core and the plume round
## it) and one light under the middle for all four.
func _make_jets(on: Node3D, s: float) -> void:
	var tex := load(GLOW) as Texture2D
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var at := Vector3(NOZZLE.x * corner.x, NOZZLE.y, NOZZLE.z * corner.y) * s
		# (size at birth, how fast it leaves, how long it lasts, how many)
		on.add_child(_jet(tex, at, 1.5 * s, 16.0, 0.16, 14, [Color(0.75, 0.9, 1.0, 1.0), Color(0.35, 0.6, 1.0, 0.8), Color(0.2, 0.3, 1.0, 0.0)]))
		on.add_child(_jet(tex, at, 2.6 * s, 11.0, 0.3, 18, [Color(1.0, 0.8, 0.45, 0.7), Color(1.0, 0.42, 0.1, 0.5), Color(0.5, 0.1, 0.02, 0.0)]))
	_jet_light = OmniLight3D.new()
	_jet_light.light_color = Color(1.0, 0.62, 0.3)
	_jet_light.omni_range = 26.0 * s
	_jet_light.light_energy = 0.0
	_jet_light.shadow_enabled = false
	_jet_light.position = Vector3(0, NOZZLE.y - 2.0, 0) * s
	_jet_light.visible = false
	on.add_child(_jet_light)


func _jet(tex: Texture2D, at: Vector3, size: float, speed: float, life: float, amount: int, colours: Array) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.position = at
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.fixed_fps = 0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.DOWN
	m.spread = 5.0
	m.initial_velocity_min = speed * 0.8
	m.initial_velocity_max = speed
	m.gravity = Vector3.ZERO
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = size * 0.12
	m.scale_min = 0.8
	m.scale_max = 1.15
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.3))
	var taper_tex := CurveTexture.new()
	taper_tex.curve = taper
	m.scale_curve = taper_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray(colours)
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	m.color_ramp = ramp
	p.process_material = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = mat
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-4, -8, -4), Vector3(8, 10, 8))
	_jets.append(p)
	return p


func _show_jets(delta: float) -> void:
	if _jet_light == null:
		return
	for p in _jets:
		if p.emitting != _burning:
			p.emitting = _burning
	var want := (5.0 + randf() * 1.5) if _burning else 0.0
	_jet_light.light_energy = lerpf(_jet_light.light_energy, want, clampf(delta * 18.0, 0.0, 1.0))
	_jet_light.visible = _jet_light.light_energy > 0.05
	if _tank != null:
		_tank.value = _burn / maxf(burn_time, 0.01)
		_tank.visible = _driver and _burn < burn_time - 0.01


## What the jets do to the ground under them, if it is near: a ring thrown out
## flat along it and dust (`hard`: the jump's own light-up, with fire in it).
func _blast(hard := true) -> void:
	var from := body.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (WHEEL_R * 2.0 * model_scale + 5.0))
	q.exclude = [body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var at := to_local(hit["position"] as Vector3)
	var k := _k()
	if hard:
		Fx.spawn(self, "shockwave", at + Vector3(0, 0.08, 0), 1.6 * k)
		Fx.spawn(self, "impact_fire", at, 0.45 * k)
	Fx.spawn(self, "dust_cloud", at, (1.5 if hard else 1.0) * k)


# ------------------------------------------------------------------ drawn each frame

func _process(delta: float) -> void:
	if body == null:
		return
	_pose_strut()
	if _driver:
		_chase(delta)
		if Input.is_action_just_pressed(&"wv_attack") and Time.get_ticks_msec() - _entered_at > 400 and not _menus() \
				and _mouse_ready():
			get_out()
			return
		_hint_left -= delta
		_hint.visible = _hint_left > 0.0
	else:
		var cam := get_viewport().get_camera_3d()
		_prompt.visible = cam != null and not DisplayServer.is_touchscreen_available() and not _menus() \
				and can_use(cam.global_position, -cam.global_basis.z)


## A click that only captures the mouse is not a use (as SCRIPT_sword_play.gd).
func _mouse_ready() -> bool:
	return DisplayServer.is_touchscreen_available() or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## The model's strut follows the wheel: the lower tube (and the spindle, hub and
## tyre on it) slides up into the upper, and the spring between them is squeezed
## from below, its top end staying on its seat.
func _pose_strut() -> void:
	if _lower == null:
		return
	var du := _d / _upper_k
	_lower.position.y = _lower_rest + du
	if _spring != null and _spring_top > _spring_bot:
		var bot := _spring_bot + du
		var k := (_spring_top - bot) / (_spring_top - _spring_bot) * _spring_scale
		var box_top := (_spring_top - _spring_pos) / _spring_scale
		_spring.scale.y = k
		_spring.position.y = _spring_top - k * box_top
	if _tire != null:
		_tire.rotation.x = -fmod(_spin, TAU)
	for i in _gimbals.size():
		_gimbals[i].rotation.x = _gimbal * deg_to_rad(24.0) * (1.0 if i == 0 else -1.0)


## The view from behind and above, held off the ground and out of the truck's
## way by a ray from the truck to it.
func _chase(delta: float) -> void:
	var stick := Input.get_vector(&"wv_look_left", &"wv_look_right", &"wv_look_up", &"wv_look_down")
	if stick.length_squared() > 0.0:
		_cam_idle = 0.0
	_cam_idle += delta
	var heading := _heading()
	var speed := body.linear_velocity.length()
	var aim := atan2(-heading.x, -heading.z)
	_cam_heading = lerp_angle(_cam_heading, aim, clampf(delta * 5.0, 0.0, 1.0))
	if speed > 3.0 and _cam_idle > 1.5:
		_cam_yaw = lerp_angle(_cam_yaw, 0.0, clampf(delta * 1.2, 0.0, 1.0))
		_cam_pitch = lerpf(_cam_pitch, -0.2, clampf(delta * 0.8, 0.0, 1.0))
	var target := body.global_position + Vector3.UP * chase_height
	_cam_pivot = _cam_pivot.lerp(target, clampf(delta * 12.0, 0.0, 1.0))
	if _cam_pivot.distance_to(target) > 6.0:
		_cam_pivot = target
	var back := Basis(Vector3.UP, _cam_heading + _cam_yaw) * Basis(Vector3.RIGHT, _cam_pitch) * Vector3.BACK
	var dist := chase_distance + speed * 0.12
	var want := _cam_pivot + back * dist
	var q := PhysicsRayQueryParameters3D.create(_cam_pivot, want)
	q.exclude = [body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = (hit["position"] as Vector3) - back * 0.4
	var floor_y := _ground(Vector2(want.x, want.z)) + 0.6
	want.y = maxf(want.y, floor_y)
	_cam.global_position = want
	_cam.look_at(_cam_pivot + Vector3.UP * 0.3, Vector3.UP)


func _make_prompts() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	var font := load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	_prompt = _label(font, 24, 0.68, 0.74)
	_prompt.text = "DRIVE  [E]"
	layer.add_child(_prompt)
	_hint = _label(font, 20, 0.05, 0.1)
	_hint.text = "STICK  drive and steer      JUMP  jump, hold for jets      RUN  more power      USE  get out" \
			if DisplayServer.is_touchscreen_available() else \
			"W S  drive      A D  steer      SPACE  jump, hold for jets      SHIFT  more power      L  lights      E  get out"
	layer.add_child(_hint)
	# What is left in the boosters' tank, while it is not full.
	_tank = ProgressBar.new()
	_tank.anchor_left = 0.44
	_tank.anchor_right = 0.56
	_tank.anchor_top = 0.115
	_tank.anchor_bottom = 0.125
	_tank.min_value = 0.0
	_tank.max_value = 1.0
	_tank.show_percentage = false
	_tank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.6, 0.2, 0.9)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.45)
	_tank.add_theme_stylebox_override(&"fill", fill)
	_tank.add_theme_stylebox_override(&"background", back)
	_tank.visible = false
	layer.add_child(_tank)


func _label(font: Font, px: int, top: float, bottom: float) -> Label:
	var l := Label.new()
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = top
	l.anchor_bottom = bottom
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", px)
	l.add_theme_color_override(&"font_color", Color(0.8, 0.95, 1.0))
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override(&"outline_size", 6)
	l.visible = false
	return l


## FIRST TIMES (SCRIPT_prewarm.gd): the truck's materials are drawn once behind
## the loading screen, so the first sight of it does not stop the game.
func warm(stage: Node3D) -> void:
	var copy := (load(MODEL) as PackedScene).instantiate() as Node3D
	copy.scale = Vector3.ONE * 0.03
	stage.add_child(copy)
	DetailLayer.apply(copy, 0.5)
	# The jets, lit once, and what they throw up off the ground.
	var jets := Node3D.new()
	stage.add_child(jets)
	var mine := _jets.duplicate()
	var my_light := _jet_light
	_jets.clear()
	_make_jets(jets, 0.03)
	for p in _jets:
		p.emitting = true
	_jets.assign(mine)
	_jet_light = my_light
	for effect in ["shockwave", "impact_fire", "dust_cloud"]:
		Fx.spawn(stage, effect, Vector3.ZERO, 0.03)
