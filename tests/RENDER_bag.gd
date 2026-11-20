extends SceneTree

# THE BAG ON ITS OWN: opens the inventory over a plain backdrop, checks the
# clicks and the recipes, and saves a still.
#
#   godot --path . --script res://tests/RENDER_bag.gd -- --out=/some/folder

var _bag: Inventory
var _frames := 0
var _out := "user://"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	var back := ColorRect.new()
	back.color = Color(0.2, 0.32, 0.22)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	_bag = Inventory.new()
	root.add_child(_bag)


func _click(slot: int, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.shift_pressed = shift
	ev.position = _bag._slot_rect(slot).get_center()
	_bag._on_gui_input(ev)


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 3:
		var ok := true
		_bag.add("log", 9)
		_bag.set_open(true)
		_click(0)                                  # the logs, onto the cursor
		_click(Inventory.BAG, MOUSE_BUTTON_RIGHT)  # one into the grid
		ok = ok and _bag.crafted() != null and _bag.crafted()[0] == "planks"
		_click(Inventory.RESULT)                   # four planks on... no: cursor holds logs
		ok = ok and _bag._held[0] == "log" and int(_bag._held[1]) == 8
		_click(1)                                  # logs down in slot 1
		_click(Inventory.RESULT)                   # planks onto the cursor, the log spent
		ok = ok and _bag._held != null and _bag._held[0] == "planks" and int(_bag._held[1]) == 4
		ok = ok and _bag.slots[Inventory.BAG] == null
		_click(Inventory.BAG, MOUSE_BUTTON_RIGHT)
		_click(Inventory.BAG + 1, MOUSE_BUTTON_RIGHT)
		ok = ok and _bag.crafted()[0] == "sticks"
		_click(12)                                 # the other two planks into the bag
		_click(Inventory.RESULT, MOUSE_BUTTON_LEFT, true)
		ok = ok and _bag.count_of("sticks") == 4 and _bag.count_of("planks") == 2
		_bag.add("workbench", 1)
		_bag.add("campfire", 1)
		_bag.slots[Inventory.BAG] = ["log", 1]
		_bag.slots[Inventory.BAG + 3] = ["log", 1]
		_bag.slots[Inventory.BAG + 1] = ["sticks", 1]
		_bag.slots[Inventory.BAG + 2] = ["sticks", 1]
		ok = ok and _bag.crafted()[0] == "campfire"
		_bag._view.queue_redraw()
		print("bag: clicks and recipes %s" % ("ok" if ok else "FAILED"))
		if not ok:
			quit(1)
			return true
	if _frames == 8:
		root.get_texture().get_image().save_png(_out.path_join("bag.png"))
		_bag.set_open(false)
		print("bag: shut with %d logs, %d sticks" % [_bag.count_of("log"), _bag.count_of("sticks")])
	if _frames == 12:
		root.get_texture().get_image().save_png(_out.path_join("hotbar.png"))
		quit(0)
		return true
	return false
