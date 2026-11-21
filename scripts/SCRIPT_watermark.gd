class_name Watermark
extends CanvasLayer

# THE GAIASPHERE LOGO IN THE BOTTOM LEFT CORNER OF THE GAME (the top left on a
# touchscreen), small and a little see-through, sized to the screen. It takes no
# input.

## The logo's width as a share of the screen's height.
@export var size := 0.26
@export var opacity := 0.85
## Stand at the top left whatever the screen (a touchscreen always does).
@export var at_top := false

var _rect: TextureRect


func _ready() -> void:
	layer = 20
	_rect = TextureRect.new()
	_rect.texture = load("res://branding/logo_small.png")
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate = Color(1, 1, 1, opacity)
	add_child(_rect)
	get_viewport().size_changed.connect(_place)
	_place()


func _place() -> void:
	var view := get_viewport().get_visible_rect().size
	var w := view.y * size
	var h := w * float(_rect.texture.get_height()) / float(_rect.texture.get_width())
	var gap := view.y * 0.022
	_rect.size = Vector2(w, h)
	# On a touchscreen the bottom left is the walking thumb's: the logo goes up
	# to the top left instead.
	if DisplayServer.is_touchscreen_available() or at_top:
		_rect.position = Vector2(gap, gap * 2.6)
	else:
		_rect.position = Vector2(gap, view.y - h - gap)
