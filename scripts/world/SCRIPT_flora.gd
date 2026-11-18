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
var _prefill_keys: Array[Vector2i] = []
var _prefilled := false
var _scale := 1.0
# The islet in the mere: wooded to its shore, with a clearing in the middle for the
# sword in the stone.
var _islet := Vector2.ZERO
var _islet_radius := 0.0
var _clearing := SwordStone.MEADOW


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
	_islet_radius = float(_field.get("flow_lagoon_islet")) * 0.86 if _field.get("flow_lagoon_islet") != null else 0.0
	_build_layers()


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
		for i in 3:
			var m := _mesh_of("res://assets/fir/%s/%s_lod%d.gltf" % [fir, fir, i])
			m.surface_set_material(0, bark)
			m.surface_set_material(1, needles if i == 0 else boughs)
			lods.append(m)
		var atlas := "res://assets/fir/textures/impostors/%s_impostor_" % fir
		var cross := _mesh_of("res://assets/fir/%s/%s_lod3_cross.gltf" % [fir, fir])
		cross.surface_set_material(0, _shader_mat("res://shaders/SHADER_impostor.gdshader", {
			"albedo_tex": load(atlas + "basecolor.png"),
			"tint": Color(0.6, 0.76, 0.7)}))
		var board := _mesh_of("res://assets/fir/%s/%s_lod4_billboard.gltf" % [fir, fir])
		board.surface_set_material(0, _shader_mat("res://shaders/SHADER_impostor.gdshader", {
			"albedo_tex": load(atlas + "basecolor.png"),
			"tint": Color(0.6, 0.76, 0.7), "billboard": true}))
		tree_kinds.append({"lods": lods, "cross": cross, "board": board})
	_layers.append({
		"name": "trees", "tile": 32.0, "radius": 135.0 * _scale, "stride": STRIDE,
		"dists": [20.0 * _scale, 52.0 * _scale], "shadow_lods": 3 if quality > 0 else 2,
		"kinds": tree_kinds, "place": _place_trees, "prefill": true,
		"cross_reach": 750.0 * _scale, "height": 50.0,
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
		"kinds": fern_kinds, "place": _place_ferns, "height": 2.0,
	})

	# --- boulders
	var rock: Material = load("res://materials/MAT_boulder.tres")
	var boulder_kinds: Array[Dictionary] = []
	for b in BOULDERS:
		var lods: Array = []
		for i in 3:
			var m := _mesh_of("res://assets/boulder/%s/%s_lod%d.gltf" % [b, b, i])
			m.surface_set_material(0, rock)
			lods.append(m)
		boulder_kinds.append({"lods": lods})
	_layers.append({
		"name": "boulders", "tile": 32.0, "radius": 380.0 * _scale, "stride": STRIDE,
		"dists": [26.0 * _scale, 90.0 * _scale], "shadow_lods": 2,
		"kinds": boulder_kinds, "place": _place_boulders, "height": 8.0,
	})

	# --- grass: crossed quads cut from the clump photos, one atlas, one draw per tile
	var reach := 62.0 * _scale
	var blades := _shader_mat("res://shaders/SHADER_foliage.gdshader", {
		"albedo_tex": load("res://assets/grass/textures/grass_atlas_basecolor.png"),
		"tint": Color(0.62, 0.7, 0.5), "alpha_cut": 0.36, "roughness": 0.7,
		"wind_bend": 0.16, "wind_flutter": 0.04, "atlas_columns": 3.0,
		"backlight": Color(0.035, 0.05, 0.015), "specular": 0.04, "thin_start": reach * 0.2, "thin_end": reach * 0.7, "thin_keep": 0.3,
		"fade_start": reach * 0.72, "fade_end": reach * 0.98})
	_layers.append({
		"name": "grass", "tile": 10.0, "radius": reach, "stride": STRIDE_CUSTOM,
		"dists": [], "shadow_lods": 0,
		"kinds": [{"lods": [_grass_mesh(blades)]}], "place": _place_grass, "height": 1.5,
	})

	for layer in _layers:
		layer["tiles"] = {}          # Vector2i -> {bufs, mmis, lod}
		layer["cache"] = {}          # Vector2i -> bufs, kept once placed
		layer["asked"] = {}
		layer["cam_tile"] = Vector2i(1 << 30, 0)
		var holder := Node3D.new()
		holder.name = String(layer["name"]).capitalize()
		add_child(holder)
		layer["holder"] = holder
		if layer.has("cross_reach"):
			layer["far"] = _far_instances(layer, holder)


## Two quads crossed at right angles, a metre tall and a metre wide, rooted at the
## origin, with one upward normal. The foliage shader draws both faces of each.
static func _grass_mesh(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := PI * 0.5 * k + 0.3
		var dx := Vector3(cos(a), 0, sin(a)) * 0.5
		var corners := [[-dx, Vector2(0, 1)], [dx, Vector2(1, 1)],
				[dx + Vector3.UP, Vector2(1, 0)], [-dx + Vector3.UP, Vector2(0, 0)]]
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


## MEADOWS: open ground among the trees, a few hundred metres across, where the
## forest stops and the grass grows thick. 0 in the wood, 1 well inside a meadow.
static func meadow(x: float, z: float) -> float:
	var n := _smooth_noise(x / 210.0, z / 210.0, 71) * 0.7 + _smooth_noise(x / 70.0, z / 70.0, 72) * 0.3
	return smoothstep(0.56, 0.66, n)


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
			if float(s.get("slope", 0.0)) > 0.4:
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
			if _hash(cx, cz, 25) > (drift - 0.28) * 1.5 * density:
				continue
			var x := x0 + (float(ix) + _hash(cx, cz, 26)) * grid
			var z := z0 + (float(iz) + _hash(cx, cz, 27)) * grid
			# A few ferns stray into the meadow's edge; none in its middle.
			if Vector2(x, z).distance_to(_islet) < _clearing * (0.55 + 0.45 * _hash(cx, cz, 32)):
				continue
			var s := f.sample(x, z)
			if not bool(s.get("on_land", false)):
				continue
			var surface := String(s.get("surface", ""))
			if surface == "rock" or surface == "sand":
				continue
			if float(s.get("slope", 0.0)) > 0.6 or float(s.get("flow_weight", 0.0)) > 0.4 \
					or float(s.get("flatten", 0.0)) > 0.25:
				continue
			if _hash(cx, cz, 28) > 0.3 + 0.7 * float(s.get("forest", 0.0)):
				continue
			var kind: int = kinds[0] if _hash(cx, cz, 29) < 0.6 else kinds[1]
			var size := 0.75 + 0.6 * _hash(cx, cz, 30)
			var basis := Basis(Vector3.UP, _hash(cx, cz, 31) * TAU).scaled(Vector3.ONE * size)
			_push(bufs[kind], basis, Vector3(x, float(s["height"]) - 0.03, z))
	return bufs


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
			var s := f.sample(x, z)
			if not bool(s.get("on_land", false)) or float(s.get("flatten", 0.0)) > 0.2:
				continue
			if Vector2(x, z).distance_to(_islet) < _clearing:
				continue
			var w: Color = s.get("weights", Color(1, 0, 0, 0))
			var flow := float(s.get("flow_weight", 0.0))
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
	return bufs


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
			if _hash(cx, cz, 52) > want * patch * 0.8 * density:
				continue
			var x := x0 + (float(ix) + _hash(cx, cz, 53)) * grid
			var z := z0 + (float(iz) + _hash(cx, cz, 54)) * grid
			var y := f.height_at(x, z, float(s["height"]))
			var variant := float(int(_hash(cx, cz, 55) * 3.0) % 3)
			var tall := 0.45 + 0.55 * _hash(cx, cz, 56)
			var wide := tall * (1.0 if variant < 0.5 else (1.2 if variant < 1.5 else 1.45))
			var basis := Basis(Vector3.UP, _hash(cx, cz, 57) * TAU).scaled(Vector3(wide, tall, wide))
			_push(buf, basis, Vector3(x, y - 0.03, z))
			buf.append_array([variant, _hash(cx, cz, 58), _hash(cx, cz, 59), 0.0])
	return [buf]


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
	_done_mutex.lock()
	_done.append([li, key, bufs])
	_done_mutex.unlock()


func _prefill_one(i: int) -> void:
	_work(0, _prefill_keys[i])


# Leaving while the trees are still being placed: let the workers finish first, or
# they run on into a node that is gone.
func _exit_tree() -> void:
	if _prefill_group >= 0 and not _prefilled:
		WorkerThreadPool.wait_for_group_task_completion(_prefill_group)


# The loading cover's hooks: place every tree on the island before the first frame.
func prefill_covered() -> void:
	pass


func prefill_step() -> bool:
	if _prefilled or _layers.is_empty():
		return true
	if _prefill_group < 0:
		var tile := float(_layers[0]["tile"])
		var n := int(ceil(_extent / tile))
		for z in range(-n, n):
			for x in range(-n, n):
				var c := Vector2((float(x) + 0.5) * tile, (float(z) + 0.5) * tile)
				if c.length() < _extent + tile:
					_prefill_keys.append(Vector2i(x, z))
		_prefill_group = WorkerThreadPool.add_group_task(_prefill_one, _prefill_keys.size(), -1, false, "flora trees")
		return false
	if not WorkerThreadPool.is_group_task_completed(_prefill_group):
		return false
	WorkerThreadPool.wait_for_group_task_completion(_prefill_group)
	_drain(1 << 30)
	_prefilled = true
	var total := 0
	for bufs in (_layers[0]["cache"] as Dictionary).values():
		for b in bufs:
			total += (b as PackedFloat32Array).size() / STRIDE
	print("[flora] %d trees placed in %d tiles" % [total, _prefill_keys.size()])
	return true


func prefill_ratio() -> float:
	if _prefilled:
		return 1.0
	return 0.0 if _prefill_group < 0 else 0.5


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
		layer["cam_tile"] = Vector2i(1 << 30, 0)       # look again: a tile arrived


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _layers.is_empty():
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


func _update_layer(li: int, at: Vector3) -> void:
	var layer := _layers[li]
	var tile := float(layer["tile"])
	var cam_tile := Vector2i(int(floor(at.x / tile)), int(floor(at.z / tile)))
	var tiles: Dictionary = layer["tiles"]
	var moved: bool = cam_tile != layer["cam_tile"]
	if moved:
		layer["cam_tile"] = cam_tile
		var radius := float(layer["radius"])
		# High above the island nothing near the ground is near the camera.
		if at.y > radius + float(layer["height"]) + 60.0:
			radius = 0.0
		var cache: Dictionary = layer["cache"]
		var asked: Dictionary = layer["asked"]
		var reach := int(ceil(radius / tile)) + 1
		var wanted := {}
		if radius > 0.0:
			for z in range(cam_tile.y - reach, cam_tile.y + reach + 1):
				for x in range(cam_tile.x - reach, cam_tile.x + reach + 1):
					var key := Vector2i(x, z)
					if _tile_distance(key, tile, at) > radius:
						continue
					if Vector2((float(x) + 0.5) * tile, (float(z) + 0.5) * tile).length() > _extent + tile:
						continue
					wanted[key] = true
					if tiles.has(key):
						continue
					if cache.has(key):
						_open_tile(layer, key, cache[key])
					elif not asked.has(key) and not layer.get("prefill", false):
						asked[key] = true
						WorkerThreadPool.add_task(_work.bind(li, key))
		for key in tiles.keys():
			if not wanted.has(key):
				for mmi in tiles[key]["mmis"]:
					if mmi != null:
						mmi.queue_free()
				tiles.erase(key)
		if layer.has("far"):
			_repack_far(layer, wanted, at)
	# Level of detail, every frame: a comparison per tile and a mesh swap when it changes.
	var dists: Array = layer["dists"]
	var kinds: Array = layer["kinds"]
	var shadow_lods := int(layer["shadow_lods"])
	for key in tiles:
		var t: Dictionary = tiles[key]
		var d := _tile_distance(key, tile, at) + maxf(0.0, at.y - float(layer["height"])) * 0.5
		var lod := 0
		while lod < dists.size() and d > float(dists[lod]):
			lod += 1
		if lod == int(t["lod"]):
			continue
		t["lod"] = lod
		for k in kinds.size():
			var mmi: MultiMeshInstance3D = t["mmis"][k]
			if mmi == null:
				continue
			var lods: Array = kinds[k]["lods"]
			mmi.multimesh.mesh = lods[mini(lod, lods.size() - 1)]
			mmi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod < shadow_lods
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _open_tile(layer: Dictionary, key: Vector2i, bufs: Array) -> void:
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
		mm.mesh = lods[lods.size() - 1]
		mm.instance_count = buf.size() / stride
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		# The buffer's first origin gives the tile's ground height without another query.
		var y := buf[7]
		var h := float(layer["height"])
		mmi.custom_aabb = AABB(Vector3(float(key.x) * tile - h * 0.3, y - 30.0, float(key.y) * tile - h * 0.3),
				Vector3(tile + h * 0.6, h + 60.0, tile + h * 0.6))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(layer["holder"] as Node3D).add_child(mmi)
		mmis.append(mmi)
	(layer["tiles"] as Dictionary)[key] = {"mmis": mmis, "lod": -1}


const FAR_CELL := 512.0


## Everything outside the near tiles, as impostors: crossed planes out to
## `cross_reach`, billboards beyond, merged per kind within each FAR_CELL square.
func _repack_far(layer: Dictionary, near: Dictionary, at: Vector3) -> void:
	var tile := float(layer["tile"])
	var cross_reach := float(layer["cross_reach"])
	var kinds: Array = layer["kinds"]
	var cache: Dictionary = layer["cache"]
	var lift := maxf(0.0, at.y - 80.0)
	var packed := {}          # Vector3i(cell x, cell z, kind * 2 + board) -> buffer
	for key in cache:
		if near.has(key):
			continue
		var bufs: Array = cache[key]
		var board := 0 if _tile_distance(key, tile, at) + lift < cross_reach else 1
		var cx := int(floor((float(key.x) + 0.5) * tile / FAR_CELL))
		var cz := int(floor((float(key.y) + 0.5) * tile / FAR_CELL))
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
		if not packed.has(slot):
			(mms[slot] as MultiMesh).instance_count = 0
	for slot in packed:
		var mm: MultiMesh = mms.get(slot)
		if mm == null:
			mm = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = kinds[slot.z / 2]["board" if slot.z % 2 == 1 else "cross"]
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.custom_aabb = AABB(Vector3(slot.x * FAR_CELL - 30.0, -20.0, slot.y * FAR_CELL - 30.0),
					Vector3(FAR_CELL + 60.0, 140.0, FAR_CELL + 60.0))
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(far["holder"] as Node3D).add_child(mmi)
			mms[slot] = mm
		var buf: PackedFloat32Array = packed[slot]
		mm.instance_count = buf.size() / STRIDE
		mm.buffer = buf
