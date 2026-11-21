class_name RiverWater
extends Node3D

# THE RIVERS' WATER, a surface of its own (island 006's; the user: "Give me
# spline based rivers with sandy bottoms and rocky edges, and beautiful but still
# retro looking water shaders"). The field carves each river's channel under its
# surface, a sandy bed shelving up to rocky banks (`FlowTerrain`,
# `IslandField.flow_water_mesh`); this lays the water over it, one mesh for the
# island, drawn by SHADER_river_water.gdshader.
#
# THE SURFACE is each river's spline (`FlowTerrain.River.points`, every
# `IslandField.flow_spline_step` metres) swept across its width at its level
# (`FlowTerrain.water_level`): a row of `ACROSS` vertices every point, from one
# bank to the other and on under each by `under_bank` of the half-width, where
# the bank has risen over it, so the shore is wherever the ground comes up out of
# the water, at any of the terrain's LODs. A crater lake is its river's head,
# which widens to the lake's round, so the same sweep is the lake. Where the
# channel ends on the land, at a spring and at a pool, it is round, and the water
# is too: a cap of rows narrowing over the channel's round end.
#
# WHAT EACH VERTEX CARRIES, for the shader:
#   UV       metres down the river and across it (positive to its left looking
#            downstream): the frame the ripples are drawn and run in;
#   UV2      how far off the middle, in half-widths, and 1 on a moving river or
#            0 on a still creek;
#   COLOR    r the water's depth over the bed there (`FlowTerrain.water_depth`)
#            over 4 m; g its fade at the coast, where the channel eases out to
#            the lip and the water with it; b its fade in at a spring;
#   CUSTOM0  the reach's HILL (below): x its flow time, y the share of a flat
#            reach's pace it covers a metre in (1 over how many times faster it
#            runs), z how steep it is, 0 flat to 1 flat out;
#   TANGENT  down the river, for the ripples' normal.
#
# THE WATER ON THE HILLS RUNS (the user: "Make water on hills much more faster
# moving, or at least appear faster moving"). The grade under each point, the
# water's drop a metre down the river read over `grade_window`, makes it steep
# (`grade_slack` to `grade_full`), and a steep reach runs up to `hill_speed`
# times as fast as a flat one; a still creek on a hill runs as a river does
# (UV2.y is how much it is running, 0 to 1). The shader runs the ripples down a
# FLOW TIME, not the metres: CUSTOM0.x climbs a metre for every metre of flat
# water and a fifth of one down a reach five times as fast, so the ripples, read
# at it and moved at one speed, run five times as fast there, drawn out down the
# flow as fast water is, and speed up and slow down along the river without the
# pattern tearing where they do. The steepness is smoothed over the same window,
# so a reach comes up to speed over a run of water rather than at a point.
#
# THE WAKES (the user: "vehicle --> water splashing rippling interaction
# (performant retro aesthetic)"; and later: "water ripples need more randomized sub
# ripples, clusters of ripples, higher frequency"). `ripple` sets a ring running
# out over the water from a point, as strong as asked, with a roll of its own that
# the shader turns into the sub-ripples round it; the shader draws up to `RIPPLES`
# at once from a slot each (see its header), and a new one past that takes the
# slot of the one with least left to show (weak and nearly done), so none that is
# still plain to see vanishes. The slots are in the field's frame, so a rebase
# carries the rings with the water;
# they are packed live-first, and the shader loops over only the live ones and
# only inside the box they reach, so water nothing has broken costs what it did.
# What breaks it is `WaterWakes` (SCRIPT_water_wakes.gd), stood up here as a
# child: the wheels that plough it and the jets that beat on it, and the
# droplets thrown up off both.
#
# THE FIELD'S FRAME: built in it, and stood at minus the world's origin offset.
# The node is a child of the scene's root and in no `origin_shiftable` group, so
# the floating origin moves it with everything else at a rebase.

@export var world_path: NodePath
@export var material: ShaderMaterial
## How far past its shore the water runs on under the banks, as a share of the
## half-width.
@export var under_bank := 0.14
## The surface stands this far over the river's level, metres, so it never meets
## the bed where the channel eases out at the coast.
@export var lift := 0.04
## A spring's water comes up over this many metres from its head.
@export var source_fade := 14.0
## Stand up `WaterWakes` (see THE WAKES): the vehicles' splashes and rings.
@export var wakes := true
## THE HILLS (see the header): the grade (metres of drop a metre down the river)
## at which a reach begins to run faster, and the grade it runs flat out at.
@export var grade_slack := 0.03
@export var grade_full := 0.25
## How many times as fast as flat water a reach runs flat out.
@export var hill_speed := 5.0
## The metres of river the grade is read over, and the steepness smoothed over.
@export var grade_window := 24.0
## The metres of hill the water takes to get up to its speed, and the metres of
## flat below it carries that speed on over.
@export var run_up := 9.0
@export var run_out := 22.0
## The metres over which a river slows into still water (a pool, the mere).
@export var meet := 18.0

## Across a river, its rows' vertices, in shares of its half-width (before
## `under_bank`).
const ACROSS := [-1.0, -0.8, -0.55, -0.28, 0.0, 0.28, 0.55, 0.8, 1.0]
## A round end's cap, its rows' distance past the end in shares of the
## half-width there.
const CAP := [0.35, 0.65, 0.88, 1.0]

var _world: Node = null
var _mi: MeshInstance3D = null
var _surfaces: Array = []   ## per river: {"river": River, "levels": PackedFloat32Array, "steep": PackedFloat32Array}
var _lagoon_y := NAN
## For `level_at`: the flows, and the river points in `LOOKUP_CELL` cells,
## Vector2i(river, point) each.
var _flows: FlowTerrain = null
var _lookup := {}
const LOOKUP_CELL := 16.0

## The rings the shader draws at once (its `ripples` array's size).
const RIPPLES := 64
## A ring's roll is one of this many: the shader's dice for its sub-ripples.
const ROLLS := 64
## The live rings, oldest first: Vector4(x, z in the field's frame, the clock it
## was made at, its strength 0 to 1).
var _rings: Array[Vector4] = []
## Each live ring's roll, 0 to `ROLLS` - 1, beside it in `_rings`.
var _rolls := PackedInt32Array()
## The rings' clock, seconds, while the tree runs: back to 0 whenever none is
## live, so the shader, which reads it in single precision, never reads a big one.
var _clock := 0.0
var _wakes: WaterWakes = null

## The lagoon's rows: one every this many metres round its outer shore, and this
## many vertices across, from under the islet's beach to under the outer one.
const LAGOON_STEP := 4.0
const LAGOON_ACROSS := 15
## How far under each beach its water runs on, metres.
const LAGOON_UNDER := 5.0
## The metres in from its shores its UV2.x runs over, 1 at the shore to 0: what
## the shader's shore foam reads, so still water frays only at its edge rather
## than over a share of its whole width.
const LAGOON_EDGE := 8.0


func _ready() -> void:
	_world = get_node_or_null(world_path)
	if _world == null or not _world.has_method(&"get_field"):
		push_warning("river_water: no GaiaSphere (set world_path)")
		return
	var field: IslandField = _world.call(&"get_field")
	if field == null:
		return
	if not field._ready:
		field.prepare()
	var hub: IslandField.Island = field.island_in_cell(field.hub_cell())
	if hub == null:
		return
	var flows := field.flows_for(hub)
	if flows == null or not flows.is_water():
		return
	_mi = MeshInstance3D.new()
	_mi.name = "Water"
	_mi.mesh = build_mesh(field, hub, flows)
	_mi.material_override = material
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	if _world.has_method(&"origin_offset"):
		position = -(_world.call(&"origin_offset") as Vector3)
	if wakes:
		_wakes = WaterWakes.new()
		_wakes.name = "Wakes"
		add_child(_wakes)
	_upload_rings()


func _process(delta: float) -> void:
	if _rings.is_empty() or material == null:
		_clock = 0.0
		return
	_clock += delta
	var n := _rings.size()
	# Any that have run out: oldest first is not first out, since a weak ring
	# dies sooner than a strong one made before it.
	var live: Array[Vector4] = []
	var rolls := PackedInt32Array()
	for i in _rings.size():
		var r := _rings[i]
		if _clock - r.z < ring_life_of(r.w):
			live.append(r)
			rolls.append(_rolls[i])
	_rings = live
	_rolls = rolls
	if _rings.size() != n:
		_upload_rings()
	material.set_shader_parameter(&"ripple_now", _clock)


## Set a ring running out over the water from world point `at` (its height is
## not read), `strength` 0 to 1: a droplet falling back in a tenth or so, a wheel's
## wake a third to three quarters, a hard splash one. Nothing where there is no
## water. True if it was set.
func ripple(at: Vector3, strength: float) -> bool:
	if _mi == null or is_nan(world_level_at(at)):
		return false
	var o := global_position
	_rings.append(Vector4(at.x - o.x, at.z - o.z, _clock, clampf(strength, 0.05, 1.0)))
	_rolls.append(randi() % ROLLS)
	while _rings.size() > RIPPLES:
		var gone := _faintest()
		_rings.remove_at(gone)
		_rolls.remove_at(gone)
	_upload_rings()
	material.set_shader_parameter(&"ripple_now", _clock)
	return true


## The live rings, oldest first: Vector4(x, z in the field's frame, the clock
## it was made at, its strength).
func rings() -> Array[Vector4]:
	return _rings


## The rings' clock, seconds.
func clock() -> float:
	return _clock


## `WaterWakes`, or null with `wakes` off or no water.
func wake_node() -> WaterWakes:
	return _wakes


## Each live ring's roll, beside `rings()`.
func ring_rolls() -> PackedInt32Array:
	return _rolls


## Seconds a ring of `strength` runs, as the shader has it: a droplet's tenth
## under a second, a hard splash's whole `ring_life`.
func ring_life_of(strength: float) -> float:
	return _ring_param(&"ring_life", 2.2) * (0.3 + 0.7 * strength)


## Metres off a ring's middle its sub-ripples are thrown, at most, either way.
func ring_spread(strength: float) -> float:
	return 0.15 + 0.45 * strength


## How far out from where it was made a ring of `strength` ever reaches, metres,
## its crest's breadth and its sub-ripples included, as the shader has it.
func ring_reach(strength: float) -> float:
	return _ring_param(&"ring_speed", 4.0) * (0.15 + 1.15 * strength) * ring_life_of(strength) \
			+ 3.0 * _ring_param(&"ring_width", 0.32) * 2.0 + ring_spread(strength) * 1.5


# The live ring with least left to show: its strength times the square of the life
# it has left, as the shader fades it.
func _faintest() -> int:
	var best := 0
	var least := INF
	for i in _rings.size():
		var r := _rings[i]
		var u := clampf((_clock - r.z) / maxf(ring_life_of(r.w), 1e-3), 0.0, 1.0)
		var left := r.w * (1.0 - u) * (1.0 - u)
		if left < least:
			least = left
			best = i
	return best


func _ring_param(nm: StringName, fallback: float) -> float:
	var v: Variant = material.get_shader_parameter(nm) if material != null else null
	return float(v) if v != null else fallback


# The live rings into the shader's slots, packed from the first, and the box they
# all reach inside.
func _upload_rings() -> void:
	if material == null:
		return
	var slots := PackedVector4Array()
	slots.resize(RIPPLES)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in _rings.size():
		var r := _rings[i]
		# The strength and the roll in one: twice the roll, plus the strength (at
		# most 1), which the shader takes apart again.
		slots[i] = Vector4(r.x, r.y, r.z, 2.0 * float(_rolls[i]) + r.w)
		var reach := ring_reach(r.w)
		lo = Vector2(minf(lo.x, r.x - reach), minf(lo.y, r.y - reach))
		hi = Vector2(maxf(hi.x, r.x + reach), maxf(hi.y, r.y + reach))
	material.set_shader_parameter(&"ripples", slots)
	material.set_shader_parameter(&"ripple_count", _rings.size())
	material.set_shader_parameter(&"ripple_box",
			Vector4(lo.x, lo.y, hi.x, hi.y) if not _rings.is_empty() else Vector4.ZERO)


## The water's mesh, or null when the island's rivers are not water.
func mesh() -> ArrayMesh:
	return _mi.mesh as ArrayMesh if _mi != null else null


## Every river's surface: {"river": FlowTerrain.River, "levels": the water's
## height at each of its points, in the field's frame}.
func surfaces() -> Array:
	return _surfaces


## The lagoon's water height, in the field's frame (NAN with none).
func lagoon_level() -> float:
	return _lagoon_y


## The water's surface over a point of the field's frame, (x, z): its height in
## that frame, or NAN where there is no water over it. A river's is its level
## along the spline, out to its shore (and on under its banks by `under_bank`,
## where the surface runs on); the lagoon's is flat, out to `LAGOON_UNDER` past
## its shores. What the eye asks to know whether it is under (`UnderwaterView`).
func level_at(x: float, z: float) -> float:
	var q := Vector2(x, z)
	var best := INF
	var y := NAN
	var key := Vector2i(floori(x / LOOKUP_CELL), floori(z / LOOKUP_CELL))
	for e: Vector2i in _lookup.get(key, []):
		var sf: Dictionary = _surfaces[e.x]
		var r: FlowTerrain.River = sf["river"]
		var lv: PackedFloat32Array = sf["levels"]
		var i := e.y
		var n := r.points.size()
		# The segment on from this point (or the last's, back), and the share
		# along it, clamped: past an end the round end is a disc of its width.
		var j := mini(i + 1, n - 1)
		var a := r.points[i]
		var b := r.points[j]
		var ab := b - a
		var t := 0.0 if ab.length_squared() < 1e-6 else clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var w := lerpf(r.width[i], r.width[j], t) * (1.0 + under_bank)
		var d := q.distance_to(a + ab * t) / maxf(w, 0.01)
		if d <= 1.0 and d < best:
			best = d
			y = lerpf(lv[i], lv[j], t)
	if _flows != null and not is_nan(_lagoon_y) and _flows.lagoon_at(x, z).x > -LAGOON_UNDER:
		return _lagoon_y if is_nan(y) else maxf(y, _lagoon_y)
	return y


## `level_at` from the world's frame: a world point (x, z), the height back in
## the world's frame.
func world_level_at(p: Vector3) -> float:
	var o := global_position
	var y := level_at(p.x - o.x, p.z - o.z)
	return y + o.y if not is_nan(y) else NAN


## The mesh, in the field's frame: every river's sweep, in one surface.
func build_mesh(field: IslandField, hub: IslandField.Island, flows: FlowTerrain) -> ArrayMesh:
	_surfaces = []
	_flows = flows
	_lookup = {}
	var st := {
		"v": PackedVector3Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(),
		"col": PackedColorArray(), "tan": PackedFloat32Array(), "idx": PackedInt32Array(),
		"flow": PackedFloat32Array(),
	}
	for r: FlowTerrain.River in flows.rivers:
		var n := r.points.size()
		if n < 2:
			continue
		var levels := PackedFloat32Array()
		## [centre, tangent, half-width, level, s, ease, fade, cap, steep, flow time, pace]
		var rows: Array = []
		for i in range(n):
			var p := r.points[i]
			var tan := (r.points[mini(i + 1, n - 1)] - r.points[maxi(i - 1, 0)]).normalized()
			var level := hub.base_y + flows.water_level(field, hub, r, i) + lift
			levels.append(level)
			var ease := flows.shore_ease(field, hub, p)
			var fade := 1.0 if r.lake else smoothstep(0.0, source_fade, r.s[i])
			rows.append([p, tan, r.width[i], level, r.s[i], ease, fade, -1.0, 0.0, 0.0, 1.0])
		var steep := hill_steepness(r.s, levels)
		# WATER HAS WEIGHT. It does not take the speed of the slope under it at once:
		# it gathers way over `run_up` metres of a hill and carries it `run_out`
		# metres on into the flat below, so a rapid begins part way down its drop and
		# ends in a tongue of fast water past its foot. From here on `steep` is that:
		# how fast the water is going, 0 at a flat reach's pace to 1 flat out.
		var way := 0.0
		for i in range(n):
			if i > 0:
				var ds := r.s[i] - r.s[i - 1]
				way += (steep[i] - way) * (1.0 - exp(-ds / (run_up if steep[i] > way else run_out)))
			else:
				way = steep[0]
			steep[i] = way
		# WHERE A RIVER MEETS STILL WATER it slows into it: a pool at its toe, the
		# mere at its mouth, the lake it rises from. Its ripples hand over to the
		# still water's across `meet` metres instead of stopping at a line.
		var into_still := r.toe
		if flows.has_lagoon() and not into_still:
			var shores := flows.lagoon_shores(0.0)
			into_still = r.points[n - 1].distance_to(flows.lagoon_center()) < shores.y * 1.1
		var tau := 0.0
		for i in range(n):
			var run := 1.0
			if into_still:
				run *= smoothstep(0.0, meet, r.length - r.s[i])
			if r.lake:
				run *= smoothstep(0.0, meet, r.s[i])
			steep[i] *= run
			rows[i].append(run)
			var pace := 1.0 / (1.0 + (hill_speed - 1.0) * steep[i])
			if i > 0:
				tau += (r.s[i] - r.s[i - 1]) * 0.5 * (pace + float(rows[i - 1][10]))
			rows[i][8] = steep[i]
			rows[i][9] = tau
			rows[i][10] = pace
			_index(_surfaces.size(), i, r.points[i], r.width[i] * (1.0 + under_bank))
		# The round ends: a spring's, a lake's far shore and a pool's, never the
		# coast's, where the water goes on over the lip as the falls.
		var head: Array = []
		for k in range(CAP.size() - 1, -1, -1):
			var e: float = CAP[k] * r.width[0]
			var tan0 := (r.points[1] - r.points[0]).normalized()
			var row: Array = rows[0].duplicate()
			row[0] = r.points[0] - tan0 * e
			row[4] = -e
			row[7] = CAP[k]
			row[9] = float(rows[0][9]) - e * float(rows[0][10])
			head.append(row)
		rows = head + rows
		if r.toe:
			var tan1 := (r.points[n - 1] - r.points[n - 2]).normalized()
			var last: Array = rows[rows.size() - 1]
			for k in range(CAP.size()):
				var e: float = CAP[k] * r.width[n - 1]
				var row: Array = last.duplicate()
				row[0] = r.points[n - 1] + tan1 * e
				row[4] = r.length + e
				row[7] = CAP[k]
				row[9] = float(last[9]) + e * float(last[10])
				rows.append(row)
		_sweep(st, rows, r.moving, flows, field)
		_surfaces.append({"river": r, "levels": levels, "steep": steep})
	if flows.has_lagoon():
		_lagoon(st, field, hub, flows)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = st["v"]
	arrays[Mesh.ARRAY_TEX_UV] = st["uv"]
	arrays[Mesh.ARRAY_TEX_UV2] = st["uv2"]
	arrays[Mesh.ARRAY_COLOR] = st["col"]
	arrays[Mesh.ARRAY_TANGENT] = st["tan"]
	arrays[Mesh.ARRAY_CUSTOM0] = st["flow"]
	var normals := PackedVector3Array()
	normals.resize((st["v"] as PackedVector3Array).size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = st["idx"]
	var m := ArrayMesh.new()
	if not (st["v"] as PackedVector3Array).is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
				Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return m


## How steep a river is at each of its points, 0 flat to 1 flat out: the grade
## (the drop a metre, from its water `levels` at metres `s` down it) read over
## `grade_window`, from `grade_slack` to `grade_full`, and smoothed over the same.
func hill_steepness(s: PackedFloat32Array, levels: PackedFloat32Array) -> PackedFloat32Array:
	var n := s.size()
	var half := grade_window * 0.5
	var raw := PackedFloat32Array()
	raw.resize(n)
	var a := 0
	var b := 0
	for i in range(n):
		while s[a] < s[i] - half:
			a += 1
		while b + 1 < n and s[b + 1] <= s[i] + half:
			b += 1
		var ds := s[b] - s[a]
		var g := (levels[a] - levels[b]) / ds if ds > 0.01 else 0.0
		raw[i] = smoothstep(grade_slack, maxf(grade_full, grade_slack + 1e-3), g)
	var out := PackedFloat32Array()
	out.resize(n)
	a = 0
	b = 0
	var sum := 0.0
	for i in range(n):
		while b < n and s[b] <= s[i] + half:
			sum += raw[b]
			b += 1
		while s[a] < s[i] - half:
			sum -= raw[a]
			a += 1
		out[i] = clampf(sum / float(maxi(b - a, 1)), 0.0, 1.0)
	return out


# A river's point into `_lookup`, in every cell its disc of `reach` touches.
func _index(river: int, i: int, p: Vector2, reach: float) -> void:
	var c0 := Vector2i(floori((p.x - reach) / LOOKUP_CELL), floori((p.y - reach) / LOOKUP_CELL))
	var c1 := Vector2i(floori((p.x + reach) / LOOKUP_CELL), floori((p.y + reach) / LOOKUP_CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var key := Vector2i(cx, cz)
			if not _lookup.has(key):
				_lookup[key] = []
			(_lookup[key] as Array).append(Vector2i(river, i))


# One river's rows swept into the mesh: `ACROSS` vertices a row, a quad between
# each pair of rows. A cap row (`row[7]` >= 0, its distance past the end in
# half-widths) narrows to the round end's chord, and its depth is read by the
# distance from the end, as the channel's round end is carved. An edge vertex
# runs on under the bank only where there is a bank over it: where the ground
# past the shore falls away (a crater's breach), it stops at the shore, so no
# sheet of water hangs over the drop.
func _sweep(st: Dictionary, rows: Array, moving: bool, flows: FlowTerrain,
		field: IslandField) -> void:
	var v: PackedVector3Array = st["v"]
	var base := v.size()
	var cols := ACROSS.size()
	for row: Array in rows:
		var c: Vector2 = row[0]
		var tan: Vector2 = row[1]
		var w: float = maxf(row[2], 0.01)
		var cap: float = row[7]
		var left := Vector2(-tan.y, tan.x)
		var chord := 1.0 if cap < 0.0 else sqrt(maxf(1.0 - cap * cap, 0.0))
		for a: float in ACROSS:
			var d := a * w * chord * (1.0 + under_bank)
			var q := c + left * d
			if absf(a) >= 1.0 and field.height_at(q.x, q.y, -INF) < float(row[3]):
				d = a * w * chord
				q = c + left * d
			st["v"].append(Vector3(q.x, row[3], q.y))
			st["uv"].append(Vector2(row[4], d))
			var at := absf(d) / w if cap < 0.0 else Vector2(cap * w, d).length() / w
			var run: float = row[11] if row.size() > 11 else 1.0
			st["uv2"].append(Vector2(at, run if moving else float(row[8])))
			st["flow"].append_array(PackedFloat32Array([row[9], row[10], row[8], 0.0]))
			var depth := flows.water_depth(minf(at, 1.0), moving) * float(row[5]) if at < 1.0 else 0.0
			st["col"].append(Color(clampf(depth / 4.0, 0.0, 1.0),
					clampf(float(row[5]) * 3.0, 0.0, 1.0), float(row[6]), 1.0))
			st["tan"].append_array(PackedFloat32Array([tan.x, 0.0, tan.y, 1.0]))
	var idx: PackedInt32Array = st["idx"]
	for i in range(rows.size() - 1):
		for k in range(cols - 1):
			var a0 := base + i * cols + k
			var b0 := a0 + 1
			var a1 := a0 + cols
			var b1 := a1 + 1
			idx.append_array(PackedInt32Array([a0, a1, b0, b0, a1, b1]))
	st["idx"] = idx


# THE LAGOON (`FlowTerrain.has_lagoon`): a ring of water round the middle, from
# under the islet's beach to under the outer one, a row every `LAGOON_STEP` metres
# round. Still water (UV2.y 0); its depth by `FlowTerrain.lagoon_depth`, so it
# shelves to clear over the sand at both shores (UV2.x 1 there, as a river's
# shore, falling to 0 over `LAGOON_EDGE`). The ripples' frame runs round it, a whole number of their tiles to the
# lap, so it closes without a seam.
func _lagoon(st: Dictionary, field: IslandField, hub: IslandField.Island, flows: FlowTerrain) -> void:
	var c := flows.lagoon_center()
	var level := hub.base_y + flows.lagoon_level() + lift
	_lagoon_y = level
	var probe := flows.lagoon_shores(0.0)
	var r_mid := (probe.x + probe.y) * 0.5
	var n := maxi(int(ceil(TAU * probe.y / LAGOON_STEP)), 32)
	var mat_tile := 16.8
	if material != null:
		mat_tile = float(material.get_shader_parameter("ripple_scale")) \
				* float(material.get_shader_parameter("ripple_stretch"))
	var lap := maxf(round(TAU * r_mid / maxf(mat_tile, 0.1)), 1.0) * mat_tile
	var v: PackedVector3Array = st["v"]
	var base := v.size()
	var cols := LAGOON_ACROSS
	for i in range(n + 1):
		var th := TAU * float(i) / float(n)
		var sh := flows.lagoon_shores(th)
		var dir := Vector2.from_angle(th)
		var tan := Vector2(-dir.y, dir.x)
		for k in range(cols):
			var r := lerpf(sh.x - LAGOON_UNDER, sh.y + LAGOON_UNDER, float(k) / float(cols - 1))
			var q := c + dir * r
			if (k == 0 or k == cols - 1) and field.height_at(q.x, q.y, -INF) < level:
				r = sh.x if k == 0 else sh.y
				q = c + dir * r
			var into := minf(r - sh.x, sh.y - r)
			st["v"].append(Vector3(q.x, level, q.y))
			st["uv"].append(Vector2(lap * float(i) / float(n), r - r_mid))
			st["uv2"].append(Vector2(clampf(1.0 - into / LAGOON_EDGE, 0.0, 1.2), 0.0))
			st["col"].append(Color(clampf(flows.lagoon_depth(into) / 4.0, 0.0, 1.0), 1.0, 1.0, 1.0))
			st["tan"].append_array(PackedFloat32Array([tan.x, 0.0, tan.y, 1.0]))
			# Flat: its flow time is its metres, at a flat reach's pace.
			st["flow"].append_array(PackedFloat32Array([lap * float(i) / float(n), 1.0, 0.0, 0.0]))
	var idx: PackedInt32Array = st["idx"]
	for i in range(n):
		for k in range(cols - 1):
			var a0 := base + i * cols + k
			var b0 := a0 + 1
			var a1 := a0 + cols
			var b1 := a1 + 1
			idx.append_array(PackedInt32Array([a0, a1, b0, b0, a1, b1]))
	st["idx"] = idx
