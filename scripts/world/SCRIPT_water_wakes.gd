class_name WaterWakes
extends Node3D

# THE WAKES: what a vehicle does to the water (the user: "vehicle --> water
# splashing rippling interaction (performant retro aesthetic)"; and later: "water
# ripples need more randomized sub ripples, clusters of ripples, higher frequency
# especially when driving through water at high speed, driving water particles need
# to be smaller, more randomized, more detailed; hover jet water particles should
# use point particle fountains same water particles as car, as proximity to water
# based vapor cloud particles"). Stood up by `RiverWater` as its child, so it is in
# the water's frame (the field's) and a rebase carries it, and what it throws, with
# the water.
#
# EVERY PHYSICS TICK, every vehicle (`map_vehicle`, a VehicleBody3D: the buggy, the
# VTOL) within `reach` of the eye is asked two things.
#
#   ITS WHEELS. Each wheel whose bottom is under the water's level
#   (`RiverWater.world_level_at` over its centre) is in it, and moving through it:
#     * GOING IN fast (falling `entry_fall` m/s or more as it meets the water, a
#       jump landed in a river) it SPLASHES: a ring as strong as the fall is hard,
#       a cluster round it, and a burst of droplets thrown up and out;
#     * PLOUGHING ON, the leading wheels (those ahead of the body's middle, the
#       way it is going) set rings MORE OFTEN THE FASTER IT GOES (`wake_rate`, a
#       second; never closer than `wake_spacing` metres apart), each one a CLUSTER:
#       the ring, and one to three smaller ones round and behind it (more at
#       speed), some a moment late, so the wake is a churn and not a chain;
#     * every wheel throws SPRAY up and back off its tyre (`spray_rate` a second
#       flat out): mostly droplets of a few centimetres, a few bigger, some STREAKS
#       drawn out along the way they fly at speed, every one with its own size,
#       speed, spread and life;
#     * and the leading wheels throw a BOW SHEET out sideways, either side of
#       them, the faster the more (`bow_rate`).
#   Its speed is read off where it was last tick, not the body's velocity, so a
#   parked body moved by hand splashes as one driven does, and a jump no tick
#   could make (a teleport, a rebase) splashes not at all: not the wheel's, nor
#   the body's, whose wheels stay where the physics last had them for the tick it
#   jumps, and would splash there.
#
#   ITS JETS (a vehicle with `nozzles()`, the VTOL). Each nozzle's exhaust, as hard
#   as it is pushing, is followed down from the nozzle to the water's level; where
#   it meets the water within `downwash_reach`, the water is beaten:
#     * a ring cluster every `downwash_gap` seconds under one jet and the next
#       under the next, each as strong as its jet pushes and as near as it is;
#     * a FOUNTAIN of droplets, the same droplets the wheels throw, up and out from
#       the point the jet strikes, as many as it is near and hard (`fountain_rate`);
#     * and VAPOUR, clouds of it billowing out low over the water from each, as
#       much and as big as the jet is NEAR THE WATER (`vapour_reach`): thick
#       skimming it, thin at half that, none higher.
#
# AND WHAT FALLS BACK IN rings the water where it lands: a droplet of any size
# hitting the water sets a ring of its own, weak and quick, up to `drip_rate` a
# second, so a spray's footprint is a pepper of small rings.
#
# THE PARTICLES are a pool of `MAX_DROPS`, one MultiMesh, one draw
# (SHADER_water_splash.gdshader: unblended, pixel-cut, dissolving by a dither),
# three kinds: a DROPLET, round; a STREAK, drawn out along its flight; VAPOUR, big,
# thin and growing. They fly on the CPU here: a droplet or a streak falls
# (`gravity`), vapour drifts, slows (`vapour_drag`) and lifts a little, and all are
# gone when their life is or when they fall back through the water they came off.
# Only the live ones are drawn (`visible_instance_count`) inside a box round them;
# with none, nothing is.
#
# NOTHING HERE NAMES AN AUTOLOAD, nor the vehicles' classes: a vehicle is a
# VehicleBody3D in `map_vehicle`, and a jet craft is one with `nozzles()`.

## Metres from the eye a vehicle is watched out to.
@export var reach := 260.0

@export_group("Wheels")
## Metres a second a wheel must be falling as it meets the water to splash.
@export var entry_fall := 3.0
## The droplets in a splash at `entry_fall`, and more by this many for each metre
## a second it falls faster, up to `MAX_BURST`.
@export var entry_drops := 30
@export var entry_drops_per := 5.0
## A leading wheel's ring clusters a second: the first slow, the second at
## `spray_full`; and never closer together than `wake_spacing` metres.
@export var wake_rate := Vector2(3.0, 14.0)
@export var wake_spacing := 0.5
## The rings round each wake ring, fewest and most (the most at speed), and how
## far round it they go, metres.
@export var cluster := Vector2i(1, 3)
@export var cluster_spread := 1.3
## Metres a second (through the water, or round its rim) at which a wheel throws
## the most spray, and droplets a second it throws then.
@export var spray_full := 18.0
@export var spray_rate := 90.0
## Droplets a second a leading wheel throws out sideways at `spray_full`.
@export var bow_rate := 40.0
## The share of the spray drawn out into streaks at `spray_full`.
@export var streak_share := 0.35

@export_group("Jets")
## Metres down a jet's exhaust the water is beaten out to.
@export var downwash_reach := 22.0
## Seconds between the ring clusters the jets beat on the water, each under the
## next jet.
@export var downwash_gap := 0.12
## Droplets a second thrown up off the water under a jet pushing flat out, at the
## water.
@export var fountain_rate := 70.0
## Vapour clouds a second off the water under a jet pushing flat out, at it; and
## the metres down its exhaust the vapour is raised out to, falling off as the
## square of the way there.
@export var vapour_rate := 16.0
@export var vapour_reach := 14.0

@export_group("Particles")
@export var gravity := 22.0
## How fast vapour slows, a share a second, and lifts, m/s².
@export var vapour_drag := 1.6
@export var vapour_lift := 0.7
## A droplet's size, metres, least and most: most are small (`_drop_size`).
@export var drop_size := Vector2(0.05, 0.2)
## A vapour cloud's size, metres, when it is made; it grows to more than twice it.
@export var vapour_size := Vector2(1.8, 4.2)
## Rings a second at most where droplets fall back in, and the size a droplet must
## be to make one.
@export var drip_rate := 16.0
@export var drip_size := 0.08

const MAX_DROPS := 512
const MAX_BURST := 96
## The kinds of particle (the shader's INSTANCE_CUSTOM.z).
const DROP := 0
const STREAK := 1
const VAPOUR := 2
## A streak is drawn as long as this many seconds of its flight.
const STREAK_TIME := 0.035
## A move a tick faster than this is a teleport, not a splash, m/s.
const TELEPORT_SPEED := 90.0
const SHADER := preload("res://shaders/SHADER_water_splash.gdshader")

var _water: RiverWater = null
var _mmi: MultiMeshInstance3D = null
var _mm: MultiMesh = null
var _buf := PackedFloat32Array()
## The live particles, packed from the first, in this node's frame.
var _n := 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _floor := PackedFloat32Array()   ## the water they came off, this node's frame
var _roll := PackedFloat32Array()
var _kind := PackedByteArray()
## Per vehicle (instance id): {wheels, last, at, wet, run, spray, bow, jet_wait,
## jet_turn, vapour, fount}.
var _seen := {}
## Ring clusters' late rings, waiting: [seconds to wait, world point, strength].
var _late: Array = []
## Rings where droplets fall back in: the ones that may be set now (`drip_rate`).
var _drips := 0.0
## For the test and the HUD of it: the rings set (droplets' rings apart), the
## splashes made, the particles thrown, since it was stood up.
var rings_set := 0
var drip_rings := 0
var splashes := 0
var thrown := 0


func _ready() -> void:
	_water = get_parent() as RiverWater
	_pos.resize(MAX_DROPS)
	_vel.resize(MAX_DROPS)
	_age.resize(MAX_DROPS)
	_life.resize(MAX_DROPS)
	_size.resize(MAX_DROPS)
	_floor.resize(MAX_DROPS)
	_roll.resize(MAX_DROPS)
	_kind.resize(MAX_DROPS)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_mm.mesh = q
	_mm.instance_count = MAX_DROPS
	_mm.visible_instance_count = 0
	_buf.resize(MAX_DROPS * 16)
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Droplets"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	if _water != null and _water.material != null:
		for k: StringName in [&"foam_color", &"color_steps"]:
			var v: Variant = _water.material.get_shader_parameter(k)
			if v != null:
				mat.set_shader_parameter(k, v)
		var sh: Variant = _water.material.get_shader_parameter(&"shallow_color")
		if sh != null:
			mat.set_shader_parameter(&"water_color", sh)
	_mmi.material_override = mat
	add_child(_mmi)


## The particles alive, for the test.
func live_drops() -> int:
	return _n


## A particle's place in the world, its kind (and whether it is vapour, "mist"),
## its size, for the test.
func drop_at(i: int) -> Dictionary:
	return {"pos": to_global(_pos[i]), "vel": global_basis * _vel[i], "mist": _kind[i] == VAPOUR,
			"kind": int(_kind[i]), "size": _size[i], "age": _age[i], "life": _life[i]}


## A SPLASH at world point `at` on the water, `strength` 0 to 1: a ring cluster as
## strong and `drops` droplets thrown up and out round it, the fastest drawn out
## into streaks. What a wheel landing in a river makes; anything else that drops in
## may ask for one.
func splash(at: Vector3, strength: float, drops: int) -> void:
	var level := _water.world_level_at(at) if _water != null else NAN
	if is_nan(level):
		return
	var p := Vector3(at.x, level, at.z)
	_cluster(p, Vector3.ZERO, Vector3.RIGHT, strength, 1.0)
	splashes += 1
	var up := lerpf(5.0, 11.0, clampf(strength, 0.0, 1.0))
	for i in mini(drops, MAX_BURST):
		var a := randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a))
		var lift := randf_range(0.5, 1.25)
		var v := out * randf_range(1.0, 5.0) * (0.6 + strength) + Vector3.UP * up * lift
		_throw(p + out * randf_range(0.1, 1.0), v, randf_range(0.5, 1.3), _drop_size(), level,
				STREAK if lift > 1.0 and randf() < 0.5 else DROP)


func _physics_process(delta: float) -> void:
	if _water == null or delta <= 0.0:
		return
	_drips = minf(_drips + drip_rate * delta, 4.0)
	_fire_late(delta)
	var cam := get_viewport().get_camera_3d()
	var keep := {}
	for v: Node in get_tree().get_nodes_in_group(&"map_vehicle"):
		var body := v as VehicleBody3D
		if body == null or not body.is_inside_tree():
			continue
		if cam != null and body.global_position.distance_squared_to(cam.global_position) > reach * reach:
			continue
		var id := body.get_instance_id()
		keep[id] = true
		var st: Dictionary = _seen.get(id, {})
		if st.is_empty():
			st = _first_sight(body)
			_seen[id] = st
		_wheels(body, st, delta)
		if body.has_method(&"nozzles"):
			_jets(body, st, delta)
	for id: int in _seen.keys():
		if not keep.has(id):
			_seen.erase(id)


func _process(delta: float) -> void:
	if _n == 0:
		return
	var o := global_position
	var i := _n - 1
	while i >= 0:
		_age[i] += delta
		var v := _vel[i]
		if _kind[i] == VAPOUR:
			v *= maxf(1.0 - vapour_drag * delta, 0.0)
			v.y += vapour_lift * delta
		else:
			v.y -= gravity * delta
		_vel[i] = v
		_pos[i] += v * delta
		if v.y < 0.0 and _pos[i].y < _floor[i] - 0.1 and _kind[i] != VAPOUR:
			# Back in the water: a ring where it lands, if it is big enough and
			# the water has rings to spare.
			if _size[i] >= drip_size and _drips >= 1.0:
				var at := _pos[i] + o
				if _water.ripple(Vector3(at.x, _floor[i] + o.y, at.z), randf_range(0.06, 0.12) + _size[i] * 0.4):
					_drips -= 1.0
					drip_rings += 1
			_kill(i)
		elif _age[i] >= _life[i]:
			_kill(i)
		i -= 1
	_mm.visible_instance_count = _n
	if _n == 0:
		return
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for k in _n:
		var p := _pos[k]
		var u := _age[k] / _life[k]
		var kind := _kind[k]
		var s := _size[k] * (1.0 + 1.3 * u if kind == VAPOUR else 1.0)
		var b := k * 16
		# A streak carries its flight in its second column, which the shader
		# draws it out along; the others are square, `s` across.
		var y := _vel[k] * STREAK_TIME if kind == STREAK else Vector3(0.0, s, 0.0)
		_buf[b] = s
		_buf[b + 1] = y.x
		_buf[b + 2] = 0.0
		_buf[b + 3] = p.x
		_buf[b + 4] = 0.0
		_buf[b + 5] = y.y
		_buf[b + 6] = 0.0
		_buf[b + 7] = p.y
		_buf[b + 8] = 0.0
		_buf[b + 9] = y.z
		_buf[b + 10] = s
		_buf[b + 11] = p.z
		_buf[b + 12] = u
		_buf[b + 13] = _roll[k]
		_buf[b + 14] = float(kind)
		_buf[b + 15] = 0.0
		var r := maxf(s, y.length())
		lo = lo.min(p - Vector3.ONE * r)
		hi = hi.max(p + Vector3.ONE * r)
	_mm.buffer = _buf
	_mmi.custom_aabb = AABB(lo, hi - lo)


# --- the vehicles ----------------------------------------------------------------

func _first_sight(body: VehicleBody3D) -> Dictionary:
	var wheels: Array[VehicleWheel3D] = []
	for w in body.find_children("*", "VehicleWheel3D", true, false):
		wheels.append(w as VehicleWheel3D)
	var n := wheels.size()
	var last := PackedVector3Array()
	last.resize(n)
	for k in n:
		last[k] = wheels[k].global_position
	var zeros := PackedFloat32Array()
	zeros.resize(n)
	var wet := PackedByteArray()
	wet.resize(n)
	var jets := PackedFloat32Array()
	jets.resize(8)
	return {"wheels": wheels, "last": last, "at": body.global_position, "wet": wet, "run": zeros.duplicate(),
			"spray": zeros.duplicate(), "bow": zeros.duplicate(), "jet_wait": 0.0, "jet_turn": 0,
			"vapour": jets.duplicate(), "fount": jets.duplicate()}


func _wheels(body: VehicleBody3D, st: Dictionary, delta: float) -> void:
	var wheels: Array[VehicleWheel3D] = st["wheels"]
	var last: PackedVector3Array = st["last"]
	var wet: PackedByteArray = st["wet"]
	var run: PackedFloat32Array = st["run"]
	var spray: PackedFloat32Array = st["spray"]
	var bow: PackedFloat32Array = st["bow"]
	var mid := body.global_position
	var jumped := mid.distance_to(st["at"]) > TELEPORT_SPEED * delta
	st["at"] = mid
	for k in wheels.size():
		var w := wheels[k]
		if not is_instance_valid(w):
			continue
		var c := w.global_position
		var pv := (c - last[k]) / delta
		last[k] = c
		if jumped or pv.length() > TELEPORT_SPEED:
			wet[k] = 0
			continue
		var level := _water.world_level_at(c)
		var depth := level - (c.y - w.wheel_radius) if not is_nan(level) else -1.0
		if depth <= 0.0:
			wet[k] = 0
			run[k] = 0.0
			continue
		var at := Vector3(c.x, level, c.z)
		var flat := Vector2(pv.x, pv.z)
		var speed := flat.length()
		var fwd := Vector3(flat.x, 0.0, flat.y) / speed if speed > 0.5 else Vector3.ZERO
		var lat := Vector3(-fwd.z, 0.0, fwd.x)
		var go := clampf(speed / maxf(spray_full, 0.1), 0.0, 1.0)
		if wet[k] == 0:
			wet[k] = 1
			var fall := -pv.y
			if fall >= entry_fall:
				var s := clampf(fall / 12.0, 0.45, 1.0)
				splash(at, s, entry_drops + int((fall - entry_fall) * entry_drops_per))
		# The wake, off the leading wheels: ring clusters, more often the faster.
		var lead := speed > 0.5 and (c - mid).dot(fwd) > 0.0
		if lead:
			run[k] += minf(lerpf(wake_rate.x, wake_rate.y, go), speed / maxf(wake_spacing, 0.05)) * delta
			if run[k] >= 1.0:
				run[k] = fmod(run[k], 1.0)
				var s := clampf(0.25 + speed / 50.0, 0.25, 0.6) \
						* clampf(depth / maxf(w.wheel_radius, 0.1) + 0.5, 0.7, 1.0) * randf_range(0.85, 1.1)
				_cluster(at + lat * randf_range(-0.25, 0.25) - fwd * randf_range(0.0, 0.3), -fwd, lat, s, go)
		else:
			run[k] = 0.0
		var rim := absf(w.get_rpm()) / 60.0 * TAU * w.wheel_radius
		var amt := clampf(maxf(speed, rim) / maxf(spray_full, 0.1), 0.0, 1.0)
		if amt < 0.08:
			continue
		# The spray, up and back off the tyre: a fan, every droplet its own.
		spray[k] += spray_rate * amt * delta
		var r := w.wheel_radius
		while spray[k] >= 1.0:
			spray[k] -= 1.0
			var sd := lat * randf_range(-0.6, 0.6) + Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15))
			var v := pv * randf_range(0.15, 0.5) + (-fwd * randf_range(0.2, 1.2) + Vector3.UP * randf_range(0.45, 1.4) + sd) \
					* (2.0 + maxf(speed, rim) * 0.32) * randf_range(0.6, 1.35)
			_throw(at - fwd * r * randf_range(0.3, 0.9) + sd * r, v, randf_range(0.35, 1.0), _drop_size() * lerpf(0.85, 1.15, amt),
					level, STREAK if randf() < streak_share * amt else DROP)
		# The bow sheet, out sideways either side of a leading wheel.
		if lead and speed > 3.0:
			bow[k] += bow_rate * go * delta
			while bow[k] >= 1.0:
				bow[k] -= 1.0
				var out := lat * (1.0 if randf() < 0.5 else -1.0)
				var v := (out * randf_range(0.6, 1.1) + Vector3.UP * randf_range(0.35, 0.9) + fwd * randf_range(0.0, 0.35)) \
						* (1.5 + speed * 0.22) * randf_range(0.7, 1.25)
				_throw(at + fwd * r * 0.5 + out * r * randf_range(0.4, 0.9), v, randf_range(0.3, 0.8), _drop_size(), level,
						STREAK if randf() < 0.5 else DROP)


func _jets(body: VehicleBody3D, st: Dictionary, delta: float) -> void:
	var noz: Array = body.call(&"nozzles")
	var top := float(body.get(&"nozzle_max")) if body.get(&"nozzle_max") != null else 1.0
	var b := body.global_basis
	var vapour: PackedFloat32Array = st["vapour"]
	var fount: PackedFloat32Array = st["fount"]
	var hits: Array[Vector4] = []   ## where each jet meets the water, and how hard
	for j in noz.size():
		var nz: Dictionary = noz[j]
		var f := clampf(float(nz["thrust"]) / maxf(top, 1.0), 0.0, 1.0)
		if f < 0.05:
			continue
		var th := float(nz["theta"])
		var from := body.global_position + b * (nz["pos"] as Vector3)
		var ex := -(b * Vector3(0.0, cos(th), sin(th)))
		if ex.y > -0.25:
			continue
		var level := _water.world_level_at(from)
		if is_nan(level) or from.y < level:
			continue
		var t := (from.y - level) / -ex.y
		if t > downwash_reach:
			continue
		var hit := from + ex * t
		if is_nan(_water.world_level_at(hit)):
			continue
		hit.y = level
		var near := f * (1.0 - t / downwash_reach)
		hits.append(Vector4(hit.x, hit.y, hit.z, near))
		if j >= vapour.size():
			continue
		var flat_ex := Vector3(ex.x, 0.0, ex.z)
		# The fountain: droplets up and out from where the jet strikes.
		fount[j] += fountain_rate * near * delta
		while fount[j] >= 1.0:
			fount[j] -= 1.0
			var a := randf() * TAU
			var out := Vector3(cos(a), 0.0, sin(a))
			var lift := randf_range(0.4, 1.2)
			var v := (out * randf_range(2.0, 7.0) + flat_ex * 2.0) * (0.5 + near) + Vector3.UP * randf_range(3.0, 9.5) * lift * (0.5 + near)
			_throw(hit + out * randf_range(0.2, 1.4), v, randf_range(0.5, 1.2), _drop_size(), level,
					STREAK if lift > 0.9 and randf() < 0.5 else DROP)
		# The vapour: as much and as big as the jet is near the water.
		var close := clampf(1.0 - t / maxf(vapour_reach, 0.1), 0.0, 1.0)
		close *= close * f
		vapour[j] += vapour_rate * close * delta
		while vapour[j] >= 1.0:
			vapour[j] -= 1.0
			var a := randf() * TAU
			var out := Vector3(cos(a), 0.0, sin(a))
			var v := (out + flat_ex * 0.6) * randf_range(3.0, 10.0) * (0.4 + close) + Vector3.UP * randf_range(0.5, 2.2)
			_throw(hit + out * randf_range(0.5, 2.5) + Vector3.UP * 0.4, v, randf_range(1.2, 2.6),
					randf_range(vapour_size.x, vapour_size.y) * (0.7 + 0.6 * close), level, VAPOUR)
	st["jet_wait"] = float(st["jet_wait"]) - delta
	if not hits.is_empty() and float(st["jet_wait"]) <= 0.0:
		st["jet_wait"] = downwash_gap
		var turn := int(st["jet_turn"]) % hits.size()
		st["jet_turn"] = turn + 1
		var h := hits[turn]
		_cluster(Vector3(h.x, h.y, h.z), Vector3.ZERO, Vector3.RIGHT, clampf(0.35 + h.w, 0.35, 1.0), h.w)


# --- the rings ---------------------------------------------------------------------

# A RING CLUSTER at world point `at` on the water: the ring, `strength`, and round
# it `cluster` more (the most when `busy` is 1), weaker, thrown round it and toward
# `back` (behind a wheel, or nowhere in particular), some of them a moment late.
func _cluster(at: Vector3, back: Vector3, side: Vector3, strength: float, busy: float) -> void:
	if _water.ripple(at, strength):
		rings_set += 1
	var more := cluster.x + int(round(clampf(busy, 0.0, 1.0) * float(cluster.y - cluster.x) * randf()))
	for i in more:
		var p := at + back * randf_range(0.2, 1.4) + side * randf_range(-1.0, 1.0) * cluster_spread \
				+ Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
		var s := strength * randf_range(0.25, 0.55)
		var wait := randf_range(0.0, 0.18)
		if wait < 0.03:
			if _water.ripple(p, s):
				rings_set += 1
		else:
			_late.append([wait, p, s])


# The late rings whose wait is up.
func _fire_late(delta: float) -> void:
	var i := _late.size() - 1
	while i >= 0:
		var e: Array = _late[i]
		e[0] = float(e[0]) - delta
		if float(e[0]) <= 0.0:
			if _water.ripple(e[1], e[2]):
				rings_set += 1
			_late.remove_at(i)
		i -= 1


# --- the particles ----------------------------------------------------------------

# Most small, a few big: a droplet's size skewed to the small end of `drop_size`.
func _drop_size() -> float:
	var u := randf()
	return lerpf(drop_size.x, drop_size.y, u * u * u)


# One particle into the pool at world `at`, moving `vel`, for `life` seconds, `size`
# metres across, of `kind`, gone if it falls back through world height `level`.
# Dropped when the pool is full: the ones in the air are enough.
func _throw(at: Vector3, vel: Vector3, life: float, size: float, level: float, kind: int) -> void:
	if _n >= MAX_DROPS:
		return
	var i := _n
	_n += 1
	var o := global_position
	_pos[i] = at - o
	_vel[i] = vel
	_age[i] = 0.0
	_life[i] = life
	_size[i] = size
	_floor[i] = level - o.y
	_roll[i] = randf()
	_kind[i] = kind
	thrown += 1


# The last live particle into slot `i`.
func _kill(i: int) -> void:
	_n -= 1
	if i == _n:
		return
	_pos[i] = _pos[_n]
	_vel[i] = _vel[_n]
	_age[i] = _age[_n]
	_life[i] = _life[_n]
	_size[i] = _size[_n]
	_floor[i] = _floor[_n]
	_roll[i] = _roll[_n]
	_kind[i] = _kind[_n]
