extends SceneTree

# THE CRAFTING MENU, LOOKED AT (by itself, no island): each of its tabs, and the
# bag, to renders/craft_<tab>.png and renders/craft_bag.png.
#
#   godot --path . --resolution 1280x720 --script res://tests/RENDER_craft_menu.gd

var _bag: Inventory
var _n := 0
var _shot := 0


func _initialize() -> void:
	var back := ColorRect.new()
	back.color = Color(0.25, 0.4, 0.3)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	_bag = Inventory.new()
	root.add_child(_bag)


func _process(_d: float) -> bool:
	_n += 1
	if _n == 3:
		_bag.add("log", 12)
		_bag.add("stone", 9)
		_bag.set_open(true, true)
	if _n < 40 or _n % 30 != 0:
		return false
	var names := Inventory.TABS.duplicate()
	names.append("bag")
	root.get_viewport().get_texture().get_image().save_png("res://renders/craft_%s.png" % String(names[_shot]).to_lower())
	_shot += 1
	if _shot < Inventory.TABS.size():
		_bag.set("_tab", _shot)
		(_bag.get("_view") as Control).queue_redraw()
	elif _shot == Inventory.TABS.size():
		_bag.set_open(true, false)
	else:
		return true
	return false
