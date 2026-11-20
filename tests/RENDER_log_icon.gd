extends SceneTree

# THE LOG'S INVENTORY ICON: the game's own log mesh, lit and photographed on a
# clear background, written to assets/ui/item_log.png.
#
#   godot --path . --resolution 512x512 --script res://tests/RENDER_log_icon.gd

var _frames := 0


func _initialize() -> void:
	root.transparent_bg = true
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.55
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
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.72
	cam.transform = Transform3D(Basis(), Vector3(0.0, 1.25, 3.0)).looking_at(Vector3.ZERO)
	root.add_child(cam)
	cam.current = true


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 2:
		# (Not in _initialize: the node's _ready, which makes the materials, has to
		# have run before the mesh is asked for.)
		var wood := Woodcutting.new()
		root.add_child(wood)
		var log := MeshInstance3D.new()
		log.mesh = wood._log_mesh(0.36)
		# Lying down, an end turned towards the camera so the rings read.
		log.rotation_degrees = Vector3(0.0, -38.0, 90.0)
		root.add_child(log)
	if _frames == 40:
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		# Cropped to the log itself and squared off, so it fills its slot whatever
		# shape the window turned out to be.
		var used := img.get_used_rect()
		var side := maxi(used.size.x, used.size.y) + 16
		var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
		square.blit_rect(img, used, (Vector2i(side, side) - used.size) / 2)
		img = square
		img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://assets/ui/item_log.png")
		print("icon: written")
		quit(0)
		return true
	return false
