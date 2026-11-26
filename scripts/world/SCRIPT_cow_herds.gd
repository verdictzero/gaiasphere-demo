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
# NO TWO COWS ARE ALIKE, AND NONE DOES THE SAME THING TWICE RUNNING. Each has a
# nature of its own, drawn when it is made (`_nature`): how hungry, how restless,
# how nosy, how fond of company, how idle, how quick on its feet, how deep its
# voice. What it does next is drawn by lot with those as the weights (`_rest`),
# so a greedy one mostly eats and a restless one mostly does not stay put:
#
#   graze    as above, for as many mouthfuls as it is hungry
#   nap      settles right down onto the grass and breathes, slowly, for a good
#            while (mostly the idle ones, and all of them more at night)
#   look     rises well up off the ground and turns about for a look round
#   visit    drifts over to another of the herd, faces it and moos; the other
#            turns and answers
#   stray    wanders off some way on its own to graze there, and comes back
#   romp     tears about in a few quick dashes; a restless neighbour may join in
#   watch    turns to keep its face on you when you come by (the nosy ones from
#            further off), and a really nosy one drifts up for a closer look
#   moo, and hanging there one way or the other
#
# THE HERD DOES NOT MOVE AS ONE: when it drifts on, each cow leaves when it gets
# round to it, the idle ones last, and now and then one stays behind eating and
# has to hurry to catch up. A herd settles down together at night.
# A truck driven at them makes them scatter, whatever else they think of you.
#
# COWS TAKE NO NOTICE OF YOU (beyond that) until one of their herd is cut down
# (SCRIPT_cow_slicing.gd). Then the rest run: away from you, wherever that is,
# out of the meadow and into the wood if need be, and again whenever you come
# near, for a minute and a half. Let alone, they always come back to the herd
# in the meadow, and only there do they graze. A herd that has lost cows is made
# up to its number again overnight.
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
## Seconds a herd stays afraid of you after one of it has been cut down.
@export var wary_for := 90.0
## The hour of the night by which a herd that has lost cows is whole again.
@export var back_by := 5.0
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
var _hour_was := -1.0
var _islet := Vector2.ZERO
var _islet_reach := 0.0
var _truck := Vector3.INF     # where a truck being driven fast is, or INF


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
	# (The islet in the mere is deep wood whatever the meadows' map says of it.)
	if Vector2(x, z).distance_to(_islet) < _islet_reach:
		return false
	var s := _field.sample(x, z)
	if not bool(s.get("on_land", false)):
		return false
	return float(s.get("slope", 1.0)) < 0.22 and float(s.get("flow_weight", 0.0)) < 0.15 \
			and String(s.get("surface", "")) != "rock"


func _place(start: Vector3) -> void:
	_field = _world.call(&"get_field")
	_islet = SwordStone.site(_field)
	var islet: Variant = _field.get("flow_lagoon_islet")
	_islet_reach = float(islet) * 1.05 if islet != null else 0.0
	var scene := load(MODEL) as PackedScene
	var homes: Array = []
	# The meadow by the wreck always has a herd in it.
	var glade := Flora.glade()
	if glade.z > 0.0 and _pasture(glade.x, glade.y):
		homes.append(Vector2(glade.x, glade.y))
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
		herd["size"] = count
		for i in count:
			var ang := TAU * float(i) / float(count) + _rng.randf_range(-0.4, 0.4)
			_add_cow(herd, (home as Vector2) + Vector2(cos(ang), sin(ang)) * _rng.randf_range(2.5, 8.0), start.y)
		_herds.append(herd)
	print("[cows] %d herds, %d cows" % [_herds.size(), _count()])


# ------------------------------------------------------------------ butchery

## The cow whose body a swing landed on (`body` is what the ray struck), or {}.
func cow_of(body: Object) -> Dictionary:
	if body == null or not body.has_meta(&"cow"):
		return {}
	var node: Node3D = body.get_meta(&"cow")
	for herd in _herds:
		for cow in herd["cows"]:
			if cow["node"] == node:
				return {"herd": herd, "cow": cow}
	return {}


## Take a cow out of its herd for good (SCRIPT_cow_slicing.gd is about to cut it
## up): returns its skin as it hangs (the mesh's arrays, its material, and where
## it is), and frees the cow. The rest of the herd runs from `from`.
func butcher(found: Dictionary, from: Vector3) -> Dictionary:
	var herd: Dictionary = found["herd"]
	var cow: Dictionary = found["cow"]
	var node: Node3D = cow["node"]
	var mi: MeshInstance3D = node.find_children("*", "MeshInstance3D", true, false)[0]
	var out := {"arrays": mi.mesh.surface_get_arrays(0), "material": mi.mesh.surface_get_material(0),
		"transform": mi.global_transform}
	(herd["cows"] as Array).erase(cow)
	herd["lost"] = int(herd.get("lost", 0)) + 1
	node.queue_free()
	herd["wary"] = wary_for
	for other in herd["cows"]:
		_flee(other, Vector2(from.x, from.z))
	return out


## A HERD THAT HAS LOST COWS IS WHOLE AGAIN BY MORNING: when the clock comes round
## to `back_by` (five, before it is light), every herd is made up to the number
## it began with, the new ones hanging among the old, and none of them afraid.
func _overnight() -> void:
	var enviro := get_node_or_null(^"../Enviro")
	if enviro == null:
		return
	var hour := float(enviro.get("hour"))
	var was := _hour_was
	_hour_was = hour
	if was < 0.0:
		return
	# Has the clock passed `back_by` since it was last looked at (going forward, and not by a jump of half a day)?
	var gone := fposmod(hour - was, 24.0)
	var to_go := fposmod(back_by - was, 24.0)
	if gone <= 0.0 or gone > 6.0 or to_go > gone or to_go <= 0.0:
		return
	var made := 0
	for herd in _herds:
		herd["wary"] = 0.0
		herd["lost"] = 0
		var centre: Vector2 = herd["centre"]
		while (herd["cows"] as Array).size() < int(herd["size"]):
			var ang := _rng.randf() * TAU
			var at := centre + Vector2(cos(ang), sin(ang)) * _rng.randf_range(2.5, 8.0)
			_add_cow(herd, at, _ground(Vector3(at.x, 0.0, at.y), 0.0))
			made += 1
		if not bool(herd["shown"]):
			for cow in herd["cows"]:
				(cow["node"] as Node3D).visible = false
				(cow["player"] as AnimationPlayer).active = false
	if made > 0:
		print("[cows] %d cows back in their herds overnight" % made)


## One more cow in a herd, hanging over `at` (`about` is roughly how high the ground is there).
func _add_cow(herd: Dictionary, at: Vector2, about: float) -> void:
	var scene := load(MODEL) as PackedScene
	var holder := Node3D.new()
	holder.name = "Cow"
	var model: Node3D = scene.instantiate()
	model.scale = Vector3.ONE * size * _rng.randf_range(0.88, 1.12)
	holder.add_child(model)
	var body := AnimatableBody3D.new()
	body.set_meta(&"cow", holder)
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
	var ground := _ground(Vector3(at.x, about, at.y), about)
	var cow := {"node": holder, "player": player, "half": model.scale.x, "state": "", "t": 0.0,
		"target": Vector2.ZERO, "yaw": _rng.randf() * TAU, "ground": ground, "ground_t": _rng.randf() * 0.2,
		"air": hover, "want_air": hover, "bites": 0, "now": ""}
	cow.merge(_nature())
	holder.position = Vector3(at.x, ground + hover + float(cow["half"]), at.y)
	holder.rotation.y = float(cow["yaw"])
	_rest(cow, herd)
	(cow["player"] as AnimationPlayer).seek(_rng.randf() * 3.0, true)       # not all in step
	(herd["cows"] as Array).append(cow)


## A cow's nature: drawn once, and what its choices are weighted by ever after.
func _nature() -> Dictionary:
	return {
		"hungry": _rng.randf_range(0.2, 1.0), "restless": _rng.randf(), "nosy": _rng.randf(),
		"friendly": _rng.randf(), "idle": _rng.randf(), "quick": _rng.randf_range(0.75, 1.3),
		"voice": _rng.randf_range(0.82, 1.18), "seen_t": _rng.randf_range(0.0, 15.0),
	}


## One of `lots` (name -> weight), by lot.
func _draw(lots: Dictionary) -> String:
	var sum := 0.0
	for k in lots:
		sum += maxf(float(lots[k]), 0.0)
	var at := _rng.randf() * sum
	for k in lots:
		at -= maxf(float(lots[k]), 0.0)
		if at <= 0.0:
			return String(k)
	return String(lots.keys()[0])


## Is it night (the herd settles)?
func _night() -> bool:
	return _hour_was >= 0.0 and (_hour_was > 21.0 or _hour_was < 5.0)


func _moo(cow: Dictionary) -> void:
	cow["state"] = "moo"
	cow["t"] = 2.6
	cow["want_air"] = hover
	_play(cow, "Moo")
	mooed.emit(cow["node"])
	if moo_sound != null:
		var voice := AudioStreamPlayer3D.new()
		voice.stream = moo_sound
		voice.unit_size = 12.0
		voice.pitch_scale = float(cow["voice"]) * _rng.randf_range(0.96, 1.04)
		(cow["node"] as Node3D).add_child(voice)
		voice.play()
		voice.finished.connect(voice.queue_free)


## Turn to face a point (from where it hangs), over the next moments.
func _face(cow: Dictionary, to: Vector2) -> void:
	var node: Node3D = cow["node"]
	var gap := to - Vector2(node.position.x, node.position.z)
	if gap.length() > 0.05:
		cow["face"] = atan2(gap.x, gap.y)


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


## Arrived, or done with what it was doing: what next. By lot, weighted by the
## cow's own nature, the hour, and where it has got to.
func _rest(cow: Dictionary, herd: Dictionary) -> void:
	var node: Node3D = cow["node"]
	var at := Vector2(node.position.x, node.position.z)
	var centre: Vector2 = herd.get("centre", at)
	cow["want_air"] = hover
	cow["pace"] = 1.0
	cow["spin"] = 0.0
	cow.erase("face")
	cow.erase("face_me")
	cow.erase("then")
	(cow["player"] as AnimationPlayer).speed_scale = 1.0
	# (Off on its own for long enough: mostly it thinks of the others.)
	if at.distance_to(centre) > 13.0 and _rng.randf() < 0.6:
		_home(cow, herd)
		return
	var night := _night()
	var hungry := float(cow["hungry"])
	var restless := float(cow["restless"])
	var idle := float(cow["idle"])
	var friendly := float(cow["friendly"])
	var others := (herd["cows"] as Array).size() > 1
	var last := String(cow.get("did", ""))
	var lots := {
		"graze": (0.15 + 0.5 * hungry) * (0.35 if night else 1.0),
		"nap": (0.03 + 0.14 * idle) * (5.0 if night else 1.0),
		"look": 0.05 + 0.1 * restless,
		"visit": (0.03 + 0.14 * friendly) if others else 0.0,
		"stray": (0.02 + 0.12 * restless * (1.0 - friendly * 0.6)) * (0.2 if night else 1.0),
		"romp": 0.0 if night else 0.01 + 0.07 * restless * (1.0 - idle),
		"moo": 0.04 + 0.07 * friendly,
		"wander": 0.08 + 0.18 * restless,
		"breathe": 0.14 + 0.1 * idle,
		"float": 0.14,
	}
	# (Not the same thing twice running, as a rule.)
	if lots.has(last):
		lots[last] = float(lots[last]) * 0.25
	var pick := _draw(lots)
	cow["did"] = pick
	match pick:
		"graze":
			cow["state"] = "graze"
			cow["want_air"] = graze_hover
			cow["bites"] = _rng.randi_range(1, 2 + int(round(hungry * 3.0)))
			cow["t"] = 0.7                       # sinking to the grass
			_play(cow, "Idle_Float")
		"nap":
			cow["state"] = "nap"
			cow["want_air"] = 0.02
			cow["t"] = _rng.randf_range(12.0, 30.0) * (2.0 if night else 1.0)
			_play(cow, "Idle_Breathe")
			(cow["player"] as AnimationPlayer).speed_scale = 0.55
		"look":
			cow["state"] = "look"
			cow["want_air"] = hover * _rng.randf_range(2.2, 3.6)
			cow["t"] = _rng.randf_range(3.5, 7.0)
			cow["spin"] = _rng.randf_range(0.35, 0.8) * (1.0 if _rng.randf() < 0.5 else -1.0)
			_play(cow, "Idle_Float")
		"visit":
			var cows: Array = herd["cows"]
			var mate: Dictionary = cows[_rng.randi_range(0, cows.size() - 1)]
			if is_same(mate, cow):
				for other: Dictionary in cows:
					if not is_same(other, cow):
						mate = other
						break
			var mp: Vector3 = (mate["node"] as Node3D).position
			var from := (at - Vector2(mp.x, mp.z))
			from = from.normalized() if from.length() > 0.1 else Vector2(1, 0)
			_go(cow, Vector2(mp.x, mp.z) + from * (float(cow["half"]) + float(mate["half"])) * 1.7)
			cow["then"] = "greet"
			cow["mate"] = mate["node"]
		"stray":
			var a := _rng.randf() * TAU
			_go(cow, centre + Vector2(cos(a), sin(a)) * _rng.randf_range(12.0, 26.0))
			cow["pace"] = 0.7
			cow["then"] = "graze"
		"romp":
			_romp(cow, _rng.randi_range(3, 5))
			# One that cannot keep still either may go with it.
			for other: Dictionary in herd["cows"]:
				if not is_same(other, cow) and String(other["state"]) in ["idle", "look"] \
						and _rng.randf() < 0.45 * float(other["restless"]):
					_romp(other, _rng.randi_range(2, 4))
		"moo":
			_moo(cow)
		"wander":
			var a := _rng.randf() * TAU
			_go(cow, centre + Vector2(cos(a), sin(a)) * _rng.randf_range(2.0, 9.0))
			cow["pace"] = _rng.randf_range(0.6, 1.0)
		"breathe":
			cow["state"] = "idle"
			cow["t"] = _rng.randf_range(3.0, 9.0)
			_play(cow, "Idle_Breathe")
		_:
			cow["state"] = "idle"
			cow["t"] = _rng.randf_range(3.0, 10.0)
			cow["want_air"] = hover * _rng.randf_range(0.8, 1.5)
			_play(cow, "Idle_Float")


## A dash to somewhere near, at speed, with `legs` more to come after it.
func _romp(cow: Dictionary, legs: int) -> void:
	var node: Node3D = cow["node"]
	var at := Vector2(node.position.x, node.position.z)
	var a := _rng.randf() * TAU
	_go(cow, at + Vector2(cos(a), sin(a)) * _rng.randf_range(5.0, 11.0))
	cow["pace"] = 2.3
	cow["legs"] = legs - 1
	cow["then"] = "romp"
	cow["want_air"] = hover * 1.6
	(cow["player"] as AnimationPlayer).speed_scale = 1.7


func _go(cow: Dictionary, to: Vector2) -> void:
	# Never into the trees of its own accord: a spot outside the meadow is given
	# up for where it is.
	if Flora.meadow(to.x, to.y) < 0.6 or to.distance_to(_islet) < _islet_reach:
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
	cow["spin"] = 0.0
	cow.erase("face")
	cow.erase("face_me")
	cow.erase("then")
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
	_overnight()
	var me := _explorer.global_position
	# A truck coming at them at any speed (SCRIPT_uni_truck.gd).
	_truck = Vector3.INF
	var truck := get_node_or_null(^"../UniTruck")
	if truck != null and truck.get("body") != null:
		var body := truck.get("body") as RigidBody3D
		if body != null and not body.freeze and body.linear_velocity.length() > 4.0:
			_truck = body.global_position
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
		herd["wary"] = maxf(float(herd.get("wary", 0.0)) - delta, 0.0)
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
					# Each in its own time: the idle ones last, and now and then one
					# stays behind and has to hurry after the rest.
					var cow: Dictionary = cows[i]
					var late := _rng.randf() < 0.12
					cow["leave_to"] = to + Vector2(cos(a), sin(a)) * _rng.randf_range(2.5, 8.5)
					cow["leave_in"] = _rng.randf_range(11.0, 20.0) if late else _rng.randf_range(0.0, 3.0 + 6.0 * float(cow["idle"]))
					cow["leave_pace"] = 1.9 if late else _rng.randf_range(0.85, 1.1)
		for cow in herd["cows"]:
			_cow_step(cow, herd, delta, me)


func _cow_step(cow: Dictionary, herd: Dictionary, delta: float, me: Vector3) -> void:
	var node: Node3D = cow["node"]
	var at := Vector2(node.position.x, node.position.z)
	var state := String(cow["state"])
	# COWS ARE NOT AFRAID OF YOU until one of them has been cut down: you can walk
	# among a herd that has never been attacked. After that, for a while, any of
	# that herd you come near runs (and further off than before: they are watching).
	var wary := float(herd.get("wary", 0.0)) > 0.0
	var near_me := wary and (at - Vector2(me.x, me.z)).length() < 5.5 + float(cow["half"]) and absf(me.y - node.position.y) < 3.5
	var me2 := Vector2(me.x, me.z)
	var threat := me2
	# A truck bearing down on it: it gets out of the way, wary or not.
	if _truck != Vector3.INF and (at - Vector2(_truck.x, _truck.z)).length() < 11.0:
		near_me = true
		threat = Vector2(_truck.x, _truck.z)
	cow["seen_t"] = float(cow["seen_t"]) - delta
	# The herd is drifting on, and this one's time to go has come.
	if cow.has("leave_to"):
		cow["leave_in"] = float(cow["leave_in"]) - delta
		if float(cow["leave_in"]) <= 0.0 and state != "flee":
			var to_go: Vector2 = cow["leave_to"]
			var hurry := float(cow["leave_pace"])
			cow.erase("leave_to")
			cow["spin"] = 0.0
			cow.erase("face")
			cow.erase("face_me")
			cow.erase("then")
			_go(cow, to_go)
			cow["pace"] = hurry
			(cow["player"] as AnimationPlayer).speed_scale = 1.5 if hurry > 1.5 else 1.0
			state = "move"
	if state == "move" or state == "flee":
		var to: Vector2 = cow["target"]
		var gap := to - at
		var running := state == "flee"
		# (Close enough is enough: another cow may be hanging right where it meant to
		# go, and one that has been trying for a while gives up and stays where it is.)
		cow["going"] = float(cow.get("going", 0.0)) + delta
		var there := gap.length() < 0.9 or (float(cow["going"]) > 14.0 and not running)
		if near_me and not running:
			cow["going"] = 0.0
			_flee(cow, threat)
		elif there:
			cow["going"] = 0.0
			(cow["player"] as AnimationPlayer).speed_scale = 1.0
			var then := String(cow.get("then", ""))
			cow.erase("then")
			if running and (at - threat).length() < 7.0 and near_me:
				_flee(cow, threat)                        # still being chased
			elif running and (at - me2).length() < 7.0 and wary:
				_flee(cow, me2)
			elif Flora.meadow(at.x, at.y) < 0.6 or at.distance_to(herd["centre"]) > roam * 0.5:
				_home(cow, herd)                          # let alone: back to the meadow and the herd
			elif then == "romp" and int(cow.get("legs", 0)) > 0:
				_romp(cow, int(cow["legs"]))              # and off again
			elif then == "greet" and is_instance_valid(cow.get("mate")):
				# Face to face with the one it came over to: a moo, and an answer.
				var mate := {}
				for other: Dictionary in herd["cows"]:
					if other["node"] == cow["mate"]:
						mate = other
				cow.erase("mate")
				_moo(cow)
				if mate.is_empty():
					return
				var mp: Vector3 = (mate["node"] as Node3D).position
				_face(cow, Vector2(mp.x, mp.z))
				if String(mate["state"]) in ["idle", "look", "graze", "nap"]:
					mate["state"] = "answer"
					mate["t"] = _rng.randf_range(1.0, 2.2)
					mate["want_air"] = hover
					mate["spin"] = 0.0
					(mate["player"] as AnimationPlayer).speed_scale = 1.0
					_play(mate, "Idle_Float")
					_face(mate, at)
			elif then == "graze":
				cow["state"] = "graze"
				cow["want_air"] = graze_hover
				cow["bites"] = _rng.randi_range(2, 5)
				cow["t"] = 0.7
				_play(cow, "Idle_Float")
			elif then == "watch":
				cow["state"] = "watch"
				cow["t"] = _rng.randf_range(4.0, 9.0)
				cow["face_me"] = true
				_play(cow, "Idle_Breathe")
			else:
				_rest(cow, herd)
		else:
			# It turns to face the way it is going (its face is its +z) and goes that way.
			var want := atan2(gap.x, gap.y)
			cow["yaw"] = lerp_angle(float(cow["yaw"]), want, minf(delta * (4.5 if running else 2.2), 1.0))
			var facing := Vector2(sin(float(cow["yaw"])), cos(float(cow["yaw"])))
			var pace := speed * (2.4 if running else float(cow.get("pace", 1.0)) * float(cow["quick"])) * clampf(facing.dot(gap.normalized()), 0.15, 1.0) \
					* minf(gap.length() / 1.5 + 0.25, 1.0)
			at += facing * pace * delta
	else:
		cow["t"] = float(cow["t"]) - delta
		# Turning on the spot: for a look round, to face another, to keep its face on you.
		if bool(cow.get("face_me", false)):
			_face(cow, me2)
		if cow.has("face"):
			cow["yaw"] = lerp_angle(float(cow["yaw"]), float(cow["face"]), minf(delta * 2.4, 1.0))
		elif float(cow.get("spin", 0.0)) != 0.0:
			cow["yaw"] = float(cow["yaw"]) + float(cow["spin"]) * delta
		var away_me := (at - me2).length()
		# Someone is right on top of it: it runs.
		if near_me:
			(cow["player"] as AnimationPlayer).speed_scale = 1.0
			_flee(cow, threat)
		elif not wary and state in ["idle", "look", "graze"] and float(cow["seen_t"]) <= 0.0 \
				and away_me < 5.0 + 11.0 * float(cow["nosy"]) and away_me > 2.5 and absf(me.y - node.position.y) < 4.0:
			# YOU HAVE COME BY, and it has noticed: it stops what it is at and
			# watches you, and the nosiest come over for a closer look first.
			cow["seen_t"] = _rng.randf_range(18.0, 50.0)
			cow["spin"] = 0.0
			cow["want_air"] = hover * _rng.randf_range(1.0, 1.7)
			if float(cow["nosy"]) > 0.65 and away_me > 6.0 and _rng.randf() < 0.7:
				_go(cow, me2 + (at - me2).normalized() * _rng.randf_range(3.2, 4.5))
				cow["pace"] = 0.75
				cow["then"] = "watch"
			else:
				cow["state"] = "watch"
				cow["t"] = _rng.randf_range(3.0, 8.0)
				cow["face_me"] = true
				_play(cow, "Idle_Breathe" if _rng.randf() < 0.5 else "Idle_Float")
		elif float(cow["t"]) <= 0.0:
			match state:
				"answer":
					_moo(cow)
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
								_rest(cow, herd)
							else:
								cow["want_air"] = graze_hover
								cow["t"] = 0.7
								_play(cow, "Idle_Float")
						_:
							_play(cow, "Eat")
							cow["t"] = 2.4
				_:
					_rest(cow, herd)
	# Not through each other.
	for other in herd["cows"]:
		if is_same(other, cow):
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
