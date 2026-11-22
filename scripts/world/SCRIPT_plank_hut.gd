class_name PlankHut
extends Node3D

# A HUT BUILT OUT OF THE PLANK KIT, to walk up to and into: four metres by two,
# plank walls, a board floor, gables and a 45 degree roof, and a door in the front
# that opens (SCRIPT_door.gd). It stands near where the game starts, set down on
# the ground there once the ground is known.
#
# Everything is a panel of assets/build/plank_kit on a two-metre grid: this is the
# first thing in the game made of them, and what a building system would do.

@export var world_path: NodePath = ^"../GaiaSphere"
@export var explorer_path: NodePath = ^"../Explorer"
## Where it stands, from where the player starts (metres: right, up, forward is -z).
@export var from_start := Vector3(7.0, 0.0, -9.0)
@export var facing_degrees := 200.0

const KIT := "res://assets/build/plank_kit/"

var _placed := false


func _ready() -> void:
	visible = false
	# Walls: the front has the door in its left half.
	var door := Door.new()
	door.position = Vector3(-1.0, 0, 1.0)
	add_child(door)
	_panel("wall_c", Vector3(1.0, 0, 1.0), 0.0, Vector3(2.0, 2.0, 0.12))
	_panel("wall_e", Vector3(-1.0, 0, -1.0), PI, Vector3(2.0, 2.0, 0.12))
	_panel("wall_g", Vector3(1.0, 0, -1.0), PI, Vector3(2.0, 2.0, 0.12))
	_panel("wall_b", Vector3(-2.0, 0, 0), -PI * 0.5, Vector3(2.0, 2.0, 0.12))
	_panel("wall_d", Vector3(2.0, 0, 0), PI * 0.5, Vector3(2.0, 2.0, 0.12))
	_panel("gable_right_a", Vector3(-1.0, 2.0, 1.0), 0.0, Vector3.ZERO)
	_panel("gable_left_a", Vector3(1.0, 2.0, 1.0), 0.0, Vector3.ZERO)
	_panel("gable_left_b", Vector3(-1.0, 2.0, -1.0), PI, Vector3.ZERO)
	_panel("gable_right_b", Vector3(1.0, 2.0, -1.0), PI, Vector3.ZERO)
	_panel("floor_a", Vector3(-1.0, 0.02, 1.0), 0.0, Vector3.ZERO)
	_panel("floor_b", Vector3(1.0, 0.02, 1.0), 0.0, Vector3.ZERO)
	_panel("roof_a", Vector3(-2.0, 2.0, 0), -PI * 0.5, Vector3.ZERO)
	_panel("roof_b", Vector3(2.0, 2.0, 0), PI * 0.5, Vector3.ZERO)
	# The floor and the two slopes of the roof, to stand on.
	var body := StaticBody3D.new()
	add_child(body)
	_box(body, Vector3(0, 0.005, 0), Vector3(4.0, 0.12, 2.0), Vector3.ZERO)
	# A ramp nobody sees, from the ground outside the door up to the sill, so the
	# step is never more than a foot can take wherever the ground falls away.
	_box(body, Vector3(-1.0, -0.27, 1.75), Vector3(1.3, 0.1, 1.6), Vector3(0.36, 0, 0))
	_box(body, Vector3(-1.0, 3.0, 0), Vector3(2.9, 0.1, 2.1), Vector3(0, 0, PI * 0.25))
	_box(body, Vector3(1.0, 3.0, 0), Vector3(2.9, 0.1, 2.1), Vector3(0, 0, -PI * 0.25))


func _panel(file: String, at: Vector3, turn: float, wall: Vector3) -> void:
	var node: Node3D = (load(KIT + file + "_lod0.glb") as PackedScene).instantiate()
	node.position = at
	node.rotation.y = turn
	add_child(node)
	if wall != Vector3.ZERO:
		var body := StaticBody3D.new()
		node.add_child(body)
		_box(body, Vector3(0, wall.y / 2.0, 0.03), wall, Vector3.ZERO)


func _box(body: StaticBody3D, at: Vector3, size: Vector3, turn: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = at
	cs.rotation = turn
	body.add_child(cs)


## Set down once the player has arrived, which is when there is ground to stand on.
func _process(_delta: float) -> void:
	if _placed:
		return
	var explorer := get_node_or_null(explorer_path)
	var world := get_node_or_null(world_path)
	if explorer == null or world == null or not bool(explorer.get("arrived")):
		return
	var start: Vector3 = (explorer as Node3D).global_position
	var at := start + from_start
	# Level with the ground outside the door, so you walk straight in; but never
	# so low that the highest ground under it comes up through the floor.
	var turn := Basis(Vector3.UP, deg_to_rad(facing_degrees))
	var highest := -1e9
	for corner in [Vector3(-2, 0, -1), Vector3(2, 0, -1), Vector3(2, 0, 1), Vector3(-2, 0, 1), Vector3.ZERO]:
		highest = maxf(highest, float(world.call(&"height_at", at + turn * corner, start.y)))
	var sill := float(world.call(&"height_at", at + turn * Vector3(-1.0, 0, 1.6), start.y))
	global_transform = Transform3D(turn, Vector3(at.x, maxf(sill, highest - 0.05), at.z))
	visible = true
	_placed = true
