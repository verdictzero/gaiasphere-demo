extends CanvasLayer

# THE BLACK OVER THE FIRST HALF MINUTE. The island is generated when the program
# starts, not shipped as meshes: `IslandWorld` builds every terrain chunk at every
# level of detail before the first frame anyone sees (`prewarm`), and the
# vegetation scatters plant the ground round the start. This covers the screen
# while they do, says how far along they are, puts the explorer down once there
# is ground under the start, and fades away. It is the project's only 2D.
#
# The second launch is much quicker: the built terrain is kept on disk
# (`TerrainBake`, under the user data folder) and read back.

@export var world_path: NodePath
@export var explorer_path: NodePath
@export var scatter_paths: Array[NodePath] = []
## Seconds the scatters are given to plant the start before the cover lifts anyway.
@export var scatter_timeout := 120.0
## Seconds to wait for collision under the start before arriving regardless.
@export var ground_timeout := 20.0
@export var fade := 1.2

enum { WORLD, SCATTER, GROUND, FADE, DONE }

var _phase := WORLD
var _left := 0.0
var _black: ColorRect
var _label: Label
var _logo: TextureRect
var _shown := 0.0
var _scatters: Array[Node] = []
var _explorer: Node3D


func _ready() -> void:
	layer = 200
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	# The logo, as large as fits with room under it, and one line beneath: LOADING n%.
	_logo = TextureRect.new()
	_logo.texture = load("res://branding/logo.png")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.anchor_left = 0.14
	_logo.anchor_right = 0.86
	_logo.anchor_top = 0.08
	_logo.anchor_bottom = 0.78
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)
	_label = Label.new()
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 0.8
	_label.anchor_bottom = 0.92
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override(&"font_color", Color(0.62, 0.95, 0.8))
	_label.add_theme_font_size_override(&"font_size", 34)
	add_child(_label)
	_show(0.0)
	_explorer = get_node_or_null(explorer_path) as Node3D
	for p in scatter_paths:
		var n := get_node_or_null(p)
		if n != null and n.has_method(&"prefill_step"):
			_scatters.append(n)
	var world := get_node_or_null(world_path)
	if world == null or not world.has_signal(&"pregen_finished") \
			or not (world.get(&"prewarm") == true or world.get(&"pregenerate") == true):
		_to_scatter()
		return
	world.connect(&"pregen_progress", _on_progress)
	world.connect(&"pregen_finished", _to_scatter)


func _on_progress(stage: String, done: int, total: int) -> void:
	if total > 0:
		# The terrain is most of the wait: it fills the first 85%.
		_show(0.85 * float(done) / float(total))


func _to_scatter() -> void:
	if _phase != WORLD:
		return
	_phase = SCATTER
	_left = scatter_timeout
	_show(0.85)


func _process(delta: float) -> void:
	match _phase:
		SCATTER:
			_left -= delta
			var all_done := true
			for s in _scatters:
				if s.has_method(&"prefill_covered"):
					s.call(&"prefill_covered")
				if not bool(s.call(&"prefill_step")):
					all_done = false
			_show(0.85 + (0.12 if all_done else 0.06))
			if all_done or _left <= 0.0:
				_phase = GROUND
				_left = ground_timeout
		GROUND:
			_left -= delta
			if _left <= 0.0 or _ground():
				if _explorer != null and _explorer.has_method(&"arrive"):
					_explorer.call(&"arrive")
				_show(1.0)
				_phase = FADE
				_left = fade
		FADE:
			_left -= delta
			_black.color.a = clampf(_left / maxf(fade, 0.01), 0.0, 1.0)
			_logo.modulate.a = _black.color.a
			_label.modulate.a = _black.color.a
			if _left <= 0.0:
				_phase = DONE
				queue_free()


## LOADING and a whole percentage that never goes backwards.
func _show(ratio: float) -> void:
	_shown = maxf(_shown, clampf(ratio, 0.0, 1.0))
	_label.text = "LOADING %d%%" % int(round(_shown * 100.0))


# Is the terrain's collision in under the explorer yet? One ray down.
func _ground() -> bool:
	if _explorer == null:
		return true
	var space := _explorer.get_world_3d().direct_space_state
	if space == null:
		return false
	var from := _explorer.global_position + Vector3.UP * 5.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 80.0)
	q.collide_with_areas = false
	if _explorer is CollisionObject3D:
		q.exclude = [(_explorer as CollisionObject3D).get_rid()]
	return not space.intersect_ray(q).is_empty()
