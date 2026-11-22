extends SceneTree

# EVERY EFFECT IN THE LIBRARY, eight to a picture, each picture taken three
# times (0.4 s, 1.3 s and 3.5 s after they are set going), written to the folder
# given: fx_<page>_a.png, _b.png, _c.png. Each effect stands 11 m from the next
# with its name under it and a 2 m post beside it for scale.
#
#   godot --path . --resolution 1600x900 --script res://tests/RENDER_fx_gallery.gd -- --out=/some/folder [--only=campfire,torch]

const PER_PAGE := 8
const TIMES := [0.4, 1.3, 3.5]

var _out := "user://"
var _names: PackedStringArray
var _page := -1
var _began := 0
var _shot := 0
var _stage: Node3D
var _frames := 0


func _initialize() -> void:
	var only := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	_names = Fx.names() if only.is_empty() else only
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	moon.light_energy = 0.5
	root.add_child(moon)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.2, 0.2, 0.19)
	plane.material = dirt
	ground.mesh = plane
	root.add_child(ground)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 27.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 30.0, 60.0), Vector3(0, 5.5, 0))
	cam.current = true
	print("fx: %d effects" % _names.size())


func _next_page() -> bool:
	_page += 1
	if _stage != null:
		_stage.queue_free()
	if _page * PER_PAGE >= _names.size():
		return false
	_stage = Node3D.new()
	root.add_child(_stage)
	for i in PER_PAGE:
		var n := _page * PER_PAGE + i
		if n >= _names.size():
			break
		var at := Vector3(-16.5 + 11.0 * float(i % 4), 0, -17.0 + 34.0 * float(i / 4))
		var made := Fx.spawn(_stage, _names[n], at)
		if made == null:
			print("fx: NOTHING MADE for ", _names[n])
		var label := Label3D.new()
		label.text = _names[n]
		label.font_size = 110
		label.outline_size = 30
		label.position = at + Vector3(0, 0.05, 3.4)
		label.rotation_degrees.x = -90.0
		_stage.add_child(label)
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 2.0, 0.12)
		post.mesh = box
		post.position = at + Vector3(-4.6, 1.0, 0)
		_stage.add_child(post)
	_began = Time.get_ticks_msec()
	_shot = 0
	return true


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if _page < 0 or _shot >= TIMES.size():
		if not _next_page():
			print("fx: ok")
			quit(0)
			return true
		return false
	if float(Time.get_ticks_msec() - _began) / 1000.0 >= float(TIMES[_shot]):
		root.get_texture().get_image().save_png(_out.path_join("fx_%02d_%s.png" % [_page, "abc"[_shot]]))
		_shot += 1
	return false
