extends Node2D
## deadtildawn replay viewer.
##
## Plays back a lap exported by tools/export_replay.py (or run_all.py).
## The physics lives in Python; this script only draws and animates.
## Builds the whole scene in code, so main.tscn is just this script.
##
## Portrait layout (720 x 1280): info bar on top, camera / playback buttons
## and the dash (gauges, gear, pedals) at the bottom. Touch or mouse works;
## keys too: 1-4 cameras, C cycle, Space pause, R restart, Up/Down speed.
##
## Cameras: Overview (whole track), Follow (north-up), Chase (car always points
## up, the world turns around it), TV (fixed trackside cameras per corner).
##
## Command line (after "--"):
##   --selftest        step through the replay headless, print checks, quit
##   --shots=<folder>  save stills from every camera at several moments, quit

const REPLAY_PATH := "res://replays/latest.json"
const REPLAY_FORMAT := "deadtildawn-replay"
const SUPPORTED_VERSION := 1

const PX_PER_M := 4.0            # world scale: 1 m = 4 px
const ROAD_WIDTH_M := 8.0        # two-lane mountain road (two 4 m lanes)
const LANE_OFFSET_M := 2.0       # car drives the center of the right-hand lane
const RoadScript := preload("res://widgets/road.gd")
const CAR_LENGTH_M := 4.45       # 6th-gen Civic coupe, roughly
const CAR_WIDTH_M := 1.70
const FOLLOW_VIEW_M := 140.0     # meters of road across the screen in follow mode
const TRACKSIDE_LEAD_M := 150.0  # cut to a corner's camera this far before its entry
const TRACKSIDE_TRAIL_M := 60.0  # ...and keep it this far past the exit
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const LABEL_SCREEN_SCALE := 0.5  # corner labels: 36 px font drawn at ~18 px on screen
const MARKER_RADIUS_PX := 9.0    # car marker ring, constant size on screen
const TOP_BAR_PX := 196.0        # info bar height (screen px)
const BOTTOM_PX := 420.0         # camera buttons + dash height (screen px)
const CHASE_VIEW_M := 110.0      # meters across the screen in chase mode
const CHASE_LOOKAHEAD_M := 22.0  # chase camera looks ahead so the car sits low on screen
const PEDAL_H := 210.0
const GaugeScript := preload("res://gauge.gd")

signal finished_viewing     # embedded mode: player pressed Continue after the finish

enum CamMode { OVERVIEW, FOLLOW, CHASE, TRACKSIDE }
const CAM_NAMES := ["Overview", "Follow", "Chase", "TV"]

# Set these before adding the viewer to the tree (game.gd does); defaults = standalone
var replay_path := REPLAY_PATH
var rival_name := ""
var rival_time := -1.0      # posted time to beat; < 0 = no rival
var embedded := false       # inside the game: Continue button, broadcast cameras

var replay: Dictionary = {}
var samples: Dictionary = {}
var corners: Array = []
var driver = null          # Dictionary, or null for a theoretical-limit run
var lap_time := 0.0

var t := 0.0              # playback time (s)
var idx := 0              # current sample index (t is between idx and idx + 1)
var playing := true
var speed_i := 2          # index into SPEEDS (1x)
var cam_mode: int = CamMode.OVERVIEW
var active_corner := -1

var camera: Camera2D
var car: Node2D
var brake_lights: Polygon2D
var track_center := Vector2.ZERO
var track_size := Vector2.ONE
var hud := {}             # name -> HUD node
var corner_labels := []   # [Label, corner midpoint, outward direction], rescaled with the zoom
var marker: Node2D


# ------------------------------------------------------------------ setup

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.16, 0.2, 0.15))   # grass
	var err := load_replay(replay_path)
	if err != "":
		show_message(err)
		return
	build_track()
	build_car()
	build_camera()
	build_hud()
	set_cam_mode(CamMode.TRACKSIDE if embedded else CamMode.OVERVIEW)
	var args := OS.get_cmdline_user_args()
	if "--selftest" in args:
		self_test()
	for a in args:
		if a.begins_with("--shots="):
			take_screenshots(a.trim_prefix("--shots="))


## Returns "" on success, otherwise a message to show.
func load_replay(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "No replay found.\n\nIn the repo, run:\n    python tools/export_replay.py\nthen restart this viewer."
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or data.get("format") != REPLAY_FORMAT:
		return "%s is not a deadtildawn replay." % path
	if int(data.get("version", 0)) != SUPPORTED_VERSION:
		return "Replay format version %s, but this viewer reads version %d.\nUpdate the viewer or re-export the replay." \
			% [str(data.get("version")), SUPPORTED_VERSION]
	replay = data
	samples = data["samples"]
	corners = data["track"]["corners"]
	driver = data.get("driver")            # optional block (older replays don't have it)
	lap_time = float(data["lap_time"])
	return ""


func to_world(x: float, y: float) -> Vector2:
	# Sim: meters, y points north. Godot 2D: pixels, y points down. Flip y.
	return Vector2(x, -y) * PX_PER_M


func severity_color(sev: int) -> Color:
	# 1 = red hairpin -> 5-6 = yellow -> 10 = green kink (matches the Python maps)
	var red := Color(0.84, 0.16, 0.17)
	var yellow := Color(1.0, 0.88, 0.5)
	var green := Color(0.1, 0.6, 0.32)
	var f := (sev - 1) / 9.0
	return red.lerp(yellow, f * 2.0) if f < 0.5 else yellow.lerp(green, (f - 0.5) * 2.0)


func make_line(pts: PackedVector2Array, width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.points = pts
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	return line


func build_track() -> void:
	var centerline: Array = replay["track"]["centerline"]
	var pts := PackedVector2Array()
	for p in centerline:
		pts.append(to_world(p[0], p[1]))

	var rect := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		rect = rect.expand(p)
	track_center = rect.get_center()
	track_size = rect.size

	# Road: asphalt, edge lines, dashed center line, severity-colored curbs
	var road: Node2D = RoadScript.new()
	road.points = pts
	road.corners = corners
	road.px_per_m = PX_PER_M
	road.severity_color = severity_color
	add_child(road)

	# Corner labels (kept outside the road and curbs; see rescale_overlays)
	for c in corners:
		var label := Label.new()
		label.text = "%s\nR %d m" % [c["text"], int(c["radius"])]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 36)
		label.add_theme_color_override("font_color", severity_color(int(c["severity"])))
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 10)
		var mid: Array = c["mid"]
		var out: Array = c["outward"]
		label.reset_size()
		label.z_index = 20
		add_child(label)
		var out_dir := Vector2(out[0], -out[1])          # flip y like to_world
		corner_labels.append([label, to_world(mid[0], mid[1]), out_dir])

	# Start and finish lines across the road
	add_child(cross_line(0))
	add_child(cross_line(centerline.size() - 1))


func cross_line(i: int) -> Line2D:
	var centerline: Array = replay["track"]["centerline"]
	var j := clampi(i + (1 if i == 0 else -1), 0, centerline.size() - 1)
	var a := to_world(centerline[i][0], centerline[i][1])
	var b := to_world(centerline[j][0], centerline[j][1])
	var n := (b - a).normalized().orthogonal() * ROAD_WIDTH_M * 0.5 * PX_PER_M
	var line := make_line(PackedVector2Array([a - n, a + n]), 1.2 * PX_PER_M, Color.WHITE)
	line.z_index = 5
	return line


func rect_poly(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


func build_car() -> void:
	# Top-down Civic: +x is the front of the car
	var l := CAR_LENGTH_M * PX_PER_M
	var w := CAR_WIDTH_M * PX_PER_M
	car = Node2D.new()
	car.z_index = 10

	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-l / 2, -w / 2), Vector2(l * 0.38, -w / 2), Vector2(l / 2, -w * 0.3),
		Vector2(l / 2, w * 0.3), Vector2(l * 0.38, w / 2), Vector2(-l / 2, w / 2)])
	body.color = Color(0.86, 0.1, 0.12)
	car.add_child(body)

	var cabin := Polygon2D.new()
	cabin.polygon = rect_poly(-l * 0.22, -w * 0.38, l * 0.42, w * 0.76)
	cabin.color = Color(0.1, 0.1, 0.14)
	car.add_child(cabin)

	brake_lights = Polygon2D.new()
	brake_lights.polygon = rect_poly(-l / 2, -w / 2, l * 0.05, w)
	brake_lights.color = Color(0.35, 0.0, 0.0)
	car.add_child(brake_lights)

	add_child(car)

	# Ring around the car that stays the same size on screen (visible when zoomed out)
	marker = Node2D.new()
	marker.z_index = 11
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 33:
		pts.append(Vector2.from_angle(TAU * i / 32.0) * MARKER_RADIUS_PX)
	ring.points = pts
	ring.width = 3.0
	ring.default_color = Color(1.0, 0.85, 0.2)
	marker.add_child(ring)
	add_child(marker)


func build_camera() -> void:
	camera = Camera2D.new()
	# Camera2D ignores its own rotation by default; the chase camera needs it
	camera.ignore_rotation = false
	add_child(camera)
	camera.make_current()


# ------------------------------------------------------------------ HUD

func add_label(parent: Node, pos: Vector2, size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label


func add_bar(parent: Node, pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	## A background box with a fill rectangle; returns the fill.
	var bg := ColorRect.new()
	bg.position = pos
	bg.size = size
	bg.color = Color(1, 1, 1, 0.08)
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.position = pos
	fill.size = size
	fill.color = color
	parent.add_child(fill)
	return fill


func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Top info bar
	var top := ColorRect.new()
	top.color = Color(0.05, 0.05, 0.06, 0.82)
	layer.add_child(top)
	hud["top"] = top
	hud["clock"] = add_label(top, Vector2(28, 40), 58)
	hud["title"] = add_label(top, Vector2(30, 112), 22, Color(0.7, 0.71, 0.75))
	hud["title"].text = "%s  /  %s" % [replay["car"]["name"], str(replay["track"]["name"]).get_basename().replace("_", " ")]
	hud["status"] = add_label(top, Vector2(30, 142), 24, Color(1.0, 0.55, 0.1))

	# Bottom: camera + playback buttons, then the dash
	var bottom := ColorRect.new()
	bottom.color = Color(0.05, 0.05, 0.06, 0.88)
	layer.add_child(bottom)
	hud["bottom"] = bottom

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	bottom.add_child(buttons)
	hud["buttons"] = buttons
	hud["cam_buttons"] = []
	for i in CAM_NAMES.size():
		var b := Button.new()
		b.text = CAM_NAMES[i]
		b.add_theme_font_size_override("font_size", 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(set_cam_mode.bind(i))
		buttons.add_child(b)
		hud["cam_buttons"].append(b)
	var play := Button.new()
	play.add_theme_font_size_override("font_size", 22)
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(toggle_play)
	buttons.add_child(play)
	hud["play"] = play
	var speed := Button.new()
	speed.add_theme_font_size_override("font_size", 22)
	speed.focus_mode = Control.FOCUS_NONE
	speed.pressed.connect(func(): speed_i = (speed_i + 1) % SPEEDS.size())
	buttons.add_child(speed)
	hud["speed_btn"] = speed

	var dash := Control.new()
	bottom.add_child(dash)
	hud["dash"] = dash
	hud["temp"] = add_label(dash, Vector2(24, 0), 22, Color(0.8, 0.8, 0.82))

	var tach: Control = GaugeScript.new()
	tach.position = Vector2(14, 34)
	tach.size = Vector2(250, 250)
	tach.max_value = 8000.0
	tach.major_step = 1000.0
	tach.minor_step = 500.0
	tach.label_scale = 0.001
	tach.redline_from = float(replay["car"]["redline"])
	tach.title = "rpm x1000"
	dash.add_child(tach)
	hud["tach"] = tach

	var speedo: Control = GaugeScript.new()
	speedo.position = Vector2(272, 34)
	speedo.size = Vector2(250, 250)
	speedo.max_value = 200.0
	speedo.major_step = 40.0
	speedo.minor_step = 10.0
	speedo.title = "km/h"
	dash.add_child(speedo)
	hud["speedo"] = speedo

	hud["gear"] = add_label(dash, Vector2(560, 22), 72, Color(1.0, 0.85, 0.3))
	hud["gear_caption"] = add_label(dash, Vector2(552, 104), 16, Color(0.6, 0.61, 0.66))
	hud["gear_caption"].text = "GEAR"
	hud["throttle"] = add_bar(dash, Vector2(616, 70), Vector2(30, PEDAL_H), Color(0.3, 0.8, 0.4))
	hud["brake"] = add_bar(dash, Vector2(656, 70), Vector2(30, PEDAL_H), Color(0.93, 0.17, 0.24))

	hud["banner"] = add_label(layer, Vector2.ZERO, 52, Color(1.0, 0.9, 0.4))
	hud["mistake"] = add_label(layer, Vector2.ZERO, 34, Color(1.0, 0.55, 0.1))
	if embedded:
		var cont := Button.new()
		cont.text = "CONTINUE"
		cont.theme_type_variation = "AccentButton"
		cont.visible = false
		cont.pressed.connect(func(): finished_viewing.emit())
		layer.add_child(cont)
		hud["continue"] = cont


func update_hud() -> void:
	var vp := get_viewport_rect().size
	var top: ColorRect = hud["top"]
	top.position = Vector2.ZERO
	top.size = Vector2(vp.x, TOP_BAR_PX)
	var bottom: ColorRect = hud["bottom"]
	bottom.position = Vector2(0, vp.y - BOTTOM_PX)
	bottom.size = Vector2(vp.x, BOTTOM_PX)
	var buttons: HBoxContainer = hud["buttons"]
	buttons.position = Vector2(14, 14)
	buttons.size = Vector2(vp.x - 28, 64)
	hud["dash"].position = Vector2((vp.x - 720.0) / 2.0, 100)

	hud["clock"].text = "%.2f" % t + (" / %.2f" % rival_time if rival_time > 0 else "")
	var push_text := "THEORETICAL LIMIT"
	if driver != null:
		push_text = "%s PUSH" % str(driver["push"]).replace("_", " ").to_upper()
	hud["status"].text = push_text + ("   vs  %s" % rival_name.to_upper() if rival_time > 0 else "")

	for i in hud["cam_buttons"].size():
		var b: Button = hud["cam_buttons"][i]
		b.theme_type_variation = "SelectedButton" if i == cam_mode else ""
	hud["play"].text = "||" if playing and t < lap_time else ">"
	hud["speed_btn"].text = "%sx" % str(SPEEDS[speed_i])

	var gear := int(samples["gear"][idx])
	hud["gear"].text = "-" if gear == 0 else str(gear)
	hud["tach"].value = value_at("rpm")
	hud["speedo"].value = value_at("v") * 3.6

	var temp := value_at("brake_temp")
	var fade := float(replay["car"]["pad_fade_temp"])
	hud["temp"].text = "FRONT ROTOR %d C%s" % [int(temp), "   FADING" if temp > fade else ""]
	hud["temp"].add_theme_color_override("font_color", Color(1, 0.35, 0.3) if temp > fade else Color(0.8, 0.8, 0.82))
	set_pedal(hud["throttle"], value_at("throttle"), Vector2(616, 70))
	set_pedal(hud["brake"], value_at("brake"), Vector2(656, 70))

	# Finish banner (two lines with a rival) and Continue
	var banner: Label = hud["banner"]
	banner.visible = t >= lap_time
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.text = "FINISH  %.2f" % lap_time
	if rival_time > 0:
		var gap := absf(lap_time - rival_time)
		var won := lap_time < rival_time
		banner.text += "\n%s %s BY %.2f" % ["BEAT" if won else "LOST TO", rival_name.to_upper(), gap]
		banner.add_theme_color_override("font_color", Color(0.46, 0.77, 0.4) if won else Color(0.93, 0.17, 0.24))
	banner.reset_size()
	banner.position = Vector2((vp.x - banner.size.x) / 2, TOP_BAR_PX + 30)
	if hud.has("continue"):
		var cont: Button = hud["continue"]
		cont.visible = t >= lap_time
		cont.reset_size()
		cont.size.x = vp.x - 120
		cont.position = Vector2(60, TOP_BAR_PX + 190)

	# Mistake callout: from the apex of a mistaken corner until shortly after it
	var mistake: Label = hud["mistake"]
	mistake.visible = false
	if driver != null and t < lap_time:
		var s_now := value_at("s")
		for c in driver["corners"]:
			var s0 := float(c["s_start"])
			var s1 := float(c["s_end"])
			if c["mistake"] and s_now >= (s0 + s1) / 2.0 and s_now <= s1 + 40.0:
				mistake.text = "MISTAKE: RAN WIDE AT %s" % str(c["text"]).to_upper()
				mistake.reset_size()
				mistake.position = Vector2((vp.x - mistake.size.x) / 2, TOP_BAR_PX + 24)
				mistake.visible = true


func set_pedal(fill: ColorRect, amount: float, base: Vector2) -> void:
	# Vertical bar that fills from the bottom
	var h := PEDAL_H * clampf(amount, 0.0, 1.0)
	fill.size = Vector2(30, h)
	fill.position = Vector2(base.x, base.y + PEDAL_H - h)


func toggle_play() -> void:
	if t >= lap_time:
		restart()
	else:
		playing = not playing


# ------------------------------------------------------------------ playback

func _process(delta: float) -> void:
	if samples.is_empty():
		return
	if playing:
		t = minf(t + delta * SPEEDS[speed_i], lap_time)
	update_car()
	update_camera(delta, false)
	update_hud()


func find_index() -> void:
	## Move idx so that samples.t[idx] <= t < samples.t[idx + 1].
	var ts: Array = samples["t"]
	while idx < ts.size() - 2 and float(ts[idx + 1]) <= t:
		idx += 1
	while idx > 0 and float(ts[idx]) > t:
		idx -= 1


func frac() -> float:
	var ts: Array = samples["t"]
	var t0 := float(ts[idx])
	var t1 := float(ts[idx + 1])
	return 0.0 if t1 <= t0 else clampf((t - t0) / (t1 - t0), 0.0, 1.0)


func value_at(key: String) -> float:
	## Telemetry channel linearly interpolated at playback time t.
	var arr: Array = samples[key]
	return lerpf(float(arr[idx]), float(arr[idx + 1]), frac())


func update_car() -> void:
	find_index()
	var h0 := float(samples["heading"][idx])
	var h1 := float(samples["heading"][idx + 1])
	var h := lerp_angle(h0, h1, frac())
	# Right-hand lane: shift the centerline point toward the right of travel.
	# (Visual only: the physics uses the centerline radius.)
	car.position = to_world(value_at("x") + sin(h) * LANE_OFFSET_M,
		value_at("y") - cos(h) * LANE_OFFSET_M)
	car.rotation = -h                                 # flip: Godot rotates clockwise
	var braking := value_at("brake") > 0.0
	brake_lights.color = Color(1.0, 0.1, 0.1) if braking else Color(0.35, 0.0, 0.0)


# ------------------------------------------------------------------ cameras

func set_cam_mode(mode: int) -> void:
	cam_mode = mode
	active_corner = -1
	update_camera(0.0, true)


func pick_corner(s: float) -> int:
	## TV camera: the corner the car is approaching or in, or -1 when the car
	## is far from every corner camera (then the broadcast follows the car).
	for i in corners.size():
		var c: Dictionary = corners[i]
		if s >= float(c["s_start"]) - TRACKSIDE_LEAD_M and s <= float(c["s_end"]) + TRACKSIDE_TRAIL_M:
			return i
	return -1


func view_area() -> Rect2:
	## Screen area between the top bar and the bottom panel.
	var vp := get_viewport_rect().size
	return Rect2(0, TOP_BAR_PX, vp.x, vp.y - TOP_BAR_PX - BOTTOM_PX)


func update_camera(delta: float, snap: bool) -> void:
	var vp := get_viewport_rect().size
	var area := view_area()
	var target_pos := car.position
	var target_zoom := area.size.x / (FOLLOW_VIEW_M * PX_PER_M)
	var target_rot := 0.0
	var cut := snap

	if cam_mode == CamMode.OVERVIEW:
		var margin := 120.0 * PX_PER_M                # room for labels outside the road
		target_zoom = minf(area.size.x / (track_size.x + margin), area.size.y / (track_size.y + margin))
		target_pos = track_center
	elif cam_mode == CamMode.CHASE:
		# Car always points up: rotate the camera with the car; look ahead along
		# the heading so the car sits in the lower part of the view
		target_zoom = area.size.x / (CHASE_VIEW_M * PX_PER_M)
		target_rot = car.rotation + PI / 2.0
		target_pos = car.position + Vector2.from_angle(car.rotation) * CHASE_LOOKAHEAD_M * PX_PER_M
	elif cam_mode == CamMode.TRACKSIDE and not corners.is_empty():
		var i := pick_corner(value_at("s"))
		if i != active_corner:
			active_corner = i
			cut = true                               # TV-style hard cut between cameras
		if active_corner >= 0:                       # a corner camera has the car
			var c: Dictionary = corners[active_corner]
			var r := float(c["radius"])
			var mid: Array = c["mid"]
			var out: Array = c["outward"]
			target_pos = to_world(mid[0] + out[0] * r * 0.15, mid[1] + out[1] * r * 0.15)
			var view_m := clampf(r * 4.5, 110.0, 420.0)
			target_zoom = minf(area.size.x, area.size.y) / (view_m * PX_PER_M)
		# else: between camera positions, keep the follow-camera defaults

	# The view area isn't centered vertically (top bar vs bottom panel): shift
	# the camera so target_pos lands in the middle of the view area
	var screen_offset := Vector2(0, (vp.y / 2.0) - area.get_center().y)

	if cut:
		camera.zoom = Vector2.ONE * target_zoom
		camera.rotation = target_rot
	else:
		var k := 1.0 - exp(-delta * 6.0)             # smooth, frame-rate independent
		camera.zoom = camera.zoom.lerp(Vector2.ONE * target_zoom, k)
		camera.rotation = lerp_angle(camera.rotation, target_rot, 1.0 - exp(-delta * 8.0))
	var world_offset := (screen_offset / camera.zoom.x).rotated(camera.rotation)
	var final_pos := target_pos + world_offset
	if cut:
		camera.position = final_pos
	else:
		camera.position = camera.position.lerp(final_pos, 1.0 - exp(-delta * 6.0))
	rescale_overlays()


## Keep corner labels and the car marker a constant size on screen
## (world size = screen size / zoom), and upright when the camera rotates.
func rescale_overlays() -> void:
	var inv := 1.0 / camera.zoom.x
	for entry in corner_labels:
		var label: Label = entry[0]
		var mid: Vector2 = entry[1]
		var out_dir: Vector2 = entry[2]
		label.scale = Vector2.ONE * LABEL_SCREEN_SCALE * inv
		label.pivot_offset = label.size / 2.0
		label.rotation = camera.rotation
		var half := label.size * label.scale / 2.0
		var reach := maxf(half.x, half.y)
		var center := mid + out_dir * ((ROAD_WIDTH_M / 2.0 + 1.2) * PX_PER_M + 10.0 * inv + reach)
		label.position = center - label.size / 2.0
	marker.position = car.position
	marker.scale = Vector2.ONE * inv
	marker.visible = cam_mode == CamMode.OVERVIEW or cam_mode == CamMode.TRACKSIDE


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			set_cam_mode(CamMode.OVERVIEW)
		KEY_2:
			set_cam_mode(CamMode.FOLLOW)
		KEY_3:
			set_cam_mode(CamMode.CHASE)
		KEY_4:
			set_cam_mode(CamMode.TRACKSIDE)
		KEY_C:
			set_cam_mode((cam_mode + 1) % CAM_NAMES.size())
		KEY_SPACE:
			toggle_play()
		KEY_R:
			restart()
		KEY_UP:
			speed_i = mini(speed_i + 1, SPEEDS.size() - 1)
		KEY_DOWN:
			speed_i = maxi(speed_i - 1, 0)
		KEY_ENTER, KEY_KP_ENTER:
			if embedded and t >= lap_time:
				finished_viewing.emit()


func restart() -> void:
	t = 0.0
	idx = 0
	playing = true


func show_message(text: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := add_label(layer, Vector2(40, 200), 28)
	label.text = text


# ------------------------------------------------------------------ self-test

## Headless check: step through the replay and every camera, print what
## the viewer sees, then quit. Run with:  godot --headless -- --selftest
func self_test() -> void:
	print("SELFTEST samples=%d lap_time=%.2f corners=%d" % [samples["t"].size(), lap_time, corners.size()])
	for check_t in [0.0, lap_time * 0.25, lap_time * 0.5, lap_time * 0.75, lap_time]:
		t = check_t
		update_car()
		for mode in [CamMode.OVERVIEW, CamMode.FOLLOW, CamMode.CHASE, CamMode.TRACKSIDE]:
			set_cam_mode(mode)
		update_hud()
		print("t=%7.2f s=%7.1f m  pos=(%7.1f, %7.1f) m  v=%5.1f km/h  gear=%d  corner_cam=%d" % [
			t, value_at("s"), car.position.x / PX_PER_M, -car.position.y / PX_PER_M,
			value_at("v") * 3.6, int(samples["gear"][idx]), active_corner])
	print("SELFTEST OK")
	get_tree().quit()


## Save stills: every camera at a few moments in the run, then quit.
## Needs a real (or virtual) display, not --headless.
func take_screenshots(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	playing = false
	var moments := {"start": 2.0, "r3_entry": 24.0, "hairpin": 34.5, "finish": lap_time}
	if driver != null:                          # also catch any mistake on camera
		for c in driver["corners"]:
			if c["mistake"]:
				moments["mistake_" + str(c["text"]).replace(" ", "_")] = time_at_s(float(c["s_end"]))
	for moment in moments:
		t = minf(float(moments[moment]), lap_time)
		update_car()
		for mode in [CamMode.OVERVIEW, CamMode.FOLLOW, CamMode.CHASE, CamMode.TRACKSIDE]:
			set_cam_mode(mode)
			update_hud()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var path := "%s/%s_%s.png" % [folder, moment, CAM_NAMES[mode].to_lower()]
			get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path)
	get_tree().quit()



## Playback time when the car reaches track position s (for screenshots).
func time_at_s(s_target: float) -> float:
	var ss: Array = samples["s"]
	var ts: Array = samples["t"]
	for i in range(1, ss.size()):
		if float(ss[i]) >= s_target:
			return float(ts[i])
	return lap_time
