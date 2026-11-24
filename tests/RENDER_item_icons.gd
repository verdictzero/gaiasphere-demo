extends SceneTree

# THE INVENTORY ICONS: the game's own log, axe and sword, each lit and
# photographed on a clear background, written to assets/ui/item_<name>.png.
#
#   godot --path . --resolution 768x768 --script res://tests/RENDER_item_icons.gd

var _frames := 0
var _cam: Camera3D
var _subject: Node3D
var _queue: Array = ["stairs"]
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
		"pickaxe":
			var model: Node3D = (load("res://assets/pickaxe/pickaxe.glb") as PackedScene).instantiate()
			var stand := Basis(Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0)).scaled(Vector3.ONE * SwordPlay.PICK_SCALE)
			model.transform = Transform3D(stand, -(stand * Vector3(0.0, 0.0, 8.5)))
			var turn := Node3D.new()
			turn.add_child(model)
			turn.rotation_degrees = Vector3(0.0, 100.0, -42.0)
			_subject.add_child(turn)
			span = 1.15
		"stone":
			# The same broken rock a boulder comes apart into (SCRIPT_mining.gd).
			var stone := MeshInstance3D.new()
			stone.mesh = (load("res://assets/boulder/boulder_c/boulder_c_lod1.gltf") as PackedScene).instantiate().find_children("*", "MeshInstance3D", true, false)[0].mesh
			var box := stone.mesh.get_aabb()
			stone.transform = Transform3D(Basis(), -box.get_center())
			var rock := StandardMaterial3D.new()
			rock.albedo_texture = load("res://textures/polyhaven/lichen_rock_basecolor.jpg")
			rock.albedo_color = Color(1.12, 1.1, 1.08)
			rock.normal_enabled = true
			rock.normal_texture = load("res://textures/polyhaven/lichen_rock_normal.jpg")
			rock.orm_texture = load("res://textures/polyhaven/lichen_rock_orm.jpg")
			rock.uv1_triplanar = true
			rock.uv1_scale = Vector3.ONE * (1.2 / box.get_longest_axis_size())
			stone.material_override = rock
			var turn := Node3D.new()
			turn.add_child(stone)
			turn.rotation_degrees = Vector3(0.0, 35.0, 0.0)
			_subject.add_child(turn)
			span = box.get_longest_axis_size() * 1.15
		"wall", "doorway", "floor", "roof", "gable", "foundation", "steps", "stairs":
			# A piece of the building kit, turned three-quarters on.
			var files := {"wall": ["plank_kit/wall_a"], "doorway": ["plank_kit/doorway_a", "plank_kit/door_a"],
				"floor": ["plank_kit/floor_a"], "roof": ["plank_kit/roof_a"], "gable": ["plank_kit/gable_right_a"],
				"stairs": ["plank_kit/stairs_a"], "foundation": ["foundation/foundation_a"], "steps": ["foundation/steps_a"]}
			var turn := Node3D.new()
			var box := AABB()
			var first := true
			for file in files[what]:
				var piece: Node3D = (load("res://assets/build/%s_lod0.glb" % file) as PackedScene).instantiate()
				if String(file).ends_with("door_a"):
					piece.position = Vector3(-0.53, 0.03, 0.004)       # hung in its doorway (SCRIPT_door.gd)
					piece.rotation.y = 0.5
				turn.add_child(piece)
				for mi in piece.find_children("*", "MeshInstance3D", true, false):
					var b: AABB = piece.transform * ((mi as MeshInstance3D).transform * (mi as MeshInstance3D).mesh.get_aabb())
					box = b if first else box.merge(b)
					first = false
			if what == "steps":
				box.position.y = 0.0                                   # (they carry on a metre underground)
				box.size.y = 1.0
			for piece in turn.get_children():
				(piece as Node3D).position -= box.get_center()
			turn.rotation_degrees = Vector3(0.0, {"floor": 28.0, "steps": 40.0, "foundation": 36.0, "roof": 150.0, "stairs": 38.0}.get(what, 30.0), 0.0)
			_subject.add_child(turn)
			if what == "steps":
				# Standing on nothing, the sunk metre would show: a card hides it.
				pass
			span = box.size.length() * 0.95
		"katana":
			var model: Node3D = (load("res://assets/katana/katana.glb") as PackedScene).instantiate()
			model.transform = Transform3D(Basis().scaled(Vector3.ONE * SwordPlay.KATANA_SCALE), Vector3(0, -60.0 * SwordPlay.KATANA_SCALE, 0))
			var turn := Node3D.new()
			turn.add_child(model)
			turn.rotation_degrees = Vector3(0.0, 90.0, -45.0)
			_subject.add_child(turn)
			span = 1.12
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
		if "log" in _queue:
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
