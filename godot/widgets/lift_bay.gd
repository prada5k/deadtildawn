extends SubViewportContainer
## CAR screen hero: the DX up on a two-post lift in a dim bay of the warehouse.
## Still camera (no turntable); drag sideways to walk around it. Dusk comes in
## through the half-open roll-up door. Call show_parts(ids) so installed parts
## appear on the car (same model as the home overlook, widgets/dx_model.gd).

const DxModel := preload("res://widgets/dx_model.gd")
const CONCRETE := preload("res://textures/concrete.jpg")
const PEGBOARD := preload("res://textures/pegboard.png")

const LIFT_H := 1.05                 # m the car is raised (sills sit on the pads at LIFT_H + 0.26)
const POST_X := -0.45                # posts by the B-pillars (front-heavy FWD car)
const POST_Z := 1.32                 # half the distance between the posts
const LIFT_RED := Color(0.38, 0.09, 0.1)     # tool-chest red, gone dull
const WALL := Color(0.16, 0.16, 0.19)
const TUBE := Color(0.85, 0.92, 1.0)         # fluorescent tube
const DUSK := Color(1.0, 0.55, 0.3)          # through the door

const YAW_MIN := 0.45                # radians around the car; 0 = side on (the near post blocks it)
const YAW_MAX := 1.45                # ~ head on
const FRONT_YAW := 1.0               # 3/4 front, right side
const REAR_YAW := -1.0               # 3/4 rear, right side (body shop: allow_rear)
const REAR_MIN := -1.5               # ~ straight behind
const CAM_DIST := 4.9

const LOWER_S := 2.2                 # the lift coming down (body shop), seconds

var car: Node3D
var cam: Camera3D
var carriage: Node3D                 # what rides up and down with the car: carriages, arms, pads
var yaw := FRONT_YAW
var yaw_min := YAW_MIN               # how far round a drag can go (allow_rear opens the back)
var lift_h := LIFT_H                 # the car's height up on the lift (Spire's lift model sets its own)
var height := LIFT_H                 # where the car sits now (0 = on the floor)
var target := Vector3(0.3, LIFT_H + 0.5, 0.0)


func _ready() -> void:
	stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.3, 0.38)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.1, 0.13)
	env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	build_bay(vp)
	build_lift(vp)
	lift_h = float(carriage.get_meta("built_at", LIFT_H))
	height = lift_h
	target.y = lift_h + 0.5

	car = DxModel.new()
	car.lights_on = false
	car.position.y = lift_h
	pose_lift(lift_h)
	vp.add_child(car)
	show_parts([])

	cam = Camera3D.new()
	cam.fov = 50
	vp.add_child(cam)
	place_camera()


func show_parts(ids: Array) -> void:
	if car != null:
		car.build(ids)


func place_camera() -> void:
	var up := lerpf(1.0, -0.35, height / lift_h)      # up on the lift: looking up at it; on the floor: down on it
	var pos := target + Vector3(sin(yaw) * CAM_DIST, up, cos(yaw) * CAM_DIST)
	cam.look_at_from_position(pos, target)


## Let the drag go all the way round to the back (the body shop: Spire, to
## see the rear spoiler, tips, plates).
func allow_rear() -> void:
	yaw_min = REAR_MIN


## Swing the camera round to a yaw (the body shop's front / back button).
func swing_to(to: float) -> void:
	var tw := create_tween()
	tw.tween_method(set_yaw, yaw, to, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func set_yaw(y: float) -> void:
	yaw = y
	place_camera()


## Bring the car down onto the floor (Spire: the body shop, so the car's
## easier to see while you dress it up). The arms come down with it and the
## camera follows. No ride in the stills / tests.
func lower(instant := false) -> void:
	var stills := instant
	for a in OS.get_cmdline_user_args():
		stills = stills or a == "--gametest" or a.begins_with("--gameshots")
	if stills:
		set_height(0.0)
		return
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_method(set_height, height, 0.0, LOWER_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func set_height(h: float) -> void:
	height = h
	car.position.y = h
	carriage.position.y = h - lift_h         # built at lift_h
	pose_lift(h)
	target.y = h + 0.5
	place_camera()


## Drag sideways to walk around the car. Only sideways drags are taken, so a
## vertical swipe still scrolls the page.
func _gui_input(event: InputEvent) -> void:
	var rel := Vector2.ZERO
	if event is InputEventScreenDrag:
		rel = (event as InputEventScreenDrag).relative
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		rel = (event as InputEventMouseMotion).relative
	if rel != Vector2.ZERO and absf(rel.x) > absf(rel.y):
		yaw = clampf(yaw + rel.x * 0.006, yaw_min, YAW_MAX)
		place_camera()
		accept_event()


func solid(mesh: Mesh, pos: Vector3, color: Color, parent: Node, rough := 0.8, metal := 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	m.material_override = mat
	parent.add_child(m)
	return m


func box(size: Vector3, pos: Vector3, color: Color, parent: Node, rough := 0.8, metal := 0.0) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return solid(b, pos, color, parent, rough, metal)


func glow(size: Vector3, pos: Vector3, color: Color, energy: float, parent: Node) -> MeshInstance3D:
	var m := box(size, pos, color, parent)
	var mat: StandardMaterial3D = m.material_override
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return m


func build_bay(vp: Node) -> void:
	# Stained concrete floor
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(24, 24)
	var fl := solid(floor_mesh, Vector3.ZERO, Color(0.62, 0.6, 0.6), vp, 0.85)
	var fmat: StandardMaterial3D = fl.material_override
	fmat.albedo_texture = CONCRETE
	fmat.uv1_scale = Vector3(6, 6, 1)
	# Back wall (behind the car), pegboard panel with the shop light over it
	box(Vector3(24, 6, 0.2), Vector3(0, 3, -4.2), WALL, vp, 0.95)
	var peg := box(Vector3(3.6, 1.4, 0.03), Vector3(-0.6, 1.9, -4.08), Color(0.7, 0.6, 0.5), vp, 0.9)
	var pmat: StandardMaterial3D = peg.material_override
	pmat.albedo_texture = PEGBOARD
	pmat.uv1_scale = Vector3(7, 3, 1)
	# Rolling tool chest under the pegboard
	box(Vector3(1.3, 1.0, 0.55), Vector3(-0.9, 0.5, -3.75), LIFT_RED.lightened(0.15), vp, 0.4, 0.3)
	for i in 4:
		box(Vector3(1.2, 0.02, 0.01), Vector3(-0.9, 0.25 + i * 0.22, -3.47), Color(0.75, 0.75, 0.78), vp, 0.3, 0.8)
	# Tire stack in the corner, a drum, a drain pan under the engine
	var tire := CylinderMesh.new()
	tire.top_radius = 0.3
	tire.bottom_radius = 0.3
	tire.height = 0.19
	for i in 4:
		solid(tire, Vector3(3.6, 0.1 + i * 0.2, -3.4), Color(0.05, 0.05, 0.055), vp, 0.95)
	var drum := CylinderMesh.new()
	drum.top_radius = 0.29
	drum.bottom_radius = 0.29
	drum.height = 0.88
	solid(drum, Vector3(4.4, 0.44, -2.9), Color(0.12, 0.2, 0.32), vp, 0.6, 0.4)
	var pan := CylinderMesh.new()
	pan.top_radius = 0.38
	pan.bottom_radius = 0.34
	pan.height = 0.08
	solid(pan, Vector3(1.4, 0.04, 0.0), Color(0.1, 0.1, 0.1), vp, 0.4, 0.5)

	# Side wall on the left with the roll-up door half open: dusk spills in
	box(Vector3(0.2, 6, 24), Vector3(-6.0, 3, 0), WALL.darkened(0.1), vp, 0.95)
	glow(Vector3(0.05, 1.4, 3.6), Vector3(-5.88, 0.7, 0.4), DUSK, 0.8, vp)
	box(Vector3(0.12, 0.14, 3.8), Vector3(-5.85, 1.45, 0.4), Color(0.3, 0.3, 0.32), vp, 0.5, 0.6)
	var dusk := SpotLight3D.new()
	dusk.light_color = DUSK
	dusk.light_energy = 6.0
	dusk.spot_range = 14.0
	dusk.spot_angle = 50.0
	dusk.shadow_enabled = true
	vp.add_child(dusk)
	dusk.look_at_from_position(Vector3(-5.6, 0.9, 0.4), Vector3(0.5, 0.0, 0.3))

	# Fluorescent shop light over the lift, buzzing cold
	glow(Vector3(1.6, 0.05, 0.16), Vector3(0.2, 3.9, 0.3), TUBE, 4.0, vp)
	var tube := OmniLight3D.new()
	tube.light_color = TUBE
	tube.light_energy = 2.4
	tube.omni_range = 9.0
	tube.shadow_enabled = true
	tube.position = Vector3(0.2, 3.7, 0.3)
	vp.add_child(tube)
	# Work lamp on the floor, aimed up at the underside
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 3.0
	lamp.spot_range = 7.0
	lamp.spot_angle = 35.0
	vp.add_child(lamp)
	lamp.look_at_from_position(Vector3(2.6, 0.3, 2.4), Vector3(0.6, LIFT_H, 0))
	glow(Vector3(0.18, 0.14, 0.12), Vector3(2.6, 0.12, 2.4), Color(1.0, 0.85, 0.6), 2.0, vp)

	# Yellow safety lines around the lift
	for z: float in [-2.3, 2.3]:
		box(Vector3(6.0, 0.005, 0.08), Vector3(0.0, 0.003, z), Color(0.85, 0.7, 0.15), vp, 0.7)


## Spire's lift model (models/car_lift.glb, Oct 2026) when it's there. It's
## RIGGED: its arms ride on bones, moved by its own animations ("...|up": the
## arms swing in, then rise). So the car's height picks the moment of "up"
## where the pads meet the car's sills (pose_lift): up on the lift, and all the
## way down in the body shop. Model frame (Blender): posts along Y, arms along
## X; centered on LIFT_MODEL_CENTER.
const LIFT_MODEL := "res://models/car_lift.glb"
const LIFT_MODEL_CENTER := Vector2(1.52, 2.42)    # Blender x, y between the posts
const PAD_ABOVE_BONE := 0.05                      # the pads' top over the arm bone (measured at rest)
const SILL := 0.19                                # the car's sills over its tires' bottom (where the pads go)
const ARM_BONE := "Bone.001_01"

var lift_anim: AnimationPlayer
var lift_up := ""                    # the "up" animation's name
var rise := []                       # [time, arm bone height] through "up"


func build_lift_model(vp: Node) -> bool:
	if not ResourceLoader.exists(LIFT_MODEL):
		return false
	var lift: Node3D = (load(LIFT_MODEL) as PackedScene).instantiate()
	# Blender (x, y, z) arrives as Godot (x, z, -y): center it on the car (x = 0, z = 0)
	lift.position = Vector3(-LIFT_MODEL_CENTER.x, 0.0, LIFT_MODEL_CENTER.y)
	vp.add_child(lift)
	for n in lift.find_children("Icosphere*", "", true, false):   # a stray sphere in the file
		n.queue_free()
	carriage = Node3D.new()                           # (the box lift's; unused with the model)
	vp.add_child(carriage)
	var aps := lift.find_children("*", "AnimationPlayer", true, false)
	var skels := lift.find_children("*", "Skeleton3D", true, false)
	if aps.is_empty() or skels.is_empty():
		return true
	lift_anim = aps[0]
	var skel: Skeleton3D = skels[0]
	for a in lift_anim.get_animation_list():
		if String(a).ends_with("|up"):
			lift_up = a
	var bone := skel.find_bone(ARM_BONE)
	if lift_up == "" or bone < 0:
		return true
	# How high the arms are through "up" (sampled once)
	lift_anim.play(lift_up)
	lift_anim.pause()
	var length := lift_anim.get_animation(lift_up).length
	for k in 121:
		var time := length * k / 120.0
		lift_anim.seek(time, true)
		skel.force_update_all_bone_transforms()
		rise.append([time, (skel.global_transform * skel.get_bone_global_pose(bone)).origin.y])
	carriage.set_meta("built_at", float(rise[-1][1]) + PAD_ABOVE_BONE - SILL)   # the car's height up top
	return true


## Pose the lift model's arms under a car sitting at height h.
func pose_lift(h: float) -> void:
	if lift_anim == null or rise.is_empty():
		return
	var want := h + SILL - PAD_ABOVE_BONE
	var time: float = rise[-1][0]
	for k in range(1, rise.size()):
		var y0: float = rise[k - 1][1]
		var y1: float = rise[k][1]
		if y1 >= want and y1 > y0:                     # the first moment the arms rise past it
			time = lerpf(rise[k - 1][0], rise[k][0], clampf((want - y0) / (y1 - y0), 0.0, 1.0))
			break
	lift_anim.seek(time, true)


## Two-post lift: posts either side of the car, an overhead beam, carriages at
## lift height, and two swing arms per post under the pinch welds.
func build_lift(vp: Node) -> void:
	if build_lift_model(vp):
		return
	carriage = Node3D.new()
	vp.add_child(carriage)
	for side: float in [-1.0, 1.0]:
		var z := side * POST_Z
		box(Vector3(0.22, 3.8, 0.26), Vector3(POST_X, 1.9, z), LIFT_RED, vp, 0.55, 0.2)
		box(Vector3(0.7, 0.03, 0.6), Vector3(POST_X, 0.015, z), Color(0.25, 0.25, 0.27), vp, 0.6, 0.5)
		box(Vector3(0.38, 0.5, 0.36), Vector3(POST_X, LIFT_H + 0.1, z - side * 0.02),
			Color(0.3, 0.3, 0.32), carriage, 0.5, 0.6)                 # carriage
		for arm_x: float in [1.0, -1.25]:                                  # front, rear lift points
			var reach := Vector3(arm_x - POST_X, 0.0, -side * (POST_Z - 0.62))
			var arm := box(Vector3(reach.length(), 0.09, 0.14), Vector3.ZERO,
				Color(0.32, 0.32, 0.35), carriage, 0.5, 0.6)
			arm.position = Vector3(POST_X, LIFT_H + 0.07, z) + reach / 2.0
			arm.rotation.y = -atan2(reach.z, reach.x)
			var pad := CylinderMesh.new()
			pad.top_radius = 0.07
			pad.bottom_radius = 0.07
			pad.height = 0.14
			solid(pad, Vector3(arm_x, LIFT_H + 0.19, side * 0.62), Color(0.08, 0.08, 0.08), carriage, 0.9)
	box(Vector3(0.2, 0.2, POST_Z * 2.0 + 0.26), Vector3(POST_X, 3.85, 0), LIFT_RED, vp, 0.55, 0.2)
