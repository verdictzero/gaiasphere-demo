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
	# THE SWELL. Still water rises and falls (SHADER_water), and the waterline has
	# to stand where the surface does. The surface is flat between its vertices,
	# so the shader is given the triangle of it the lens is over and the swell's
	# own settings, and works the height at each corner exactly as the surface's
	# shader does.
	var height := 0.0
	var surface := _water.material
	if surface != null:
		var lens := float(_mat.get_shader_parameter(&"lens"))
		var tri := _water.lagoon_triangle(p - cam.global_basis.z * lens)
		if tri.size() == 3:
			# (A value the material leaves alone reads as null: the shader's own then.)
			var read := func(what: StringName, otherwise: float) -> float:
				var v: Variant = surface.get_shader_parameter(what)
				return float(v) if v != null else otherwise
			height = read.call(&"wave_height", 0.42)
			_mat.set_shader_parameter(&"swell_a", tri[0])
			_mat.set_shader_parameter(&"swell_b", tri[1])
			_mat.set_shader_parameter(&"swell_c", tri[2])
			var centre: Variant = surface.get_shader_parameter(&"mere_centre")
			_mat.set_shader_parameter(&"swell_centre", centre if centre != null else Vector2.ZERO)
			_mat.set_shader_parameter(&"swell_noise", surface.get_shader_parameter(&"swell_noise"))
			_mat.set_shader_parameter(&"swell_length", read.call(&"wave_length", 13.0))
			_mat.set_shader_parameter(&"swell_pace", read.call(&"wave_pace", 2.6))
	_mat.set_shader_parameter(&"swell_height", height)
	# (Shown while the lens could be under the highest the swell ever stands.)
	return p.y + lens_low(cam) < y + height * 0.65 * 3.0 + 0.02


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
