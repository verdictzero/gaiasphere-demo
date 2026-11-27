class_name Vitals
extends CanvasLayer

# HEALTH, HUNGER AND STAMINA, AND HOW EACH LEANS ON THE OTHERS.
#
#   health    what a fall takes, and what going without food takes: a landing
#             faster than `safe_fall` metres a second hurts, the more the faster,
#             and an empty stomach wears it down a little every second. It mends
#             by itself while you are fed (above `mend_above` food), paid for in
#             food. At nothing you are put back where you started, fed enough to
#             go on, with everything you were carrying. Going under the cloud sea
#             does the same.
#   stamina   spent by running, jumping, swimming and every swing of the axe
#             or sword; comes back when you ease off (in the water: when you
#             float still). Run it to nothing and you cannot
#             run again until some of it is back.
#   hunger    how fed you are, 100 full. It runs down by itself, slowly, and
#             faster for every bit of effort: getting stamina back is paid for
#             in food.
#
# THE CONNECTION RUNS BOTH WAYS. Effort costs food; and going hungry costs
# effort: below `hungry_at` your stamina comes back more and more slowly and
# its ceiling comes down, until on an empty stomach you have a third of it and
# it takes four times as long to return.
#
# Eating is what puts it right: berries, with the berries' slot selected in the
# hotbar, one to a click (SCRIPT_sword_play.gd holds them in the hand).
#
# The three bars sit over the hotbar, each under its name: health, hunger,
# stamina.

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
## A landing slower than this (metres a second) costs nothing; each metre a
## second over it costs `fall_harm` health. (A drop of about 7 m is the limit.)
@export var safe_fall := 12.0
@export var fall_harm := 6.0
## Health lost a second on an empty stomach.
@export var starve_harm := 0.5
## Health mends above this much food, this fast, at this much food a point.
@export var mend_above := 50.0
@export var mend := 0.9
@export var food_per_health := 0.06
## Seconds of air in a breath, seconds to get it all back at the surface, and
## the health lost a second once it is gone.
@export var breath := 45.0
@export var breath_back := 3.5
@export var drown_harm := 14.0
## SWIMMING IS WORK. Stamina a second while swimming along, and how many times
## that with the head under. Floating still at the surface costs nothing and
## gets stamina back at `float_rest` of the usual rate: the way to rest out of
## your depth. Swum out (no stamina left, until the second wind), you swim at
## half speed, a breath under water goes `tired_breath` times as fast, and at
## the surface you can no longer keep your mouth clear while you keep swimming:
## the air goes at `tired_gulp` of a breath's rate instead of coming back.
@export var swim_cost := 1.6
@export var dive_effort := 1.4
@export var float_rest := 0.35
@export var tired_breath := 1.8
@export var tired_gulp := 0.3
## What one berry is worth.
@export var berry_food := 14.0
## And one cut of raw beef.
@export var beef_food := 18.0
## Cooked, it is worth a good deal more.
@export var steak_food := 55.0

const PANEL := Color(0.06, 0.07, 0.085, 0.62)
const EDGE := Color(1, 1, 1, 0.14)
const FOOD := Color(0.96, 0.66, 0.26)
const WIND := Color(0.56, 0.86, 1.0)
const AIR := Color(0.75, 0.95, 1.0)
const BOOST := Color(0.8, 0.58, 1.0)
const INK := Color(0.93, 0.95, 0.97)

var health := 100.0
var hunger := 100.0
var stamina := 100.0
## Air, 0 to 100: goes down with the head under water, comes back fast above it.
var oxygen := 100.0
## True from running stamina out until `second_wind` of it is back.
## GOD MODE, for trying things out (F3, or the tick in the options panel, SCRIPT_options_menu.gd):
## nothing hurts, no breath runs out, nothing tires or starves, and building is
## free: every piece can be crafted for nothing and set down without being used
## up (SCRIPT_inventory.gd, SCRIPT_building.gd).
static var debug := false
## True while the head is under water.
var under := false
var spent := false
var _explorer: CharacterBody3D
var _rest := 0.0
var _view: Control
var _font: Font
var _flash := 0.0            # the hunger bar's glow just after eating
var _hurt := 0.0             # the red at the screen's edge just after harm
var _dropping := 0.0         # the fastest this fall has got, metres a second
var _airborne := false
var _dead := false
var _shroud: ColorRect
var _epitaph: Label
const BLOOD := Color(0.86, 0.2, 0.22)


func _ready() -> void:
	layer = 29
	debug = false
	if not InputMap.has_action(&"wv_debug"):
		InputMap.add_action(&"wv_debug")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F3
		InputMap.action_add_event(&"wv_debug", key)
	_explorer = get_node_or_null(explorer_path) as CharacterBody3D
	_font = load("res://branding/fonts/RobotoCondensed-Regular.ttf")
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	# What comes down over the screen at the end, and what it says.
	_shroud = ColorRect.new()
	_shroud.color = Color(0, 0, 0, 0)
	_shroud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shroud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shroud)
	_epitaph = Label.new()
	_epitaph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_epitaph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_epitaph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_epitaph.add_theme_font_override(&"font", _font)
	_epitaph.add_theme_font_size_override(&"font_size", 34)
	_epitaph.add_theme_color_override(&"font_color", Color(0.9, 0.9, 0.92))
	_epitaph.modulate.a = 0.0
	_epitaph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_epitaph)
	if _explorer != null and _explorer.has_signal(&"fell"):
		_explorer.connect(&"fell", _lost.bind("YOU FELL FROM THE ISLAND", false))


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


## Harm done: health down, the screen's edge red for a moment, and the end if
## that was the last of it (`how` is what the screen then says).
func hurt(amount: float, how := "YOU DIED") -> void:
	if debug:
		return
	if _dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_hurt = clampf(_hurt + amount / 25.0, 0.3, 1.0)
	if health <= 0.0:
		_lost(how, true)


## The end, and the beginning again: the screen goes dark, the player is put
## back at the start (unless the island has already done that), mended and fed
## enough to go on, and the dark lifts. Nothing carried is lost.
func _lost(how: String, put_back: bool) -> void:
	if _dead:
		return
	_dead = true
	_epitaph.text = how
	if not is_inside_tree():
		_revive(put_back)
		return
	var fade := create_tween()
	fade.tween_property(_shroud, "color:a", 1.0, 0.12 if not put_back else 0.7)
	fade.parallel().tween_property(_epitaph, "modulate:a", 1.0, 0.5)
	fade.tween_callback(_revive.bind(put_back))
	fade.tween_interval(1.6)
	fade.tween_property(_shroud, "color:a", 0.0, 1.2)
	fade.parallel().tween_property(_epitaph, "modulate:a", 0.0, 0.7)


func _revive(put_back: bool) -> void:
	if put_back and _explorer != null and _explorer.has_method(&"arrive"):
		_explorer.call(&"arrive")
	health = 100.0
	oxygen = 100.0
	hunger = maxf(hunger, 45.0)
	stamina = ceiling()
	spent = false
	_dropping = 0.0
	_airborne = false
	_hurt = 0.0
	_dead = false


## On the ground or not. (`grounded`, where a body has it, stands in for the
## physics: a test's body is never really standing on anything.)
func _on_ground() -> bool:
	var told: Variant = _explorer.get("grounded")
	return bool(told) if told != null else _explorer.is_on_floor()


func eat(food: float) -> void:
	hunger = minf(hunger + food, 100.0)
	_flash = 1.0


func _process(delta: float) -> void:
	if _explorer == null or not bool(_explorer.get("arrived")) or _dead:
		return
	if Input.is_action_just_pressed(&"wv_debug"):
		debug = not debug
	if debug:
		health = 100.0
		oxygen = 100.0
		hunger = 100.0
		stamina = 100.0
		spent = false
		under = false
		_dropping = 0.0
		_airborne = false
		_explorer.set("run_allowed", true)
		_view.queue_redraw()
		return
	var flying := bool(_explorer.get("flying"))
	# FALLS. The fastest the drop got is what the landing is judged by; water
	# deep enough to swim in breaks it, and flying is not falling.
	var grounded := _on_ground()
	var in_water := float(_explorer.get("deep")) > 1.0 if _explorer.get("deep") != null else false
	if flying or in_water:
		_dropping = 0.0
		_airborne = false
	elif not grounded:
		_airborne = true
		_dropping = maxf(_dropping, -_explorer.velocity.y)
	elif _airborne:
		_airborne = false
		if _dropping > safe_fall:
			hurt((_dropping - safe_fall) * fall_harm, "YOU FELL")
		_dropping = 0.0
	# AIR. The head is under when the water stands over the eyes; a breath lasts
	# `breath` seconds, and when it is gone the water takes health instead.
	var eyes := float(_explorer.get("eye_height")) if _explorer.get("eye_height") != null else 1.6
	under = not flying and _explorer.get("deep") != null and float(_explorer.get("deep")) > eyes + 0.05
	var swimming: bool = not flying and _explorer.get("swimming") == true
	var stroking: bool = swimming and (Vector2(_explorer.velocity.x, _explorer.velocity.z).length() > 0.6 or absf(_explorer.velocity.y) > 0.6)
	var swum_out: bool = swimming and spent
	if under or (swum_out and stroking):
		var rate := (tired_breath if swum_out else 1.0) if under else tired_gulp
		oxygen = maxf(oxygen - 100.0 / maxf(breath, 1.0) * rate * delta, 0.0)
		if oxygen <= 0.0:
			hurt(drown_harm * delta, "YOU DROWNED")
			if _dead:
				return
	else:
		oxygen = minf(oxygen + 100.0 / maxf(breath_back, 0.1) * delta, 100.0)
	# An empty stomach wears health down; a fed one mends it, for food.
	if hunger <= 0.0:
		hurt(starve_harm * delta, "YOU STARVED")
		_hurt = minf(_hurt, 0.25)
	elif hunger > mend_above and health < 100.0:
		var mended := minf(mend * delta, 100.0 - health)
		health += mended
		hunger = maxf(hunger - mended * food_per_health, 0.0)
	_hurt = maxf(_hurt - delta * 1.3, 0.0)
	if _dead:
		return
	var running := bool(_explorer.get("running")) and not flying
	# Hunger: always, a little; more for the effort of running.
	var idle := 100.0 / maxf(minutes_to_starve * 60.0, 1.0)
	hunger = maxf(hunger - idle * (2.0 if running else 1.0) * delta, 0.0)
	if not flying and Input.is_action_just_pressed(&"wv_up") and _on_ground():
		spend(jump_cost)
	if running:
		spend(run_cost * delta)
	elif stroking:
		spend(swim_cost * (dive_effort if under else 1.0) * delta)
	else:
		_rest += delta
		if _rest >= regain_wait and stamina < ceiling():
			# Walking gets it back too, more slowly than standing.
			var moving := Vector2(_explorer.velocity.x, _explorer.velocity.z).length() > 1.0
			var back := minf(regain * recovery() * (float_rest if swimming else (0.6 if moving else 1.0)) * delta, ceiling() - stamina)
			stamina += back
			hunger = maxf(hunger - back * food_per_stamina, 0.0)
	stamina = minf(stamina, maxf(ceiling(), stamina - 30.0 * delta))      # the ceiling coming down takes it with it, gently
	if spent and stamina >= minf(second_wind, ceiling() * 0.6):
		spent = false
	_explorer.set("run_allowed", not spent)
	_explorer.set("swim_tired", swum_out)
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
	if Inventory.menu_open or GraphicsMenu.menu_open or EnvironmentMenu.menu_open or OptionsMenu.menu_open:
		return
	var k := UiFit.scale(_view.size)
	# Harm: red in at the edges of the screen, gone in a moment.
	if _hurt > 0.01:
		var deep := 150.0 * k
		for step in 6:
			var inset := deep * float(step) / 6.0
			var band := deep / 6.0
			var red := Color(BLOOD.r, 0.05, 0.05, _hurt * 0.3 * (1.0 - float(step) / 6.0))
			_view.draw_rect(Rect2(inset, inset, _view.size.x - inset * 2.0, band), red)
			_view.draw_rect(Rect2(inset, _view.size.y - inset - band, _view.size.x - inset * 2.0, band), red)
			_view.draw_rect(Rect2(inset, inset + band, band, _view.size.y - (inset + band) * 2.0), red)
			_view.draw_rect(Rect2(_view.size.x - inset - band, inset + band, band, _view.size.y - (inset + band) * 2.0), red)
	var cell := 84.0 * k
	var left := (_view.size.x - cell * 9.0) * 0.5 + 5.0 * k
	var top := _view.size.y - cell - 26.0 * k - 64.0 * k
	var gap := 18.0 * k
	var wide := (cell * 9.0 - 10.0 * k - gap * 2.0) / 3.0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	if debug:
		# Small, in the bottom left corner, just over the mark there.
		_view.draw_string(_font, Vector2(24.0 * k, _view.size.y - 176.0 * k), "GOD MODE", HORIZONTAL_ALIGNMENT_LEFT, -1, int(15.0 * k),
				Color(1.0, 0.85, 0.3, 0.9))
	# AIR: a bar of its own over the other three, there only while it matters
	# (under water, or still getting a breath back).
	if under or oxygen < 99.5:
		var air := Rect2(Vector2(left + wide + gap, top - 40.0 * k), Vector2(wide, 16.0 * k))
		_box(air, PANEL, 8.0 * k, EDGE, 1.5 * k)
		var air_in := air.grow(-3.0 * k)
		var air_colour := AIR.lerp(Color(1.0, 0.25, 0.2), pulse * 0.8) if oxygen < 25.0 else AIR
		if oxygen > 0.5:
			_box(Rect2(air_in.position, Vector2(air_in.size.x * oxygen / 100.0, air_in.size.y)), air_colour, 5.0 * k)
		var air_at := Vector2(air.position.x + 2.0 * k, air.position.y - 7.0 * k)
		_view.draw_string(_font, air_at + Vector2(1, 1) * k, "OXYGEN", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * k), Color(0, 0, 0, 0.6))
		_view.draw_string(_font, air_at, "OXYGEN", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * k), Color(INK.r, INK.g, INK.b, 0.85))
	# BOOST: the truck's jets, a bar of its own over the stamina's while it is
	# driven (SCRIPT_uni_truck.gd's `boost_left`).
	var truck := get_node_or_null(^"../UniTruck")
	var boost := float(truck.call(&"boost_left")) if truck != null and truck.has_method(&"boost_left") else -1.0
	if boost >= 0.0:
		var jet := Rect2(Vector2(left + (wide + gap) * 2.0, top - 40.0 * k), Vector2(wide, 16.0 * k))
		_box(jet, PANEL, 8.0 * k, EDGE, 1.5 * k)
		var jet_in := jet.grow(-3.0 * k)
		var jet_colour := BOOST.lerp(Color(1.0, 0.25, 0.2), pulse * 0.8) if boost < 0.2 else BOOST
		if boost > 0.005:
			_box(Rect2(jet_in.position, Vector2(jet_in.size.x * boost, jet_in.size.y)), jet_colour, 5.0 * k)
		var jet_at := Vector2(jet.position.x + 2.0 * k, jet.position.y - 7.0 * k)
		_view.draw_string(_font, jet_at + Vector2(1, 1) * k, "BOOST", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * k), Color(0, 0, 0, 0.6))
		_view.draw_string(_font, jet_at, "BOOST", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * k), Color(INK.r, INK.g, INK.b, 0.85))
	for side in 3:
		var value: float = [health, hunger, stamina][side]
		var colour: Color = [BLOOD, FOOD, WIND][side]
		var r := Rect2(Vector2(left + (wide + gap) * float(side), top), Vector2(wide, 16.0 * k))
		_box(r, PANEL, 8.0 * k, EDGE, 1.5 * k)
		var inner := r.grow(-3.0 * k)
		if side == 2:
			# What hunger has taken off the top of the stamina bar: shaded out.
			var lost := 1.0 - ceiling() / 100.0
			if lost > 0.005:
				_box(Rect2(inner.position + Vector2(inner.size.x * (1.0 - lost), 0), Vector2(inner.size.x * lost, inner.size.y)),
						Color(FOOD.r, FOOD.g, FOOD.b, 0.28), 5.0 * k)
		var low := value < 20.0 or (side == 2 and spent)
		var shown := colour.lerp(Color(1.0, 0.25, 0.2) if side != 0 else Color(1, 1, 1), pulse * 0.7) if low else colour
		if side == 1 and _flash > 0.0:
			shown = shown.lerp(Color(1, 1, 1), _flash * 0.6)
		if value > 0.5:
			_box(Rect2(inner.position, Vector2(inner.size.x * value / 100.0, inner.size.y)), shown, 5.0 * k)
		# Named, not pictured: a small label over each bar's left end.
		var fs := int(16.0 * k)
		var name: String = ["HEALTH", "HUNGER", "STAMINA"][side]
		var at := Vector2(r.position.x + 2.0 * k, r.position.y - 7.0 * k)
		_view.draw_string(_font, at + Vector2(1, 1) * k, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
		_view.draw_string(_font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK.r, INK.g, INK.b, 0.85))
