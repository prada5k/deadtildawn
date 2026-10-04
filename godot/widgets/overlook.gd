extends SubViewportContainer
## Home hero: the DX parked at a canyon turnout above the Pacific at dusk,
## headlights on. A still camera (no turntable). Shown inside the Polaroid on
## the home screen; call show_parts(ids) so installed parts appear on the car.

const DxModel := preload("res://widgets/dx_model.gd")

const SKY_TOP := Color(0.16, 0.12, 0.27)
const SKY_HORIZON := Color(0.93, 0.47, 0.25)
const SUN := Color(1.0, 0.62, 0.36)
const DUSK_FILL := Color(0.45, 0.5, 0.78)
const OCEAN := Color(0.09, 0.12, 0.24)
const HEADLAND := Color(0.2, 0.15, 0.24)
const TURNOUT := Color(0.2, 0.18, 0.18)
const ARMCO := Color(0.62, 0.62, 0.64)

var car: Node3D


func _ready() -> void:
	stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP
	sky_mat.sky_horizon_color = SKY_HORIZON
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = SKY_HORIZON.darkened(0.4)
	sky_mat.ground_bottom_color = Color(0.05, 0.04, 0.08)
	sky_mat.sun_angle_max = 8.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.35, 0.4)
	env.fog_density = 0.00035
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	# Low sun behind the car, over the ocean: rims the car in orange
	var sun := DirectionalLight3D.new()
	sun.light_color = SUN
	sun.light_energy = 1.5
	vp.add_child(sun)
	sun.look_at_from_position(Vector3(-60, 6, -90), Vector3.ZERO)
	# Cool dusk fill from the camera side so the white paint still reads
	var fill := DirectionalLight3D.new()
	fill.light_color = DUSK_FILL
	fill.light_energy = 0.55
	vp.add_child(fill)
	fill.look_at_from_position(Vector3(40, 30, 60), Vector3.ZERO)

	build_world(vp)

	car = DxModel.new()
	vp.add_child(car)
	show_parts([])

	var cam := Camera3D.new()
	cam.fov = 42
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(4.9, 2.3, 5.3), Vector3(-2.2, 0.15, -2.6))


## Rebuild the car with these installed parts, headlights on the gravel.
func show_parts(ids: Array) -> void:
	if car == null:
		return
	car.build(ids)
	for side: float in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.92, 0.72)
		spot.light_energy = 3.0
		spot.spot_range = 22.0
		spot.spot_angle = 24.0
		spot.position = Vector3(2.25, 0.64, side * 0.56)
		car.add_child(spot)
		spot.look_at(spot.global_position + Vector3(1, -0.12, side * 0.05))


func solid(mesh: Mesh, pos: Vector3, color: Color, rough := 0.9, parent: Node = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	m.material_override = mat
	parent.add_child(m)
	return m


func build_world(vp: Node) -> void:
	# The turnout: a gravel/asphalt shelf, the cliff drops away behind the rail
	var shelf := BoxMesh.new()
	shelf.size = Vector3(60, 2, 14)
	solid(shelf, Vector3(0, -1, 2.5), TURNOUT, 0.95, vp)
	var cliff := BoxMesh.new()                   # a thin lip past the rail, then the drop
	cliff.size = Vector3(80, 70, 1.4)
	solid(cliff, Vector3(0, -35.2, -4.4), Color(0.17, 0.13, 0.13), 1.0, vp)

	# Pacific: glossy enough to catch the sun
	var sea := PlaneMesh.new()
	sea.size = Vector2(6000, 6000)
	var water := solid(sea, Vector3(0, -45, 0), OCEAN, 0.12, vp)
	water.material_override.metallic_specular = 0.9

	# Headlands down the coast, fading into the haze
	# (all to the left of the shot, like the coast running north; open sea under the sun)
	for h in [[Vector3(-430, -45, -170), Vector3(190, 58, 150)], [Vector3(-950, -45, -120), Vector3(320, 52, 300)],
			[Vector3(-1500, -45, -420), Vector3(420, 40, 320)]]:
		var hill := SphereMesh.new()
		hill.radius = 1.0
		hill.height = 2.0
		var m := solid(hill, h[0], HEADLAND, 1.0, vp)
		m.scale = h[1]

	# Armco along the edge, posts every 2 m
	var rail := BoxMesh.new()
	rail.size = Vector3(40, 0.32, 0.06)
	var r := solid(rail, Vector3(0, 0.62, -3.6), ARMCO, 0.4, vp)
	r.material_override.metallic = 0.7
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.75, 0.12)
	for i in range(-10, 11):
		solid(post, Vector3(i * 2.0, 0.37, -3.68), ARMCO.darkened(0.3), 0.6, vp)
