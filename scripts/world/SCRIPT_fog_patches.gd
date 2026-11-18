class_name FogPatches
extends Node3D

# PATCHES OF FOG THAT HANG IN THE WOODS. The Environment's fog is even: it thickens
# with distance and pools in low ground. These are the pieces of it that have
# shape: banks a few tens of metres across that sit between the trunks and over
# the water, drift, and catch the low sun. Each is a couple of soft camera-facing
# sheets (SHADER_fog_patch); one MultiMesh holds every bank near the camera and is
# re-laid when the camera crosses into another cell.

@export var world_path: NodePath = ^"../IslandWorld"
@export var enviro_path: NodePath = ^"../Enviro"
## Metres between places a bank might be.
@export var cell := 70.0
@export var reach := 340.0
## Share of cells that hold a bank in clear weather; fog raises it.
@export_range(0.0, 1.0) var chance := 0.35
@export var patch_seed := 152

var _world: Node
var _enviro: Enviro
var _mm: MultiMesh
var _mat: ShaderMaterial
var _cell := Vector2i(1 << 30, 0)


func _ready() -> void:
	_world = get_node_or_null(world_path)
	_enviro = get_node_or_null(enviro_path) as Enviro
	var noise := NoiseTexture2D.new()
	noise.width = 256
	noise.height = 256
	noise.seamless = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.012
	fn.fractal_octaves = 4
	noise.noise = fn
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/SHADER_fog_patch.gdshader")
	_mat.set_shader_parameter("noise_tex", noise)
	_mat.set_shader_parameter("far_start", reach * 0.75)
	_mat.set_shader_parameter("far_end", reach)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = _mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = quad
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-4000, -100, -4000), Vector3(8000, 400, 8000))
	add_child(mmi)


static func _hash(x: int, z: int, salt: int) -> float:
	var h := (x * 73856093) ^ (z * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFFFF) / float(0x1000000)


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _world == null:
		return
	# Thicker weather, more and denser banks.
	var mist := 0.0
	if _enviro != null:
		mist = clampf(_enviro.fog_amount(), 0.0, 1.0)
	_mat.set_shader_parameter("opacity", lerpf(0.3, 0.62, mist))
	var at := cam.global_position
	var here := Vector2i(int(floor(at.x / cell)), int(floor(at.z / cell)))
	if here == _cell:
		return
	_cell = here
	var want := lerpf(chance, minf(1.0, chance * 2.2), mist)
	var n := int(ceil(reach / cell))
	var buf := PackedFloat32Array()
	for z in range(here.y - n, here.y + n + 1):
		for x in range(here.x - n, here.x + n + 1):
			if _hash(x, z, patch_seed) > want:
				continue
			var px := (float(x) + _hash(x, z, 1)) * cell
			var pz := (float(z) + _hash(x, z, 2)) * cell
			var ground := float(_world.call(&"height_at", Vector3(px, 0.0, pz), -1e9))
			if ground < -1e8:
				continue
			# A bank is two or three sheets, offset, so it has depth as you pass it.
			for s in 2 + int(_hash(x, z, 3) * 2.0):
				var wide := lerpf(34.0, 78.0, _hash(x, z, 10 + s))
				var tall := lerpf(7.0, 15.0, _hash(x, z, 20 + s))
				var ox := (_hash(x, z, 30 + s) - 0.5) * 30.0
				var oz := (_hash(x, z, 40 + s) - 0.5) * 30.0
				var y := ground + tall * 0.45 + _hash(x, z, 50 + s) * 5.0
				buf.append_array([wide, 0, 0, px + ox, 0, tall, 0, y, 0, 0, 1, pz + oz,
						_hash(x, z, 60 + s), 0, 0, 0])
	_mm.instance_count = buf.size() / 16
	if not buf.is_empty():
		_mm.buffer = buf
