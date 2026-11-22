extends SceneTree

# EVERY EFFECT IN THE LIBRARY, ONE AFTER ANOTHER, for a film of them: each is
# set going alone in the middle of the picture with its name under it, framed to
# its own size, and left for as long as it lasts (a looping one for a few
# seconds), then cleared for the next. Run it under Godot's film writer:
#
#   godot --path . --resolution 1280x720 --fixed-fps 30 --write-movie /some/folder/fx.avi \
#         --script res://tests/RENDER_fx_video.gd [-- --only=campfire,torch]
#
# and turn the .avi into something smaller with ffmpeg.

const LOOP_SECONDS := 3.2
const GAP := 0.25

var _names: PackedStringArray
var _at := -1
var _left := 0.0
var _effect: Node3D
var _cam: Camera3D
var _title: Label
var _count: Label
var _post: MeshInstance3D
var _frames := 0


func _initialize() -> void:
	var only := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	if only.is_empty():
		# The composed ones first, then one per texture, each lot in order of name.
		var composed := PackedStringArray()
		var plain := PackedStringArray()
		for n in Fx.names():
			var layers: Array = Fx.describe(n)["layers"]
			var own := false
			for layer in layers:
				if String(layer.get("texture", "")) == n:
					own = true
			if own:
				plain.append(n)
			else:
				composed.append(n)
		_names = composed + plain
	else:
		_names = only
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	moon.light_energy = 0.5
	root.add_child(moon)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.2, 0.2, 0.19)
	plane.material = dirt
	ground.mesh = plane
	root.add_child(ground)
	_post = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 2.0, 0.1)
	_post.mesh = box
	root.add_child(_post)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_cam.current = true
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var font: Font = load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	_title = Label.new()
	_title.add_theme_font_override(&"font", font)
	_title.add_theme_font_size_override(&"font_size", 44)
	_title.position = Vector2(40, 590)
	layer.add_child(_title)
	_count = Label.new()
	_count.add_theme_font_override(&"font", font)
	_count.add_theme_font_size_override(&"font_size", 24)
	_count.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
	_count.position = Vector2(42, 650)
	layer.add_child(_count)
	print("fx film: %d effects" % _names.size())


## How big an effect is, metres, from what its layers say: to frame it by.
func _extent(made: Dictionary) -> Vector2:
	var wide := 0.22
	var high := 0.22
	for layer in made["layers"]:
		if String(layer["type"]) != "particles":
			continue
		var size := float(layer.get("size", 1.0)) * maxf(float(layer.get("grow", 1.0)), 1.0)
		var life := float(layer.get("lifetime", 1.0))
		var travel := (float(layer.get("rise", 0.0)) + float(layer.get("burst", 0.0)) * 0.4) * life
		wide = maxf(wide, size + float(layer.get("spread", 0.0)) * 2.0 + float(layer.get("line", 0.0)) + float(layer.get("burst", 0.0)) * 0.5)
		high = maxf(high, float(layer.get("lift", 0.0)) + size * 0.5 + travel * 0.5 + float(layer.get("column", 0.0)))
	return Vector2(wide, high)


func _next() -> bool:
	_at += 1
	if _effect != null and is_instance_valid(_effect):
		_effect.queue_free()
	_effect = null
	if _at >= _names.size():
		return false
	var made := Fx.describe(_names[_at])
	var size := _extent(made)
	var reach := maxf(size.x * 1.0, size.y * 1.5) + 0.35
	var middle := Vector3(0, size.y * 0.5, 0)
	_cam.look_at_from_position(middle + Vector3(0, reach * 0.12, reach * 1.45), middle)
	# (The 2 m post stands beside anything big enough to want one.)
	_post.visible = reach > 2.5
	_post.position = Vector3(-size.x * 0.5 - 0.6, 1.0, 0)
	_effect = Fx.spawn(root, _names[_at], Vector3.ZERO)
	_title.text = _names[_at]
	_count.text = "%d / %d    %s    %s" % [_at + 1, _names.size(), "loops" if bool(made["loop"]) else "one-shot  %.1f s" % float(made.get("seconds", 1.0)),
			String(made.get("about", ""))]
	_left = LOOP_SECONDS if bool(made["loop"]) else clampf(float(made.get("seconds", 1.0)) + 0.3, 1.2, 4.2)
	return true


func _process(delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_left -= delta
	if _left <= -GAP or _at < 0:
		if not _next():
			print("fx film: ok, %d frames" % _frames)
			quit(0)
			return true
	elif _left <= 0.0 and _effect != null and is_instance_valid(_effect):
		_effect.queue_free()          # a blink of empty ground between one and the next
		_effect = null
	return false
