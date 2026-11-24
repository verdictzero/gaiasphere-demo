class_name Building
extends Node3D

# BUILDING: the crafted pieces (SCRIPT_inventory.gd's crafting list) set down
# in the world, snapping to each other.
#
# Take a piece in hand from the hotbar and a ghost of it stands where you are
# looking: pale blue where it can go, red where it cannot. The use button sets
# it down and takes one from the stack; the turn key (X, the mouse wheel, the
# pad's right shoulder, TURN on a touchscreen) turns it. A swing of the axe at
# a piece takes it down again and gives it back.
#
# EVERYTHING SNAPS TO A GRID, and each building has its own. The first piece
# set down somewhere new goes exactly where you point, facing the way you face
# (the turn key swings it 15 degrees at a time), and lays out a grid of two-metre
# squares round itself; every piece put down near it after that belongs to the
# same grid. On that grid:
#
#   stairs               fill a square as a roof does: a flight from a floor to the
#                        storey above, climbing the way you face
#   foundation, steps    fill a square, sunk into the ground; a foundation's top
#                        is the building's ground floor, steps climb to it
#   floor, roof          fill a square at the foot of a storey (every 2 m up); a
#                        roof rises 45 degrees from the edge nearest you
#   wall, doorway, gable stand on the edge of a square nearest where you point,
#                        facing out of it; aim high on a wall to build on top
#
# Nothing has to rest on anything: there are no rules of support yet. What is
# built lasts as long as the run does. The ground under a foundation or steps
# is cleared of whatever grew there (Flora.clear_ground).

@export var explorer_path: NodePath = ^"../Explorer"
@export var inventory_path: NodePath = ^"../Inventory"
@export var hand_path: NodePath = ^"../SwordPlay"
## How far away a piece can be set down, metres.
@export var reach := 7.0
## A piece within this of where you point pulls the new one onto its grid.
@export var snap_range := 7.0
## How much of a new building's first foundation shows above the ground.
@export var proud := 0.35

const CELL := 2.0
const STOREY := 2.0
const KIT := "res://assets/build/"
## Each thing that can be built: how it sits on the grid, and the models it is drawn from.
const PIECES := {
	"foundation": {"sits": "square", "files": ["foundation/foundation_a", "foundation/foundation_b", "foundation/foundation_c"]},
	"steps": {"sits": "square", "files": ["foundation/steps_a", "foundation/steps_b"]},
	"floor": {"sits": "square", "files": ["plank_kit/floor_a", "plank_kit/floor_b", "plank_kit/floor_c"]},
	"roof": {"sits": "square", "files": ["plank_kit/roof_a", "plank_kit/roof_b", "plank_kit/roof_c", "plank_kit/roof_d"]},
	"stairs": {"sits": "square", "files": ["plank_kit/stairs_a", "plank_kit/stairs_b"]},
	"wall": {"sits": "edge", "files": ["plank_kit/wall_a", "plank_kit/wall_b", "plank_kit/wall_c", "plank_kit/wall_d",
		"plank_kit/wall_e", "plank_kit/wall_f", "plank_kit/wall_g", "plank_kit/wall_h"]},
	"doorway": {"sits": "edge", "files": ["plank_kit/doorway_a", "plank_kit/doorway_b"]},
	"gable": {"sits": "edge", "files": ["plank_kit/gable_right_a", "plank_kit/gable_right_b"],
		"other_hand": ["plank_kit/gable_left_a", "plank_kit/gable_left_b"]},
}
## The four ways along the grid, in the order the turn key steps through them.
const WAYS := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]

var _explorer: Node3D
var _bag: Inventory
var _hand: Node
var _buildings: Array = []      # each {"frame": Transform3D, "slots": {key: the piece's node}}
var _turns := 0
var _ghost: Node3D
var _ghost_of := ""
var _ghost_ok: StandardMaterial3D
var _ghost_no: StandardMaterial3D
var _plan := {}
var _hint: Label


func _ready() -> void:
	_explorer = get_node_or_null(explorer_path)
	_bag = get_node_or_null(inventory_path) as Inventory
	_hand = get_node_or_null(hand_path)
	if not InputMap.has_action(&"wv_turn"):
		InputMap.add_action(&"wv_turn")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_X
		InputMap.action_add_event(&"wv_turn", key)
		for button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var wheel := InputEventMouseButton.new()
			wheel.button_index = button
			InputMap.action_add_event(&"wv_turn", wheel)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_RIGHT_SHOULDER
		InputMap.action_add_event(&"wv_turn", pad)
	_ghost_ok = _ghost_material(Color(0.5, 0.85, 1.0, 0.42))
	_ghost_no = _ghost_material(Color(1.0, 0.25, 0.2, 0.42))
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
	_hint.offset_top = -182.0
	_hint.offset_bottom = -156.0
	_hint.offset_left = -400.0
	_hint.offset_right = 400.0
	_hint.visible = false
	layer.add_child(_hint)


static func _ghost_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## The piece in hand, or "" if what is in hand is not for building.
func holding() -> String:
	if _bag == null or _bag.slots[_bag.selected] == null:
		return ""
	var id := String(_bag.slots[_bag.selected][0])
	return id if PIECES.has(id) else ""


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"wv_turn") and holding() != "" and not _menus():
		_turns += -1 if (event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN) else 1


func _menus() -> bool:
	return Inventory.menu_open or GraphicsMenu.menu_open or EnvironmentMenu.menu_open


func _process(_delta: float) -> void:
	var item := holding()
	var cam := get_viewport().get_camera_3d()
	if item == "" or cam == null or _menus() or _explorer == null:
		if _ghost != null:
			_ghost.visible = false
		_hint.visible = false
		_plan = {}
		return
	if item != _ghost_of:
		_new_ghost(item)
	_plan = aim(item, cam.global_position, -cam.global_basis.z, _turns)
	_ghost.visible = not _plan.is_empty()
	_hint.visible = true
	_hint.text = "USE  set down      %s  turn      AXE  take down" % ("TURN" if DisplayServer.is_touchscreen_available() else "X / WHEEL")
	if _plan.is_empty():
		return
	_ghost.global_transform = _plan["at"]
	_tint(_ghost, _ghost_ok if bool(_plan["free"]) else _ghost_no)
	if item == "gable":
		_ghost.get_child(0).visible = not bool(_plan.get("other_hand", false))
		_ghost.get_child(1).visible = bool(_plan.get("other_hand", false))
	if not Input.is_action_just_pressed(&"wv_attack") or not bool(_plan["free"]):
		return
	if _hand != null and not bool(_hand.call(&"_mouse_ready")):
		return
	# A door in front of you is worked, not built over (SCRIPT_sword_play.gd).
	for thing in get_tree().get_nodes_in_group(&"usable"):
		if bool(thing.call(&"can_use", cam.global_position, -cam.global_basis.z)):
			return
	if Vitals.debug or _bag.take_selected():          # (in debug mode a piece is not used up)
		build(_plan)


func _new_ghost(item: String) -> void:
	if _ghost != null:
		_ghost.queue_free()
	_ghost_of = item
	_ghost = Node3D.new()
	_ghost.name = "Ghost"
	add_child(_ghost)
	var files: Array = [PIECES[item]["files"][0]]
	if PIECES[item].has("other_hand"):
		files.append(PIECES[item]["other_hand"][0])
	for file in files:
		_ghost.add_child((load(KIT + String(file) + "_lod0.glb") as PackedScene).instantiate())
	for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _tint(node: Node, mat: Material) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat


# ------------------------------------------------------------------ where a piece would go

## Where `item` would go for someone at `from` looking along `dir`, having turned
## it `turns` times: {} if nowhere, else what `build` needs, with "at" (where the
## piece stands in the world) and "free" (whether it may be put there).
func aim(item: String, from: Vector3, dir: Vector3, turns := 0) -> Dictionary:
	dir = dir.normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
	if _explorer is CollisionObject3D:
		q.exclude = [(_explorer as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var point: Vector3 = hit["position"]
	# Which building's grid: that of the nearest piece standing near the point.
	var home := -1
	var nearest := snap_range
	for b in _buildings.size():
		for piece in (_buildings[b]["slots"] as Dictionary).values():
			var away := ((piece as Node3D).global_position - point).length()
			if away < nearest:
				nearest = away
				home = b
	var frame: Transform3D
	var quarter := turns
	if home >= 0:
		frame = _buildings[home]["frame"]
	else:
		# NEW GROUND: the piece goes where you point, facing as you face, and the
		# grid is laid out from it. (Here the turn key swings the whole grid.)
		var facing := snappedf(atan2(-dir.x, -dir.z), deg_to_rad(15.0)) + deg_to_rad(15.0) * float(turns)
		var basis := Basis(Vector3.UP, facing)
		var sunk: bool = item == "foundation" or item == "steps"
		# (A square is centred on the point; a wall stands on it, across your way.)
		var spot := Vector3(CELL * 0.5, 0, CELL - 0.01 if PIECES[item]["sits"] == "edge" else CELL * 0.5)
		frame = Transform3D(basis, point + Vector3(0, proud if sunk else 0.0, 0) - basis * spot)
		quarter = 0
	var inv := frame.affine_inverse()
	var plan := place(item, inv * point, inv.basis * dir, quarter)
	plan["building"] = home
	plan["frame"] = frame
	plan["at"] = frame * (plan["stands"] as Transform3D)
	plan["free"] = home < 0 or not (_buildings[home]["slots"] as Dictionary).has(plan["key"])
	# Not on top of whoever is building it.
	if plan["free"] and (item == "foundation" or item == "steps"):
		var me: Vector3 = (plan["at"] as Transform3D).affine_inverse() * _explorer.global_position
		if absf(me.x) < 1.35 and absf(me.z) < 1.35 and me.y > -0.5 and me.y < 3.0:
			plan["free"] = false
	return plan


## The grid's answer, in a building's own frame: where `item` goes when pointed
## at `p` (a point in that frame) by someone looking along `look`.
func place(item: String, p: Vector3, look: Vector3, turns: int) -> Dictionary:
	var flat := Vector3(look.x, 0, look.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3(0, 0, -1)
	# The way you face, to the nearest of the grid's four, and turned from there.
	var ahead := 0
	for w in 4:
		if (WAYS[w] as Vector3).dot(flat) > (WAYS[ahead] as Vector3).dot(flat):
			ahead = w
	var way: Vector3 = WAYS[posmod(ahead + turns, 4)]
	var facing := atan2(-way.x, -way.z)                    # the turn that takes a model's -z to `way`
	match item:
		"foundation", "steps":
			# The square on your side of what you point at; its top level with the
			# floor above the ground there.
			var q := p - look * 0.06
			var cell := Vector2i(int(floor(q.x / CELL)), int(floor(q.z / CELL)))
			var top := int(ceil(p.y - 0.05))
			var mid := Vector3((float(cell.x) + 0.5) * CELL, 0, (float(cell.y) + 0.5) * CELL)
			if item == "foundation":
				return {"item": item, "key": "F:%d:%d:%d" % [cell.x, cell.y, top],
					"stands": Transform3D(Basis(Vector3.UP, facing), mid + Vector3(0, top - 1, 0))}
			return {"item": item, "key": "S:%d:%d:%d" % [cell.x, cell.y, top],
				"stands": Transform3D(Basis(Vector3.UP, facing), mid + Vector3(0, top - 1, 0))}
		"floor", "roof", "stairs":
			# The square beyond what you point at, at the foot of the nearest storey.
			var q := p + look * 0.12
			var cell := Vector2i(int(floor(q.x / CELL)), int(floor(q.z / CELL)))
			var level := int(round(p.y / STOREY)) * int(STOREY)
			var mid := Vector3((float(cell.x) + 0.5) * CELL, level, (float(cell.y) + 0.5) * CELL)
			if item == "floor":
				# (The model's foot is one edge of it, and it lies back from there.)
				return {"item": item, "key": "L:%d:%d:%d" % [cell.x, cell.y, level],
					"stands": Transform3D(Basis(Vector3.UP, facing), mid + Vector3(0, 0.02, 0) - way * (CELL * 0.5))}
			if item == "stairs":
				# (Its foot on the near edge, climbing the way you face to the next storey.)
				return {"item": item, "key": "T:%d:%d:%d" % [cell.x, cell.y, level],
					"stands": Transform3D(Basis(Vector3.UP, facing), mid - way * (CELL * 0.5))}
			return {"item": item, "key": "R:%d:%d:%d" % [cell.x, cell.y, level],
				"stands": Transform3D(Basis(Vector3.UP, facing), mid - way * (CELL * 0.5))}
	# A WALL, A DOORWAY, A GABLE: on the nearest edge of the square pointed into,
	# facing out of it. An odd turn faces it in; for a gable, turns also swap
	# which side its slope climbs to.
	var cell := Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))
	var fx := p.x - float(cell.x) * CELL
	var fz := p.z - float(cell.y) * CELL
	var out := Vector3(-1, 0, 0)
	var least := fx
	if CELL - fx < least:
		least = CELL - fx
		out = Vector3(1, 0, 0)
	if fz < least:
		least = fz
		out = Vector3(0, 0, -1)
	if CELL - fz < least:
		out = Vector3(0, 0, 1)
	var level := int(floor((p.y + 0.9) / STOREY)) * int(STOREY)
	var mid := Vector3((float(cell.x) + 0.5) * CELL, level, (float(cell.y) + 0.5) * CELL) + out * (CELL * 0.5)
	# One piece to an edge, whichever way it faces: the edge is named by where it is.
	var key := "E:%d:%d:%d:%d" % [int(round(mid.x * 2.0)), int(round(mid.z * 2.0)), level, 0]
	var face := out if posmod(turns, 2) == 0 else -out
	return {"item": item, "key": key, "other_hand": posmod(turns, 4) >= 2,
		"stands": Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), mid)}


# ------------------------------------------------------------------ setting it down

## Set down what `aim` planned. Returns the piece.
func build(plan: Dictionary) -> Node3D:
	var b := int(plan["building"])
	if b < 0:
		_buildings.append({"frame": plan["frame"], "slots": {}})
		b = _buildings.size() - 1
	var item := String(plan["item"])
	var key := String(plan["key"])
	var at: Transform3D = plan["at"]
	var files: Array = PIECES[item]["other_hand"] if bool(plan.get("other_hand", false)) else PIECES[item]["files"]
	var file := String(files[absi(hash(key)) % files.size()])        # the same piece in the same place, every time
	var piece: Node3D
	if item == "doorway":
		var door := Door.new()
		door.variant = file.right(1)
		piece = door
	else:
		piece = Node3D.new()
		piece.add_child((load(KIT + file + "_lod0.glb") as PackedScene).instantiate())
		var body := StaticBody3D.new()
		piece.add_child(body)
		_solid(item, body, bool(plan.get("other_hand", false)))
	piece.name = "%s_%s" % [item, key.replace(":", "_")]
	piece.set_meta(&"build_item", item)
	piece.set_meta(&"build_key", key)
	piece.set_meta(&"build_in", b)
	add_child(piece)
	piece.global_transform = at
	(_buildings[b]["slots"] as Dictionary)[key] = piece
	if item == "foundation" or item == "steps":
		for grower in [get_node_or_null(^"../Flora"), get_node_or_null(^"../BerryBushes")]:
			if grower != null:
				grower.call(&"clear_ground", at, Vector2(1.3, 1.3))
	# It drops into place.
	var model := piece.get_child(0) as Node3D
	if model != null and item != "doorway":
		model.position.y = 0.12
		create_tween().tween_property(model, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return piece


## What stops you, for each kind of piece (in the piece's own frame).
func _solid(item: String, body: StaticBody3D, other_hand: bool) -> void:
	match item:
		"foundation":
			_box(body, Vector3(0, 0.5, 0), Vector3(2.0, 1.0, 2.0))
		"steps":
			# Climbed as a slope laid along the noses of the steps (a foot does not
			# take a 20 cm step), with the top one flat.
			_box(body, Vector3(0, 0.411, 0.355), Vector3(2.0, 0.2, 2.236), Vector3(0.4636, 0, 0))
			_box(body, Vector3(0, 0.5, -0.8), Vector3(2.0, 1.0, 0.4))
		"floor":
			_box(body, Vector3(0, 0.0, -1.0), Vector3(2.0, 0.1, 2.0))
		"roof":
			_box(body, Vector3(0, 1.0, -1.0), Vector3(2.0, 0.1, 2.83), Vector3(PI * 0.25, 0, 0))
		"stairs":
			# Climbed as a slope through the middle of the treads, the top one flat.
			_box(body, Vector3(0, 0.965, -0.895), Vector3(2.0, 0.1, 2.83), Vector3(PI * 0.25, 0, 0))
			# (The flat begins where the slope reaches its height: a lip there, even
			# of a hand's breadth, stops a foot coming up the slope dead.)
			_box(body, Vector3(0, 1.95, -1.93), Vector3(2.0, 0.1, 0.14))
		"wall":
			_box(body, Vector3(0, 1.0, 0.03), Vector3(2.0, 2.0, 0.12))
		"gable":
			# A wedge: the wall's thickness, under the slope.
			var high := -1.0 if other_hand else 1.0
			var shape := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for z in [-0.03, 0.09]:
				points.append(Vector3(-1, 0, z))
				points.append(Vector3(1, 0, z))
				points.append(Vector3(high, 2, z))
			shape.points = points
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)


func _box(body: StaticBody3D, at: Vector3, size: Vector3, turn := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = at
	cs.rotation = turn
	body.add_child(cs)


## Set `item` down in building `b` by the grid's own reckoning (see `place`):
## what a hand does by pointing, done by saying where. Null if the place is taken.
func put(b: int, item: String, p: Vector3, look: Vector3, turns := 0) -> Node3D:
	var plan := place(item, p, look, turns)
	if (_buildings[b]["slots"] as Dictionary).has(plan["key"]):
		return null
	plan["building"] = b
	plan["frame"] = _buildings[b]["frame"]
	plan["at"] = (plan["frame"] as Transform3D) * (plan["stands"] as Transform3D)
	return build(plan)


# ------------------------------------------------------------------ taking it down

## A swing of the axe from `from` along `dir`: a built piece it lands on comes
## down and goes back in the bag. True if it met one.
func strike(from: Vector3, dir: Vector3, far := 3.2) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * far)
	if _explorer is CollisionObject3D:
		q.exclude = [(_explorer as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var node := hit["collider"] as Node
	while node != null and node != self and not node.has_meta(&"build_item"):
		node = node.get_parent()
	if node == null or node == self:
		return false
	var slots: Dictionary = _buildings[int(node.get_meta(&"build_in"))]["slots"]
	slots.erase(String(node.get_meta(&"build_key")))
	if _bag != null:
		_bag.add(String(node.get_meta(&"build_item")), 1)
	node.queue_free()
	return true
