class_name Door
extends Node3D

# A DOORWAY WITH A DOOR IN IT THAT OPENS.
#
# Two panels of the plank kit (assets/build/plank_kit): the wall with the framed
# opening, and the ledged and braced leaf that hangs in it on its hinge edge.
# Look at it from within `reach` and press the use button (the same one that
# swings: left mouse, E, the big touch button) and it swings open, away from
# whoever opened it; again, and it shuts. Open, you walk through; shut, you do
# not: the leaf carries its own collider round with it.
#
# The node stands where a wall panel would: 2 m wide, its foot on the origin,
# facing +Z.

@export var variant := "a"
## Degrees the leaf swings.
@export var swing := 104.0
## Metres from which it can be worked.
@export var reach := 3.0
@export var seconds := 0.7

const OPENING := 1.1        # the doorway's width and height, as the kit builds it
const HEIGHT := 1.95
const LEAF := 1.06

var open := false
var _hinge: Node3D
var _moving: Tween


func _ready() -> void:
	add_to_group(&"usable")
	var frame: Node3D = (load("res://assets/build/plank_kit/doorway_%s_lod0.glb" % variant) as PackedScene).instantiate()
	add_child(frame)
	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	_hinge.position = Vector3(-OPENING / 2.0 + 0.02, 0.03, 0.004)
	add_child(_hinge)
	var leaf: Node3D = (load("res://assets/build/plank_kit/door_%s_lod0.glb" % variant) as PackedScene).instantiate()
	_hinge.add_child(leaf)
	# What stops you: the wall either side and over the opening, and the leaf.
	var wall := StaticBody3D.new()
	add_child(wall)
	var side_w := (2.0 - OPENING) / 2.0
	for box in [[Vector3(-(OPENING / 2.0 + side_w / 2.0), 1.0, 0.03), Vector3(side_w, 2.0, 0.12)],
			[Vector3(OPENING / 2.0 + side_w / 2.0, 1.0, 0.03), Vector3(side_w, 2.0, 0.12)],
			[Vector3(0.0, HEIGHT + 0.1, 0.03), Vector3(OPENING, 0.2, 0.12)]]:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box[1]
		cs.shape = shape
		cs.position = box[0]
		wall.add_child(cs)
	var body := AnimatableBody3D.new()
	_hinge.add_child(body)
	var lcs := CollisionShape3D.new()
	var lshape := BoxShape3D.new()
	lshape.size = Vector3(LEAF, HEIGHT - 0.06, 0.06)
	lcs.shape = lshape
	lcs.position = Vector3(LEAF / 2.0, (HEIGHT - 0.06) / 2.0, 0.02)
	body.add_child(lcs)


## Whether someone at `from`, looking along `dir`, is at the door and facing it.
func can_use(from: Vector3, dir: Vector3) -> bool:
	var middle := to_global(Vector3(0.0, 1.1, 0.0))
	var to := middle - from
	return to.length() <= reach and dir.normalized().dot(to.normalized()) > 0.72


func use_label() -> String:
	return "CLOSE" if open else "OPEN"


## Work the door, if `can_use`. True if it was worked.
func try_use(from: Vector3, dir: Vector3) -> bool:
	if not can_use(from, dir):
		return false
	open = not open
	var target := 0.0
	if open:
		# Away from whoever is opening it: a door that swings into your face is no door.
		var in_front := (from - global_position).dot(global_basis.z) > 0.0
		target = deg_to_rad(swing) * (1.0 if in_front else -1.0)
	if _moving != null:
		_moving.kill()
	_moving = create_tween()
	var step := _moving.tween_property(_hinge, "rotation:y", target, seconds)
	step.set_trans(Tween.TRANS_BACK if open else Tween.TRANS_SINE)
	step.set_ease(Tween.EASE_OUT if open else Tween.EASE_IN_OUT)
	return true
