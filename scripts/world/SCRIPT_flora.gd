class_name Flora
extends Node3D

# EVERYTHING THAT GROWS OR LIES ON THE ISLAND: firs, ferns, boulders and grass,
# placed from the same IslandField that shapes and paints the ground, and drawn
# as instanced meshes whose level of detail steps down with distance.
#
# HOW IT IS DRAWN. The island is cut into square tiles per layer. A tile near the
# camera owns one MultiMeshInstance3D per kind of plant in it, and as the camera
# moves the tile swaps that MultiMesh's mesh for a coarser or finer one: the
# instances are uploaded once and never re-packed. Near tiles are frustum-culled
# one by one. Trees are the only layer seen from across the island, so beyond the
# near tiles they are drawn as impostors merged into two island-wide MultiMeshes
# per kind (crossed planes, then camera-facing billboards) that are re-packed
# only when the camera crosses into another tile.
#
# HOW IT IS PLACED. Each layer has a `_place_*` function that turns one tile into
# instance buffers. It runs on the worker pool against a private clone of the
# field. Trees are placed for the whole island behind the loading cover; the
# other layers are placed as the camera comes near and kept.

@export var world_path: NodePath
## 0 low, 1 medium, 2 high: scales every draw and detail distance.
@export_range(0, 2) var quality := 1
## Scales how many plants there are.
@export_range(0.1, 2.0) var density := 1.0
@export var world_seed := 152

const FIRS := ["fir_small_a", "fir_small_b", "fir_medium_a", "fir_medium_b",
		"fir_tall_a", "fir_tall_b", "fir_giant_a", "fir_giant_b"]
const FERNS := ["fern_small_a", "fern_medium_a", "fern_medium_b", "fern_large_a"]
const BOULDERS := ["boulder_a", "boulder_b", "boulder_c", "boulder_d", "boulder_e"]
## The first of the boulder layer's fresh-dug kinds (the crash's debris): the same
## five shapes over again in pale, mossless stone.
const DEBRIS_KIND := 5

const STRIDE := 12          # floats per instance: a 3x4 transform
const STRIDE_CUSTOM := 16   # ... plus a custom vec4

var _world: Node
var _field: IslandField
var _extent := 1500.0
var _layers: Array[Dictionary] = []
var _pool: Array[IslandField] = []
var _pool_mutex := Mutex.new()
var _done: Array = []                  # finished tiles waiting for the main thread
var _done_mutex := Mutex.new()
var _prefill_group := -1
var _prefill_jobs: Array = []          # [layer index, tile]
var _prefill_count := 0
var _prefilled := false
var _near_mutex := Mutex.new()
var _near_done := {}                   # layer index -> a finished sorting (see _near_update)
var _near_tasks := {}                  # layer index -> its sorting's task
var _scale := 1.0
# The islet in the mere: wooded to its shore, with a clearing in the middle for the
# sword in the stone.
var _islet := Vector2.ZERO
var _islet_radius := 0.0
var _clearing := SwordStone.MEADOW
# The mere's surface (world metres) and how far from its middle it can reach.
var _mere_level := -1e9
var _mere_reach := 0.0
var _path_a := Vector2.ZERO      # the cobbled way over the causeway: its two ends and half its width
var _path_b := Vector2.ZERO
var _path_half := 0.0
var _wreck := Vector2.ZERO
var _crash: Variant = null       # the mere's FlowTerrain, for where the shuttle's skid is


func _ready() -> void:
	_world = get_node_or_null(world_path)
	if _world == null or not _world.has_method(&"get_field"):
		set_process(false)       # no island: a test borrowing the meshes and materials
		return
	_field = _world.call(&"get_field")
	if not _field._ready:
		_field.prepare()
	var isl: Variant = _field.island_in_cell(_field.hub_cell())
	if isl != null:
		_extent = float(_field.island_extent(isl)) + 40.0
	if OS.has_feature("mobile"):
		quality = 0
	_scale = [0.7, 1.0, 1.35][quality]
	_islet = SwordStone.site(_field)
	var flows: Variant = _field.flows_for(isl) if isl != null else null
	if flows != null and flows.has_lagoon():
		_mere_level = float(isl.base_y) + float(flows.lagoon_level())
		var ends: PackedVector2Array = flows.causeway_ends()
		_path_a = ends[0]
		_path_b = ends[1]
		_path_half = 2.9
		_mere_reach = float(_field.get("flow_lagoon_radius")) * 1.25
	_glade = Vector3.ZERO
	_crash = flows if (flows != null and flows.has_lagoon()) else null
	if _crash != null:
		_wreck = (_crash.crash_site() as PackedVector2Array)[0]
	if flows != null and flows.has_lagoon():
		var site: PackedVector2Array = flows.crash_site()
		if site[1] != Vector2.ZERO:
			var mid := site[0] + site[1] * GLADE_UP_SHORE
			_glade = Vector3(mid.x, mid.y, GLADE_REACH)
	_islet_radius = float(_field.get("flow_lagoon_islet")) * 0.86 if _field.get("flow_lagoon_islet") != null else 0.0
	_build_layers()


## Is a point on the cobbled way across the causeway (or within `spare` metres
## of it)? Nothing grows on the cobbles; the verges either side are green.
func _on_path(x: float, z: float, spare: float) -> bool:
	# (Nor in the shuttle's skid and divot: ploughed earth.)
	if _crash != null:
		var c: Vector2 = _crash.crash_weight(x, z)
		if c.x > 0.3 or c.y > 0.15:
			return true
	if _path_half <= 0.0:
		return false
	var ab := _path_b - _path_a
	var p := Vector2(x, z) - _path_a
	var t := clampf(p.dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (p - ab * t).length() < _path_half + spare


# ------------------------------------------------------------------ assets

static func _mesh_of(path: String) -> ArrayMesh:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("flora: cannot load " + path)
		return null
	var scene := packed.instantiate()
	var found: ArrayMesh = null
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		found = (n as MeshInstance3D).mesh as ArrayMesh
		break
	scene.free()
	return found


static func _shader_mat(shader: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


func _build_layers() -> void:
	var needles := _shader_mat("res://shaders/SHADER_foliage.gdshader", {
		"albedo_tex": load("res://assets/fir/textures/fir_branch_basecolor.png"),
		"tint": Color(0.62, 0.74, 0.62), "wind_bend": 0.55, "wind_flutter": 0.05,
		"backlight": Color(0.1, 0.14, 0.05)})
	# The mid LODs carry one picture of a whole bough per limb (tools/build_bough_atlas.py).
	var boughs := _shader_mat("res://shaders/SHADER_foliage.gdshader", {
		"albedo_tex": load("res://assets/fir/textures/fir_bough_atlas_basecolor.png"),
		"tint": Color(0.76, 0.84, 0.77), "wind_bend": 0.55, "wind_flutter": 0.03,
		"backlight": Color(0.1, 0.14, 0.05)})
	var bark := _shader_mat("res://shaders/SHADER_bark.gdshader", {
		"albedo_tex": load("res://assets/fir/textures/pine_bark_basecolor.jpg"),
		"normal_tex": load("res://assets/fir/textures/pine_bark_normal.jpg"),
		"orm_tex": load("res://assets/fir/textures/pine_bark_orm.jpg"), "wind_bend": 0.55})
	var frond := _shader_mat("res://shaders/SHADER_foliage.gdshader", {
		"albedo_tex": load("res://assets/fern/textures/fern_frond_basecolor.png"),
		"tint": Color(0.8, 0.9, 0.7), "alpha_cut": 0.4, "roughness": 0.65,
		"wind_bend": 0.07, "wind_flutter": 0.02, "backlight": Color(0.2, 0.26, 0.06)})

	# --- trees: three meshes near, crossed planes and billboards far
	var tree_kinds: Array[Dictionary] = []
	for fir in FIRS:
		var lods: Array = []
		# Six meshes (tools/build_fir.py): every frond a card at the first two, one
		# card to a limb from the third, fewer and wider after that.
		for i in 6:
			var m := _mesh_of("res://assets/fir/%s/%s_lod%d.gltf" % [fir, fir, i])
			m.surface_set_material(0, bark)
			m.surface_set_material(1, needles if i < 2 else boughs)
			lods.append(m)
		var atlas := "res://assets/fir/textures/impostors/%s_impostor_" % fir
		var cross := _mesh_of("res://assets/fir/%s/%s_lod6_cross.gltf" % [fir, fir])
		cross.surface_set_material(0, _shader_mat("res://shaders/SHADER_impostor.gdshader", {
			"albedo_tex": load(atlas + "basecolor.png"),
			"tint": Color(0.44, 0.57, 0.5)}))
		var board := _mesh_of("res://assets/fir/%s/%s_lod7_billboard.gltf" % [fir, fir])
		board.surface_set_material(0, _shader_mat("res://shaders/SHADER_impostor.gdshader", {
			"albedo_tex": load(atlas + "basecolor.png"),
			"tint": Color(0.44, 0.57, 0.5), "billboard": true}))
		# The trunk, to walk into: a post as thick as this fir's foot.
		var trunk := CylinderShape3D.new()
		trunk.radius = [0.13, 0.17, 0.26, 0.30, 0.42, 0.46, 0.62, 0.70][FIRS.find(fir)] * 1.2
		trunk.height = 8.0
		tree_kinds.append({"lods": lods, "cross": cross, "board": board, "shape": trunk, "shape_lift": 4.0})
	_layers.append({
		# EIGHT LEVELS: the six meshes hand over at these distances, then the
		# crossed cards from `radius`, then the flat boards from `cross_reach`.
		# Only the nearest four cast shadows.
		"name": "trees", "tile": 32.0, "radius": 140.0 * _scale, "stride": STRIDE,
		"dists": [9.0 * _scale, 18.0 * _scale, 32.0 * _scale, 55.0 * _scale, 90.0 * _scale],
		"shadow_lods": 4 if quality > 0 else 3,
		"kinds": tree_kinds, "place": _place_trees, "prefill": true,
		"cross_reach": 480.0 * _scale, "height": 50.0, "collide": true,
		# Each tree picks its own level (see _near_update): not a tile at a time.
		"near_field": true,
	})

	# --- ferns: three meshes, then their own impostors, then nothing
	var fern_kinds: Array[Dictionary] = []
	for fern in FERNS:
		var lods: Array = []
		for i in 3:
			var m := _mesh_of("res://assets/fern/%s/%s_lod%d.gltf" % [fern, fern, i])
			m.surface_set_material(0, frond)
			lods.append(m)
		var atlas := "res://assets/fern/textures/impostors/%s_impostor_" % fern
		var cross := _mesh_of("res://assets/fern/%s/%s_lod3_cross.gltf" % [fern, fern])
		cross.surface_set_material(0, _shader_mat("res://shaders/SHADER_impostor.gdshader", {
			"albedo_tex": load(atlas + "basecolor.png"),
			"tint": Color(0.85, 0.95, 0.75)}))
		lods.append(cross)
		fern_kinds.append({"lods": lods})
	_layers.append({
		"name": "ferns", "tile": 20.0, "radius": 95.0 * _scale, "stride": STRIDE,
		"dists": [9.0 * _scale, 24.0 * _scale, 50.0 * _scale], "shadow_lods": 1,
		"kinds": fern_kinds, "prefill": true, "place": _place_ferns, "height": 2.0, "near_field": true,
	})

	# (No plain bushes: the only bushes are the berry bushes, SCRIPT_berry_bushes.gd.)

	# --- seaweed, under the mere
	var weed := _shader_mat("res://shaders/SHADER_foliage.gdshader", {
		"albedo_tex": load("res://assets/seaweed/textures/seaweed_atlas_basecolor.png"),
		"tint": Color(0.4, 0.5, 0.26), "alpha_cut": 0.4, "roughness": 0.22, "specular": 0.45,
		"wind_bend": 1.5, "wind_flutter": 0.08, "atlas_columns": 2.0, "push_bend": 0.45,
		"backlight": Color(0.1, 0.16, 0.04)})
	_layers.append({
		"name": "seaweed", "tile": 24.0, "radius": 120.0 * _scale, "stride": STRIDE_CUSTOM,
		"dists": [30.0 * _scale], "shadow_lods": 0,
		"kinds": [{"lods": [_seaweed_mesh(weed, 6), _seaweed_mesh(weed, 3)]}],
		"prefill": true, "place": _place_seaweed, "height": 8.0,
	})

	# --- boulders
	var rock: Material = load("res://materials/MAT_boulder.tres")
	var boulder_kinds: Array[Dictionary] = []
	for b in BOULDERS:
		# Every level the simplifier makes from the finest of the boulder's own
		# (MeshLods): eight or so, each held only as near as it is worth.
		var lod0 := _mesh_of("res://assets/boulder/%s/%s_lod0.gltf" % [b, b])
		lod0.surface_set_material(0, rock)
		var lods: Array = MeshLods.chain(lod0, 12)
		boulder_kinds.append({"lods": lods, "shape": (lods[mini(4, lods.size() - 1)] as ArrayMesh).create_convex_shape(true, true),
				"shape_lift": 0.0})
	# AND THE SAME FIVE AGAIN AS FRESH-DUG ROCK (kinds DEBRIS_KIND and up): what
	# the shuttle tore out of the ground coming down. Never weathered and never
	# grown over: pale, clean stone, no moss, its broken faces still bright.
	var dug := (rock as ShaderMaterial).duplicate() as ShaderMaterial
	dug.set_shader_parameter("moss_amount", 0.0)
	dug.set_shader_parameter("rock_tint", Color(2.15, 1.95, 1.65))
	dug.set_shader_parameter("macro_variation", 0.25)
	dug.set_shader_parameter("ground_occlusion_height", 0.2)
	for i in BOULDERS.size():
		var fresh: Array = []
		for m: ArrayMesh in boulder_kinds[i]["lods"]:
			var copy := m.duplicate() as ArrayMesh
			copy.surface_set_material(0, dug)
			fresh.append(copy)
		boulder_kinds.append({"lods": fresh, "shape": boulder_kinds[i]["shape"], "shape_lift": 0.0})
	var steps: Array = []
	for d in MeshLods.distances(mini(8, (boulder_kinds[0]["lods"] as Array).size()), 3.0, 1.6):
		steps.append(float(d) * _scale)
	_layers.append({
		# (Past `radius` the bigger boulders are still drawn, island-wide, at their
		# simplest: `_far_rocks`. Rocks never go.)
		"name": "boulders", "tile": 32.0, "radius": maxf(380.0 * _scale, float(steps.back()) * 1.2), "stride": STRIDE,
		"dists": steps, "shadow_lods": 2,
		"kinds": boulder_kinds, "prefill": true, "place": _place_boulders, "height": 8.0, "collide": true,
		"near_field": true,
	})

	# --- grass: crossed quads cut from the clump photos, one atlas, one draw per tile
	var reach := 62.0 * _scale
	var blades := _shader_mat("res://shaders/SHADER_foliage.gdshader", {
		"albedo_tex": load("res://assets/grass/textures/grass_atlas_basecolor.png"),
		# (Three-quarters of the way to the green of the meadow ground it stands in,
		# leafy_grass as the terrain draws it: the blades also take light through
		# their leaves, which the ground does not.)
		"tint": Color(0.78, 0.88, 0.64), "alpha_cut": 0.36, "roughness": 0.7,
		"wind_bend": 0.16, "wind_flutter": 0.04, "atlas_columns": 3.0, "push_bend": 0.3,
		"backlight": Color(0.035, 0.05, 0.015), "specular": 0.04, "thin_start": reach * 0.2, "thin_end": reach * 0.7, "thin_keep": 0.3,
		"fade_start": reach * 0.72, "fade_end": reach * 0.98})
	_blades = blades
	_layers.append({
		"name": "grass", "tile": 10.0, "radius": reach, "stride": STRIDE_CUSTOM,
		"dists": [], "shadow_lods": 0,
		"kinds": [{"lods": [_grass_mesh(blades)]}], "prefetch": 70.0, "place": _place_grass, "height": 1.5,
		# (Kept packed small, and opened out when a tile is drawn: `_pack_grass`.)
		"packed": true,
	})

	for layer in _layers:
		layer["tiles"] = {}          # Vector2i -> {bufs, lods: {level: [mmi per kind]}}
		layer["cache"] = {}          # Vector2i -> bufs, kept once placed
		layer["asked"] = {}
		layer["cam_tile"] = Vector2i(1 << 30, 0)
		# As built, so the graphics menu can scale them (see apply_view).
		layer["radius0"] = layer["radius"]
		layer["dists0"] = (layer["dists"] as Array).duplicate()
		layer["shadow_lods0"] = layer["shadow_lods"]
		if layer.has("cross_reach"):
			layer["cross0"] = layer["cross_reach"]
		var holder := Node3D.new()
		holder.name = String(layer["name"]).capitalize()
		add_child(holder)
		layer["holder"] = holder
		if layer.has("cross_reach"):
			layer["far"] = _far_instances(layer, holder)


var _blades: ShaderMaterial


## THE GRAPHICS MENU'S HAND ON THE PLANTS. Each is a multiple of what the layers
## were built with: `veg` how far the plant meshes are drawn, `lod` how far each
## level of detail is held before the next takes over, `impostor` how far the
## trees' crossed cards reach before the flat boards, `grass` how far the grass
## runs. `grass_keep` is the share of grass clumps drawn; `shadows` whether
## plants cast any. Everything open is closed and reopened to the new distances.
func apply_view(veg: float, lod: float, impostor: float, grass: float, grass_keep: float, shadows: bool) -> void:
	for layer in _layers:
		var radius0 := float(layer["radius0"])
		if String(layer["name"]) == "grass":
			var reach := radius0 * grass
			layer["radius"] = reach
			if _blades != null:
				_blades.set_shader_parameter("thin_start", reach * 0.2)
				_blades.set_shader_parameter("thin_end", reach * 0.7)
				_blades.set_shader_parameter("fade_start", reach * 0.72)
				_blades.set_shader_parameter("fade_end", reach * 0.98)
				_blades.set_shader_parameter("keep_share", grass_keep)
		else:
			var dists: Array = []
			for d in layer["dists0"]:
				dists.append(float(d) * lod)
			# The last hand-over has to fall inside what is drawn at all.
			var radius := radius0 * veg
			if not dists.is_empty():
				radius = maxf(radius, float(dists[-1]) * 1.15)
			layer["dists"] = dists
			layer["radius"] = radius
			if layer.has("cross0"):
				layer["cross_reach"] = maxf(float(layer["cross0"]) * impostor, radius * 1.3)
		layer["shadow_lods"] = int(layer["shadow_lods0"]) if shadows else 0
		layer["rebin"] = true
		var tiles: Dictionary = layer["tiles"]
		for key in tiles:
			var held: Dictionary = tiles[key]["lods"]
			for level in held:
				_close_level(held[level])
			held.clear()
		if layer.has("far"):
			var mms: Dictionary = layer["far"]["mms"]
			for slot in mms:
				var mmi: MultiMeshInstance3D = mms[slot]
				var cross_reach := float(layer["cross_reach"])
				mmi.set_instance_shader_parameter(&"lod_in", cross_reach if slot.z % 2 == 1 else float(layer["radius"]))
				mmi.set_instance_shader_parameter(&"lod_out", 0.0 if slot.z % 2 == 1 else cross_reach)
		layer["cam_tile"] = Vector2i(1 << 30, 0)


## Two quads crossed at right angles, a metre tall and a metre wide, rooted at the
## origin, with one upward normal. The foliage shader draws both faces of each.
static func _grass_mesh(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := PI * 0.5 * k + 0.3
		var dx := Vector3(cos(a), 0, sin(a)) * 0.5
		var corners := [[-dx, Vector2(0.001, 1)], [dx, Vector2(0.999, 1)],
				[dx + Vector3.UP, Vector2(0.999, 0)], [-dx + Vector3.UP, Vector2(0.001, 0)]]
		for order in [[0, 1, 2, 0, 2, 3]]:
			for i in order:
				var uv: Vector2 = corners[i][1]
				st.set_normal(Vector3(0, 1, 0))
				st.set_uv(uv)
				st.set_uv2(Vector2(1.0 - uv.y, 0.0))
				st.set_color(Color.WHITE * (0.6 + 0.4 * (1.0 - uv.y)))
				st.add_vertex(corners[i][0])
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


## A frond of seaweed a metre tall and half a metre across, rooted at the origin:
## two crossed cards, cut into bands up their height so they can sway.
static func _seaweed_mesh(mat: Material, bands: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := PI * 0.5 * float(k) + 0.4
		var ax := Vector3(cos(a), 0, sin(a)) * 0.25
		for i in bands:
			var y0 := float(i) / float(bands)
			var y1 := float(i + 1) / float(bands)
			# The frond arcs over as it rises (the current has leaned it), so it is not a post.
			var b0 := Vector3(0.34 * y0 * y0, 0.0, 0.1 * sin(y0 * 4.0))
			var b1 := Vector3(0.34 * y1 * y1, 0.0, 0.1 * sin(y1 * 4.0))
			var c := [[-ax + Vector3.UP * y0 + b0, Vector2(0.001, 1.0 - y0)], [ax + Vector3.UP * y0 + b0, Vector2(0.999, 1.0 - y0)],
					[ax + Vector3.UP * y1 + b1, Vector2(0.999, 1.0 - y1)], [-ax + Vector3.UP * y1 + b1, Vector2(0.001, 1.0 - y1)]]
			for j in [0, 1, 2, 0, 2, 3]:
				var pos: Vector3 = c[j][0]
				st.set_normal(Vector3(0, 1, 0))
				st.set_uv(c[j][1])
				st.set_uv2(Vector2(clampf(pos.y, 0.0, 1.0) * clampf(pos.y, 0.0, 1.0), 0.0))        # the tip swings, the root holds
				st.set_color(Color.WHITE * (0.6 + 0.4 * pos.y))
				st.add_vertex(pos)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


## UNDER THE MERE: where the seaweed and the sunken rocks gather. Clumps sit on a
## lattice (nearly every cell has one, and they run into each other: the bed is
## more weed than not), each with its own middle, reach and vigour.
## Returns (metres from the nearest clump's middle, that clump's reach, its vigour
## 0..1), or a reach of 0 where there is none near.
static func clump_at(x: float, z: float) -> Vector3:
	var cell := 17.0
	var cx := int(floor(x / cell))
	var cz := int(floor(z / cell))
	var best := Vector3(1e9, 0.0, 0.0)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ix := cx + dx
			var iz := cz + dz
			if _hash(ix, iz, 101) > 0.9:
				continue
			var mid := Vector2((float(ix) + 0.15 + 0.7 * _hash(ix, iz, 102)) * cell, (float(iz) + 0.15 + 0.7 * _hash(ix, iz, 103)) * cell)
			var d := mid.distance_to(Vector2(x, z))
			if d < best.x:
				best = Vector3(d, 5.0 + 8.5 * _hash(ix, iz, 104), 0.4 + 0.6 * _hash(ix, iz, 105))
	return best


func _far_instances(_layer: Dictionary, holder: Node3D) -> Dictionary:
	# Filled by `_repack_far`: one MultiMesh per (kind, impostor, FAR_CELL square of
	# island), each with that square's bounds, so the far forest is frustum- and
	# occlusion-culled square by square instead of being one island-wide draw.
	return {"holder": holder, "mms": {}}


# ------------------------------------------------------------------ placement
# These run on worker threads. `f` is a private clone of the field.

static func _hash(x: int, z: int, salt: int) -> float:
	var h := (x * 73856093) ^ (z * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)


static func _smooth_noise(x: float, z: float, salt: int) -> float:
	var ix := int(floor(x))
	var iz := int(floor(z))
	var fx := x - float(ix)
	var fz := z - float(iz)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	return lerpf(lerpf(_hash(ix, iz, salt), _hash(ix + 1, iz, salt), fx),
			lerpf(_hash(ix, iz + 1, salt), _hash(ix + 1, iz + 1, salt), fx), fz)


# THE SAME NOISE, IN 32 BITS, so the terrain shader can work out exactly the same
# thing (SHADER_terrain.gdshader's `wood_zones`): GDScript's ints are 64-bit and a
# shader's 32, so every product is cut to 32 bits as a shader's would be.
static func _hash32(x: int, z: int, salt: int) -> float:
	const M := 0xFFFFFFFF
	var h := (((x & M) * 73856093) & M) ^ (((z & M) * 19349663) & M) ^ (((salt & M) * 83492791) & M)
	h = ((h ^ (h >> 13)) * 1274126177) & M
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)


static func _noise32(x: float, z: float, salt: int) -> float:
	var ix := int(floor(x))
	var iz := int(floor(z))
	var fx := x - float(ix)
	var fz := z - float(iz)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	return lerpf(lerpf(_hash32(ix, iz, salt), _hash32(ix + 1, iz, salt), fx),
			lerpf(_hash32(ix, iz + 1, salt), _hash32(ix + 1, iz + 1, salt), fx), fz)


## THE WOOD'S OWN PLACES, each 0..1 (only in the wood: see `_wood`): x, a DRIFT OF
## FERNS, thick, knee-deep, no grass under it; y, a CLEARING, bare leafy floor,
## nothing growing. The terrain shader paints the clearings' floor from this same
## arithmetic, so the bare ground is exactly where nothing grows.
static func wood_zones(x: float, z: float) -> Vector2:
	var fern := smoothstep(0.56, 0.68, _noise32(x / 38.0, z / 38.0, 81) * 0.7 + _noise32(x / 13.0, z / 13.0, 83) * 0.3)
	var clear := smoothstep(0.69, 0.77, _noise32(x / 30.0, z / 30.0, 82) * 0.75 + _noise32(x / 9.0, z / 9.0, 84) * 0.25)
	return Vector2(fern * (1.0 - clear), clear)


## How much a point is in the wood (the field's forest), as the shader takes it.
static func _wood(forest: float) -> float:
	return smoothstep(0.15, 0.6, forest)


## MEADOWS: open ground among the trees, a few hundred metres across, where the
## forest stops and the grass grows thick. 0 in the wood, 1 well inside a meadow.
static func meadow(x: float, z: float) -> float:
	var n := _smooth_noise(x / 210.0, z / 210.0, 71) * 0.7 + _smooth_noise(x / 70.0, z / 70.0, 72) * 0.3
	var open := smoothstep(0.56, 0.66, n)
	if _glade.z > 0.0:
		# The one meadow that is put there: its edge ragged like the others'.
		var far := Vector2(x - _glade.x, z - _glade.y).length() + (_smooth_noise(x / 16.0, z / 16.0, 73) - 0.5) * 16.0
		open = maxf(open, 1.0 - smoothstep(_glade.z * 0.72, _glade.z, far))
	return open


## THE MEADOW BY THE WRECK: the first open ground you come to up the shore from
## where the shuttle went in, so there are cows to be found at once. (x, z, its
## reach in metres); a reach of 0 when there is none.
const GLADE_UP_SHORE := FlowTerrain.MEADOW_UP
const GLADE_REACH := 60.0
static var _glade := Vector3.ZERO


static func glade() -> Vector3:
	return _glade


static func _push(buf: PackedFloat32Array, basis: Basis, at: Vector3) -> void:
	buf.append_array([basis.x.x, basis.y.x, basis.z.x, at.x, basis.x.y, basis.y.y, basis.z.y, at.y,
			basis.x.z, basis.y.z, basis.z.z, at.z])


func _blank(layer: Dictionary) -> Array:
	var bufs: Array = []
	for i in (layer["kinds"] as Array).size():
		bufs.append(PackedFloat32Array())
	return bufs


func _place_trees(f: IslandField, layer: Dictionary, key: Vector2i) -> Array:
	var bufs := _blank(layer)
	var grid := 14.0
	var tile := float(layer["tile"])
	# A stand is of an age: each tile draws from two kinds, chosen by a slow hash,
	# so sizes drift across the island instead of being shuffled tree by tree.
	var stand := _hash(key.x >> 1, key.y >> 1, 11)
	var first := clampi(int(stand * 4.0), 0, 3) * 2
	var pair := [first + (key.x & 1), mini(7, first + 2 + (key.y & 1)) if _hash(key.x, key.y, 12) > 0.6 else first + ((key.x + 1) & 1)]
	var x0 := float(key.x) * tile
	var z0 := float(key.y) * tile
	var c0x := int(floor(x0 / grid))
	var c0z := int(floor(z0 / grid))
	for cz in range(c0z, int(floor((z0 + tile) / grid)) + 1):
		for cx in range(c0x, int(floor((x0 + tile) / grid)) + 1):
			var x := (float(cx) + 0.15 + 0.7 * _hash(cx, cz, 1)) * grid
			var z := (float(cz) + 0.15 + 0.7 * _hash(cx, cz, 2)) * grid
			if x < x0 or x >= x0 + tile or z < z0 or z >= z0 + tile:
				continue
			if _on_path(x, z, 1.3):
				continue
			var s := f.sample(x, z)
			if not bool(s.get("on_land", false)):
				continue
			var surface := String(s.get("surface", ""))
			var from_stone := Vector2(x, z).distance_to(_islet)
			var want := lerpf(0.16, 0.9, float(s.get("forest", 0.0))) * density
			if from_stone < _islet_radius:
				# The islet is deep wood whatever the field makes of its ground.
				if from_stone < _clearing:
					continue
				want = 0.95 * density
			elif surface == "rock" or surface == "sand" or float(s.get("flatten", 0.0)) > 0.3 \
					or float(s.get("flow_weight", 0.0)) > 0.3:
				continue
			if float(s.get("slope", 0.0)) > STEEP or CliffRocks.covers(x, z, 1.5):
				continue
			# (And not out by the island's edge: EDGE.)
			if float(s.get("mask", 1.0)) < EDGE * (0.85 + 0.5 * _hash(cx, cz, 9)):
				continue
			# Meadows are open: the wood thins at their edge and stops inside.
			if from_stone >= _islet_radius and _hash(cx, cz, 8) < meadow(x, z) * 1.15:
				continue
			if _hash(cx, cz, 3) > want:
				continue
			var kind: int = pair[0] if _hash(cx, cz, 4) < 0.65 else pair[1]
			var size := 0.85 + 0.3 * _hash(cx, cz, 5)
			var basis := Basis(Vector3.UP, _hash(cx, cz, 6) * TAU)
			basis = Basis(Vector3(1, 0, 0), (_hash(cx, cz, 7) - 0.5) * 0.07) * basis
			_push(bufs[kind], basis.scaled(Vector3.ONE * size), Vector3(x, float(s["height"]) - 0.25, z))
	return bufs


func _place_ferns(f: IslandField, layer: Dictionary, key: Vector2i) -> Array:
	var bufs := _blank(layer)
	var grid := 2.4
	var tile := float(layer["tile"])
	var x0 := float(key.x) * tile
	var z0 := float(key.y) * tile
	var kinds := [int(_hash(key.x, key.y, 21) * 4.0) % 4, int(_hash(key.x, key.y, 22) * 3.0) % 3]
	var n := int(round(tile / grid))
	for iz in n:
		for ix in n:
			var cx := key.x * n + ix
			var cz := key.y * n + iz
			# Ferns come in drifts: a slow hash decides where they are thick.
			var drift := _hash(cx >> 2, cz >> 2, 23) * 0.6 + _hash(cx >> 4, cz >> 4, 24) * 0.4
			var x := x0 + (float(ix) + _hash(cx, cz, 26)) * grid
			var z := z0 + (float(iz) + _hash(cx, cz, 27)) * grid
			# The wood's drifts of ferns are thick; its clearings bare.
			var zones := wood_zones(x, z)
			if zones.y > 0.35:
				continue
			if _hash(cx, cz, 25) > maxf((drift - 0.28) * 1.5, zones.x * 1.4) * density:
				continue
			# A few ferns stray into the meadow's edge; none in its middle.
			if Vector2(x, z).distance_to(_islet) < _clearing * (0.55 + 0.45 * _hash(cx, cz, 32)):
				continue
			if _on_path(x, z, 1.3):
				continue
			var s := f.sample(x, z)
			if not bool(s.get("on_land", false)):
				continue
			var surface := String(s.get("surface", ""))
			if surface == "rock" or surface == "sand":
				continue
			# (None on a cliff's face, ROCK_FACE, nor in a cliff's rock.)
			if float(s.get("slope", 0.0)) > STEEP or CliffRocks.covers(x, z, 0.4) \
					or float(s.get("mask", 1.0)) < EDGE * (0.8 + 0.5 * _hash(cx, cz, 37)) \
					or float(s.get("flow_weight", 0.0)) > 0.4 \
					or float(s.get("flatten", 0.0)) > 0.25:
				continue
			if _hash(cx, cz, 28) > 0.3 + 0.7 * float(s.get("forest", 0.0)):
				continue
			var kind: int = kinds[0] if _hash(cx, cz, 29) < 0.6 else kinds[1]
			var size := 0.75 + 0.6 * _hash(cx, cz, 30)
			var basis := Basis(Vector3.UP, _hash(cx, cz, 31) * TAU).scaled(Vector3.ONE * size)
			_push(bufs[kind], basis, Vector3(x, float(s["height"]) - 0.03, z))
			# In a drift, they crowd: a second fern beside the first.
			var wood := _wood(float(s.get("forest", 0.0)))
			if zones.x * wood > 0.5 and _hash(cx, cz, 33) < zones.x:
				var x2 := x + grid * (_hash(cx, cz, 34) - 0.5)
				var z2 := z + grid * 0.5
				var size2 := 0.85 + 0.6 * _hash(cx, cz, 35)
				_push(bufs[kind], Basis(Vector3.UP, _hash(cx, cz, 36) * TAU).scaled(Vector3.ONE * size2),
						Vector3(x2, f.height_at(x2, z2, float(s["height"])) - 0.03, z2))
	return bufs



func _place_seaweed(f: IslandField, layer: Dictionary, key: Vector2i) -> Array:
	var buf := PackedFloat32Array()
	if _mere_reach <= 0.0:
		return [buf]
	var grid := 0.5
	var tile := float(layer["tile"])
	var x0 := float(key.x) * tile
	var z0 := float(key.y) * tile
	if Vector2(x0 + tile * 0.5, z0 + tile * 0.5).distance_to(_islet) > _mere_reach + tile:
		return [buf]
	var n := int(round(tile / grid))
	for iz in n:
		for ix in n:
			var cx := key.x * n + ix
			var cz := key.y * n + iz
			var x := x0 + (float(ix) + _hash(cx, cz, 111)) * grid
			var z := z0 + (float(iz) + _hash(cx, cz, 112)) * grid
			var c := clump_at(x, z)
			# Thick in the middle of a clump, thinning toward its edge; and the fronds
			# themselves shorten the same way, tall at the heart, small outside. Between
			# the clumps the bed is not bare: short weed, thinly, everywhere.
			var inward := maxf(1.0 - c.x / c.y, 0.0) if c.y > 0.0 else 0.0
			var rich := c.z
			var stand := false           # one of the wreck's own stands of weed
			# ROUND THE WRECK THE WEED IS THICK: besides the bed's own clumps, a
			# stand of it in most of the 9 m squares within WRECK_WEED of the
			# shuttle, each a few metres across, tall at its heart.
			if _crash != null:
				var from_wreck := Vector2(x, z).distance_to(_wreck)
				if from_wreck < WRECK_WEED:
					var sx := int(floor(x / 9.0))
					var sz := int(floor(z / 9.0))
					for oz in range(-1, 2):
						for ox in range(-1, 2):
							if _hash(sx + ox, sz + oz, 131) > 0.72:
								continue
							var mid := Vector2((float(sx + ox) + 0.2 + 0.6 * _hash(sx + ox, sz + oz, 132)) * 9.0,
									(float(sz + oz) + 0.2 + 0.6 * _hash(sx + ox, sz + oz, 133)) * 9.0)
							var reach := 2.6 + 3.4 * _hash(sx + ox, sz + oz, 134)
							var into := 1.0 - Vector2(x, z).distance_to(mid) / reach
							# (Thinning out toward the edge of the wreck's ground.)
							into *= 1.0 - smoothstep(WRECK_WEED * 0.7, WRECK_WEED, from_wreck)
							if into > inward * rich:
								inward = into
								rich = 1.0
								stand = true
			if _hash(cx, cz, 113) > inward * (0.35 + inward) * 1.25 * rich * density + 0.07 * density:
				continue
			# THE SHUTTLE WENT THROUGH IT: none in its trench or on the berms, and
			# out from there what is left is thin, short and torn, back to whole
			# weed a few widths off.
			var swept := 1.0
			if _crash != null:
				var off: float = _crash.crash_swath(x, z)
				if off < 1.9:
					continue
				# (The stands that have grown up round the wreck since are whole.)
				swept = 1.0 if stand else smoothstep(1.9, 4.5, off)
				if _hash(cx, cz, 121) > 0.15 + 0.85 * swept:
					continue
			var ground := f.height_at(x, z, 1e9)
			var depth := _mere_level - ground
			if depth < 1.1:
				continue
			var tall := (0.6 + 4.6 * inward * rich) * (0.7 + 0.6 * _hash(cx, cz, 114)) * lerpf(0.3, 1.0, swept)
			tall = minf(tall, depth * 0.92)
			var wide := tall * (0.55 + 0.35 * _hash(cx, cz, 115)) * 2.0 * 0.5
			var basis := Basis(Vector3.UP, _hash(cx, cz, 116) * TAU)
			basis = Basis(Vector3(1, 0, 0), (_hash(cx, cz, 117) - 0.5) * 0.7) * Basis(Vector3(0, 0, 1), (_hash(cx, cz, 120) - 0.5) * 0.7) * basis
			_push(buf, basis.scaled_local(Vector3(wide, tall, wide)), Vector3(x, ground - 0.05, z))
			buf.append_array([float(int(_hash(cx, cz, 118) * 2.0) % 2), _hash(cx, cz, 119), 1.0, 0.0])
	return [buf]


func _place_boulders(f: IslandField, layer: Dictionary, key: Vector2i) -> Array:
	var bufs := _blank(layer)
	var grid := 16.0
	var tile := float(layer["tile"])
	var n := int(round(tile / grid))
	for iz in n:
		for ix in n:
			var cx := key.x * n + ix
			var cz := key.y * n + iz
			var x := (float(cx) + _hash(cx, cz, 41)) * grid
			var z := (float(cz) + _hash(cx, cz, 42)) * grid
			if _on_path(x, z, 1.3):
				continue
			# THE BED OF THE MERE IS STREWN WITH ROCK: one chance in every four metres
			# of it rather than every sixteen, thickest among the weed, mostly small
			# stones with a big one now and then.
			if _mere_reach > 0.0 and Vector2((float(cx) + 0.5) * grid, (float(cz) + 0.5) * grid).distance_to(_islet) < _mere_reach + grid:
				for sz in 4:
					for sx in 4:
						var ux := cx * 4 + sx
						var uz := cz * 4 + sz
						var bx := (float(ux) + _hash(ux, uz, 141)) * grid * 0.25
						var bz := (float(uz) + _hash(ux, uz, 142)) * grid * 0.25
						if Vector2(bx, bz).distance_to(_islet) >= _mere_reach or _on_path(bx, bz, 1.3):
							continue
						var clump := clump_at(bx, bz)
						var amid := 1.0 - clampf(clump.x / maxf(clump.y * 1.4, 0.01), 0.0, 1.0) if clump.y > 0.0 else 0.0
						if _hash(ux, uz, 143) > (0.3 + 0.55 * amid) * density:
							continue
						var bed := f.sample(bx, bz)
						if not bool(bed.get("on_land", false)) or float(bed["height"]) >= _mere_level - 1.0:
							continue
						var kind_b := int(_hash(ux, uz, 144) * 5.0) % 5
						var roll := _hash(ux, uz, 145)
						var size_b := 0.22 + roll * roll * 1.1 + (2.2 * _hash(ux, uz, 146) if _hash(ux, uz, 147) > 0.93 else 0.0)
						var lie := Basis(Vector3.UP, _hash(ux, uz, 148) * TAU) * Basis(Vector3(1, 0, 0), (_hash(ux, uz, 149) - 0.5) * 0.9)
						_push(bufs[kind_b], lie.scaled(Vector3.ONE * size_b), Vector3(bx, float(bed["height"]) - 0.12 * size_b, bz))
			var s := f.sample(x, z)
			if not bool(s.get("on_land", false)) or float(s.get("flatten", 0.0)) > 0.2:
				continue
			if Vector2(x, z).distance_to(_islet) < _clearing:
				continue
			var w: Color = s.get("weights", Color(1, 0, 0, 0))
			var flow := float(s.get("flow_weight", 0.0))
			# (The bed of the mere has had its rocks already, above.)
			if _mere_reach > 0.0 and float(s["height"]) < _mere_level - 1.0 and Vector2(x, z).distance_to(_islet) < _mere_reach:
				continue
			if flow > 0.55:
				continue
			# More of them where the ground is already rock, and along the rivers.
			var want := 0.07 + 0.6 * w.b + 0.35 * smoothstep(0.1, 0.4, flow)
			if _hash(cx, cz, 43) > want * density:
				continue
			var kind := int(_hash(cx, cz, 44) * 5.0) % 5
			var big := _hash(cx, cz, 45)
			var size := 0.35 + big * big * big * 3.0
			var basis := Basis(Vector3.UP, _hash(cx, cz, 46) * TAU)
			basis = Basis(Vector3(1, 0, 0), (_hash(cx, cz, 47) - 0.5) * 0.7) * basis
			basis = Basis(Vector3(0, 0, 1), (_hash(cx, cz, 48) - 0.5) * 0.7) * basis
			_push(bufs[kind], basis.scaled(Vector3.ONE * size), Vector3(x, float(s["height"]) - 0.1 * size, z))
	# FALLEN ROCK at the foot of the tablelands' walls (IslandField's mesa_*): where
	# the ground is level but a wall rises close by, a heap of what came off it,
	# mostly small, now and then one the size of a car, lying toward the wall.
	if f.mesa_enabled:
		# (A whole number of cells to the tile, so every rock lies in the tile that
		# holds it: its colliders and its level of detail go by the tile.)
		var tn := 5
		var tg := tile / float(tn)
		for iz in tn:
			for ix in tn:
				var cx := key.x * tn + ix
				var cz := key.y * tn + iz
				if _hash(cx, cz, 61) > 0.55 * density:
					continue
				var x := (float(cx) + _hash(cx, cz, 62)) * tg
				var z := (float(cz) + _hash(cx, cz, 63)) * tg
				if _on_path(x, z, 1.0):
					continue
				var h := f.height_at(x, z, -1e9)
				if h < -1e8 or absf(f.height_at(x + 1.5, z, h) - h) > 0.9 or absf(f.height_at(x, z + 1.5, h) - h) > 0.9:
					continue          # not at the foot: on the wall, or off the land
				var best := 0.0
				var wall := Vector2.ZERO
				for d in 6:
					var dir := Vector2.from_angle(TAU * float(d) / 6.0 + _hash(cx, cz, 64))
					var rise := f.height_at(x + dir.x * 9.0, z + dir.y * 9.0, h) - h
					if rise > best:
						best = rise
						wall = dir
				if best < 7.0:
					continue
				var count := 1 + int(_hash(cx, cz, 65) * 4.0)
				for r in count:
					var u := _hash(cx * 7 + r, cz * 13 - r, 66)
					var size_t := 0.35 + 2.4 * pow(u, 3.0)
					var off := wall * (_hash(cx + r, cz, 67) * 3.0) + Vector2(_hash(cx, cz + r, 68) - 0.5, _hash(cx - r, cz, 69) - 0.5) * 4.0
					var bx := x + off.x
					var bz := z + off.y
					var kind_t := int(_hash(cx + 3 * r, cz - 5 * r, 70) * 5.0) % 5
					var lie := Basis(Vector3.UP, _hash(cx, cz, 71 + r) * TAU) * Basis(Vector3(1, 0, 0), (_hash(cz, cx, 72 + r) - 0.5) * 0.9)
					_push(bufs[kind_t], lie.scaled(Vector3.ONE * size_t), Vector3(bx, f.height_at(bx, bz, h) - 0.15 * size_t, bz))
	# The rock the shuttle turned up round its divot and along its skid, those of
	# it that lie in this tile (SCRIPT_crashed_shuttle.gd's `debris`).
	for d in _crash_debris(f):
		var where: Transform3D = d[1]
		if int(floor(where.origin.x / tile)) == key.x and int(floor(where.origin.z / tile)) == key.y:
			_push(bufs[DEBRIS_KIND + int(d[0])], where.basis, where.origin)
	return bufs


var _debris: Variant = null
var _debris_lock := Mutex.new()


func _crash_debris(f: IslandField) -> Array:
	_debris_lock.lock()
	if _debris == null:
		_debris = []
		if _crash != null:
			var site: PackedVector2Array = _crash.crash_site()
			if site[1] != Vector2.ZERO:
				_debris = CrashedShuttle.debris(f, site[0], site[1])
	var out: Array = _debris
	_debris_lock.unlock()
	return out


func _place_grass(f: IslandField, layer: Dictionary, key: Vector2i) -> Array:
	var buf := PackedFloat32Array()
	var grid := 0.44        # thick underfoot; the shader thins it with distance
	var tile := float(layer["tile"])
	var x0 := float(key.x) * tile
	var z0 := float(key.y) * tile
	var n := int(round(tile / grid))
	# The field is sampled on a coarse lattice and the clumps between its points
	# take the nearest answer: a clump does not need its own look at the ground
	# type, only its own height.
	var coarse := 4
	var m := n / coarse + 1
	var samples: Array = []
	for jz in m:
		for jx in m:
			samples.append(f.sample(x0 + (float(jx) + 0.5) * grid * coarse, z0 + (float(jz) + 0.5) * grid * coarse))
	for iz in n:
		for ix in n:
			var cx := key.x * n + ix
			var cz := key.y * n + iz
			var s: Dictionary = samples[mini(iz / coarse, m - 1) * m + mini(ix / coarse, m - 1)]
			if not bool(s.get("on_land", false)):
				continue
			if _on_path(x0 + (float(ix) + 0.5) * grid, z0 + (float(iz) + 0.5) * grid, 0.3):
				continue
			var w: Color = s.get("weights", Color(1, 0, 0, 0))
			var want := clampf(w.r * 1.5, 0.0, 1.0) * (1.0 - 0.45 * float(s.get("forest", 0.0)))
			if (float(s.get("flow_weight", 0.0)) > 0.5 or float(s.get("flatten", 0.0)) > 0.3) \
					and Vector2(x0 + (float(ix) + 0.5) * grid, z0 + (float(iz) + 0.5) * grid).distance_to(_islet) > _clearing * 1.15:
				continue
			var patch := 0.35 + 0.65 * _hash(cx >> 3, cz >> 3, 51)
			var px := x0 + (float(ix) + 0.5) * grid
			var pz := z0 + (float(iz) + 0.5) * grid
			var meadow := 1.0 - smoothstep(_clearing * 0.8, _clearing * 1.15, Vector2(px, pz).distance_to(_islet))
			meadow = maxf(meadow, Flora.meadow(px, pz) * clampf(w.r * 2.5 + 0.4, 0.0, 1.0))
			if meadow > 0.0:
				# Meadows (and the one round the stone) are all grass, thick and even.
				want = maxf(want, meadow * 1.3)
				patch = maxf(patch, meadow)
			if Vector2(px, pz).distance_to(_islet) < 1.3:
				continue
			# In the wood: none in a clearing or a drift of ferns.
			var wood := _wood(float(s.get("forest", 0.0)))
			if wood > 0.0:
				var zones := wood_zones(px, pz)
				want *= 1.0 - wood * clampf(zones.y * 1.3 + zones.x, 0.0, 1.0)
			if _hash(cx, cz, 52) > want * patch * 0.8 * density:
				continue
			var x := x0 + (float(ix) + _hash(cx, cz, 53)) * grid
			var z := z0 + (float(iz) + _hash(cx, cz, 54)) * grid
			var y := f.height_at(x, z, float(s["height"]))
			# NONE ON ROCK: not on a cliff's face (the blade's own ground, looked at
			# only where the ground about is steep at all), nor in a cliff's rock.
			if float(s.get("slope", 0.0)) > STEEP * 0.25:
				var gx := f.height_at(x + 1.0, z, y) - y
				var gz := f.height_at(x, z + 1.0, y) - y
				if gx * gx + gz * gz > ROCK_FACE * ROCK_FACE:
					continue
			if CliffRocks.covers(x, z, 0.3):
				continue
			# Thinning out to nothing well short of the island's edge.
			if _hash(cx, cz, 60) > smoothstep(EDGE * 0.6, EDGE * 1.2, float(s.get("mask", 1.0))):
				continue
			var variant := float(int(_hash(cx, cz, 55) * 3.0) % 3)
			var tall := 0.45 + 0.55 * _hash(cx, cz, 56)
			var wide := tall * (1.0 if variant < 0.5 else (1.2 if variant < 1.5 else 1.45))
			var basis := Basis(Vector3.UP, _hash(cx, cz, 57) * TAU).scaled(Vector3(wide, tall, wide))
			_push(buf, basis, Vector3(x, y - 0.03, z))
			buf.append_array([variant, _hash(cx, cz, 58), _hash(cx, cz, 59), 0.0])
			# MEADOWS ARE THICK: a second clump between this and the next.
			if meadow > 0.5 and _hash(cx, cz, 60) < (meadow - 0.4) * 1.4 * density:
				var x2 := x + grid * 0.5
				var z2 := z + grid * (_hash(cx, cz, 61) - 0.5)
				var tall2 := 0.5 + 0.55 * _hash(cx, cz, 62)
				_push(buf, Basis(Vector3.UP, _hash(cx, cz, 63) * TAU).scaled(Vector3(tall2 * 1.15, tall2, tall2 * 1.15)),
						Vector3(x2, f.height_at(x2, z2, y) - 0.03, z2))
				buf.append_array([float(int(_hash(cx, cz, 64) * 3.0) % 3), _hash(cx, cz, 65), _hash(cx, cz, 66), 0.0])
	return [buf]


# ------------------------------------------------------------------ grass, kept small
#
# ALL THE ISLAND'S GRASS IS PLACED IN THE BUILD (the user: "PRE-BAKE ALL GRASS ...
# driving in the truck causes grass to lag behind"): a truck at speed crosses
# tiles faster than their grass could be worked out, so none of it is worked out
# in play any more. It is millions of clumps, and as drawn a clump is sixteen
# floats, hundreds of megabytes of them; so a tile's grass is KEPT as fourteen
# bytes a clump and opened out into what is drawn only when the tile is
# (`_unpack_grass`), which is a few hundred clumps and no work to speak of.
#
#   0  u16  x in the tile (a metre's margin either side)     2  u16  z likewise
#   4  f32  height                                           8  u8   turned (256ths of a turn)
#   9  u8   how tall (1/200 m)                               10 u8   how wide for its height (1/100)
#   11 u8   which clump of the atlas    12, 13  u8  its two lots (the shader's shade and thinning)
const GRASS_BYTES := 14
## How far round the wreck the weed stands thick (`_place_seaweed`), metres.
const WRECK_WEED := 85.0
## Set by tests/BAKE_island.gd: plant the grass of the whole island, not only
## round where the player starts.
static var grass_everywhere := false


static func _pack_grass(buf: PackedFloat32Array, key: Vector2i, tile: float) -> PackedByteArray:
	var n := buf.size() / STRIDE_CUSTOM
	var out := PackedByteArray()
	out.resize(n * GRASS_BYTES)
	var x0 := float(key.x) * tile - 1.0
	var z0 := float(key.y) * tile - 1.0
	var span := 65535.0 / (tile + 2.0)
	for k in n:
		var i := k * STRIDE_CUSTOM
		var o := k * GRASS_BYTES
		var wide := Vector2(buf[i], buf[i + 8]).length()
		var tall := buf[i + 5]
		out.encode_u16(o, clampi(int(round((buf[i + 3] - x0) * span)), 0, 65535))
		out.encode_u16(o + 2, clampi(int(round((buf[i + 11] - z0) * span)), 0, 65535))
		out.encode_float(o + 4, buf[i + 7])
		out[o + 8] = int(round(fposmod(atan2(-buf[i + 8], buf[i]), TAU) / TAU * 256.0)) & 255
		out[o + 9] = clampi(int(round(tall * 200.0)), 0, 255)
		out[o + 10] = clampi(int(round(wide / maxf(tall, 0.001) * 100.0)), 0, 255)
		out[o + 11] = clampi(int(round(buf[i + 12])), 0, 255)
		out[o + 12] = clampi(int(round(buf[i + 13] * 255.0)), 0, 255)
		out[o + 13] = clampi(int(round(buf[i + 14] * 255.0)), 0, 255)
	return out


static func _unpack_grass(data: PackedByteArray, key: Vector2i, tile: float) -> PackedFloat32Array:
	var n := data.size() / GRASS_BYTES
	var buf := PackedFloat32Array()
	buf.resize(n * STRIDE_CUSTOM)
	var x0 := float(key.x) * tile - 1.0
	var z0 := float(key.y) * tile - 1.0
	var span := (tile + 2.0) / 65535.0
	for k in n:
		var o := k * GRASS_BYTES
		var i := k * STRIDE_CUSTOM
		var yaw := float(data[o + 8]) / 256.0 * TAU
		var tall := float(data[o + 9]) / 200.0
		var wide := tall * float(data[o + 10]) / 100.0
		buf[i] = cos(yaw) * wide
		buf[i + 2] = sin(yaw) * wide
		buf[i + 3] = x0 + float(data.decode_u16(o)) * span
		buf[i + 5] = tall
		buf[i + 7] = data.decode_float(o + 4)
		buf[i + 8] = -sin(yaw) * wide
		buf[i + 10] = cos(yaw) * wide
		buf[i + 11] = z0 + float(data.decode_u16(o + 2)) * span
		buf[i + 12] = float(data[o + 11])
		buf[i + 13] = float(data[o + 12]) / 255.0
		buf[i + 14] = float(data[o + 13]) / 255.0
	return buf


## A tile's buffers as they are drawn, from what the cache holds for it.
func _drawn(layer: Dictionary, key: Vector2i, held: Array) -> Array:
	if not layer.has("packed"):
		return held
	return [_unpack_grass(held[0], key, float(layer["tile"]))]


# ------------------------------------------------------------------ threading

func _take_field() -> IslandField:
	_pool_mutex.lock()
	var f: IslandField = _pool.pop_back() if not _pool.is_empty() else null
	_pool_mutex.unlock()
	return f if f != null else _field.clone()


func _give_field(f: IslandField) -> void:
	_pool_mutex.lock()
	_pool.append(f)
	_pool_mutex.unlock()


func _work(li: int, key: Vector2i) -> void:
	var layer := _layers[li]
	var f := _take_field()
	var bufs: Array = (layer["place"] as Callable).call(f, layer, key)
	_give_field(f)
	if layer.has("packed"):
		bufs = [_pack_grass(bufs[0], key, float(layer["tile"]))]
	_done_mutex.lock()
	_done.append([li, key, bufs])
	_done_mutex.unlock()


func _prefill_one(i: int) -> void:
	var job: Array = _prefill_jobs[i]
	_work(int(job[0]), job[1])
	_done_mutex.lock()
	_prefill_count += 1
	_done_mutex.unlock()


# Leaving while plants are still being placed: let the workers finish first, or
# they run on into a node that is gone.
func _exit_tree() -> void:
	if _prefill_group >= 0 and not _prefilled:
		WorkerThreadPool.wait_for_group_task_completion(_prefill_group)
	for li in _near_tasks:
		WorkerThreadPool.wait_for_task_completion(_near_tasks[li])


# THE LOADING COVER'S HOOKS: everything is planted behind the loading screen, so
# nothing has to be worked out while the player is moving. Trees, ferns, bushes,
# seaweed and boulders are placed for the whole island, and so is the grass in a
# build (`grass_everywhere`, kept packed: "grass, kept small" above). Run from
# the editor or a test with no bake, grass is placed for `GRASS_PRELOAD` metres
# round where the player starts and after that `prefetch` metres ahead of what
# is drawn (see _update_layer), which is also what fills any tile a bake lacks.
const GRASS_PRELOAD := 320.0


func prefill_covered() -> void:
	pass


## THE PLANTING IS BAKED INTO THE BUILD, like the terrain. Working out where
## every plant on the island stands takes minutes on a desktop and far longer on
## a phone, and the answer never changes: it is a pure function of the island's
## settings and this code. `tests/BAKE_island.gd` runs it once and writes
## data/bake/flora_<signature>.bake; the game reads that back in a second or two
## and only places whatever the file does not hold. No file, or one whose
## signature no longer matches, and it is all worked out here as before.
const BAKE_STORE := "flora"
const BAKE_VERSION := 5
## Ground steeper than this (rise over run) is a cliff's face and bare: where the
## terrain's shader begins to draw it as rock (`cliff_face` there: 0.55).
const ROCK_FACE := 0.52
## The same steepness as the field's samples give it ("slope" there is ONE MINUS
## THE NORMAL'S HEIGHT, not rise over run: 0.113 is a rise of 0.52, 27 degrees).
## Trees, ferns and grass stop there. (They were tested against the field's
## figure as if it were rise over run, and so grew on ground up to 60 degrees.)
const STEEP := 0.113
## NOTHING GROWS OUT BY THE ISLAND'S EDGE: no trees, ferns or grass nearer it than
## about this, in the field's mask units (0 at the edge, 1 at the middle: 0.05 of
## a 1250 m island is 60 m), the line ragged and the grass thinning out to it.
const EDGE := 0.05
const SOURCES := [
	"res://scripts/world/SCRIPT_flora.gd",
	"res://scripts/world/SCRIPT_island_field.gd",
	"res://scripts/world/SCRIPT_flow_terrain.gd",
	"res://scripts/world/SCRIPT_sword_stone.gd",
]

var _bake_tried := false
var _bake_task := -1
var _bake_read: Dictionary = {}
var bake_source := ""


## Only declared settings and the code go in: nothing computed, so a phone and
## the machine that baked arrive at the same name.
func bake_signature() -> String:
	return BakeStore.signature_for(BAKE_VERSION, [_field, {
		"density": density, "seed": world_seed,
		"code": BakeStore.source_digest(SOURCES),
		"cliffs": CliffRocks.layout_key,
	}])


## Write every tile placed so far. Returns the number of tiles, or -1.
func save_bake(path: String) -> int:
	var out := {}
	var n := 0
	for layer in _layers:
		out[String(layer["name"])] = layer["cache"]
		n += (layer["cache"] as Dictionary).size()
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return -1
	f.store_var(out)
	f.close()
	return n


func _read_bake(path: String) -> void:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	var v: Variant = f.get_var()
	f.close()
	if v is Dictionary:
		_bake_read = v


func prefill_step() -> bool:
	if _prefilled or _layers.is_empty():
		return true
	# (Nothing is planted until the cliffs' rocks are down: plants keep off them.)
	if not CliffRocks.laid_out:
		return false
	if not _bake_tried:
		_bake_tried = true
		var path := BakeStore.find_bake(BAKE_STORE, bake_signature())
		if path != "":
			bake_source = path
			_bake_task = WorkerThreadPool.add_task(_read_bake.bind(path), false, "flora bake")
	if _bake_task >= 0:
		if not WorkerThreadPool.is_task_completed(_bake_task):
			return false
		WorkerThreadPool.wait_for_task_completion(_bake_task)
		_bake_task = -1
		var held := 0
		for layer in _layers:
			var got: Variant = _bake_read.get(String(layer["name"]))
			if got is Dictionary:
				layer["cache"] = got
				layer["cam_tile"] = Vector2i(1 << 30, 0)
				held += (got as Dictionary).size()
		_bake_read = {}
		print("[flora] read %d planted tiles from %s" % [held, bake_source])
	if _prefill_group < 0:
		var start := Vector2.ZERO
		var explorer := get_node_or_null(^"../Explorer") as Node3D
		if explorer != null:
			start = Vector2(explorer.global_position.x, explorer.global_position.z)
		for li in _layers.size():
			var layer := _layers[li]
			var whole := bool(layer.get("prefill", false))
			if not whole and String(layer["name"]) != "grass":
				continue
			var cache: Dictionary = layer["cache"]
			var tile := float(layer["tile"])
			var n := int(ceil(_extent / tile))
			for z in range(-n, n):
				for x in range(-n, n):
					var c := Vector2((float(x) + 0.5) * tile, (float(z) + 0.5) * tile)
					if c.length() > _extent + tile:
						continue
					if not whole and not grass_everywhere and c.distance_to(start) > GRASS_PRELOAD:
						continue
					if cache.has(Vector2i(x, z)):
						continue
					_prefill_jobs.append([li, Vector2i(x, z)])
		if _prefill_jobs.is_empty():
			_prefilled = true
			_far_rocks()
			return true
		_prefill_group = WorkerThreadPool.add_group_task(_prefill_one, _prefill_jobs.size(), -1, false, "flora")
		return false
	if not WorkerThreadPool.is_group_task_completed(_prefill_group):
		return false
	WorkerThreadPool.wait_for_group_task_completion(_prefill_group)
	_drain(1 << 30)
	_prefilled = true
	_far_rocks()
	var report := ""
	for layer in _layers:
		var total := 0
		for bufs in (layer["cache"] as Dictionary).values():
			for buf in bufs:
				total += buf.size() / (GRASS_BYTES if layer.has("packed") else int(layer["stride"]))
		report += "%s %d  " % [layer["name"], total]
	print("[flora] planted: %s(%d tiles)" % [report, _prefill_jobs.size()])
	return true


func prefill_ratio() -> float:
	if _prefilled:
		return 1.0
	if _bake_task >= 0:
		return 0.5
	if _prefill_group < 0 or _prefill_jobs.is_empty():
		return 0.0
	return float(_prefill_count) / float(_prefill_jobs.size())


func prefill_label() -> String:
	return "planting the forest"


# ------------------------------------------------------------------ each frame

func _drain(limit: int) -> void:
	_done_mutex.lock()
	var take := _done.slice(0, limit)
	_done = _done.slice(limit)
	_done_mutex.unlock()
	for item in take:
		var layer := _layers[int(item[0])]
		(layer["cache"] as Dictionary)[item[1]] = item[2]
		(layer["asked"] as Dictionary).erase(item[1])
		if not _cleared.is_empty():
			_sweep(layer, item[1], _cleared)       # (ground built on stays bare as it streams in)
		layer["cam_tile"] = Vector2i(1 << 30, 0)       # look again: a tile arrived


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _layers.is_empty() or not CliffRocks.laid_out:
		return
	_drain(24)
	var at := cam.global_position
	for li in _layers.size():
		_update_layer(li, at)


static func _tile_distance(key: Vector2i, tile: float, at: Vector3) -> float:
	var lo := Vector2(float(key.x) * tile, float(key.y) * tile)
	var dx := maxf(maxf(lo.x - at.x, at.x - (lo.x + tile)), 0.0)
	var dz := maxf(maxf(lo.y - at.z, at.z - (lo.y + tile)), 0.0)
	return sqrt(dx * dx + dz * dz)


## WHAT CAN BE WALKED INTO. Tree trunks and boulders get collision, but only the
## ones in the tile the camera is in and the eight round it: a few dozen shapes on
## one static body, rebuilt when the camera crosses into another tile. Seventeen
## thousand trunks in the physics world would buy nothing.
func _rebuild_colliders(layer: Dictionary, cam_tile: Vector2i) -> void:
	var body: StaticBody3D = layer.get("body")
	if body == null:
		body = StaticBody3D.new()
		body.name = "Colliders"
		(layer["holder"] as Node3D).add_child(body)
		layer["body"] = body
	for c in body.get_children():
		c.queue_free()
	var cache: Dictionary = layer["cache"]
	var stride := int(layer["stride"])
	var kinds: Array = layer["kinds"]
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var bufs: Variant = cache.get(cam_tile + Vector2i(dx, dz))
			if bufs == null:
				continue
			for k in kinds.size():
				var shape: Shape3D = kinds[k].get("shape")
				var buf: PackedFloat32Array = bufs[k]
				if shape == null:
					continue
				for i in range(0, buf.size(), stride):
					var basis := Basis(Vector3(buf[i], buf[i + 4], buf[i + 8]), Vector3(buf[i + 1], buf[i + 5], buf[i + 9]),
							Vector3(buf[i + 2], buf[i + 6], buf[i + 10]))
					var cs := CollisionShape3D.new()
					cs.shape = shape
					cs.transform = Transform3D(basis, Vector3(buf[i + 3], buf[i + 7], buf[i + 11])
							+ basis.y * float(kinds[k].get("shape_lift", 0.0)))
					body.add_child(cs)


# ------------------------------------------------------------------ felling

func _tree_layer() -> Dictionary:
	for layer in _layers:
		if String(layer["name"]) == "trees":
			return layer
	return {}


## The first tree a reach of `reach` metres from `from` along `dir` meets, or {}.
## Looked for among the placed trees themselves (the tiles round `from`), so it
## does not depend on which trunks have colliders at the moment.
func tree_on(from: Vector3, dir: Vector3, reach: float, slack := 0.35) -> Dictionary:
	var layer := _tree_layer()
	if layer.is_empty():
		return {}
	var tile := float(layer["tile"])
	var cache: Dictionary = layer["cache"]
	var kinds: Array = layer["kinds"]
	var a := Vector2(from.x, from.z)
	var d := Vector2(dir.x, dir.z)
	d = d.normalized() if d.length() > 0.001 else Vector2.ZERO
	var at_tile := Vector2i(int(floor(from.x / tile)), int(floor(from.z / tile)))
	var best := {}
	var best_t := 1e9
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := at_tile + Vector2i(dx, dz)
			var bufs: Variant = cache.get(key)
			if bufs == null:
				continue
			for k in kinds.size():
				var buf: PackedFloat32Array = bufs[k]
				for i in range(0, buf.size(), STRIDE):
					var p := Vector2(buf[i + 3], buf[i + 11])
					var t := clampf((p - a).dot(d), 0.0, reach)
					var size := Vector3(buf[i + 1], buf[i + 5], buf[i + 9]).length()
					var r := float((kinds[k]["shape"] as CylinderShape3D).radius) / 1.2 * size
					if (a + d * t).distance_to(p) > r + slack or t >= best_t:
						continue
					var h := float((kinds[k]["lods"][0] as Mesh).get_aabb().size.y) * size
					if from.y < buf[i + 7] - 1.0 or from.y > buf[i + 7] + h:
						continue
					best_t = t
					best = {"key": key, "kind": k, "index": i, "radius": r, "height": h, "size": size,
						"origin": Vector3(buf[i + 3], buf[i + 7], buf[i + 11]),
						"basis": Basis(Vector3(buf[i], buf[i + 4], buf[i + 8]), Vector3(buf[i + 1], buf[i + 5], buf[i + 9]),
							Vector3(buf[i + 2], buf[i + 6], buf[i + 10])).orthonormalized()}
	return best


## The full mesh of a kind of tree (`tree_on`'s "kind"), for a tree that has
## left the instance buffers and is drawn on its own while it falls.
func tree_mesh(kind: int) -> Mesh:
	var layer := _tree_layer()
	return null if layer.is_empty() else (layer["kinds"][kind]["lods"][0] as Mesh)


## Take a tree `tree_on` found out of the wood: its meshes, its impostors and its
## collider all go, for as long as this run lasts.
func fell(tree: Dictionary) -> void:
	_take_out(_tree_layer(), tree, 0.6)


func _rock_layer() -> Dictionary:
	for layer in _layers:
		if String(layer["name"]) == "boulders":
			return layer
	return {}


## The boulder a reach of `reach` metres from `from` along `dir` strikes, or {}.
## Boulders near the player are solid (`_rebuild_colliders`), so this is a ray
## against the real stone: "at" is where it lands on the rock and "normal" the
## face there. "size" is the boulder's scale, "span" its width in metres.
func rock_on(from: Vector3, dir: Vector3, reach: float, skip: Array[RID] = []) -> Dictionary:
	var layer := _rock_layer()
	var body: StaticBody3D = layer.get("body") if not layer.is_empty() else null
	if body == null or dir.length() < 0.001:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * reach)
	q.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit["collider"] != body:
		return {}
	var stone := body.shape_owner_get_owner(body.shape_find_owner(int(hit["shape"]))) as Node3D
	if stone == null or stone.is_queued_for_deletion():
		return {}
	var origin := stone.position
	var tile := float(layer["tile"])
	var cache: Dictionary = layer["cache"]
	var kinds: Array = layer["kinds"]
	var at_tile := Vector2i(int(floor(origin.x / tile)), int(floor(origin.z / tile)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := at_tile + Vector2i(dx, dz)
			var bufs: Variant = cache.get(key)
			if bufs == null:
				continue
			for k in kinds.size():
				var buf: PackedFloat32Array = bufs[k]
				for i in range(0, buf.size(), STRIDE):
					if absf(buf[i + 3] - origin.x) > 0.01 or absf(buf[i + 7] - origin.y) > 0.01 or absf(buf[i + 11] - origin.z) > 0.01:
						continue
					var size := Vector3(buf[i + 1], buf[i + 5], buf[i + 9]).length()
					var box: AABB = (kinds[k]["lods"][0] as Mesh).get_aabb()
					var basis := Basis(Vector3(buf[i], buf[i + 4], buf[i + 8]), Vector3(buf[i + 1], buf[i + 5], buf[i + 9]),
							Vector3(buf[i + 2], buf[i + 6], buf[i + 10]))
					return {"key": key, "kind": k, "index": i, "size": size, "origin": origin, "basis": basis,
						"centre": origin + basis * box.get_center(),
						"span": (box.size.x + box.size.y + box.size.z) / 3.0 * size,
						"at": hit["position"], "normal": hit["normal"]}
	return {}


## The low mesh of a kind of boulder (`rock_on`'s "kind"), for the rubble one
## breaks into.
func rock_mesh(kind: int) -> Mesh:
	var layer := _rock_layer()
	if layer.is_empty():
		return null
	var lods: Array = layer["kinds"][kind]["lods"]
	return lods[mini(3, lods.size() - 1)] as Mesh


## Take a boulder `rock_on` found out of the world: its meshes and its collider.
func quarry(rock: Dictionary) -> void:
	_take_out(_rock_layer(), rock, 0.02)


## ROCKS NEVER GO. Past the boulder layer's radius, where its tiles stop being
## drawn, every boulder big enough to be seen from there (over 0.8 m) is drawn
## island-wide at its simplest, one MultiMesh per kind per FAR_CELL square (so
## the squares out of view are culled), dithering in exactly where the near ones
## dither out (lod_in: the layer's radius). Built once the island is planted.
func _far_rocks() -> void:
	var layer := _rock_layer()
	if layer.is_empty() or layer.has("far_rocks"):
		return
	var kinds: Array = layer["kinds"]
	var packed := {}         # Vector3i(cell x, cell z, kind) -> PackedFloat32Array
	for key in layer["cache"]:
		var bufs: Array = layer["cache"][key]
		for k in bufs.size():
			var buf: PackedFloat32Array = bufs[k]
			for i in range(0, buf.size(), STRIDE):
				if Vector3(buf[i + 1], buf[i + 5], buf[i + 9]).length() < 0.8:
					continue
				var slot := Vector3i(int(floor(buf[i + 3] / FAR_CELL)), int(floor(buf[i + 11] / FAR_CELL)), k)
				var into: PackedFloat32Array = packed.get(slot, PackedFloat32Array())
				into.append_array(buf.slice(i, i + STRIDE))
				packed[slot] = into
	var holder := Node3D.new()
	holder.name = "FarRocks"
	add_child(holder)
	var count := 0
	for slot: Vector3i in packed:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var lods: Array = kinds[slot.z]["lods"]
		mm.mesh = lods[lods.size() - 1]
		var buf: PackedFloat32Array = packed[slot]
		mm.instance_count = buf.size() / STRIDE
		mm.buffer = buf
		count += mm.instance_count
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.custom_aabb = AABB(Vector3(slot.x * FAR_CELL - 10.0, -60.0, slot.y * FAR_CELL - 10.0),
				Vector3(FAR_CELL + 20.0, 260.0, FAR_CELL + 20.0))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.set_instance_shader_parameter(&"lod_in", float(layer["radius"]))
		mmi.set_instance_shader_parameter(&"lod_out", 0.0)
		holder.add_child(mmi)
	layer["far_rocks"] = holder
	print("[flora] %d far rocks, drawn to the horizon" % count)


## One plant or stone out of a layer's instance buffers, and its collider (the
## one standing within `near` metres of it) with it.
func _take_out(layer: Dictionary, tree: Dictionary, near: float) -> void:
	if layer.is_empty() or tree.is_empty():
		return
	var key: Vector2i = tree["key"]
	var bufs: Variant = (layer["cache"] as Dictionary).get(key)
	if bufs == null:
		return
	var buf: PackedFloat32Array = bufs[int(tree["kind"])]
	var i := int(tree["index"])
	if i + STRIDE > buf.size():
		return
	var cut := buf.slice(0, i)
	cut.append_array(buf.slice(i + STRIDE))
	bufs[int(tree["kind"])] = cut
	# The tile's open levels take the shorter buffer as they stand: nothing is
	# closed, rebuilt or reopened, so a felling costs one buffer upload a level.
	layer["rebin"] = true
	var tiles: Dictionary = layer["tiles"]
	if tiles.has(key):
		tiles[key]["bufs"] = bufs
		var held: Dictionary = tiles[key]["lods"]
		for lod in held:
			var mmi: MultiMeshInstance3D = held[lod][int(tree["kind"])]
			if mmi == null:
				continue
			mmi.multimesh.instance_count = cut.size() / STRIDE
			if not cut.is_empty():
				mmi.multimesh.buffer = cut
	# Its collider goes now. The far impostors are not repacked for one tree
	# (that walks every tile on the island): a tree near enough to fell is drawn
	# as a mesh, and the impostors catch up at the next tile crossed.
	var body: StaticBody3D = layer.get("body")
	var origin: Vector3 = tree["origin"]
	if body != null:
		for c in body.get_children():
			var at: Vector3 = (c as Node3D).position
			if absf(at.x - origin.x) < near and absf(at.z - origin.z) < near:
				c.queue_free()


# ------------------------------------------------------------------ building on it

var _cleared: Array = []     # ground that has been built on: [world to its own frame, half its size]


## BUILT-ON GROUND GROWS NOTHING. Everything standing in a rectangle of ground
## (`frame` is its middle and which way it faces, `half` half its width and depth,
## metres) goes: grass, ferns, bushes, trees, boulders and their colliders. It
## stays gone for the run, for tiles placed later as well as those here now.
func clear_ground(frame: Transform3D, half: Vector2) -> void:
	var zone := [frame.affine_inverse(), half, frame.origin, half.length()]
	_cleared.append(zone)
	for layer in _layers:
		var tile := float(layer["tile"])
		var cache: Dictionary = layer["cache"]
		var lo := Vector2i(int(floor((frame.origin.x - half.length()) / tile)), int(floor((frame.origin.z - half.length()) / tile)))
		var hi := Vector2i(int(floor((frame.origin.x + half.length()) / tile)), int(floor((frame.origin.z + half.length()) / tile)))
		for z in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				if cache.has(Vector2i(x, z)):
					_sweep(layer, Vector2i(x, z), [zone])


## One tile of one layer, with whatever stands in any of `zones` taken out.
func _sweep(layer: Dictionary, key: Vector2i, zones: Array) -> void:
	var tile := float(layer["tile"])
	var middle := Vector3((float(key.x) + 0.5) * tile, 0.0, (float(key.y) + 0.5) * tile)
	var near: Array = []
	for zone in zones:
		var c: Vector3 = zone[2]
		if Vector2(c.x - middle.x, c.z - middle.z).length() <= float(zone[3]) + tile * 0.7072:
			near.append(zone)
	if near.is_empty():
		return
	var bufs: Array = _drawn(layer, key, (layer["cache"] as Dictionary)[key])
	var stride := int(layer["stride"])
	var open: Variant = (layer["tiles"] as Dictionary).get(key)
	var gone := false
	for k in bufs.size():
		var buf: PackedFloat32Array = bufs[k]
		var kept := PackedFloat32Array()
		for i in range(0, buf.size(), stride):
			var out := false
			for zone in near:
				var at: Vector3 = (zone[0] as Transform3D) * Vector3(buf[i + 3], (zone[2] as Vector3).y, buf[i + 11])
				if absf(at.x) <= (zone[1] as Vector2).x and absf(at.z) <= (zone[1] as Vector2).y:
					out = true
					break
			if not out:
				kept.append_array(buf.slice(i, i + stride))
		if kept.size() == buf.size():
			continue
		gone = true
		bufs[k] = kept
		if open != null:
			for lod in open["lods"]:
				var mmi: MultiMeshInstance3D = open["lods"][lod][k]
				if mmi == null:
					continue
				mmi.multimesh.instance_count = kept.size() / stride
				if not kept.is_empty():
					mmi.multimesh.buffer = kept
	if not gone:
		return
	if layer.has("packed"):
		(layer["cache"] as Dictionary)[key] = [_pack_grass(bufs[0], key, tile)]
	if open != null:
		open["bufs"] = bufs
	layer["rebin"] = true
	var body: StaticBody3D = layer.get("body")
	if body != null:
		for c in body.get_children():
			for zone in near:
				var at: Vector3 = (zone[0] as Transform3D) * Vector3((c as Node3D).position.x, (zone[2] as Vector3).y, (c as Node3D).position.z)
				if absf(at.x) <= (zone[1] as Vector2).x and absf(at.z) <= (zone[1] as Vector2).y:
					c.queue_free()
					break


## Half the hand-over band, as a share of the distance: SHADERINC_lod_fade's LOD_BAND.
const LOD_BAND := 0.12


## The nearest and farthest a tile's plants can be from the camera.
func _tile_span(layer: Dictionary, key: Vector2i, at: Vector3) -> Vector2:
	var tile := float(layer["tile"])
	var flat := _tile_distance(key, tile, at)
	var dy := maxf(0.0, at.y - float(layer["height"]))
	var near := sqrt(flat * flat + dy * dy)
	# The farthest a plant's ROOT in it can be (that is what a level is chosen by):
	# across the tile's diagonal, and a few metres for ground that is not level.
	return Vector2(near, near + tile * 1.4143 + 6.0)


func _update_layer(li: int, at: Vector3) -> void:
	var layer := _layers[li]
	var tile := float(layer["tile"])
	var cam_tile := Vector2i(int(floor(at.x / tile)), int(floor(at.z / tile)))
	var tiles: Dictionary = layer["tiles"]
	var radius := float(layer["radius"])
	# High above the island nothing near the ground is near the camera.
	if at.y > radius + float(layer["height"]) + 60.0:
		radius = 0.0
	if cam_tile != layer["cam_tile"] or radius != float(layer.get("radius_now", -1.0)):
		layer["cam_tile"] = cam_tile
		layer["radius_now"] = radius
		layer["rebin"] = true          # (the tiles in range are about to change)
		var cache: Dictionary = layer["cache"]
		var asked: Dictionary = layer["asked"]
		# Tiles are held a band (and a tile) past the radius, so the last level can
		# dither out, or hand over to the impostors, instead of vanishing.
		var hold := radius * (1.0 + LOD_BAND) + tile if radius > 0.0 else 0.0
		# Placed further out than it is drawn, so a tile is ready before it is wanted
		# however fast the player is going.
		var ahead := hold + float(layer.get("prefetch", 0.0)) if radius > 0.0 else 0.0
		var reach := int(ceil(ahead / tile)) + 1
		var wanted := {}
		if radius > 0.0:
			for z in range(cam_tile.y - reach, cam_tile.y + reach + 1):
				for x in range(cam_tile.x - reach, cam_tile.x + reach + 1):
					var key := Vector2i(x, z)
					var away := _tile_distance(key, tile, at)
					if away > ahead:
						continue
					if away > hold:
						if not cache.has(key) and not asked.has(key) and not layer.get("prefill", false) \
								and Vector2((float(x) + 0.5) * tile, (float(z) + 0.5) * tile).length() <= _extent + tile:
							asked[key] = true
							WorkerThreadPool.add_task(_work.bind(li, key))
						continue
					if Vector2((float(x) + 0.5) * tile, (float(z) + 0.5) * tile).length() > _extent + tile:
						continue
					wanted[key] = true
					if tiles.has(key):
						continue
					if cache.has(key):
						tiles[key] = {"bufs": _drawn(layer, key, cache[key]), "lods": {}}
					elif not asked.has(key) and not layer.get("prefill", false):
						asked[key] = true
						WorkerThreadPool.add_task(_work.bind(li, key))
		for key in tiles.keys():
			if not wanted.has(key):
				for lod in tiles[key]["lods"]:
					_close_level(tiles[key]["lods"][lod])
				tiles.erase(key)
		if layer.has("far"):
			_repack_far(layer, at, radius)
		if layer.get("collide", false):
			_rebuild_colliders(layer, cam_tile)
	if layer.get("near_field", false):
		_near_update(li, at, radius)
		return
	# WHICH LEVELS EACH TILE DRAWS, every frame: usually one, and two while any of
	# its plants are in the band round a hand-over distance (the shader then picks,
	# plant by plant and pixel by pixel, which of the two shows).
	var dists: Array = layer["dists"]
	var levels := dists.size() + 1
	for key in tiles:
		var t: Dictionary = tiles[key]
		var span := _tile_span(layer, key, at)
		var held: Dictionary = t["lods"]
		for lod in levels:
			var lo := 0.0 if lod == 0 else float(dists[lod - 1])
			var hi := radius if lod == levels - 1 else float(dists[lod])
			var need := span.x <= hi * (1.0 + LOD_BAND) and span.y >= lo * (1.0 - LOD_BAND)
			if need and not held.has(lod):
				held[lod] = _open_level(layer, key, t["bufs"], lod, lo, hi)
			elif not need and held.has(lod):
				_close_level(held[lod])
				held.erase(lod)


func _close_level(mmis: Array) -> void:
	for mmi in mmis:
		if mmi != null:
			mmi.queue_free()


## EVERY PLANT NEAR THE CAMERA, SORTED INTO ITS OWN LEVEL OF DETAIL. Trees, bushes,
## ferns and boulders are not drawn a tile at a time (every plant in a tile at
## every level any of them needs, and a draw call per tile per kind per level):
## each plant goes into the one level its own distance calls for, or the two it
## is passing between, and the result is ONE MultiMesh per kind per level for
## everything in range. A few dozen draws where there were hundreds, and nothing
## submitted at a level it is not shown at.
##
## The sorting is done on a worker thread, from a snapshot of the tiles in range,
## whenever the camera has moved `step` metres (a fraction of the narrowest
## hand-over band, so nothing is ever caught at the wrong level): thousands of
## bushes are too many to sort between two frames on a phone. The main thread
## only hands the finished buffers to the MultiMeshes.
##
## A SORTING IS OUT OF DATE BY THE TIME IT IS SHOWN: the camera has gone on while
## the thread worked (and on a phone, with the pool busy laying terrain, it can
## wait its turn for a good part of a second). A plant handed to exactly the
## levels its distance called for when the sorting began is then at none of them:
## past where the one it is in lets go, and not yet in the next. It vanishes, and
## comes back at the next sorting, which is what a ring of trees blinking out
## ahead of a running player was. So each plant is given to every level it could
## be wanted at within `slack` metres either way of where it stood, the slack
## growing with how fast the camera is going; the shader shows it at the right
## one (and folds it away at the others), whichever the camera has reached. And
## a layer with few plants in range (the trees, the boulders) is not sent to a
## thread at all: it is sorted there and then, and is never out of date.
func _near_update(li: int, at: Vector3, radius: float) -> void:
	var layer := _layers[li]
	# How fast the camera is going, let down slowly so one still frame does not forget a sprint.
	var now := Time.get_ticks_msec()
	var since := maxf(float(now - int(layer.get("seen_ms", now))) / 1000.0, 0.001)
	var was: Vector3 = layer.get("seen_at", at)
	layer["seen_ms"] = now
	layer["seen_at"] = at
	layer["speed"] = maxf(float(layer.get("speed", 0.0)) * 0.97, minf(was.distance_to(at) / since, 80.0))
	# A sorting that has come back: put it on screen.
	_near_mutex.lock()
	var done: Variant = _near_done.get(li)
	_near_done.erase(li)
	_near_mutex.unlock()
	if done != null:
		_near_show(layer, done)
		layer["sorting"] = false
		if _near_tasks.has(li):
			WorkerThreadPool.wait_for_task_completion(_near_tasks[li])       # (done already: this lets the pool forget it)
			_near_tasks.erase(li)
	if layer.get("sorting", false):
		return
	var dists: Array = layer["dists"]
	var step := 0.5
	if not dists.is_empty():
		step = clampf(float(dists[0]) * LOD_BAND * 0.45, 0.4, 2.5)
	var last: Vector3 = layer.get("binned_at", Vector3(1e9, 0, 0))
	if not layer.get("rebin", true) and last.distance_to(at) <= step:
		return
	layer["rebin"] = false
	layer["binned_at"] = at
	var los := PackedFloat32Array()
	var his := PackedFloat32Array()
	for lod in dists.size() + 1:
		los.append(0.0 if lod == 0 else float(dists[lod - 1]))
		his.append(radius if lod == dists.size() else float(dists[lod]))
	# The tiles in range, as they are now. (A tile's buffers are replaced, never
	# changed in place, so the thread can read these while the game goes on.)
	var snapshot: Array = []
	var plants := 0
	if radius > 0.0:
		for key in (layer["tiles"] as Dictionary):
			var bufs: Array = layer["tiles"][key]["bufs"]
			snapshot.append(bufs.duplicate())
			for buf in bufs:
				plants += (buf as PackedFloat32Array).size()
	plants /= int(layer["stride"])
	# Half a second's travel of slack, and the step it is sorted at, and a little.
	var slack := clampf(float(layer["speed"]) * 0.5, 0.0, 16.0) + step + 0.5
	if plants <= NEAR_AT_ONCE:
		_near_sort(li, snapshot, at, los, his, int(layer["stride"]), (layer["kinds"] as Array).size(), step + 0.5)
		_near_mutex.lock()
		var sorted: Variant = _near_done.get(li)
		_near_done.erase(li)
		_near_mutex.unlock()
		if sorted != null:
			_near_show(layer, sorted)
		return
	layer["sorting"] = true
	var task := WorkerThreadPool.add_task(
			_near_sort.bind(li, snapshot, at, los, his, int(layer["stride"]), (layer["kinds"] as Array).size(), slack), true, "flora levels")
	_near_tasks[li] = task


## Fewer plants in range than this are sorted where they stand, not on a thread.
const NEAR_AT_ONCE := 1500


func _near_sort(li: int, snapshot: Array, at: Vector3, los: PackedFloat32Array, his: PackedFloat32Array,
		stride: int, kinds: int, slack: float) -> void:
	var levels := los.size()
	var packed: Array = []
	for k in kinds:
		var per: Array = []
		for lod in levels:
			per.append(PackedFloat32Array())
		packed.append(per)
	var flat: Array = []
	for i in kinds * levels:
		flat.append(PackedFloat32Array())
	for bufs: Array in snapshot:
		for k in kinds:
			var buf: PackedFloat32Array = bufs[k]
			for i in range(0, buf.size(), stride):
				var d := Vector3(buf[i + 3] - at.x, buf[i + 7] - at.y, buf[i + 11] - at.z).length()
				for lod in levels:
					if d > his[lod] * (1.0 + LOD_BAND) + slack:
						continue
					if lod > 0 and d < los[lod] * (1.0 - LOD_BAND) - slack:
						break
					# (Taken out of the list while it grows and put back: a packed array
					# reached through a list is a copy, and appending to one that is
					# held in two places copies the whole of it every time.)
					var slot := k * levels + lod
					var acc: PackedFloat32Array = flat[slot]
					flat[slot] = null
					acc.append_array(buf.slice(i, i + stride))
					flat[slot] = acc
	for k in kinds:
		for lod in levels:
			packed[k][lod] = flat[k * levels + lod]
	_near_mutex.lock()
	_near_done[li] = {"packed": packed, "at": at, "los": los, "his": his}
	_near_mutex.unlock()


func _near_show(layer: Dictionary, done: Dictionary) -> void:
	var packed: Array = done["packed"]
	var los: PackedFloat32Array = done["los"]
	var his: PackedFloat32Array = done["his"]
	var at: Vector3 = done["at"]
	var kinds: Array = layer["kinds"]
	var stride := int(layer["stride"])
	var near: Dictionary = layer.get("near", {})
	layer["near"] = near
	var reach := his[his.size() - 1] * (1.0 + LOD_BAND) + 80.0
	var box := AABB(at - Vector3(reach, 80.0, reach), Vector3(reach * 2.0, 220.0, reach * 2.0))
	for k in kinds.size():
		for lod in los.size():
			var buf: PackedFloat32Array = packed[k][lod]
			var slot := Vector2i(k, lod)
			var mmi: MultiMeshInstance3D = near.get(slot)
			if mmi == null:
				if buf.is_empty():
					continue
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_custom_data = stride == STRIDE_CUSTOM
				mm.mesh = kinds[k]["lods"][mini(lod, (kinds[k]["lods"] as Array).size() - 1)]
				mmi = MultiMeshInstance3D.new()
				mmi.multimesh = mm
				(layer["holder"] as Node3D).add_child(mmi)
				near[slot] = mmi
			mmi.multimesh.instance_count = buf.size() / stride
			if not buf.is_empty():
				mmi.multimesh.buffer = buf
			mmi.custom_aabb = box
			mmi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod < int(layer["shadow_lods"])
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			mmi.set_instance_shader_parameter(&"lod_in", los[lod])
			mmi.set_instance_shader_parameter(&"lod_out", his[lod])


## One level of detail of one tile: a MultiMeshInstance3D per kind of plant in it,
## told where it takes over (`lo`) and where it gives way (`hi`).
func _open_level(layer: Dictionary, key: Vector2i, bufs: Array, lod: int, lo: float, hi: float) -> Array:
	var tile := float(layer["tile"])
	var stride := int(layer["stride"])
	var kinds: Array = layer["kinds"]
	var mmis: Array = []
	for k in kinds.size():
		var buf: PackedFloat32Array = bufs[k]
		if buf.is_empty():
			mmis.append(null)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = stride == STRIDE_CUSTOM
		var lods: Array = kinds[k]["lods"]
		mm.mesh = lods[mini(lod, lods.size() - 1)]
		mm.instance_count = buf.size() / stride
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		# The buffer's first origin gives the tile's ground height without another query.
		var y := buf[7]
		var h := float(layer["height"])
		mmi.custom_aabb = AABB(Vector3(float(key.x) * tile - h * 0.3, y - 30.0, float(key.y) * tile - h * 0.3),
				Vector3(tile + h * 0.6, h + 60.0, tile + h * 0.6))
		mmi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod < int(layer["shadow_lods"])
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		mmi.set_instance_shader_parameter(&"lod_in", lo)
		mmi.set_instance_shader_parameter(&"lod_out", hi)
		(layer["holder"] as Node3D).add_child(mmi)
		mmis.append(mmi)
	return mmis


const FAR_CELL := 512.0


## The trees beyond the near tiles, as impostors: the double cross from `radius`
## out to `cross_reach`, billboards beyond, merged per kind within each FAR_CELL
## square. A tile in the band round either distance goes into both sides of it,
## and the shader hands over between them plant by plant.
func _repack_far(layer: Dictionary, at: Vector3, radius: float) -> void:
	var tile := float(layer["tile"])
	var cross_reach := float(layer["cross_reach"])
	var kinds: Array = layer["kinds"]
	var cache: Dictionary = layer["cache"]
	var packed := {}          # Vector3i(cell x, cell z, kind * 2 + board) -> buffer
	for key in cache:
		var span := _tile_span(layer, key, at)
		var cx := int(floor((float(key.x) + 0.5) * tile / FAR_CELL))
		var cz := int(floor((float(key.y) + 0.5) * tile / FAR_CELL))
		var bufs: Array = cache[key]
		for board in 2:
			# A tile's width of slack either way: this is only redone when the camera
			# crosses into another tile.
			if board == 0 and (span.y < radius * (1.0 - LOD_BAND) - tile or span.x > cross_reach * (1.0 + LOD_BAND) + tile):
				continue
			if board == 1 and span.y < cross_reach * (1.0 - LOD_BAND) - tile:
				continue
			for k in kinds.size():
				var from: PackedFloat32Array = bufs[k]
				if from.is_empty():
					continue
				var slot := Vector3i(cx, cz, k * 2 + board)
				var into: PackedFloat32Array = packed.get(slot, PackedFloat32Array())
				into.append_array(from)
				packed[slot] = into
	var far: Dictionary = layer["far"]
	var mms: Dictionary = far["mms"]
	for slot in mms:
		var mmi: MultiMeshInstance3D = mms[slot]
		if not packed.has(slot):
			mmi.multimesh.instance_count = 0
		if slot.z % 2 == 0:
			mmi.set_instance_shader_parameter(&"lod_in", radius)
	for slot in packed:
		var mmi: MultiMeshInstance3D = mms.get(slot)
		if mmi == null:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = kinds[slot.z / 2]["board" if slot.z % 2 == 1 else "cross"]
			mmi = MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.custom_aabb = AABB(Vector3(slot.x * FAR_CELL - 30.0, -20.0, slot.y * FAR_CELL - 30.0),
					Vector3(FAR_CELL + 60.0, 140.0, FAR_CELL + 60.0))
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.set_instance_shader_parameter(&"lod_in", cross_reach if slot.z % 2 == 1 else radius)
			mmi.set_instance_shader_parameter(&"lod_out", 0.0 if slot.z % 2 == 1 else cross_reach)
			(far["holder"] as Node3D).add_child(mmi)
			mms[slot] = mmi
		var buf: PackedFloat32Array = packed[slot]
		mmi.multimesh.instance_count = buf.size() / STRIDE
		mmi.multimesh.buffer = buf
