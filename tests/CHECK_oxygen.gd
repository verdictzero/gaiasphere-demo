extends SceneTree

# AIR: a breath runs out under water and comes back above it; with none left the
# water takes health; in god mode none of it happens, and building is free.
#
#   godot --headless --path . --script res://tests/CHECK_oxygen.gd

func _process(_dt: float) -> bool:
	var body := CharacterBody3D.new()
	body.set_script(load("res://tests/STUB_body.gd"))
	root.add_child(body)
	var v := Vitals.new()
	v._explorer = body
	v._view = Control.new()
	v._epitaph = Label.new()
	v._shroud = ColorRect.new()
	for action in [&"wv_debug", &"wv_up"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var ok := true
	# Wading to the chest is not being under.
	body.deep = 1.4
	for i in 50:
		v._process(0.1)
	print("oxygen: chest deep for 5 s, air %.0f" % v.oxygen)
	ok = ok and v.oxygen > 99.0
	# Under.
	body.deep = 4.0
	var seconds := 0.0
	while v.oxygen > 0.0 and seconds < 200.0:
		v._process(0.1)
		seconds += 0.1
	print("oxygen: a breath lasted %.1f s; health %.0f" % [seconds, v.health])
	ok = ok and absf(seconds - v.breath) < 1.0 and v.health > 95.0
	for i in 20:
		v._process(0.1)
	print("oxygen: two seconds with none, health %.0f" % v.health)
	ok = ok and v.health < 80.0 and v.health > 50.0
	# Up for air.
	body.deep = 0.5
	seconds = 0.0
	while v.oxygen < 100.0 and seconds < 60.0:
		v._process(0.1)
		seconds += 0.1
	print("oxygen: back to a full breath in %.1f s" % seconds)
	ok = ok and seconds < 5.0
	# God mode: under for a minute and a half, and nothing.
	Vitals.debug = true
	v.health = 60.0
	body.deep = 4.0
	for i in 900:
		v._process(0.1)
	v.hurt(500.0)
	print("oxygen: god mode, 90 s under and a blow of 500: air %.0f, health %.0f" % [v.oxygen, v.health])
	ok = ok and v.oxygen >= 100.0 and v.health >= 100.0
	var bag := Inventory.new()
	bag.slots.resize(Inventory.BAG)
	var able := bag.can_craft(5)
	var made := bag.craft(5)
	print("oxygen:   can %s, made %s, holds %d" % [able, made, bag.count_of("foundation")])
	ok = ok and able and made and bag.count_of("foundation") == 1
	print("oxygen: god mode, a foundation crafted out of nothing: %s" % (bag.count_of("foundation") == 1))
	Vitals.debug = false
	ok = ok and not bag.can_craft(5)
	bag.free()
	print("oxygen: ok" if ok else "oxygen: FAILED")
	quit(0 if ok else 1)
	return true
