extends Control
## THE STAGE (Spire, Oct 2026): one underground garage behind every hub screen,
## filmed by one camcorder that never cuts. Changing screens whips the camera
## to that screen's spot (whip_to(shot)): a fast swing with motion blur, then
## a jolt as it lands. Everything lives in the same lot:
##   home      the DX backed into its stall under the one tube that works
##   car       the DX up on the two-post lift (Spire's rigged model): drag orbits
##   bodyshop  the same lift, lowered to the floor, orbit all the way round
##   shop      the kei truck with the pull boxes in its bed (widgets/kei_set.gd)
##   phone     the camera tips down: the calendar is on your phone
##   team      the crew's corner, stickers on the wall
##   other     down the aisle (settings, codes, the road read...)
## The DX is ONE car: it moves between the stall and the lift mid-whip (you
## never see it go). Low poly, flat-shaded; the VHS shader over the footage.
## Shell (screens/shell.gd) owns it; screens find it in the group "stage".
##
## Frame: Godot meters, the floor at y = 0, the stalls' back wall at x = BACK_X.

signal box_picked(id: String)

const DxModel := preload("res://widgets/dx_model.gd")
const CarModel := preload("res://widgets/car_model.gd")
const KeiSet := preload("res://widgets/kei_set.gd")
const VHS := preload("res://widgets/vhs.gdshader")
const WHIP := preload("res://widgets/whip_blur.gdshader")

const CAR_AT := Vector3(7.0, 0.0, 3.75)     # the stall: backed in against the back wall, nose out (-x)
const LIFT_AT := Vector3(-4.6, 0.0, -2.2)   # the lift bay, across the aisle
const KEI_AT := Vector3(-4.4, 0.0, 6.2)     # the kei truck
const CREW_AT := Vector3(-7.85, 1.4, 2.4)   # the crew's sticker wall (left wall)
const TUBE := Color(0.82, 0.92, 1.0)        # cold fluorescent
const FOV := 68.0                            # horizontal (portrait screen)
const SWAY_M := 0.03                         # handheld: how far the hands wander (m)...
const SWAY_DEG := 0.7                        # ...and how much it tips
const DRIFT_M := 0.25                        # a slow side step back and forth...
const DRIFT_S := 16.0                        # ...over this long
const WHIP_S := 0.42                         # the whip pan
const JOLT_S := 0.3                          # ...and the jolt as it lands
const JOLT_DEG := 2.2
const ORBIT_R := 5.0                         # the lift shots: around the car
const LOWER_S := 2.2                         # the lift coming down / going up
const LIGHT_LEVELS := 5                      # the tube over the DX: 0 (off) .. 4
# Each shot: camera position, what it looks at, and how far below that it
# aims (the subject sits high: the menus cover the bottom of the screen)
const SHOTS := {
	"home": [Vector3(2.4, 1.45, 1.2), Vector3(6.2, 0.5, 3.6), 1.25],
	"shop": [KEI_AT + Vector3(3.6, 2.6, 3.4), KEI_AT + Vector3(0.5, 0.7, 0.0), 1.9],
	"phone": [Vector3(2.4, 1.35, 1.2), Vector3(0.8, 0.0, 0.4), 0.0],
	"team": [CREW_AT + Vector3(4.6, 0.1, 0.4), CREW_AT - Vector3(0, 0.2, 0), 0.6],
	"other": [Vector3(6.5, 1.6, -4.5), Vector3(-2.0, 0.7, 5.0), 1.0],
}
const PARKED := ["1995 Honda Accord LX", "1989 Toyota Corolla GT-S (AE86)", "1977 Nissan 280Z",
	"2009 Nissan 370Z", "Toyota Celica", "Mitsubishi Lancer Evolution III", "1998 Mitsubishi Eclipse GS-T",
	"2002 Volkswagen GTI 1.8T", "2006 Mazdaspeed 3", "2009 Honda Civic Si (FA5)"]

var car: Node3D
var other: Node3D                # the other cars parked in the garage (settings: hide them)
var kei: Node3D
var cam: Camera3D
var stall_tube: OmniLight3D       # the light over the DX (the brightness setting)
var stall_tube_mesh: MeshInstance3D
var flicker: OmniLight3D
var flicker_tube: MeshInstance3D
var whip_rect: ColorRect
var noise := FastNoiseLite.new()
var t := 0.0
var still := false
var shot := "home"
var parts_shown = null           # what the DX is built with (null: not built yet)
# The camera: where it is now (the handheld sway rides on top)
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var whip_t := -1.0               # >= 0 while whipping
var whip_from := []              # [pos, look]
var whip_to_pose := []
var jolt_t := -1.0
var car_where := "stall"
var warm := 0                    # >= 0: warming up (each spot seen once, so the whip never stalls)
var warm_card: ColorRect
# The lift: orbit and height
var yaw := 1.0
var yaw_min := 0.45
var yaw_max := 1.45
var lift_h := 1.4                # the car's height up on the lift (the model sets it)
var height := 1.4                # where the car sits now
var lift_tween: Tween
var lift_anim: AnimationPlayer
var lift_up := ""
var rise := []                   # [time, arm bone height] through "up"


func _ready() -> void:
	add_to_group("stage")
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
	# The whip's blur, then the tape (VHS) over the footage only
	whip_rect = ColorRect.new()
	whip_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	whip_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wm := ShaderMaterial.new()
	wm.shader = WHIP
	whip_rect.material = wm
	whip_rect.visible = false
	add_child(whip_rect)
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
	var pose := shot_pose(shot)
	cam_pos = pose[0]
	cam_look = pose[1]
	place_camera()
	if still:
		warm = -1
	else:
		warm_card = ColorRect.new()
		warm_card.color = Color(0.01, 0.01, 0.015)
		warm_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		warm_card.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(warm_card)


## The first time the camera sees a part of the garage, Godot compiles its
## shaders (a hitch). So on start, behind a black card, look at each spot for
## a couple of frames (the DX on the lift too), then show the real shot.
func warm_up() -> void:
	var spots := SHOTS.keys() + ["car"]
	var i := warm / 2
	if i < spots.size():
		place_car("lift" if spots[i] == "car" else "stall")
		var pose := shot_pose(spots[i])
		cam.look_at_from_position(pose[0], pose[1])
		warm += 1
		return
	warm = -1
	place_car("lift" if shot == "car" or shot == "bodyshop" else "stall")
	place_camera()
	warm_card.queue_free()


# ------------------------------------------------------------------ the camera

## Where a shot puts the camera: [position, the point it aims at].
func shot_pose(s: String) -> Array:
	if s == "car" or s == "bodyshop":
		var target := LIFT_AT + Vector3(0.3, height + 0.5, 0.0)
		var up := lerpf(1.6, 0.9, clampf(height / maxf(lift_h, 0.01), 0.0, 1.0))
		var pos := target + Vector3(sin(yaw) * ORBIT_R, up, cos(yaw) * ORBIT_R)
		return [pos, target - Vector3(0, 1.15, 0)]
	var sh: Array = SHOTS.get(s, SHOTS["other"])
	return [sh[0], sh[1] - Vector3(0, sh[2], 0)]


## Whip the camcorder to a shot. Instant in the stills / tests.
func whip_to(s: String) -> void:
	if s == shot and whip_t < 0.0:
		return
	var lift_shot := s == "car" or s == "bodyshop"
	if lift_shot and not (shot == "car" or shot == "bodyshop"):
		yaw = 1.0
	yaw_min = -1.5 if s == "bodyshop" else 0.45
	shot = s
	if still:
		place_car("lift" if lift_shot else "stall")
		set_height(0.0 if s == "bodyshop" else lift_h)
		var pose := shot_pose(s)
		cam_pos = pose[0]
		cam_look = pose[1]
		place_camera()
		return
	whip_from = [cam_pos, cam_look]
	whip_t = 0.0
	whip_rect.visible = true
	# The swing's direction on screen: which way the aim moves, left or right
	var to := shot_pose(s)
	var fwd := (cam_look - cam_pos).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var to_look: Vector3 = to[1]
	var swing := (to_look - cam_look).dot(right)
	(whip_rect.material as ShaderMaterial).set_shader_parameter("dir", Vector2(signf(swing) if absf(swing) > 0.1 else 1.0, 0.15))
	var snd := get_node_or_null("/root/Sound")       # the tape's whir (absent in tools)
	if snd != null:
		snd.play("tape", -12.0, 1.6)
	# The lift goes down for the body shop, back up for the car (after the whip lands)
	if lift_shot:
		var want := 0.0 if s == "bodyshop" else lift_h
		if absf(height - want) > 0.01:
			if lift_tween != null:
				lift_tween.kill()
			lift_tween = create_tween()
			lift_tween.tween_interval(WHIP_S + 0.15)
			lift_tween.tween_method(set_height, height, want, LOWER_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func place_camera() -> void:
	var drift := sin(t * TAU / DRIFT_S) * DRIFT_M
	var side := (cam_look - cam_pos).cross(Vector3.UP).normalized()
	var hand := Vector3(noise.get_noise_2d(t, 0.0), noise.get_noise_2d(t, 40.0), noise.get_noise_2d(t, 80.0)) * SWAY_M
	var pos := cam_pos + side * drift + hand
	cam.look_at_from_position(pos, cam_look)
	cam.rotate_object_local(Vector3.FORWARD, deg_to_rad(noise.get_noise_2d(t, 120.0) * SWAY_DEG))
	cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(noise.get_noise_2d(t, 160.0) * SWAY_DEG * 0.6))
	if jolt_t >= 0.0:                                 # landing: a hard little shake, dying out
		var k := 1.0 - jolt_t / JOLT_S
		cam.rotate_object_local(Vector3.FORWARD, deg_to_rad(sin(jolt_t * 70.0) * JOLT_DEG * k * k))
		cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(cos(jolt_t * 55.0) * JOLT_DEG * 0.6 * k * k))


func _process(delta: float) -> void:
	if still:
		return
	t += delta
	if warm >= 0:                                      # first frames: glance at every spot behind a black card
		warm_up()
		return
	if whip_t >= 0.0:
		whip_t += minf(delta, 1.0 / 30.0)               # a slow frame never skips the swing
		var s := clampf(whip_t / WHIP_S, 0.0, 1.0)
		var e := ease_whip(s)
		var to := shot_pose(shot)
		cam_pos = (whip_from[0] as Vector3).lerp(to[0], e)
		cam_look = (whip_from[1] as Vector3).lerp(to[1], e)
		(whip_rect.material as ShaderMaterial).set_shader_parameter("amount", sin(PI * s) * 1.0)
		if s >= 0.5:                                    # mid-swing, all blur: the DX goes where it's needed
			place_car("lift" if shot == "car" or shot == "bodyshop" else "stall")
		if s >= 1.0:
			whip_t = -1.0
			jolt_t = 0.0
			whip_rect.visible = false
	elif shot == "car" or shot == "bodyshop":           # follow the orbit and the lift
		var to := shot_pose(shot)
		cam_pos = cam_pos.lerp(to[0], 1.0 - exp(-delta * 10.0))
		cam_look = cam_look.lerp(to[1], 1.0 - exp(-delta * 10.0))
	if jolt_t >= 0.0:
		jolt_t += delta
		if jolt_t > JOLT_S:
			jolt_t = -1.0
	place_camera()
	# The bad tube: mostly on, then a stutter
	var n := noise.get_noise_2d(t * 6.0, 300.0)
	var on := n > -0.25 or randf() < 0.3
	flicker.light_energy = 1.3 if on else 0.05
	(flicker_tube.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if on else 0.2


## Slow in, fast through, a touch of overshoot at the end: a hand whipping the camera.
static func ease_whip(s: float) -> float:
	var e := 0.5 - 0.5 * cos(PI * pow(s, 0.8))
	return e + sin(PI * s) * 0.06 * s


# ------------------------------------------------------------------ the lift

## Drag on the car / body shop shots: walk round the car.
func orbit(dx: float) -> void:
	yaw = clampf(yaw + dx * 0.006, yaw_min, yaw_max)


## Straight to a yaw (the stills).
func set_yaw(y: float) -> void:
	yaw = clampf(y, yaw_min, yaw_max)
	var pose := shot_pose(shot)
	cam_pos = pose[0]
	cam_look = pose[1]
	place_camera()


## Swing round to a yaw (the body shop's front / back button).
func swing_to(to: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "yaw", clampf(to, yaw_min, yaw_max), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func place_car(where: String) -> void:
	if where == car_where or car == null:
		return
	car_where = where
	if where == "lift":
		car.position = LIFT_AT + Vector3(0, height, 0)
		car.rotation.y = 0.0
	else:
		car.position = CAR_AT
		car.rotation.y = PI


func set_height(h: float) -> void:
	height = h
	if car_where == "lift":
		car.position.y = h
	pose_lift(h)


# Spire's lift model (models/car_lift.glb): RIGGED, its arms on bones moved by
# its own "...|up" animation. The car's height picks the moment of "up" where
# the pads meet the car's sills (pose_lift). Model frame (Blender): posts along
# Y, arms along X; centered on LIFT_MODEL_CENTER.
const LIFT_MODEL := "res://models/car_lift.glb"
const LIFT_MODEL_CENTER := Vector2(1.52, 2.42)
const PAD_ABOVE_BONE := 0.05
const SILL := 0.19
const ARM_BONE := "Bone.001_01"


func build_lift(vp: Node) -> void:
	if not ResourceLoader.exists(LIFT_MODEL):
		return
	var lift: Node3D = (load(LIFT_MODEL) as PackedScene).instantiate()
	lift.position = LIFT_AT + Vector3(-LIFT_MODEL_CENTER.x, 0.0, LIFT_MODEL_CENTER.y)
	vp.add_child(lift)
	for n in lift.find_children("Icosphere*", "", true, false):
		n.queue_free()
	var aps := lift.find_children("*", "AnimationPlayer", true, false)
	var skels := lift.find_children("*", "Skeleton3D", true, false)
	if aps.is_empty() or skels.is_empty():
		return
	lift_anim = aps[0]
	var skel: Skeleton3D = skels[0]
	for a in lift_anim.get_animation_list():
		if String(a).ends_with("|up"):
			lift_up = a
	var bone := skel.find_bone(ARM_BONE)
	if lift_up == "" or bone < 0:
		return
	lift_anim.play(lift_up)
	lift_anim.pause()
	var length := lift_anim.get_animation(lift_up).length
	for k in 121:
		var time := length * k / 120.0
		lift_anim.seek(time, true)
		skel.force_update_all_bone_transforms()
		rise.append([time, (skel.global_transform * skel.get_bone_global_pose(bone)).origin.y])
	lift_h = float(rise[-1][1]) + PAD_ABOVE_BONE - SILL
	height = lift_h
	pose_lift(height)


func pose_lift(h: float) -> void:
	if lift_anim == null or rise.is_empty():
		return
	var want := h + SILL - PAD_ABOVE_BONE
	var time: float = rise[-1][0]
	for k in range(1, rise.size()):
		var y0: float = rise[k - 1][1]
		var y1: float = rise[k][1]
		if y1 >= want and y1 > y0:
			time = lerpf(rise[k - 1][0], rise[k][0], clampf((want - y0) / (y1 - y0), 0.0, 1.0))
			break
	lift_anim.seek(time, true)


# ------------------------------------------------------------------ the shop

func setup_boxes(sources: Dictionary) -> void:
	if kei != null:
		kei.setup(sources)


## A tap on the shop shot: the box under it ("" = none). Emits box_picked.
func pick_box(screen_pos: Vector2) -> String:
	if kei == null:
		return ""
	var id: String = kei.pick(cam, screen_pos)
	if id != "":
		box_picked.emit(id)
	return id


func selected_box() -> String:
	return kei.selected if kei != null else ""


# ------------------------------------------------------------------ the car + settings

func show_parts(ids: Array) -> void:
	if parts_shown == null or ids != parts_shown:
		parts_shown = ids.duplicate()
		if car != null:
			car.build(ids)


## The DX's strobes (body shop) flashing or not (home's STROBES button).
func set_strobes(on: bool) -> void:
	if car != null:
		car.strobes_on = on


## The other cars parked in the garage, on or off (the settings screen).
func show_parked_car(on: bool) -> void:
	if other != null:
		other.visible = on


## The tube over the DX's stall, 0 (dead) .. LIGHT_LEVELS - 1 (Spire: brightness on the home screen).
func set_light(level: int) -> void:
	var k := float(clampi(level, 0, LIGHT_LEVELS - 1)) / float(LIGHT_LEVELS - 1)
	stall_tube.light_energy = 6.4 * k * k
	(stall_tube_mesh.material_override as StandardMaterial3D).emission_energy_multiplier = 0.2 + 3.0 * k


# ------------------------------------------------------------------ the garage

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
	env.fog_density = 0.06
	env.glow_enabled = true                     # the tubes bloom like they do on a camcorder
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	build_lot(vp)
	var tl := tube_light(vp, CAR_AT + Vector3(-0.6, CEIL_Y - 0.25, 0.0), 3.2, 6.5, true)   # over the DX's stall
	stall_tube = tl[0]
	stall_tube_mesh = tl[1]
	tube_light(vp, LIFT_AT + Vector3(0.4, CEIL_Y - 0.25, 0.0), 3.6, 7.5, true)           # over the lift
	tube_light(vp, CREW_AT + Vector3(1.6, CEIL_Y - 1.65, 0.0), 1.2, 4.5, false)          # the crew corner
	var f := tube_light(vp, Vector3(1.5, CEIL_Y - 0.25, 7.5), 1.3, 7.0, false)          # the bad one
	flicker = f[0]
	flicker_tube = f[1]
	tube_mesh(vp, Vector3(1.5, CEIL_Y - 0.2, -2.0), Color(0.15, 0.16, 0.18), 0.0)       # dead
	build_lift(vp)
	kei = KeiSet.new()
	kei.position = KEI_AT
	vp.add_child(kei)

	car = DxModel.new()
	car.lights_on = false
	car.position = CAR_AT
	car.rotation.y = PI                         # nose out into the aisle
	vp.add_child(car)
	car.build(parts_shown if parts_shown != null else [])
	parts_shown = parts_shown if parts_shown != null else []

	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = FOV
	cam.near = 0.05
	vp.add_child(cam)


## The garage, low poly (Spire: low-poly kanjo): laid out like Spire's scan
## (art/models/parking_garage.glb), built from flat-shaded shapes. A row of
## stalls along the back wall (x = BACK_X), the aisle in front, the lift bay
## and the kei truck across it, pillars with red/white hazard bands, beams, a
## concrete floor of faceted tiles, other people's cars in the other stalls.
const BACK_X := 9.3
const ROOM := Rect2(-8.0, -6.0, 17.3, 17.0)    # x, z extent of the level
const CEIL_Y := 3.3
const CONCRETE := Color(0.42, 0.41, 0.4)
const FLOOR := Color(0.3, 0.29, 0.28)
const BAND := Color(0.26, 0.3, 0.36)          # the gray-blue strip along the walls' feet
const PAINT := Color(0.86, 0.86, 0.82)        # stall lines
const HAZARD := Color(0.8, 0.16, 0.1)
const CREW_STICKERS := [Color(0.9, 0.15, 0.15), Color(0.97, 0.8, 0.1), Color(0.95, 0.95, 0.92),
	Color(0.2, 0.55, 0.95), Color(0.95, 0.45, 0.1), Color(0.1, 0.1, 0.12)]


func build_lot(vp: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	add_mesh(vp, facet_floor(rng), true)
	solid(vp, Vector3(ROOM.size.x, 0.25, ROOM.size.y), Vector3(ROOM.get_center().x, CEIL_Y + 0.125, ROOM.get_center().y), CONCRETE.darkened(0.25))
	for z in range(int(ROOM.position.y) + 1, int(ROOM.end.y), 5):
		solid(vp, Vector3(ROOM.size.x, 0.35, 0.3), Vector3(ROOM.get_center().x, CEIL_Y - 0.17, z), CONCRETE.darkened(0.15))
	for w: Array in [[Vector3(0.3, CEIL_Y, ROOM.size.y), Vector3(BACK_X + 0.15, 0, ROOM.get_center().y)],
			[Vector3(ROOM.size.x, CEIL_Y, 0.3), Vector3(ROOM.get_center().x, 0, ROOM.end.y)],
			[Vector3(ROOM.size.x, CEIL_Y, 0.3), Vector3(ROOM.get_center().x, 0, ROOM.position.y)],
			[Vector3(0.3, CEIL_Y, ROOM.size.y), Vector3(ROOM.position.x, 0, ROOM.get_center().y)]]:
		var wall_size: Vector3 = w[0]
		var at: Vector3 = w[1]
		solid(vp, wall_size, at + Vector3(0, CEIL_Y / 2.0, 0), CONCRETE)
		solid(vp, wall_size + Vector3(0.02, 0, 0.02) * Vector3(1 if wall_size.x < 1 else 0, 0, 1 if wall_size.z < 1 else 0)
			+ Vector3(0, 0.45 - CEIL_Y, 0), at + Vector3(0, 0.225, 0), BAND)
	for z: float in [-2.5, 0.0, 2.5, 5.0, 7.5, 10.0]:
		solid(vp, Vector3(4.5, 0.012, 0.11), Vector3(BACK_X - 2.25, 0.006, z), PAINT)
	solid(vp, Vector3(0.11, 0.012, 12.6), Vector3(4.8, 0.006, 3.75), PAINT.darkened(0.25))
	for z: float in [-1.25, 1.25, 3.75, 6.25, 8.75]:
		solid(vp, Vector3(0.18, 0.12, 1.6), Vector3(BACK_X - 0.75, 0.06, z), Color(0.55, 0.53, 0.5))
	# The lift bay: yellow lines painted round it
	for z: float in [-4.0, -0.4]:
		solid(vp, Vector3(5.2, 0.012, 0.09), LIFT_AT + Vector3(0.2, 0.006, z + 2.2), Color(0.85, 0.7, 0.15))
	for p: Vector2 in [Vector2(4.6, -2.5), Vector2(4.6, 10.0), Vector2(4.6, 7.5), Vector2(-1.2, -5.0), Vector2(1.5, 10.5)]:
		pillar(vp, Vector3(p.x, 0, p.y))
	solid(vp, Vector3(0.03, 0.3, 0.42), Vector3(BACK_X - 0.01, 1.7, 5.0), Color(0.85, 0.7, 0.1))
	solid(vp, Vector3(0.12, 0.55, 0.5), Vector3(BACK_X - 0.06, 1.15, 0.6), HAZARD)
	glow_box(vp, Vector3(0.05, 0.16, 0.4), Vector3(BACK_X - 0.02, 2.35, 9.0), Color(0.2, 0.95, 0.4), 2.5)
	for z: float in [3.75, 8.75, -1.25]:
		solid(vp, Vector3(1.1, 0.004, 0.8), Vector3(BACK_X - 2.4, 0.003, z + rng.randf_range(-0.2, 0.2)), Color(0.12, 0.11, 0.1))
	# The crew's corner: stickers slapped on the left wall, a red tool chest
	for k in 26:
		var s := Vector3(0.012, rng.randf_range(0.12, 0.3), rng.randf_range(0.18, 0.42))
		var at := CREW_AT + Vector3(0.0, rng.randf_range(-0.7, 0.8), rng.randf_range(-1.3, 1.3))
		var st := solid(vp, s, at, CREW_STICKERS[k % CREW_STICKERS.size()])
		st.rotation.x = rng.randf_range(-0.35, 0.35)
	solid(vp, Vector3(0.6, 1.0, 1.3), CREW_AT + Vector3(0.35, -0.9, -2.2), Color(0.6, 0.1, 0.1))
	# Other people's cars in the other stalls (Spire: random ones): a few of the
	# model cars, a new mix every time; some backed in, some nosed in
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
## slightly different grey and a few millimeters off level, flat-shaded.
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


func solid(vp: Node, box_size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = box_size
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	mi.position = at
	vp.add_child(mi)
	return mi


func glow_box(vp: Node, box_size: Vector3, at: Vector3, color: Color, energy: float) -> void:
	var mi := solid(vp, box_size, at, color)
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


## (Older callers: the reveal's backdrop hides the DX.)
func show_car(on: bool) -> void:
	if car != null:
		car.visible = on
