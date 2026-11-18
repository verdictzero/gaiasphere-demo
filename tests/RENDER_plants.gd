extends SceneTree

# THE PLANTS ON A TABLE: one fir at every level of detail, side by side, under the
# project's own sky and shaders, then the ferns the same way. It is how a change
# to a mesh, an impostor or a plant shader is checked without building the island.
#
#   godot --path . --script res://tests/RENDER_plants.gd -- --out=/some/folder [--fir=fir_tall_a] [--hour=15]

var _out := "user://plants"
var _fir := "fir_tall_a"
var _hour := 15.5
var _frames := 0
var _cam: Camera3D
var _flora: Flora


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--fir="):
			_fir = a.substr(6)
		elif a.begins_with("--hour="):
			_hour = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	var enviro := Enviro.new()
	enviro.hour = _hour
	enviro.advance = false
	enviro.weather = "clear"
	enviro.god_rays = false
	world.add_child(enviro)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.13, 0.14, 0.1)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)

	# Borrow the game's own materials by letting Flora build its layers with no world.
	_flora = Flora.new()
	_flora.set_process(false)
	world.add_child(_flora)
	_flora._build_layers()
	var trees: Dictionary = _flora._layers[0]
	var kind: Dictionary = trees["kinds"][Flora.FIRS.find(_fir)]
	var meshes: Array = (kind["lods"] as Array).duplicate()
	meshes.append(kind["cross"])
	meshes.append(kind["board"])
	for i in meshes.size():
		# Through a MultiMesh, as the game draws them.
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[i]
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, 0.6), Vector3((i - 2) * 15.0, 0, 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if i >= 3:        # impostors do not cast shadows in the game either
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mmi)
	var ferns: Dictionary = _flora._layers[1]
	var fern_meshes: Array = ferns["kinds"][3]["lods"]
	for i in fern_meshes.size():
		var mi := MeshInstance3D.new()
		mi.mesh = fern_meshes[i]
		mi.position = Vector3((i - 1.5) * 3.0, 0, 300.0)
		world.add_child(mi)

	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.far = 2000.0
	world.add_child(_cam)
	_cam.look_at_from_position(Vector3(0.0, 13.0, 92.0), Vector3(0.0, 16.0, 0.0))
	_cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 14:
		root.get_texture().get_image().save_png(_out.path_join("fir_lods.png"))
		_cam.look_at_from_position(Vector3(8.0, 9.0, 16.0), Vector3(-15.0, 13.0, 0.0))
	elif _frames == 22:
		root.get_texture().get_image().save_png(_out.path_join("fir_lod1_close.png"))
		_cam.look_at_from_position(Vector3(0.0, 2.2, 308.5), Vector3(0.0, 0.4, 300.0))
	elif _frames == 30:
		root.get_texture().get_image().save_png(_out.path_join("fern_lods.png"))
		print("plants: ", _out)
		return true
	return false
