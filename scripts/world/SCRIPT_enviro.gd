class_name Enviro
extends Node3D

# THE SKY AND THE WEATHER, IN ONE PLACE: time of day, the sun and the moon and the
# one shadowed light they share, the atmosphere, volumetric clouds, fog, rain,
# lightning, god rays, wind and wetness. It owns the WorldEnvironment and the
# DirectionalLight3D, and every lit shader in the project reads what it publishes
# as global shader parameters (`enviro_*`), so the island, the water and the cloud
# sea all answer to the same light.
#
#   enviro.hour = 21.5                  # jump to a time
#   enviro.set_weather("storm", 20.0)   # blend to a preset over 20 seconds
#
# Keys while playing: T / G time forward / back, F1-F7 the weather presets.

signal weather_changed(name: String)

const WEATHERS := {
	# coverage and density shape the clouds; fog is metres^-1; rain 0..1;
	# dim is how much direct light the cloud takes away; bolts per minute.
	"clear":    {"coverage": 0.22, "density": 0.030, "fog": 0.00012, "mist": 0.0015, "wind": 0.25, "rain": 0.0, "dim": 0.0,  "bolts": 0.0},
	"cloudy":   {"coverage": 0.50, "density": 0.036, "fog": 0.00022, "mist": 0.003, "wind": 0.40, "rain": 0.0, "dim": 0.25, "bolts": 0.0},
	"overcast": {"coverage": 0.86, "density": 0.050, "fog": 0.00045, "mist": 0.006, "wind": 0.50, "rain": 0.0, "dim": 0.70, "bolts": 0.0},
	"foggy":    {"coverage": 0.60, "density": 0.040, "fog": 0.0042, "mist": 0.03, "wind": 0.15, "rain": 0.0, "dim": 0.45, "bolts": 0.0},
	"rain":     {"coverage": 0.92, "density": 0.058, "fog": 0.0011, "mist": 0.01, "wind": 1.05, "rain": 0.6, "dim": 0.80, "bolts": 0.0},
	# The island as it is meant to be seen: broken cloud that lets a low sun through,
	# fog thick enough to carry its shafts.
	"golden_fog": {"coverage": 0.66, "density": 0.07, "fog": 0.0019, "mist": 0.035, "wind": 0.38, "rain": 0.0, "dim": 0.08, "bolts": 0.0},
	"storm":    {"coverage": 1.00, "density": 0.075, "fog": 0.0016, "mist": 0.008, "wind": 1.9, "rain": 1.0, "dim": 0.92, "bolts": 7.0},
}
const WEATHER_KEYS := ["golden_fog", "clear", "cloudy", "overcast", "foggy", "rain", "storm"]

## Hour of the day, 0-24.
@export_range(0.0, 24.0) var hour := 17.3
## Whether time passes on its own. Off: the island is held at golden hour.
@export var advance := true
## Real minutes for one full day.
@export var day_minutes := 36.0
## Weather changes by itself every so often (the keys still set it by hand).
@export var auto_weather := true
## Real minutes a spell of weather lasts: shortest and longest.
@export var weather_minutes := Vector2(2.5, 6.0)
## Tilt of the sun's path from overhead, degrees.
@export var latitude := 38.0
## Where the moon is in its month: 0 new, 0.5 full.
@export_range(0.0, 1.0) var moon_phase := 0.42
@export var weather := "golden_fog"
## 0 low, 1 medium, 2 high: cloud march steps, god-ray samples, shadow reach.
@export_range(0, 2) var quality := 1
## Cold, slightly drained colour: the look of the place. 0 turns the grade off.
@export_range(0.0, 1.0) var spooky := 0.5
## Share of the screen's resolution the 3D world is drawn at on a phone.
@export_range(0.25, 1.0) var mobile_render_scale := 0.5
## The film grade (a 3D colour lookup table built in _grade_lut): 0 off, 1 full.
@export_range(0.0, 1.0) var cinematic_grade := 0.85
## How bright the night's own light is, as a multiple of a dark, starlit night.
@export_range(0.0, 20.0) var night_ambient := 5.5
@export var god_rays := true
## The camera: depth of field, the eye adjusting to light and dark, and the lens
## pass (grade, vignette, fringing, grain). Each can be turned off.
@export var depth_of_field := true
@export var eye_adaptation := true
@export var lens_effects := true
## Black bars for a 2.39:1 cinema frame.
@export var letterbox := false
## The anamorphic lens flare on the sun (0 turns it off).
@export_range(0.0, 2.0) var flare_strength := 0.85
## How far the fog turns gold when the sun is low (0 leaves it grey).
@export_range(0.0, 1.0) var fog_warmth := 0.8

var sun_dir := Vector3.UP
var moon_dir := Vector3.DOWN
## The light the world is lit by right now (sun or moon), and its colour x energy.
var light_dir := Vector3.UP
var light_color := Color.WHITE
var fog_color := Color(0.4, 0.45, 0.5)
var wetness := 0.0
## True while the camera is under water (SCRIPT_underwater_view.gd sets it).
var submerged := false

var _env: Environment
var _sky_mat: ShaderMaterial
var _light: DirectionalLight3D
var _flash_light: DirectionalLight3D
var _rays: MeshInstance3D
var _rays_mat: ShaderMaterial
var _rain: GPUParticles3D
var _now := {}            # the blended weather values in force
var _from := {}
var _to := {}
var _blend := 1.0
var _blend_seconds := 1.0
var _wind_drift := Vector3.ZERO
var _wind_time := 0.0
var _flash := 0.0
var _bolt_wait := 4.0
var _rng := RandomNumberGenerator.new()
var _weather_left := 150.0
# What may follow what, so the sky changes the way weather does: it clouds over
# before it rains, and clears by stages.
const WEATHER_NEXT := {
	"clear": ["cloudy", "cloudy", "golden_fog"],
	"golden_fog": ["clear", "cloudy", "foggy"],
	"cloudy": ["clear", "golden_fog", "overcast", "overcast"],
	"overcast": ["cloudy", "rain", "rain", "foggy"],
	"foggy": ["golden_fog", "overcast", "cloudy"],
	"rain": ["overcast", "storm", "cloudy"],
	"storm": ["rain", "overcast"],
}


func _ready() -> void:
	if OS.has_feature("mobile"):
		quality = 0
		# Phones draw the 3D world at half resolution each way (a quarter of the pixels)
		# and scale it up; the controls and text over it stay sharp.
		get_viewport().scaling_3d_scale = mobile_render_scale
	_rng.seed = 152
	_to = WEATHERS.get(weather, WEATHERS["clear"]).duplicate()
	_from = _to.duplicate()
	_now = _to.duplicate()
	_build_environment()
	_build_light()
	_build_rays()
	_build_rain()
	_apply(0.0)


# ------------------------------------------------------------------ the API

func set_weather(to: String, seconds := 12.0) -> void:
	if not WEATHERS.has(to):
		push_warning("enviro: no weather called '%s'" % to)
		return
	weather = to
	_from = _now.duplicate()
	_to = WEATHERS[to].duplicate()
	_blend = 0.0
	_blend_seconds = maxf(seconds, 0.01)
	weather_changed.emit(to)
	_weather_left = _rng.randf_range(weather_minutes.x, weather_minutes.y) * 60.0


## How foggy it is, 0 (clear air) to 1 (the thickest preset).
func fog_amount() -> float:
	return clampf(float(_now["fog"]) / 0.0042, 0.0, 1.0)


## 0 at night, 1 in full day.
func daylight() -> float:
	return smoothstep(-0.08, 0.22, sun_dir.y)


## The wind right now, gusts included: its direction times its strength (a breeze
## is about 0.3, a gale about 2). The direction backs and veers a little.
func wind_vector() -> Vector3:
	return Vector3(0.8, 0.0, 0.6).rotated(Vector3.UP, _veer) * wind_strength


## The wind's strength right now.
var wind_strength := 0.3
var _veer := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_T:
			hour = fposmod(hour + 0.5, 24.0)
		elif k == KEY_G:
			hour = fposmod(hour - 0.5, 24.0)
		elif k >= KEY_F1 and k <= KEY_F7 and not event.echo:
			# The number keys are the hotbar's (SCRIPT_inventory.gd).
			set_weather(WEATHER_KEYS[k - KEY_F1], 8.0)


# ------------------------------------------------------------------ building

func _build_environment() -> void:
	var shape := NoiseTexture3D.new()
	shape.width = 64
	shape.height = 64
	shape.depth = 64
	shape.seamless = true
	shape.seamless_blend_skirt = 0.3
	var n3 := FastNoiseLite.new()
	n3.noise_type = FastNoiseLite.TYPE_CELLULAR
	n3.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	n3.frequency = 0.05
	n3.fractal_octaves = 3
	n3.seed = 7
	shape.noise = n3
	shape.invert = true
	var weather_map := NoiseTexture2D.new()
	weather_map.width = 256
	weather_map.height = 256
	weather_map.seamless = true
	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n2.frequency = 0.012
	n2.fractal_octaves = 4
	n2.seed = 21
	weather_map.noise = n2

	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/SHADER_enviro_sky.gdshader")
	_sky_mat.set_shader_parameter("cloud_shape", shape)
	_sky_mat.set_shader_parameter("cloud_weather", weather_map)
	_sky_mat.set_shader_parameter("cloud_steps", [32, 80, 112][quality])
	_sky_mat.set_shader_parameter("cloud_light_steps", [3, 5, 6][quality])
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# NO REFLECTIONS FROM THE SKY'S CUBEMAP. The sky changes every frame (clouds
	# drift, the sun moves), so that cubemap was being rebuilt continuously, a face
	# and a mip at a time, and anything mirror-smooth showed the half-built steps:
	# the water flickered light and dark from frame to frame on a phone. The water
	# works its reflection of the sky out for itself from the colours below, which
	# is steady and far cheaper.
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# AgX: bright, saturated light (a low sun, the beam on the sword) rolls off to
	# white the way film does instead of clipping to a flat colour. It comes out
	# flat, and the grade below puts the contrast back.
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_white = 8.0
	_env.tonemap_exposure = 1.15
	# Bloom: what is brighter than white (the sun's disc and glare, glitter on the
	# water, the beam on the sword) spreads into a glow.
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_strength = 1.15
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.0
	_env.glow_hdr_scale = 2.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level in 7:
		_env.set_glow_level(level, [0.0, 0.6, 1.0, 1.0, 0.8, 0.5, 0.0][level] if quality > 0
				else [0.0, 0.8, 1.0, 0.0, 0.0, 0.0, 0.0][level])
	_env.fog_enabled = true
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.0
	# The pooled mist lies below the island's rim, on the cloud sea, not over the wall.
	_env.fog_height = -30.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = lerpf(1.0, 0.94, spooky)
	_env.adjustment_contrast = 1.0
	if cinematic_grade > 0.0:
		_env.adjustment_color_correction = _grade_lut(cinematic_grade)
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = _env
	# THE CAMERA. The far distance goes soft, and so does whatever is right against
	# the lens; the exposure drifts toward what is in view, so walking out of the
	# trees into the sun dazzles and then settles, and the deep wood opens up.
	var cam := CameraAttributesPractical.new()
	if depth_of_field and quality > 0:
		cam.dof_blur_far_enabled = true
		cam.dof_blur_far_distance = 160.0
		cam.dof_blur_far_transition = 500.0
		cam.dof_blur_near_enabled = true
		cam.dof_blur_near_distance = 0.55
		cam.dof_blur_near_transition = 0.5
		cam.dof_blur_amount = 0.04
	# Not on a phone: the exposure chasing glitter on the water reads as flicker.
	if eye_adaptation and quality > 0:
		cam.auto_exposure_enabled = true
		cam.auto_exposure_scale = 0.38
		cam.auto_exposure_speed = 0.7
		cam.auto_exposure_min_sensitivity = 60.0
		cam.auto_exposure_max_sensitivity = 800.0
	we.camera_attributes = cam
	if lens_effects:
		var layer := CanvasLayer.new()
		layer.name = "Lens"
		layer.layer = 5
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lens := ShaderMaterial.new()
		lens.shader = load("res://shaders/SHADER_lens.gdshader")
		lens.set_shader_parameter("letterbox_aspect", 2.39 if letterbox else 0.0)
		if quality == 0:
			lens.set_shader_parameter("fringe", 0.0)
		rect.material = lens
		layer.add_child(rect)
		add_child(layer)
	add_child(we)


## THE GRADE, as a lookup table: every colour the picture can hold, mapped to the
## colour it should be. A film print's S-curve (deep toe, soft shoulder); shadows
## pushed toward teal and highlights toward amber, which is the look of dusk on
## film; the darkest tones a little lifted and drained, the mid-tones a little
## richer.
func _grade_lut(amount: float) -> Texture3D:
	var n := 24
	var slices: Array[Image] = []
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g in n:
			for r in n:
				var c := Vector3(r, g, b) / float(n - 1)
				var lum := c.dot(Vector3(0.2126, 0.7152, 0.0722))
				# the S-curve, per channel
				var s := Vector3(_film(c.x), _film(c.y), _film(c.z))
				# split tone
				var shadow := 1.0 - smoothstep(0.0, 0.45, lum)
				var high := smoothstep(0.45, 1.0, lum)
				s += Vector3(-0.022, 0.012, 0.03) * shadow + Vector3(0.035, 0.012, -0.03) * high
				# saturation: thin in the shadows, fuller in the middle
				var l2 := s.dot(Vector3(0.2126, 0.7152, 0.0722))
				var sat := lerpf(0.82, 1.14, smoothstep(0.05, 0.5, lum)) * lerpf(1.0, 0.92, high)
				s = Vector3(l2, l2, l2).lerp(s, sat)
				s = c.lerp(s, amount)
				img.set_pixel(r, g, Color(clampf(s.x, 0.0, 1.0), clampf(s.y, 0.0, 1.0), clampf(s.z, 0.0, 1.0)))
		slices.append(img)
	var lut := ImageTexture3D.new()
	lut.create(Image.FORMAT_RGB8, n, n, n, false, slices)
	return lut


static func _film(x: float) -> float:
	# a toe that holds the blacks down, a shoulder that eases the whites in
	var t := x * x * (3.0 - 2.0 * x)
	return lerpf(x, t, 0.55) * 0.97 + 0.012


func _build_light() -> void:
	_light = DirectionalLight3D.new()
	_light.name = "DirectionalLight3D"
	_light.shadow_enabled = true
	_light.directional_shadow_mode = (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality == 0
			else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	_light.directional_shadow_max_distance = [120.0, 220.0, 320.0][quality]
	_light.directional_shadow_blend_splits = quality > 0
	_light.shadow_bias = 0.06
	_light.shadow_normal_bias = 1.6
	_light.shadow_blur = 1.2
	add_child(_light)
	# Lightning: a second, unshadowed light that is dark except for the flash.
	_flash_light = DirectionalLight3D.new()
	_flash_light.name = "Lightning"
	_flash_light.light_color = Color(0.75, 0.82, 1.0)
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	_flash_light.rotation_degrees = Vector3(-65.0, 40.0, 0.0)
	add_child(_flash_light)


func _build_rays() -> void:
	_rays_mat = ShaderMaterial.new()
	_rays_mat.shader = load("res://shaders/SHADER_god_rays.gdshader")
	_rays_mat.render_priority = 100
	_rays_mat.set_shader_parameter("samples", [16, 32, 48][quality])
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_rays = MeshInstance3D.new()
	_rays.name = "GodRays"
	_rays.mesh = quad
	_rays.material_override = _rays_mat
	_rays.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rays.extra_cull_margin = 16384.0
	_rays.visible = god_rays
	add_child(_rays)


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = [4000, 9000, 14000][quality]
	_rain.lifetime = 0.9
	_rain.preprocess = 0.9
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	_rain.local_coords = false
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 22)
	pm.direction = Vector3(0.12, -1, 0.08)
	pm.spread = 2.0
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 30.0
	pm.gravity = Vector3(0, -6, 0)
	_rain.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.009, 0.42)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# No billboard in the material: the particles themselves turn to face the camera
	# with their length along the way they are falling, so driven rain slants.
	sm.albedo_color = Color(0.75, 0.8, 0.85, 0.14)
	# Drops right in front of the lens fade out: up close they are bars, not rain.
	sm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	sm.distance_fade_min_distance = 1.5
	sm.distance_fade_max_distance = 5.0
	streak.material = sm
	_rain.draw_pass_1 = streak
	_rain.emitting = false
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)


# ------------------------------------------------------------------ each frame

func _process(dt: float) -> void:
	if auto_weather and advance:
		_weather_left -= dt
		if _weather_left <= 0.0:
			var next: Array = WEATHER_NEXT.get(weather, ["cloudy"])
			set_weather(next[_rng.randi() % next.size()], 45.0)
	if advance and day_minutes > 0.0:
		hour = fposmod(hour + dt * 24.0 / (day_minutes * 60.0), 24.0)
	if _blend < 1.0:
		_blend = minf(1.0, _blend + dt / _blend_seconds)
		var k := smoothstep(0.0, 1.0, _blend)
		for key in _to:
			_now[key] = lerpf(float(_from[key]), float(_to[key]), k)
	_apply(dt)


func _apply(dt: float) -> void:
	var coverage := float(_now["coverage"])
	var dim := float(_now["dim"])
	var rain := float(_now["rain"])
	# GUSTS. The weather sets the wind's mean; it blows in gusts and lulls round
	# that, and the harder it blows the gustier it is: a breeze is steady, a gale
	# slams and slackens. Everything that answers to wind reads this one number
	# (the trees and bushes and grass, the waves and their foam, the rain's slant,
	# the clouds, the fog banks, the pollen).
	var mean := float(_now["wind"])
	var gusty := smoothstep(0.5, 1.6, mean)
	var gt := Time.get_ticks_msec() * 0.001
	var gust := sin(gt * 0.31) * 0.5 + sin(gt * 0.83 + 1.7) * 0.3 + sin(gt * 2.1 + 0.4) * 0.2
	wind_strength = maxf(0.02, mean * (1.0 + gust * lerpf(0.12, 0.5, gusty)))
	_veer = sin(gt * 0.11) * lerpf(0.1, 0.45, gusty)
	var wind := wind_strength

	# Where the sun and moon are.
	var ang := hour / 24.0 * TAU - PI * 0.5
	var tilt := deg_to_rad(latitude)
	sun_dir = Vector3(cos(ang), sin(ang) * cos(tilt), sin(ang) * sin(tilt)).normalized()
	var mang := ang + PI + (moon_phase - 0.5) * TAU
	moon_dir = Vector3(cos(mang), sin(mang) * cos(tilt * 0.8), -sin(mang) * sin(tilt * 0.8)).normalized()

	var day := daylight()
	var dusk := exp(-pow(sun_dir.y / 0.16, 2.0))
	var sun_tint := Color(1.0, 0.62, 0.3).lerp(Color(1.0, 0.95, 0.86), smoothstep(0.02, 0.42, sun_dir.y))
	# A low sun is the strong, warm one: this is where the contrast comes from.
	var sun_energy := smoothstep(-0.03, 0.1, sun_dir.y) * lerpf(3.4, 2.0, smoothstep(0.1, 0.5, sun_dir.y))
	var moon_tint := Color(0.55, 0.68, 1.0)
	var moon_lit := 1.0 - absf(moon_phase - 0.5) * 2.0
	var moon_energy := smoothstep(-0.02, 0.16, moon_dir.y) * (1.0 - day) * (0.4 + 0.55 * moon_lit)

	# One shadowed light: whichever is stronger owns it, and it dips through zero
	# at the hand-over so the shadows never jump.
	var direct := 1.0 - dim
	var use_sun := sun_energy >= moon_energy
	light_dir = sun_dir if use_sun else moon_dir
	var energy := (sun_energy if use_sun else moon_energy) * (0.12 + 0.88 * direct)
	energy *= smoothstep(0.0, 0.06, absf(sun_energy - moon_energy) + 0.02)
	var tint := sun_tint if use_sun else moon_tint
	light_color = Color(tint.r * energy, tint.g * energy, tint.b * energy)
	_light.light_color = tint
	_light.light_energy = energy
	if light_dir.y > 0.02:
		_light.global_basis = Basis.looking_at(-light_dir, Vector3.UP)
	_light.shadow_enabled = energy > 0.02

	# Sky colours: night, day, and grey as the cloud closes in.
	var zenith := Color(0.004, 0.007, 0.018).lerp(Color(0.09, 0.24, 0.62), day)
	var horizon := Color(0.016, 0.024, 0.045).lerp(Color(0.52, 0.66, 0.82), day)
	horizon = horizon.lerp(Color(0.75, 0.42, 0.24), dusk * 0.45 * direct)
	var grey := (zenith.r + zenith.g + zenith.b) / 3.0 * 1.6 + 0.006
	var overcast := smoothstep(0.55, 1.0, coverage)
	zenith = zenith.lerp(Color(grey, grey * 1.02, grey * 1.06), overcast * 0.85)
	var hgrey := (horizon.r + horizon.g + horizon.b) / 3.0
	horizon = horizon.lerp(Color(hgrey, hgrey * 1.02, hgrey * 1.05), overcast * 0.8)
	# Under a closed sky the horizon is no brighter than the cloud above it.
	horizon = horizon.lerp(zenith * 1.5, overcast * 0.65)
	# ... and the whole sky behind the cloud is as dark as the cloud: thick cloud
	# takes the light out of all of it.
	var gloom := lerpf(1.0, 0.6, overcast * dim)
	zenith *= gloom
	horizon *= gloom
	# The look: a cold green-grey cast over whatever the hour gives.
	var cast := Color(0.84, 0.98, 1.0).lerp(Color.WHITE, 1.0 - spooky)
	zenith *= cast
	horizon *= cast

	var ambient := horizon.lerp(zenith, 0.45)
	# Light from the whole sky is nearer white than the blue overhead.
	var ambient_grey := (ambient.r + ambient.g + ambient.b) / 3.0
	ambient = ambient.lerp(Color(ambient_grey, ambient_grey, ambient_grey), 0.55)
	var ambient_energy := lerpf(0.75, 1.9, day) * lerpf(1.0, 1.2, overcast)
	fog_color = horizon.lerp(ambient, 0.35)
	fog_color += Color(tint.r, tint.g, tint.b) * energy * (0.05 + 0.06 * dusk)
	# Golden hour: the air itself goes gold. Fog keeps its brightness and takes the
	# low sun's colour, more the lower the sun and the more of it gets through.
	var gold := clampf(dusk * direct * fog_warmth, 0.0, 1.0)
	var fog_lum := (fog_color.r + fog_color.g + fog_color.b) / 3.0
	fog_color = fog_color.lerp(Color(1.0, 0.68, 0.36) * fog_lum * 1.5, gold)

	_env.ambient_light_color = ambient + Color(0.03, 0.045, 0.075) * night_ambient * (1.0 - day) + Color(0.012, 0.016, 0.02) + Color(0.7, 0.75, 1.0) * _flash * 0.6
	_env.ambient_light_energy = ambient_energy
	_env.fog_light_color = fog_color
	# Fog is a layer on the ground: seen from high above, the island shows through it.
	var cam_y := 0.0
	var view_cam := get_viewport().get_camera_3d()
	if view_cam != null:
		cam_y = view_cam.global_position.y
	_env.fog_density = float(_now["fog"]) * lerpf(1.0, 0.07, smoothstep(70.0, 420.0, cam_y))
	_env.fog_height_density = float(_now["mist"])
	_env.fog_sun_scatter = 0.22 * direct
	_env.background_energy_multiplier = 1.0

	# Lightning.
	var bolts := float(_now["bolts"])
	if bolts > 0.0 and dt > 0.0:
		_bolt_wait -= dt
		if _bolt_wait <= 0.0:
			_flash = _rng.randf_range(0.6, 1.0)
			_bolt_wait = _rng.randf_range(0.4, 2.0) * 60.0 / bolts
	_flash = maxf(0.0, _flash - dt * 3.5) if dt > 0.0 else _flash
	var flicker := _flash * (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.09))
	_flash_light.light_energy = flicker * 3.0

	# Wind and wet.
	_wind_time += dt * (0.6 + wind)
	_wind_drift += wind_vector() * dt * 22.0
	wetness = move_toward(wetness, clampf(rain * 1.5, 0.0, 1.0), dt * (0.08 if rain > 0.01 else 0.02))

	var cloud_light := Color(tint.r, tint.g, tint.b) * (minf(sun_energy, 1.8) if use_sun else moon_energy * 2.2)
	_sky_mat.set_shader_parameter("zenith_color", zenith)
	_sky_mat.set_shader_parameter("horizon_color", horizon)
	_sky_mat.set_shader_parameter("ground_color", fog_color * 0.8)
	_sky_mat.set_shader_parameter("sun_dir", sun_dir)
	_sky_mat.set_shader_parameter("sun_color", sun_tint)
	_sky_mat.set_shader_parameter("sun_energy", smoothstep(-0.06, 0.1, sun_dir.y) * direct)
	_sky_mat.set_shader_parameter("sun_glow_color", sun_tint.lerp(Color(1.0, 0.5, 0.25), dusk))
	_sky_mat.set_shader_parameter("moon_dir", moon_dir)
	_sky_mat.set_shader_parameter("moon_color", moon_tint)
	_sky_mat.set_shader_parameter("moon_energy", (1.0 - day) * direct + 0.0001)
	_sky_mat.set_shader_parameter("moon_phase", moon_phase)
	_sky_mat.set_shader_parameter("stars", (1.0 - smoothstep(-0.2, -0.02, sun_dir.y)) * (1.0 - overcast))
	_sky_mat.set_shader_parameter("cloud_coverage", coverage)
	_sky_mat.set_shader_parameter("cloud_density", float(_now["density"]))
	_sky_mat.set_shader_parameter("cloud_wind", _wind_drift)
	_sky_mat.set_shader_parameter("cloud_light_dir", light_dir)
	_sky_mat.set_shader_parameter("cloud_light_color", cloud_light)
	_sky_mat.set_shader_parameter("cloud_ambient", ambient * ambient_energy * lerpf(1.0, 0.55, overcast))
	_sky_mat.set_shader_parameter("flash", flicker)
	_sky_mat.set_shader_parameter("sun_gap", dusk * (1.0 - smoothstep(0.8, 1.0, coverage)))

	# What every other lit shader reads.
	var wv := wind_vector()
	RenderingServer.global_shader_parameter_set(&"enviro_light_dir", light_dir)
	RenderingServer.global_shader_parameter_set(&"enviro_light_color", light_color)
	RenderingServer.global_shader_parameter_set(&"enviro_ambient", _env.ambient_light_color * ambient_energy)
	RenderingServer.global_shader_parameter_set(&"enviro_sky_zenith", zenith.lerp(ambient, overcast * 0.6))
	RenderingServer.global_shader_parameter_set(&"enviro_sky_horizon", horizon.lerp(ambient, overcast * 0.4))
	RenderingServer.global_shader_parameter_set(&"enviro_fog_color", fog_color)
	RenderingServer.global_shader_parameter_set(&"enviro_wind", Vector4(wv.x, wv.z, wind, _wind_time))
	RenderingServer.global_shader_parameter_set(&"enviro_wetness", wetness)
	RenderingServer.global_shader_parameter_set(&"enviro_flash", flicker)
	# The underwater pass still reads its old names.
	RenderingServer.global_shader_parameter_set(&"tod_sun_dir", light_dir)
	RenderingServer.global_shader_parameter_set(&"tod_sun_color", light_color)
	RenderingServer.global_shader_parameter_set(&"tod_haze_tint", fog_color * 2.2)
	RenderingServer.global_shader_parameter_set(&"tod_water_tint", ambient * 2.0)

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Rain rides above the camera.
	_rain.global_position = cam.global_position + Vector3(0, 14, 0) - cam.global_basis.z * 6.0
	_rain.emitting = rain > 0.02
	# Rain is driven by the wind: near upright in still air, slanting hard in a gale.
	var rain_pm := _rain.process_material as ParticleProcessMaterial
	rain_pm.direction = Vector3(wv.x * 0.45, -1.0, wv.z * 0.45).normalized()
	rain_pm.gravity = Vector3(wv.x * 9.0, -6.0, wv.z * 9.0)
	_rain.amount_ratio = clampf(rain, 0.05, 1.0)

	# God rays: where the light sits on screen, and how much of it gets through.
	if god_rays:
		_rays.global_position = cam.global_position
		var facing := (-cam.global_basis.z).dot(light_dir)
		var strength := smoothstep(0.05, 0.45, facing) * smoothstep(0.0, 0.1, light_dir.y)
		strength *= (0.25 + 0.75 * direct) * (0.7 + fog_amount() * 1.3)
		var uv := Vector2(0.5, 0.5)
		if facing > 0.0:
			var sp := cam.unproject_position(cam.global_position + light_dir * 1000.0)
			var size := get_viewport().get_visible_rect().size
			uv = Vector2(sp.x / size.x, sp.y / size.y)
		_rays_mat.set_shader_parameter("light_uv", uv)
		_rays_mat.set_shader_parameter("flare", (0.0 if submerged else flare_strength) * smoothstep(0.0, 0.3, facing)
				* smoothstep(0.0, 0.08, light_dir.y) * minf(energy, 1.6) * (1.0 if use_sun else 0.3))
		_rays_mat.set_shader_parameter("ray_color", Color(tint.r, tint.g, tint.b))
		_rays_mat.set_shader_parameter("intensity", strength * (0.3 if submerged else 1.0) * (0.52 if use_sun else 0.26) * lerpf(1.0, 0.2, smoothstep(40.0, 300.0, cam.global_position.y)) * minf(energy + 0.15, 1.0))
