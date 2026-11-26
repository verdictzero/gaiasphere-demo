extends SceneTree

# THE CLIFF BLOCK BY ITSELF, in the rock shader, from two sides: as handed over
# (left), at its first level of detail (1000 triangles, middle) and its second
# (700, right), with the baked edge wear and crevices on (top row) and off
# (bottom row). To renders/cliff_block.png.
#
#   godot --path . --script res://tests/RENDER_cliff_block.gd

var _n := 0


func _initialize() -> void:
	var r := Node3D.new()
	root.add_child(r)
	var terrain: ShaderMaterial = load("res://materials/MAT_terrain.tres")
	var block := Flora._mesh_of(CliffRocks.BLOCK) as ArrayMesh
	var meshes := [block, MeshLods.reduced(block, CliffRocks.BLOCK_LOD0), MeshLods.reduced(block, CliffRocks.BLOCK_LOD1)]
	for row in 2:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/SHADER_cliff_rock.gdshader")
		for p in ["ground_albedo", "ground_normal", "macro_noise"]:
			mat.set_shader_parameter(p, terrain.get_shader_parameter(p))
		mat.set_shader_parameter("top_start", 2.0)        # (no turf: the rock alone)
		mat.set_shader_parameter("top_full", 3.0)
		if row == 1:
			mat.set_shader_parameter("edge_wear", 0.0)
			mat.set_shader_parameter("crevice", 0.0)
		for i in meshes.size():
			var mi := MeshInstance3D.new()
			mi.mesh = meshes[i]
			mi.material_override = mat
			mi.position = Vector3((float(i) - 1.0) * 9.0, 5.5 - 11.0 * float(row), 0.0)
			mi.rotation.y = 0.6
			r.add_child(mi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	r.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.47, 0.5)
	r.add_child(env)
	var cam := Camera3D.new()
	r.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0, 32), Vector3.ZERO)
	cam.make_current()


func _process(_d: float) -> bool:
	_n += 1
	if _n == 8:
		root.get_viewport().get_texture().get_image().save_png("res://renders/cliff_block.png")
		return true
	return false
