class_name UnderwaterView
extends MeshInstance3D
# UNDER THE WATER'S PASS (the user: "Add underwater shader with waterline half in
# half out effect"): a quad over the whole screen drawn by SHADER_underwater, the
# shader says how. This keeps it with whichever camera is drawing, tells it the
# height of the water over the eye (`RiverWater.world_level_at`), and shows it
# only while some of the picture is under: the eye in a river, a crater lake or
# the lagoon, and the lowest corner of the lens under the surface's highest wave.
# Hidden, it costs nothing, not even the copy of the screen it reads. Never during
# a fight, as the ruins' heat haze is not: the battle has its own screen.
#
# On foot the eye stands 1.6 m over the ground, and a moving river is 1.6 m deep
# down its middle: wade in and the waterline is across the middle of the screen.

## The scene's RiverWater, whose surface this reads.
@export var water_path: NodePath
## No eye further under than this, metres, is in the water: the deepest of it is
## the lagoon's 2.2 m. Below that it is under the ground (the ruins run under the
## rivers), where the water over the map is nothing to do with it.
@export var max_depth := 200.0

var _water: RiverWater = null
var _mat: ShaderMaterial = null


func _ready() -> void:
	_water = get_node_or_null(water_path) as RiverWater
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	mesh = q
	_mat = material_override as ShaderMaterial
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Never culled: the shader puts it over the screen wherever it stands.
	extra_cull_margin = 16384.0
	visible = false


func _process(_delta: float) -> void:
	visible = _wanted()
	# The sky's lens flare and bloom have no business under water.
	var enviro := get_node_or_null(^"../Enviro")
	if enviro != null:
		enviro.set(&"submerged", visible)


# Whether any of the picture is under, and the shader told where the water is.
func _wanted() -> bool:
	if _water == null or _mat == null:
		return false
	var st := get_node_or_null(^"/root/RpgState")
	if st != null and bool(st.get("in_battle")):
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return false
	var p := cam.global_position
	var y := _water.world_level_at(p)
	if is_nan(y) or p.y < y - max_depth:
		return false
	global_position = p
	_mat.set_shader_parameter(&"water_y", y)
	return p.y + lens_low(cam) < y + float(_mat.get_shader_parameter(&"wave_height")) + 0.01


## How far under the eye the lens's lowest corner is, metres (negative: under):
## the frustum's corners at `lens` in front of the eye.
func lens_low(cam: Camera3D) -> float:
	var lens := float(_mat.get_shader_parameter(&"lens")) if _mat != null else 0.45
	var size := cam.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var tv := tan(deg_to_rad(cam.fov) * 0.5)
	var th := tv * aspect
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		th = tv
		tv = th / aspect
	var b := cam.global_basis
	return lens * (-b.z.y - absf(b.y.y) * tv - absf(b.x.y) * th)
