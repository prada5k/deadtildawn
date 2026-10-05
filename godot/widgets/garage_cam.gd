extends Control
## Home backdrop (Spire: "like recording the civic through a camcorder in a
## dark and partly lit parking lot", full screen, the menus in front): Spire's
## scanned underground garage (models/garage.glb, art/blender/prep_garage.py),
## the DX backed into a stall under the one tube that works, the rest of the
## level dark, a far tube flickering. Filmed handheld: the camera breathes and
## drifts, the picture goes through the VHS shader. The camcorder's OSD (REC,
## the date, the brackets) is the home screen's viewfinder (widgets/viewfinder.gd).
##
## Frame: Godot meters, the garage's floor at y = 0. Blender (x, y, z) from the
## prep script -> Godot (x, z, -y).

const DxModel := preload("res://widgets/dx_model.gd")
const GARAGE := "res://models/garage.glb"
const VHS := preload("res://widgets/vhs.gdshader")

const CAR_AT := Vector3(7.0, 0.0, 3.75)     # backed into the stall against the back wall, nose out (-x)
const TUBE := Color(0.82, 0.92, 1.0)        # cold fluorescent
const SODIUM := Color(1.0, 0.62, 0.28)      # the one orange lamp by the ramp
const SCAN_DIM := 0.32                       # the scan's baked light, turned down: our lights do the work
# The camcorder: where it stands in the aisle and what it's on (the car's front 3/4);
# AIM_DROP aims below the car so it sits high in the frame (the menus cover the bottom)
const CAM_AT := Vector3(2.4, 1.45, 1.2)
const LOOK_AT := Vector3(6.2, 0.5, 3.6)
const AIM_DROP := 1.25
const FOV := 68.0                            # horizontal (portrait screen)
const SWAY_M := 0.03                         # handheld: how far the hands wander (m)...
const SWAY_DEG := 0.7                        # ...and how much it tips
const DRIFT_M := 0.35                        # a slow side step back and forth...
const DRIFT_S := 16.0                        # ...over this long

var car: Node3D
var cam: Camera3D
var flicker: OmniLight3D
var flicker_tube: MeshInstance3D
var noise := FastNoiseLite.new()
var t := 0.0
var still := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for a in OS.get_cmdline_user_args():
		still = still or a == "--gametest" or a.begins_with("--gameshots")
	var box := SubViewportContainer.new()
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	box.add_child(vp)
	build_world(vp)
	# The tape: the VHS shader over the footage only (the menus are drawn after it)
	var tape := ColorRect.new()
	tape.set_anchors_preset(Control.PRESET_FULL_RECT)
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = VHS
	tape.material = sm
	add_child(tape)
	noise.seed = 7
	noise.frequency = 0.35
	noise.fractal_octaves = 2
	place_camera()


func build_world(vp: SubViewport) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.33, 0.4)
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.fog_enabled = true                      # the far end of the level fades into the dark
	env.fog_light_color = Color(0.03, 0.035, 0.05)
	env.fog_density = 0.07
	env.glow_enabled = true                     # the tubes bloom like they do on a camcorder
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	if ResourceLoader.exists(GARAGE):
		var garage: Node3D = (load(GARAGE) as PackedScene).instantiate()
		vp.add_child(garage)
		dim_scan(garage)

	# The tube over Faba's stall: the one that works. Cold, a little green.
	tube_light(vp, CAR_AT + Vector3(-0.6, 2.5, 0.0), 3.2, 6.5, true)
	# Down the aisle: one flickering, one dead, the sodium lamp by the ramp
	var f := tube_light(vp, Vector3(-2.5, 2.5, 5.5), 1.3, 7.0, false)
	flicker = f[0]
	flicker_tube = f[1]
	tube_mesh(vp, Vector3(1.5, 2.55, -2.0), Color(0.15, 0.16, 0.18), 0.0)     # dead
	var sodium := OmniLight3D.new()
	sodium.light_color = SODIUM
	sodium.light_energy = 1.1
	sodium.omni_range = 7.0
	sodium.position = Vector3(-4.5, 2.3, -2.5)
	vp.add_child(sodium)

	car = DxModel.new()
	car.lights_on = false
	car.position = CAR_AT
	car.rotation.y = PI                         # nose out into the aisle
	vp.add_child(car)

	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = FOV
	cam.near = 0.05
	vp.add_child(cam)


## The scan's photo light is baked in: turn it down and let the scene's lights
## (and the dark) shape it.
func dim_scan(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			var d := src.duplicate() as BaseMaterial3D
			d.albedo_color = d.albedo_color * Color(SCAN_DIM, SCAN_DIM, SCAN_DIM * 1.08)
			d.roughness = 0.85
			d.metallic = 0.0
			d.cull_mode = BaseMaterial3D.CULL_DISABLED     # the slimmed scan has faces turned the wrong way: draw both sides
			m.set_surface_override_material(i, d)


## A fluorescent fixture on the ceiling: the glowing tube and its light.
func tube_light(vp: Node, at: Vector3, energy: float, reach: float, shadows: bool) -> Array:
	var l := OmniLight3D.new()
	l.light_color = TUBE
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadows
	l.position = at - Vector3(0, 0.15, 0)
	vp.add_child(l)
	return [l, tube_mesh(vp, at, TUBE, 3.0)]


func tube_mesh(vp: Node, at: Vector3, color: Color, glow: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(1.25, 0.05, 0.1)
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	m.material_override = mat
	m.position = at
	vp.add_child(m)
	return m


func show_parts(ids: Array) -> void:
	if car != null:
		car.build(ids)


func place_camera() -> void:
	var drift := sin(t * TAU / DRIFT_S) * DRIFT_M
	var side := (LOOK_AT - CAM_AT).cross(Vector3.UP).normalized()
	var hand := Vector3(noise.get_noise_2d(t, 0.0), noise.get_noise_2d(t, 40.0), noise.get_noise_2d(t, 80.0)) * SWAY_M
	var pos := CAM_AT + side * drift + hand
	cam.look_at_from_position(pos, LOOK_AT - Vector3(0, AIM_DROP, 0))
	cam.rotate_object_local(Vector3.FORWARD, deg_to_rad(noise.get_noise_2d(t, 120.0) * SWAY_DEG))
	cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(noise.get_noise_2d(t, 160.0) * SWAY_DEG * 0.6))


func _process(delta: float) -> void:
	if still:
		return
	t += delta
	place_camera()
	# The bad tube: mostly on, then a stutter
	var n := noise.get_noise_2d(t * 6.0, 300.0)
	var on := n > -0.25 or randf() < 0.3
	flicker.light_energy = 1.3 if on else 0.05
	(flicker_tube.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if on else 0.2
