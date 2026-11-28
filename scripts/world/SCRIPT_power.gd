class_name Power
extends Node3D

# POWER: solar panels, batteries, junction boxes and light poles (the power kit,
# SCRIPT_power_kit.gd), set down in the world and joined by CABLES you run by hand.
#
#   solar panel   makes power while the sun is up (the panel turns to follow it)
#   battery       takes what is to spare and gives it back when there is none
#   junction box  nothing but four sockets: where lines meet
#   light pole    lights when it is dark, if power reaches it
#
# Each is made in the bag and set down where you point with it in hand (the turn
# key turns it), as a cooking fire is; the axe takes one down again.
#
# A CABLE has a plug at each end and every part has sockets (a round one in the
# middle of each side of its box: four on most, two on a battery). With a cable in
# hand, look at a part and use it: one plug goes into the nearest free socket and
# the other is in your hand, the cable running out behind you as you walk (up to
# `cable_most` metres). The cable is a real hanging line while this goes on: it
# sags, drags after you, lies along the ground AND ON WHATEVER IS SOLID (a roof, a
# wall's top, a part, the truck: every collision layer), goes round a corner and
# pulls tight against it, and lies over the cables that are already there. Use another part to plug the
# second end in; use anything else to put the plug down where you stand (it can be
# picked up again); the turn key coils the whole cable back into the bag. A plug
# that is in a socket, or lying loose, is taken in hand again by using it.
# WHEN BOTH ENDS ARE OUT OF YOUR HAND the cable settles for a moment and then
# SETS: it stops being worked out every frame and stays as it lies, one fixed
# mesh, until an end is taken up again.
#
# WHAT IS JOINED BY CABLES IS ONE CIRCUIT (both ends of a cable in sockets). In
# each, twice a second: the panels' power goes to the lights first, what is over
# charges the batteries, what is short is drawn from them. Lights dim as power
# runs short and go out with none.

@export var explorer_path: NodePath = ^"../Explorer"
@export var inventory_path: NodePath = ^"../Inventory"
@export var world_path: NodePath = ^"../GaiaSphere"
@export var enviro_path: NodePath = ^"../Enviro"
## How far off a part can be set down.
@export var reach := 11.0
## How far off a socket or a plug can be worked.
@export var plug_reach := 6.0
## The most cable there is on one line, metres.
@export var cable_most := 70.0
## What a panel makes in full sun, and what a light draws, a second.
@export var solar_power := 6.0
@export var lamp_draw := 1.0
## Nights of one light that a full battery holds.
@export var battery_nights := 2.0

const CABLE := "cable"
## THE KIT IS DRAWN AT HALF THE SIZE IT WAS MADE: a junction box a metre across.
const SCALE := 0.5
const SEG := 0.3                  # metres of cable between two of its points
const THICK := 0.03               # its radius
const SIDES := 6
const PLUG_OUT := 0.394 * SCALE           # where the cable leaves a plug, along the plug's +X
## Each kind: the item, what stands there, its sockets (in its own frame: where,
## and facing which way), the box that is its body.
const KINDS := {
	# (In metres as it stands, at SCALE.)
	"solar_panel": {"name": "SOLAR PANEL", "stand": 0.5, "sockets": 4, "box": [Vector3(1, 1, 1), Vector3.ZERO]},
	"battery": {"name": "BATTERY", "stand": 0.5065, "sockets": 2, "box": [Vector3(1.01, 1.51, 2.01), Vector3(0, 0.25, 0)]},
	"junction": {"name": "JUNCTION BOX", "stand": 0.5, "sockets": 4, "box": [Vector3(1, 1, 1), Vector3.ZERO]},
	"light_pole": {"name": "LIGHT POLE", "stand": 1.034, "sockets": 4, "box": [Vector3(1, 1, 1), Vector3.ZERO]},
}
const SOCKET_WAYS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
const LAMP_AT := Vector3(0, 10.3, 0) * SCALE

## A part standing in the world.
class Dev extends RefCounted:
	var kind := ""
	var node: StaticBody3D
	var sockets: Array = []       # each {"at", "way" (its own frame), "cable": the Line in it or null}
	var charge := 0.0
	var lit := 0.0
	var state := ""
	var net := -1
	var lamp: OmniLight3D
	var glow: Array = []
	var glowing := true
	var tilt: Node3D
	var shaft: Node3D


## A cable: its two ends (each {"dev", "socket"}, or {"hand"}, or {"at"} lying
## loose), its points, its mesh and its two plugs.
class Line extends RefCounted:
	var ends: Array = [{"at": Transform3D.IDENTITY}, {"at": Transform3D.IDENTITY}]
	var pts := PackedVector3Array()
	var old := PackedVector3Array()
	var node: MeshInstance3D
	var plugs: Array = []
	var live := true
	var still := 0.0
	var age := 0.0


var devices: Array = []           # of Dev
var cables: Array = []            # of Line

var _explorer: Node3D
var _bag: Inventory
var _world: Node
var _enviro: Node
var _carry: Line                  # the cable an end of which is in hand, and which end
var _carry_end := -1
var _turns := 0
var _ghost: Node3D
var _ghost_of := ""
var _ghost_ok: StandardMaterial3D
var _ghost_no: StandardMaterial3D
var _plan := {}
var _hint: Label
var _rubber: StandardMaterial3D
var _tick := 0.0
var _dark_lamp := {}              # a lit material -> the same with its glow off
var _step_left := 0.0
var _query: PhysicsRayQueryParameters3D
var _other := {}                  # the cables that have set, by cell: see `_others`
var _other_of: Line
var _other_stamp := -1
var _stamp := 0                   # goes up whenever a cable sets, wakes or goes
var _phase := 0


func _ready() -> void:
	_explorer = get_node_or_null(explorer_path)
	_bag = get_node_or_null(inventory_path) as Inventory
	_world = get_node_or_null(world_path)
	_enviro = get_node_or_null(enviro_path)
	_ghost_ok = Building._ghost_material(Color(0.5, 0.85, 1.0, 0.42))
	_ghost_no = Building._ghost_material(Color(1.0, 0.25, 0.2, 0.42))
	_rubber = StandardMaterial3D.new()
	_rubber.albedo_color = Color(0.035, 0.035, 0.04)
	_rubber.roughness = 0.55
	_rubber.metallic = 0.0
	add_to_group(&"usable")
	var layer := CanvasLayer.new()
	layer.layer = 29
	add_child(layer)
	_hint = Label.new()
	_hint.add_theme_font_override(&"font", load("res://branding/fonts/RobotoCondensed-Regular.ttf"))
	_hint.add_theme_font_size_override(&"font_size", 20)
	_hint.add_theme_color_override(&"font_color", Color(0.93, 0.95, 0.97, 0.85))
	_hint.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.6))
	_hint.add_theme_constant_override(&"outline_size", 5)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -214.0
	_hint.offset_bottom = -188.0
	_hint.offset_left = -500.0
	_hint.offset_right = 500.0
	_hint.visible = false
	layer.add_child(_hint)


func _menus() -> bool:
	return Inventory.menu_open or GraphicsMenu.menu_open or EnvironmentMenu.menu_open or OptionsMenu.menu_open or MapMenu.menu_open or TitleMenu.menu_open or UniTruck.driving


## The part in hand to be set down, or "".
func holding() -> String:
	if _bag == null or _bag.slots[_bag.selected] == null or _carry != null:
		return ""
	var id := String(_bag.slots[_bag.selected][0])
	return id if KINDS.has(id) else ""


func _holding_cable() -> bool:
	return _bag != null and _bag.slots[_bag.selected] != null and String(_bag.slots[_bag.selected][0]) == CABLE


## A plug is in hand.
func carrying() -> bool:
	return _carry != null


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"wv_turn") or _menus():
		return
	if carrying():
		coil(_carry)
	elif holding() != "":
		_turns += -1 if (event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN) else 1


# ------------------------------------------------------------------ the parts

## One piece of the kit with all its levels, each shown over its own stretch of
## distance; the impostor last, where it has one and `flat_last` is not asked.
static func part(piece: String, with_impostor := true) -> Node3D:
	var holder := Node3D.new()
	holder.name = piece
	var meshes := PowerKit.lods(piece)
	var far: Array = []
	for d: float in PowerKit.distances(piece):
		far.append(d * maxf(SCALE, 0.6))
	var from := 0.0
	for k in meshes.size():
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[k]
		mi.visibility_range_begin = from
		mi.visibility_range_end = float(far[k])
		# (Only the near levels throw shadows.)
		if k > 2:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		from = float(far[k])
	var picture := PowerKit.impostor(piece) if with_impostor else []
	if not picture.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = picture[0]
		mi.material_override = picture[1]
		mi.visibility_range_begin = from
		mi.visibility_range_end = 900.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16.0
		holder.add_child(mi)
	elif holder.get_child_count() > 0:
		(holder.get_child(holder.get_child_count() - 1) as MeshInstance3D).visibility_range_end = maxf(from, 420.0) if with_impostor else from
	return holder


## What a kind looks like, standing on its own lowest point. `plain`: the finest
## level only (a ghost, an icon).
static func model(kind: String, plain := false) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, float(KINDS[kind]["stand"]), 0)
	body.scale = Vector3.ONE * SCALE
	root.add_child(body)
	var pieces: Array = []
	match kind:
		"solar_panel":
			pieces = [["solar_box", Vector3.ZERO, true]]
		"battery":
			pieces = [["battery_box", Vector3.ZERO, true]]
		"junction":
			pieces = [["junction_box", Vector3.ZERO, true]]
		"light_pole":
			pieces = [["light_pole", Vector3.ZERO, true]]
	for p: Array in pieces:
		var node := _piece(String(p[0]), bool(p[2]), plain)
		node.position = p[1]
		body.add_child(node)
	if kind == "solar_panel":
		# AS THE PART IS LAYERED: the box; on it the SHAFT (the support), which turns
		# about the upright; on the shaft the actuator, and on that the panel, which
		# TILT about the one level axis along the panel's length. Two turns at two
		# places, one axis each.
		var shaft := Node3D.new()
		shaft.name = "Shaft"
		shaft.position = Vector3(0, 1, 0)
		body.add_child(shaft)
		shaft.add_child(_piece("solar_support", false, plain))
		var tilt := Node3D.new()
		tilt.name = "Tilt"
		tilt.position = Vector3(0, 1, 0)
		shaft.add_child(tilt)
		tilt.add_child(_piece("solar_actuator", false, plain))
		tilt.add_child(_piece("solar_panel", true, plain))
	return root


static func _piece(piece: String, with_impostor: bool, plain: bool) -> Node3D:
	if not plain:
		return part(piece, with_impostor)
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = PowerKit.lods(piece)[0]
	holder.add_child(mi)
	return holder


func _socket_list(kind: String) -> Array:
	var out: Array = []
	var box: Array = KINDS[kind]["box"]
	for i in int(KINDS[kind]["sockets"]):
		var way: Vector3 = SOCKET_WAYS[i]
		out.append({"at": Vector3(0, float(KINDS[kind]["stand"]), 0) + way * (absf(way.dot(box[0] as Vector3)) * 0.5), "way": way, "cable": null})
	return out


## Stand a part at `at` (its foot). Returns its record.
func set_down(kind: String, at: Transform3D, charge := 0.0) -> Dev:
	var body := StaticBody3D.new()
	body.name = kind
	body.add_child(model(kind))
	var box: Array = KINDS[kind]["box"]
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box[0]
	shape.shape = bs
	shape.position = Vector3(0, float(KINDS[kind]["stand"]), 0) + (box[1] as Vector3)
	body.add_child(shape)
	var dev := Dev.new()
	dev.kind = kind
	dev.node = body
	dev.sockets = _socket_list(kind)
	dev.charge = charge
	if kind == "light_pole":
		# The post, to walk into; and the light itself.
		var post := CollisionShape3D.new()
		var ps := BoxShape3D.new()
		ps.size = Vector3(0.45, 8.6, 0.45) * SCALE
		post.shape = ps
		post.position = Vector3(0, 2.068 + 1.0 + 4.3, 0) * SCALE
		body.add_child(post)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, 1.034, 0) + LAMP_AT - Vector3(0, 0.5, 0)
		lamp.omni_range = 30.0
		lamp.omni_attenuation = 0.7
		lamp.light_color = Color(1.0, 0.93, 0.8)
		lamp.light_energy = 0.0
		lamp.shadow_enabled = false
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 170.0
		lamp.distance_fade_length = 50.0
		lamp.visible = false
		body.add_child(lamp)
		dev.lamp = lamp
		dev.glow = _lamp_surfaces(body)
		_set_glow(dev, false)
	elif kind == "solar_panel":
		dev.tilt = body.find_child("Tilt", true, false) as Node3D
		dev.shaft = body.find_child("Shaft", true, false) as Node3D
	add_child(body)
	body.global_transform = at
	body.set_meta(&"power_device", true)
	devices.append(dev)
	for grower in [get_node_or_null(^"../Flora"), get_node_or_null(^"../BerryBushes")]:
		if grower != null:
			grower.call(&"clear_ground", at, Vector2(0.9, 0.9))
	_tick = 0.0
	return dev


## The lamp's textured levels: [the mesh instance, its lit material] for each
## surface that glows, so the glow can be put out.
func _lamp_surfaces(body: Node) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.material_override != null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null and mat.emission_enabled:
				if not _dark_lamp.has(mat):
					var dark := mat.duplicate() as BaseMaterial3D
					dark.emission_enabled = false
					_dark_lamp[mat] = dark
				out.append([mi, s, mat])
	return out


func _set_glow(dev: Dev, on: bool) -> void:
	if dev.glowing == on:
		return
	dev.glowing = on
	for entry: Array in dev.glow:
		(entry[0] as MeshInstance3D).set_surface_override_material(int(entry[1]), null if on else _dark_lamp[entry[2]])


func _device_of(body: Object) -> Dev:
	for dev: Dev in devices:
		if dev.node == body:
			return dev
	return null


func _socket_world(dev: Dev, i: int) -> Transform3D:
	var s: Dictionary = dev["sockets"][i]
	var frame := (dev["node"] as Node3D).global_transform
	var out: Vector3 = (frame.basis * (s["way"] as Vector3)).normalized()
	# The plug's +X is out of the socket; its Y as near upright as can be.
	var up := Vector3.UP
	var z := out.cross(up).normalized()
	return Transform3D(Basis(out, z.cross(out).normalized(), z), frame * (s["at"] as Vector3))


## Take a part down: it goes back in the bag, and whatever was plugged into it
## falls out where it was.
func remove(dev: Dev) -> void:
	for i in (dev["sockets"] as Array).size():
		var cable: Variant = dev["sockets"][i]["cable"]
		if cable != null:
			var c: Line = cable
			for e in 2:
				var end: Dictionary = c["ends"][e]
				if end.get("dev") == dev and int(end["socket"]) == i:
					var where := _socket_world(dev, i)
					c["ends"][e] = {"at": where}
					_wake(c)
	(dev["node"] as Node).queue_free()
	devices.erase(dev)
	_tick = 0.0


## The axe on a part: true if one was hit.
func strike(from: Vector3, dir: Vector3) -> bool:
	var hit := _ray(from, dir, 4.5)
	if hit.is_empty():
		return false
	var dev := _device_of(hit["collider"])
	if dev == null:
		return false
	if _bag != null:
		_bag.add(String(dev["kind"]), 1)
	remove(dev)
	return true


func _ray(from: Vector3, dir: Vector3, far: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * far)
	if _explorer is CollisionObject3D:
		q.exclude = [(_explorer as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


# ------------------------------------------------------------------ what the use button would do

## What using would do for someone at `from` looking along `dir`: {} for nothing,
## else "do" (plug / start / take / drop) and what it needs.
func _aim(from: Vector3, dir: Vector3) -> Dictionary:
	if _menus():
		return {}
	var hit := _ray(from, dir, plug_reach)
	var dev: Dev = _device_of(hit["collider"]) if not hit.is_empty() else null
	var socket := -1
	if dev != null:
		var nearest := 1.5
		for i in (dev["sockets"] as Array).size():
			if dev["sockets"][i]["cable"] != null:
				continue
			var d := _socket_world(dev, i).origin.distance_to(hit["position"])
			if d < nearest:
				nearest = d
				socket = i
	if carrying():
		if socket >= 0:
			return {"do": "plug", "dev": dev, "socket": socket}
		return {"do": "drop", "hit": hit}
	if socket >= 0 and _holding_cable():
		return {"do": "start", "dev": dev, "socket": socket}
	# A plug looked at: in a socket, or lying loose.
	var best := {}
	var best_dot := 0.965
	for cable: Line in cables:
		for e in 2:
			var plug := (cable["plugs"][e] as Node3D).global_position
			var to := plug - from
			if to.length() > plug_reach:
				continue
			var d := dir.normalized().dot(to.normalized())
			# (Near enough, a plug need not be looked at so squarely.)
			if d > best_dot or (d > 0.9 and to.length() < 2.2 and best.is_empty()):
				best_dot = maxf(d, best_dot)
				best = {"do": "take", "cable": cable, "end": e}
	return best


func can_use(from: Vector3, dir: Vector3) -> bool:
	return not _aim(from, dir).is_empty()


func use_label() -> String:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return "USE"
	match String(_aim(cam.global_position, -cam.global_basis.z).get("do", "")):
		"plug", "start":
			return "PLUG IN"
		"take":
			return "UNPLUG"
		"drop":
			return "DROP"
	return "USE"


func try_use(from: Vector3, dir: Vector3) -> bool:
	var plan := _aim(from, dir)
	match String(plan.get("do", "")):
		"start":
			if not Vitals.debug and not _bag.take_selected():
				return false
			var cable := _new_cable()
			_plug(cable, 0, plan["dev"] as Dev, int(plan["socket"]))
			_take_up(cable, 1)
			var start := _end_point(cable, 0)
			cable["pts"] = PackedVector3Array([start, start])
			cable["old"] = PackedVector3Array([start, start])
			return true
		"plug":
			_plug(_carry, _carry_end, plan["dev"] as Dev, int(plan["socket"]))
			_carry = null
			_carry_end = -1
			return true
		"drop":
			drop()
			return true
		"take":
			_take_up(plan["cable"] as Line, int(plan["end"]))
			return true
	return false


# ------------------------------------------------------------------ cables

func _new_cable() -> Line:
	var node := MeshInstance3D.new()
	node.mesh = ArrayMesh.new()
	node.material_override = _rubber
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_transform = Transform3D.IDENTITY
	var plugs: Array = []
	for e in 2:
		var plug := part("plug_end")
		add_child(plug)
		plugs.append(plug)
	var cable := Line.new()
	cable.node = node
	cable.plugs = plugs
	cables.append(cable)
	return cable


func _plug(cable: Line, e: int, dev: Dev, socket: int) -> void:
	cable["ends"][e] = {"dev": dev, "socket": socket}
	dev["sockets"][socket]["cable"] = cable
	_wake(cable)
	_tick = 0.0


func _unplug(cable: Line, e: int) -> void:
	var end: Dictionary = cable["ends"][e]
	if end.get("dev") != null:
		end["dev"]["sockets"][int(end["socket"])]["cable"] = null
	_tick = 0.0


## An end into the hand.
func _take_up(cable: Line, e: int) -> void:
	if carrying():
		drop()
	_unplug(cable, e)
	cable["ends"][e] = {"hand": true}
	_carry = cable
	_carry_end = e
	_wake(cable)


## The plug in hand put down: on what is looked at if that is near, else at the feet.
func drop() -> void:
	if not carrying():
		return
	var at := (_carry["plugs"][_carry_end] as Node3D).global_transform
	var foot := at.origin
	if _explorer != null:
		foot = _explorer.global_position + Vector3(0, 0.3, 0) - _explorer.global_basis.z * 0.9
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var hit := _ray(cam.global_position, -cam.global_basis.z, 4.0)
		if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.5:
			foot = hit["position"]
	foot.y = maxf(foot.y, _ground(foot)) + 0.19 * SCALE
	# Lying on its side, the cable leaving it back toward the rest of the line.
	var pts: PackedVector3Array = _carry["pts"]
	var back := Vector3.FORWARD
	if pts.size() > 2:
		back = pts[2 if _carry_end == 0 else pts.size() - 3] - foot
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.FORWARD
	_carry["ends"][_carry_end] = {"at": Transform3D(Basis(back, Vector3.UP, back.cross(Vector3.UP)), foot)}
	_wake(_carry)
	_carry = null
	_carry_end = -1


## The whole cable back into the bag.
func coil(cable: Line) -> void:
	for e in 2:
		_unplug(cable, e)
	if cable == _carry:
		_carry = null
		_carry_end = -1
	(cable["node"] as Node).queue_free()
	for plug: Node in cable["plugs"]:
		plug.queue_free()
	cables.erase(cable)
	_stamp += 1
	if _bag != null and not Vitals.debug:
		_bag.add(CABLE, 1)


func _wake(cable: Line) -> void:
	_stamp += 1
	cable["live"] = true
	cable["still"] = 0.0
	cable["age"] = 0.0


## Where an end's plug is, in the world.
func _end_frame(cable: Line, e: int) -> Transform3D:
	var end: Dictionary = cable["ends"][e]
	if end.get("dev") != null:
		return _socket_world(end["dev"], int(end["socket"]))
	if end.has("hand"):
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			# In the right hand, prongs forward, the cable out behind and down.
			var b := cam.global_basis
			return Transform3D(Basis(b.z, b.y, -b.x), cam.global_position + b.x * 0.4 - b.y * 0.34 - b.z * 0.85)
	return end.get("at", Transform3D.IDENTITY)


func _end_point(cable: Line, e: int) -> Vector3:
	var f := _end_frame(cable, e)
	return f.origin + f.basis.x * PLUG_OUT


func _ground(at: Vector3) -> float:
	if _world != null:
		return float(_world.call(&"height_at", at, -1e9))
	return -1e9


## What a cable can lie on, hang over and be pulled round: everything solid there
## is (every layer: the ground's own collision, what is built, the parts, the
## truck, trunks and rocks where they have bodies), but not you.
func _solid(from: Vector3, to: Vector3) -> Dictionary:
	if _query == null:
		_query = PhysicsRayQueryParameters3D.new()
		_query.collision_mask = 0xFFFFFFFF
		_query.collide_with_areas = false
		_query.hit_back_faces = false
		_query.hit_from_inside = false
	_query.from = from
	_query.to = to
	_query.exclude = [(_explorer as CollisionObject3D).get_rid()] if _explorer is CollisionObject3D else []
	return get_world_3d().direct_space_state.intersect_ray(_query)


const CELL := 0.6


## THE OTHER CABLES, as a cable being worked out meets them: every length of every
## cable that has set, filed by the 60 cm cells it passes through. Made again only
## when a cable sets, wakes or goes.
func _others(but: Line) -> Dictionary:
	if _other_of == but and _other_stamp == _stamp:
		return _other
	_other = {}
	_other_of = but
	_other_stamp = _stamp
	var reach := Vector3.ONE * (THICK * 2.0)
	for cable: Line in cables:
		if cable == but or cable.live:
			continue
		var pts := cable.pts
		for i in pts.size() - 1:
			var lo := ((pts[i].min(pts[i + 1]) - reach) / CELL).floor()
			var hi := ((pts[i].max(pts[i + 1]) + reach) / CELL).floor()
			for x in range(int(lo.x), int(hi.x) + 1):
				for y in range(int(lo.y), int(hi.y) + 1):
					for z in range(int(lo.z), int(hi.z) + 1):
						var key := Vector3i(x, y, z)
						if not _other.has(key):
							_other[key] = PackedVector3Array()
						(_other[key] as PackedVector3Array).append_array([pts[i], pts[i + 1]])
	return _other


## A point kept off the other cables: out of any it is in, and that mostly upward,
## so the one that comes later lies over the one that was there.
func _off_cables(p: Vector3, others: Dictionary) -> Vector3:
	var lengths: Variant = others.get(Vector3i((p / CELL).floor()))
	if lengths == null:
		return p
	var list: PackedVector3Array = lengths
	for k in range(0, list.size(), 2):
		var a := list[k]
		var ab := list[k + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
		var away := p - (a + ab * t)
		var d := away.length()
		if d < THICK * 2.0:
			away = (away / d if d > 1e-4 else Vector3.UP) + Vector3.UP * 0.6
			p += away.normalized() * (THICK * 2.0 - d)
	return p


## The cable worked out for one step: a string of points each a fixed way from the
## next, falling; lying on the ground and on whatever is solid, bent round what is
## in its way, over the cables already there; its two ends where its plugs are.
func _step_cable(cable: Line, dt: float) -> float:
	var pts: PackedVector3Array = cable["pts"]
	var old: PackedVector3Array = cable["old"]
	var a := _end_point(cable, 0)
	var b := _end_point(cable, 1)
	var held := cable == _carry
	var n := pts.size()
	# PAID OUT AND TAKEN IN at the end in hand, by how the cable itself is doing and
	# not by how far apart its ends are (it may be round a corner): more when it is
	# pulled tight, less when what is nearest the hand has gone slack.
	if held:
		var total := 0.0
		for i in n - 1:
			total += pts[i].distance_to(pts[i + 1])
		var at_end := _carry_end == 1
		var tight := total > float(n - 1) * SEG * 1.025
		if n < 5 or (tight and float(n) * SEG < cable_most):
			for k in (3 if n >= 5 else 5 - n):
				if at_end:
					pts.append(b)
					old.append(b)
				else:
					pts.insert(0, a)
					old.insert(0, a)
		elif tight and total > float(n - 1) * SEG * 1.1:
			# No more cable, and it is being pulled: the plug comes out of the hand.
			cable["pts"] = pts
			cable["old"] = old
			drop()
			return 1.0
		elif n > 12:
			var near := pts[n - 1].distance_to(pts[n - 8]) if at_end else pts[0].distance_to(pts[7])
			if near < 7.0 * SEG * 0.72:
				if at_end:
					pts.remove_at(n - 1)
					old.remove_at(n - 1)
				else:
					pts.remove_at(0)
					old.remove_at(0)
		n = pts.size()
	if n < 2:
		return 0.0
	var was := pts.duplicate()
	for i in range(1, n - 1):
		var p := pts[i]
		# (Out of the hand it is let come to rest quickly.)
		var v := (p - old[i]) * (0.985 if held else 0.94)
		old[i] = p
		p += v + Vector3(0, -9.8 * dt * dt, 0)
		pts[i] = p
	# Where each end leaves its plug it goes straight out a little way first.
	var fa := _end_frame(cable, 0).basis.x
	var fb := _end_frame(cable, 1).basis.x
	var stiff := n > 5
	var others := _others(cable)
	_phase = (_phase + 1) % 4
	for round_i in 2:
		for pass_i in (8 if round_i == 0 else 3):
			pts[0] = a
			pts[n - 1] = b
			if stiff:
				pts[1] = a + fa * SEG
				pts[n - 2] = b + fb * SEG
			for i in n - 1:
				var d := pts[i + 1] - pts[i]
				var l := d.length()
				if l < 1e-5:
					continue
				var fix := d * ((l - SEG) / l * 0.5)
				pts[i] += fix
				pts[i + 1] -= fix
		pts[0] = a
		pts[n - 1] = b
		var first := 2 if stiff else 1
		var last := n - 3 if stiff else n - 2
		if round_i == 0:
			# WHAT IS SOLID. A point that has gone into something on its way from where
			# it was is put back on its face...
			for i in range(first, last + 1):
				if was[i].distance_squared_to(pts[i]) < 0.000025:
					continue
				var hit := _solid(was[i], pts[i])
				if not hit.is_empty():
					var on: Vector3 = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * THICK
					pts[i] = on
					old[i] = old[i].lerp(on, 0.55)
			# ... and a length of cable with something between its two ends (a corner,
			# an edge, a post) is pushed off it, so the cable goes round and pulls
			# tight against it. (Half the lengths a step, each way in turn.)
			for i in range(first + (_phase & 1), last, 2):
				var from := pts[i] if _phase < 2 else pts[i + 1]
				var to := pts[i + 1] if _phase < 2 else pts[i]
				var hit := _solid(from, to)
				if not hit.is_empty():
					var push: Vector3 = (hit["normal"] as Vector3) * 0.035
					pts[i] += push
					pts[i + 1] += push
		# The other cables, and the ground: nothing of it goes under, and what lies
		# on it drags.
		for i in range(1, n - 1):
			var p := pts[i]
			if not others.is_empty():
				p = _off_cables(p, others)
			var g := _ground(p) + THICK
			if p.y < g:
				p.y = g
				var before := old[i]
				old[i] = Vector3(lerpf(before.x, p.x, 0.55), p.y, lerpf(before.z, p.z, 0.55))
			pts[i] = p
	var moved := 0.0
	for i in range(1, n - 1):
		moved = maxf(moved, (pts[i] - old[i]).length())
	cable["pts"] = pts
	cable["old"] = old
	return moved / maxf(dt, 1e-4)


## The cable's mesh from its points: a tube.
func _draw_cable(cable: Line) -> void:
	var pts: PackedVector3Array = cable["pts"]
	var mesh := (cable["node"] as MeshInstance3D).mesh as ArrayMesh
	mesh.clear_surfaces()
	var n := pts.size()
	if n < 2:
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.resize(n * SIDES)
	normals.resize(n * SIDES)
	var side := Vector3.UP
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)])
		t = t.normalized() if t.length() > 1e-5 else Vector3.RIGHT
		# (The ring's frame carried along from the last one, so the tube does not twist.)
		side = (side - t * side.dot(t))
		side = side.normalized() if side.length() > 1e-3 else t.cross(Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD).normalized()
		var other := t.cross(side)
		for s in SIDES:
			var ang := TAU * float(s) / float(SIDES)
			var out := side * cos(ang) + other * sin(ang)
			verts[i * SIDES + s] = pts[i] + out * THICK
			normals[i * SIDES + s] = out
	for i in n - 1:
		for s in SIDES:
			var a0 := i * SIDES + s
			var a1 := i * SIDES + (s + 1) % SIDES
			var b0 := a0 + SIDES
			var b1 := a1 + SIDES
			indices.append_array([a0, a1, b0, a1, b1, b0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	for e in 2:
		(cable["plugs"][e] as Node3D).global_transform = _end_frame(cable, e).scaled_local(Vector3.ONE * SCALE)


func _run_cables(delta: float) -> void:
	_step_left = minf(_step_left + delta, 0.1)
	var steps := 0
	while _step_left >= 1.0 / 60.0:
		_step_left -= 1.0 / 60.0
		steps += 1
	for cable: Line in cables.duplicate():
		if not bool(cable["live"]):
			continue
		var speed := 0.0
		for s in steps:
			speed = _step_cable(cable, 1.0 / 60.0)
			if not cables.has(cable):
				break
		if not cables.has(cable):
			continue
		_draw_cable(cable)
		if cable == _carry or steps == 0:
			continue
		# OUT OF THE HAND: once it has lain still a moment (or been long enough about
		# it), it SETS: no more working out, the mesh as it is.
		var dt := float(steps) / 60.0
		cable["age"] = float(cable["age"]) + dt
		cable["still"] = float(cable["still"]) + dt if speed < 0.3 else 0.0
		if float(cable["still"]) > 0.6 or float(cable["age"]) > 5.0:
			cable["live"] = false
			_stamp += 1
			cable["old"] = (cable["pts"] as PackedVector3Array).duplicate()


# ------------------------------------------------------------------ the circuits

func _daylight() -> float:
	return float(_enviro.call(&"daylight")) if _enviro != null else 1.0


func _night_seconds() -> float:
	var day_minutes := float(_enviro.get("day_minutes")) if _enviro != null else 36.0
	return maxf(day_minutes, 1.0) * 60.0 * 0.45


func capacity() -> float:
	return lamp_draw * _night_seconds() * battery_nights


func _circuits(dt: float) -> void:
	# Which parts are joined: each cable with both ends in sockets joins two.
	for i in devices.size():
		(devices[i] as Dev).net = i
	var changed := true
	while changed:
		changed = false
		for cable: Line in cables:
			var d0 := cable.ends[0].get("dev") as Dev
			var d1 := cable.ends[1].get("dev") as Dev
			if d0 == null or d1 == null or d0.net == d1.net:
				continue
			var low := mini(d0.net, d1.net)
			d0.net = low
			d1.net = low
			changed = true
	var nets := {}
	for dev: Dev in devices:
		if not nets.has(dev["net"]):
			nets[dev["net"]] = []
		(nets[dev["net"]] as Array).append(dev)
	var sun := _daylight()
	var dark := sun < 0.35
	var full := capacity()
	for key in nets:
		var made := 0.0
		var wanted := 0.0
		var stored := 0.0
		var batteries: Array = []
		var lamps: Array = []
		for dev: Dev in nets[key]:
			match String(dev["kind"]):
				"solar_panel":
					made += solar_power * sun
					dev["state"] = "%.1f kW" % (solar_power * sun) if sun > 0.02 else "no sun"
				"battery":
					dev["charge"] = clampf(float(dev["charge"]), 0.0, full)
					batteries.append(dev)
					stored += float(dev["charge"])
				"light_pole":
					lamps.append(dev)
					if dark:
						wanted += lamp_draw
				"junction":
					dev["state"] = "%d of 4 in use" % _in_use(dev)
		var can := made + stored / maxf(dt, 1e-4)
		var share := clampf(can / wanted, 0.0, 1.0) if wanted > 0.0 else 0.0
		var flow := (made - wanted * share) * dt          # into the batteries (out of them, if under 0)
		if not batteries.is_empty():
			# Shared between them, as each has room (or has any).
			for round_i in 3:
				var open: Array = []
				for b: Dev in batteries:
					if (flow > 0.0 and float(b["charge"]) < full) or (flow < 0.0 and float(b["charge"]) > 0.0):
						open.append(b)
				if open.is_empty() or absf(flow) < 1e-6:
					break
				var each := flow / float(open.size())
				for b: Dev in open:
					var to := clampf(float(b["charge"]) + each, 0.0, full)
					flow -= to - float(b["charge"])
					b["charge"] = to
			for b: Dev in batteries:
				var rate := made - wanted * share
				b["state"] = "%d%%%s" % [int(round(float(b["charge"]) / full * 100.0)),
						"  charging" if rate > 0.01 and float(b["charge"]) < full else ("  in use" if rate < -0.01 else "")]
		for lamp: Dev in lamps:
			lamp["lit"] = share if dark else 0.0
			lamp["state"] = ("lit" if share > 0.99 else ("dim: short of power" if share > 0.01 else "no power")) if dark \
					else ("waiting for dark" if (made > 0.0 or stored > 0.0) else "no power")


func _in_use(dev: Dev) -> int:
	var n := 0
	for s: Dictionary in dev["sockets"]:
		if s["cable"] != null:
			n += 1
	return n


func _show_power(delta: float) -> void:
	var sun_dir: Vector3 = _enviro.get("sun_dir") if _enviro != null else Vector3.UP
	var sun := _daylight()
	for dev: Dev in devices:
		if dev.lamp != null:
			var lamp := dev["lamp"] as OmniLight3D
			var to := float(dev["lit"]) * 10.0
			lamp.light_energy = move_toward(lamp.light_energy, to, delta * 20.0)
			lamp.visible = lamp.light_energy > 0.01
			_set_glow(dev, lamp.light_energy > 0.5)
		elif dev.tilt != null:
			# The shaft turned to where the sun stands round the sky, the panel tilted
			# over toward it (as far as the actuator goes); flat by night, the shaft
			# left where it was.
			var lean := 0.0
			if sun > 0.05:
				var local := (dev.node.global_basis.inverse() * sun_dir).normalized()
				if Vector2(local.x, local.z).length() > 0.05:
					dev.shaft.rotation.y = lerp_angle(dev.shaft.rotation.y, atan2(local.x, local.z), clampf(delta * 0.5, 0.0, 1.0))
				lean = minf(acos(clampf(local.y, -1.0, 1.0)), deg_to_rad(58.0))
			dev.tilt.rotation.x = lerp_angle(dev.tilt.rotation.x, lean, clampf(delta * 0.5, 0.0, 1.0))


# ------------------------------------------------------------------ every frame

func _process(delta: float) -> void:
	if UniTruck.driving and carrying():
		drop()
	_run_cables(delta)
	_tick -= delta
	if _tick <= 0.0:
		_circuits(0.5)
		_tick = 0.5
	_show_power(delta)
	_place()
	_say()


## The part in hand: shown where it would go, and set down on the use button.
func _place() -> void:
	var item := holding()
	var cam := get_viewport().get_camera_3d()
	if item == "" or cam == null or _menus():
		if _ghost != null:
			_ghost.visible = false
		_plan = {}
		return
	if _ghost == null or _ghost_of != item:
		if _ghost != null:
			_ghost.queue_free()
		_ghost = model(item, true)
		_ghost_of = item
		add_child(_ghost)
	_plan = aim(item, cam.global_position, -cam.global_basis.z)
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
		set_down(item, _plan["at"])


## Where a part would go: {} if nowhere, else "at" and "free".
func aim(kind: String, from: Vector3, dir: Vector3) -> Dictionary:
	var hit := _ray(from, dir, reach)
	if hit.is_empty():
		return {}
	var at: Vector3 = hit["position"]
	var level: bool = (hit["normal"] as Vector3).y > 0.8
	var clear := _device_of(hit["collider"]) == null
	var wide := maxf((KINDS[kind]["box"][0] as Vector3).x, (KINDS[kind]["box"][0] as Vector3).z)
	for dev: Dev in devices:
		var other: Vector3 = (KINDS[dev["kind"]]["box"][0] as Vector3)
		if ((dev["node"] as Node3D).global_position - at).length() < (wide + maxf(other.x, other.z)) * 0.5 + 0.3:
			clear = false
	var facing := atan2(-dir.x, -dir.z) + float(_turns) * deg_to_rad(15.0)
	return {"at": Transform3D(Basis(Vector3.UP, facing), at), "free": level and clear}


func _say() -> void:
	var cam := get_viewport().get_camera_3d()
	var text := ""
	if cam != null and not _menus():
		var from := cam.global_position
		var dir := -cam.global_basis.z
		var plan := _aim(from, dir)
		match String(plan.get("do", "")):
			"start", "plug":
				text = "PLUG INTO THE %s" % String(KINDS[plan["dev"]["kind"]]["name"])
			"take":
				text = "TAKE THE PLUG"
			"drop":
				text = "PUT THE PLUG DOWN   ·   TURN: COIL THE CABLE UP"
		if text == "" or String(plan.get("do", "")) in ["start", "plug"]:
			var hit := _ray(from, dir, plug_reach + 4.0)
			var dev: Dev = _device_of(hit["collider"]) if not hit.is_empty() else null
			if dev != null and String(dev["state"]) != "":
				var about := "%s: %s" % [String(KINDS[dev["kind"]]["name"]), String(dev["state"])]
				text = about if text == "" else "%s   ·   %s" % [text, about]
	_hint.text = text
	_hint.visible = text != ""


# ------------------------------------------------------------------ saving

func saved() -> Dictionary:
	var parts: Array = []
	for dev: Dev in devices:
		parts.append({"kind": dev["kind"], "at": (dev["node"] as Node3D).global_transform, "charge": dev["charge"]})
	var lines: Array = []
	for cable: Line in cables:
		var ends: Array = []
		for e in 2:
			var end: Dictionary = cable["ends"][e]
			if end.get("dev") != null:
				ends.append({"dev": devices.find(end["dev"]), "socket": end["socket"]})
			else:
				# (An end in hand is saved lying where it is.)
				ends.append({"at": _end_frame(cable, e)})
		lines.append({"ends": ends, "pts": (cable["pts"] as PackedVector3Array).duplicate()})
	return {"parts": parts, "cables": lines}


func restore(data: Dictionary) -> void:
	_carry = null
	_carry_end = -1
	for cable: Line in cables:
		(cable["node"] as Node).queue_free()
		for plug: Node in cable["plugs"]:
			plug.queue_free()
	cables.clear()
	for dev: Dev in devices:
		(dev["node"] as Node).queue_free()
	devices.clear()
	for p: Dictionary in data.get("parts", []):
		set_down(String(p["kind"]), p["at"], float(p.get("charge", 0.0)))
	for line: Dictionary in data.get("cables", []):
		var cable := _new_cable()
		for e in 2:
			var end: Dictionary = line["ends"][e]
			if end.has("dev") and int(end["dev"]) >= 0 and int(end["dev"]) < devices.size():
				_plug(cable, e, devices[int(end["dev"])], int(end["socket"]))
			else:
				cable["ends"][e] = {"at": end.get("at", Transform3D.IDENTITY)}
		cable["pts"] = (line["pts"] as PackedVector3Array).duplicate()
		cable["old"] = (line["pts"] as PackedVector3Array).duplicate()
		# (As it lay: drawn once, and set.)
		_draw_cable(cable)
		cable["live"] = false
	_stamp += 1
	_tick = 0.0
