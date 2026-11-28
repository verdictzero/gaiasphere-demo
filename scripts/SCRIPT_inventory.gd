class_name Inventory
extends CanvasLayer

# THE HOTBAR AND THE BAG.
#
# Nine slots along the bottom of the screen, always shown; 1-9 (or a tap) picks
# one. TAB or I (pad Start, the BAG touch button) opens the bag: twenty-seven
# more slots.
#
#   left click     pick a stack up, put it down, swap, or add to a like stack
#   right click    take half a stack, or put one down
#
# CRAFTING IS ITS OWN MENU (B, the CRAFT touch button), not part of the bag: a
# panel of TABS, one to each kind of thing (TABS: building, camp, power,
# defence), and under the tab chosen a row for each thing of that kind that can
# be made, with what it takes. A row you have the makings of is lit; click it and
# the makings leave the bag and the thing arrives in it. (1-4, or the wheel, go
# from tab to tab; B or TAB again, Escape, or a click outside shuts it.)

const STACK := 64
const HOTBAR := 9
const BAG := 36          # the hotbar's nine and twenty-seven more

const ITEMS := {
	"log": {"name": "Fir Log", "icon": "res://assets/ui/item_log.png"},
	"axe": {"name": "Axe", "icon": "res://assets/ui/item_axe.png"},
	"pickaxe": {"name": "Pickaxe", "icon": "res://assets/ui/item_pickaxe.png"},
	"sword": {"name": "Sword", "icon": "res://assets/ui/item_sword.png"},
	"katana": {"name": "Katana", "icon": "res://assets/ui/item_katana.png"},
	"stone": {"name": "Stone", "icon": "res://assets/ui/item_stone.png"},
	"berry": {"name": "Berries", "icon": "res://assets/ui/item_berry.png"},
	"beef": {"name": "Raw Beef", "icon": "res://assets/ui/item_beef.png"},
	"steak": {"name": "Cooked Beef", "icon": "res://assets/ui/item_steak.png"},
	"wall": {"name": "Plank Wall", "icon": "res://assets/ui/item_wall.png"},
	"doorway": {"name": "Doorway and Door", "icon": "res://assets/ui/item_doorway.png"},
	"floor": {"name": "Plank Floor", "icon": "res://assets/ui/item_floor.png"},
	"roof": {"name": "Plank Roof", "icon": "res://assets/ui/item_roof.png"},
	"gable": {"name": "Gable", "icon": "res://assets/ui/item_gable.png"},
	"stairs": {"name": "Plank Stairs", "icon": "res://assets/ui/item_stairs.png"},
	"campfire": {"name": "Cooking Fire", "icon": "res://assets/ui/item_campfire.png"},
	"foundation": {"name": "Stone Foundation", "icon": "res://assets/ui/item_foundation.png"},
	"steps": {"name": "Stone Steps", "icon": "res://assets/ui/item_steps.png"},
	"solar_panel": {"name": "Solar Panel", "icon": "res://assets/ui/item_solar_panel.png"},
	"battery": {"name": "Battery", "icon": "res://assets/ui/item_battery.png"},
	"junction": {"name": "Junction Box", "icon": "res://assets/ui/item_junction.png"},
	"light_pole": {"name": "Light Pole", "icon": "res://assets/ui/item_light_pole.png"},
	"cable": {"name": "Cable", "icon": "res://assets/ui/item_cable.png"},
	"laser_ciws": {"name": "Laser CIWS", "icon": "res://assets/ui/item_laser_ciws.png"},
}

## What can be made, in the order the list shows it, and what each takes.
## The crafting menu's tabs, in order; each recipe says which it is under ("tab").
const TABS := ["BUILDING", "CAMP", "POWER", "DEFENCE"]
const RECIPES := [
	# (Beef is cooked on the fire, not in the bag: SCRIPT_cooking.gd.)
	{"makes": "campfire", "tab": 1, "needs": {"log": 3, "stone": 6}},
	{"makes": "wall", "tab": 0, "needs": {"log": 4}},
	{"makes": "doorway", "tab": 0, "needs": {"log": 6}},
	{"makes": "floor", "tab": 0, "needs": {"log": 3}},
	{"makes": "roof", "tab": 0, "needs": {"log": 4}},
	{"makes": "gable", "tab": 0, "needs": {"log": 2}},
	{"makes": "stairs", "tab": 0, "needs": {"log": 5}},
	{"makes": "foundation", "tab": 0, "needs": {"log": 2, "stone": 8}},
	{"makes": "steps", "tab": 0, "needs": {"log": 2, "stone": 5}},
	# Power (SCRIPT_power.gd).
	{"makes": "solar_panel", "tab": 2, "needs": {"log": 4, "stone": 12}},
	{"makes": "battery", "tab": 2, "needs": {"log": 4, "stone": 10}},
	{"makes": "junction", "tab": 2, "needs": {"log": 2, "stone": 6}},
	{"makes": "light_pole", "tab": 2, "needs": {"log": 6, "stone": 6}},
	{"makes": "cable", "tab": 2, "needs": {"log": 1, "stone": 2}},
	{"makes": "laser_ciws", "tab": 3, "needs": {"log": 8, "stone": 20}},
]

const PANEL := Color(0.075, 0.085, 0.1, 0.9)
const SLOT := Color(1, 1, 1, 0.065)
const EDGE := Color(1, 1, 1, 0.14)
const ACCENT := Color(0.56, 0.86, 1.0)
const INK := Color(0.93, 0.95, 0.97)

## True while the bag is open: the sword and the look stand down.
static var menu_open := false

var slots: Array = []        # BAG entries, each null or [id, count]
var selected := 0
var _held: Variant = null    # the stack on the cursor
var _view: Control
var _icons := {}
var _font: Font
var _hover := -1
var _craft_hover := -1
var _tab := 0                # the crafting menu's tab
var _tab_hover := -1
## True while the menu that is up is the crafting one (and `menu_open` with it).
static var crafting := false
var _made := -1              # the recipe just made, and how long ago: its row flashes
var _made_for := 0.0
var _was_captured := false
var _shown := 0.0            # 0 shut .. 1 open, eased


func _ready() -> void:
	layer = 30
	menu_open = false
	slots.resize(BAG)
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
	if not InputMap.has_action(&"wv_craft"):
		InputMap.add_action(&"wv_craft")
		var craft_key := InputEventKey.new()
		craft_key.physical_keycode = KEY_B
		InputMap.action_add_event(&"wv_craft", craft_key)
		var craft_pad := InputEventJoypadButton.new()
		craft_pad.button_index = JOY_BUTTON_BACK
		InputMap.action_add_event(&"wv_craft", craft_pad)
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_gui_input)
	add_child(_view)


func _exit_tree() -> void:
	menu_open = false


func _process(delta: float) -> void:
	var want := 1.0 if menu_open else 0.0
	if _shown != want:
		_shown = move_toward(_shown, want, delta * 7.0)
		_view.queue_redraw()
	if _made_for > 0.0:
		_made_for = maxf(_made_for - delta, 0.0)
		_view.queue_redraw()


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


## One off the stack in the hotbar slot in hand. True if there was one to take.
func take_selected() -> bool:
	var stack: Variant = slots[selected]
	if stack == null:
		return false
	stack[1] = int(stack[1]) - 1
	if int(stack[1]) <= 0:
		slots[selected] = null
	if _view != null:
		_view.queue_redraw()
	return true


func count_of(id: String) -> int:
	var n := 0
	for i in BAG:
		if slots[i] != null and slots[i][0] == id:
			n += int(slots[i][1])
	return n


## Take `count` of `id` out of the bag, wherever it lies. False (and nothing
## taken) if there is not that much.
func take(id: String, count: int) -> bool:
	if count_of(id) < count:
		return false
	for i in range(BAG - 1, -1, -1):          # the bag's own rows first, the hotbar last
		if count <= 0:
			break
		if slots[i] != null and slots[i][0] == id:
			var out := mini(count, int(slots[i][1]))
			slots[i][1] = int(slots[i][1]) - out
			count -= out
			if int(slots[i][1]) <= 0:
				slots[i] = null
	if _view != null:
		_view.queue_redraw()
	return true


# ------------------------------------------------------------------ making things

func can_craft(recipe: int) -> bool:
	if Vitals.debug:
		return true
	var needs: Dictionary = RECIPES[recipe]["needs"]
	for id in needs:
		if count_of(id) < int(needs[id]):
			return false
	return true


## Make one of recipe `recipe`: its makings out of the bag, the thing into it.
## False if the makings are not there, or there is nowhere to put it.
func craft(recipe: int) -> bool:
	if recipe < 0 or recipe >= RECIPES.size() or not can_craft(recipe):
		return false
	var needs: Dictionary = RECIPES[recipe]["needs"] if not Vitals.debug else {}
	for id in needs:
		take(id, int(needs[id]))
	if add(String(RECIPES[recipe]["makes"]), 1) > 0:
		for id in needs:                         # no room: the makings go back
			add(id, int(needs[id]))
		return false
	_made = recipe
	_made_for = 0.45
	return true


# ------------------------------------------------------------------ open and shut

## Open or shut; `craft`: the crafting menu, not the bag (one or the other).
func set_open(open: bool, craft := false) -> void:
	if open == menu_open and (not open or craft == crafting):
		return
	if open and menu_open and _held != null:
		add(_held[0], int(_held[1]))            # (from one to the other: nothing left on the cursor)
		_held = null
	var was_open := menu_open
	menu_open = open
	crafting = open and craft
	_view.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if open:
		if not was_open:
			_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		# Nothing is left on the cursor.
		if _held != null:
			add(_held[0], int(_held[1]))
			_held = null
		_hover = -1
		_craft_hover = -1
		_tab_hover = -1
		if _was_captured and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"wv_bag"):
		set_open(not (menu_open and not crafting), false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"wv_craft"):
		set_open(not (menu_open and crafting), true)
		get_viewport().set_input_as_handled()
	elif menu_open and crafting and event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_tab = posmod(_tab + (1 if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), TABS.size())
		_view.queue_redraw()
		get_viewport().set_input_as_handled()
	elif menu_open and event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if menu_open and crafting and k >= KEY_1 and k < KEY_1 + TABS.size():
			_tab = k - KEY_1
			_view.queue_redraw()
		elif k >= KEY_1 and k <= KEY_9:
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
	return UiFit.scale(_view.size)


func _panel_rect() -> Rect2:
	var k := _k()
	var cell := 84.0 * k
	var w := cell * 9.0 + 56.0 * k
	var h := cell * 4.0 + 132.0 * k
	return Rect2(Vector2((_view.size.x - w) * 0.5, (_view.size.y - h) * 0.5), Vector2(w, h))


const CRAFT_W := 640.0
const CRAFT_ROW := 56.0
const CRAFT_TOP := 138.0      # the title and the tabs, above the first row


## The recipes under the tab chosen, by their places in RECIPES.
func _tab_recipes() -> Array:
	var out: Array = []
	for i in RECIPES.size():
		if int(RECIPES[i]["tab"]) == _tab:
			out.append(i)
	return out


func _most_rows() -> int:
	var most := 1
	for t in TABS.size():
		var n := 0
		for r: Dictionary in RECIPES:
			if int(r["tab"]) == t:
				n += 1
		most = maxi(most, n)
	return most


## The crafting panel: in the middle of the screen, as tall as its longest tab
## needs (so it does not change size from tab to tab).
func _craft_rect() -> Rect2:
	var k := _k()
	var size := Vector2(CRAFT_W, CRAFT_TOP + CRAFT_ROW * float(_most_rows()) + 16.0) * k
	return Rect2((_view.size - size) * 0.5, size)


func _tab_rect(t: int) -> Rect2:
	var k := _k()
	var c := _craft_rect()
	var gap := 8.0 * k
	var w := (c.size.x - 28.0 * k - gap * float(TABS.size() - 1)) / float(TABS.size())
	return Rect2(c.position + Vector2(14.0 * k + (w + gap) * float(t), 74.0 * k), Vector2(w, 46.0 * k))


func _tab_at(at: Vector2) -> int:
	for t in TABS.size():
		if _tab_rect(t).has_point(at):
			return t
	return -1


## The row of the `n`th recipe under the tab chosen.
func _craft_row(n: int) -> Rect2:
	var k := _k()
	var c := _craft_rect()
	return Rect2(c.position + Vector2(14.0, CRAFT_TOP + CRAFT_ROW * float(n)) * k, Vector2(CRAFT_W - 28.0, CRAFT_ROW - 6.0) * k)


## The recipe (its place in RECIPES) whose row is at `at`, or -1.
func _craft_at(at: Vector2) -> int:
	var list := _tab_recipes()
	for n in list.size():
		if _craft_row(n).has_point(at):
			return list[n]
	return -1


func _slot_rect(i: int) -> Rect2:
	var k := _k()
	var cell := 84.0 * k
	var s := Vector2(74.0, 74.0) * k
	if not menu_open:
		var x0 := (_view.size.x - cell * 9.0) * 0.5
		return Rect2(Vector2(x0 + cell * float(i) + 5.0 * k, _view.size.y - cell - 26.0 * k), s)
	var p := _panel_rect()
	var left := p.position.x + 28.0 * k + 5.0 * k
	if i < HOTBAR:
		return Rect2(Vector2(left + cell * float(i), p.end.y - cell - 22.0 * k), s)
	var j := i - HOTBAR
	return Rect2(Vector2(left + cell * float(j % 9), p.position.y + 76.0 * k + cell * float(j / 9)), s)


func _slot_at(at: Vector2) -> int:
	for i in BAG:
		if _slot_rect(i).has_point(at):
			return i
	return -1


# ------------------------------------------------------------------ the clicks

func _on_gui_input(event: InputEvent) -> void:
	if not menu_open:
		return
	if event is InputEventMouseMotion:
		var at := (event as InputEventMouseMotion).position
		_hover = -1 if crafting else _slot_at(at)
		_craft_hover = _craft_at(at) if crafting else -1
		_tab_hover = _tab_at(at) if crafting else -1
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if crafting:
		# The crafting menu: a tab, a row, or (outside it) shut.
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var tab := _tab_at(mb.position)
		var row := _craft_at(mb.position)
		if tab >= 0:
			_tab = tab
		elif row >= 0:
			craft(row)
		elif not _craft_rect().has_point(mb.position):
			set_open(false)
		_view.queue_redraw()
		return
	var i := _slot_at(mb.position)
	if i < 0:
		if not _panel_rect().has_point(mb.position) and _held == null:
			set_open(false)       # a click outside shuts the bag
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
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


# ------------------------------------------------------------------ drawing

func _box(r: Rect2, fill: Color, radius: float, edge := Color(0, 0, 0, 0), width := 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius * _k()))
	sb.corner_detail = 10
	sb.anti_aliasing = true
	if width > 0.0:
		sb.set_border_width_all(maxi(1, int(round(width * _k()))))
		sb.border_color = edge
	_view.draw_style_box(sb, r)


func _label(at: Vector2, text: String, px: float, color: Color, centred := false) -> void:
	var fs := int(px * _k())
	if centred:
		at.x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
	_view.draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw_stack(r: Rect2, stack: Variant, fade := 1.0) -> void:
	if stack == null:
		return
	var k := _k()
	_view.draw_texture_rect(_icons[stack[0]], r.grow(-5.0 * k), false, Color(1, 1, 1, fade))
	if int(stack[1]) > 1:
		# The count, on a small dark pill in the corner.
		var label := str(int(stack[1]))
		var fs := int(20.0 * k)
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pill := Rect2(r.end - Vector2(w + 16.0 * k, 28.0 * k), Vector2(w + 12.0 * k, 24.0 * k))
		_box(pill, Color(0.03, 0.04, 0.05, 0.82 * fade), 12.0)
		_view.draw_string(_font, pill.position + Vector2(6.0, 18.5) * k, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(INK.r, INK.g, INK.b, fade))


func _draw_slot(r: Rect2, i: int, in_panel: bool) -> void:
	var picked := i == selected and i < HOTBAR
	var fill := SLOT if in_panel else Color(0.06, 0.07, 0.085, 0.62)
	if in_panel and i == _hover:
		fill = Color(1, 1, 1, 0.16)
	_box(r, fill, 14.0, ACCENT if picked else EDGE, 3.0 if picked else 1.5)
	if picked:
		# A short bar under the slot in hand.
		_box(Rect2(Vector2(r.get_center().x - 14.0 * _k(), r.end.y + 6.0 * _k()), Vector2(28.0, 4.0) * _k()), ACCENT, 2.0)


func _draw_view() -> void:
	var k := _k()
	if not menu_open:
		for i in HOTBAR:
			var r := _slot_rect(i)
			_draw_slot(r, i, false)
			_draw_stack(r, slots[i])
		if slots[selected] != null:
			_label(Vector2(_view.size.x * 0.5, _slot_rect(0).position.y - 16.0 * k), ITEMS[slots[selected][0]]["name"],
					22.0, Color(INK.r, INK.g, INK.b, 0.9), true)
		return
	var ease_in := 1.0 - pow(1.0 - _shown, 3.0)
	_view.draw_rect(Rect2(Vector2.ZERO, _view.size), Color(0.0, 0.01, 0.02, 0.55 * ease_in))
	_view.draw_set_transform(Vector2(0.0, (1.0 - ease_in) * 26.0 * k))
	if crafting:
		_draw_crafting(ease_in)
		_view.draw_set_transform(Vector2.ZERO)
		return
	var p := _panel_rect()
	_box(p.grow(10.0 * k), Color(0, 0, 0, 0.22 * ease_in), 34.0)          # a soft shadow
	_box(p, Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * ease_in), 26.0, EDGE, 1.5)
	_label(p.position + Vector2(33.0, 50.0) * k, "INVENTORY", 26.0, Color(INK.r, INK.g, INK.b, 0.92 * ease_in))
	var used := 0
	for i in BAG:
		if slots[i] != null:
			used += 1
	var tally := "%d / %d" % [used, BAG]
	var tw := _font.get_string_size(tally, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k)).x
	_label(Vector2(p.end.x - 33.0 * k - tw, p.position.y + 48.0 * k), tally, 20.0, Color(INK.r, INK.g, INK.b, 0.5 * ease_in))
	# A hairline between the bag and the hotbar's row.
	var rule_y := _slot_rect(0).position.y - 12.0 * k
	_view.draw_rect(Rect2(Vector2(p.position.x + 33.0 * k, rule_y), Vector2(p.size.x - 66.0 * k, maxf(1.0, 1.5 * k))),
			Color(1, 1, 1, 0.1 * ease_in))
	for i in BAG:
		var r := _slot_rect(i)
		_draw_slot(r, i, true)
		_draw_stack(r, slots[i], ease_in)
	var mouse := _view.get_local_mouse_position()
	if _held != null:
		_draw_stack(Rect2(mouse - Vector2(40, 40) * k, Vector2(80, 80) * k), _held)
	elif _hover >= 0 and slots[_hover] != null:
		var name: String = ITEMS[slots[_hover][0]]["name"]
		var w := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(21.0 * k)).x
		var tip := Rect2(mouse + Vector2(18, -46) * k, Vector2(w + 28.0 * k, 38.0 * k))
		_box(tip, Color(0.03, 0.04, 0.05, 0.95), 12.0, EDGE, 1.5)
		_label(tip.position + Vector2(14, 26) * k, name, 21.0, INK)
	_view.draw_set_transform(Vector2.ZERO)


## The crafting menu: its tabs, and under them a row to each recipe of the tab
## chosen, its picture and name on the left, what it takes on the right with how
## many of each you have against how many it wants.
func _draw_crafting(fade: float) -> void:
	var k := _k()
	var c := _craft_rect()
	_box(c.grow(10.0 * k), Color(0, 0, 0, 0.22 * fade), 34.0)
	_box(c, Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * fade), 26.0, EDGE, 1.5)
	_label(c.position + Vector2(28.0, 50.0) * k, "CRAFTING", 26.0, Color(INK.r, INK.g, INK.b, 0.92 * fade))
	for t in TABS.size():
		var r := _tab_rect(t)
		var on := t == _tab
		_box(r, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85 * fade) if on else Color(1, 1, 1, (0.16 if t == _tab_hover else 0.065) * fade), 12.0,
				ACCENT if on else EDGE, 1.5)
		_label(Vector2(r.get_center().x, r.position.y + 31.0 * k), TABS[t], 20.0,
				Color(0.03, 0.04, 0.05, fade) if on else Color(INK.r, INK.g, INK.b, 0.9 * fade), true)
	var list := _tab_recipes()
	for n in list.size():
		var i: int = list[n]
		var r := _craft_row(n)
		var able := can_craft(i)
		var dim := (1.0 if able else 0.42) * fade
		var fill := SLOT
		if i == _made and _made_for > 0.0:
			fill = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.1 + 0.5 * _made_for / 0.45)
		elif i == _craft_hover and able:
			fill = Color(1, 1, 1, 0.16)
		_box(r, Color(fill.r, fill.g, fill.b, fill.a * fade), 12.0, ACCENT if (able and i == _craft_hover) else EDGE, 1.5)
		var id := String(RECIPES[i]["makes"])
		var icon := Rect2(r.position + Vector2(8.0, 3.0) * k, Vector2(44.0, 44.0) * k)
		_view.draw_texture_rect(_icons[id], icon, false, Color(1, 1, 1, dim))
		_label(r.position + Vector2(64.0, 33.0) * k, ITEMS[id]["name"], 22.0, Color(INK.r, INK.g, INK.b, 0.95 * dim))
		# What it takes, laid out from the right: a small picture and "have / want".
		var x := r.end.x - 12.0 * k
		var needs: Dictionary = RECIPES[i]["needs"]
		var ids := needs.keys()
		ids.reverse()
		for need in ids:
			var have := count_of(need)
			var text := "%d/%d" % [mini(have, 999), int(needs[need])]
			var fs := int(20.0 * k)
			var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			x -= w
			var enough := have >= int(needs[need])
			var ink := INK if enough else Color(1.0, 0.45, 0.4)
			_view.draw_string(_font, Vector2(x, r.position.y + 32.0 * k), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(ink.r, ink.g, ink.b, (0.9 if enough else 0.95) * fade * (1.0 if able or not enough else 0.6)))
			x -= 40.0 * k
			_view.draw_texture_rect(_icons[need], Rect2(Vector2(x, r.position.y + 7.0 * k), Vector2(36.0, 36.0) * k), false,
					Color(1, 1, 1, fade * (1.0 if enough else 0.55)))
			x -= 16.0 * k
