extends SceneTree

# THE POWER KIT ON A TABLE: each part in a row, its levels of detail left to right
# from the finest and last its impostor (the quad turned to the eye), one picture
# a part (renders/power_bake/row_<part>.png); tools/build_power_sheet.py stacks
# them into renders/power_kit.png.
#
#   godot --path . --resolution 1920x1080 --script res://tests/RENDER_power_kit.gd
#   python3 tools/build_power_sheet.py

var _cam: Camera3D
var _n := 0
var _rows: Array = []        # [part, the row's middle, its width, its height]
var _row := 0


func _initialize() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.34, 0.4, 0.48)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	sun.light_energy = 1.5
	root.add_child(sun)
	var z := 0.0
	for part in PowerKit.names():
		var info := PowerKit.about(part)
		var size: Array = info["size_m"]
		var low: Array = info["low"]
		var pitch := maxf(float(size[0]), float(size[2])) * 1.5 + 0.3
		var lods := PowerKit.lods(part)
		for k in lods.size() + 1:
			var mi := MeshInstance3D.new()
			if k < lods.size():
				mi.mesh = lods[k]
			else:
				var imp := PowerKit.impostor(part)
				if imp.is_empty():
					continue
				mi.mesh = imp[0]
				mi.material_override = imp[1]
				mi.set_instance_shader_parameter(&"lod_in", 0.0)
				mi.set_instance_shader_parameter(&"lod_out", 0.0)
			mi.position = Vector3(pitch * (float(k) + 0.5), -float(low[1]), z)
			mi.rotation.y = 0.5
			root.add_child(mi)
		_rows.append([part, Vector3(pitch * float(lods.size() + 1) * 0.5, float(size[1]) * 0.5, z), pitch * float(lods.size() + 1), float(size[1])])
		z += 200.0                      # (each row far from the next: one to a picture)
		print("power kit: %-16s %s triangles, then its impostor; hand-overs at %s m" % [part, info["triangles"],
				PowerKit.distances(part).map(func(d: float) -> int: return int(d))])
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	root.add_child(_cam)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders/power_bake"))
	_aim()


func _aim() -> void:
	var row: Array = _rows[_row]
	var mid: Vector3 = row[1]
	_cam.size = float(row[2]) * 1.04
	_cam.position = mid + Vector3(0.0, 30.0 * 0.32, 30.0)
	_cam.look_at(mid)
	_n = 0


func _process(_d: float) -> bool:
	_n += 1
	if _n < (40 if _row == 0 else 8):
		return false
	root.get_viewport().get_texture().get_image().save_png("res://renders/power_bake/row_%s.png" % _rows[_row][0])
	_row += 1
	if _row >= _rows.size():
		quit(0)
		return true
	_aim()
	return false
