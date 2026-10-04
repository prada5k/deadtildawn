extends SubViewportContainer
## Race night backdrop: a canyon turnout over the Pacific after dark. Faba's DX
## and tonight's opponent parked nose to nose, headlights crossing on the
## gravel; moon, stars, and city lights down the coast. Still camera.
## Call setup(opponent_car_name, faba_parts) once it's in the tree.
##
## The opponent uses the DX body in his replay paint (widgets/car_sprite.gd
## profile), clean: a placeholder until there's a model per car. At night,
## behind his own headlights, he mostly reads as a shape.

const DxModel := preload("res://widgets/dx_model.gd")
const CarSprite := preload("res://widgets/car_sprite.gd")

const SKY_TOP := Color(0.015, 0.02, 0.06)
const SKY_HORIZON := Color(0.13, 0.1, 0.2)
const MOON := Color(0.75, 0.8, 1.0)
const OCEAN := Color(0.02, 0.03, 0.07)
const HEADLAND := Color(0.03, 0.025, 0.045)
const TURNOUT := Color(0.16, 0.15, 0.16)
const ARMCO := Color(0.55, 0.55, 0.58)
const HEADLIGHT := Color(1.0, 0.9, 0.7)
const CITY := [Color(1.0, 0.72, 0.38), Color(1.0, 0.86, 0.6), Color(0.85, 0.9, 1.0)]

const GAP := 3.9                 # m from the middle to each car's center

var vp: SubViewport
var faba_car: Node3D
var their_car: Node3D


func _ready() -> void:
	stretch = true
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP
	sky_mat.sky_horizon_color = SKY_HORIZON
	sky_mat.sky_curve = 0.2
	sky_mat.ground_horizon_color = SKY_HORIZON.darkened(0.5)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.33, 0.5)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	# Moonlight from up the coast: cold, faint, enough to rim the cars
	var moon := DirectionalLight3D.new()
	moon.light_color = MOON
	moon.light_energy = 0.35
	vp.add_child(moon)
	moon.look_at_from_position(Vector3(-300, 170, -700), Vector3.ZERO)

	build_world()

	faba_car = DxModel.new()
	faba_car.position.x = -GAP
	vp.add_child(faba_car)
	their_car = DxModel.new()
	their_car.rough = false
	their_car.position.x = GAP
	their_car.rotation.y = PI                # facing Faba
	vp.add_child(their_car)
	setup("", [])

	var cam := Camera3D.new()
	cam.fov = 44
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.3, 1.3, 10.6), Vector3(0.0, 2.1, 0.0))   # cars low, sky up top


## Paint the opponent like his replay car and put Faba's parts on the DX.
func setup(opponent_car: String, faba_parts: Array) -> void:
	if faba_car == null:
		return
	faba_car.build(faba_parts)
	headlights(faba_car)
	their_car.paint_color = CarSprite.profile_for(opponent_car)["paint"] if opponent_car != "" \
		else Color(0.3, 0.3, 0.32)
	their_car.build([])
	headlights(their_car)


## Two spotlights on the gravel ahead of a car (built with dx_model).
func headlights(car: Node3D) -> void:
	for side: float in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.light_color = HEADLIGHT
		spot.light_energy = 7.0
		spot.spot_range = 24.0
		spot.spot_angle = 26.0
		spot.position = Vector3(2.25, 0.64, side * 0.56)
		car.add_child(spot)
		spot.look_at(spot.global_position + car.global_transform.basis * Vector3(1, -0.1, side * 0.04))


func solid(mesh: Mesh, pos: Vector3, color: Color, rough := 0.9) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	m.material_override = mat
	vp.add_child(m)
	return m


## Many tiny glowing points as one MultiMesh (stars, city lights).
func points(positions: Array, colors: Array, radius: float) -> void:
	var dot := SphereMesh.new()
	dot.radius = radius
	dot.height = radius * 2.0
	dot.radial_segments = 6
	dot.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	dot.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = dot
	mm.instance_count = positions.size()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))
		mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	vp.add_child(inst)


func build_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 96

	# The turnout shelf, a thin cliff lip, Armco along the edge
	var shelf := BoxMesh.new()
	shelf.size = Vector3(60, 2, 14)
	solid(shelf, Vector3(0, -1, 2.5), TURNOUT, 0.95)
	var cliff := BoxMesh.new()
	cliff.size = Vector3(80, 70, 1.4)
	solid(cliff, Vector3(0, -35.2, -4.4), Color(0.06, 0.05, 0.06), 1.0)
	var rail := BoxMesh.new()
	rail.size = Vector3(40, 0.32, 0.06)
	var r := solid(rail, Vector3(0, 0.62, -3.6), ARMCO, 0.4)
	r.material_override.metallic = 0.7
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.75, 0.12)
	for i in range(-10, 11):
		solid(post, Vector3(i * 2.0, 0.37, -3.68), ARMCO.darkened(0.4), 0.6)

	# The Pacific, black and glossy enough to catch the moon
	var sea := PlaneMesh.new()
	sea.size = Vector2(6000, 6000)
	var water := solid(sea, Vector3(0, -45, 0), OCEAN, 0.08)
	water.material_override.metallic_specular = 1.0

	# Headlands down the coast, black against the sky (left of the moon's path)
	for h in [[Vector3(-560, -45, -780), Vector3(300, 55, 200)], [Vector3(-1150, -45, -980), Vector3(420, 48, 300)]]:
		var hill := SphereMesh.new()
		hill.radius = 1.0
		hill.height = 2.0
		var m := solid(hill, h[0], HEADLAND, 1.0)
		m.scale = h[1]

	# The moon over the water
	var disc := SphereMesh.new()
	disc.radius = 16.0
	disc.height = 32.0
	var moon := solid(disc, Vector3(-260, 150, -760), MOON)
	var mm: StandardMaterial3D = moon.material_override
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.2, 1.2, 1.1)

	# Stars: a dome of dots, thinning toward the horizon
	var stars := []
	var star_cols := []
	for i in 260:
		var az := rng.randf_range(-PI, 0.2)
		var el := asin(rng.randf_range(0.12, 1.0))
		stars.append(Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)) * 900.0)
		star_cols.append(Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.6)))
	points(stars, star_cols, 1.3)

	# City lights strung along the shore and up the headland
	var city := []
	var city_cols := []
	for i in 420:
		var x := rng.randf_range(-1000, -180)
		var z := rng.randf_range(-640, -540) + (x + 180.0) * 0.25
		city.append(Vector3(x, -44.0 + rng.randf_range(0, 14) * rng.randf(), z))
		city_cols.append(CITY[rng.randi() % CITY.size()] * rng.randf_range(0.7, 1.6))
	points(city, city_cols, 1.4)
