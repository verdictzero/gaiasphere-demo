extends SceneTree

# THE BAG ON ITS OWN: opens the inventory over a plain backdrop, checks the
# clicks and the crafting, and saves a still.
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
		_bag.add("log", 150)
		ok = ok and int(_bag.slots[0][1]) == 64 and int(_bag.slots[2][1]) == 22
		_bag.set_open(true)
		_click(0)                                  # a full stack, onto the cursor
		_click(20)                                 # and down in the bag
		ok = ok and _bag.slots[0] == null and int(_bag.slots[20][1]) == 64
		_click(1, MOUSE_BUTTON_RIGHT)              # half of the next
		_click(13, MOUSE_BUTTON_RIGHT)             # one of those put down
		_click(2)                                  # the rest onto the 22
		ok = ok and int(_bag.slots[13][1]) == 1 and int(_bag.slots[2][1]) == 53 and _bag._held == null
		ok = ok and _bag.count_of("log") == 150
		# CRAFTING: a wall takes four logs; a foundation cannot be made without stone,
		# and can with it; a click on its row in the list does the same.
		ok = ok and _bag.craft(1) and _bag.count_of("wall") == 1 and _bag.count_of("log") == 146
		ok = ok and not _bag.can_craft(6) and not _bag.craft(6) and _bag.count_of("log") == 146
		_bag.add("stone", 20)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = _bag._craft_row(6).get_center()
		_bag._on_gui_input(ev)
		ok = ok and _bag.count_of("foundation") == 1 and _bag.count_of("stone") == 12 and _bag.count_of("log") == 144
		ok = ok and _bag.craft(7) and _bag.count_of("stone") == 7 and not _bag.can_craft(6)
		_bag._craft_hover = 1
		_bag._view.queue_redraw()
		print("bag: clicks and crafting %s" % ("ok" if ok else "FAILED"))
		if not ok:
			quit(1)
			return true
	if _frames == 30:
		root.get_texture().get_image().save_png(_out.path_join("bag.png"))
		_bag.set_open(false)
		print("bag: shut with %d logs" % _bag.count_of("log"))
	if _frames == 40:
		root.get_texture().get_image().save_png(_out.path_join("hotbar.png"))
		quit(0)
		return true
	return false
