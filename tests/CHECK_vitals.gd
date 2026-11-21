extends SceneTree

# HUNGER AND STAMINA: running spends stamina until there is none and running
# stops; rest brings it back and costs food; an empty stomach lowers the ceiling
# and slows the return; a berry puts food back.
#
#   godot --headless --path . --script res://tests/CHECK_vitals.gd

func _process(_dt: float) -> bool:
	var body := CharacterBody3D.new()
	body.set_script(load("res://tests/STUB_body.gd"))
	root.add_child(body)
	var v := Vitals.new()
	v._explorer = body
	v._view = Control.new()
	var ok := true
	# Run flat out.
	body.running = true
	var seconds := 0.0
	while not v.spent and seconds < 60.0:
		v._process(0.1)
		seconds += 0.1
	print("vitals: ran for %.1f s before stopping; can run: %s; food left %.1f" % [seconds, body.run_allowed, v.hunger])
	ok = ok and v.spent and not body.run_allowed and seconds > 8.0 and seconds < 30.0
	# Stand and breathe.
	body.running = false
	var food_before := v.hunger
	seconds = 0.0
	while v.stamina < 99.0 and seconds < 60.0:
		v._process(0.1)
		seconds += 0.1
	print("vitals: back to full in %.1f s, for %.2f food; can run: %s" % [seconds, food_before - v.hunger, body.run_allowed])
	ok = ok and body.run_allowed and v.stamina >= 99.0 and food_before - v.hunger > 1.0
	var fed_time := seconds
	# The same on an empty stomach.
	v.hunger = 0.0
	for i in 100:
		v._process(0.1)
	print("vitals: starving, stamina settles at %.0f of a ceiling of %.0f" % [v.stamina, v.ceiling()])
	ok = ok and v.stamina <= v.ceiling() + 0.5 and v.ceiling() < 40.0
	v.stamina = 0.0
	v.spent = true
	seconds = 0.0
	while v.stamina < v.ceiling() - 0.5 and seconds < 120.0:
		v._process(0.1)
		seconds += 0.1
	print("vitals: starving, a third as much comes back in %.1f s (fed: all of it in %.1f s)" % [seconds, fed_time])
	ok = ok and seconds > fed_time * 0.9
	# Eat.
	v.eat(v.berry_food)
	v.eat(v.berry_food)
	v.eat(v.berry_food)
	print("vitals: three berries on, food %.0f, ceiling %.0f" % [v.hunger, v.ceiling()])
	ok = ok and v.hunger > 40.0 and v.ceiling() > 99.0
	# A swing.
	var before := v.stamina
	v.spend(v.swing_cost)
	ok = ok and absf(before - v.stamina - v.swing_cost) < 0.01
	print("vitals: %s" % ("ok" if ok else "FAILED"))
	quit(0 if ok else 1)
	return true
