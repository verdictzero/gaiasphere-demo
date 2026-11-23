class_name FlowTerrain
extends RefCounted

# THE FLOWS: an island's structure as what flowed over it. Island 004's
# volcanoes and lava rivers (docs/DOC_island_004_lava.md; the user: "Give me
# terrain based splats like lava rivers, cooled lava rivers, lava erosion, make
# the fire biome really structurally intense") and island 005's ice peaks and
# glaciers (docs/DOC_island_005_ice.md; "Same with the ice island, terrain
# structure based splats") are this one construction with two sets of numbers.
#
# Four things, all of them landform, folded into `IslandField.base_height` so the
# mesh, the collision, the golf and everything that stands on the ground agree
# about them:
#   * THE CONES: a few big ones in the wild ground round the course, each with a
#     summit crater (a volcano's, or near none on an ice peak), its rim breached
#     on one side, its flanks cut by radial gullies (the erosion of a cone;
#     couloirs, on the ice), and in some of them a lake. Small VENTS stand on the
#     plain (vent cones, pingos), each the source of one flow.
#   * THE RIVERS, moving and still (molten and cooled lava; glacier ice and
#     frozen meltwater): traced downhill off the cones and the vents across the
#     land, most of them to the coast and over it. Each is a channel graded down
#     its length: the ground lowered to it where it is level with the land, a
#     gorge where the land rises across its path (it cut its way through: the
#     erosion of a river), and levees either side (lateral moraines). A river
#     that does not reach the coast ends in a TOE, a lobe standing proud of the
#     ground, its levees wrapped round its front (a terminal moraine). The crater
#     lakes are the heads of rivers: the channel widened to the crater floor,
#     filled level.
#   * THE TERRACES: the ground stepped, a few metres at a time, into terraces
#     with steep fronts (stacked flows; ice benches).
#   * THE CODES for the terrain shader: where the river is, along it and across
#     it, so the shader can draw it moving down the channel (`info`).
#
# ISLAND 006'S RIVERS ARE WATER (`IslandField.flow_water_mesh`; the user: "Give
# me spline based rivers with sandy bottoms and rocky edges, and beautiful but
# still retro looking water shaders"). Their courses are splines
# (`flow_river_spline`, `_spline`), and the channel is carved UNDER the river's
# surface (`_carve`): a sandy bed `flow_water_depth` down the middle, shelving up
# to the shore at the river's half-width, where the rocky banks rise. The water is
# a surface of its own, laid along the spline at `water_level` (`RiverWater`,
# SCRIPT_river_water.gd), and the terrain shader draws the bed and the banks.
#
# WHAT IT KEEPS OFF: every hole and pad (and their banks), the line each ruin
# of the ring may slide along (so the ring stands exactly where it stood before
# any flow was laid), and the coast's lip, where every part of it is eased out
# so the ground meets the cliff wall at the island's base as it always has. The
# trails are laid after it and keep off the cones and the moving rivers; they
# cross the still ones (`IslandField._trail_ok`).
#
# BUILT ONCE PER ISLAND per field instance, inside `IslandField._place_zones`,
# after the holes and pads and before the trails, and cached on the island: the
# same seed gives the same cones on every thread. While it is being built
# `base_height` answers without it, which is the ground it is traced over.
#
# CHEAP TO ASK: the rivers are in a 16 m grid of the segments near each cell,
# the terraces need one noise, and the ruins' lines are bucketed the same way;
# most of the island is a dictionary miss and a noise.

## A river's kind, carried to the shader in its along-river code: the code is
## `s + kind * KIND_SPAN`, `s` the metres down the river.
const KIND_STILL := 0
const KIND_MOVING := 1
## The lagoon's kind (`IslandField.flow_lagoon_radius`): its codes are written as
## a river's, `LAGOON_W` metres to a half-width, out from its shores.
const KIND_LAGOON := 2
const KIND_SPAN := 10000.0
const LAGOON_W := 10.0
## Its beaches rise this many metres a metre from the water, and past them its
## banks this steeply, until they meet the ground.
const LAGOON_SLOPE := 0.07
const LAGOON_BANK := 0.38
## The segment grid's cell, metres.
const GRID := 16.0
## The codes reach this far past a river's last visible ground, so the vertex
## past it carries them too and the triangle between never mixes a river's
## codes with the open ground's (see `info`). Wider than the coarsest rung a
## river is still visible at.
const CODE_MARGIN := 14.0
## A gorge's walls: as wide as this share of its depth, within these bounds.
const WALL_SLOPE := 1.1
const WALL_MIN := 3.0
const WALL_MAX := 18.0
## The across code's bound, metres: past every segment's reach.
const ACROSS_MAX := 90.0

class Cone:
	var center := Vector2.ZERO
	## Base radius, and rim over the ground round it, metres.
	var radius := 1.0
	var height := 1.0
	## Rim radius as a share of `radius`.
	var crater := 0.25
	## Crater floor under the rim, metres.
	var depth := 1.0
	## The breach in the rim: its bearing (radians), its half-width (radians),
	## and how far it takes the rim down (metres).
	var breach := 0.0
	var breach_w := 0.4
	var notch := 0.0
	## Gullies round the flank, and how deep at mid-flank (metres).
	var gullies := 0
	var gully_depth := 0.0
	var phase := 0.0
	## Holds a lake, which a moving river drains through the breach.
	var lake := false
	## A vent: the small cone at the source of one flow, no gullies.
	var vent := false

class River:
	var points := PackedVector2Array()
	## Metres down the river at each point.
	var s := PackedFloat32Array()
	## The channel's surface at each point, metres over the island's base.
	var bed := PackedFloat32Array()
	## Half-width at each point, metres.
	var width := PackedFloat32Array()
	var moving := false
	## Ends on the land, in a lobe, rather than at the coast.
	var toe := false
	## Rises in a crater lake, which its head is.
	var lake := false
	var length := 0.0

var cones: Array = []    ## Array[Cone]
var rivers: Array = []   ## Array[River]

# Parameters, copied off the field so a query needs nothing of it.
var _shore_w := 0.05
var _terrace_h := 0.0
var _terrace_steps := 4
var _terrace_front := 0.25
var _terrace_floor := 0.3
var _terrace_noise: FastNoiseLite = null
var _depth_moving := 1.0
var _depth_still := 2.4
var _levee_moving := 1.5
var _levee_still := 2.4
var _toe_height := 5.0
var _toe_length := 45.0
var _cone_soil := true
var _moving_blocks := true
var _splined := false
var _spline_step := 4.0
var _water := false
var _water_depth := 1.6
# How many times wider than `WALL_SLOPE` makes them a river's walls are
# (`IslandField.flow_wall_soften`), and how a gully eases in off the rim
# (`IslandField.flow_gully_ease`).
var _wall_soft := 1.0
var _gully_ease := 0.7
# The rivers that cross a race track's ring (`IslandField.flow_ring_crossings`):
# their indices in `rivers`, as keys.
var _crossings := {}

# THE LAGOON: its middle, its shores' mean radii and their wander, its water's
# level (metres over the island's base), depth, shelf and beach, and the safe
# zone's level core it never cuts.
var _lagoon := false
var _lag_c := Vector2.ZERO
var _lag_in := 0.0
var _lag_out := 0.0
var _lag_wob := 0.0
var _lag_ph := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _lag_level := 0.0
var _lag_depth := 2.2
var _lag_shelf := 24.0
var _lag_beach := 16.0
var _lag_core := 0.0
var _lag_reach := 0.0

# The ruins' slide lines: segment ends and keep-off radius, bucketed by cell.
var _ruin_a := PackedVector2Array()
var _ruin_b := PackedVector2Array()
var _ruin_r := PackedFloat32Array()
var _ruin_fade := 40.0
var _ruin_cells := {}    ## Vector2i -> PackedInt32Array of lines
const RUIN_CELL := 64.0

# Every river segment, flat, and the grid of them.
var _sa := PackedVector2Array()
var _sab := PackedVector2Array()
var _sl2 := PackedFloat32Array()
var _ss0 := PackedFloat32Array()
var _ss1 := PackedFloat32Array()
var _sbed0 := PackedFloat32Array()
var _sbed1 := PackedFloat32Array()
var _sw0 := PackedFloat32Array()
var _sw1 := PackedFloat32Array()
var _sreach := PackedFloat32Array()
var _sriver := PackedInt32Array()
var _grid := {}          ## Vector2i -> PackedInt32Array of segments
var _cone_box := Rect2()

# The last point asked, and what was found there: `info` after `relief` at the
# same point (the mesher's order) finds it without a second search.
var _hx := INF
var _hz := INF
var _hseg := -1
var _hu := 0.0
var _hd := 0.0

static func build(field: IslandField, isl, zones: Array) -> FlowTerrain:
	var lt := FlowTerrain.new()
	lt._build(field, isl, zones)
	return lt


# ------------------------------------------------------------------ queries

## The ground with the flows in it. `g` is the wild ground at (x, z), metres over
## the island's base after the shore ramp; `mask` the landmass mask there.
func relief(x: float, z: float, mask: float, g: float) -> float:
	var ls := _shore(mask)
	if ls <= 0.0:
		return g
	g += _built(x, z) * ls
	if not _nearest(x, z):
		return g
	return _carve(g, ls)


## The terrain shader's codes at a point, into `out`: [band, along, across,
## cone].
##   * `band` is where across the river's ground this is: 1 down its middle,
##     falling straight to 0 at three half-widths out, where the scoured ground
##     past its levees ends. The shader takes the half-widths back out of it
##     (`3 * (1 - band)`), so the channel, the levees and the scour sit where the
##     ground has them whatever the river's width — a crater lake's included;
##   * `along` is `s + kind * KIND_SPAN`, `s` the metres down the river;
##   * `across` the signed metres off its middle, positive to its left looking
##     downstream: with `s`, the coordinates the shader draws the river's surface
##     in, at one scale in a channel and a lake alike;
##   * `cone` how much of a cone's flank this is (0..1).
## Returns whether a river's codes reach here at all: where they do, `band` may
## still be 0, on the margin past its edge (`CODE_MARGIN`).
func info(x: float, z: float, mask: float, out: Array) -> bool:
	out[3] = cone_weight(x, z)
	if _lagoon and mask > 0.0:
		var dx := x - _lag_c.x
		var dz := z - _lag_c.y
		if dx * dx + dz * dz < _lag_reach * _lag_reach:
			var at := lagoon_at(x, z)
			var off := -at.x
			if off < 2.0 * LAGOON_W + CODE_MARGIN:
				# (The top of the causeway is dry land and green: not the mere's ground.)
				out[0] = clampf(1.0 - (off + LAGOON_W) / (3.0 * LAGOON_W), 0.0, 1.0) \
						* (1.0 - smoothstep(0.55, 0.92, causeway_weight(x, z)))
				out[1] = (at.y + PI) * (_lag_in + _lag_out) * 0.5 + float(KIND_LAGOON) * KIND_SPAN
				out[2] = clampf(at.z - (_lag_in + _lag_out) * 0.5, -ACROSS_MAX, ACROSS_MAX)
				return true
	if mask <= 0.0 or not _nearest(x, z):
		out[0] = 0.0
		out[1] = 0.0
		out[2] = 0.0
		return false
	var si := _hseg
	var w := lerpf(_sw0[si], _sw1[si], _hu)
	out[0] = clampf(1.0 - absf(_hd) / (3.0 * maxf(w, 0.01)), 0.0, 1.0)
	out[1] = lerpf(_ss0[si], _ss1[si], _hu) \
			+ float(KIND_MOVING if (rivers[_sriver[si]] as River).moving else KIND_STILL) * KIND_SPAN
	out[2] = clampf(_hd, -ACROSS_MAX, ACROSS_MAX)
	return true


## Are the rivers water, drawn as a surface of their own over a carved bed?
## (`IslandField.flow_water_mesh`.)
func is_water() -> bool:
	return _water


## Is there a lagoon at the middle (`IslandField.flow_lagoon_radius`)?
func has_lagoon() -> bool:
	return _lagoon


func lagoon_center() -> Vector2:
	return _lag_c


## The lagoon's water, metres over the island's base.
func lagoon_level() -> float:
	return _lag_level


## The lagoon's shores on bearing `th` (radians round its middle): (inner, outer)
## radius, metres. They wander on two slow waves each, so it is no ring drawn
## with a compass.
func lagoon_shores(th: float) -> Vector2:
	var wi := 0.6 * sin(3.0 * th + _lag_ph[0]) + 0.4 * sin(5.0 * th + _lag_ph[1])
	var wo := 0.6 * sin(4.0 * th + _lag_ph[2]) + 0.4 * sin(7.0 * th + _lag_ph[3])
	return Vector2(_lag_in * (1.0 + _lag_wob * wi), _lag_out * (1.0 + _lag_wob * wo))


## How deep the lagoon's water stands `into` metres in from its nearer shore: the
## full depth past its shelf, shelving to nothing at the shore.
func lagoon_depth(into: float) -> float:
	return _lag_depth * smoothstep(0.0, _lag_shelf, maxf(into, 0.0))


## Metres a point stands in from the lagoon's nearer shore (negative: out of the
## water, on a beach or beyond), and its bearing round the middle: (into, th, r).
func lagoon_at(x: float, z: float) -> Vector3:
	var d := Vector2(x, z) - _lag_c
	var r := d.length()
	var th := atan2(d.y, d.x)
	var sh := lagoon_shores(th)
	return Vector3(minf(r - sh.x, sh.y - r), th, r)


# ------------------------------------------------------------- the causeway
# A LAND BRIDGE TO THE ISLET: a bank of ground left standing across the mere
# where it is narrowest, a little above the water: a cobbled way down its middle
# and a green verge either side, where grass, bushes and trees grow (Flora keeps
# them off the cobbles), with sand at the water's edge. Cobbled by the terrain shader
# (SCRIPT_causeway.gd hands it the line). It is terrain: the mesher, the
# collision and the bake all get it from `lagoon` below.

const CAUSEWAY_HALF := 10.0        ## half the width of its flat top, metres
const CAUSEWAY_BANK := 5.0        ## metres its sides take to fall to the bed
const CAUSEWAY_RISE := 1.1        ## its top, metres over the water

## A LEVEL SPOT at the middle of the islet, so what stands there (the sword in the
## stone) sits even: flat out to FLAT_RADIUS, eased back into the ground beyond.
const FLAT_RADIUS := 8.0
const FLAT_EASE := 13.0
var _flat_h := 0.0

var _cw_dir := Vector2.ZERO
var _cw_in := 0.0
var _cw_out := 0.0


func _place_causeway() -> void:
	var best := 1e9
	for i in 96:
		var th := TAU * float(i) / 96.0
		var sh := lagoon_shores(th)
		if sh.y - sh.x < best:
			best = sh.y - sh.x
			_cw_dir = Vector2(cos(th), sin(th))
			_cw_in = sh.x
			_cw_out = sh.y


## The causeway's two ends (on the islet, on the outer shore) in world metres.
func causeway_ends() -> PackedVector2Array:
	return PackedVector2Array([_lag_c + _cw_dir * (_cw_in - 6.0), _lag_c + _cw_dir * (_cw_out + 6.0)])


## How much of the causeway stands at a point: 1 on its top, falling to 0 down its banks.
func causeway_weight(x: float, z: float) -> float:
	if _cw_dir == Vector2.ZERO:
		return 0.0
	var d := Vector2(x, z) - _lag_c
	var along := d.dot(_cw_dir)
	if along < _cw_in - 14.0 or along > _cw_out + 14.0:
		return 0.0
	var off := absf(d.dot(Vector2(-_cw_dir.y, _cw_dir.x)))
	# A little wander in its edge, so it is a bank and not a ruled strip: long and
	# slow, since anything quicker than the ground's own grid comes out as teeth.
	off -= 0.3 * sin(along * 0.13) + 0.12 * sin(along * 0.29 + 1.3)
	var ends := smoothstep(_cw_in - 14.0, _cw_in - 4.0, along) * (1.0 - smoothstep(_cw_out + 4.0, _cw_out + 14.0, along))
	# Eased twice over: a rounded shoulder at the top and a rounded foot on the bed.
	var side := 1.0 - smoothstep(CAUSEWAY_HALF, CAUSEWAY_HALF + CAUSEWAY_BANK, off)
	return side * side * (3.0 - 2.0 * side) * ends


## THE LAGOON CARVED into the ground `g` (metres over the base, the zones'
## shelves already in it): the bed under the water, shelving to the shores; the
## beaches rising gently from the water on both sides, and past them the banks,
## until they meet the ground; never into the safe zone's level core, and never
## raising the ground. `IslandField.base_height` calls it after the shelves.
func lagoon(x: float, z: float, g: float) -> float:
	if not _lagoon:
		return g
	var carved := _lagoon_carve(x, z, g)
	var from_middle := Vector2(x, z).distance_to(_lag_c)
	if from_middle < FLAT_RADIUS + FLAT_EASE:
		return lerpf(_flat_h, carved, smoothstep(FLAT_RADIUS, FLAT_RADIUS + FLAT_EASE, from_middle))
	var cw := causeway_weight(x, z)
	if cw <= 0.0:
		return crash(x, z, carved)
	return lerpf(carved, maxf(carved, _lag_level + CAUSEWAY_RISE), cw)


# ------------------------------------------------------------- the crash
# WHERE THE SHUTTLE CAME DOWN (SCRIPT_crashed_shuttle.gd stands the wreck in it).
# It came in over the shore, ploughed a GOUGE down the beach and the shelf, and
# stopped at the foot of the shelf in a DIVOT of its own making: a bowl of sand
# a couple of dozen metres across with a thrown-up rim. All of it is terrain,
# from here, so the mesh, the collision and the bake have it; `crash_splat`
# turns the ground it broke to bare sand.
#
# The place is fixed by the mere's own shape: straight across from the causeway,
# CRASH_IN metres in from the outer shore, facing the middle.

const CRASH_IN := 19.0            ## metres in from the outer shore the wreck lies
const CRASH_BOWL := 11.0          ## the divot's radius
const CRASH_DEPTH := 1.5          ## and how deep its middle is dug
const CRASH_RIM := 0.45           ## the lip thrown up round it
const CRASH_GOUGE := 48.0         ## how far back up the shore the gouge runs
const CRASH_WIDE := 5.0           ## its half-width at the wreck (it narrows going back)
const CRASH_CUT := 1.7            ## and its depth there (it shallows going back)

var _crash_at := Vector2.ZERO
var _crash_out := Vector2.ZERO    # from the wreck back up the shore: the way it came from, reversed


func _place_crash() -> void:
	if _cw_dir == Vector2.ZERO:
		return
	_crash_out = -_cw_dir
	var shores := lagoon_shores(_crash_out.angle())
	_crash_at = _lag_c + _crash_out * (shores.y - CRASH_IN)


## Where the wreck lies and the way back up its gouge, world metres; (0, 0) twice if there is none.
func crash_site() -> PackedVector2Array:
	return PackedVector2Array([_crash_at, _crash_out])


## (how much of the divot, how much of the gouge) is at a point, each 0 to 1.
func crash_weight(x: float, z: float) -> Vector2:
	if _crash_out == Vector2.ZERO:
		return Vector2.ZERO
	var d := Vector2(x, z) - _crash_at
	var far := d.length()
	if far > CRASH_GOUGE + CRASH_BOWL:
		return Vector2.ZERO
	var bowl := 1.0 - smoothstep(CRASH_BOWL * 0.25, CRASH_BOWL, far)
	var along := d.dot(_crash_out)
	var gouge := 0.0
	if along > -2.0 and along < CRASH_GOUGE:
		var t := clampf(along / CRASH_GOUGE, 0.0, 1.0)
		var wide := lerpf(CRASH_WIDE, CRASH_WIDE * 0.45, t)
		# It wanders a little: nothing that weighs what a shuttle does slides straight.
		var off := absf(d.dot(Vector2(-_crash_out.y, _crash_out.x)) - 1.2 * sin(along * 0.16))
		gouge = (1.0 - smoothstep(wide * 0.45, wide, off)) * (1.0 - t * t) * smoothstep(-2.0, 2.0, along)
	return Vector2(bowl, gouge)


## The ground `h` at a point with the crash dug into it.
func crash(x: float, z: float, h: float) -> float:
	if _crash_out == Vector2.ZERO:
		return h
	var w := crash_weight(x, z)
	if w.x <= 0.0 and w.y <= 0.0:
		# The rim stands a little way outside the bowl.
		var far := Vector2(x, z).distance_to(_crash_at)
		if far < CRASH_BOWL * 1.5:
			var lip := far / CRASH_BOWL
			return h + CRASH_RIM * smoothstep(1.0, 1.12, lip) * (1.0 - smoothstep(1.12, 1.5, lip))
		return h
	var d := Vector2(x, z) - _crash_at
	var along := d.dot(_crash_out)
	var t := clampf(along / CRASH_GOUGE, 0.0, 1.0)
	var dug := h - CRASH_DEPTH * w.x
	var cut := h - CRASH_CUT * lerpf(1.0, 0.25, t) * w.y
	# Above the water the gouge is never cut below it: there is no water to fill
	# a trench in the beach, and one dug under the mere's level would stand dry.
	if h > _lag_level + 0.15:
		cut = maxf(cut, _lag_level + 0.15)
	var out := minf(dug, cut)
	# Thrown up either side of the gouge, and round the bowl where the gouge does not leave it.
	var far2 := d.length() / CRASH_BOWL
	out += CRASH_RIM * smoothstep(0.85, 1.0, far2) * (1.0 - smoothstep(1.0, 1.4, far2)) * (1.0 - w.y)
	return out


## The ground's surface where the crash broke it: bare sand.
func crash_splat(x: float, z: float, w: Color) -> Color:
	if _crash_out == Vector2.ZERO:
		return w
	var c := crash_weight(x, z)
	var bare := maxf(smoothstep(0.0, 0.5, c.x), smoothstep(0.05, 0.5, c.y))
	return w.lerp(Color(0.0, 0.0, 0.0, 1.0), bare) if bare > 0.0 else w


func _lagoon_carve(x: float, z: float, g: float) -> float:
	var dx := x - _lag_c.x
	var dz := z - _lag_c.y
	if dx * dx + dz * dz > _lag_reach * _lag_reach:
		return g
	var at := lagoon_at(x, z)
	var into := at.x
	if into >= 0.0:
		return minf(g, _lag_level - lagoon_depth(into))
	var out := -into
	var cut := _lag_level + LAGOON_SLOPE * minf(out, _lag_beach) \
			+ LAGOON_BANK * maxf(out - _lag_beach, 0.0)
	var h := minf(g, cut)
	return lerpf(g, h, smoothstep(_lag_core, _lag_core + 8.0, at.z))


## How deep the water stands over the bed `across` half-widths off a river's
## middle (0 down the middle, 1 at its shore): the full depth over the middle
## half, shelving up to nothing at the shore. A still river is shallower.
func water_depth(across: float, moving: bool) -> float:
	var full := _water_depth if moving else _water_depth * 0.6
	return full * (1.0 - smoothstep(0.45, 1.0, absf(across)))


## How far the flows have eased in at a point, 0 at the coast's lip to 1 a
## `IslandField.flow_shore` inland: the channel, and the water in it, with them.
func shore_ease(field: IslandField, isl, p: Vector2) -> float:
	return _shore(field.mask_for(isl, p.x, p.y))


## The water's surface over a river's point `i`, metres over the island's base:
## the river's surface, eased out toward the ground at the coast as the channel
## is (`_carve`), so the water and its bed meet the lip together.
func water_level(field: IslandField, isl, r: River, i: int) -> float:
	var p := r.points[i]
	var ls := _shore(field.mask_for(isl, p.x, p.y))
	return lerpf(_trace_h(field, isl, p, true), r.bed[i], ls)


## How much of a cone's flank a point is, 0..1: what the splat hands the cone's
## own ground (`splat`).
func cone_weight(x: float, z: float) -> float:
	if not _cone_box.has_point(Vector2(x, z)):
		return 0.0
	var best := 0.0
	for c: Cone in cones:
		var dx := x - c.center.x
		var dz := z - c.center.y
		var r2 := c.radius * c.radius
		var d2 := dx * dx + dz * dz
		if d2 < r2:
			best = maxf(best, 1.0 - smoothstep(0.8, 1.0, sqrt(d2) / c.radius))
	return best


## The splat on a cone's flank: its own ground (`IslandField.flow_cone_ground`:
## a volcano's soil, black cinder; a peak's open ground, snow), and the rock it is
## cut into where the crater wall and the gullies' sides are steep.
##
## And where the rivers are water (`is_water`), under and beside them by `band`
## (`info`'s): the bed to the shore is SAND and the rocky edges past it ROCK,
## which is what the ground draws there, and what keeps every scatter out of a
## river (rock and sand grow nothing) without its asking where the water is. The
## lagoon (`along` of its kind) is sand, its bed and its beaches.
func splat(w: Color, slope: float, cone: float, band := 0.0, along := 0.0) -> Color:
	if cone > 0.0:
		var rk := smoothstep(0.62, 0.95, slope)
		var own := Color(0.0, 1.0 - rk, rk, 0.0) if _cone_soil else Color(1.0 - rk, 0.0, rk, 0.0)
		w = w.lerp(own, cone)
	if _water and band > 0.0 and along >= float(KIND_LAGOON) * KIND_SPAN - 0.5:
		# The lagoon: sand, its bed and its beaches alike.
		return w.lerp(Color(0.0, 0.0, 0.0, 1.0), 1.0 - smoothstep(2.5, 2.95, 3.0 * (1.0 - band)))
	if _water and band > 0.0:
		var at := 3.0 * (1.0 - band)
		var edge := smoothstep(0.85, 1.0, at)
		w = w.lerp(Color(0.0, 0.0, 0.0, 1.0), 1.0 - edge)
		w = w.lerp(Color(0.0, 0.0, 1.0, 0.0), edge * (1.0 - smoothstep(1.6, 1.9, at)))
	return w


## Is a point on a cone, or within `pad` metres of a moving river's ground (when
## those keep trails off: `IslandField.flow_moving_blocks_trails`)? The trails'
## test: they keep off both and cross the still rivers.
func blocks_trail(x: float, z: float, pad: float) -> bool:
	if _lagoon and Vector2(x, z).distance_to(_lag_c) < _lag_out * (1.0 + _lag_wob) + _lag_beach + pad:
		return true
	if _cone_box.grow(pad).has_point(Vector2(x, z)):
		for c: Cone in cones:
			if Vector2(x, z).distance_to(c.center) < c.radius * 0.95 + pad:
				return true
	if not _moving_blocks or not _nearest(x, z):
		return false
	var si := _hseg
	if not (rivers[_sriver[si]] as River).moving:
		return false
	var w := maxf(_sw0[si], _sw1[si])
	return absf(_hd) < w * 2.0 + pad


## Where smoke rises off moving lava: points along the moving rivers,
## `spacing` apart, and the middle of every crater lake. (x, kind, z) in the
## field's frame, kind 1 for a lake and 0 for a river.
func smoke_points(spacing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c: Cone in cones:
		if c.lake:
			out.append(Vector3(c.center.x, 1.0, c.center.y))
	for r: River in rivers:
		if not r.moving:
			continue
		var next := spacing * 0.5
		for i in range(1, r.points.size()):
			while next <= r.s[i]:
				var u := (next - r.s[i - 1]) / maxf(r.s[i] - r.s[i - 1], 1e-4)
				var p := r.points[i - 1].lerp(r.points[i], u)
				out.append(Vector3(p.x, 0.0, p.y))
				next += spacing
	return out


# ----------------------------------------------------------------- the shapes

func _shore(mask: float) -> float:
	return smoothstep(0.0, _shore_w, mask)


# The terraces and the cones: everything but the rivers, which are carved into
# this (`_carve`) and traced over it (`_trace_h`).
func _built(x: float, z: float) -> float:
	var h := 0.0
	if _terrace_h > 0.0:
		var open := _open(x, z)
		if open > 0.0:
			h += _terrace(x, z) * open
	if _cone_box.has_point(Vector2(x, z)):
		for c: Cone in cones:
			var dx := x - c.center.x
			var dz := z - c.center.y
			if dx * dx + dz * dz < c.radius * c.radius:
				h += _cone_h(c, dx, dz)
	return h


# THE TERRACES: a slow noise cut into `_terrace_steps` steps, each a level
# top and a steep front, `_terrace_h` metres a step. The lowest share of the
# noise (`_terrace_floor`) is left at the old ground, so not all of it is high.
func _terrace(x: float, z: float) -> float:
	var n := _terrace_noise.get_noise_2d(x, z) * 0.5 + 0.5
	var v := clampf((n - _terrace_floor) / (1.0 - _terrace_floor), 0.0, 1.0) * float(_terrace_steps)
	var k := floorf(v)
	var fr := v - k
	return (k + smoothstep(1.0 - _terrace_front, 1.0, fr)) * _terrace_h


# 1 except near a ruin's slide line, where the terraces ease out.
func _open(x: float, z: float) -> float:
	var list = _ruin_cells.get(Vector2i(floori(x / RUIN_CELL), floori(z / RUIN_CELL)))
	if list == null:
		return 1.0
	var p := Vector2(x, z)
	var open := 1.0
	for i: int in list:
		var d := _seg_dist(p, _ruin_a[i], _ruin_b[i])
		open = minf(open, smoothstep(_ruin_r[i], _ruin_r[i] + _ruin_fade, d))
	return open


# A cone, at (dx, dz) from its centre, metres over the ground it stands on.
#
# THE PROFILE: a bowl inside the rim and a concave flank outside it (steepest
# under the rim, easing out to nothing at the foot), the two met by a smooth
# minimum, so the rim is a crest a few metres round rather than a knife.
# THE BREACH: the rim and the crater wall lowered on one bearing, a gap the
# lake drains through. THE GULLIES: valleys running straight down the
# flank between rounded ribs, wandering a little as they go, deepest at
# mid-flank and gone at the rim and the foot.
func _cone_h(c: Cone, dx: float, dz: float) -> float:
	var r := sqrt(dx * dx + dz * dz)
	var u := r / c.radius
	var uc := c.crater
	var p := 1.35
	var flank := c.height * pow(maxf(1.0 - u, 0.0) / (1.0 - uc), p)
	var floor_y := c.height - c.depth
	var bowl := floor_y + c.depth * pow(u / uc, 2.2)
	var k := maxf(c.height * 0.07, 1.5)
	var h := _smin(bowl, flank, k)
	var th := atan2(dz, dx)
	var off := absf(angle_difference(th, c.breach))
	var notch := exp(-pow(off / c.breach_w, 2.0))
	h -= c.notch * notch * exp(-pow((u - uc) / (uc * 0.9), 2.0))
	if c.gullies > 0 and u > uc:
		var fl := clampf((u - uc) / (1.0 - uc), 0.0, 1.0)
		var amp := c.gully_depth * pow(sin(PI * fl), _gully_ease) * (1.0 - notch)
		var wob := 0.3 * sin(u * 9.0 + c.phase) + 0.15 * sin(u * 23.0 + th * 3.0 + c.phase * 2.0)
		var a := th * float(c.gullies) / TAU + wob * 0.35 + c.phase
		var tri := absf((a - floorf(a)) * 2.0 - 1.0)
		# Rounded in the bottom and over the rib, not V-cut: a cosine across.
		var gully := pow(0.5 + 0.5 * cos(PI * tri), 1.5)
		h -= amp * gully
	# The foot: eased to nothing over the last tenth, so a cone never ends on a
	# crease however its flank and the gullies meet the ground.
	return h * smoothstep(1.0, 0.9, u)


static func _smin(a: float, b: float, k: float) -> float:
	var hh := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, hh) - k * hh * (1.0 - hh)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


# The nearest river segment within its reach of (x, z), into `_hseg`, `_hu`
# (along it, 0..1) and `_hd` (signed distance off it, metres; positive to the
# river's left looking downstream). False when none reaches.
func _nearest(x: float, z: float) -> bool:
	if x == _hx and z == _hz:
		return _hseg >= 0
	_hx = x
	_hz = z
	_hseg = -1
	var list = _grid.get(Vector2i(floori(x / GRID), floori(z / GRID)))
	if list == null:
		return false
	var p := Vector2(x, z)
	var best := INF
	for si: int in list:
		var ap := p - _sa[si]
		var ab := _sab[si]
		var u := clampf(ap.dot(ab) / _sl2[si], 0.0, 1.0)
		var dd := (ap - ab * u).length_squared()
		if dd < best:
			best = dd
			_hseg = si
			_hu = u
	if _hseg < 0:
		return false
	var dist := sqrt(best)
	if dist > _sreach[_hseg]:
		_hseg = -1
		return false
	var ab2 := _sab[_hseg]
	var ap2 := p - _sa[_hseg]
	_hd = dist if ab2.x * ap2.y - ab2.y * ap2.x >= 0.0 else -dist
	return true


# The river at the last `_nearest` hit, carved into the ground `g` there.
#
# THE CHANNEL: the ground taken to the river's surface across its width, out
# to its walls, which are as wide as the cut is deep (`WALL_SLOPE`), so a deep
# gorge has walls a climber could see and a channel on the level has a lip;
# `flow_wall_soften` times as wide on an island that wants its banks gentler.
# THE LEVEES: a bank either side, just outside the walls, where the cut is
# shallow; in a gorge there is none, the river having cut below where it
# would have built them. Both eased out at the coast with everything else.
func _carve(g: float, ls: float) -> float:
	var si := _hseg
	var u := _hu
	var w := lerpf(_sw0[si], _sw1[si], u)
	var bed := lerpf(_sbed0[si], _sbed1[si], u)
	var ad := absf(_hd)
	var cut := g - bed
	var wall := clampf(cut * WALL_SLOPE * _wall_soft, WALL_MIN * _wall_soft, WALL_MAX * _wall_soft)
	var chan := 1.0 - smoothstep(w * 0.9, w + wall, ad)
	var river: River = rivers[_sriver[si]]
	var depth := _depth_moving if river.moving else _depth_still
	var lh := _levee_moving if river.moving else _levee_still
	# Round a toe the levees wrap the lobe's front and stand taller.
	var s := lerpf(_ss0[si], _ss1[si], u)
	if river.toe:
		lh *= 1.0 + 0.8 * (1.0 - smoothstep(0.0, _toe_length, river.length - s))
	var lw := w * 0.45 + 2.5
	var lev := lh * exp(-pow((ad - (w + wall * 0.5 + lw)) / lw, 2.0)) \
			* (1.0 - smoothstep(depth + 1.0, depth + 6.0, cut))
	if _water:
		# UNDER THE WATER: the bed `water_depth` down, shelving to the shore at
		# the half-width; the water lies over it at the river's surface.
		var floor_h := bed - water_depth(ad / maxf(w, 0.01), river.moving)
		return lerpf(g, floor_h, chan * ls) + lev * ls
	return lerpf(g, bed, chan * ls) + lev * ls


# ------------------------------------------------------------------ building

func _build(field: IslandField, isl, zones: Array) -> void:
	_shore_w = maxf(field.flow_shore, 0.001)
	_terrace_h = maxf(field.flow_terrace_height, 0.0)
	_terrace_steps = maxi(field.flow_terrace_steps, 1)
	_terrace_front = clampf(field.flow_terrace_front, 0.02, 1.0)
	_terrace_floor = clampf(field.flow_terrace_floor, 0.0, 0.95)
	_depth_moving = field.flow_moving_depth
	_depth_still = field.flow_still_depth
	_levee_moving = field.flow_moving_levee
	_levee_still = field.flow_still_levee
	_toe_height = field.flow_toe_height
	_toe_length = field.flow_toe_length
	_cone_soil = field.flow_cone_ground == 1
	_moving_blocks = field.flow_moving_blocks_trails
	_splined = field.flow_river_spline
	_spline_step = maxf(field.flow_spline_step, 1.0)
	_water = field.flow_water_mesh
	_water_depth = maxf(field.flow_water_depth, 0.0)
	_wall_soft = maxf(field.flow_wall_soften, 1.0)
	_gully_ease = maxf(field.flow_gully_ease, 0.1)
	_terrace_noise = FastNoiseLite.new()
	_terrace_noise.seed = field.world_seed ^ 0x1A7A
	_terrace_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_terrace_noise.frequency = 1.0 / maxf(field.flow_terrace_scale, 1.0)
	_terrace_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_terrace_noise.fractal_octaves = 2

	var rng := RandomNumberGenerator.new()
	rng.seed = (isl.cell.x * 52711) ^ (isl.cell.y * 14627) ^ field.world_seed ^ 0x1A7A0

	# The holes and pads, with their reach: what every part of this keeps off.
	var keep_zones: Array = []
	for entry in zones:
		var zn: IslandField.Zone = entry
		if zn.kind == IslandField.ZONE_PATH:
			continue
		keep_zones.append([zn, zn.width * (1.0 + field.zone_irregularity) + zn.apron + zn.skirt])
	_ruin_lines(field, isl)
	_place_lagoon(field, isl, zones)

	_place_cones(field, isl, keep_zones, rng)
	_place_rivers(field, isl, keep_zones, rng)
	_place_crossings(field, isl, zones)
	_index_rivers()


# THE LAVA ACROSS A RACE TRACK'S RING (`IslandField.flow_ring_crossings`): a moving
# river at each bearing, straight across the ring and `flow_crossing_reach` past
# its edges, its surface `flow_crossing_depth` under the ring's shelf (the safe
# zone's lift). The rest of the flows know nothing of them; `crossing` cuts them
# again after the shelves.
func _place_crossings(field: IslandField, isl, zones: Array) -> void:
	var ring := field.safe_ring_radius
	if ring <= 0.0 or field.flow_ring_crossings.is_empty():
		return
	var lift := 0.0
	for e in zones:
		var zn: IslandField.Zone = e
		if zn.safe:
			lift = zn.lift
			break
	var half := field.safe_zone_radius * (1.0 + field.zone_irregularity) + field.flow_crossing_reach
	var bed := lift - maxf(field.flow_crossing_depth, 0.5)
	var w := maxf(field.flow_crossing_width, 1.0)
	for deg: float in field.flow_ring_crossings:
		var dir := Vector2.from_angle(deg_to_rad(deg))
		var a: Vector2 = isl.center + dir * (ring - half)
		var n := maxi(int(ceil(2.0 * half / 10.0)), 2)
		var r := River.new()
		r.moving = true
		for i in n + 1:
			var t := float(i) / float(n)
			r.points.append(a + dir * (2.0 * half * t))
			r.s.append(2.0 * half * t)
			r.bed.append(bed)
			r.width.append(w)
		r.length = 2.0 * half
		_crossings[rivers.size()] = true
		rivers.append(r)


## Whether river `ri` is one of the lava crossings of a race track's ring.
func is_crossing(ri: int) -> bool:
	return _crossings.has(ri)


## THE LAVA ACROSS A RACE TRACK'S RING cut into the ground `g` (metres over the
## base, the zones' shelves in it), as `relief` cut it before them; elsewhere `g`
## as it was. `IslandField.base_height` calls it after the shelves.
func crossing(x: float, z: float, mask: float, g: float) -> float:
	if _crossings.is_empty() or not _nearest(x, z) or not _crossings.has(_sriver[_hseg]):
		return g
	var ls := _shore(mask)
	return _carve(g, ls) if ls > 0.0 else g


# THE RUINS' SLIDE LINES. Each entrance of the ring is placed on a radial line,
# anywhere `ruin_ring_slide` along it, by surveying the ground round it; the
# flows keep that far off the whole of every line, so the survey finds the
# ground it found before there were any, and the ring stands where it did.
func _ruin_lines(field: IslandField, isl) -> void:
	if not field.ruin_enabled or field.ruin_ring_count <= 0:
		return
	var ring: float = isl.radius * field.ruin_ring_radius
	var slide := maxf(field.ruin_ring_slide, 0.0)
	var r := field.ruin_outer_radius() + field.flow_ruin_gap
	for k in range(field.ruin_ring_count):
		var ang := deg_to_rad(field.ruin_ring_spin) + TAU * float(k) / float(field.ruin_ring_count)
		var dir := Vector2(cos(ang), sin(ang))
		var a: Vector2 = isl.center + dir * maxf(ring - slide, 0.0)
		var b: Vector2 = isl.center + dir * (ring + slide)
		var i := _ruin_a.size()
		_ruin_a.append(a)
		_ruin_b.append(b)
		_ruin_r.append(r)
		var reach := r + _ruin_fade
		var cells := {}
		for cx in range(floori((minf(a.x, b.x) - reach) / RUIN_CELL), floori((maxf(a.x, b.x) + reach) / RUIN_CELL) + 1):
			for cz in range(floori((minf(a.y, b.y) - reach) / RUIN_CELL), floori((maxf(a.y, b.y) + reach) / RUIN_CELL) + 1):
				var key := Vector2i(cx, cz)
				var arr: PackedInt32Array = _ruin_cells.get(key, PackedInt32Array())
				arr.append(i)
				_ruin_cells[key] = arr


# THE LAGOON: round the island's middle, its shores' wander rolled off their own
# numbers (the rest roll as they would), its water a little under the lowest of
# the ground round both its shores, the zones' shelves in it (the flows are not
# yet: `IslandField.flows_building`), so every beach stands out of it.
func _place_lagoon(field: IslandField, isl, zones: Array) -> void:
	if field.flow_lagoon_radius <= 0.0 or not _water:
		return
	_lagoon = true
	_lag_c = isl.center
	_lag_out = field.flow_lagoon_radius
	_lag_in = clampf(field.flow_lagoon_islet, 0.0, _lag_out - 20.0)
	_lag_wob = field.flow_lagoon_wobble
	_lag_depth = maxf(field.flow_lagoon_depth, 0.1)
	_lag_shelf = maxf(field.flow_lagoon_shelf, 1.0)
	_lag_beach = maxf(field.flow_lagoon_beach, 0.0)
	_lag_core = field.safe_zone_radius * (1.0 + field.zone_irregularity)
	var lr := RandomNumberGenerator.new()
	lr.seed = field.world_seed ^ 0x1A6005
	for k in range(4):
		_lag_ph[k] = lr.randf() * TAU
	_lag_reach = _lag_out * (1.0 + _lag_wob) + _lag_beach + 60.0
	var zi: Array = [IslandField.ZONE_ROUGH, 0.0, 0, 1e9, 0.0]
	var low := INF
	for k in range(144):
		var th := TAU * float(k) / 144.0
		var sh := lagoon_shores(th)
		var dir := Vector2.from_angle(th)
		for r: float in [sh.x - _lag_beach, sh.x - _lag_beach * 0.5, sh.y + _lag_beach * 0.5,
				sh.y + _lag_beach]:
			if r <= 0.0:
				continue
			var q: Vector2 = _lag_c + dir * r
			var m := field.mask_for(isl, q.x, q.y)
			field.zone_at(q.x, q.y, zones, zi)
			low = minf(low, field.base_height(q.x, q.y, m, isl, zi[4], zi[1], false) - isl.base_y)
	_lag_level = low - 0.6
	# The ground at the middle of the islet, for the level spot the stone stands on.
	var mc := field.mask_for(isl, _lag_c.x, _lag_c.y)
	field.zone_at(_lag_c.x, _lag_c.y, zones, zi)
	_flat_h = field.base_height(_lag_c.x, _lag_c.y, mc, isl, zi[4], zi[1], false) - isl.base_y
	_place_causeway()
	_place_crash()


# Clear of every hole and pad by `gap` past its reach, and of every ruin line?
func _clear_of(p: Vector2, gap: float, keep_zones: Array) -> bool:
	for kz in keep_zones:
		var zn: IslandField.Zone = kz[0]
		if zn.axis_distance(p) < float(kz[1]) + gap:
			return false
	for i in range(_ruin_a.size()):
		if _seg_dist(p, _ruin_a[i], _ruin_b[i]) < _ruin_r[i] + gap:
			return false
	return true


func _place_cones(field: IslandField, isl, keep_zones: Array, rng: RandomNumberGenerator) -> void:
	# THE MIDDLE'S VOLCANO (`flow_center_cone`), before any other and drawing no
	# numbers, so the rest roll as they would.
	if field.flow_center_cone > 0.0:
		var m := Cone.new()
		m.center = isl.center
		m.radius = field.flow_center_cone
		m.height = m.radius * field.flow_center_cone_height
		m.crater = (field.flow_cone_crater.x + field.flow_cone_crater.y) * 0.5
		m.depth = m.height * (field.flow_cone_depth.x + field.flow_cone_depth.y) * 0.5
		m.breach = 0.0
		m.breach_w = 0.38
		m.notch = m.depth * 0.65
		m.gullies = maxi(int(round(m.radius * field.flow_gully_density)), 6)
		m.gully_depth = m.height * 0.06
		m.lake = field.flow_lakes > 0
		cones.append(m)
	var want := maxi(field.flow_cones, 0)
	var tries := 500
	var big := 0
	for i in range(tries):
		if big >= want:
			break
		var shrink := float(i) / float(tries)
		var rad := lerpf(field.flow_cone_radius.y, field.flow_cone_radius.x, shrink) * rng.randf_range(0.85, 1.0)
		var at: Vector2 = isl.center + Vector2.from_angle(rng.randf() * TAU) \
				* isl.radius * sqrt(rng.randf_range(0.2, 1.3))
		if not _cone_fits(field, isl, at, rad, keep_zones, field.flow_zone_gap):
			continue
		var c := Cone.new()
		c.center = at
		c.radius = rad
		c.height = rad * rng.randf_range(field.flow_cone_height.x, field.flow_cone_height.y)
		c.crater = rng.randf_range(field.flow_cone_crater.x, field.flow_cone_crater.y)
		c.depth = c.height * rng.randf_range(field.flow_cone_depth.x, field.flow_cone_depth.y)
		# Breached toward the sea, more or less: that is where its river goes.
		var out: float = (at - isl.center).angle()
		c.breach = out + rng.randf_range(-0.9, 0.9)
		c.breach_w = rng.randf_range(0.3, 0.45)
		c.notch = c.depth * rng.randf_range(0.55, 0.75)
		c.gullies = maxi(int(round(rad * field.flow_gully_density)), 6)
		c.gully_depth = c.height * rng.randf_range(0.045, 0.075)
		c.phase = rng.randf() * TAU
		c.lake = big < field.flow_lakes
		cones.append(c)
		big += 1
	var small := 0
	for i in range(tries):
		if small >= field.flow_vents:
			break
		var rad := rng.randf_range(field.flow_vent_radius.x, field.flow_vent_radius.y)
		var at: Vector2 = isl.center + Vector2.from_angle(rng.randf() * TAU) \
				* isl.radius * sqrt(rng.randf_range(0.3, 1.3))
		if not _cone_fits(field, isl, at, rad + 40.0, keep_zones, field.flow_zone_gap):
			continue
		var c := Cone.new()
		c.vent = true
		c.center = at
		c.radius = rad
		c.height = rad * rng.randf_range(field.flow_vent_height.x, field.flow_vent_height.y)
		c.crater = 0.38
		c.depth = c.height * 0.5
		c.breach = (at - isl.center).angle() + rng.randf_range(-1.2, 1.2)
		c.breach_w = 0.5
		c.notch = c.depth * 0.8
		c.lake = false
		cones.append(c)
		small += 1
	_cone_box = Rect2()
	for i in range(cones.size()):
		var c: Cone = cones[i]
		var box := Rect2(c.center - Vector2.ONE * c.radius, Vector2.ONE * c.radius * 2.0)
		_cone_box = box if i == 0 else _cone_box.merge(box)


func _cone_fits(field: IslandField, isl, at: Vector2, rad: float, keep_zones: Array,
		gap: float) -> bool:
	if field.mask_for(isl, at.x, at.y) < field.flow_cone_inland:
		return false
	for k in range(16):
		var q := at + Vector2.from_angle(TAU * float(k) / 16.0) * rad * 1.05
		if field.mask_for(isl, q.x, q.y) < _shore_w:
			return false
	if not _clear_of(at, rad + gap, keep_zones):
		return false
	for other: Cone in cones:
		if at.distance_to(other.center) < rad + other.radius + 30.0:
			return false
	return true


# The ground a river is traced over: the wild ground with the terraces and the
# cones in it, without the micro relief (`micro`), whose metre-scale slopes
# would turn it every step.
func _trace_h(field: IslandField, isl, p: Vector2, micro: bool) -> float:
	var m := field.mask_for(isl, p.x, p.y)
	return field.wild_ground(isl, p.x, p.y, m, micro) + _built(p.x, p.y) * _shore(m)


func _trace_grad(field: IslandField, isl, p: Vector2) -> Vector2:
	var e := 8.0
	return Vector2(
			_trace_h(field, isl, p + Vector2(e, 0.0), false) - _trace_h(field, isl, p - Vector2(e, 0.0), false),
			_trace_h(field, isl, p + Vector2(0.0, e), false) - _trace_h(field, isl, p - Vector2(0.0, e), false)) / (2.0 * e)


func _place_rivers(field: IslandField, isl, keep_zones: Array, rng: RandomNumberGenerator) -> void:
	var taken := {}   # cell -> Array of [point, half-width] of rivers already laid
	for ci in range(cones.size()):
		var c: Cone = cones[ci]
		var bdir := Vector2.from_angle(c.breach)
		if c.vent:
			var moving := rng.randf() < field.flow_vent_moving
			var vw := field.flow_vent_moving_width if moving else field.flow_vent_still_width
			var w := rng.randf_range(vw.x, vw.y)
			_river(field, isl, c.center + bdir * c.radius * 0.3, bdir, moving, w, ci, 0.0,
					keep_zones, taken, rng)
			continue
		if c.lake:
			# The lake is the river's head: the channel runs straight across the
			# crater floor to the breach, widened to the lake, and out. Water fills
			# the crater to the lake's level, so its shore is where the bowl
			# (`_cone_h`, its walls rising as the 2.2 power) reaches the fill.
			var lake_r := c.radius * c.crater * (pow(clampf(field.flow_lake_fill, 0.05, 0.95), 1.0 / 2.2)
					if _water else 0.62)
			var w := rng.randf_range(field.flow_moving_width.x, field.flow_moving_width.y)
			_river(field, isl, c.center - bdir * lake_r, bdir, true, w, ci, lake_r,
					keep_zones, taken, rng)
		else:
			# A dry crater's breach flow: still (an old lava flow), or moving at
			# `flow_breach_moving` odds (a glacier out of a peak's cirque). The odds
			# are only rolled where there are any, so a field with none draws the
			# same numbers it always did.
			var moving := field.flow_breach_moving > 0.0 and rng.randf() < field.flow_breach_moving
			var bw := field.flow_moving_width if moving else field.flow_still_width
			var w := rng.randf_range(bw.x, bw.y)
			_river(field, isl, c.center + bdir * c.radius * c.crater * 0.8, bdir, moving, w, ci, 0.0,
					keep_zones, taken, rng)
		# Flows out of the flanks: still, or moving at `flow_flank_moving` odds,
		# rolled on the same terms.
		var flows := rng.randi_range(field.flow_flank_flows.x, field.flow_flank_flows.y)
		for _f in range(flows):
			var bearing := c.breach + rng.randf_range(0.9, PI - 0.4) * (1.0 if rng.randf() < 0.5 else -1.0)
			var dir := Vector2.from_angle(bearing)
			var u := rng.randf_range(0.35, 0.6)
			var moving := field.flow_flank_moving > 0.0 and rng.randf() < field.flow_flank_moving
			var fw := field.flow_moving_width if moving else field.flow_still_width
			var w := rng.randf_range(fw.x, fw.y)
			_river(field, isl, c.center + dir * c.radius * u, dir, moving, w, ci, 0.0,
					keep_zones, taken, rng)


# Trace one river downhill from `start` and keep it if it runs far enough.
#
# EACH STEP turns toward the steepest way down (strongly on a cone's flank,
# barely on the level), keeps most of its heading, leans a little toward the
# sea, and wanders across its line on a slow wave, never turning more than
# `MAX_TURN` a step. It stops at the coast, or short of anything it may not
# reach: a hole's or pad's bank, a ruin's line, another cone, another river,
# itself. `lake_r` > 0 makes it a crater lake's: it runs straight out of the
# lake before it is free to turn.
func _river(field: IslandField, isl, start: Vector2, dir0: Vector2, moving: bool, w: float,
		own: int, lake_r: float, keep_zones: Array, taken: Dictionary,
		rng: RandomNumberGenerator) -> void:
	const MAX_TURN := 0.14
	var step := maxf(field.flow_river_step, 2.0)
	var pts := PackedVector2Array([start])
	var p := start
	var dir := dir0.normalized()
	var own_cone: Cone = cones[own]
	var straight := 0.0
	if lake_r > 0.0:
		straight = own_cone.radius * own_cone.crater + lake_r + 12.0
	var wf := rng.randf_range(1.0 / 260.0, 1.0 / 140.0)
	var wph := rng.randf() * TAU
	var travelled := 0.0
	var coast := false
	var reach := w * 3.0
	while travelled < field.flow_river_max:
		var want := dir
		if travelled >= straight:
			var down := -_trace_grad(field, isl, p)
			var gl := down.length()
			var seaward: Vector2 = (p - isl.center).normalized()
			want = dir * 1.0 + seaward * field.flow_river_seaward \
					+ dir.orthogonal() * sin(travelled * wf * TAU + wph) * 0.3
			if gl > 1e-5:
				want += down / gl * clampf(gl * 10.0, 0.0, 1.8)
			want = want.normalized()
		var turn := clampf(dir.angle_to(want), -MAX_TURN, MAX_TURN)
		dir = dir.rotated(turn)
		var q := p + dir * step
		var mq := field.mask_for(isl, q.x, q.y)
		if mq <= 0.002:
			# Over the lip: find it, and end the river on it.
			var lo := 0.0
			var hi := 1.0
			for _k in range(16):
				var mid := (lo + hi) * 0.5
				var t := p.lerp(q, mid)
				if field.mask_for(isl, t.x, t.y) > 0.002:
					lo = mid
				else:
					hi = mid
			pts.append(p.lerp(q, lo))
			coast = true
			break
		if not _river_clear(q, reach, own, keep_zones, taken, pts, field):
			break
		pts.append(q)
		p = q
		travelled += step
	if travelled < field.flow_river_min and lake_r <= 0.0:
		return
	if pts.size() < 3:
		return
	var r := River.new()
	r.moving = moving
	r.toe = not coast
	r.lake = lake_r > 0.0
	r.points = _spline(pts, _spline_step) if _splined else _smooth(pts, step)
	_grade(field, isl, r, w, lake_r)
	var ri := rivers.size()
	rivers.append(r)
	for i in range(r.points.size()):
		var key := Vector2i(floori(r.points[i].x / 48.0), floori(r.points[i].y / 48.0))
		var arr: Array = taken.get(key, [])
		arr.append([r.points[i], reach, ri])
		taken[key] = arr


func _river_clear(q: Vector2, reach: float, own: int, keep_zones: Array, taken: Dictionary,
		own_pts: PackedVector2Array, field: IslandField) -> bool:
	if not _clear_of(q, reach + field.flow_zone_gap, keep_zones):
		return false
	if _lagoon and q.distance_to(_lag_c) < _lag_reach + reach:
		return false
	for ci in range(cones.size()):
		if ci == own:
			continue
		var c: Cone = cones[ci]
		if q.distance_to(c.center) < c.radius * 0.85 + reach:
			return false
	var key := Vector2i(floori(q.x / 48.0), floori(q.y / 48.0))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for e in taken.get(key + Vector2i(dx, dz), []):
				if q.distance_to(e[0]) < reach + float(e[1]) + 10.0:
					return false
	# Itself, past the last few steps: no river runs back across its own bed.
	for i in range(0, own_pts.size() - 8):
		if q.distance_to(own_pts[i]) < reach * 2.0:
			return false
	return true


# Two passes of Chaikin's corner cutting, the ends held, then resampled to an
# even `step`: a river bends, it does not kink. A lake's head is straight, and
# corner cutting leaves a straight run straight.
static func _smooth(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var cur := pts
	for _pass in range(2):
		var nxt := PackedVector2Array([cur[0]])
		for i in range(cur.size() - 1):
			var a := cur[i]
			var b := cur[i + 1]
			if i > 0:
				nxt.append(a.lerp(b, 0.25))
			if i < cur.size() - 2:
				nxt.append(a.lerp(b, 0.75))
		nxt.append(cur[cur.size() - 1])
		cur = nxt
	return _resample(cur, step)


# A polyline resampled to an even `step` along it, its ends held.
static func _resample(cur: PackedVector2Array, step: float) -> PackedVector2Array:
	var total := 0.0
	for i in range(cur.size() - 1):
		total += cur[i].distance_to(cur[i + 1])
	var n := maxi(int(round(total / step)), 1)
	var out := PackedVector2Array([cur[0]])
	var seg := 0
	var seg_s := 0.0
	for k in range(1, n):
		var want := total * float(k) / float(n)
		while seg < cur.size() - 2 and seg_s + cur[seg].distance_to(cur[seg + 1]) < want:
			seg_s += cur[seg].distance_to(cur[seg + 1])
			seg += 1
		var l := cur[seg].distance_to(cur[seg + 1])
		out.append(cur[seg].lerp(cur[seg + 1], clampf((want - seg_s) / maxf(l, 1e-4), 0.0, 1.0)))
	out.append(cur[cur.size() - 1])
	return out


# THE GRADE. The river's surface is the lowest the ground has been anywhere up
# its course, less its depth: it never climbs, so where the land rises across
# its path it holds level and cuts through (a gorge), and where the land falls
# it follows. Smoothed down its length without ever climbing. A lake's surface
# is level, at the crater floor plus a fill, and holds the river at it out
# through the breach until the flank falls away under it. A toe stands proud
# of the ground at the end.
func _grade(field: IslandField, isl, r: River, w: float, lake_r: float) -> void:
	var n := r.points.size()
	r.s.resize(n)
	r.bed.resize(n)
	r.width.resize(n)
	var acc := 0.0
	for i in range(n):
		if i > 0:
			acc += r.points[i].distance_to(r.points[i - 1])
		r.s[i] = acc
	r.length = acc
	var depth := _depth_moving if r.moving else _depth_still
	var ground := PackedFloat32Array()
	ground.resize(n)
	for i in range(n):
		ground[i] = _trace_h(field, isl, r.points[i], true)
	var lake_level := INF
	if lake_r > 0.0:
		var lo := INF
		for i in range(n):
			if r.s[i] <= lake_r * 2.0:
				lo = minf(lo, ground[i])
		var c := _cone_at(r.points[0])
		lake_level = lo + (c.depth * field.flow_lake_fill if c != null else 0.0)
	var low := INF
	for i in range(n):
		low = minf(low, ground[i])
		r.bed[i] = minf(low - depth, lake_level)
		if lake_r > 0.0 and r.s[i] <= lake_r * 2.0:
			r.bed[i] = lake_level
	# Smoothed, then held to never climb.
	for _pass in range(3):
		var nxt := r.bed.duplicate()
		for i in range(1, n - 1):
			nxt[i] = (r.bed[i - 1] + r.bed[i] * 2.0 + r.bed[i + 1]) * 0.25
		r.bed = nxt
	for i in range(1, n):
		r.bed[i] = minf(r.bed[i], r.bed[i - 1])
	# The width: a lake's head round as the lake, a flank vent's narrow at the
	# vent and widening as it runs.
	for i in range(n):
		var wi := w
		if lake_r > 0.0:
			var ds := r.s[i] - lake_r
			wi = maxf(w, sqrt(maxf(lake_r * lake_r - ds * ds, 0.0)))
		else:
			wi = w * clampf(0.45 + r.s[i] / 60.0, 0.45, 1.0)
		r.width[i] = wi
	if r.toe:
		for i in range(n):
			var k := 1.0 - smoothstep(0.0, _toe_length, r.length - r.s[i])
			# Water that ends on the land does not climb out of its bed in a lobe:
			# it narrows and ends in a pool, the channel's round end.
			if _water:
				r.width[i] *= 1.0 - 0.45 * k
			else:
				r.bed[i] += (depth + _toe_height) * k


# THE SPLINE: a centripetal Catmull-Rom curve through every third point of the
# trace (30 m apart at the trace's 10 m step), its ends held, drawn densely and
# resampled to an even `step`. It passes through its control points, so it stays
# on the trace's cleared ground within a metre or two, and its curvature is
# continuous: a river meanders, it does not run in chords. Centripetal, so it
# never loops or overshoots where the points bunch.
static func _spline(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var ctl := PackedVector2Array()
	for i in range(0, pts.size(), 3):
		ctl.append(pts[i])
	var last := pts[pts.size() - 1]
	if ctl[ctl.size() - 1] != last:
		if ctl.size() >= 2 and ctl[ctl.size() - 1].distance_to(last) < 12.0:
			ctl[ctl.size() - 1] = last
		else:
			ctl.append(last)
	if ctl.size() < 3:
		return _resample(ctl, step)
	var dense := PackedVector2Array([ctl[0]])
	for i in range(ctl.size() - 1):
		var p1 := ctl[i]
		var p2 := ctl[i + 1]
		var p0 := ctl[i - 1] if i > 0 else p1 * 2.0 - p2
		var p3 := ctl[i + 2] if i + 2 < ctl.size() else p2 * 2.0 - p1
		var sub := maxi(int(ceil(p1.distance_to(p2) / (step * 0.5))), 2)
		for k in range(1, sub + 1):
			dense.append(_catmull_rom(p0, p1, p2, p3, float(k) / float(sub)))
	return _resample(dense, step)


# One span of a centripetal Catmull-Rom spline, p1 to p2, at `t` 0..1
# (Barry and Goldman's pyramid).
static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t1 := maxf(sqrt(p0.distance_to(p1)), 1e-3)
	var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 1e-3)
	var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 1e-3)
	var tt := lerpf(t1, t2, t)
	var a1 := p0.lerp(p1, tt / t1)
	var a2 := p1.lerp(p2, (tt - t1) / (t2 - t1))
	var a3 := p2.lerp(p3, (tt - t2) / (t3 - t2))
	var b1 := a1.lerp(a2, tt / t2)
	var b2 := a2.lerp(a3, (tt - t1) / (t3 - t1))
	return b1.lerp(b2, (tt - t1) / (t2 - t1))


func _cone_at(p: Vector2) -> Cone:
	for c: Cone in cones:
		if p.distance_to(c.center) < c.radius:
			return c
	return null


func _index_rivers() -> void:
	for ri in range(rivers.size()):
		var r: River = rivers[ri]
		for i in range(r.points.size() - 1):
			var a := r.points[i]
			var b := r.points[i + 1]
			var si := _sa.size()
			_sa.append(a)
			_sab.append(b - a)
			_sl2.append(maxf((b - a).length_squared(), 1e-6))
			_ss0.append(r.s[i])
			_ss1.append(r.s[i + 1])
			_sbed0.append(r.bed[i])
			_sbed1.append(r.bed[i + 1])
			_sw0.append(r.width[i])
			_sw1.append(r.width[i + 1])
			_sriver.append(ri)
			var wm := maxf(r.width[i], r.width[i + 1])
			# Past the scoured ground, the walls of the deepest gorge and the
			# levees beyond them, and the codes' margin past that.
			var reach := maxf(wm * 3.0, wm + WALL_MAX * _wall_soft + wm * 0.7 + 3.0) + CODE_MARGIN
			_sreach.append(reach)
			for cx in range(floori((minf(a.x, b.x) - reach) / GRID), floori((maxf(a.x, b.x) + reach) / GRID) + 1):
				for cz in range(floori((minf(a.y, b.y) - reach) / GRID), floori((maxf(a.y, b.y) + reach) / GRID) + 1):
					# Only the cells the reach actually touches: the box's
					# corners are a long way off a diagonal segment.
					var cc := Vector2((float(cx) + 0.5) * GRID, (float(cz) + 0.5) * GRID)
					if _seg_dist(cc, a, b) > reach + GRID * 0.7072:
						continue
					var key := Vector2i(cx, cz)
					var arr: PackedInt32Array = _grid.get(key, PackedInt32Array())
					arr.append(si)
					_grid[key] = arr
