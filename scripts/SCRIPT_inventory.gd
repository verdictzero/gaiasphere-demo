class_name Inventory
extends CanvasLayer

# THE HOTBAR, THE BAG AND THE START OF CRAFTING.
#
# Nine slots along the bottom of the screen, always shown; 1-9 (or a tap) picks
# one. TAB or I (pad Start, the BAG touch button) opens the bag: twenty-seven more
# slots, and a two-by-two crafting grid with its result.
#
#   left click     pick a stack up, put it down, swap, or add to a like stack
#   right click    take half a stack, or put one down
#   the result     click to take what the grid makes (shift-click: all it can)
#
# Recipes are shapeless: what is in the grid's cells, one from each, whatever
# cells they are in. They are the `RECIPES` table below and nothing else; add a
# line to add one. Nothing made here can be placed in the world yet.

const STACK := 64
const HOTBAR := 9
const BAG := 36          # the hotbar's nine and twenty-seven more
const GRID := 4          # slots 36..39: the crafting grid
const RESULT := 40

const ITEMS := {
	"log": {"name": "Fir Log", "icon": "res://assets/ui/item_log.png"},
	"planks": {"name": "Planks", "icon": "res://assets/ui/item_planks.png"},
	"sticks": {"name": "Sticks", "icon": "res://assets/ui/item_sticks.png"},
	"workbench": {"name": "Workbench", "icon": "res://assets/ui/item_workbench.png"},
	"campfire": {"name": "Campfire", "icon": "res://assets/ui/item_campfire.png"},
}
## What goes in (one from each of that many cells) and what comes out.
const RECIPES := [
	{"in": {"log": 1}, "out": ["planks", 4]},
	{"in": {"planks": 2}, "out": ["sticks", 4]},
	{"in": {"planks": 4}, "out": ["workbench", 1]},
	{"in": {"log": 2, "sticks": 2}, "out": ["campfire", 1]},
]

## True while the bag is open: the sword and the look stand down.
static var menu_open := false

var slots: Array = []        # BAG + GRID entries, each null or [id, count]
var selected := 0
var _held: Variant = null    # the stack on the cursor
var _view: Control
var _icons := {}
var _font: Font
var _hover := -1
var _was_captured := false


func _ready() -> void:
	layer = 30
	menu_open = false
	slots.resize(BAG + GRID)
	for id in ITEMS:
		_icons[id] = load(ITEMS[id]["icon"])
	_font = load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	if not InputMap.has_action(&"wv_bag"):
		InputMap.add_action(&"wv_bag")
		for code in [KEY_TAB, KEY_I]:
			var key := InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(&"wv_bag", key)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_START
		InputMap.action_add_event(&"wv_bag", pad)
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_gui_input)
	add_child(_view)


func _exit_tree() -> void:
	menu_open = false


# ------------------------------------------------------------------ the stacks

## Put `count` of `id` in the bag: like stacks first, then the first empty slot,
## hotbar first. Returns how many did not fit.
func add(id: String, count: int) -> int:
	for i in BAG:
		if count <= 0:
			break
		if slots[i] != null and slots[i][0] == id and int(slots[i][1]) < STACK:
			var fit := mini(count, STACK - int(slots[i][1]))
			slots[i][1] = int(slots[i][1]) + fit
			count -= fit
	for i in BAG:
		if count <= 0:
			break
		if slots[i] == null:
			var fit := mini(count, STACK)
			slots[i] = [id, fit]
			count -= fit
	if _view != null:
		_view.queue_redraw()
	return count


func count_of(id: String) -> int:
	var n := 0
	for i in BAG:
		if slots[i] != null and slots[i][0] == id:
			n += int(slots[i][1])
	return n


## What the grid makes at the moment: [id, count], or null.
func crafted() -> Variant:
	var have := {}
	for i in range(BAG, BAG + GRID):
		if slots[i] != null:
			have[slots[i][0]] = int(have.get(slots[i][0], 0)) + 1
	if have.is_empty():
		return null
	for recipe in RECIPES:
		if (recipe["in"] as Dictionary).hash() == have.hash() and recipe["in"] == have:
			return recipe["out"]
	return null


func _spend_grid() -> void:
	for i in range(BAG, BAG + GRID):
		if slots[i] != null:
			slots[i][1] = int(slots[i][1]) - 1
			if int(slots[i][1]) <= 0:
				slots[i] = null


# ------------------------------------------------------------------ open and shut

func set_open(open: bool) -> void:
	if open == menu_open:
		return
	menu_open = open
	_view.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if open:
		_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		# Nothing is left behind in the grid or on the cursor.
		for i in range(BAG, BAG + GRID):
			if slots[i] != null:
				add(slots[i][0], int(slots[i][1]))
				slots[i] = null
		if _held != null:
			add(_held[0], int(_held[1]))
			_held = null
		if _was_captured and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"wv_bag"):
		set_open(not menu_open)
		get_viewport().set_input_as_handled()
	elif menu_open and event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			selected = k - KEY_1
			_view.queue_redraw()
	elif not menu_open and event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# A tap on the hotbar picks that slot.
		for i in HOTBAR:
			if _slot_rect(i).has_point((event as InputEventMouseButton).position):
				selected = i
				_view.queue_redraw()
				get_viewport().set_input_as_handled()
	elif menu_open and event is InputEventMouseMotion:
		_view.queue_redraw()


# ------------------------------------------------------------------ layout

func _k() -> float:
	return _view.size.y / 1080.0


func _panel_rect() -> Rect2:
	var k := _k()
	var cell := 78.0 * k
	var w := cell * 9.0 + 48.0 * k
	var h := cell * 6.0 + 150.0 * k
	return Rect2((_view.size - Vector2(w, h)) * 0.5, Vector2(w, h))


func _slot_rect(i: int) -> Rect2:
	var k := _k()
	var cell := 78.0 * k
	var s := Vector2(72.0, 72.0) * k
	if not menu_open:
		var x0 := (_view.size.x - cell * 9.0) * 0.5
		return Rect2(Vector2(x0 + cell * float(i) + 3.0 * k, _view.size.y - cell - 22.0 * k), s)
	var p := _panel_rect()
	var left := p.position.x + 24.0 * k + 3.0 * k
	if i < HOTBAR:
		return Rect2(Vector2(left + cell * float(i), p.end.y - cell - 20.0 * k), s)
	if i < BAG:
		var j := i - HOTBAR
		return Rect2(Vector2(left + cell * float(j % 9), p.end.y - cell * 4.0 - 38.0 * k + cell * float(j / 9)), s)
	var top := p.position.y + 62.0 * k
	if i < BAG + GRID:
		var j := i - BAG
		return Rect2(Vector2(left + cell * (1.0 + float(j % 2)), top + cell * float(j / 2)), s)
	return Rect2(Vector2(left + cell * 4.3, top + cell * 0.5), s)


func _slot_at(at: Vector2) -> int:
	for i in RESULT + 1:
		if _slot_rect(i).has_point(at):
			return i
	return -1


# ------------------------------------------------------------------ the clicks

func _on_gui_input(event: InputEvent) -> void:
	if not menu_open:
		return
	if event is InputEventMouseMotion:
		_hover = _slot_at((event as InputEventMouseMotion).position)
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var i := _slot_at(mb.position)
	if i < 0:
		if not _panel_rect().has_point(mb.position) and _held == null:
			set_open(false)       # a click outside shuts the bag
		return
	if i == RESULT:
		_take_result(mb.shift_pressed)
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		if i < HOTBAR:
			selected = i
		var there: Variant = slots[i]
		if _held != null and there != null and there[0] == _held[0]:
			var fit := mini(int(_held[1]), STACK - int(there[1]))
			there[1] = int(there[1]) + fit
			_held[1] = int(_held[1]) - fit
			if int(_held[1]) <= 0:
				_held = null
		else:
			slots[i] = _held
			_held = there
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		var there: Variant = slots[i]
		if _held == null and there != null:
			var half := (int(there[1]) + 1) / 2
			_held = [there[0], half]
			there[1] = int(there[1]) - half
			if int(there[1]) <= 0:
				slots[i] = null
		elif _held != null and (there == null or (there[0] == _held[0] and int(there[1]) < STACK)):
			if there == null:
				slots[i] = [_held[0], 1]
			else:
				there[1] = int(there[1]) + 1
			_held[1] = int(_held[1]) - 1
			if int(_held[1]) <= 0:
				_held = null
	_view.queue_redraw()


func _take_result(all: bool) -> void:
	for round_ in 256:
		var out: Variant = crafted()
		if out == null:
			return
		if all:
			if add(out[0], int(out[1])) > 0:
				return
		elif _held == null:
			_held = [out[0], int(out[1])]
		elif _held[0] == out[0] and int(_held[1]) + int(out[1]) <= STACK:
			_held[1] = int(_held[1]) + int(out[1])
		else:
			return
		_spend_grid()
		if not all:
			return


# ------------------------------------------------------------------ drawing

func _text(at: Vector2, text: String, px: float, color: Color) -> void:
	var fs := int(px * _k())
	_view.draw_string(_font, at + Vector2(2, 2) * _k(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, color.a * 0.7))
	_view.draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw_stack(r: Rect2, stack: Variant) -> void:
	if stack == null:
		return
	_view.draw_texture_rect(_icons[stack[0]], r.grow(-6.0 * _k()), false)
	if int(stack[1]) > 1:
		var label := str(int(stack[1]))
		var fs := int(26.0 * _k())
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_text(r.end - Vector2(w + 5.0 * _k(), 5.0 * _k()), label, 26.0, Color.WHITE)


## A sunk square, the way a slot is cut into the panel.
func _draw_slot(r: Rect2, i: int) -> void:
	var k := _k()
	if menu_open:
		_view.draw_rect(r, Color(0.545, 0.545, 0.545))
		_view.draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0 * k)), Color(0.22, 0.22, 0.22))
		_view.draw_rect(Rect2(r.position, Vector2(3.0 * k, r.size.y)), Color(0.22, 0.22, 0.22))
		_view.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3.0 * k), Vector2(r.size.x, 3.0 * k)), Color(1, 1, 1))
		_view.draw_rect(Rect2(r.position + Vector2(r.size.x - 3.0 * k, 0), Vector2(3.0 * k, r.size.y)), Color(1, 1, 1))
		if i == _hover:
			_view.draw_rect(r.grow(-3.0 * k), Color(1, 1, 1, 0.3))
	else:
		_view.draw_rect(r, Color(0.05, 0.05, 0.05, 0.5))
		_view.draw_rect(r, Color(0.55, 0.55, 0.55, 0.85), false, 3.0 * k)
	if i == selected and i < HOTBAR:
		_view.draw_rect(r.grow(3.0 * k), Color(1, 1, 1, 0.95), false, 5.0 * k)


func _draw_view() -> void:
	var k := _k()
	if not menu_open:
		for i in HOTBAR:
			var r := _slot_rect(i)
			_draw_slot(r, i)
			_draw_stack(r, slots[i])
		if slots[selected] != null:
			var name: String = ITEMS[slots[selected][0]]["name"]
			var w := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24.0 * k)).x
			_text(Vector2((_view.size.x - w) * 0.5, _slot_rect(0).position.y - 14.0 * k), name, 24.0, Color(1, 1, 1, 0.9))
		return
	_view.draw_rect(Rect2(Vector2.ZERO, _view.size), Color(0, 0, 0, 0.45))
	var p := _panel_rect()
	_view.draw_rect(p, Color(0.776, 0.776, 0.776))
	_view.draw_rect(Rect2(p.position, Vector2(p.size.x, 5.0 * k)), Color(1, 1, 1))
	_view.draw_rect(Rect2(p.position, Vector2(5.0 * k, p.size.y)), Color(1, 1, 1))
	_view.draw_rect(Rect2(p.position + Vector2(0, p.size.y - 5.0 * k), Vector2(p.size.x, 5.0 * k)), Color(0.33, 0.33, 0.33))
	_view.draw_rect(Rect2(p.position + Vector2(p.size.x - 5.0 * k, 0), Vector2(5.0 * k, p.size.y)), Color(0.33, 0.33, 0.33))
	_view.draw_rect(p, Color(0, 0, 0), false, 2.0 * k)
	var ink := Color(0.25, 0.25, 0.25)
	var fs := int(28.0 * k)
	_view.draw_string(_font, p.position + Vector2(27.0, 44.0) * k, "CRAFTING", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	_view.draw_string(_font, Vector2(p.position.x + 27.0 * k, _slot_rect(HOTBAR).position.y - 12.0 * k), "INVENTORY",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	# The arrow from the grid to what it makes.
	var a := _slot_rect(RESULT)
	var mid := Vector2(a.position.x - 62.0 * k, a.get_center().y)
	_view.draw_rect(Rect2(mid - Vector2(34.0, 5.0) * k, Vector2(48.0, 10.0) * k), ink)
	_view.draw_colored_polygon(PackedVector2Array([mid + Vector2(14, -18) * k, mid + Vector2(40, 0) * k, mid + Vector2(14, 18) * k]), ink)
	# What can be made, written out: this is the whole of the crafting so far.
	var x := a.end.x + 22.0 * k
	var y := p.position.y + 44.0 * k
	_view.draw_string(_font, Vector2(x, y), "RECIPES", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	for recipe in RECIPES:
		y += 34.0 * k
		var parts: Array = []
		for id in recipe["in"]:
			parts.append("%d %s" % [int(recipe["in"][id]), ITEMS[id]["name"]])
		_view.draw_string(_font, Vector2(x, y), "%s  >  %d %s" % [" + ".join(parts), int(recipe["out"][1]), ITEMS[recipe["out"][0]]["name"]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k), ink)
	for i in RESULT + 1:
		var r := _slot_rect(i)
		_draw_slot(r, i)
		_draw_stack(r, crafted() if i == RESULT else slots[i])
	var mouse := _view.get_local_mouse_position()
	if _held != null:
		_draw_stack(Rect2(mouse - Vector2(36, 36) * k, Vector2(72, 72) * k), _held)
	elif _hover >= 0:
		var under: Variant = crafted() if _hover == RESULT else slots[_hover]
		if under != null:
			var name: String = ITEMS[under[0]]["name"]
			var w := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24.0 * k)).x
			var box := Rect2(mouse + Vector2(18, -40) * k, Vector2(w + 20.0 * k, 36.0 * k))
			_view.draw_rect(box, Color(0.08, 0.02, 0.12, 0.92))
			_view.draw_rect(box, Color(0.3, 0.1, 0.6), false, 2.0 * k)
			_view.draw_string(_font, box.position + Vector2(10, 26) * k, name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24.0 * k), Color.WHITE)
