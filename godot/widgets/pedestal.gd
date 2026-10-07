extends SubViewportContainer
## Hero pedestal: a low-poly 1995 Civic EG6 hatch on a slow turntable.
## Built from primitive meshes (factory dimensions: 4.070 m long, 1.695 m wide,
## 2.570 m wheelbase). Placeholder art: swap in a real model later by replacing
## build_car() with an imported scene (.glb) under `turntable`.

const SPIN_DEG_PER_S := 14.0
const BODY := Color(0.62, 0.07, 0.09)
const GLASS := Color(0.06, 0.07, 0.09)
const TIRE := Color(0.05, 0.05, 0.05)
const RIM := Color(0.55, 0.56, 0.6)
const PLATFORM := Color(0.13, 0.08, 0.09)
const ACCENT := Color(0.839, 0.251, 0.271)    # #D64045

var turntable: Node3D


func _ready() -> void:
	stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.5, 0.52)
	env.environment.ambient_light_energy = 0.6
	vp.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, -150, 0)
	rim.light_color = ACCENT
	rim.light_energy = 0.6
	vp.add_child(rim)

	var cam := Camera3D.new()
	cam.fov = 32
	cam.position = Vector3(6.4, 3.0, 6.4)
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.45, 0))

	turntable = Node3D.new()
	vp.add_child(turntable)
	build_platform()
	build_car()


func _process(delta: float) -> void:
	if turntable:
		turntable.rotate_y(deg_to_rad(SPIN_DEG_PER_S) * delta)


func mat(color: Color, emissive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.45
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.5
	return m


func part(mesh: Mesh, color: Color, pos: Vector3, rot_deg := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, emissive)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	turntable.add_child(mi)
	return mi


func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func build_platform() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 3.3
	disc.bottom_radius = 3.4
	disc.height = 0.12
	disc.radial_segments = 48
	part(disc, PLATFORM, Vector3(0, -0.06, 0))
	var ring := TorusMesh.new()
	ring.inner_radius = 3.22
	ring.outer_radius = 3.36
	ring.rings = 48
	part(ring, ACCENT, Vector3(0, 0.01, 0), Vector3.ZERO, true)
	for i in range(-2, 3):                      # grid lines on the platform
		part(box(Vector3(5.6, 0.005, 0.03)), Color(0.3, 0.2, 0.21), Vector3(0, 0.005, i * 1.1))
		part(box(Vector3(0.03, 0.005, 5.6)), Color(0.3, 0.2, 0.21), Vector3(i * 1.1, 0.005, 0))


func build_car() -> void:
	# x = length (front is +x), z = width, y = up
	part(box(Vector3(4.070, 0.5, 1.695)), BODY, Vector3(0, 0.55, 0))
	part(box(Vector3(1.1, 0.12, 1.62)), BODY, Vector3(1.42, 0.86, 0), Vector3(0, 0, -4))
	part(box(Vector3(0.32, 0.1, 1.62)), BODY, Vector3(-1.87, 0.84, 0))      # short hatch tail
	part(box(Vector3(2.25, 0.46, 1.48)), GLASS, Vector3(-0.3, 1.02, 0))
	part(box(Vector3(1.5, 0.06, 1.46)), BODY, Vector3(-0.36, 1.27, 0))
	part(box(Vector3(0.08, 0.44, 1.5)), BODY, Vector3(-1.52, 1.03, 0))
	part(box(Vector3(0.06, 0.12, 0.42)), Color(1, 0.96, 0.88), Vector3(2.01, 0.68, 0.55), Vector3.ZERO, true)
	part(box(Vector3(0.06, 0.12, 0.42)), Color(1, 0.96, 0.88), Vector3(2.01, 0.68, -0.55), Vector3.ZERO, true)
	part(box(Vector3(0.06, 0.1, 0.5)), Color(0.9, 0.08, 0.08), Vector3(-2.01, 0.7, 0.52), Vector3.ZERO, true)
	part(box(Vector3(0.06, 0.1, 0.5)), Color(0.9, 0.08, 0.08), Vector3(-2.01, 0.7, -0.52), Vector3.ZERO, true)
	for x in [1.285, -1.285]:                   # wheelbase 2.570 m
		for z in [0.76, -0.76]:
			var t := CylinderMesh.new()
			t.top_radius = 0.3
			t.bottom_radius = 0.3
			t.height = 0.2
			part(t, TIRE, Vector3(x, 0.3, z), Vector3(90, 0, 0))
			var r := CylinderMesh.new()
			r.top_radius = 0.18
			r.bottom_radius = 0.18
			r.height = 0.21
			part(r, RIM, Vector3(x, 0.3, z), Vector3(90, 0, 0))
