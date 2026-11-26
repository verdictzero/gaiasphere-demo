extends SceneTree

# THE GROUND AND A ROCK'S TOP, SIDE BY SIDE: flat patches of the terrain's shader
# (top row) and of the cliff rock's (bottom row, as a rock's top would be), open
# ground on the left and wooded on the right, to see that they are the same. Seen
# from 22 m (renders/ground_match_near.png) and from 300 m through a long lens
# (ground_match_far.png: past both of the far-off economies).
#
#   godot --path . --script res://tests/RENDER_ground_match.gd

var _n := 0
var _cam: Camera3D


func _quad(mat: Material, forest: float, x: float, r: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(-4, 0, -4), Vector3(4, 0, -4), Vector3(4, 0, 4), Vector3(-4, 0, -4), Vector3(4, 0, 4), Vector3(-4, 0, 4)]:
		st.set_normal(Vector3.UP)
		st.set_color(Color(1, 0, 0, 0))
		st.set_uv(Vector2(0, 0))
		st.set_uv2(Vector2(forest, 0))
		st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = Vector3(x, 0, 0)
	r.add_child(mi)


func _rock(mat: Material, forest: float, x: float, r: Node3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3(8, 0.2, 8)
	mm.mesh = box
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis(), Vector3(x, -0.1, 9)))
	mm.set_instance_custom_data(0, Color(forest, 1, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	r.add_child(mmi)


func _initialize() -> void:
	var r := Node3D.new()
	root.add_child(r)
	var terrain: ShaderMaterial = load("res://materials/MAT_terrain.tres")
	var cliff := ShaderMaterial.new()
	cliff.shader = load("res://shaders/SHADER_cliff_rock.gdshader")
	for p in ["ground_albedo", "ground_normal", "macro_noise"]:
		cliff.set_shader_parameter(p, terrain.get_shader_parameter(p))
	for i in 2:
		_quad(terrain, float(i), -5.0 + 10.0 * i, r)
		_rock(cliff, float(i), -5.0 + 10.0 * i, r)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	r.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.6, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.4, 0.4, 0.4)
	r.add_child(env)
	_cam = Camera3D.new()
	r.add_child(_cam)
	_cam.look_at_from_position(Vector3(0, 22, 4.6), Vector3(0, 0, 4.5), Vector3(0, 0, -1))
	_cam.make_current()


func _process(_d: float) -> bool:
	_n += 1
	if _n == 8:
		root.get_viewport().get_texture().get_image().save_png("res://renders/ground_match_near.png")
		_cam.fov = 75.0 * 22.0 / 300.0
		_cam.look_at_from_position(Vector3(0, 300, 4.6), Vector3(0, 0, 4.5), Vector3(0, 0, -1))
	if _n == 16:
		root.get_viewport().get_texture().get_image().save_png("res://renders/ground_match_far.png")
		return true
	return false
