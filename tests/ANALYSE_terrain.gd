extends SceneTree

# AN INSPECTION OF THE TERRAIN'S MESHES: every chunk of the island is meshed at
# every level the game keeps (64, 32, 16, 8 and 4 cells), and a sample of chunks
# at the two near levels (128 and 256), exactly as the game meshes them
# (ChunkMesher.build), and each is gone over for what a broken chunk looks like:
#
#   numbers     a position, normal or splat weight that is not a number, a normal
#               not of length one, weights below nothing or not adding to one
#   triangles   of no area; facing down (the ground's own, not its skirts)
#   spikes      an edge of the ground steeper than 80 degrees, inland
#   the field   a vertex not at the height the field gives for that place
#   seams       where two chunks at the SAME level meet: do their edges agree?
#   steps       where a chunk meets a COARSER neighbour: how far apart the two
#               edges stand (the skirt, `chunk_skirt_depth`, has to cover it)
#   levels      does a vertex at a finer level stand where the coarser has it?
#
#   godot --headless --path . --script res://tests/ANALYSE_terrain.gd
#
# Prints a summary and writes it, with the worst places, to
# renders/terrain_analysis.txt.

const SIZE := 128.0
const LEVELS := [64, 32, 16, 8, 4]
const NEAR := [128, 256]
const NEAR_SAMPLE := 14

var _field: IslandField
var _isl: IslandField.Island
var _base := Vector2.ZERO
var _pivot := Vector3.ZERO
var _n := 0
var _pool: Array = []
var _lock := Mutex.new()
var _jobs: Array = []          # [ci, cj, cells]
var _done := {}                # "ci,cj@cells" -> digest
var _report: PackedStringArray = []


func _say(line: String) -> void:
	print(line)
	_report.append(line)


func _take() -> IslandField:
	_lock.lock()
	var f: IslandField = _pool.pop_back() if not _pool.is_empty() else null
	_lock.unlock()
	return f if f != null else _field.clone()


func _give(f: IslandField) -> void:
	_lock.lock()
	_pool.append(f)
	_lock.unlock()


## One chunk meshed and gone over (on a worker): what was found, and its edges.
func _job(i: int) -> void:
	var job: Array = _jobs[i]
	var ci: int = job[0]
	var cj: int = job[1]
	var cells: int = job[2]
	var f := _take()
	var isl := f.island_in_cell(_isl.cell)
	var res := ChunkMesher.build(f, isl, _base.x, _base.y, ci, cj, SIZE, cells, _pivot)
	var out := {"empty": res.is_empty(), "ci": ci, "cj": cj, "cells": cells}
	if not res.is_empty():
		_inspect(f, res, out)
	_give(f)
	_lock.lock()
	_done["%d,%d@%d" % [ci, cj, cells]] = out
	_lock.unlock()


func _inspect(f: IslandField, res: Dictionary, out: Dictionary) -> void:
	var top: Array = res["top"]
	var v: PackedVector3Array = top[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = top[Mesh.ARRAY_NORMAL]
	var col: PackedColorArray = top[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = top[Mesh.ARRAY_INDEX]
	var coastal := not (res["cliff_bands"] as Array).is_empty()
	var x0 := _base.x + float(out["ci"]) * SIZE - _pivot.x
	var z0 := _base.y + float(out["cj"]) * SIZE - _pivot.z
	var step := SIZE / float(out["cells"])
	var bad_number := 0
	var bad_normal := 0
	var bad_weight := 0
	var ground := PackedByteArray()
	ground.resize(v.size())
	# The ground's own vertices: on the chunk's grid, looking up. (The skirts' look
	# straight out sideways; the rim's shoulder is off the grid or off the chunk.)
	var edges := [{}, {}, {}, {}]          # -x, +x, -z, +z: along (mm) -> height
	var grid := {}                         # Vector2i(grid) -> height, for the levels' check
	for k in v.size():
		var p := v[k]
		var n := nr[k]
		var c := col[k]
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z) and is_finite(n.x) and is_finite(n.y) and is_finite(n.z)
				and is_finite(c.r) and is_finite(c.g) and is_finite(c.b) and is_finite(c.a)):
			bad_number += 1
			continue
		if absf(n.length() - 1.0) > 0.02:
			bad_normal += 1
		if absf(n.y) < 1e-6:
			continue                        # a skirt's
		var gxf := (p.x - x0) / step
		var gzf := (p.z - z0) / step
		var on_grid := absf(gxf - roundf(gxf)) < 1e-3 and absf(gzf - roundf(gzf)) < 1e-3 \
				and gxf > -1e-3 and gzf > -1e-3 and gxf < float(out["cells"]) + 1e-3 and gzf < float(out["cells"]) + 1e-3
		if not on_grid:
			continue                        # the coast's own vertices, and the rim's
		ground[k] = 1
		var sum := c.r + c.g + c.b + c.a
		if minf(minf(c.r, c.g), minf(c.b, c.a)) < -0.001 or absf(sum - 1.0) > 0.03:
			bad_weight += 1
		var gi := int(roundf(gxf))
		var gj := int(roundf(gzf))
		grid[Vector2i(gi, gj)] = p.y
		if gi == 0:
			edges[0][gj] = p.y
		if gi == int(out["cells"]):
			edges[1][gj] = p.y
		if gj == 0:
			edges[2][gi] = p.y
		if gj == int(out["cells"]):
			edges[3][gi] = p.y
	# Triangles of the ground.
	var flat := 0
	var down := 0
	var spikes := 0
	var worst_spike := 0.0
	var worst_at := Vector3.ZERO
	var ground_tris := 0
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var b := idx[t + 1]
		var c2 := idx[t + 2]
		if ground[a] == 0 or ground[b] == 0 or ground[c2] == 0:
			continue
		ground_tris += 1
		var cross := (v[b] - v[a]).cross(v[c2] - v[a])
		if cross.length() < 1e-7:
			flat += 1
			continue
		# (Godot winds its faces clockwise: a face looking up has its cross down.)
		if cross.y > 0.0:
			down += 1
		if coastal:
			continue
		for e: Array in [[a, b], [b, c2], [c2, a]]:
			var dv := v[e[1]] - v[e[0]]
			var run := Vector2(dv.x, dv.z).length()
			if run > 1e-4:
				var steep := absf(dv.y) / run
				if steep > 5.67:
					spikes += 1
				if steep > worst_spike:
					worst_spike = steep
					worst_at = (v[e[0]] + v[e[1]]) * 0.5 + _pivot
	# Against the field, a vertex in sixteen.
	var off_field := 0
	var worst_off := 0.0
	var seen := 0
	for key: Vector2i in grid:
		if (key.x * 7 + key.y * 13) % 16 != 0:
			continue
		seen += 1
		var wx := x0 + _pivot.x + float(key.x) * step
		var wz := z0 + _pivot.z + float(key.y) * step
		var want := f.height_at(wx, wz, -1e9)
		if want < -1e8:
			continue
		var gap := absf(float(grid[key]) + _pivot.y - want)
		worst_off = maxf(worst_off, gap)
		if gap > 0.05:
			off_field += 1
	out.merge({"verts": v.size(), "tris": idx.size() / 3, "ground_tris": ground_tris, "coastal": coastal,
		"bad_number": bad_number, "bad_normal": bad_normal, "bad_weight": bad_weight, "flat": flat, "down": down,
		"spikes": spikes, "worst_spike": worst_spike, "worst_at": worst_at, "off_field": off_field,
		"worst_off": worst_off, "edges": edges, "grid": grid if int(out["cells"]) >= 64 else {}})


func _run(jobs: Array) -> void:
	_jobs = jobs
	var id := WorkerThreadPool.add_group_task(_job, jobs.size(), -1, false, "terrain analysis")
	WorkerThreadPool.wait_for_group_task_completion(id)


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	_field = load("res://data/ISLANDFIELD_forest_003_r2.tres")
	_field.prepare()
	_isl = _field.island_in_cell(_field.hub_cell())
	var extent := _field.island_extent(_isl)
	_base = _isl.center - Vector2(extent, extent)
	_pivot = Vector3(_isl.center.x, _isl.base_y, _isl.center.y)
	_n = maxi(1, ceili(extent * 2.0 / SIZE))
	_say("TERRAIN ANALYSIS: an island %.0f m across the radius, %d x %d chunks of %.0f m" % [_isl.radius, _n, _n, SIZE])
	# Which chunks hold land: all of them, at the coarsest level.
	var jobs: Array = []
	for cj in _n:
		for ci in _n:
			jobs.append([ci, cj, 4])
	_run(jobs)
	var land: Array = []
	for cj in _n:
		for ci in _n:
			if not bool(_done["%d,%d@4" % [ci, cj]]["empty"]):
				land.append(Vector2i(ci, cj))
	_say("  %d chunks hold land" % land.size())
	jobs = []
	for cells: int in LEVELS:
		if cells == 4:
			continue
		for c: Vector2i in land:
			jobs.append([c.x, c.y, cells])
	_run(jobs)
	# The near levels: the chunks with the steepest ground and a spread of others.
	var inland: Array = []
	for c: Vector2i in land:
		var d: Dictionary = _done["%d,%d@64" % [c.x, c.y]]
		if not bool(d.get("empty", true)) and not bool(d["coastal"]):
			inland.append([float(d["worst_spike"]), c])
	inland.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var picked: Array = []
	for i in mini(NEAR_SAMPLE / 2, inland.size()):
		picked.append(inland[i][1])
	var stride := maxi(1, inland.size() / (NEAR_SAMPLE - picked.size()))
	for i in range(0, inland.size(), stride):
		if not picked.has(inland[i][1]) and picked.size() < NEAR_SAMPLE:
			picked.append(inland[i][1])
	jobs = []
	for cells: int in NEAR:
		for c: Vector2i in picked:
			jobs.append([c.x, c.y, cells])
	_run(jobs)

	# ---------------------------------------------------------------- the findings
	var all_levels: Array = LEVELS.duplicate()
	all_levels.append_array(NEAR)
	all_levels.sort()
	all_levels.reverse()
	var trouble := 0
	for cells: int in all_levels:
		var chunks := 0
		var verts := 0
		var tris := 0
		var sums := {"bad_number": 0, "bad_normal": 0, "bad_weight": 0, "flat": 0, "down": 0, "spikes": 0, "off_field": 0}
		var worst_spike := 0.0
		var spike_at := Vector3.ZERO
		var worst_off := 0.0
		var off_chunk := Vector2i.ZERO
		var with_spikes := 0
		for key: String in _done:
			var d: Dictionary = _done[key]
			if int(d["cells"]) != cells or bool(d["empty"]):
				continue
			chunks += 1
			verts += int(d["verts"])
			tris += int(d["tris"])
			for s in sums:
				sums[s] = int(sums[s]) + int(d[s])
			if int(d["spikes"]) > 0:
				with_spikes += 1
			if float(d["worst_spike"]) > worst_spike:
				worst_spike = float(d["worst_spike"])
				spike_at = d["worst_at"]
			if float(d["worst_off"]) > worst_off:
				worst_off = float(d["worst_off"])
				off_chunk = Vector2i(int(d["ci"]), int(d["cj"]))
		_say("")
		_say("LEVEL %d cells (%.2f m between vertices): %d chunks, %d vertices, %d triangles%s" % [cells, SIZE / float(cells),
				chunks, verts, tris, "  (a sample)" if NEAR.has(cells) else ""])
		_say("  not numbers %d   normals not unit %d   splat weights wrong %d" % [sums["bad_number"], sums["bad_normal"], sums["bad_weight"]])
		_say("  triangles of no area %d   ground facing down %d" % [sums["flat"], sums["down"]])
		_say("  edges over 80 degrees, inland: %d in %d chunks; steepest %.0f degrees at (%.0f, %.0f, %.0f)" % [sums["spikes"], with_spikes,
				rad_to_deg(atan(worst_spike)), spike_at.x, spike_at.y, spike_at.z])
		_say("  vertices off the field's height by over 5 cm: %d; furthest %.3f m (chunk %s)" % [sums["off_field"], worst_off, off_chunk])
		trouble += int(sums["bad_number"]) + int(sums["bad_normal"]) + int(sums["bad_weight"]) + int(sums["flat"]) + int(sums["down"]) + int(sums["off_field"])
		# Seams with the neighbour at the same level, and steps down to the next coarser.
		var seam_worst := 0.0
		var seam_bad := 0
		var seam_pairs := 0
		var seam_at := ""
		var step_worst := 0.0
		var step_over := 0
		var step_pairs := 0
		var coarser := cells / 2
		for key: String in _done:
			var d: Dictionary = _done[key]
			if int(d["cells"]) != cells or bool(d["empty"]):
				continue
			for side: Array in [[1, 0, 1, 0], [0, 1, 3, 2]]:       # +x against its -x; +z against its -z
				var other_key := "%d,%d" % [int(d["ci"]) + int(side[0]), int(d["cj"]) + int(side[1])]
				var mine: Dictionary = (d["edges"] as Array)[int(side[2])]
				var same: Dictionary = _done.get("%s@%d" % [other_key, cells], {})
				if not same.is_empty() and not bool(same["empty"]):
					var theirs: Dictionary = (same["edges"] as Array)[int(side[3])]
					seam_pairs += 1
					for along in mine:
						if theirs.has(along):
							var gap := absf(float(mine[along]) - float(theirs[along]))
							if gap > seam_worst:
								seam_worst = gap
								seam_at = "%s | %s" % [key, other_key]
							if gap > 0.002:
								seam_bad += 1
				var coarse: Dictionary = _done.get("%s@%d" % [other_key, coarser], {})
				if coarser >= 4 and not coarse.is_empty() and not bool(coarse["empty"]) and not bool(d["coastal"]) and not bool(coarse["coastal"]):
					var theirs2: Dictionary = (coarse["edges"] as Array)[int(side[3])]
					step_pairs += 1
					for along in mine:
						var lo := int(along) / 2
						var hi := lo + (int(along) % 2)
						if theirs2.has(lo) and theirs2.has(hi):
							var gap2 := absf(float(mine[along]) - (float(theirs2[lo]) + float(theirs2[hi])) * 0.5)
							step_worst = maxf(step_worst, gap2)
							if gap2 > _field.chunk_skirt_depth:
								step_over += 1
		_say("  seams with a neighbour at the same level: %d pairs, %d vertices over 2 mm apart, widest %.4f m %s" % [seam_pairs, seam_bad,
				seam_worst, seam_at])
		if coarser >= 4:
			_say("  against a neighbour one level coarser: %d pairs, widest step %.2f m, %d over the %.1f m the skirt covers" % [step_pairs,
					step_worst, step_over, _field.chunk_skirt_depth])
		trouble += seam_bad + step_over
		# Does this level stand where the next coarser has it, vertex for vertex?
		if cells > 64 or cells == 64:
			var agree_worst := 0.0
			var agree_bad := 0
			var compared := 0
			for key: String in _done:
				var d: Dictionary = _done[key]
				if int(d["cells"]) != cells or bool(d["empty"]) or cells == 64:
					continue
				var base: Dictionary = _done.get("%d,%d@64" % [int(d["ci"]), int(d["cj"])], {})
				if base.is_empty() or bool(base["empty"]):
					continue
				var ratio := cells / 64
				var fine: Dictionary = d["grid"]
				for g: Vector2i in base["grid"]:
					var at := g * ratio
					if fine.has(at):
						compared += 1
						var gap := absf(float(fine[at]) - float(base["grid"][g]))
						agree_worst = maxf(agree_worst, gap)
						if gap > 0.005:
							agree_bad += 1
			if cells > 64:
				_say("  against the 64-cell level at the vertices they share: %d compared, %d over 5 mm apart, furthest %.4f m" % [compared,
						agree_bad, agree_worst])
				trouble += agree_bad
	_say("")
	_say("%s   (%.0f s)" % ["NOTHING BROKEN FOUND" if trouble == 0 else "%d FAULTS COUNTED, above" % trouble,
			float(Time.get_ticks_msec() - started) / 1000.0])
	var file := FileAccess.open("res://renders/terrain_analysis.txt", FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_report) + "\n")
	quit(0)
