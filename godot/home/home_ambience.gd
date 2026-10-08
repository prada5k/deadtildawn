extends Node3D
## HOME's small living details, all visual-only and cheap: one aging fluorescent that stutters now and then, a
## little dust drifting around the tube light, and an occasional gnat crossing the view. Created by home_garage.gd
## once the warehouse is loaded (one per HOME visit: the screen that owns it is freed on leaving HOME, and
## setup() refuses to build a second set under the same parent).
##
## Nothing here touches the Civic, the warehouse geometry, or the camera, and it does nothing while HOME is not on
## screen.

const Flicker := preload("res://widgets/light_flicker.gd")
const Handheld := preload("res://widgets/handheld_motion.gd")
const DUST_SHADER := "res://assets/shaders/dust_mote.gdshader"

# ---- the aging tube ----
const AGING_FIXTURE := "Fixture_1"          # over the Civic's left side; the other fixtures stay steady
const AGING_LIGHT_ENERGY := 2.0             # its own small light (no shadow): the flicker dips THIS, never the main light
const AGING_LIGHT_RANGE := 7.0

# ---- dust ----
const DUST_COUNT := 48
const DUST_LIFETIME_S := 18.0
const DUST_CENTER := Vector3(0.6, 1.5, 0.6)  # a box of air around the tube lights and above the Civic
const DUST_HALF_EXTENTS := Vector3(3.6, 1.25, 3.0)
const DUST_SIZE_M := 0.022               # ~1-3 px on a 390-wide screen at 4-10 m
const BEAM_LIGHT_AT := Vector3(0.0, 2.4, 0.2)   # GarageTube (under Fixture_1): the dust glows near it

# ---- gnat ----
const GNAT_FIRST_S := 5.0
const GNAT_GAP_MIN_S := 9.0
const GNAT_GAP_MAX_S := 22.0
const GNAT_CROSS_MIN_S := 2.6
const GNAT_CROSS_MAX_S := 4.6
const GNAT_SIZE_M := 0.0075

var flicker := Flicker.new()
var time_s := 0.0                            # this visit's ambience clock (stops with HOME)
var aging_light: OmniLight3D
var aging_material: StandardMaterial3D       # a PRIVATE copy of the tube's emissive material (the other tubes share the original)
var aging_emission_base := 1.0
var dust: CPUParticles3D
var gnat: MeshInstance3D
var gnat_material: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _camera_reference := Transform3D()
var _camera_fov := 27.0
var _gnat_next_s := GNAT_FIRST_S
var _gnat_from := Vector3.ZERO
var _gnat_to := Vector3.ZERO
var _gnat_start_s := 0.0
var _gnat_duration_s := 0.0
var _gnat_active := false
var _gnat_salt := 0
var _built := false


## garage_root: the node that holds the loaded warehouse + props. camera_reference: the camera's approved pose
## (the gnat crosses what that camera sees). Returns false if a set already exists under this parent.
func setup(garage_root: Node, camera_reference: Transform3D, camera_fov: float) -> bool:
	if _built:
		return false
	for sibling in get_parent().get_children():
		if sibling != self and sibling.name == name:
			return false
	_built = true
	_camera_reference = camera_reference
	_camera_fov = camera_fov
	_rng.seed = 1996
	build_aging_tube(garage_root)
	build_dust()
	build_gnat()
	return true


# ------------------------------------------------------------------ the aging tube

func build_aging_tube(garage_root: Node) -> void:
	var fixture := garage_root.find_child(AGING_FIXTURE, true, false) as Node3D
	var at := fixture.global_position if fixture != null else Vector3(-0.8, 3.0, 0.4)
	aging_light = OmniLight3D.new()
	aging_light.name = "AgingTubeLight"
	aging_light.light_color = Color(1.0, 0.88, 0.7)
	aging_light.light_energy = AGING_LIGHT_ENERGY
	aging_light.omni_range = AGING_LIGHT_RANGE
	aging_light.light_specular = 0.2
	aging_light.shadow_enabled = false           # no extra real-time shadows
	add_child(aging_light)
	aging_light.global_position = at - Vector3(0.0, 0.2, 0.0)
	if fixture == null:
		return
	for node in fixture.find_children("*", "MeshInstance3D", true, false) + ([fixture] if fixture is MeshInstance3D else []):
		var mi := node as MeshInstance3D
		for surface in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(surface) as StandardMaterial3D
			if source != null and source.emission_enabled:
				aging_material = source.duplicate() as StandardMaterial3D        # this fixture only
				aging_emission_base = aging_material.emission_energy_multiplier
				mi.set_surface_override_material(surface, aging_material)


# ------------------------------------------------------------------ dust

func build_dust() -> void:
	dust = CPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = DUST_COUNT
	dust.lifetime = DUST_LIFETIME_S
	dust.preprocess = DUST_LIFETIME_S                     # already drifting when HOME appears (no puff of new dust)
	dust.lifetime_randomness = 0.5
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = DUST_HALF_EXTENTS
	dust.direction = Vector3(0.2, 0.15, -0.1)             # a very slight drift, mostly random
	dust.spread = 180.0
	dust.initial_velocity_min = 0.004
	dust.initial_velocity_max = 0.03
	dust.gravity = Vector3(0.0, -0.0015, 0.0)
	dust.linear_accel_min = -0.003
	dust.linear_accel_max = 0.003
	dust.damping_min = 0.0
	dust.damping_max = 0.01
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.3
	dust.explosiveness = 0.0
	dust.randomness = 1.0
	var ramp := Gradient.new()                            # fade in and out: never a visible pop
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.18, 0.78, 1.0])
	dust.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(DUST_SIZE_M, DUST_SIZE_M)
	dust.mesh = quad
	var shader := load(DUST_SHADER) as Shader
	if shader != null:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("light_pos", BEAM_LIGHT_AT)
		dust.material_override = material
	dust.position = DUST_CENTER
	dust.emitting = true
	add_child(dust)


# ------------------------------------------------------------------ gnat

func build_gnat() -> void:
	gnat = MeshInstance3D.new()
	gnat.name = "Gnat"
	var quad := QuadMesh.new()
	quad.size = Vector2(GNAT_SIZE_M, GNAT_SIZE_M)
	gnat.mesh = quad
	gnat_material = StandardMaterial3D.new()
	gnat_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gnat_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gnat_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gnat_material.albedo_color = Color(0.03, 0.03, 0.04, 0.85)
	gnat_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	gnat.material_override = gnat_material
	gnat.visible = false
	add_child(gnat)


## Pick a smooth crossing: side to side at some depth in front of the (reference) camera, inside what it sees.
func start_gnat() -> void:
	var depth := _rng.randf_range(2.2, 6.5)
	var half_h := depth * tan(deg_to_rad(_camera_fov) / 2.0)
	var view := get_viewport().get_visible_rect().size            # the real hero aspect (the screen, not a guess)
	var half_w := half_h * view.x / maxf(view.y, 1.0)
	var forward := -_camera_reference.basis.z
	var right := _camera_reference.basis.x
	var up := _camera_reference.basis.y
	var from_left := _rng.randf() < 0.5
	var y0 := _rng.randf_range(-0.35, 0.45)
	var y1 := clampf(y0 + _rng.randf_range(-0.25, 0.25), -0.5, 0.6)
	var x0 := -1.15 if from_left else 1.15
	var base := _camera_reference.origin + forward * depth
	_gnat_from = base + right * (x0 * half_w) + up * (y0 * half_h)
	_gnat_to = base + right * (-x0 * half_w) + up * (y1 * half_h)
	_gnat_duration_s = _rng.randf_range(GNAT_CROSS_MIN_S, GNAT_CROSS_MAX_S)
	_gnat_start_s = time_s
	_gnat_salt = _rng.randi_range(1, 100000)
	_gnat_active = true
	gnat_material.albedo_color.a = 0.0          # it fades in from nothing, off the edge of the picture
	gnat.global_position = _gnat_from
	gnat.visible = true


func update_gnat() -> void:
	if not _gnat_active:
		if time_s < _gnat_next_s:
			return
		start_gnat()
	var u := (time_s - _gnat_start_s) / _gnat_duration_s
	if u >= 1.0:
		_gnat_active = false
		gnat.visible = false
		_gnat_next_s = time_s + _rng.randf_range(GNAT_GAP_MIN_S, GNAT_GAP_MAX_S)
		return
	var eased := clampf(u + 0.06 * sin(u * TAU * 1.5), 0.0, 1.0)         # monotonic (it always gets across) but not constant: it dawdles and darts
	var along := _gnat_from.lerp(_gnat_to, eased)
	var right := _camera_reference.basis.x
	var up := _camera_reference.basis.y
	var t := time_s - _gnat_start_s
	var wander := right * (0.09 * Handheld.smooth_noise(t * 1.7, _gnat_salt) + 0.03 * Handheld.smooth_noise(t * 5.3, _gnat_salt + 1)) \
		+ up * (0.07 * Handheld.smooth_noise(t * 2.1, _gnat_salt + 2) + 0.025 * Handheld.smooth_noise(t * 6.1, _gnat_salt + 3))
	gnat.global_position = along + wander
	gnat_material.albedo_color.a = 0.85 * smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.92, 1.0, u))


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not _built or not is_visible_in_tree():            # nothing runs while HOME is not on screen
		return
	time_s += delta
	var level := flicker.level(time_s)
	if aging_light != null:
		aging_light.light_energy = AGING_LIGHT_ENERGY * level
	if aging_material != null:
		aging_material.emission_energy_multiplier = aging_emission_base * level
	update_gnat()
