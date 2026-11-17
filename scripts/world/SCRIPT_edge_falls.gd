class_name EdgeFalls
extends Node3D

# THE FALLS OFF THE EDGE: every moving river (`FlowTerrain`) that runs to the
# coast pours on off it, down the shoulder and the cliff wall under it: molten
# lava on island 004, glacier ice on island 005 (an icefall frozen down the
# wall). SHADERINC_edge_falls.gdshaderinc draws them in the terrain shader (the
# shoulder) and SHADER_cliff_wall.gdshader (the wall) from one list, which this
# hands both materials when the scene stands: each fall's bearing round the
# island's middle, its half-width, the lip's height (the island's base: the
# ground meets the wall there, `IslandField.flow_shore`) and how far out its
# mouth is. At most eight, the shaders' array. How they look (hot or cold, fast
# or still) is the materials' `edge_fall_*`.
#
# THE FIELD'S FRAME. The list is in it; the shaders draw in render space, so
# this writes the island's origin offset to both as `edge_fall_origin`, and
# again at every rebase (`origin_shiftable`), so the falls stay on their
# mouths wherever the floating origin is.

@export var world_path: NodePath

var _world: Node = null
var _mats: Array[ShaderMaterial] = []
var _origin := Vector3.ZERO
var _falls := PackedVector4Array()


func _ready() -> void:
	add_to_group("origin_shiftable")
	_world = get_node_or_null(world_path)
	if _world == null or not _world.has_method(&"get_field"):
		push_warning("edge_falls: no IslandWorld (set world_path)")
		return
	for k in ["terrain_material", "cliff_material"]:
		var m := _world.get(k) as ShaderMaterial
		if m != null:
			_mats.append(m)
	if _world.has_method(&"origin_offset"):
		_origin = _world.call(&"origin_offset")
	_publish_origin()
	var field: IslandField = _world.call(&"get_field")
	if field == null:
		return
	if not field._ready:
		field.prepare()
	var hub: IslandField.Island = field.island_in_cell(field.hub_cell())
	if hub != null:
		_publish(field, hub)


## The falls handed to the shaders: (bearing, half-width, lip height, the mouth's
## distance from the centre) each, in the field's frame.
func falls() -> PackedVector4Array:
	return _falls


func apply_origin_shift(shift: Vector3) -> void:
	_origin -= shift
	_publish_origin()


func _publish_origin() -> void:
	for m in _mats:
		m.set_shader_parameter(&"edge_fall_origin", _origin)


func _publish(field: IslandField, hub: IslandField.Island) -> void:
	_falls = PackedVector4Array()
	var flows := field.flows_for(hub)
	if flows != null:
		for r: FlowTerrain.River in flows.rivers:
			if not r.moving or r.toe or _falls.size() >= 8:
				continue
			var mouth := r.points[r.points.size() - 1]
			_falls.append(Vector4((mouth - hub.center).angle(), r.width[r.width.size() - 1],
					hub.base_y, mouth.distance_to(hub.center)))
	var arr: Array[Vector4] = []
	for i in range(8):
		arr.append(_falls[i] if i < _falls.size() else Vector4.ZERO)
	for m in _mats:
		m.set_shader_parameter(&"edge_falls", arr)
		m.set_shader_parameter(&"edge_fall_count", _falls.size())
		m.set_shader_parameter(&"edge_fall_center", hub.center)
