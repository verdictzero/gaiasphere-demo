class_name FxFlicker
extends Node

# A fire's light is never still. Hung under a light by Fx: its energy wanders
# about `base` by up to `amount` of it, on two slow waves and a quick one.

var base := 2.0
var amount := 0.3
var _t := randf() * 100.0


func _process(delta: float) -> void:
	var light := get_parent() as Light3D
	if light == null or light.has_meta(&"dying"):
		return
	_t += delta
	var wave := sin(_t * 7.3) * 0.45 + sin(_t * 13.1 + 1.7) * 0.35 + sin(_t * 31.0 + 0.4) * 0.2
	light.light_energy = base * (1.0 + wave * amount)
