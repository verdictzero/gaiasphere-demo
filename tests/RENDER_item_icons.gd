extends SceneTree

# THE INVENTORY ICONS: the game's own log, axe and sword, each lit and
# photographed on a clear background, written to assets/ui/item_<name>.png.
#
#   godot --path . --resolution 768x768 --script res://tests/RENDER_item_icons.gd

var _frames := 0
var _cam: Camera3D
var _subject: Node3D
var _queue: Array = ["log", "axe", "sword"]
var _wood: Woodcutting


func _initialize() -> void:
	root.transparent_bg = true
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.96, 0.9)
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.7, 0.8, 1.0)
	root.add_child(rim)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.transform = Transform3D(Basis(), Vector3(0.0, 1.25, 3.0)).looking_at(Vector3.ZERO)
	root.add_child(_cam)
	_cam.current = true


## The next thing to photograph, turned to show itself and centred.
func _stage(what: String) -> void:
	if _subject != null:
		_subject.queue_free()
	_subject = Node3D.new()
	root.add_child(_subject)
	var span := 1.7
	match what:
		"log":
			var log := MeshInstance3D.new()
			log.mesh = _wood._log_mesh(0.36)
			# Lying down, an end turned towards the camera so the rings read.
			log.rotation_degrees = Vector3(0.0, -38.0, 90.0)
			_subject.add_child(log)
		"axe":
			var model: Node3D = (load("res://assets/axe/axe.glb") as PackedScene).instantiate()
			var stand := Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)).scaled(Vector3.ONE * SwordPlay.AXE_SCALE)
			model.transform = Transform3D(stand, -(stand * Vector3(0.29, 0.0, 5.9)))
			var turn := Node3D.new()
			turn.add_child(model)
			# Leaning across the frame, the flat of the head to the camera.
			turn.rotation_degrees = Vector3(0.0, 100.0, -42.0)
			_subject.add_child(turn)
			span = 1.0
		"sword":
			var scene: Node3D = (load("res://assets/sword_in_stone/sword_in_stone.gltf") as PackedScene).instantiate()
			var sword := scene.find_child("sword", true, false) as MeshInstance3D
			sword.get_parent().remove_child(sword)
			scene.free()
			var box := sword.mesh.get_aabb()
			sword.transform = Transform3D(Basis(), -box.get_center())
			var turn := Node3D.new()
			turn.add_child(sword)
			turn.rotation_degrees = Vector3(0.0, 0.0, -45.0)
			_subject.add_child(turn)
			span = box.get_longest_axis_size() * 1.05
	_cam.size = span


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 2:
		# (Not in _initialize: the node's _ready, which makes the materials, has to
		# have run before the mesh is asked for.)
		_wood = Woodcutting.new()
		root.add_child(_wood)
	if _frames < 3:
		return false
	if (_frames - 3) % 40 == 0:
		if _queue.is_empty():
			quit(0)
			return true
		_stage(_queue[0])
	elif (_frames - 3) % 40 == 39:
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		# Cropped to the thing itself and squared off, so it fills its slot whatever
		# shape the window turned out to be.
		var used := img.get_used_rect()
		var side := maxi(used.size.x, used.size.y) + 16
		var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
		square.blit_rect(img, used, (Vector2i(side, side) - used.size) / 2)
		square.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		square.save_png("res://assets/ui/item_%s.png" % _queue[0])
		print("icon: ", _queue.pop_front())
	return false
