class_name Vitals
extends CanvasLayer

# HUNGER AND STAMINA, AND HOW EACH LEANS ON THE OTHER.
#
#   stamina   spent by running, jumping and every swing of the axe or sword;
#             comes back when you ease off. Run it to nothing and you cannot
#             run again until some of it is back.
#   hunger    how fed you are, 100 full. It runs down by itself, slowly, and
#             faster for every bit of effort: getting stamina back is paid for
#             in food.
#
# THE CONNECTION RUNS BOTH WAYS. Effort costs food; and going hungry costs
# effort: below `hungry_at` your stamina comes back more and more slowly and
# its ceiling comes down, until on an empty stomach you have a third of it and
# it takes four times as long to return. Nothing here kills you.
#
# Eating is what puts it right: berries, with the berries' slot selected in the
# hotbar, one to a click (SCRIPT_sword_play.gd holds them in the hand).
#
# The two bars sit over the hotbar, each under its name: hunger on the left,
# stamina on the right.

@export var explorer_path: NodePath = ^"../Explorer"
## Real minutes for a full stomach to empty doing nothing at all.
@export var minutes_to_starve := 30.0
## Below this much food, stamina starts to suffer.
@export var hungry_at := 40.0
## Stamina a second: spent running, and got back at rest on a full stomach.
@export var run_cost := 6.5
@export var regain := 15.0
## Seconds of ease before any comes back.
@export var regain_wait := 0.9
## Food spent for each point of stamina got back.
@export var food_per_stamina := 0.014
## What a jump and a swing cost.
@export var jump_cost := 4.0
@export var swing_cost := 5.0
## Stamina has to come back this far before you can run again after spending it all.
@export var second_wind := 22.0
## What one berry is worth.
@export var berry_food := 14.0

const PANEL := Color(0.06, 0.07, 0.085, 0.62)
const EDGE := Color(1, 1, 1, 0.14)
const FOOD := Color(0.95, 0.42, 0.3)
const WIND := Color(0.56, 0.86, 1.0)
const INK := Color(0.93, 0.95, 0.97)

var hunger := 100.0
var stamina := 100.0
## True from running stamina out until `second_wind` of it is back.
var spent := false
var _explorer: CharacterBody3D
var _rest := 0.0
var _view: Control
var _font: Font
var _flash := 0.0            # the hunger bar's glow just after eating


func _ready() -> void:
	layer = 29
	_explorer = get_node_or_null(explorer_path) as CharacterBody3D
	_font = load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)


## The most stamina a body this hungry can hold, and how fast it comes back, as
## shares of what a fed one manages.
func ceiling() -> float:
	return 100.0 * lerpf(0.33, 1.0, clampf(hunger / maxf(hungry_at, 1.0), 0.0, 1.0))


func recovery() -> float:
	return lerpf(0.25, 1.0, clampf(hunger / maxf(hungry_at, 1.0), 0.0, 1.0))


## An effort made: a swing, a jump. Returns false (and takes nothing) only when
## `needed` is asked for and there is not that much left.
func spend(amount: float, needed := false) -> bool:
	if needed and stamina < amount:
		return false
	stamina = maxf(stamina - amount, 0.0)
	_rest = 0.0
	if stamina <= 0.0:
		spent = true
	return true


func eat(food: float) -> void:
	hunger = minf(hunger + food, 100.0)
	_flash = 1.0


func _process(delta: float) -> void:
	if _explorer == null or not bool(_explorer.get("arrived")):
		return
	var flying := bool(_explorer.get("flying"))
	var running := bool(_explorer.get("running")) and not flying
	# Hunger: always, a little; more for the effort of running.
	var idle := 100.0 / maxf(minutes_to_starve * 60.0, 1.0)
	hunger = maxf(hunger - idle * (2.0 if running else 1.0) * delta, 0.0)
	if not flying and Input.is_action_just_pressed(&"wv_up") and _explorer.is_on_floor():
		spend(jump_cost)
	if running:
		spend(run_cost * delta)
	else:
		_rest += delta
		if _rest >= regain_wait and stamina < ceiling():
			# Walking gets it back too, more slowly than standing.
			var moving := Vector2(_explorer.velocity.x, _explorer.velocity.z).length() > 1.0
			var back := minf(regain * recovery() * (0.6 if moving else 1.0) * delta, ceiling() - stamina)
			stamina += back
			hunger = maxf(hunger - back * food_per_stamina, 0.0)
	stamina = minf(stamina, maxf(ceiling(), stamina - 30.0 * delta))      # the ceiling coming down takes it with it, gently
	if spent and stamina >= minf(second_wind, ceiling() * 0.6):
		spent = false
	_explorer.set("run_allowed", not spent)
	_flash = maxf(_flash - delta * 1.6, 0.0)
	_view.queue_redraw()


# ------------------------------------------------------------------ the bars

func _box(r: Rect2, fill: Color, radius: float, edge := Color(0, 0, 0, 0), width := 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	sb.corner_detail = 8
	sb.anti_aliasing = true
	if width > 0.0:
		sb.set_border_width_all(maxi(1, int(round(width))))
		sb.border_color = edge
	_view.draw_style_box(sb, r)


func _draw_view() -> void:
	if Inventory.menu_open or GraphicsMenu.menu_open or EnvironmentMenu.menu_open:
		return
	var k := _view.size.y / 1080.0
	var cell := 84.0 * k
	var left := (_view.size.x - cell * 9.0) * 0.5 + 5.0 * k
	var top := _view.size.y - cell - 26.0 * k - 64.0 * k
	var wide := cell * 4.5 - 14.0 * k
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	for side in 2:
		var value := hunger if side == 0 else stamina
		var colour := FOOD if side == 0 else WIND
		var r := Rect2(Vector2(left + (wide + 18.0 * k) * float(side), top), Vector2(wide, 16.0 * k))
		_box(r, PANEL, 8.0 * k, EDGE, 1.5 * k)
		var inner := r.grow(-3.0 * k)
		if side == 1:
			# What hunger has taken off the top of the stamina bar: hatched out.
			var lost := 1.0 - ceiling() / 100.0
			if lost > 0.005:
				_box(Rect2(inner.position + Vector2(inner.size.x * (1.0 - lost), 0), Vector2(inner.size.x * lost, inner.size.y)),
						Color(FOOD.r, FOOD.g, FOOD.b, 0.28), 5.0 * k)
		var low := value < 20.0 or (side == 1 and spent)
		var shown := colour.lerp(Color(1.0, 0.25, 0.2), pulse * 0.7) if low else colour
		if side == 0 and _flash > 0.0:
			shown = shown.lerp(Color(1, 1, 1), _flash * 0.6)
		if value > 0.5:
			_box(Rect2(inner.position, Vector2(inner.size.x * value / 100.0, inner.size.y)), shown, 5.0 * k)
		# Named, not pictured: a small label over each bar's left end.
		var fs := int(16.0 * k)
		var name := "HUNGER" if side == 0 else "STAMINA"
		var at := Vector2(r.position.x + 2.0 * k, r.position.y - 7.0 * k)
		_view.draw_string(_font, at + Vector2(1, 1) * k, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
		_view.draw_string(_font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK.r, INK.g, INK.b, 0.85))
