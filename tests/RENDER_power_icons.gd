extends SceneTree

# THE BAG'S PICTURES OF THE POWER PARTS: each as it stands, from above one corner,
# on nothing.
#
#   godot --path . --script res://tests/RENDER_power_icons.gd
# Writes assets/ui/item_<part>.png (256 square).

const ITEMS := ["solar_panel", "battery", "junction", "light_pole", "cable", "laser_ciws"]

var _i := 0
var _port: SubViewport
var _cam: Camera3D
var _model: Node3D
var _wait := 0


func _initialize() -> void:
	_port = SubViewport.new()
	_port.own_world_3d = true
	_port.transparent_bg = true
	_port.size = Vector2i(512, 512)
	_port.msaa_3d = Viewport.MSAA_4X
	_port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_port)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	_port.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 0.9
	key.rotation_degrees = Vector3(-40, 35, 0)
	_port.add_child(key)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_port.add_child(_cam)
	_next()


func _next() -> void:
	if _model != null:
		_model.free()
	var item: String = ITEMS[_i]
	if item == "cable":
		_model = Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = PowerKit.lods("plug_end")[0]
		_model.add_child(mi)
	else:
		_model = Power.model(item, true)
	_port.add_child(_model)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var mid := box.get_center()
	var away := Vector3(-0.75, 0.5, 1.0).normalized() if item != "cable" else Vector3(-0.8, 0.45, 0.9).normalized()
	_cam.size = box.size.length() * (0.92 if item != "light_pole" else 1.0)
	_cam.look_at_from_position(mid + away * 60.0, mid)
	_wait = 4


func _process(_d: float) -> bool:
	_wait -= 1
	if _wait > 0:
		return false
	var image := _port.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var used := image.get_used_rect()
	var side := maxi(used.size.x, used.size.y) + 24
	var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
	square.blit_rect(image, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
	square.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	square.save_png("res://assets/ui/item_%s.png" % ITEMS[_i])
	print("icon: %s" % ITEMS[_i])
	_i += 1
	if _i >= ITEMS.size():
		return true
	_next()
	return false
