class_name Cooking
extends Node3D

# COOKING FIRES. A fire is made in the bag (logs and stone) and set down where
# you point with it in hand: a fire box of charred wood with a pot hung over it
# from a frame (assets/cooking/cooking_fire.glb, sized to `fire_width` across). It burns from the moment it is set down.
#
# TO COOK: stand at a fire, look at it, and use it. A cut of raw beef goes from
# the bag into the pot (up to `places` at once) and cooks for `cook_seconds`:
# nothing of it is shown but a ring over the fire for each cut, filling as it
# goes. Then it comes back to the bag cooked. A fire you look at with no raw beef on you
# is not worked: the swing in your hand goes ahead.
#
# The axe takes a fire down again (as it does anything built) and the fire goes
# back in the bag; whatever was still cooking on it falls out raw.

const MODEL := "res://assets/cooking/cooking_fire.glb"
const ITEM := "campfire"

@export var explorer_path: NodePath = ^"../Explorer"
@export var inventory_path: NodePath = ^"../Inventory"
## How wide a fire is across its ring of stones, metres.
@export var fire_width := 2.3
## How far off one can be set down, and worked.
@export var reach := 4.2
## Seconds a cut takes to cook.
@export var cook_seconds := 7.0
## Cuts a fire takes at once.
@export var places := 3

var _explorer: Node3D
var _bag: Inventory
var _scene: PackedScene
var _scale := 1.0
var _foot := 0.0              # how far the model's lowest point is under its origin, its own units
var _fire_at := Vector3.ZERO  # where the flames go, in a fire's own frame
var _top := 1.0               # how tall a fire stands, metres
var _ghost: Node3D
var _ghost_ok: StandardMaterial3D
var _ghost_no: StandardMaterial3D
var _plan := {}
var _fires: Array = []        # each {"node", "cooking": [[seconds left, sprite]...]}
var _ring: ShaderMaterial
var _ring_quad: QuadMesh


func _ready() -> void:
	_explorer = get_node_or_null(explorer_path)
	_bag = get_node_or_null(inventory_path) as Inventory
	_scene = load(MODEL) as PackedScene
	# The model is some thirteen of its own units tall: measured, and cut to size.
	var probe: Node3D = _scene.instantiate()
	var box := AABB()
	var first := true
	for mi in probe.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t := m.transform
		var up := m.get_parent()
		while up != null and up != probe and up is Node3D:
			t = (up as Node3D).transform * t
			up = up.get_parent()
		var b: AABB = t * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var fire_node := probe.find_child("putFireHere", true, false) as Node3D
	_scale = fire_width / maxf(maxf(box.size.x, box.size.z), 0.001)
	_foot = box.position.y
	var mid := box.get_center()
	_fire_at = Vector3(0.0, ((fire_node.position.y if fire_node != null else mid.y * 0.3) - _foot) * _scale, 0.0)
	_top = box.size.y * _scale
	probe.free()
	_ghost_ok = Building._ghost_material(Color(0.5, 0.85, 1.0, 0.42))
	_ghost_no = Building._ghost_material(Color(1.0, 0.25, 0.2, 0.42))
	_ring = ShaderMaterial.new()
	_ring.shader = load("res://shaders/SHADER_progress_ring.gdshader")
	_ring_quad = QuadMesh.new()
	_ring_quad.size = Vector2(0.38, 0.38)
	_ring_quad.material = _ring
	add_to_group(&"usable")
	add_to_group(Prewarm.GROUP)
	print("[cooking] a fire is %.2f m across and %.2f m tall" % [fire_width, box.size.y * _scale])


## FIRST TIMES (SCRIPT_prewarm.gd): a fire burning, the ghost of one being
## placed, and a ring of progress.
func warm(stage: Node3D) -> void:
	var at := stage.global_position
	var fire := _model()
	stage.add_child(fire)
	fire.global_transform = Transform3D(stage.global_basis.scaled(Vector3.ONE * 0.4), at - stage.global_basis.y * 0.5)
	Fx.spawn(fire, "campfire_small", _fire_at, 0.75 * fire_width / 1.15)
	var ghost := _model()
	stage.add_child(ghost)
	ghost.global_transform = Transform3D(stage.global_basis.scaled(Vector3.ONE * 0.3), at + stage.global_basis.x * 0.8)
	for mi in ghost.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _ghost_ok
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_quad
	stage.add_child(ring)
	ring.global_position = at + stage.global_basis.y * 0.3


## A fire's model, sized and stood on its own lowest point.
func _model() -> Node3D:
	var model: Node3D = _scene.instantiate()
	model.scale = Vector3.ONE * _scale
	model.position = Vector3(0.0, -_foot * _scale, 0.0)
	return model


## The fire in hand, if that is what is in hand.
func holding() -> bool:
	return _bag != null and _bag.slots[_bag.selected] != null and String(_bag.slots[_bag.selected][0]) == ITEM


func _menus() -> bool:
	return Inventory.menu_open or GraphicsMenu.menu_open or EnvironmentMenu.menu_open or OptionsMenu.menu_open or MapMenu.menu_open or UniTruck.driving


# ------------------------------------------------------------------ setting one down

## Where a fire would go for someone at `from` looking along `dir`: {} if nowhere,
## else "at" (where it stands) and "free" (whether it may).
func aim(from: Vector3, dir: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * reach)
	if _explorer is CollisionObject3D:
		q.exclude = [(_explorer as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var at: Vector3 = hit["position"]
	var level: bool = (hit["normal"] as Vector3).y > 0.75
	var clear := true
	for fire in _fires:
		if ((fire["node"] as Node3D).global_position - at).length() < fire_width * 1.2:
			clear = false
	# Not in the water: nothing burns there.
	var deep: Variant = _explorer.get(&"deep") if _explorer != null else null
	var facing := atan2(-dir.x, -dir.z)
	return {"at": Transform3D(Basis(Vector3.UP, facing), at), "free": level and clear and not (deep is bool and deep)}


func set_down(at: Transform3D) -> Node3D:
	var fire := StaticBody3D.new()
	fire.name = "CookingFire"
	fire.add_child(_model())
	var ring := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = fire_width * 0.42
	shape.height = 0.22 * fire_width
	ring.shape = shape
	ring.position = Vector3(0, 0.11 * fire_width, 0)
	fire.add_child(ring)
	add_child(fire)
	fire.global_transform = at
	Fx.spawn(fire, "campfire_small", _fire_at, 0.75 * fire_width / 1.15)
	_fires.append({"node": fire, "cooking": []})
	for grower in [get_node_or_null(^"../Flora"), get_node_or_null(^"../BerryBushes")]:
		if grower != null:
			grower.call(&"clear_ground", at, Vector2(fire_width * 0.6, fire_width * 0.6))
	return fire


# ------------------------------------------------------------------ working one

func _fire_before(from: Vector3, dir: Vector3) -> int:
	var best := -1
	var nearest := reach
	for i in _fires.size():
		var to: Vector3 = (_fires[i]["node"] as Node3D).global_position + Vector3(0, _top * 0.35, 0) - from
		if to.length() < nearest and dir.normalized().dot(to.normalized()) > 0.8:
			nearest = to.length()
			best = i
	return best


## There is a fire in front of you, room on it, and raw beef to put there.
func can_use(from: Vector3, dir: Vector3) -> bool:
	if holding() or _bag == null or _bag.count_of("beef") == 0:
		return false
	var i := _fire_before(from, dir)
	return i >= 0 and (_fires[i]["cooking"] as Array).size() < places


func use_label() -> String:
	return "COOK"


func try_use(from: Vector3, dir: Vector3) -> bool:
	if not can_use(from, dir):
		return false
	var fire: Dictionary = _fires[_fire_before(from, dir)]
	if not _bag.take("beef", 1):
		return false
	var cooking: Array = fire["cooking"]
	# The cut itself is not shown: only how far along it is, a ring over the fire
	# for each, filling.
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_quad
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(fire["node"] as Node3D).add_child(ring)
	ring.position = Vector3((float(cooking.size()) - float(places - 1) * 0.5) * 0.46, _top + 0.3, 0.0)
	ring.set_instance_shader_parameter(&"progress", 0.0)
	cooking.append([cook_seconds, ring])
	return true


## The axe on a fire: it comes down and goes back in the bag. True if one was hit.
func strike(from: Vector3, dir: Vector3) -> bool:
	var i := _fire_before(from, dir)
	if i < 0:
		return false
	var fire: Dictionary = _fires[i]
	if _bag != null:
		_bag.add(ITEM, 1)
		_bag.add("beef", (fire["cooking"] as Array).size())
	(fire["node"] as Node3D).queue_free()
	_fires.remove_at(i)
	return true


func _process(delta: float) -> void:
	# What is on the fires cooks, in the bag's sight or out of it.
	for fire in _fires:
		var cooking: Array = fire["cooking"]
		for k in range(cooking.size() - 1, -1, -1):
			cooking[k][0] = float(cooking[k][0]) - delta
			(cooking[k][1] as MeshInstance3D).set_instance_shader_parameter(&"progress", clampf(1.0 - float(cooking[k][0]) / cook_seconds, 0.0, 1.0))
			if float(cooking[k][0]) <= 0.0:
				(cooking[k][1] as Node).queue_free()
				cooking.remove_at(k)
				if _bag != null:
					_bag.add("steak", 1)
	# The fire in hand: shown where it would go, and set down on the use button.
	var cam := get_viewport().get_camera_3d()
	if not holding() or cam == null or _menus():
		if _ghost != null:
			_ghost.visible = false
		_plan = {}
		return
	if _ghost == null:
		_ghost = _model()
		var holder := Node3D.new()
		holder.add_child(_ghost)
		add_child(holder)
		_ghost = holder
	_plan = aim(cam.global_position, -cam.global_basis.z)
	_ghost.visible = not _plan.is_empty()
	if _plan.is_empty():
		return
	_ghost.global_transform = _plan["at"]
	for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _ghost_ok if bool(_plan["free"]) else _ghost_no
	if not Input.is_action_just_pressed(&"wv_attack") or not bool(_plan["free"]):
		return
	var hand := get_node_or_null(^"../SwordPlay")
	if hand != null and not bool(hand.call(&"_mouse_ready")):
		return
	if Vitals.debug or _bag.take_selected():
		set_down(_plan["at"])
