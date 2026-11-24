class_name Prewarm
extends RefCounted

# FIRST TIMES, GOT OVER BEHIND THE LOADING SCREEN. The first time anything is
# drawn with a material the renderer has not seen (the meat of a cut cow, the
# fire of the beam's burst, sparks off a rock, the sawn face of a tree), the
# shaders for it are built there and then, and on a phone that stops the game
# for a second or more. Built once, they are kept, so the second time costs
# nothing. So every first time is had while the screen is still black: once the
# player has arrived, SCRIPT_loading_cover.gd hangs a STAGE just in front of the
# eye and every node in the group below sets one of each of its things off on
# it (frozen, touching nothing), holds it there until the renderer has stopped
# building, and then takes it all away and lets the cover lift.
#
# A node joins by `add_to_group(Prewarm.GROUP)` and having
#     func warm(stage: Node3D) -> void
# which makes whatever it makes on or about `stage` (any of it that its own
# helpers hang from the node itself is handed over to the stage by `gather`).

const GROUP := &"prewarm"


## Everything added to `maker` since it had `before` children is moved onto
## `stage`, where it is in the world, and made inert.
static func gather(maker: Node, before: int, stage: Node3D) -> void:
	var made := maker.get_children().slice(before)
	for n in made:
		n.reparent(stage, true)
		inert(n)


## Still and touching nothing: whatever bodies there are in `node` are frozen
## and taken out of every collision layer.
static func inert(node: Node) -> void:
	var all: Array = node.find_children("*", "CollisionObject3D", true, false)
	if node is CollisionObject3D:
		all.append(node)
	for body in all:
		(body as CollisionObject3D).collision_layer = 0
		(body as CollisionObject3D).collision_mask = 0
		if body is RigidBody3D:
			(body as RigidBody3D).freeze = true


## Pipelines the renderer has built so far, for every reason it builds them.
static func built() -> int:
	return int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)) \
			+ int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)) \
			+ int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)) \
			+ int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION))
