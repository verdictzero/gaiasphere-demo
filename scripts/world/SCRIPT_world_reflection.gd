class_name WorldReflection
extends Node3D

# THE WORLD, REFLECTED IN THE SWORD.
#
# The sky's own reflections are off (rebuilding its radiance map every frame of
# a moving clock is what made the water flicker on phones), so nothing metal had
# anything to mirror and the blade rendered near black. This is a reflection
# probe that goes where the player goes and photographs the world round them:
# the sky, the sun or moon in it, the tree line, the ground.
#
# ONLY THE SWORD READS IT. The probe's `reflection_mask` is one render layer and
# the sword is the only thing on it, so the ground and the plants are lit exactly
# as before and nothing else pays for the lookup.
#
# IT IS RETAKEN WHEN THE LIGHT HAS MOVED, NOT EVERY FRAME. A capture is six
# small views of the world, which Godot spreads over six frames. One is asked
# for when the clock has moved `hour_step`, the weather has changed, or the
# player has walked `walk_step` from the last one, and never more often than
# `min_interval`: at the default day that is a fresh map every eight seconds or
# so, for about the cost of drawing a 256-pixel view each frame while it lasts.

@export var enviro_path: NodePath = ^"../Enviro"
@export var explorer_path: NodePath = ^"../Explorer"
@export var stone_path: NodePath = ^"../SwordStone"
## Hours of game time between captures.
@export var hour_step := 0.08
## Metres walked between captures.
@export var walk_step := 16.0
## Seconds: never retaken sooner than this, and always by `max_interval`.
@export var min_interval := 2.0
@export var max_interval := 25.0
## How far the capture sees, metres.
@export var reach := 450.0

## The render layer (1-20) that marks what mirrors the probe.
const MIRROR_LAYER := 10
const BOX := 96.0

var _probe: ReflectionProbe
var _enviro: Node
var _explorer: Node3D
var _hour := -100.0
var _weather := ""
var _at := Vector3(1e9, 0, 0)
var _since := 1e9
var _tagged := false
var _nudge := 1.0
var captures := 0


func _ready() -> void:
	_enviro = get_node_or_null(enviro_path)
	_explorer = get_node_or_null(explorer_path)
	if OS.has_feature("mobile"):
		hour_step *= 2.5
		min_interval = 6.0
		reach = 220.0
	_probe = ReflectionProbe.new()
	_probe.name = "Probe"
	_probe.top_level = true
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.size = Vector3(BOX, BOX, BOX)
	_probe.max_distance = reach
	_probe.enable_shadows = false
	_probe.box_projection = false
	_probe.interior = false
	_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	_probe.mesh_lod_threshold = 4.0
	var bit := 1 << (MIRROR_LAYER - 1)
	_probe.reflection_mask = bit
	_probe.cull_mask = 0xFFFFF & ~bit          # the sword does not photograph itself
	add_child(_probe)


## The sword, once it exists, moves to the mirror layer (the camera draws every
## layer, so it looks no different; it only starts reading the probe).
func _tag_sword() -> void:
	var stone := get_node_or_null(stone_path)
	if stone == null:
		return
	var sword := stone.find_child("sword", true, false) as MeshInstance3D
	if sword == null:
		return
	sword.layers = 1 << (MIRROR_LAYER - 1)
	_tagged = true


func _process(delta: float) -> void:
	if not _tagged:
		_tag_sword()
	if _explorer == null or _enviro == null:
		return
	_since += delta
	var here := _explorer.global_position + Vector3(0, 1.6, 0)
	var hour := float(_enviro.get("hour"))
	var weather := String(_enviro.get("weather"))
	var turned := absf(fposmod(hour - _hour + 12.0, 24.0) - 12.0) >= hour_step
	var due := turned or weather != _weather or here.distance_to(_at) > walk_step or _since > max_interval
	if not due or _since < min_interval:
		return
	_hour = hour
	_weather = weather
	_at = here
	_since = 0.0
	captures += 1
	# Moving a capture-once probe is what asks for a new capture; a player
	# standing still is moved a hair, back and forth.
	_nudge = -_nudge
	_probe.global_position = here + Vector3(0, 0.004 * _nudge, 0)
