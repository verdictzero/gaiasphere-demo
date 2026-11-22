class_name CowHerds
extends Node3D

# HERDS OF FLOATING COW CUBES.
#
# A cow here is a cube, a metre and a half across, that hangs in the air a
# little off the ground and drifts about in a herd. Each herd keeps to its own
# pasture, in a meadow (Flora.meadow), never in the wood: every so often the whole herd drifts to a new spot in it, and between
# times each cow does what its animations say it can:
#
#   Move_Float     drifting to where it is going
#   Idle_Float     hanging there
#   Idle_Breathe   hanging there, breathing
#   Eat            tipping down to the grass for a mouthful (it sinks to it first)
#   Chew, Chomp    working on the mouthful, back upright
#   Moo            mooing (`mooed` is sent, and `moo_sound` played if there is one)
#
# A cow you walk right up to runs: away from you, wherever that is, out of the
# meadow and into the wood if need be, and again if you follow. Let alone, it
# always comes back to its herd in the meadow, and only there does it graze.
# They are solid: you can lean on one. Herds far from the player are hidden and stand still.

signal mooed(cow: Node3D)

@export var world_path: NodePath = ^"../GaiaSphere"
@export var explorer_path: NodePath = ^"../Explorer"
@export var herds := 6
@export var herd_size := Vector2i(4, 7)
## Herds are put down between these distances of where the game starts, metres.
@export var nearest := 55.0
@export var farthest := 420.0
## How far a herd strays from the middle of its pasture.
@export var roam := 60.0
## Seconds a herd stays put before drifting on.
@export var stay := Vector2(25.0, 60.0)
## Metres of air under a cow, and under one that is eating.
@export var hover := 0.55
@export var graze_hover := 0.06
## A cow's size against the model's two metres.
@export var size := 0.75
@export var speed := 1.7
## Herds further off than this are not drawn or moved.
@export var view_range := 260.0
## Played at the cow when it moos, once there is one to play.
@export var moo_sound: AudioStream

const MODEL := "res://assets/cow/cow.glb"
const LOOPED := ["Idle_Float", "Move_Float", "Idle_Breathe", "Chew"]

var _world: Node
var _explorer: Node3D
var _field: IslandField
var _herds: Array = []        # each {"home", "centre", "wait", "cows": [...]}
var _rng := RandomNumberGenerator.new()
var _placed := false


func _ready() -> void:
	_world = get_node_or_null(world_path)
	_explorer = get_node_or_null(explorer_path)
	_rng.seed = 74113
	if OS.has_feature("mobile"):
		herds = mini(herds, 4)


func _ground(at: Vector3, fallback: float) -> float:
	return float(_world.call(&"height_at", at, fallback))


## Is this somewhere a cow could hang: a meadow (Flora.meadow: the open ground
## among the trees, at least `open` of the way into one), on land, fairly level,
## not river or mere? Cows keep out of the wood.
func _pasture(x: float, z: float, open := 0.9) -> bool:
	if Flora.meadow(x, z) < open:
		return false
	var s := _field.sample(x, z)
	if not bool(s.get("on_land", false)):
		return false
	return float(s.get("slope", 1.0)) < 0.22 and float(s.get("flow_weight", 0.0)) < 0.15 \
			and String(s.get("surface", "")) != "rock"


func _place(start: Vector3) -> void:
	_field = _world.call(&"get_field")
	var scene := load(MODEL) as PackedScene
	var homes: Array = []
	for attempt in 2500:
		if homes.size() >= herds:
			break
		var ang := _rng.randf() * TAU
		# (The first herd is always close by, so there are cows to be found at once.)
		# (For a while the first herd is looked for close by, so there are cows to be
		# found at once, if there is a meadow that near.)
		var far := lerpf(nearest, farthest, sqrt(_rng.randf())) if (not homes.is_empty() or attempt > 250) \
				else _rng.randf_range(nearest, nearest + 90.0)
		var p := Vector2(start.x + cos(ang) * far, start.z + sin(ang) * far)
		# Well inside a meadow: open ground here and all round, not its ragged edge.
		var inside := _pasture(p.x, p.y, 0.97)
		for k in 6:
			var round := Vector2(cos(TAU * float(k) / 6.0), sin(TAU * float(k) / 6.0)) * 28.0
			inside = inside and Flora.meadow(p.x + round.x, p.y + round.y) > 0.8
		if not inside:
			continue
		var crowded := false
		for h in homes:
			if (h as Vector2).distance_to(p) < 90.0:
				crowded = true
		if not crowded:
			homes.append(p)
	for home in homes:
		var herd := {"home": home, "centre": home, "wait": _rng.randf_range(stay.x, stay.y) * 0.5, "cows": [], "shown": true}
		var count := _rng.randi_range(herd_size.x, herd_size.y)
		for i in count:
			var holder := Node3D.new()
			holder.name = "Cow"
			var model: Node3D = scene.instantiate()
			model.scale = Vector3.ONE * size * _rng.randf_range(0.88, 1.12)
			holder.add_child(model)
			var body := AnimatableBody3D.new()
			body.sync_to_physics = false
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3.ONE * 2.0 * model.scale.x
			cs.shape = box
			body.add_child(cs)
			holder.add_child(body)
			add_child(holder)
			var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			for n in LOOPED:
				if player.has_animation(n):
					player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			var ang := TAU * float(i) / float(count) + _rng.randf_range(-0.4, 0.4)
			var at: Vector2 = (home as Vector2) + Vector2(cos(ang), sin(ang)) * _rng.randf_range(2.5, 8.0)
			var ground := _ground(Vector3(at.x, start.y, at.y), start.y)
			var cow := {"node": holder, "player": player, "half": model.scale.x, "state": "", "t": 0.0,
				"target": Vector2.ZERO, "yaw": _rng.randf() * TAU, "ground": ground, "ground_t": _rng.randf() * 0.2,
				"air": hover, "want_air": hover, "bites": 0, "now": ""}
			holder.position = Vector3(at.x, ground + hover + float(cow["half"]), at.y)
			holder.rotation.y = float(cow["yaw"])
			_rest(cow)
			(cow["player"] as AnimationPlayer).seek(_rng.randf() * 3.0, true)       # not all in step
			(herd["cows"] as Array).append(cow)
		_herds.append(herd)
	print("[cows] %d herds, %d cows" % [_herds.size(), _count()])


func _count() -> int:
	var n := 0
	for herd in _herds:
		n += (herd["cows"] as Array).size()
	return n


func _play(cow: Dictionary, anim: String) -> void:
	if String(cow["now"]) == anim:
		return
	cow["now"] = anim
	(cow["player"] as AnimationPlayer).play(anim, 0.35)


## Arrived, or done with what it was doing: what next.
func _rest(cow: Dictionary) -> void:
	var pick := _rng.randf()
	cow["want_air"] = hover
	if pick < 0.36:
		cow["state"] = "graze"
		cow["want_air"] = graze_hover
		cow["bites"] = _rng.randi_range(1, 3)
		cow["t"] = 0.7                       # sinking to the grass
		_play(cow, "Idle_Float")
	elif pick < 0.45:
		cow["state"] = "moo"
		cow["t"] = 2.6
		_play(cow, "Moo")
		mooed.emit(cow["node"])
		if moo_sound != null:
			var voice := AudioStreamPlayer3D.new()
			voice.stream = moo_sound
			voice.unit_size = 12.0
			voice.pitch_scale = _rng.randf_range(0.9, 1.1)
			(cow["node"] as Node3D).add_child(voice)
			voice.play()
			voice.finished.connect(voice.queue_free)
	elif pick < 0.7:
		cow["state"] = "idle"
		cow["t"] = _rng.randf_range(4.0, 8.0)
		_play(cow, "Idle_Breathe")
	else:
		cow["state"] = "idle"
		cow["t"] = _rng.randf_range(4.0, 9.0)
		_play(cow, "Idle_Float")


func _go(cow: Dictionary, to: Vector2) -> void:
	# Never into the trees of its own accord: a spot outside the meadow is given
	# up for where it is.
	if Flora.meadow(to.x, to.y) < 0.6:
		var node: Node3D = cow["node"]
		to = Vector2(node.position.x, node.position.z)
	cow["state"] = "move"
	cow["target"] = to
	cow["want_air"] = hover
	_play(cow, "Move_Float")
	(cow["player"] as AnimationPlayer).speed_scale = 1.0


## RUNNING AWAY is the one thing that takes a cow out of its meadow: off it goes,
## fast, wherever away is (into the wood if that is the way), so long as it is
## dry land. It comes back when it is let alone (see `_cow_step`).
func _flee(cow: Dictionary, from: Vector2) -> void:
	var node: Node3D = cow["node"]
	var at := Vector2(node.position.x, node.position.z)
	var away := (at - from).normalized() if at.distance_to(from) > 0.05 else Vector2(1, 0)
	var to := at
	for attempt in 5:
		var tried := at + away.rotated(_rng.randf_range(-0.7, 0.7) * (1.0 + 0.4 * float(attempt))) * _rng.randf_range(9.0, 15.0)
		var s := _field.sample(tried.x, tried.y)
		if bool(s.get("on_land", false)) and float(s.get("flow_weight", 0.0)) < 0.3 and float(s.get("slope", 1.0)) < 0.45:
			to = tried
			break
	cow["state"] = "flee"
	cow["target"] = to
	cow["want_air"] = hover
	_play(cow, "Move_Float")
	(cow["player"] as AnimationPlayer).speed_scale = 1.8


## Back to the herd in the meadow, to a place of its own round the middle of it.
func _home(cow: Dictionary, herd: Dictionary) -> void:
	var a := _rng.randf() * TAU
	var centre: Vector2 = herd["centre"]
	var to := centre + Vector2(cos(a), sin(a)) * _rng.randf_range(2.5, 8.5)
	cow["state"] = "move"
	cow["target"] = to if Flora.meadow(to.x, to.y) >= 0.6 else centre
	cow["want_air"] = hover
	_play(cow, "Move_Float")
	(cow["player"] as AnimationPlayer).speed_scale = 1.0


func _process(delta: float) -> void:
	if _world == null or _explorer == null:
		return
	if not _placed:
		if not bool(_explorer.get("arrived")) or not _world.has_method(&"get_field"):
			return
		_placed = true
		_place(_explorer.global_position)
		return
	delta = minf(delta, 0.1)
	var me := _explorer.global_position
	for herd in _herds:
		var centre: Vector2 = herd["centre"]
		var shown := Vector2(me.x, me.z).distance_to(centre) < view_range
		if shown != bool(herd["shown"]):
			herd["shown"] = shown
			for cow in herd["cows"]:
				(cow["node"] as Node3D).visible = shown
				(cow["player"] as AnimationPlayer).active = shown
		if not shown:
			continue
		# The herd drifts on, all of it, to somewhere else in its pasture.
		herd["wait"] = float(herd["wait"]) - delta
		if float(herd["wait"]) <= 0.0:
			herd["wait"] = _rng.randf_range(stay.x, stay.y)
			var ang := _rng.randf() * TAU
			var to: Vector2 = (herd["home"] as Vector2) + Vector2(cos(ang), sin(ang)) * roam * sqrt(_rng.randf())
			if _pasture(to.x, to.y):
				herd["centre"] = to
				var cows: Array = herd["cows"]
				for i in cows.size():
					var a := TAU * float(i) / float(cows.size()) + _rng.randf_range(-0.5, 0.5)
					_go(cows[i], to + Vector2(cos(a), sin(a)) * _rng.randf_range(2.5, 8.5))
		for cow in herd["cows"]:
			_cow_step(cow, herd, delta, me)


func _cow_step(cow: Dictionary, herd: Dictionary, delta: float, me: Vector3) -> void:
	var node: Node3D = cow["node"]
	var at := Vector2(node.position.x, node.position.z)
	var state := String(cow["state"])
	var near_me := (at - Vector2(me.x, me.z)).length() < 2.6 + float(cow["half"]) and absf(me.y - node.position.y) < 3.5
	if state == "move" or state == "flee":
		var to: Vector2 = cow["target"]
		var gap := to - at
		var running := state == "flee"
		if near_me and not running:
			_flee(cow, Vector2(me.x, me.z))
		elif gap.length() < 0.5:
			(cow["player"] as AnimationPlayer).speed_scale = 1.0
			if running and (at - Vector2(me.x, me.z)).length() < 7.0:
				_flee(cow, Vector2(me.x, me.z))          # still being chased
			elif Flora.meadow(at.x, at.y) < 0.6 or at.distance_to(herd["centre"]) > roam * 0.5:
				_home(cow, herd)                          # let alone: back to the meadow and the herd
			else:
				_rest(cow)
		else:
			# It turns to face the way it is going (its face is its +z) and goes that way.
			var want := atan2(gap.x, gap.y)
			cow["yaw"] = lerp_angle(float(cow["yaw"]), want, minf(delta * (4.5 if running else 2.2), 1.0))
			var facing := Vector2(sin(float(cow["yaw"])), cos(float(cow["yaw"])))
			var pace := speed * (2.4 if running else 1.0) * clampf(facing.dot(gap.normalized()), 0.15, 1.0) \
					* minf(gap.length() / 1.5 + 0.25, 1.0)
			at += facing * pace * delta
	else:
		cow["t"] = float(cow["t"]) - delta
		# Someone is right on top of it: it runs.
		if near_me:
			_flee(cow, Vector2(me.x, me.z))
		elif float(cow["t"]) <= 0.0:
			match state:
				"graze":
					# Down at the grass: a mouthful, then the working of it, then
					# another or enough.
					match String(cow["now"]):
						"Eat":
							var chomp := _rng.randf() < 0.35
							_play(cow, "Chomp" if chomp else "Chew")
							cow["t"] = 1.0 * float(_rng.randi_range(2, 3)) if chomp else 1.6 * float(_rng.randi_range(2, 4))
							cow["now"] = "working"
							cow["want_air"] = hover
						"working":
							cow["bites"] = int(cow["bites"]) - 1
							if int(cow["bites"]) <= 0:
								_rest(cow)
							else:
								cow["want_air"] = graze_hover
								cow["t"] = 0.7
								_play(cow, "Idle_Float")
						_:
							_play(cow, "Eat")
							cow["t"] = 2.4
				_:
					# Now and then a cow wanders a few steps on its own within the herd.
					if _rng.randf() < 0.3:
						var a := _rng.randf() * TAU
						_go(cow, (herd["centre"] as Vector2) + Vector2(cos(a), sin(a)) * _rng.randf_range(2.0, 9.0))
					else:
						_rest(cow)
	# Not through each other.
	for other in herd["cows"]:
		if other == cow:
			continue
		var op: Vector3 = (other["node"] as Node3D).position
		var apart := at - Vector2(op.x, op.z)
		var room := (float(cow["half"]) + float(other["half"])) * 1.25
		if apart.length() < room and apart.length() > 0.01:
			at += apart.normalized() * (room - apart.length()) * minf(delta * 3.0, 1.0)
	# Over the ground, which is asked after a few times a second, not every frame.
	cow["ground_t"] = float(cow["ground_t"]) - delta
	if float(cow["ground_t"]) <= 0.0:
		cow["ground_t"] = 0.2
		cow["ground"] = _ground(Vector3(at.x, node.position.y, at.y), float(cow["ground"]))
	cow["air"] = lerpf(float(cow["air"]), float(cow["want_air"]), minf(delta * 2.5, 1.0))
	var y := lerpf(node.position.y, float(cow["ground"]) + float(cow["air"]) + float(cow["half"]), minf(delta * 4.0, 1.0))
	node.position = Vector3(at.x, y, at.y)
	node.rotation.y = float(cow["yaw"])
