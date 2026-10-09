extends Node
## The replay's 3D "camera car" view: a small 3D world (the road from the replay's own centerline, shoulders,
## reflector posts, dusk sky and fog) with the subject car in it, filmed from a SEPARATE following car
## (widgets/camera_car.gd) at windshield height.
##
## EVERYTHING HERE IS PRESENTATION. The viewer (main.gd) hands over the recorded values for the current playback
## time; this node only draws them. It never reads input, never changes the recorded path, timing or telemetry,
## and every visual motion is a pure function of playback time (precomputed on a fixed grid), so pause, seek,
## restart and playback speed cannot change a frame. The player never steers.
##
## MODEL HIERARCHY (one subject car):
##   car_pivot    the AUTHORITATIVE replay transform: x / y / road height / yaw.
##    +- RoadPitch      road grade once; applies to body and wheels, not the visual dynamics
##        +- BodyRoll   visual body: roll, braking pitch, heave about a roll axis 0.30 m above the road
##    |    +- Body          the model's body mesh (+ the car's headlamp)
##    +- Suspension     the wheels, which stay planted on the road while the body moves above them
##         +- Wheel_FL / FR / RL / RR   spin from the recorded distance, front pair steered (kinematic, see vehicle_dynamics.gd)
##
## Frame: replay (x east, y north, heading CCW from east) -> Godot 3D (x, 0, -y); heading h = a yaw of +h about +Y.
## The prepared car models point their nose along +X (art/blender/prep_home.py).

const OverlayScript := preload("res://widgets/camcorder_overlay.gd")
const VehicleDynamics := preload("res://widgets/vehicle_dynamics.gd")
const CameraCar := preload("res://widgets/camera_car.gd")
const RoadElevation := preload("res://widgets/road_elevation.gd")
const EG6_MODEL := "res://assets/models/cars/eg6_game.glb"
## replay metadata's stable visual id -> the prepared model (the rival profile is not edited to change it)
const PREPARED_VISUALS := {"eg9_ferio_temp_proxy": "res://assets/models/cars/eg9_game.glb"}

const ROAD_HALF_M := 4.0               # same two-lane road as the 2D viewer (two 4 m lanes)
const LANE_OFFSET_M := 2.0             # the subject drives the middle of the right-hand lane
const SHOULDER_M := 4.0
const POST_EVERY_M := 20.0
const ROLL_AXIS_Y := 0.30              # the body rolls and pitches about a line this high above the road

const ASPHALT := Color(0.2, 0.205, 0.22)
const SHOULDER := Color(0.3, 0.27, 0.22)
const GROUND := Color(0.1, 0.12, 0.085)
const LINE_WHITE := Color(0.78, 0.78, 0.74)
const LINE_YELLOW := Color(0.78, 0.62, 0.12)
const FOG := Color(0.2, 0.19, 0.26)               # the horizon glow the distance fades into (SoCal dusk)

var layer: CanvasLayer
var container: SubViewportContainer
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var road_mesh: ArrayMesh
var car_pivot: Node3D
var road_pitch: Node3D
var body_roll: Node3D
var suspension: Node3D
var model_label := ""                  # which model is on the road ("EG6 GAME MODEL", "EG9 TEMPORARY VISUAL PROXY", ...)
var model_is_fallback := false
var wheels: Array[Node3D] = []
var wheel_radius: Array[float] = []
var wheel_is_front: Array[bool] = []
var wheelbase_m := 2.6                 # measured from the model's own wheel positions (a proxy's body is NOT an EJ6 spec)
var brake_materials: Array[StandardMaterial3D] = []
var brake_base_energy: Array[float] = []
var camera_light: SpotLight3D
var dynamics := VehicleDynamics.new()  # the subject's body dynamics (visual only), from the recorded run
var rig := CameraCar.new()             # the filming car
var elevation := RoadElevation.new()
var debug_exaggerate := 1.0             # QA stills only (main.gd --exaggerate=5): multiplies roll / pitch / steer so their DIRECTION is visible; 1 = real
var debug_view := ""                   # QA stills only (main.gd --view=): "side" | "rear_close" | "front34" put a camera beside the posed car; "" = the footage


## replay: the loaded replay dictionary. Builds the world and precomputes every visual series once.
func build(replay: Dictionary) -> void:
	elevation = RoadElevation.new()
	if not elevation.load_track(replay["track"], int(replay["version"])):
		push_error("Replay elevation profile is invalid")
		return
	layer = CanvasLayer.new()
	layer.name = "RearChaseLayer"
	layer.layer = 1
	add_child(layer)
	container = SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	build_environment()
	build_car(replay.get("vehicle_visual", {}), str(replay["car"].get("name", "")))
	var s: Dictionary = replay["samples"]
	dynamics.wheelbase_m = wheelbase_m
	dynamics.build(s["t"], s["s"], s["heading"], s["v"])
	rig.build(replay["track"]["centerline"], s["t"], s["s"], s["x"], s["y"], s["heading"], s["v"], elevation)
	if elevation.elevated:
		rig.fov_deg = 58.0 # portrait-safe coverage through the tight crest; v1 framing is unchanged
	build_road(rig.road_pts, int(rig.road_extension_m))
	camera = Camera3D.new()
	camera.near = 0.1
	camera.far = 600.0
	camera.fov = rig.fov_deg
	world.add_child(camera)
	camera_light = SpotLight3D.new()                 # the filming car's lamp, so the subject's tail and the road read
	camera_light.spot_range = 45.0
	camera_light.spot_angle = 38.0
	camera_light.light_energy = 2.4
	camera_light.light_color = Color(1.0, 0.95, 0.85)
	camera.add_child(camera_light)
	var overlay := Control.new()                     # the camcorder frame + grit over the footage (no battery here)
	overlay.name = "Camcorder"
	overlay.set_script(OverlayScript)
	overlay.set("show_battery", false)
	overlay.set("scan_strength", 0.06)               # lighter than HOME: the car and road must stay readable
	overlay.set("grain_strength", 0.045)
	overlay.set("vignette", 0.22)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)                         # (a sibling of the container: a Container would resize it)
	layer.visible = false


func set_active(on: bool) -> void:
	layer.visible = on
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## The screen rectangle (in the viewer's canvas pixels) the 3D view fills.
func set_area(area: Rect2) -> void:
	container.position = area.position
	container.size = area.size
	var overlay := layer.get_node_or_null("Camcorder") as Control
	if overlay != null:
		overlay.position = area.position
		overlay.size = area.size


# ------------------------------------------------------------------ the world

func build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()      # a dusk gradient: dark blue overhead, a warm-violet glow at the horizon
	sky_material.sky_top_color = Color(0.04, 0.06, 0.16)
	sky_material.sky_horizon_color = FOG
	sky_material.ground_horizon_color = FOG
	sky_material.ground_bottom_color = Color(0.08, 0.09, 0.07)
	sky_material.sky_curve = 0.18
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.45, 0.62)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = FOG
	env.fog_density = 0.009
	env.fog_sky_affect = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var moon := DirectionalLight3D.new()                 # high and dim: lights the road and the car's roof without long shadows
	moon.rotation_degrees = Vector3(-62, 40, 0)
	moon.light_color = Color(0.7, 0.75, 0.95)
	moon.light_energy = 0.8
	world.add_child(moon)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12000, 12000)
	ground.mesh = plane
	ground.position = Vector3(0, -0.06, 0)
	ground.material_override = flat_material(GROUND)
	world.add_child(ground)


func flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Road, shoulders, edge lines, dashed centre line, start/finish lines, reflector posts. `pts` is the replay's
## centerline extended straight behind the start line by `start_index` points (1 m apart), so the filming car can
## start a gap back; the start line sits at point `start_index`.
func build_road(pts: Array[Vector2], start_index: int) -> void:
	var n := pts.size()
	var right: Array[Vector2] = []                     # unit normal to the right of travel (replay frame)
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		right.append(Vector2(t.y, -t.x))
	add_ribbon(pts, right, -ROAD_HALF_M - SHOULDER_M, -ROAD_HALF_M, -0.01, SHOULDER, 0.08)
	add_ribbon(pts, right, ROAD_HALF_M, ROAD_HALF_M + SHOULDER_M, -0.01, SHOULDER, 0.08)
	road_mesh = add_ribbon(pts, right, -ROAD_HALF_M, ROAD_HALF_M, 0.0, ASPHALT, 0.07)
	add_ribbon(pts, right, -ROAD_HALF_M + 0.35, -ROAD_HALF_M + 0.5, 0.012, LINE_WHITE, 0.0)
	add_ribbon(pts, right, ROAD_HALF_M - 0.5, ROAD_HALF_M - 0.35, 0.012, LINE_WHITE, 0.0)
	add_ribbon(pts, right, -0.07, 0.07, 0.012, LINE_YELLOW, 0.0, 9, 3)     # dashed: 3 m on, 6 m off
	add_ribbon(pts, right, -ROAD_HALF_M, ROAD_HALF_M, 0.014, LINE_WHITE, 0.0, 1, 1, start_index, start_index + 1)     # start line (1 m)
	add_ribbon(pts, right, -ROAD_HALF_M, ROAD_HALF_M, 0.014, LINE_WHITE, 0.0, 1, 1, n - 2, n - 1)                    # finish line
	var posts: Array[Transform3D] = []
	for i in range(0, n, int(POST_EVERY_M)):
		for side in [-1.0, 1.0]:
			var p2: Vector2 = pts[i] + right[i] * (ROAD_HALF_M + 1.6) * side
			posts.append(Transform3D(Basis.IDENTITY, Vector3(p2.x, elevation.at(rig.road_s[i]).x + 0.45, -p2.y)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.9, 0.12)
	mm.mesh = box
	mm.instance_count = posts.size()
	for i in posts.size():
		mm.set_instance_transform(i, posts[i])
	var post_mesh := MultiMeshInstance3D.new()
	post_mesh.multimesh = mm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.85, 0.85, 0.8)
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	post_mesh.material_override = pm
	world.add_child(post_mesh)


## A strip along the road between two offsets (m, + = right), flat-shaded quads with a little per-quad tone
## variation (low-poly asphalt). every/on/first/last pick which quads exist (dashes, the short start line).
func add_ribbon(pts: Array[Vector2], right: Array[Vector2], off0: float, off1: float, y: float, color: Color,
		jitter: float, every := 1, on := 1, first := 0, last := -1) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var end_i := (pts.size() - 1) if last < 0 else mini(last, pts.size() - 1)
	for i in range(first, end_i):
		if (i - first) % every >= on:
			continue
		var tone := 1.0 + jitter * (fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) - 0.5) * 2.0
		st.set_color(Color(color.r * tone, color.g * tone, color.b * tone))
		var a0 := pts[i] + right[i] * off0
		var a1 := pts[i] + right[i] * off1
		var b0 := pts[i + 1] + right[i + 1] * off0
		var b1 := pts[i + 1] + right[i + 1] * off1
		for vertex in [[a0, i], [a1, i], [b1, i + 1], [a0, i], [b1, i + 1], [b0, i + 1]]:
			var j: int = vertex[1]
			var v: Vector2 = vertex[0]
			var vertical := elevation.at(rig.road_s[j])
			var h: float = rig.road_h[j]
			st.set_normal(Vector3(-cos(h) * vertical.y, 1.0, sin(h) * vertical.y).normalized())
			st.add_vertex(Vector3(v.x, vertical.x + y, -v.y))
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := flat_material(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	world.add_child(mi)
	return mesh


## Stable visual road query for the replay viewer and later roadside placement.
## s is horizontal centerline distance; edges are on the same unbanked surface.
func road_geometry(s: float) -> Dictionary:
	var road := rig.road_at(s)
	var p: Vector2 = road["pos"]
	var h: float = road["heading"]
	var q: float = road["grade"]
	var right := Vector3(sin(h), 0.0, cos(h))
	var center := Vector3(p.x, float(road["height"]), -p.y)
	return {"s": s, "center": center, "tangent": Vector3(cos(h), q, -sin(h)).normalized(),
		"normal": Vector3(-cos(h) * q, 1.0, sin(h) * q).normalized(),
		"left_edge": center - right * ROAD_HALF_M, "right_edge": center + right * ROAD_HALF_M}


# ------------------------------------------------------------------ the car

## The model comes from the replay's metadata only: a stable visual id -> a prepared model, or (no visual
## selected) the player's EG6 when the replay is the EG6; anything else is the generic low-poly stand-in.
func build_car(selection: Dictionary, car_name: String) -> void:
	var path := ""
	var visual_id := str(selection.get("visual_id", ""))
	if PREPARED_VISUALS.has(visual_id):
		path = PREPARED_VISUALS[visual_id]
		model_label = str(selection.get("asset_label", "TEMPORARY VISUAL PROXY"))
	elif selection.is_empty() and car_name.contains("EG6"):
		path = EG6_MODEL
		model_label = "EG6 GAME MODEL"
	var model: Node3D = null
	if path != "" and ResourceLoader.exists(path):
		model = (load(path) as PackedScene).instantiate()
	else:
		model_is_fallback = true
		model_label = "GENERIC MARKER" if path == "" else "MODEL MISSING / GENERIC MARKER"
		model = generic_car()

	car_pivot = Node3D.new()                         # the authoritative replay transform (set in sync, nothing else touches it)
	car_pivot.name = "ReplayCar"
	world.add_child(car_pivot)
	road_pitch = Node3D.new()
	road_pitch.name = "RoadPitch"
	car_pivot.add_child(road_pitch)
	body_roll = Node3D.new()                         # visual-only body motion lives here
	body_roll.name = "BodyRoll"
	body_roll.position = Vector3(0.0, ROLL_AXIS_Y, 0.0)
	road_pitch.add_child(body_roll)
	suspension = Node3D.new()                        # the wheels: planted on the road, steered and spun
	suspension.name = "Suspension"
	road_pitch.add_child(suspension)

	var body := model.get_node_or_null("Body") as Node3D
	if body != null:
		model.remove_child(body)
		body_roll.add_child(body)
		body.position = Vector3(0.0, -ROLL_AXIS_Y, 0.0)   # the body keeps its place; the axis just moved up
	for wheel_name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var wheel := model.get_node_or_null(wheel_name) as Node3D
		if wheel == null:
			continue
		model.remove_child(wheel)
		suspension.add_child(wheel)
		wheels.append(wheel)
		wheel_radius.append(maxf(wheel.position.y, 0.2))   # the hub sits one tire radius above the road
		wheel_is_front.append(wheel_name.begins_with("Wheel_F"))
	var front_x := 0.0
	var rear_x := 0.0
	var fronts := 0
	var rears := 0
	for i in wheels.size():                          # wheelbase = the model's own axle spacing
		if wheel_is_front[i]:
			front_x += wheels[i].position.x
			fronts += 1
		else:
			rear_x += wheels[i].position.x
			rears += 1
	if fronts > 0 and rears > 0:
		wheelbase_m = front_x / fronts - rear_x / rears
	model.queue_free()                               # (an empty root: its children now live in the hierarchy above)
	soften_and_find_lights(body_roll)
	var headlamp := SpotLight3D.new()                # the car's own beam down the road
	headlamp.position = Vector3(1.9, 0.7 - ROLL_AXIS_Y, 0.0)
	headlamp.rotation_degrees = Vector3(-3, -90, 0)
	headlamp.spot_range = 55.0
	headlamp.spot_angle = 24.0
	headlamp.light_energy = 4.0
	headlamp.light_color = Color(1.0, 0.95, 0.8)
	body_roll.add_child(headlamp)


func soften_and_find_lights(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for surface in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var material_name := source.resource_name
			if material_name == "Paint" or material_name == "Glass":
				var softer := source.duplicate() as StandardMaterial3D
				softer.roughness = 0.6 if material_name == "Paint" else 0.45
				softer.metallic_specular = 0.3 if material_name == "Paint" else 0.2
				mi.set_surface_override_material(surface, softer)
			elif material_name == "Taillight" or material_name == "BrakeLight":
				var lamp := source.duplicate() as StandardMaterial3D
				mi.set_surface_override_material(surface, lamp)
				brake_materials.append(lamp)
				brake_base_energy.append(lamp.emission_energy_multiplier)


## The stand-in when no model applies: named like a real model (Body, Wheel_xx) so it animates the same way.
func generic_car() -> Node3D:
	var car := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	car.add_child(body)
	var shell := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.07, 0.5, 1.7)
	shell.mesh = box
	shell.position = Vector3(0, 0.55, 0)
	shell.material_override = flat_material(Color(0.7, 0.1, 0.12))
	body.add_child(shell)
	var cabin := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(2.0, 0.45, 1.5)
	cabin.mesh = cb
	cabin.position = Vector3(-0.3, 1.02, 0)
	cabin.material_override = flat_material(Color(0.06, 0.07, 0.09))
	body.add_child(cabin)
	var names := {"Wheel_FL": Vector3(1.25, 0.3, -0.78), "Wheel_FR": Vector3(1.25, 0.3, 0.78),
		"Wheel_RL": Vector3(-1.25, 0.3, -0.78), "Wheel_RR": Vector3(-1.25, 0.3, 0.78)}
	for wheel_name: String in names:
		var wheel := Node3D.new()                    # the hub: spins about Z; the tire is a cylinder laid along Z inside it
		wheel.name = wheel_name
		wheel.position = names[wheel_name]
		var tire := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 0.2
		cyl.radial_segments = 10
		tire.mesh = cyl
		tire.rotation_degrees = Vector3(90, 0, 0)
		tire.material_override = flat_material(Color(0.04, 0.04, 0.04))
		wheel.add_child(tire)
		car.add_child(wheel)
	return car


# ------------------------------------------------------------------ per frame

## Pose the subject and the filming car for playback time t. Pure in t (and the recorded values for t): nothing
## here keeps state between calls, so seeking, pausing and restarting give the same picture every time.
func sync(t: float, x: float, y: float, heading: float, distance: float, brake: float, path_distance := -1.0) -> void:
	# The recorded horizontal path and the replay's authoritative road profile.
	var vertical := elevation.at(distance)
	car_pivot.position = Vector3(x + sin(heading) * LANE_OFFSET_M, vertical.x, -y + cos(heading) * LANE_OFFSET_M)
	car_pivot.rotation = Vector3(0.0, heading, 0.0)
	road_pitch.rotation.z = atan(vertical.y)
	# visual-only body motion (roll / pitch / heave) on its own node
	var body := dynamics.at(t)
	body_roll.position = Vector3(0.0, ROLL_AXIS_Y + float(body["heave"]), 0.0)
	body_roll.rotation = Vector3(float(body["roll"]), 0.0, float(body["pitch"])) * debug_exaggerate
	# wheels: rolling from the recorded distance; the front pair steered by the kinematic angle
	for i in wheels.size():
		wheels[i].rotation = Vector3(0.0, float(body["steer"]) * debug_exaggerate if wheel_is_front[i] else 0.0,
			-(path_distance if path_distance >= 0.0 else distance) / wheel_radius[i])
	# brake lights from the RECORDED brake input
	var lit := 1.0 if brake > 0.0 else 0.0
	for i in brake_materials.size():
		brake_materials[i].emission_energy_multiplier = lerpf(brake_base_energy[i], 5.0, lit)
	# the filming car
	var shot := rig.at(t)
	camera.transform = shot["transform"]
	camera.fov = shot["fov"]
	if debug_view != "":
		camera.transform = debug_camera()
		camera.fov = 45.0


## A camera by the posed car, for checking roll / dive / steering / lights in stills. Not part of the footage.
func debug_camera() -> Transform3D:
	var at := car_pivot.global_position
	var yaw := car_pivot.rotation.y
	var ahead := Vector3(cos(yaw), 0.0, -sin(yaw))
	var right := Vector3(sin(yaw), 0.0, cos(yaw))
	var pos := at + right * 5.5 + Vector3(0, 0.7, 0)
	match debug_view:
		"rear_close":
			pos = at - ahead * 5.0 + Vector3(0, 0.9, 0)
		"front34":
			pos = at + ahead * 4.6 + right * 3.2 + Vector3(0, 0.9, 0)
	return Transform3D(Basis.looking_at(at + Vector3(0, 0.6, 0) - pos, Vector3.UP), pos)


## For the viewer's self-test: where the subject lands in the picture and how the filming car sits.
func measure(t: float) -> Dictionary:
	var shot := rig.at(t)
	var centre := car_pivot.global_position + Vector3(0, 0.7, 0)
	var size := Vector2(viewport.size)
	var on_screen := false
	var px := Vector2.ZERO
	if not camera.is_position_behind(centre):
		px = camera.unproject_position(centre)
		on_screen = px.x >= 0.0 and px.y >= 0.0 and px.x <= size.x and px.y <= size.y
	# the WHOLE car in frame? project the 8 corners of its bounding box (4.1 x 1.4 x 1.7 m) and find the tightest margin
	var margin := 1.0                       # fraction of the view's width/height left between the car and the nearest edge
	var any_behind := false
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for cx in [-2.05, 2.05]:
		for cy in [0.0, 1.4]:
			for cz in [-0.85, 0.85]:
				var corner: Vector3 = car_pivot.to_global(Vector3(cx, cy, cz))
				if camera.is_position_behind(corner):
					any_behind = true
					continue
				var q := camera.unproject_position(corner)
				min_x = minf(min_x, q.x); max_x = maxf(max_x, q.x); min_y = minf(min_y, q.y); max_y = maxf(max_y, q.y)
	if any_behind or min_x == INF:
		margin = -1.0
	else:
		margin = minf(minf(min_x / size.x, (size.x - max_x) / size.x), minf(min_y / size.y, (size.y - max_y) / size.y))
	return {"on_screen": on_screen, "px": px, "frame_margin": margin, "distance": camera.global_position.distance_to(car_pivot.global_position),
		"height": camera.global_position.y, "camera": camera.global_position, "car": car_pivot.global_position,
		"fov": camera.fov, "view": size, "gap": shot["gap"], "camera_speed": shot["speed"]}
