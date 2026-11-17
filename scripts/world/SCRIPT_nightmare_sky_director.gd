class_name NightmareSkyDirector
extends Node

# =============================================================================
#  THE FOUR BEATS OF THE FLIP
# =============================================================================
#
# `SkyCycleController` moves the world's COLOUR across the crossing — the sun, the
# haze, the art tint, the two environment balls. It has always done that as one
# continuous blend, and one continuous blend is the right model for a colour and
# the wrong model for an EVENT. Nothing about a lerp says *the old sky was taken
# away and a new one arrived*.
#
# This node is the event. It reads the same crossing the colours read and runs
# four beats against it:
#
#     stage 0.00 - 0.55   THE VORTEX GOES.  It winds up — faster every frame, not
#                         to a new constant rate — while its disc shrinks toward
#                         the zenith, and in the last quarter of that it fades. It
#                         does not stop; it accelerates until it is a point and
#                         then the point is not there.
#     stage 0.48 - 0.72   THE FLASH.  Full frame, blood red, hard attack and a
#                         longer decay. It peaks at 0.55, which is inside the band
#                         where the sun colour and the haze are crossing over, so
#                         the world that comes back out of it is already wrong.
#     stage 0.58 - 0.86   THE EYE DOME.  `sky/SKY_eye_hdri.hdr` fades up over the
#                         grey, under the tail of the flash.
#     stage 0.62 - 1.00   THE PUPIL.  A massive red lens flare lights at the
#                         zenith, in the middle of the eye that the panorama puts
#                         there. See `apex_flare`.
#
# AND THE REVERSE IS FREE, which is why every one of those is written as a pure
# function of the crossing and not as a timeline. Coming back, the pupil dims, the
# dome fades out, the world flashes again, and the vortex spins down out of the
# point it vanished into. There is no second code path and nothing to keep in step
# — a state that can only be entered by one route and left by another is the bug
# this shape does not have.
#
# THE ONE EXCEPTION IS THE SPIN, and it is an exception on purpose. Angle is the
# integral of rate, so it is the one quantity here that is history and not state:
# `_extra_a` accumulates and never runs backwards. A swirl slowing down does not
# un-rotate, and driving the angle itself off the crossing would rewind the arms
# on the way back, which reads as the footage being played in reverse — which it
# is, and which is the thing to hide.
#
#
# WHY THIS IS NOT IN `SCRIPT_sky_cycle_controller.gd`
# --------------------------------------------
# That controller is shared by SCENE_test_zone_A, A2, W and W2 and is already the
# longest script in scripts/. All of this is W2's alone. Keeping it out means the
# other three scenes do not load it, cannot be broken by it, and do not grow four
# groups of exports describing a sky they do not have.
#
# It also puts the event bus to work rather than leaving it as an assertion in a
# test: this node is a listener, holding no clock of its own and owning no state
# that could disagree with the sky's. If the crossing is interrupted half way, the
# beats turn round with it because they were never anything but a function of it.
#
# The two writers do not collide. The controller owns `bottom_color`, `top_color`,
# `horizon_glow`, `sun_glow_color` and `vortex_color`; this owns the vortex's
# GEOMETRY and the eye dome. Disjoint sets on one material.
#
#
# WHY IT IS NOT `@tool`
# ---------------------
# SCENE_test_zone_W2's TimeOfDay comment records a property worth keeping: every
# value the controller writes at the scene's parked phase is already the value in
# `MAT_sky_w2_void.tres`, so opening the scene in the editor cannot dirty that
# resource. This node writes an ACCUMULATED angle, which by definition is not the
# committed one. Not running in the editor keeps the property true, and costs
# nothing — at stage 0 the material's own values already are the picture.

## The crossing to ride. Left unset the node does nothing at all, which is the
## right behaviour for a scene that has a sky but no nightmare.
@export var sky_cycle: SkyCycleController
## The sky. Must be a `shaders/SHADER_sky_void_gradient.gdshader` material — this writes
## the vortex geometry and the eye dome on it.
@export var sky_material: ShaderMaterial
## The zenith lens flare: a `scripts/SCRIPT_space_sun.gd` with `direction_override` set to
## straight up. Its `master_alpha` is driven from here.
@export var apex_flare: SpaceSun
## Full-frame flash. Put it on a CanvasLayer BELOW PostFX (layer 128) so it goes
## through the palette pass with the rest of the frame instead of sitting on top of
## it as the one un-quantised surface in the scene.
@export var flash_rect: ColorRect


# =============================================================================
#  BEAT 1 — the vortex
# =============================================================================

@export_group("Vortex Collapse")
## Where the collapse finishes on the 0..1 crossing. Everything in this group is a
## fraction of the window from 0 to here.
##
## IT HAS TO LAND BEFORE `flash_peak`, not on it. The first draft put both at 0.55
## and the swirl's last frame was also the flash's brightest — so the point did not
## wink out, it was painted over, and what the eye reads then is a transition that
## was interrupted rather than one that completed. Ending here leaves a beat of
## empty sky between the two, which is the pause the flash lands in.
## `tests/TEST_w2_cycle.gd` asserts the ordering.
@export_range(0.05, 1.0) var collapse_end := 0.50
## Extra spin at the end of the collapse, radians per second, ON TOP of the
## material's own idle rate. 24 is about four turns a second — past the point where
## the arms resolve, which is the intent: it should stop being a shape.
##
## It is added as an ANGLE (see `_extra_a`) rather than by rewriting
## `vortex_spin_rad_per_sec`, and that is not a stylistic choice. The shader spins
## by `offset + rate * TIME`, so raising `rate` moves the arms by
## `(new - old) * TIME` instantly — a jump of thousands of radians a few minutes
## into a session. Integrating here and writing the offset is continuous at every
## rate, including the first frame of the flip.
@export_range(0.0, 200.0, 0.5, "or_greater") var spin_boost := 24.0
## Shape of the wind-up. 3 makes the first half of the collapse almost still and
## the last quarter violent, which is the read — something spooling up, not a dial
## being turned.
@export_range(1.0, 8.0, 0.1) var spin_curve := 3.0
## Layer B keeps its 2:1 relationship with layer A through the wind-up. Breaking
## the ratio here would let the two discs beat against each other at a rate nobody
## chose, at the one moment they are turning fast enough for it to show.
@export_range(0.1, 8.0, 0.05) var spin_ratio_b := 2.0
## The disc's dome coverage at rest and at the end. 0.012 is about 11 degrees
## across, inside the 0.05 zenith blackout — so the last thing it does is shrink
## into the dark pool it always sat in.
@export_range(0.01, 0.6) var coverage_base := 0.35
@export_range(0.005, 0.6) var coverage_end := 0.012
## Shape of the shrink. Above 1 it holds its size and then goes quickly.
@export_range(0.5, 8.0, 0.1) var coverage_curve := 2.2
## The material's own opacity, restored exactly at stage 0.
@export_range(0.0, 1.0) var strength_base := 1.0
## The zenith blackout's coverage at rest — the dark pool the swirl's eye sits in
## (`MAT_sky_w2_void.tres`, 0.05, a cap about 18 degrees across).
##
## IT HAS TO CLOSE WITH THE SWIRL, and leaving it open is a bug the first render of
## this caught. The blackout is not a feature of the sky, it is the vortex's own
## dark — the swirl's core is near-black with the arms brightening outwards, so the
## cap is what the middle of it disappears into. Collapse the disc to a point and
## leave the cap at 0.05 and what is left in the sky is an 18-degree black blob
## with nothing in it and no reason to be there, hanging over the flash. It closes
## on the same curve the swirl's opacity fades on, so the pool shuts exactly as the
## thing inside it goes.
@export_range(0.0, 0.6) var zenith_black_base := 0.05
## Fraction of the collapse window that is over before the fade to nothing starts.
## Late on purpose: a swirl that dims all the way down reads as a light going out,
## and this is meant to read as a thing being pulled through a hole.
@export_range(0.0, 1.0) var fade_start := 0.72


# =============================================================================
#  BEAT 2 — the flash
# =============================================================================

@export_group("Flash")
## Opens exactly where the collapse closes, so the flash starts on the frame the
## point disappears. `SkyCycleController.STAGE_STARTS[Stage.FLASH]` is this number
## — the beat a listener hears and the light it sees are the same instant.
@export_range(0.0, 1.0) var flash_begin := 0.50
@export_range(0.0, 1.0) var flash_peak := 0.57
@export_range(0.0, 1.0) var flash_end := 0.74
## Peak opacity. NOT 1.0 — a full white-out throws the frame away, and the frame is
## the point: what should be on screen is the world being LIT by the flash, not the
## flash instead of the world.
##
## 0.85 was the first value and it did throw the frame away. The peak lands inside
## the sunset band, where the sky is already a flat orange with no structure in it,
## so 15% of the world showing through was 15% of nothing — the picture was a solid
## fill with the cloud deck barely ghosted. At 0.72 the treeline and the deck stay
## legible as darker shapes inside the red, which is what makes it read as a flash
## going off over a place rather than as a cut to a colour.
@export_range(0.0, 1.0) var flash_alpha := 0.72
## Deliberately not pure red. The palette LUT resolves a flat 1,0,0 to a dark
## crimson entry, so the flash would land DARKER than the sky it is supposed to
## blow out; the green and blue lift it to an entry near the top of the ramp.
@export var flash_color: Color = Color(1.0, 0.16, 0.1)


# =============================================================================
#  BEATS 3 AND 4 — the eye, and its pupil
# =============================================================================

@export_group("Eye Dome")
@export_range(0.0, 1.0) var eye_begin := 0.58
@export_range(0.0, 1.0) var eye_full := 0.86
## Level for the panorama, whose eyes are authored at a true-HDR 6.0.
##
## 0.16 PUTS THEM ON THE BRIGHTEST RED THE PALETTE HAS, and that is a measurement
## rather than a preference. `palette/PALETTE_ps1-soft.hex` has no bright saturated red at
## all: walk the LUT up the pure-red axis with green and blue pinned at zero and
## the whole ramp above r = 13/15 resolves to ONE entry, a84820 (168, 72, 32) — a
## bright rust. The only other stops on that axis are 882828 and 680010, both
## darker. So the choice here is not "how red" but "which of three", and anything
## from 0.14 to 0.24 lands on the brightest of them; 0.16 sits in the middle of
## that plateau rather than near an edge, so the eyes do not dither between two
## entries and come out mottled.
##
## Pushing it higher does not help. Past 0.30 the green channel clears the next
## quantiser step and the entry becomes c86848, which is brighter but reads as
## salmon — a pink sky, not a blood one. Below 0.14 it drops to 882828 and the eyes
## stop being light sources. This is the top of the range.
@export_range(0.0, 4.0, 0.005) var eye_energy := 0.16

@export_group("Apex Flare")
@export_range(0.0, 1.0) var flare_begin := 0.62
@export_range(0.0, 1.0) var flare_full := 1.0


var _extra_a := 0.0
var _extra_b := 0.0
var _armed := false


func _ready() -> void:
	if sky_cycle == null:
		set_process(false)
		return
	# THE BUS. The stage is read back every frame, because the four curves need it
	# every frame; the BEAT is a discrete thing and arrives as a signal, which is
	# what puts the flare to sleep while the world is settled. See `_on_beat`.
	sky_cycle.nightmare_beat.connect(_on_beat)
	_armed = true
	var s := sky_cycle.nightmare_stage()
	advance(s, 0.0)
	# Seed the flare's sleep state, because the signal only fires on a CHANGE and a
	# scene that starts normal never crosses into it — the flare would run for the
	# whole session before the first flip and then correctly sleep after the first
	# return, which is the sort of asymmetry that never shows up in a profile
	# because it looks like the steady state.
	_on_beat(SkyCycleController.Stage.NORMAL if s < 0.02
			else SkyCycleController.Stage.COLLAPSE, true)


func _process(delta: float) -> void:
	if not _armed:
		return
	advance(sky_cycle.nightmare_stage(), delta)


## Put the sky at `stage`, having spent `delta` seconds getting there.
##
## `_process` calls this once a frame off the live crossing, and that is the whole
## of the node's behaviour. It is PUBLIC because of the one quantity here that is
## not a function of the stage: `delta` only appears in the spin integral, so a
## capture that steps the stage by hand — `tests/RENDER_w2_flip.gd`, rendering a
## strip on a software rasteriser at seconds per frame — would otherwise advance
## the arms by the wall time it took to draw the last picture and produce a swirl
## that jumps by half a turn between adjacent frames of a "3-second" video.
## Calling this with a synthetic delta makes the capture show the flip at the rate
## the flip actually runs.
func advance(stage: float, delta: float) -> void:
	_write(stage, delta)


# A settled normal world has no pupil in it, and the flare should not be paying for
# one. `SCRIPT_space_sun.gd` runs a full screen-projection and a physics raycast every
# frame whatever its alpha is, so leaving it enabled through the 99% of a session
# that is daylight costs a ray and a Control redraw check per frame for a thing
# that draws nothing.
#
# THIS IS WHAT THE BEAT SIGNAL IS FOR — a threshold crossed, once, in a known
# direction. Polling `nightmare_stage() > 0` from `_process` would work and would
# also mean this node runs a branch every frame to discover that nothing has
# happened, which is the cost it is trying to avoid.
func _on_beat(stage: SkyCycleController.Stage, _to_nightmare: bool) -> void:
	if apex_flare == null:
		return
	var awake := stage != SkyCycleController.Stage.NORMAL
	apex_flare.set_process(awake)
	apex_flare.visible = awake


func _write(s: float, delta: float) -> void:
	# --- beat 1: the vortex -------------------------------------------------
	var p := clampf(s / maxf(collapse_end, 1e-4), 0.0, 1.0)
	# Rate is a function of the crossing; ANGLE is its integral and is not. See the
	# header. Wrapped to keep it bounded over a long session — a rotation is
	# periodic, so the sample is identical either way.
	#
	# NEVER RESET, and the wrap is why it does not have to be. An earlier draft
	# released the accumulator back to 0 on settling at NORMAL, to hand the material
	# back the value it ships with — and that is a visible half-turn snap of the
	# arms on the last frame of every return trip, paid for a cosmetic property of
	# an in-memory resource that is never written to disk. `fposmod` keeps it
	# bounded for the life of the process, and a rigid rotation of a six-armed
	# swirl by a constant is not something anyone can see.
	var rate := spin_boost * pow(p, spin_curve)
	_extra_a = fposmod(_extra_a + rate * delta, TAU)
	_extra_b = fposmod(_extra_b + rate * spin_ratio_b * delta, TAU)

	var cov := lerpf(coverage_base, coverage_end, pow(p, coverage_curve))
	var strength := strength_base * _out_at(s)

	if sky_material != null:
		sky_material.set_shader_parameter("vortex_spin_offset_rad", _extra_a)
		sky_material.set_shader_parameter("vortex_spin_b_offset_rad", _extra_b)
		sky_material.set_shader_parameter("vortex_coverage", cov)
		sky_material.set_shader_parameter("vortex_strength", strength)
		sky_material.set_shader_parameter("zenith_black_coverage", zenith_black_at(s))
		# --- beat 3: the eye dome -------------------------------------------
		sky_material.set_shader_parameter("eye_blend",
				smoothstep(eye_begin, eye_full, s))
		sky_material.set_shader_parameter("eye_energy", eye_energy)

	# --- beat 2: the flash --------------------------------------------------
	if flash_rect != null:
		var a := 0.0
		if s > flash_begin and s < flash_end:
			# Two half-curves rather than one symmetric bump: the attack is a third
			# of the decay, which is what makes it a flash and not a pulse.
			a = smoothstep(flash_begin, flash_peak, s) if s <= flash_peak \
					else 1.0 - smoothstep(flash_peak, flash_end, s)
		flash_rect.color = Color(flash_color.r, flash_color.g, flash_color.b,
				a * flash_alpha)
		flash_rect.visible = a > 0.001

	# --- beat 4: the pupil --------------------------------------------------
	if apex_flare != null:
		apex_flare.master_alpha = smoothstep(flare_begin, flare_full, s)


## The vortex disc's current dome coverage. Public because
## `scripts/SCRIPT_bake_env_ball.gd` and `tests/TEST_w2_cycle.gd` both have to know what
## the swirl is doing at a given point in the crossing, and re-deriving the curve
## in two more places is how they come apart.
func vortex_coverage_at(s: float) -> float:
	return lerpf(coverage_base, coverage_end,
			pow(clampf(s / maxf(collapse_end, 1e-4), 0.0, 1.0), coverage_curve))


## ...and its opacity, for the same reason.
func vortex_strength_at(s: float) -> float:
	return strength_base * _out_at(s)


## ...and the dark pool it sits in, which closes on the same curve.
func zenith_black_at(s: float) -> float:
	return zenith_black_base * _out_at(s)


func _out_at(s: float) -> float:
	return 1.0 - smoothstep(fade_start, 1.0,
			clampf(s / maxf(collapse_end, 1e-4), 0.0, 1.0))


## How much of the eye dome is showing at a given point in the crossing.
func eye_blend_at(s: float) -> float:
	return smoothstep(eye_begin, eye_full, s)
