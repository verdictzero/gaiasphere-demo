extends Node3D

# The volumetric cloud SEA: one large horizontal quad running
# `shaders/SHADER_cloud_volumetric.gdshader`, parked at `sea_altitude` and chasing the
# camera in XZ — never in Y. The shader does the raymarch through the slab hanging
# below the quad; this node only has to
#
#   * keep the quad centred under the camera (so its finite size is never reached),
#   * keep the density field anchored in the LOGICAL frame across a floating-origin
#     rebase (via the shader's `world_offset`), exactly as `cloud_plane.gd` does,
#   * feed the sun direction for the cloud self-shadow, and
#   * be the single source of truth for the altitude and size the shader must agree
#     with.
#
# Y-following is deliberately absent: the sea being at ONE altitude is what makes it
# a floor the islands rise out of. XZ-following is invisible because the shader's UVs
# are world-anchored, so sliding the quad sideways moves no cloud.

## The volumetric cloud material (MAT_cloud_sea_volumetric.tres).
@export var cloud_material: ShaderMaterial
## World Y of the cloud-sea surface. Pushed to the material's `sea_top` so the quad
## and the marched slab share one altitude. Keep it well below the island shore so the
## landmass rises cleanly out of the cloud rather than the cloud clipping through it.
@export var sea_altitude := -45.0
## Edge length of the quad in metres. The material's `rim_fade_end` must stay under
## half of this or the geometric edge shows.
@export var deck_size := 12000.0
## How far the sea climbs the island's wall, metres above `sea_altitude`.
@export var rise := 16.0
@export var world_path: NodePath = ^"../GaiaSphere"

var _prox_thread: Thread

var _mi: MeshInstance3D
var _offset := Vector3.ZERO


func _ready() -> void:
	add_to_group("origin_shiftable")
	if cloud_material == null:
		push_warning("CloudSea has no cloud_material; nothing will render.")
		return

	var plane := PlaneMesh.new()
	plane.size = Vector2(deck_size, deck_size)

	_mi = MeshInstance3D.new()
	_mi.mesh = plane
	_mi.material_override = cloud_material
	# The sea must never cast a directional shadow: it is a 12 km camera-following
	# quad, and a shadow from it would fall across the whole world. The material
	# already declares `shadows_disabled` (and is `blend_mix`, which the shadow pass
	# skips), so this is belt-and-suspenders — but MeshInstance3D defaults cast_shadow
	# to ON, and this keeps the sea out of the shadow map even if the shader's render
	# mode or the material ever changes. Mirrors SCRIPT_veg_scatter.gd.
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The marched slab hangs BELOW the quad, so the instance's bounds must reach down
	# too or it frustum-culls the instant the flat surface leaves the top of frame.
	_mi.custom_aabb = AABB(Vector3(-deck_size * 0.5, -2000.0, -deck_size * 0.5),
			Vector3(deck_size, 2100.0, deck_size))
	_mi.extra_cull_margin = 4000.0
	add_child(_mi)

	cloud_material.set_shader_parameter("sea_top", sea_altitude)
	cloud_material.set_shader_parameter("rise", rise)
	_start_proximity()
	_broadcast()


# The sea's altitude and its surface tone, published as global shader parameters so
# everything that has to DISSOLVE INTO the deck agrees with the deck itself rather
# than carrying its own copy of these numbers. `SHADER_cliff_wall.gdshader` is the consumer:
# the island wall fades to `sea_surface_color` as it enters, on a band centred on
# `sea_surface_y`, and both of those used to be hand-tuned against an altitude typed
# out in a second place.
#
# Read off the MATERIAL, not off exported copies: `cloud_color` and
# `cloud_bottom_color` are what the raymarch actually paints, so calibration here
# cannot drift from what the eye sees. Altitude is this node's own, which the
# header already declares is the single source of truth for it.
#
# SET ONLY, NEVER GET. `RenderingServer.global_shader_parameter_get` is an
# editor-only call — outside the editor the GLES3 backend refuses it with "this
# function should never be used outside the editor" on every invocation — so
# globals are a one-way channel into shaders and are no use for handing these
# numbers to another SCRIPT. `SCRIPT_cloud_sea_veil.gd` therefore reads this node
# directly, through the two accessors below, rather than round-tripping.
func _broadcast() -> void:
	RenderingServer.global_shader_parameter_set("sea_surface_y", sea_altitude)
	var surf: Variant = cloud_material.get_shader_parameter("cloud_color")
	if surf != null:
		RenderingServer.global_shader_parameter_set("sea_surface_color", surf)
	var deep: Variant = cloud_material.get_shader_parameter("cloud_bottom_color")
	if deep != null:
		RenderingServer.global_shader_parameter_set("sea_interior_color", deep)


## World Y of the deck's nominal top surface. The billowed surface undulates down
## from here by the material's `bump_amp`; this is the flat reference the quad sits
## at, and what anything asking "am I under the cloud?" should compare against.
func surface_y() -> float:
	return sea_altitude


## What the inside of the deck looks like — the material's own `cloud_bottom_color`,
## which is the tone the raymarch converges on at the base of the slab. Used by
## `SCRIPT_cloud_sea_veil.gd` to fill the screen with the colour the player is inside of.
func interior_color() -> Color:
	if cloud_material != null:
		var deep: Variant = cloud_material.get_shader_parameter("cloud_bottom_color")
		if deep is Color:
			return deep
	return Color(0.089, 0.089, 0.089, 1.0)


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _mi == null:
		return
	var c := cam.global_position
	# The quad rides at the highest the cloud can stand: the march begins on it.
	_mi.global_position = Vector3(c.x, sea_altitude + rise + 12.0, c.z)


# Rendered world rebased: fold the shift into the logical offset so the noise field
# stays put, matching `gaiasphere.apply_origin_shift`. The quad itself is re-
# centred on the camera every frame, so it needs no explicit move here.
func apply_origin_shift(shift: Vector3) -> void:
	_offset -= shift
	if cloud_material != null:
		cloud_material.set_shader_parameter("world_offset", Vector2(_offset.x, _offset.z))


# ------------------------------------------------------------ the island's shape
# WHERE THE LAND IS, as a soft map the shader banks the cloud against: the field
# is asked "land?" on a coarse grid and the answer blurred, so the map reads 0.5
# along the coast and falls away to nothing some 150 m out. Built once, on a
# thread, from a private copy of the field.

const PROX_CELLS := 192
const PROX_BLUR := 8


func _start_proximity() -> void:
	var world := get_node_or_null(world_path)
	if world == null or not world.has_method(&"get_field"):
		return
	var field: IslandField = world.call(&"get_field")
	if not field._ready:
		field.prepare()
	var extent := 1800.0
	var isl: Variant = field.island_in_cell(field.hub_cell())
	if isl != null:
		extent = float(field.island_extent(isl)) + 350.0
	cloud_material.set_shader_parameter("prox_extent", extent)
	_prox_thread = Thread.new()
	_prox_thread.start(_build_proximity.bind(field.clone(), extent))


func _build_proximity(field: IslandField, extent: float) -> void:
	var n := PROX_CELLS
	var land := PackedFloat32Array()
	land.resize(n * n)
	for z in n:
		for x in n:
			var wx := (float(x) + 0.5) / float(n) * 2.0 * extent - extent
			var wz := (float(z) + 0.5) / float(n) * 2.0 * extent - extent
			land[z * n + x] = 1.0 if field.is_land(wx, wz) else 0.0
	# Two box blurs, across then down.
	var tmp := PackedFloat32Array()
	tmp.resize(n * n)
	for pass_i in 2:
		var src := land if pass_i == 0 else tmp
		var dst := tmp if pass_i == 0 else land
		var step := 1 if pass_i == 0 else n
		for z in n:
			for x in n:
				var sum := 0.0
				var along := x if pass_i == 0 else z
				for k in range(-PROX_BLUR, PROX_BLUR + 1):
					var a := clampi(along + k, 0, n - 1)
					sum += src[z * n + a] if pass_i == 0 else src[a * n + x]
				dst[z * n + x] = sum / float(2 * PROX_BLUR + 1)
		if pass_i == 0:
			tmp = dst
		else:
			land = dst
	var bytes := PackedByteArray()
	bytes.resize(n * n)
	for i in n * n:
		bytes[i] = int(clampf(land[i], 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_R8, bytes)
	_install_proximity.call_deferred(img)


func _install_proximity(img: Image) -> void:
	cloud_material.set_shader_parameter("island_prox", ImageTexture.create_from_image(img))
	if _prox_thread != null:
		_prox_thread.wait_to_finish()
		_prox_thread = null


func _exit_tree() -> void:
	if _prox_thread != null:
		_prox_thread.wait_to_finish()
