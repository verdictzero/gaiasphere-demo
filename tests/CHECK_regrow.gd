extends SceneTree

# BERRY BUSHES GROW BACK: a bush stripped stays bare while the player is looking
# at it however long, starts back the moment they look away once three days are
# up, and does not start early even with their back turned.
#
#   godot --headless --path . --script res://tests/CHECK_regrow.gd

# (In the first frame, not in _initialize: nodes have no place in the world until
# the tree is running.)
func _process(_dt: float) -> bool:
	var bushes := BerryBushes.new()
	bushes.set_script(load("res://scripts/world/SCRIPT_berry_bushes.gd"))
	var explorer := Node3D.new()
	var enviro := Node3D.new()
	enviro.set_script(load("res://tests/STUB_clock.gd"))
	bushes._explorer = explorer
	bushes._enviro = enviro
	root.add_child(explorer)
	root.add_child(enviro)
	var sq := Vector2i(3, 4)
	var ok := true
	enviro.hour = 8.0
	bushes._process(0.1)
	bushes._stripped[sq] = bushes.today()
	# A bush standing in that square, ten metres in front of the player.
	bushes._live[sq] = Transform3D(Basis(), Vector3(0, 0, -10))
	# Four days pass with the player facing it.
	for day in 4:
		for hour in [14.0, 20.0, 2.0, 8.0]:
			enviro.hour = hour
			bushes._regrow_check = 0.0
			bushes._process(0.1)
	ok = ok and bushes._stripped.has(sq) and absf(bushes.today() - bushes._stripped[sq] - 4.0) < 0.01
	print("regrow: after 4 days of being looked at: %s" % ("still bare" if bushes._stripped.has(sq) else "REGROWN"))
	# The player turns their back: now it starts, and fades in.
	explorer.rotation.y = PI
	bushes._regrow_check = 0.0
	bushes._process(0.1)
	var started: bool = bushes._growing.has(sq)
	ok = ok and started
	print("regrow: then with their back turned: %s" % ("leaves coming in (%.0f%%)" % (float(bushes._growing.get(sq, 0.0)) * 100.0) if started else "STILL BARE"))
	for i in 60:
		bushes._process(0.1)
	var whole: bool = not bushes._growing.has(sq) and not bushes._stripped.has(sq)
	ok = ok and whole
	print("regrow: six seconds on: %s" % ("whole, the bare bush gone" if whole else "NOT FINISHED"))
	# Stripped again, back still turned, two days: not yet.
	bushes._stripped[sq] = bushes.today()
	for day in 2:
		for hour in [14.0, 20.0, 2.0, 8.0]:
			enviro.hour = hour
			bushes._regrow_check = 0.0
			bushes._process(0.1)
	ok = ok and bushes._stripped.has(sq)
	print("regrow: 2 days on, back turned: %s" % ("still bare" if bushes._stripped.has(sq) else "REGROWN EARLY"))
	print("regrow: %s" % ("ok" if ok else "FAILED"))
	quit(0 if ok else 1)
	return true
