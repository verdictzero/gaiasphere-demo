extends SceneTree

# THE BOULDERS ON A TABLE: every boulder shape under a plain sun, some of them
# tipped over or scaled, to check the rock shader and that its moss stays on top
# whatever way the instance is turned.
#
#   godot --path . --script res://tests/RENDER_boulders.gd -- --out=/some/folder

const NAMES := ["boulder_a", "boulder_b", "boulder_c", "boulder_d", "boulder_e"]

var _out := "user://boulders"
var _frames := 0


static func mesh_of(path: String) -> Mesh:
	var scene := (load(path) as PackedScene).instantiate()
	var found: Mesh = null
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		found = (n as MeshInstance3D).mesh
		break
	scene.free()
	return found


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.6
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.17, 0.12)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)

	var mat: Material = load("res://materials/MAT_boulder.tres")
	# Front row: upright, each LOD0. Back row: the same shapes tipped and scaled.
	for i in NAMES.size():
		for row in 2:
			var mi := MeshInstance3D.new()
			var lod: String = "lod0" if row == 0 else ["lod0", "lod1", "lod2", "lod0", "lod1"][i]
			mi.mesh = mesh_of("res://assets/boulder/%s/%s_%s.gltf" % [NAMES[i], NAMES[i], lod])
			mi.material_override = mat
			mi.position = Vector3((i - 2) * 3.2, 0.0, -row * 4.5)
			if row == 1:
				mi.rotation_degrees = Vector3(70.0 * (i % 2), 40.0 * i, 110.0 * ((i + 1) % 2))
				mi.scale = Vector3.ONE * (1.0 + 0.35 * i)
				mi.position.y = 0.6
			world.add_child(mi)

	var cam := Camera3D.new()
	cam.fov = 42.0
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 4.2, 11.5), Vector3(0.0, 0.6, -1.5))
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 12:
		var path := _out.path_join("boulders.png")
		root.get_texture().get_image().save_png(path)
		print("boulders: ", path)
		return true
	return false
