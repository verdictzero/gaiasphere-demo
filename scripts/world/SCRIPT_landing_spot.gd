class_name LandingSpot
extends Node3D

# WHERE THE PLAYER ARRIVES ON AN ISLAND WITH NO ESCAPE POD. The pod and the crash
# site are where the game begins, on island 001; an island met later (island 002,
# the desert) has neither, and something still has to say where the player
# stands when it loads, where they come back to out of the cloud sea, and where
# the buggy waits.
#
# IT ANSWERS AS THE POD DOES. Everything that reads the pod reads it through four
# duck-typed calls — `settled`, `pod()`, `hatch_spot()` and `hatch_facing()` —
# so `ArrivalDrop`, `CloudSeaRespawn` and `BuggySpot` are pointed at this node by
# the same `escape_pod_path` they take on island 001 and run unchanged. The one
# thing the pod gives that this cannot is its DENT, which `ArrivalDrop` parks the
# camera over at load so the streaming builds the right ground first; for that
# this answers `landing_centre()` and `landing_heading()`, which the arrival asks
# for when the field carries no dent.
#
# ON THE RING ROAD. The spot is the road's centreline at `bearing_deg` round the
# island (the field's XZ frame, 0 along +X, as `ruin_ring_spin` is measured),
# facing along the road the way the bearings run — so the player stands on the
# tarmac with it winding off in front of them, and `BuggySpot`'s "ahead and to
# one side" puts the buggy on the road too. A field with no road but trails
# (island 003) gets the trail joint nearest the point at that bearing a third of
# the way out, facing along the trail; one with neither gets that point, facing
# the centre.
#
# Placed once, in `_ready`, before the floating origin has moved, and kept as this
# node's own position thereafter; the origin shifts it with the rest of the scene,
# so `hatch_spot()` is always render space, as the pod's is.

@export var island_world_path: NodePath
## Round the island, in degrees, in the field's XZ frame.
@export_range(0.0, 360.0) var bearing_deg := 200.0

## True once the spot is placed. The pod's flag, with the pod's meaning.
var settled := false

var _facing := Vector3.FORWARD
var _centre := Vector2.ZERO
var _heading := Vector2.RIGHT


func _ready() -> void:
	var world := get_node_or_null(island_world_path)
	if world == null or not world.has_method(&"get_field"):
		push_warning("landing_spot: no GaiaSphere (set island_world_path)")
		return
	var field: IslandField = world.call(&"get_field")
	if field == null:
		push_warning("landing_spot: the GaiaSphere carries no field")
		return
	if not field._ready:
		field.prepare()
	var hub: IslandField.Island = field.island_in_cell(field.hub_cell())
	if hub == null:
		return
	var dir := Vector2.from_angle(deg_to_rad(bearing_deg))
	var at := hub.center + dir * hub.radius * 0.33
	var along := -dir
	var best := 1e30
	# The LOOP's joints only (`road_ring`): a lay-by or a service road is road too,
	# but the arrival belongs on the carriageway, facing along it.
	for e in field.road_ring(hub):
		var zn: IslandField.Zone = e
		# The road joint whose bearing is nearest the one asked for.
		var off := absf(angle_difference(dir.angle(), (zn.a - hub.center).angle()))
		if off < best:
			best = off
			at = zn.a
			along = (zn.b - zn.a).normalized()
	# NO ROAD BUT TRAILS (island 003's web through the wood): the trail joint
	# nearest that point a third of the way out, facing along the trail.
	if best >= 1e30:
		var near := 1e30
		var want := at
		for e in field.trails(hub):
			var zn: IslandField.Zone = e
			var d := zn.a.distance_to(want)
			if d < near:
				near = d
				at = zn.a
				along = (zn.b - zn.a).normalized()
	_centre = at
	_heading = along
	_facing = Vector3(along.x, 0.0, along.y)
	var y := float(world.call(&"height_at", Vector3(at.x, 0.0, at.y), 0.0))
	global_position = Vector3(at.x, y, at.y)
	settled = true


## The node a pod would hand back: this one.
func pod() -> Node3D:
	return self


## Where the player stands, in render space.
func hatch_spot() -> Vector3:
	return global_position if settled else Vector3.ZERO


## Which way they face: along the road.
func hatch_facing() -> Vector3:
	return _facing


## The spot in the field's own XZ, for the arrival to park the camera over at
## load. Logical, not render: it is read before the origin first moves.
func landing_centre() -> Vector2:
	return _centre


func landing_heading() -> Vector2:
	return _heading
