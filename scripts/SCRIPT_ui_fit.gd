class_name UiFit
extends RefCounted

# HOW BIG THE INTERFACE IS DRAWN, AND HOW FAR IN FROM THE GLASS'S EDGES.
#
# Everything on the screen (the bars, the hotbar, the bag, the menus, the touch
# controls) is laid out in the units of a screen 1080 tall, and scaled by
# `scale`. On an ordinary wide screen that is the screen's height over 1080.
# On a squarer one (a folding phone opened out is about 6:5, a tablet 4:3) the
# height alone would make the widest panels wider than the glass, so there the
# width decides instead: the layout always has `WIDE` of its units across to
# work with, which is more than the widest panel takes.
#
# `insets` is how far the rounded corners, the camera's hole and the like eat
# into the picture on a phone, in the picture's own units: what stands in a
# corner (the thumbs' controls, the mark) is moved in by it.

const TALL := 1080.0
const WIDE := 1680.0


static func scale(size: Vector2) -> float:
	return minf(size.y / TALL, size.x / WIDE)


## (left, top, right, bottom), in the units of a picture `size` across. Nothing
## off a phone: a desktop's "safe area" is the screen less its taskbar, which is
## nothing to do with the game's window.
static func insets(size: Vector2) -> Vector4:
	if not (OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")):
		return Vector4.ZERO
	var window := Vector2(DisplayServer.window_get_size())
	if window.x < 1.0 or window.y < 1.0:
		return Vector4.ZERO
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x < 1.0 or safe.size.y < 1.0:
		return Vector4.ZERO
	var k := Vector2(size.x / window.x, size.y / window.y)
	# (Never more than an eighth of the screen, whatever a device claims.)
	return Vector4(
			clampf(safe.position.x * k.x, 0.0, size.x * 0.125),
			clampf(safe.position.y * k.y, 0.0, size.y * 0.125),
			clampf((window.x - safe.end.x) * k.x, 0.0, size.x * 0.125),
			clampf((window.y - safe.end.y) * k.y, 0.0, size.y * 0.125))
