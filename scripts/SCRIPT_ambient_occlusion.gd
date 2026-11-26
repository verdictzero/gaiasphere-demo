class_name AmbientOcclusion
extends MeshInstance3D

# AMBIENT OCCLUSION over the whole frame (SHADER_ambient_occlusion.gdshader): a
# screen-filling quad drawn after everything solid and before anything
# see-through, darkening creases and the feet of things by what the depth
# buffer shows round each pixel. Three methods (fast, SSAO, HBAO) and a dozen
# settings, all of them the options panel's (SCRIPT_options_menu.gd).
#
# The cheapest method, FAST, is what it starts on: the user's rule ("most
# efficient wins").

const METHODS := ["OFF", "FAST", "SSAO", "HBAO"]
## Every setting, as the shader has it to begin with.
const DEFAULTS := {
	"method": 1.0, "intensity": 1.0, "radius": 1.0, "radius_growth": 0.02, "power": 1.5, "bias": 0.03,
	"falloff": 1.0, "max_distance": 160.0, "floor_light": 0.15, "samples": 8.0, "directions": 6.0, "steps": 4.0,
}

var values := DEFAULTS.duplicate()
var _mat: ShaderMaterial


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/SHADER_ambient_occlusion.gdshader")
	# Before the water, the particles and the rest of what is see-through.
	_mat.render_priority = -100
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh = quad
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	for key in values:
		put(key, float(values[key]))


func put(key: String, value: float) -> void:
	values[key] = value
	if key in ["method", "samples", "directions", "steps"]:
		_mat.set_shader_parameter(key, int(round(value)))
	else:
		_mat.set_shader_parameter(key, value)
	if key == "method":
		visible = int(round(value)) > 0
