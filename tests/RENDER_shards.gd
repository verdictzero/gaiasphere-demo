extends SceneTree

# THE SHARDS BY THEMSELVES (CliffRocks.shard_mesh): all twelve in a row, lit, to
# renders/shards.png, to see their shape (and that their faces face out).
#
#   godot --path . --script res://tests/RENDER_shards.gd

var _n := 0


func _initialize() -> void:
	var r := Node3D.new()
	root.add_child(r)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	r.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.45, 0.5)
	r.add_child(env)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.48, 0.45)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED if OS.get_environment("BOTH") == "1" else BaseMaterial3D.CULL_BACK
	for i in CliffRocks.SHARDS:
		var mi := MeshInstance3D.new()
		mi.mesh = CliffRocks.shard_mesh(i)
		mi.material_override = mat
		r.add_child(mi)
		mi.position = Vector3((float(i % 6) - 2.5) * 1.6, 0.0 if i < 6 else -2.6, 0.0)
		mi.scale = Vector3(1.0, 2.2, 1.0)
	# A plain box beside them, lit the same, to judge them by.
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.material_override = mat
	r.add_child(box)
	box.position = Vector3(5.6, 0.3, 0.0)
	box.rotation_degrees = Vector3(0, 30, 0)
	var cam := Camera3D.new()
	r.add_child(cam)
	cam.position = Vector3(0, 0.2, 9.5)
	cam.look_at(Vector3(0, -0.2, 0))
	cam.make_current()


func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		root.get_viewport().get_texture().get_image().save_png("res://renders/shards.png")
		return true
	return false
