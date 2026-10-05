extends Node3D
## The CHASE view in 3D (Spire, after the Topfoil Evo touge videos): the road
## and its place built in 3D from the replay, the car this view films, and
## the CAMERA CAR behind it: a camera in a second car, low, at night, nothing
## of it showing but its HID headlights on the road and on the car ahead.
##
## Built once (build(viewer)) by a split-screen pane of the replay viewer
## (main.gd, pane mode); every frame sync(viewer) copies the viewer's state
## in. main.gd stays the ONE place that drives things: where each car is
## along the road (the sim's), its line across it, its body's roll and pitch
## (car_sprite.gd load_g), the camera car's speed and gap (camcar_*), the
## spotters' and flagger's lights, the crash. This only draws, so the 3D view
## and the 2D overview always agree.
##
## Axes: the 2D world's (x, y) in px -> 3D (x, 0, y) / px_per_m (meters, +y up:
## the 2D map is the ground seen from above). A 2D rotation r (clockwise on
## screen) is a 3D yaw of -r. Car models: +x forward, +z right (dx_model.gd).
##
## The camera: in the camera car at CAM_H_M, aimed by an operator who keeps
## the car in frame a beat late (PAN_RATE) and zooms slowly to keep it about
## FRAME_W_M wide; the camera car's own body roll, braking dive and road buzz
## move the shot (its cornering, not the subject's: the camera is in it).

const DxModel := preload("res://widgets/dx_model.gd")
const CarModel := preload("res://widgets/car_model.gd")
const Road2D := preload("res://widgets/road.gd")
const Land2D := preload("res://widgets/scenery.gd")
const SkyShader := preload("res://widgets/night_sky.gdshader")

# The camera
const CAM_H_M := 2.0             # camera on the camera car's roof (sees over the car, down the road)
const AIM_UP_M := 0.7            # the operator frames the car low in the shot...
const AIM_LEAD_M := 1.5          # ...and a little ahead of it (room to drive into)
const PAN_RATE := 5.0            # 1/s: how fast his pan catches up (a beat late)
const FRAME_W_M := 9.5           # he zooms to keep about this much width at the car...
const WRECK_FRAME_W_M := 14.0    # ...more around a wreck
const FOV_MIN := 24.0            # ...within the lens's range (vertical degrees)
const FOV_MAX := 62.0
const ZOOM_RATE := 1.2           # 1/s: zooms slowly, like a person
const ROLL_PER_G := 0.035        # rad: the camera car's body roll per g of ITS cornering
const PITCH_PER_MS2 := 0.0035    # rad per m/s^2: dives braking, squats on the gas
const BUZZ_RAD := 0.0028         # road buzz (rad) at 40 m/s, growing with v^2 (Spire: gentle)...
const BUZZ_TURN_RAD := 0.0025    # ...plus this per g of cornering
const SHAKE_RAD := 0.035         # a crash
const NEAR_M := 0.25             # near/far clip (a near plane further out keeps the paint
const FAR_M := 2500.0            # on the road from flickering in the distance)
# The filmed car's body on its springs: radians per m of car_sprite's body shift
const BODY_ROLL := 0.22          # ~2.5 deg per g, to the outside
const BODY_PITCH := 0.2          # ~1.8 deg per g, nose down braking
const CRASH_TILT := Vector3(0.1, 0.0, -0.08)   # in the ditch: leaned over, nose down
const BUMP_M := 0.012            # the body over the road's bumps at 40 m/s (m up and down)...
const BUMP_PITCH := 0.006        # ...and rocking (rad)
const BUMP_EVERY := 0.08         # 1/m: a swell every ~12 m (~2.5 Hz at 30 m/s: the body, not the wheels)

# Speed (Spire: immersion)
const BLUR_FROM_MS := 14.0       # speed blur starts at 50 km/h...
const BLUR_FULL_MS := 42.0       # ...full at 150 km/h
const DUST_AHEAD_M := 12.0       # dust and bugs in the camera car's lights: a box this far ahead...
const DUST_BOX := Vector3(4.5, 1.2, 10.0)   # ...this big (half extents: across, up, along)
const DUST_ALPHA := 0.85
const BEAM_HAZE := 0.09         # the filmed car's headlight beams in the night air
const ADVISORY_G := 0.2          # curve warning signs: the advisory speed holds this lateral g (MUTCD-ish)

# Night
const MOON_DIR := Vector3(-0.8, 0.3, -0.35)    # low over the Pacific (west)
const MOON := Color(0.75, 0.8, 1.0)
const AMBIENT := Color(0.34, 0.38, 0.6)
const FOG := Color(0.025, 0.03, 0.055)
const FOG_DENSITY := 0.0075      # 1/m: half gone by ~90 m, the road ahead melts into the dark
const HALOGEN := Color(1.0, 0.9, 0.72)
const HID := Color(0.88, 0.93, 1.0)            # the camera car's: bluer than the racers'
const HAZARD := Color(1.0, 0.55, 0.1)
const BRAKE_RED := Color(1.0, 0.06, 0.04)

# The place
const ROAD_HALF_M := 4.0
const SHOULDER_M := 1.2          # gravel past the edge, then the land
const LINE_W_M := 0.15
const CHUNK := 60                # road points (m) per mesh: lights only redraw the chunks they reach
const SEA_DROP_M := 26.0         # coast: the cliff down to the water
const VOID_DROP_M := 340.0       # mountain: the drop to the valley
const SIGN_W_M := 0.75           # chevron sign (a real one is 0.45 x 0.6; bigger so it reads on a phone)
const SIGN_H_M := 0.95
const SIGN_UP_M := 0.9           # bottom of the sign
const SIGN_OUT_M := 1.6          # past the edge of the asphalt
const POST_OUT_M := 1.0
const ROCK := Color(0.34, 0.28, 0.24)
const GRAVEL := Color(0.3, 0.28, 0.25)
const TRUNK := Color(0.16, 0.12, 0.09)
const JACKET := Color(0.1, 0.1, 0.12)
const SKIN := Color(0.55, 0.42, 0.33)
const HI_VIS := Color(0.78, 0.95, 0.2)          # spotters' vests
const WARN_YELLOW := Color(1.0, 0.8, 0.1)       # curve warning signs
const FLARE_M := 1.1             # a flashlight pointed at the lens: this big a glow

var px := 4.0                    # the 2D world's px per m
var road := PackedVector2Array() # centerline (m, (x, z)), 1 m apart
var right := PackedVector2Array()  # unit normal to the right of travel
var who := "car"                 # the filmed car: "car" (Faba) or "ghost" (him)
var car := {}                    # its nodes: root, body, head, tail, brakes, hazard...
var camcar_lamps := []
var people := []                 # spotters + the flagger: {"root", "lamp", "lens", "lens_mat", "src", "beam", "flagger"}
var cam: Camera3D
var aim := Vector3.ZERO          # where the operator points (unit), smoothed
var fov := 45.0
var roll := 0.0
var pitch := 0.0
var last_v := -1.0
var accel := 0.0                 # the camera car's, smoothed (m/s^2)
var crashed := false
var fx: Node3D                   # crash sparks + smoke
var buzz := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var scatter := {}                # "kind:chunk" -> [transforms, colors] (bushes, trees...)
var noise_tex: NoiseTexture2D
var blur := 0.0                  # speed blur, 0..1 (read by main.gd for the pane's shader)
var flow := Vector2(0.5, 0.45)   # where the camera's heading on screen (0..1)
var dust: CPUParticles3D
var dust_mat: StandardMaterial3D
var gravel: CPUParticles3D       # dust off the shoulder when the car runs wide (or goes off)
var bumps := FastNoiseLite.new()
var _flame_until := 0.0          # a pop's flame burns until this real time...
var _flame_len := 0.6            # ...this long (m)
var cops := []                   # the cruiser behind the camera car: [red, blue] lights


# ------------------------------------------------------------------ build

func build(v: Node) -> void:
	px = v.PX_PER_M
	who = v.subject()
	rng.seed = 96 + v.road_pts.size()
	buzz.seed = 5
	buzz.frequency = 1.0
	for p in v.road_pts:
		road.append(p / px)
	right.resize(road.size())
	for i in road.size():
		var d := (road[mini(i + 1, road.size() - 1)] - road[maxi(i - 1, 0)]).normalized()
		right[i] = Vector2(-d.y, d.x)
	var grain := FastNoiseLite.new()
	grain.frequency = 0.05
	noise_tex = NoiseTexture2D.new()
	noise_tex.seamless = true
	noise_tex.noise = grain
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.72, 0.72))
	ramp.set_color(1, Color(1, 1, 1))
	noise_tex.color_ramp = ramp

	build_sky()
	build_land(v)
	build_road()
	build_posts()
	for c in v.corners:
		build_chevrons(c, v.severity_color(int(c["severity"])))
	match str(v.location):
		"coast":
			build_coast(v.land)
		"canyon":
			build_canyon(v)
		"mountain":
			build_mountain(v.land)
	flush_scatter()
	build_car(v)
	for k in 2:
		var lamp := spot(HID, 2.4, 85.0, 21.0)
		camcar_lamps.append(lamp)
	for sp: Dictionary in v.spotters:
		people.append(make_person(sp["node"], sp["beam"], false))
	people.append(make_person(v.flagger, v.lights["flagger"], true))
	build_warnings(v.corners)
	build_speed_fx()
	for col: Color in [Color(1.0, 0.08, 0.05), Color(0.1, 0.25, 1.0)]:
		var l := OmniLight3D.new()
		l.light_color = col
		l.omni_range = 34.0
		l.light_energy = 0.0
		l.visible = false
		add_child(l)
		cops.append(l)
	fx = Node3D.new()
	add_child(fx)
	cam = Camera3D.new()
	cam.near = NEAR_M
	cam.far = FAR_M
	add_child(cam)
	cam.make_current()


func m3(p2: Vector2, y := 0.0) -> Vector3:
	## A 2D world point (px) in 3D (m).
	return Vector3(p2.x / px, y, p2.y / px)


## A point beside the road: off_m to the right of point i, at height y.
func at(i: int, off_m: float, y: float) -> Vector3:
	var p := road[i] + right[i] * off_m
	return Vector3(p.x, y, p.y)


func mat(color: Color, rough := 0.9, grain := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED      # hand-built strips: either side may face us
	if grain:                                         # world-space noise: no UVs needed
		m.albedo_texture = noise_tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * 0.18
	return m


func glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func mesh_node(mesh: Mesh, material: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi


func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func spot(color: Color, energy: float, reach: float, angle: float) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = reach
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.6
	add_child(l)
	return l


## Strip of quads beside the road from point i0 to i1, between offsets a and b
## (m right of the middle), at height y.
func strip(st: SurfaceTool, i0: int, i1: int, a: float, b: float, y: float) -> void:
	for i in range(i0, i1):
		st.add_vertex(at(i, a, y))
		st.add_vertex(at(i + 1, a, y))
		st.add_vertex(at(i + 1, b, y))
		st.add_vertex(at(i, a, y))
		st.add_vertex(at(i + 1, b, y))
		st.add_vertex(at(i, b, y))


func flat_tool() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	return st


## One lit triangle; its normal faces `toward` (both sides draw anyway).
func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, toward: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.dot(toward) < 0.0:
		n = -n
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


# ------------------------------------------------------------------ sky + land

func build_sky() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SkyShader
	sky_mat.set_shader_parameter("moon_dir", MOON_DIR)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 0.95
	env.fog_enabled = true
	env.fog_light_color = FOG
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = MOON
	moon.light_energy = 0.22
	moon.transform.basis = Basis.looking_at(-MOON_DIR.normalized(), Vector3.UP)
	add_child(moon)


## The ground: everywhere, or (coast / mountain) only on the land side of the
## edge the 2D scenery drew: the sea or the drop is beyond it.
func build_land(v: Node) -> void:
	var land: Node2D = v.land
	var lo := road[0]
	var hi := road[0]
	for p in road:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var far := Rect2(lo, hi - lo).grow(1800.0)
	var poly := PackedVector2Array()
	var edge := edge_m(land)
	if edge.size() < 2:
		poly = PackedVector2Array([far.position, Vector2(far.end.x, far.position.y), far.end,
			Vector2(far.position.x, far.end.y)])
	else:
		var side: float = land.edge_side
		var keep_x := far.end.x if side < 0.0 else far.position.x     # the land side
		poly.append(Vector2(edge[0].x, far.position.y))
		poly.append_array(edge)
		poly.append(Vector2(edge[-1].x, far.end.y))
		poly.append(Vector2(keep_x, far.end.y))
		poly.append(Vector2(keep_x, far.position.y))
	var idx := Geometry2D.triangulate_polygon(poly)
	var st := flat_tool()
	for k in idx:
		st.add_vertex(Vector3(poly[k].x, -0.06, poly[k].y))
	var ground_col: Color = Land2D.GROUND.get(v.location, Land2D.GROUND["canyon"])
	mesh_node(st.commit(), mat(ground_col, 1.0, true))


## The 2D scenery's coast / drop-off line, in meters ([] if this place has none).
func edge_m(land: Node2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	if land == null or land.edge.size() < 2:
		return out
	for p: Vector2 in land.edge:
		out.append(p / px)
	return out


## A cliff face along the edge from the land (y = 0) down to `drop`, its foot
## pushed `out_m` beyond the edge.
func cliff(edge: PackedVector2Array, side: float, drop: float, out_m: float, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := Vector3(side, 0.3, 0.0)              # out over the water / the valley
	for k in edge.size() - 1:
		var j := rng.randf_range(-3.0, 3.0)
		var a := Vector3(edge[k].x, 0.0, edge[k].y)
		var b := Vector3(edge[k + 1].x, 0.0, edge[k + 1].y)
		var a2 := Vector3(edge[k].x + side * (out_m + j), -drop, edge[k].y)
		var b2 := Vector3(edge[k + 1].x + side * (out_m + j), -drop, edge[k + 1].y)
		tri(st, a, b, b2, faces)
		tri(st, a, b2, a2, faces)
	mesh_node(st.commit(), mat(color, 1.0, true))


# ------------------------------------------------------------------ the road

func build_road() -> void:
	var n := road.size()
	var asphalt := mat(Road2D.ASPHALT, 0.85, true)
	asphalt.uv1_scale = Vector3.ONE * 0.6             # finer grain than the land: ~1.5 m blotches
	var gravel := mat(GRAVEL, 1.0, true)
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 0.6
	var edge_off := ROAD_HALF_M - 0.35
	var i0 := 0
	while i0 < n - 1:
		var i1 := mini(i0 + CHUNK, n - 1)
		var mesh := ArrayMesh.new()
		var st := flat_tool()
		strip(st, i0, i1, -ROAD_HALF_M, ROAD_HALF_M, 0.0)
		st.commit(mesh)
		st = flat_tool()
		strip(st, i0, i1, -ROAD_HALF_M - SHOULDER_M, -ROAD_HALF_M, -0.025)
		strip(st, i0, i1, ROAD_HALF_M, ROAD_HALF_M + SHOULDER_M, -0.025)
		st.commit(mesh)
		st = flat_tool()
		st.set_color(Road2D.EDGE_LINE)
		for s: float in [-1.0, 1.0]:
			strip(st, i0, i1, s * edge_off - LINE_W_M / 2.0, s * edge_off + LINE_W_M / 2.0, 0.02)
		st.set_color(Road2D.CENTER_LINE)
		for i in range(i0, i1):                       # dashes: 3 m on, 6 m off (as the overview)
			if i % (Road2D.DASH_M + Road2D.GAP_M) < Road2D.DASH_M:
				strip(st, i, i + 1, -LINE_W_M / 2.0, LINE_W_M / 2.0, 0.02)
		# Old asphalt: patches and tar snakes (sealed cracks). Detail on the road
		# is what flows past under the lights: it's how speed reads
		for q in rng.randi_range(1, 4):
			var pi0 := rng.randi_range(i0, maxi(i1 - 4, i0))
			var a := rng.randf_range(-3.6, 2.2)
			st.set_color(Road2D.ASPHALT.darkened(rng.randf_range(0.18, 0.4)) if rng.randf() < 0.7
				else Road2D.ASPHALT.lightened(0.14))
			strip(st, pi0, mini(pi0 + rng.randi_range(2, 7), i1), a, minf(a + rng.randf_range(0.8, 2.6), 3.8), 0.008)
		st.set_color(Road2D.ASPHALT.darkened(0.38))
		for q in rng.randi_range(0, 3):
			var a := rng.randf_range(-3.5, 3.4)
			for j in range(rng.randi_range(i0, maxi(i1 - 10, i0)), mini(i1, i0 + 60)):
				a = clampf(a + rng.randf_range(-0.18, 0.18), -3.7, 3.6)
				strip(st, j, j + 1, a, a + 0.07, 0.009)
				if rng.randf() < 0.08:
					break
		st.set_color(Color.WHITE)                     # start and finish lines across the road
		for i: int in [0, n - 1]:
			if i >= i0 and i <= i1:
				var along := Vector2(right[i].y, -right[i].x)
				for k in 2:
					var q := [road[i] + along * 0.3 - right[i] * ROAD_HALF_M, road[i] + along * 0.3 + right[i] * ROAD_HALF_M,
						road[i] - along * 0.3 + right[i] * ROAD_HALF_M, road[i] - along * 0.3 - right[i] * ROAD_HALF_M]
					var tri_k: Array = [0, 1, 2] if k == 0 else [0, 2, 3]
					for j: int in tri_k:
						st.add_vertex(Vector3(q[j].x, 0.02, q[j].y))
		st.commit(mesh)
		mesh.surface_set_material(0, asphalt)
		mesh.surface_set_material(1, gravel)
		mesh.surface_set_material(2, paint)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		add_child(mi)
		i0 = i1


## Reflector posts every 20 m down both edges (white post, amber reflector
## facing the traffic): the dots that line the road into the dark.
func build_posts() -> void:
	var posts := []
	var lamps := []
	var k := Road2D.POST_EVERY_M
	while k < road.size() - 1:
		var along := Vector3(-right[k].y, 0.0, right[k].x) * -1.0
		for s: float in [-1.0, 1.0]:
			var base := at(k, s * (ROAD_HALF_M + POST_OUT_M), 0.0)
			posts.append(Transform3D(Basis(), base + Vector3(0, 0.5, 0)))
			lamps.append(Transform3D(Basis(), base + Vector3(0, 0.86, 0) - along * 0.06))
		k += Road2D.POST_EVERY_M
	multi(box(Vector3(0.1, 1.0, 0.1)), mat(Road2D.POST_WHITE, 0.7), posts)
	multi(box(Vector3(0.08, 0.16, 0.08)), glow_mat(Road2D.REFLECTOR, 1.6), lamps)


func multi(mesh: Mesh, material: Material, xforms: Array, colors := []) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = material
	add_child(inst)


## Chevron signs on the outside of a corner, facing the cars coming at them:
## the corner's severity color with a black arrow the way the road turns (a
## U-turn on a hairpin). Like the overview's (road.gd), 3-8 per corner.
func build_chevrons(c: Dictionary, col: Color) -> void:
	var s0 := float(c["s_start"])
	var s1 := float(c["s_end"])
	var count := clampi(int(round((s1 - s0) / Road2D.CHEVRON_EVERY_M)), Road2D.CHEVRONS_MIN, Road2D.CHEVRONS_MAX)
	var inward := 1.0 if c["direction"] == "R" else -1.0
	var hairpin := float(c["radius"]) <= Road2D.HAIRPIN_M
	var face := StandardMaterial3D.new()
	face.albedo_texture = chevron_texture(col, inward, hairpin)
	face.emission_enabled = true                      # retroreflective: faint even unlit
	face.emission_texture = face.albedo_texture
	face.emission_energy_multiplier = 0.3
	face.roughness = 0.5
	var quad := QuadMesh.new()
	quad.size = Vector2(SIGN_W_M, SIGN_H_M)
	var post := box(Vector3(0.07, SIGN_UP_M + SIGN_H_M * 0.5, 0.07))
	var post_mat := mat(Color(0.25, 0.25, 0.27), 0.6)
	for k in count:
		var i := clampi(int(round(s0 + (s1 - s0) * (k + 0.5) / count)), 0, road.size() - 1)
		var base := at(i, -inward * (ROAD_HALF_M + SIGN_OUT_M), 0.0)
		var back := Vector3(-right[i].y, 0.0, right[i].x)          # back down the road, at the cars
		var facing := (back + Vector3(right[i].x, 0.0, right[i].y) * inward * 0.35).normalized()
		var x_axis := Vector3.UP.cross(facing)
		var plate := mesh_node(quad, face, base + Vector3(0, SIGN_UP_M + SIGN_H_M / 2.0, 0))
		plate.basis = Basis(x_axis, Vector3.UP, facing)
		mesh_node(post, post_mat, base + Vector3(0, (SIGN_UP_M + SIGN_H_M * 0.5) / 2.0, 0) - facing * 0.04)


## The sign's face: severity color, a dark rim, the arrow (">" = turn right as
## the driver sees it), drawn into a small image (once per kind of sign: both
## panes and every corner of the same severity share it).
static var _faces := {}

func chevron_texture(col: Color, inward: float, hairpin: bool) -> ImageTexture:
	var key := "%s/%d/%s" % [col.to_html(), int(inward), hairpin]
	if not _faces.has(key):
		_faces[key] = draw_chevron(col, inward, hairpin)
	return _faces[key]


func draw_chevron(col: Color, inward: float, hairpin: bool) -> ImageTexture:
	var w := 64
	var h := 80
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Road2D.CHEVRON_INK)
	img.fill_rect(Rect2i(5, 5, w - 10, h - 10), col)
	var segs := []
	if hairpin:                                       # a U: up, over the top the way it turns, back down
		var r := 11.0
		var cx := 32.0
		var top := 32.0
		var near_x := cx - inward * r
		segs.append([Vector2(near_x, 64), Vector2(near_x, top)])
		var prev := Vector2(near_x, top)
		for k in range(1, 13):
			var ang := PI * k / 12.0
			var p := Vector2(cx - inward * r * cos(ang), top - r * sin(ang))
			segs.append([prev, p])
			prev = p
		segs.append([prev, Vector2(cx + inward * r, 48)])
		segs.append([Vector2(cx + inward * r, 54), Vector2(cx + inward * r - 7, 44)])   # arrowhead
		segs.append([Vector2(cx + inward * r, 54), Vector2(cx + inward * r + 7, 44)])
	else:
		var tip := Vector2(32 + inward * 13, 40)
		segs.append([Vector2(32 - inward * 11, 16), tip])
		segs.append([tip, Vector2(32 - inward * 11, 64)])
	var thick := 4.6 if hairpin else 6.5
	for y in range(5, h - 5):
		for x in range(5, w - 5):
			var p := Vector2(x + 0.5, y + 0.5)
			for sg: Array in segs:
				if Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1]).distance_to(p) < thick:
					img.set_pixel(x, y, Road2D.CHEVRON_INK)
					break
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ places

## Coast (PCH): the land stops at a cliff over the Pacific, surf at its foot,
## Armco where the road runs along it; coastal scrub inland.
func build_coast(land: Node2D) -> void:
	var edge := edge_m(land)
	if edge.size() > 1:
		var side: float = land.edge_side
		cliff(edge, side, SEA_DROP_M, 10.0, Land2D.CLIFF)
		var sea := PlaneMesh.new()
		sea.size = Vector2(9000, 9000)
		var water := mat(Land2D.OCEAN, 0.12)
		water.metallic_specular = 1.0
		mesh_node(sea, water, Vector3(edge[0].x - 4500.0 * -side, -SEA_DROP_M, (edge[0].y + edge[-1].y) / 2.0))
		var surf := SurfaceTool.new()                 # white water where the swell hits the rocks
		surf.begin(Mesh.PRIMITIVE_TRIANGLES)
		surf.set_normal(Vector3.UP)
		for k in edge.size() - 1:
			var a := Vector3(edge[k].x + side * 10.0, -SEA_DROP_M + 0.3, edge[k].y)
			var b := Vector3(edge[k + 1].x + side * 10.0, -SEA_DROP_M + 0.3, edge[k + 1].y)
			var o := Vector3(side * 6.0, 0, 0)
			for p: Vector3 in [a, b, b + o, a, b + o, a + o]:
				surf.add_vertex(p)
		var foam := StandardMaterial3D.new()
		foam.albedo_color = Color(Land2D.SURF, 0.4)
		foam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		foam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		foam.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_node(surf.commit(), foam)
		armco_by_edge(land, 55.0)
	scatter_plants(Land2D.SCRUB, 0.55, 1.0, 2.6, 2.0, 60.0, "bush", land)


## Canyon (Malibu): rock cut into the hill on the inside of every corner,
## chaparral and the odd oak.
func build_canyon(v: Node) -> void:
	for c in v.corners:
		var i0 := clampi(int(float(c["s_start"])) - 20, 0, road.size() - 1)
		var i1 := clampi(int(float(c["s_end"])) + 20, 0, road.size() - 1)
		var side := -1.0 if str(c["direction"]) == "L" else 1.0
		var room := clampf(float(c["radius"]) - ROAD_HALF_M - 2.5, 1.5, 14.0)
		rock_wall(i0, i1, side, room)
	scatter_plants(Land2D.CHAPARRAL, 0.75, 1.2, 3.2, 1.5, 55.0, "bush", v.land)
	scatter_plants(Land2D.OAK, 0.08, 3.0, 6.0, 6.0, 45.0, "oak", v.land)


## A rock cut beside the road: a face rising from the shoulder into the hill,
## then its top running back. Tapers in at both ends; never deeper than room.
func rock_wall(i0: int, i1: int, side: float, room: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := i1 - i0
	var foot := ROAD_HALF_M + SHOULDER_M
	var rows := []
	for k in n + 1:
		var ramp := minf(minf(k, n - k) / 12.0, 1.0)
		var depth := minf((6.0 + 8.0 * absf(sin(k * 0.13)) + rng.randf_range(0.0, 3.0)) * ramp, room)
		var h := (1.0 + depth * 0.6 + rng.randf_range(0.0, 0.8)) * ramp
		var i := i0 + k
		rows.append([at(i, side * foot, -0.05), at(i, side * (foot + depth * 0.22), h),
			at(i, side * (foot + depth), h + 0.8 * ramp)])
	for k in n:
		var i := i0 + k
		var toward := Vector3(-right[i].x * side, 0.6, -right[i].y * side)   # back at the road, and up
		for band in 2:
			var a: Vector3 = rows[k][band]
			var b: Vector3 = rows[k + 1][band]
			var c: Vector3 = rows[k + 1][band + 1]
			var d: Vector3 = rows[k][band + 1]
			tri(st, a, b, c, toward)
			tri(st, a, c, d, toward)
	mesh_node(st.commit(), mat(ROCK, 1.0, true))


## Mountain (Angeles Crest): pines, and on the east the mountain falls away to
## the valley, its city lights far below. Armco along the drop.
func build_mountain(land: Node2D) -> void:
	var edge := edge_m(land)
	if edge.size() > 1:
		var side: float = land.edge_side
		cliff(edge, side, VOID_DROP_M, 120.0, Land2D.ROCK.darkened(0.45))
		armco_by_edge(land, 40.0)
		var dots := []
		var cols := []
		for cluster in 16:
			var k := rng.randi_range(2, edge.size() - 3)
			var cz := edge[k].y
			var cx := edge[k].x + side * rng.randf_range(180.0, 650.0)
			for d in 80:
				var p := Vector2(cx + rng.randf_range(-90.0, 90.0), cz + rng.randf_range(-70.0, 70.0))
				if rng.randf() < 0.5:                 # a loose street grid
					p.x = cx + snappedf(p.x - cx, 10.0)
				else:
					p.y = cz + snappedf(p.y - cz, 10.0)
				dots.append(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.8, 1.6)),
					Vector3(p.x, -VOID_DROP_M + 2.0, p.y)))
				cols.append(Land2D.CITY[rng.randi() % Land2D.CITY.size()] * 1.6)
		var dot := SphereMesh.new()
		dot.radius = 1.2
		dot.height = 2.4
		dot.radial_segments = 6
		dot.rings = 3
		var lit := StandardMaterial3D.new()
		lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lit.vertex_color_use_as_albedo = true
		lit.disable_fog = true                        # miles off, through clear air: they still glow
		multi(dot, lit, dots, cols)
	scatter_plants(Land2D.PINE, 0.9, 2.0, 4.0, 3.0, 70.0, "pine", land)


## Armco wherever the road runs within `near_m` of the edge, on the edge side.
func armco_by_edge(land: Node2D, near_m: float) -> void:
	var side: float = land.edge_side
	var run := []
	for i in road.size():
		var gap: float = (road[i].x - land.edge_x(road[i].y * px) / px) * -side
		var near := gap < near_m
		if near:
			run.append(i)
		if (not near or i == road.size() - 1) and run.size() > 5:
			var s := 1.0 if right[int(run[0])].x * side > 0.0 else -1.0
			armco(int(run[0]), int(run[-1]), s)
		if not near:
			run = []


func armco(i0: int, i1: int, s: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var off := s * (ROAD_HALF_M + POST_OUT_M)
	for i in range(i0, i1):
		var toward := Vector3(-right[i].x * s, 0.0, -right[i].y * s)
		var a := at(i, off, 0.48)
		var b := at(i + 1, off, 0.48)
		var c := at(i + 1, off, 0.8)
		var d := at(i, off, 0.8)
		tri(st, a, b, c, toward)
		tri(st, a, c, d, toward)
	var rail := mat(Land2D.ARMCO, 0.35)
	rail.metallic = 0.6
	mesh_node(st.commit(), rail)
	var posts := []
	for i in range(i0, i1, 4):
		posts.append(Transform3D(Basis(), at(i, off + s * 0.1, 0.4)))
	multi(box(Vector3(0.12, 0.8, 0.12)), mat(Land2D.ARMCO.darkened(0.4), 0.6), posts)


## Plants along both sides of the road (the overview's rules, scenery.gd
## scatter()): every spacing_m, chance density per side, size r0..r1 m, clear of
## the road, out to reach_m, never in the sea / over the drop.
func scatter_plants(palette: Array, density: float, r0: float, r1: float, spacing_m: float, reach_m: float,
		kind: String, land: Node2D) -> void:
	var step := maxi(int(spacing_m), 1)
	var edge_side: float = land.edge_side if land != null else 0.0
	for i in range(0, road.size(), step):
		for side: float in [-1.0, 1.0]:
			if rng.randf() > density:
				continue
			var d := rng.randf_range(ROAD_HALF_M + 3.0, reach_m)
			var p := road[i] + right[i] * side * d + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			if land != null and land.road_distance(p * px) < (ROAD_HALF_M + 3.0) * px:
				continue
			if edge_side != 0.0 and land.edge.size() > 1 and (p.x - land.edge_x(p.y * px) / px) * edge_side > -4.0:
				continue
			var r := rng.randf_range(r0, r1)
			var col: Color = palette[rng.randi() % palette.size()]
			plant(kind, Vector3(p.x, 0.0, p.y), r, col, i / CHUNK)


func plant(kind: String, pos: Vector3, r: float, col: Color, chunk: int) -> void:
	var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
	match kind:
		"bush":
			add_scatter("bush", chunk, Transform3D(turn.scaled(Vector3(r * 0.75, r * 0.6, r * 0.75)),
				pos + Vector3(0, r * 0.25, 0)), col)
		"oak":
			add_scatter("trunk", chunk, Transform3D(turn.scaled(Vector3(0.35, 3.2, 0.35)), pos + Vector3(0, 1.6, 0)), TRUNK)
			add_scatter("bush", chunk, Transform3D(turn.scaled(Vector3(r * 0.8, r * 0.55, r * 0.8)),
				pos + Vector3(0, 2.6 + r * 0.35, 0)), col)
		"pine":
			var h := r * 4.0
			add_scatter("trunk", chunk, Transform3D(turn.scaled(Vector3(0.4, 2.0, 0.4)), pos + Vector3(0, 1.0, 0)), TRUNK)
			add_scatter("cone", chunk, Transform3D(turn.scaled(Vector3(r * 0.8, h, r * 0.8)),
				pos + Vector3(0, 1.4 + h / 2.0, 0)), col)


func add_scatter(kind: String, chunk: int, xf: Transform3D, col: Color) -> void:
	var key := "%s:%d" % [kind, chunk]
	if not scatter.has(key):
		scatter[key] = [[], []]
	scatter[key][0].append(xf)
	scatter[key][1].append(col)


## One MultiMesh per kind per stretch of road (so a headlight only redraws
## the plants near it).
func flush_scatter() -> void:
	var meshes := {}
	var blob := SphereMesh.new()                      # bushes, oak canopies: lumpy low-poly balls
	blob.radius = 1.0
	blob.height = 2.0
	blob.radial_segments = 7
	blob.rings = 4
	meshes["bush"] = blob
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.5
	trunk.bottom_radius = 0.6
	trunk.height = 1.0
	trunk.radial_segments = 6
	meshes["trunk"] = trunk
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 7
	meshes["cone"] = cone
	var leaf := StandardMaterial3D.new()
	leaf.vertex_color_use_as_albedo = true
	leaf.roughness = 1.0
	for key: String in scatter:
		multi(meshes[key.get_slice(":", 0)], leaf, scatter[key][0], scatter[key][1])
	scatter.clear()


# ------------------------------------------------------------------ the car + people

## The filmed car: Faba's DX (with his parts on it) or his opponent's car,
## on a body pivot (roll / pitch), with its headlight, brake lights,
## taillight glow and hazards.
func build_car(v: Node) -> void:
	var root := Node3D.new()
	add_child(root)
	var body := Node3D.new()
	body.position.y = 0.5                             # roughly the roll center
	root.add_child(body)
	var half: float
	var width: float
	var lamp_h: float
	var tails := []
	if who == "car":
		var dx: Node3D = DxModel.new()
		dx.position.y = -0.5
		body.add_child(dx)
		dx.build(v.faba_parts)
		half = DxModel.front_x()                     # the shell on (Spire's EG6, or the EJ)
		width = DxModel.WIDTH
		lamp_h = 0.64
		tails = DxModel.taillights()
	else:
		var cm: Node3D = CarModel.new()
		cm.position.y = -0.5
		body.add_child(cm)
		cm.build_car(str(v.ghost["car"]))
		half = float(cm.spec["length"]) / 2.0
		width = float(cm.spec["width"])
		lamp_h = cm.headlight_positions()[0].y
		var th := float(cm.spec["belt"]) - 0.12
		tails = [Vector3(-half - 0.025, th, -0.52), Vector3(-half - 0.025, th, 0.52)]
	var head := SpotLight3D.new()
	head.light_color = HALOGEN
	head.light_energy = 9.0
	head.spot_range = 75.0
	head.spot_angle = 30.0
	head.spot_angle_attenuation = 0.7
	head.position = Vector3(half + 0.15, lamp_h - 0.5, 0.0)
	head.basis = Basis.looking_at(Vector3(1.0, -0.05, 0.0), Vector3.UP)
	body.add_child(head)
	var brake := glow_mat(BRAKE_RED, 0.0)
	var brake_rest := 0.0                             # the taillights' glow when not braking
	var lenses: Variant = body.get_child(0).get("taillight_mat") if who == "car" else null
	if lenses != null:
		brake = lenses                                  # a real model: its own lenses light up, no lamp boxes
		brake_rest = brake.emission_energy_multiplier
		tails = []
	for tpos: Vector3 in tails:
		var lamp := MeshInstance3D.new()
		lamp.mesh = box(Vector3(0.03, 0.15, 0.42))
		lamp.material_override = brake
		lamp.position = tpos - Vector3(0, 0.5, 0)
		body.add_child(lamp)
	var tail := OmniLight3D.new()
	tail.light_color = BRAKE_RED
	tail.omni_range = 3.5
	tail.position = Vector3(-half - 0.6, 0.2, 0.0)
	body.add_child(tail)
	var hz := OmniLight3D.new()
	hz.light_color = HAZARD
	hz.omni_range = 7.0
	hz.position = Vector3(0, 0.8, 0)
	root.add_child(hz)
	var blink := glow_mat(HAZARD, 4.0)
	var corners := []
	for x: float in [half - 0.1, -half + 0.1]:
		for z: float in [-width / 2.0 + 0.1, width / 2.0 - 0.1]:
			var b := MeshInstance3D.new()
			b.mesh = box(Vector3(0.1, 0.07, 0.14))
			b.material_override = blink
			b.position = Vector3(x, lamp_h - 0.38, z)
			body.add_child(b)
			corners.append(b)
	# Its headlight beam in the night air: a faint cone (the camera looks down
	# it from behind, so it hangs in the air ahead of the car)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.15
	cone.bottom_radius = 4.2
	cone.height = 17.0
	cone.radial_segments = 16
	cone.cap_top = false
	cone.cap_bottom = false
	var haze := ShaderMaterial.new()
	haze.shader = beam_shader()
	haze.set_shader_parameter("tint", HALOGEN)
	haze.set_shader_parameter("strength", BEAM_HAZE)
	var beam := MeshInstance3D.new()
	beam.mesh = cone
	beam.material_override = haze
	beam.rotation.z = deg_to_rad(87.0)                # its narrow top at the lamp, opening forward, a touch down
	beam.position = Vector3(half + 0.15, lamp_h - 0.5, 0.0) + Vector3(cos(deg_to_rad(-3.0)), sin(deg_to_rad(-3.0)), 0) * 8.5
	body.add_child(beam)
	# Dust off the shoulder (emits in the world: it hangs where it was kicked up)
	gravel = CPUParticles3D.new()
	var puff := QuadMesh.new()
	puff.size = Vector2(1.3, 1.3)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_texture = soft_dot()
	dirt.vertex_color_use_as_albedo = true
	dirt.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dirt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = dirt
	gravel.mesh = puff
	gravel.amount = 40
	gravel.lifetime = 1.8
	gravel.emitting = false
	gravel.position = Vector3(-half + 0.3, 0.3, 0.0)
	gravel.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	gravel.emission_box_extents = Vector3(0.3, 0.1, width / 2.0)
	gravel.direction = Vector3(-1.0, 0.8, 0.0)
	gravel.spread = 40.0
	gravel.initial_velocity_min = 0.5
	gravel.initial_velocity_max = 2.5
	gravel.gravity = Vector3(0, -0.6, 0)
	var swell := Curve.new()
	swell.add_point(Vector2(0, 0.5))
	swell.add_point(Vector2(1, 2.2))
	gravel.scale_amount_curve = swell
	var fade := Gradient.new()
	fade.set_color(0, Color(0.55, 0.47, 0.37, 0.45))
	fade.set_color(1, Color(0.45, 0.4, 0.33, 0.0))
	gravel.color_ramp = fade
	root.add_child(gravel)
	# The exhaust tip (rear, right, under the bumper) and the flame it spits on
	# a pop: a cone of fire pointing back, and an orange flash on the road
	var tip_at := Vector3(-half - 0.02, 0.27 - 0.5, 0.42)
	var tip := MeshInstance3D.new()
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.045
	pipe.bottom_radius = 0.045
	pipe.height = 0.16
	tip.mesh = pipe
	tip.material_override = mat(Color(0.5, 0.5, 0.52), 0.35)
	tip.rotation.z = PI / 2.0
	tip.position = tip_at
	tip.visible = who != "car"                         # the DX models its own (by its header)
	body.add_child(tip)
	var fire := CylinderMesh.new()
	fire.top_radius = 0.0                              # the tip of the flame...
	fire.bottom_radius = 0.16                          # ...and its root, at the pipe
	fire.height = 1.0
	fire.radial_segments = 10
	fire.cap_top = false
	fire.cap_bottom = false
	var burn := ShaderMaterial.new()
	burn.shader = flame_shader()
	var flame := MeshInstance3D.new()
	flame.mesh = fire
	flame.material_override = burn
	flame.rotation.z = PI / 2.0                        # its point backward (-x)
	flame.visible = false
	body.add_child(flame)
	# Seen from behind the flame points at the lens, end-on: what reads is the
	# fireball, a soft glow that blooms
	var ball_mat := StandardMaterial3D.new()
	ball_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ball_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ball_mat.no_depth_test = false
	ball_mat.albedo_texture = soft_dot()
	ball_mat.albedo_color = Color(2.2, 1.1, 0.35)
	var ball_q := QuadMesh.new()
	ball_q.size = Vector2(0.9, 0.9)
	var ball := MeshInstance3D.new()
	ball.mesh = ball_q
	ball.material_override = ball_mat
	ball.visible = false
	body.add_child(ball)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.55, 0.15)
	flash.omni_range = 7.0
	flash.light_energy = 0.0
	flash.visible = false
	flash.position = tip_at + Vector3(-0.4, 0.1, 0)
	body.add_child(flash)
	car = {"root": root, "body": body, "head": head, "brake": brake, "brake_rest": brake_rest, "tail": tail, "hazard": hz,
		"flame": flame, "flame_mat": burn, "flash": flash, "tip_at": tip_at, "ball": ball,
		"blinkers": corners, "half": half}


## A person by the road (spotter / flagger) with a flashlight: dark clothes,
## a hi-vis vest with reflective bands (what reads at 3 a.m.), and the
## flashlight, which flares when he points it your way.
func make_person(src: Node2D, beam: PointLight2D, is_flagger: bool) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var torso := CapsuleMesh.new()
	torso.radius = 0.24
	torso.height = 1.5
	var t := MeshInstance3D.new()
	t.mesh = torso
	t.material_override = mat(JACKET, 0.9)
	t.position.y = 0.78
	root.add_child(t)
	var vest := CylinderMesh.new()
	vest.top_radius = 0.255
	vest.bottom_radius = 0.265
	vest.height = 0.5
	var v := MeshInstance3D.new()
	v.mesh = vest
	v.material_override = glow_mat(HI_VIS, 0.18)
	v.position.y = 1.2
	root.add_child(v)
	for y: float in [1.08, 1.32]:
		var band := CylinderMesh.new()
		band.top_radius = 0.27
		band.bottom_radius = 0.27
		band.height = 0.05
		var b := MeshInstance3D.new()
		b.mesh = band
		b.material_override = glow_mat(Color(0.85, 0.87, 0.9), 0.7)
		b.position.y = y
		root.add_child(b)
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.26
	var hd := MeshInstance3D.new()
	hd.mesh = head
	hd.material_override = mat(SKIN, 0.8)
	hd.position.y = 1.68
	root.add_child(hd)
	var flare_mat := StandardMaterial3D.new()
	flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flare_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flare_mat.albedo_texture = soft_dot()
	flare_mat.albedo_color = Color(1.0, 0.95, 0.82, 0.0)
	var flare := QuadMesh.new()
	flare.size = Vector2.ONE * FLARE_M
	var fl := mesh_node(flare, flare_mat)
	var lamp := spot(Color(1.0, 0.96, 0.85), 0.0, 32.0, 18.0)
	return {"root": root, "lamp": lamp, "lens": fl, "lens_mat": flare_mat, "src": src, "beam": beam,
		"flagger": is_flagger}


## A pop (main.gd shift_events): the flame for a split second.
func flame() -> void:
	_flame_until = Time.get_ticks_msec() / 1000.0 + randf_range(0.07, 0.14)
	_flame_len = randf_range(0.5, 1.1)


## Exhaust fire: white-hot at the pipe, through yellow and orange to a red,
## see-through tip, a touch of blue at the root, added on top of the night.
static var _fire: Shader

static func flame_shader() -> Shader:
	if _fire == null:
		_fire = Shader.new()
		_fire.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 1.0;
void fragment() {
	float root = UV.y;                                   // 1 at the pipe, 0 at the tip
	vec3 hot = mix(vec3(1.0, 0.25, 0.05), vec3(1.0, 0.75, 0.2), smoothstep(0.1, 0.6, root));
	hot = mix(hot, vec3(1.0, 0.97, 0.85), smoothstep(0.7, 0.95, root));
	hot = mix(hot, vec3(0.35, 0.5, 1.0), smoothstep(0.96, 1.0, root) * 0.6);
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = hot * strength * (0.4 + 1.6 * root) * edge * 2.2;
}
"""
	return _fire


## A headlight beam lit up by the air: brightest at the lamp, fading out
## along it, soft at the edges (where you look through less of it).
static var _beam: Shader

static func beam_shader() -> Shader:
	if _beam == null:
		_beam = Shader.new()
		_beam.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.72);
uniform float strength = 0.05;
void fragment() {
	float along = pow(1.0 - UV.y, 1.6);                  // UV.y: 0 at the lamp, 1 at the far end
	float edge = pow(abs(dot(NORMAL, VIEW)), 2.0);
	ALBEDO = tint * strength * along * edge;
}
"""
	return _beam


## Dust and bugs hanging in the night air, lit by the camera car's HIDs as it
## drives through them: emitted in a box ahead of the camera (sync_camcar
## moves it), they stay put in the world, so at speed they stream past.
func build_speed_fx() -> void:
	dust_mat = StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.9, 0.88, 0.8, 0.0)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dust_mat.albedo_texture = soft_dot()
	var speck := QuadMesh.new()
	speck.size = Vector2(0.055, 0.055)
	speck.material = dust_mat
	dust = CPUParticles3D.new()
	dust.mesh = speck
	dust.amount = 140
	dust.lifetime = 1.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = DUST_BOX
	dust.direction = Vector3.UP
	dust.spread = 180.0
	dust.initial_velocity_min = 0.0
	dust.initial_velocity_max = 0.3
	dust.gravity = Vector3.ZERO
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.6
	add_child(dust)
	bumps.seed = 31
	bumps.frequency = BUMP_EVERY
	bumps.fractal_type = FastNoiseLite.FRACTAL_NONE


## Curve warning signs before the slow corners, like the real road: a yellow
## diamond (a curve, a sharp turn, or a hairpin's U) and an advisory speed
## plate (the speed that holds ADVISORY_G round it, rounded down to 5 mph).
## On the right, ~70 m before the corner, facing the traffic.
func build_warnings(corners: Array) -> void:
	var post_mat := mat(Color(0.25, 0.25, 0.27), 0.6)
	var font := preload("res://fonts/BarlowCondensed-Bold.ttf")
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = WARN_YELLOW
	plate_mat.emission_enabled = true
	plate_mat.emission = WARN_YELLOW
	plate_mat.emission_energy_multiplier = 0.25
	for c: Dictionary in corners:
		var r := float(c["radius"])
		var mph := floori(sqrt(ADVISORY_G * 9.81 * r) * 2.237 / 5.0) * 5
		if mph >= 45:
			continue                                  # an easy bend: no sign
		var s0 := float(c["s_start"])
		var prev_end := 0.0
		for o: Dictionary in corners:
			if float(o["s_end"]) <= s0:
				prev_end = maxf(prev_end, float(o["s_end"]))
		var s := maxf(s0 - 70.0, prev_end + 8.0)
		if s0 - s < 15.0 or s < 5.0:
			continue                                  # no room for one
		var i := clampi(int(s), 0, road.size() - 1)
		var base := at(i, ROAD_HALF_M + 1.4, 0.0)
		var back := Vector3(-right[i].y, 0.0, right[i].x)
		var facing := (back - Vector3(right[i].x, 0.0, right[i].y) * 0.3).normalized()
		var turned := Basis(Vector3.UP.cross(facing), Vector3.UP, facing)
		mesh_node(box(Vector3(0.08, 2.4, 0.08)), post_mat, base + Vector3(0, 1.2, 0) - facing * 0.04)
		var kind := "hairpin" if r <= Road2D.HAIRPIN_M else ("turn" if r <= 40.0 else "curve")
		var face := StandardMaterial3D.new()
		face.albedo_texture = warning_texture(kind, 1.0 if c["direction"] == "R" else -1.0)
		face.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		face.emission_enabled = true
		face.emission_texture = face.albedo_texture
		face.emission_energy_multiplier = 0.3
		var diamond := QuadMesh.new()
		diamond.size = Vector2(0.95, 0.95)
		mesh_node(diamond, face, base + Vector3(0, 1.98, 0)).basis = turned
		var plate := QuadMesh.new()
		plate.size = Vector2(0.52, 0.5)
		mesh_node(plate, plate_mat, base + Vector3(0, 1.2, 0)).basis = turned
		var label := Label3D.new()
		label.text = "%d\nMPH" % mph
		label.font = font
		label.font_size = 64
		label.pixel_size = 0.0028
		label.line_spacing = -14.0
		label.modulate = Road2D.CHEVRON_INK
		label.outline_size = 0
		label.basis = turned
		label.position = base + Vector3(0, 1.2, 0) + facing * 0.01
		add_child(label)


## The diamond's face: yellow with a dark rim, the arrow the way it goes.
static var _warnings := {}

func warning_texture(kind: String, turn: float) -> ImageTexture:
	var key := "%s/%d" % [kind, int(turn)]
	if _warnings.has(key):
		return _warnings[key]
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var segs := []
	var cx := 48.0
	match kind:
		"curve":                                      # up, bending over to the side
			var prev := Vector2(cx - turn * 6.0, 74)
			for k in range(1, 11):
				var f := k / 10.0
				var p := Vector2(cx - turn * 6.0 + turn * 18.0 * f * f, 74.0 - 44.0 * f)
				segs.append([prev, p])
				prev = p
			segs.append([prev, prev + Vector2(-turn * 11.0, 4.0)])
			segs.append([prev, prev + Vector2(turn * 1.0, 12.0)])
		"turn":                                       # up, then a hard 90 to the side
			segs.append([Vector2(cx - turn * 8.0, 74), Vector2(cx - turn * 8.0, 44)])
			segs.append([Vector2(cx - turn * 8.0, 44), Vector2(cx + turn * 16.0, 44)])
			segs.append([Vector2(cx + turn * 16.0, 44), Vector2(cx + turn * 7.0, 35)])
			segs.append([Vector2(cx + turn * 16.0, 44), Vector2(cx + turn * 7.0, 53)])
		_:                                            # the hairpin's U
			var r := 11.0
			segs.append([Vector2(cx - turn * r, 72), Vector2(cx - turn * r, 42)])
			var prev := Vector2(cx - turn * r, 42)
			for k in range(1, 13):
				var ang := PI * k / 12.0
				var p := Vector2(cx - turn * r * cos(ang), 42.0 - r * sin(ang))
				segs.append([prev, p])
				prev = p
			segs.append([prev, Vector2(cx + turn * r, 56)])
			segs.append([Vector2(cx + turn * r, 60), Vector2(cx + turn * r - 7, 50)])
			segs.append([Vector2(cx + turn * r, 60), Vector2(cx + turn * r + 7, 50)])
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := absf(p.x - 48.0) + absf(p.y - 48.0)
			if d > 46.0:
				continue
			var col := Road2D.CHEVRON_INK if d > 41.0 else WARN_YELLOW
			for sg: Array in segs:
				if Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1]).distance_to(p) < 4.2:
					col = Road2D.CHEVRON_INK
					break
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	_warnings[key] = ImageTexture.create_from_image(img)
	return _warnings[key]


## A soft round spot (flares, smoke puffs).
func soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.18, Color(1, 1, 1, 0.75))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


# ------------------------------------------------------------------ every frame

## Copy the viewer's state in and point the camera. snap: no smoothing
## (a jump, a still, the first frame).
func sync(v: Node, delta: float, snap := false) -> void:
	sync_car(v)
	sync_people(v)
	sync_camcar(v, delta, snap)
	if v.subject_out() and not crashed:
		crashed = true
		crash_fx()


func sync_car(v: Node) -> void:
	var node: Node2D = v.ghost_car if who == "ghost" else v.car
	var root: Node3D = car["root"]
	root.position = m3(node.position)
	root.rotation.y = -node.rotation
	var b: Vector2 = node._body                        # car_sprite's body shift (m) on its spring
	var tilt := Vector3(b.y * BODY_ROLL, 0.0, -b.x * BODY_PITCH)
	var age: float = v.subject_crash_age()
	if age >= 0.0:                                     # off (main.gd slides it): leaned over in the ditch
		tilt += CRASH_TILT * smoothstep(0.0, 0.8, age)
		fx.position = root.position                    # the smoke goes with it, leaving a trail
	# The road under it: the body rides the swells, more the faster it goes
	var sv: Vector2 = v.subject_sv()
	var ride := clampf(sv.y / 40.0, 0.0, 1.2)
	tilt.z += bumps.get_noise_1d(sv.x + 400.0) * BUMP_PITCH * ride
	car["body"].position.y = 0.5 + bumps.get_noise_1d(sv.x) * BUMP_M * ride
	car["body"].rotation = tilt
	# Wheels off the asphalt (running wide, or going off): dust
	var i := clampi(int(sv.x), 0, road.size() - 1)
	var off_mid := Vector2(root.position.x, root.position.z) - road[i]
	var wide := absf(off_mid.dot(right[i])) > ROAD_HALF_M - 0.75 and sv.y > 4.0
	gravel.emitting = wide or (age >= 0.0 and age < 1.6)
	# A pop's flame: a flickering cone out the back for a split second
	var now := Time.get_ticks_msec() / 1000.0
	var fl: MeshInstance3D = car["flame"]
	var lit := now < _flame_until and age < 0.0
	fl.visible = lit
	car["flash"].visible = lit
	car["ball"].visible = lit
	if lit:
		var k := clampf((_flame_until - now) / 0.12, 0.0, 1.0)      # dying out
		var length := _flame_len * (0.6 + 0.4 * k) * randf_range(0.85, 1.15)
		fl.scale = Vector3(1.0 + 0.3 * k, length, 1.0 + 0.3 * k)
		fl.position = car["tip_at"] + Vector3(-length / 2.0 - 0.06, 0, 0)
		car["flame_mat"].set_shader_parameter("strength", (0.7 + 0.5 * k) * randf_range(0.8, 1.2))
		car["flash"].light_energy = 5.0 * k
		car["ball"].position = car["tip_at"] + Vector3(-length * 0.45, 0.02, 0)
		car["ball"].scale = Vector3.ONE * (0.6 + 0.9 * k) * randf_range(0.85, 1.15)
	var braking: bool = node.braking
	if who == "ghost" and v.ghost["samples"].has("brake"):
		braking = v.ghost_at("brake", v.t) > 0.0 and not v.subject_out()
	car["brake"].emission_energy_multiplier = 7.0 if braking else float(car["brake_rest"])
	car["tail"].light_energy = 0.7 if braking else 0.12
	var hz_key := who + "_hazard"
	var hz_e: float = v.lights[hz_key].energy if v.lights.has(hz_key) else 0.0
	car["hazard"].visible = hz_e > 0.01
	car["hazard"].light_energy = hz_e * 2.0
	for bl: MeshInstance3D in car["blinkers"]:
		bl.visible = hz_e > 0.01


func sync_people(v: Node) -> void:
	for p: Dictionary in people:
		var src: Node2D = p["src"]
		var root: Node3D = p["root"]
		root.visible = src.visible
		root.position = m3(src.position)
		root.rotation.y = -src.rotation
		var beam: PointLight2D = p["beam"]
		var e: float = beam.energy if src.visible else 0.0
		var dir := Vector3(cos(beam.rotation), 0.0, sin(beam.rotation))
		var hand := root.position + Vector3(0, 1.3, 0) + dir * 0.4
		if p["flagger"] and v.countdown > 0.0:
			dir = (dir + Vector3(0, 1.4, 0)).normalized()   # the count: light held up high
		else:
			dir = (dir + Vector3(0, -0.12, 0)).normalized()
		var lamp: SpotLight3D = p["lamp"]
		lamp.visible = e > 0.01
		lamp.light_energy = e * 3.0
		lamp.position = hand
		lamp.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK)
		# The flare: bright when the light points at the camera, a glint when not
		var to_cam := (cam.global_position - hand).normalized() if cam != null else -dir
		var facing := clampf(dir.dot(to_cam), 0.0, 1.0)
		p["lens"].position = hand + dir * 0.08
		p["lens"].visible = root.visible and e > 0.01
		p["lens_mat"].albedo_color.a = clampf(e / 2.2, 0.0, 1.0) * (0.25 + 0.75 * facing * facing)


## The camera car: its lamps, and the camera in it.
func sync_camcar(v: Node, delta: float, snap: bool) -> void:
	var yaw: float = v.camcar["yaw"]
	var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-fwd.z, 0.0, fwd.x)            # its right
	var base := m3(v.camcar_pos())
	for k in 2:
		var lamp: SpotLight3D = camcar_lamps[k]
		lamp.position = base + fwd * 2.0 + side * (-0.75 if k == 0 else 0.75) + Vector3(0, 0.68, 0)
		lamp.basis = Basis.looking_at((fwd + Vector3(0, -0.035, 0)).normalized(), Vector3.UP)

	var cam_pos := base + Vector3(0, CAM_H_M, 0) + fwd * 0.4
	var root: Node3D = car["root"]
	var sub_fwd := root.basis.x                         # the model's +x: where it's pointing
	var out: bool = v.subject_out()
	var target := root.position + Vector3(0, AIM_UP_M, 0) + (Vector3.ZERO if out else sub_fwd * AIM_LEAD_M)
	var want := (target - cam_pos).normalized()
	var dist := cam_pos.distance_to(root.position)
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var frame_w := WRECK_FRAME_W_M if out else FRAME_W_M
	var want_fov := clampf(rad_to_deg(2.0 * atan(frame_w / (2.0 * maxf(dist, 1.0) * aspect))), FOV_MIN, FOV_MAX)

	# The camera car's own ride: body roll in its corners, dive and squat
	var cv: float = v.camcar["v"]
	var ride: Vector2 = v.camcar_ride()
	var running: bool = v.playing and v.countdown <= 0.0
	if snap or last_v < 0.0 or delta <= 0.0:
		aim = want
		fov = want_fov
		accel = 0.0
	else:
		aim = aim.slerp(want, 1.0 - exp(-delta * PAN_RATE)).normalized()
		fov = lerpf(fov, want_fov, 1.0 - exp(-delta * ZOOM_RATE))
		if running:
			accel = lerpf(accel, (cv - last_v) / delta, 1.0 - exp(-delta * 4.0))
	last_v = cv
	var want_roll := ride.y * minf(ride.x, 1.2) * ROLL_PER_G
	roll = want_roll if snap else lerpf(roll, want_roll, 1.0 - exp(-delta * 5.0))
	pitch = clampf(accel, -9.0, 5.0) * PITCH_PER_MS2

	var look := aim
	var cam_right := look.cross(Vector3.UP).normalized()
	look = look.rotated(cam_right, pitch)
	# Buzz: the road through its suspension, with speed^2 and cornering g
	if running and cv > 0.5:
		var amp := BUZZ_RAD * pow(cv / 40.0, 2.0) + BUZZ_TURN_RAD * minf(ride.x, 1.3)
		var tt := Time.get_ticks_msec() / 1000.0 * 9.0
		look = look.rotated(Vector3.UP, buzz.get_noise_1d(tt) * amp)
		look = look.rotated(cam_right, buzz.get_noise_1d(tt + 300.0) * amp)
	var shake: float = v.shake
	if shake > 0.0:
		look = look.rotated(Vector3.UP, randf_range(-1, 1) * SHAKE_RAD * shake * shake)
		look = look.rotated(cam_right, randf_range(-1, 1) * SHAKE_RAD * shake * shake)
	var up := Vector3.UP.rotated(look, -roll)
	cam.fov = fov
	cam.global_transform = Transform3D(Basis.looking_at(look, up), cam_pos)

	# Speed: the picture streaks out from where it's heading (main.gd puts
	# blur + flow on the pane's shader), and dust and bugs stream through its lights
	var fast := clampf((cv - BLUR_FROM_MS) / (BLUR_FULL_MS - BLUR_FROM_MS), 0.0, 1.0)
	blur = fast * fast if running else 0.0
	var heading := cam_pos + fwd * 80.0
	if not cam.is_position_behind(heading):
		flow = cam.unproject_position(heading) / vp
	dust.position = cam_pos + fwd * DUST_AHEAD_M + Vector3(0, -0.7, 0)
	dust.basis = Basis.looking_at(fwd, Vector3.UP)
	dust_mat.albedo_color.a = DUST_ALPHA * clampf(cv / 30.0, 0.0, 1.0)
	# The cops: lights on behind them once it's over (red, blue, alternating)
	var lit: bool = v.busted and v.t >= v.end_time
	for k in 2:
		var l: OmniLight3D = cops[k]
		l.visible = lit
		if lit:
			var on := int(Time.get_ticks_msec() / 130) % 2 == k
			l.light_energy = 5.0 if on else 0.4
			l.position = cam_pos - fwd * 5.0 + side * (-0.7 if k == 0 else 0.7) + Vector3(0, -0.3, 0)


## How much of the filmed car is in the shot (selftest): 0 = none, 1 = its
## middle, 2 = all of it (nose and tail, both sides).
func subject_in_frame() -> int:
	var root: Node3D = car["root"]
	if not cam.is_position_in_frustum(root.position + Vector3(0, 0.7, 0)):
		return 0
	var half: float = car["half"]
	for x: float in [half, -half]:
		for z: float in [-0.85, 0.85]:
			if not cam.is_position_in_frustum(root.position + root.basis * Vector3(x, 0.7, z)):
				return 1
	return 2


func reset() -> void:
	crashed = false
	last_v = -1.0
	for c in fx.get_children():
		c.queue_free()


## The crash: a shower of sparks off the rocks, then smoke, on the fx node
## (it rides with the wreck: what it throws off stays behind as a trail).
func crash_fx() -> void:
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var spark_q := QuadMesh.new()
	spark_q.size = Vector2(0.07, 0.07)
	spark_q.material = spark_mat
	var sparks := CPUParticles3D.new()
	sparks.mesh = spark_q
	sparks.position = Vector3(0, 0.5, 0)
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.amount = 90
	sparks.lifetime = 0.9
	sparks.spread = 75.0
	sparks.direction = Vector3(0, 0.6, 0)
	sparks.initial_velocity_min = 3.0
	sparks.initial_velocity_max = 11.0
	sparks.gravity = Vector3(0, -9.8, 0)
	var hot := Gradient.new()
	hot.set_color(0, Color(3.0, 2.4, 1.2))
	hot.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	sparks.color_ramp = hot
	fx.add_child(sparks)
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_texture = soft_dot()
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var smoke_q := QuadMesh.new()
	smoke_q.size = Vector2(1.6, 1.6)
	smoke_q.material = smoke_mat
	var smoke := CPUParticles3D.new()
	smoke.mesh = smoke_q
	smoke.position = Vector3(0, 0.6, 0)
	smoke.amount = 40
	smoke.lifetime = 3.5
	smoke.direction = Vector3.UP
	smoke.spread = 35.0
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 1.4
	smoke.gravity = Vector3.ZERO
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 2.4))
	smoke.scale_amount_curve = grow
	var grey := Gradient.new()
	grey.set_color(0, Color(0.5, 0.5, 0.52, 0.5))
	grey.set_color(1, Color(0.3, 0.3, 0.32, 0.0))
	smoke.color_ramp = grey
	fx.add_child(smoke)
	var flash := OmniLight3D.new()                    # the impact lights the trees up for a moment
	flash.light_color = Color(1.0, 0.6, 0.25)
	flash.omni_range = 14.0
	flash.light_energy = 6.0
	flash.position = Vector3(0, 1.0, 0)
	fx.add_child(flash)
	create_tween().tween_property(flash, "light_energy", 0.0, 0.6)
	sparks.emitting = true
	smoke.emitting = true
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(smoke):
			smoke.emitting = false)
