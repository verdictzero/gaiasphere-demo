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
	# SWIMMING. Along the surface it costs stamina; floating still gets it back.
	body.deep = 1.55
	body.swimming = true
	body.velocity = Vector3(3, 0, 0)
	v.stamina = 100.0
	v.spent = false
	for i in 200:
		v._process(0.1)
	print("oxygen: 20 s of swimming, stamina %.0f, air %.0f" % [v.stamina, v.oxygen])
	ok = ok and v.stamina < 75.0 and v.stamina > 55.0 and v.oxygen > 99.0
	seconds = 0.0
	while not v.spent and seconds < 200.0:
		v._process(0.1)
		seconds += 0.1
	for i in 100:
		v._process(0.1)
	print("oxygen: swum out after %.0f s more; ten seconds on, air %.0f, slowed %s" % [seconds, v.oxygen, body.swim_tired])
	ok = ok and v.spent and body.swim_tired and v.oxygen < 97.0 and v.oxygen > 85.0
	body.velocity = Vector3.ZERO
	for i in 300:
		v._process(0.1)
	print("oxygen: floated still for 30 s, stamina %.0f, air %.0f, swum out %s" % [v.stamina, v.oxygen, v.spent])
	ok = ok and v.stamina > 25.0 and v.oxygen > 99.0 and not v.spent
	body.swimming = false
	body.deep = 0.5
	v.stamina = 100.0
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
	var which := 0
	for i in Inventory.RECIPES.size():
		if String(Inventory.RECIPES[i]["makes"]) == "foundation":
			which = i
	var able := bag.can_craft(which)
	var made := bag.craft(which)
	print("oxygen:   can %s, made %s, holds %d" % [able, made, bag.count_of("foundation")])
	ok = ok and able and made and bag.count_of("foundation") == 1
	print("oxygen: god mode, a foundation crafted out of nothing: %s" % (bag.count_of("foundation") == 1))
	Vitals.debug = false
	ok = ok and not bag.can_craft(which)
	bag.free()
	print("oxygen: ok" if ok else "oxygen: FAILED")
	quit(0 if ok else 1)
	return true
