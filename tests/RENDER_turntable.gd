extends SceneTree

# A TURNTABLE: one model, lit by nothing but a photographed sky, with the camera
# going once round it. For a film of it, run under Godot's film writer:
#
#   godot --path . --resolution 1280x720 --fixed-fps 30 --write-movie /some/folder/turn.avi \
#         --script res://tests/RENDER_turntable.gd -- --sky=/path/to/sky.hdr [--model=res://...glb] [--seconds=10]

var _model := "res://assets/berry_bush/viburnum_bush.glb"
var _sky := ""
var _seconds := 10.0
var _t := 0.0
var _cam: Camera3D
var _middle := Vector3.ZERO
var _reach := 5.0
var _frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sky="):
			_sky = a.trim_prefix("--sky=")
		elif a.begins_with("--model="):
			_model = a.trim_prefix("--model=")
		elif a.begins_with("--seconds="):
			_seconds = float(a.trim_prefix("--seconds="))
	var env := Environment.new()
	var img := Image.load_from_file(_sky) if _sky != "" else null
	if img != null:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = ImageTexture.create_from_image(img)
		var sky := Sky.new()
		sky.sky_material = pano
		sky.radiance_size = Sky.RADIANCE_SIZE_256
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.ambient_light_energy = 1.0
	else:
		push_warning("turntable: no sky picture (--sky=), lit flat")
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.4, 0.45, 0.5)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.8, 0.85, 0.9)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var thing: Node3D = (load(_model) as PackedScene).instantiate()
	if _model.contains("berry_bush"):
		# A berry bush is drawn in the game by its own shader, as one of a MultiMesh
		# (SCRIPT_berry_bushes.gd): shown the same way here, all of it grown.
		var mesh: Mesh = (thing.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D())
		mm.set_instance_custom_data(0, Color(1, 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = BerryBushes._bush_material(mesh)
		root.add_child(mmi)
		thing.visible = false
	root.add_child(thing)
	# How big it is, to stand off from it by.
	var box := AABB()
	var first := true
	for mi in thing.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	_middle = box.get_center()
	_reach = box.size.length() * 0.95
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = box.size.length() * 1.6
	disc.bottom_radius = disc.top_radius
	disc.height = 0.02
	var matte := StandardMaterial3D.new()
	matte.albedo_color = Color(0.32, 0.33, 0.3)
	matte.roughness = 1.0
	disc.material = matte
	ground.mesh = disc
	ground.position.y = box.position.y - 0.01
	root.add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	root.add_child(_cam)
	_cam.current = true


func _process(delta: float) -> bool:
	_frames += 1
	if _frames > 2:
		_t += delta
	var a := TAU * _t / _seconds
	_cam.look_at_from_position(_middle + Vector3(sin(a) * _reach, _reach * 0.22, cos(a) * _reach), _middle)
	if _t >= _seconds:
		quit(0)
		return true
	return false
