extends Control
## Home backdrop (Spire: "like recording the civic through a camcorder in a
## dark and partly lit parking lot", full screen, the menus in front): an
## underground garage built low poly in code (build_lot, laid out like Spire's scan),
## the DX backed into a stall under the one tube that works, the rest of the
## level dark, a far tube flickering. Filmed handheld: the camera breathes and
## drifts, the picture goes through the VHS shader. The camcorder's OSD (REC,
## the date, the brackets) is the home screen's viewfinder (widgets/viewfinder.gd).
##
## Frame: Godot meters, the floor at y = 0, the stalls' back wall at x = BACK_X.

const DxModel := preload("res://widgets/dx_model.gd")
const CarModel := preload("res://widgets/car_model.gd")
const VHS := preload("res://widgets/vhs.gdshader")

const CAR_AT := Vector3(7.0, 0.0, 3.75)     # backed into the stall against the back wall, nose out (-x)
const TUBE := Color(0.82, 0.92, 1.0)        # cold fluorescent
const SODIUM := Color(1.0, 0.62, 0.28)      # the one orange lamp by the ramp
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
var other: Node3D                # the other cars parked in the garage (settings: hide them)
const PARKED := ["1995 Honda Accord LX", "1989 Toyota Corolla GT-S (AE86)", "1977 Nissan 280Z",
	"2009 Nissan 370Z", "Toyota Celica", "Mitsubishi Lancer Evolution III", "1998 Mitsubishi Eclipse GS-T",
	"2002 Volkswagen GTI 1.8T", "2006 Mazdaspeed 3", "2009 Honda Civic Si (FA5)"]
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

	build_lot(vp)

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


## The garage, low poly (Spire: low-poly kanjo): laid out like Spire's scan
## (art/models/parking_garage.glb), built from flat-shaded shapes. A row of
## stalls along the back wall (x = BACK_X), the aisle in front, pillars with
## red/white hazard bands at the stalls' mouths, ceiling beams, a concrete
## floor of faceted tiles, a second car parked in the dark.
const BACK_X := 9.3
const ROOM := Rect2(-8.0, -6.0, 17.3, 17.0)    # x, z extent of the level
const CEIL_Y := 2.75
const CONCRETE := Color(0.42, 0.41, 0.4)
const FLOOR := Color(0.3, 0.29, 0.28)
const BAND := Color(0.26, 0.3, 0.36)          # the gray-blue strip along the walls' feet
const PAINT := Color(0.86, 0.86, 0.82)        # stall lines
const HAZARD := Color(0.8, 0.16, 0.1)


func build_lot(vp: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	add_mesh(vp, facet_floor(rng), true)
	# Ceiling slab and beams across it
	solid(vp, Vector3(ROOM.size.x, 0.25, ROOM.size.y), Vector3(ROOM.get_center().x, CEIL_Y + 0.125, ROOM.get_center().y), CONCRETE.darkened(0.25))
	for z in range(int(ROOM.position.y) + 1, int(ROOM.end.y), 5):
		solid(vp, Vector3(ROOM.size.x, 0.35, 0.3), Vector3(ROOM.get_center().x, CEIL_Y - 0.17, z), CONCRETE.darkened(0.15))
	# Walls: concrete with the band along the bottom
	for w: Array in [[Vector3(0.3, CEIL_Y, ROOM.size.y), Vector3(BACK_X + 0.15, 0, ROOM.get_center().y)],
			[Vector3(ROOM.size.x, CEIL_Y, 0.3), Vector3(ROOM.get_center().x, 0, ROOM.end.y)],
			[Vector3(ROOM.size.x, CEIL_Y, 0.3), Vector3(ROOM.get_center().x, 0, ROOM.position.y)],
			[Vector3(0.3, CEIL_Y, ROOM.size.y), Vector3(ROOM.position.x, 0, ROOM.get_center().y)]]:
		var size: Vector3 = w[0]
		var at: Vector3 = w[1]
		solid(vp, size, at + Vector3(0, CEIL_Y / 2.0, 0), CONCRETE)
		solid(vp, size + Vector3(0.02, 0, 0.02) * Vector3(1 if size.x < 1 else 0, 0, 1 if size.z < 1 else 0)
			+ Vector3(0, 0.45 - CEIL_Y, 0), at + Vector3(0, 0.225, 0), BAND)
	# The stalls along the back wall: lines across, a stop line at the mouth
	for z: float in [-2.5, 0.0, 2.5, 5.0, 7.5, 10.0]:
		solid(vp, Vector3(4.5, 0.012, 0.11), Vector3(BACK_X - 2.25, 0.006, z), PAINT)
	solid(vp, Vector3(0.11, 0.012, 12.6), Vector3(4.8, 0.006, 3.75), PAINT.darkened(0.25))
	# Wheel stops in each stall
	for z: float in [-1.25, 1.25, 3.75, 6.25, 8.75]:
		solid(vp, Vector3(0.18, 0.12, 1.6), Vector3(BACK_X - 0.75, 0.06, z), Color(0.55, 0.53, 0.5))
	# Pillars at the stalls' mouths and across the aisle, hazard-banded
	for p: Vector2 in [Vector2(4.6, -2.5), Vector2(4.6, 10.0), Vector2(4.6, 7.5), Vector2(-3.0, 0.0), Vector2(-3.0, 7.5)]:
		pillar(vp, Vector3(p.x, 0, p.y))
	# Things on the walls: the yellow notice, a fire hose box, the green exit
	solid(vp, Vector3(0.03, 0.3, 0.42), Vector3(BACK_X - 0.01, 1.7, 5.0), Color(0.85, 0.7, 0.1))
	solid(vp, Vector3(0.12, 0.55, 0.5), Vector3(BACK_X - 0.06, 1.15, 0.6), HAZARD)
	glow_box(vp, Vector3(0.05, 0.16, 0.4), Vector3(BACK_X - 0.02, 2.35, 9.0), Color(0.2, 0.95, 0.4), 2.5)
	# Oil stains under where cars sit
	for z: float in [3.75, 8.75, -1.25]:
		solid(vp, Vector3(1.1, 0.004, 0.8), Vector3(BACK_X - 2.4, 0.003, z + rng.randf_range(-0.2, 0.2)), Color(0.12, 0.11, 0.1))
	# Someone else's car, two stalls down in the dark
	# Other people's cars in the other stalls (Spire: random ones): a few of the
	# model cars, a new mix every time you come home; some backed in, some nosed in
	other = Node3D.new()
	vp.add_child(other)
	var pool := PARKED.duplicate()
	pool.shuffle()
	var stalls := [-1.25, 1.25, 6.25, 8.75]
	stalls.shuffle()
	for k in randi_range(2, 3):
		var c: Node3D = CarModel.new()
		c.build_car(pool[k], false)
		var backed_in := randf() < 0.6
		c.position = Vector3(7.0 if backed_in else 6.8, 0, stalls[k] + randf_range(-0.12, 0.12))
		c.rotation.y = (PI if backed_in else 0.0) + randf_range(-0.05, 0.05)
		other.add_child(c)


## The floor: 1 m tiles split into two triangles each, every triangle its own
## slightly different grey and a few millimeters off level, flat-shaded: the
## low-poly concrete look.
func facet_floor(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := int(ROOM.position.x)
	var z0 := int(ROOM.position.y)
	var nx := int(ROOM.size.x) + 1
	var nz := int(ROOM.size.y) + 1
	var h := {}
	for i in nx + 1:
		for j in nz + 1:
			h[Vector2i(i, j)] = rng.randf_range(-0.012, 0.012)
	for i in nx:
		for j in nz:
			var c := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			var p := []
			for k: Vector2i in c:
				p.append(Vector3(x0 + k.x, h[k], z0 + k.y))
			for tri: Array in [[p[0], p[2], p[1]], [p[0], p[3], p[2]]]:
				var a: Vector3 = tri[0]
				var b: Vector3 = tri[1]
				var d: Vector3 = tri[2]
				var n := (b - a).cross(d - a).normalized()
				var col := FLOOR.lightened(rng.randf_range(-0.06, 0.08)) if rng.randf() > 0.08 else FLOOR.darkened(0.3)
				st.set_color(col)
				st.set_normal(n)
				for v: Vector3 in tri:
					st.add_vertex(v)
	return st.commit()


func add_mesh(vp: Node, mesh: Mesh, vertex_colors: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = vertex_colors
	m.roughness = 0.9
	mi.material_override = m
	vp.add_child(mi)


func solid(vp: Node, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	mi.position = at
	vp.add_child(mi)
	return mi


func glow_box(vp: Node, size: Vector3, at: Vector3, color: Color, energy: float) -> void:
	var mi := solid(vp, size, at, color)
	var m: StandardMaterial3D = mi.material_override
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy


## A round concrete pillar (8 sides: faceted) with red / white hazard bands.
func pillar(vp: Node, at: Vector3) -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.22
	c.bottom_radius = 0.22
	c.height = CEIL_Y
	c.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = CONCRETE.lightened(0.1)
	m.roughness = 0.9
	mi.material_override = m
	mi.position = at + Vector3(0, CEIL_Y / 2.0, 0)
	vp.add_child(mi)
	for k in 6:
		var band := CylinderMesh.new()
		band.top_radius = 0.225
		band.bottom_radius = 0.225
		band.height = 0.2
		band.radial_segments = 8
		var bi := MeshInstance3D.new()
		bi.mesh = band
		var bm := StandardMaterial3D.new()
		bm.albedo_color = HAZARD if k % 2 == 0 else Color(0.9, 0.9, 0.86)
		bm.roughness = 0.8
		bi.material_override = bm
		bi.position = at + Vector3(0, 0.3 + k * 0.2, 0)
		vp.add_child(bi)


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


## Faba's car on or off (the other screens' dimmed backdrop: the lot without it).
func show_car(on: bool) -> void:
	if car != null:
		car.visible = on


## The other car in the garage, on or off (the settings screen).
func show_parked_car(on: bool) -> void:
	if other != null:
		other.visible = on


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
