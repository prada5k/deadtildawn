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
const CAR_LENGTH_M := 4.070      # 1995 EG6 factory length
const CAR_WIDTH_M := 1.695      # 1995 EG6 factory width
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
const ChaseScript := preload("res://widgets/replay_chase.gd")
const GearBoxScript := preload("res://widgets/gear_box.gd")

signal finished_viewing     # embedded mode: player pressed Continue after the finish

enum CamMode { OVERVIEW, FOLLOW, CHASE, TRACKSIDE, REAR }
const CAM_NAMES := ["Overview", "Follow", "Chase", "TV", "REAR"]   # REAR = the 3D low rear-bumper camera (widgets/replay_chase.gd)

# Set these before adding the viewer to the tree (game.gd does); defaults = standalone
var replay_path := REPLAY_PATH
var rival_name := ""
var rival_time := -1.0      # posted time to beat; < 0 = no rival
var embedded := false       # inside the game: Continue button, broadcast cameras
var status_text := ""       # optional non-race label for reused controlled-test playback
var vehicle_visual_status := ""

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
var chase = null           # the 3D rear chase camera (widgets/replay_chase.gd)


# ------------------------------------------------------------------ setup

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.16, 0.2, 0.15))   # grass
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--replay="):
			replay_path = arg.trim_prefix("--replay=")
	var err := load_replay(replay_path)
	if err != "":
		show_message(err)
		return
	build_track()
	build_car()
	build_camera()
	build_chase()
	build_hud()
	var start_mode: int = CamMode.REAR if embedded else CamMode.OVERVIEW      # the signature view is the low rear camera
	for a in args:
		if a.begins_with("--cam="):                          # standalone: --cam=overview|follow|chase|tv|rear
			var found := CAM_NAMES.map(func(n: String): return n.to_lower()).find(a.trim_prefix("--cam=").to_lower())
			if found >= 0:
				start_mode = found
	for a in args:
		if a.begins_with("--view="):                         # QA stills: a camera beside the car (side | rear_close | front34)
			chase.debug_view = a.trim_prefix("--view=")
		if a.begins_with("--exaggerate="):                   # QA stills: x the body motion so its direction shows (never in the game)
			chase.debug_exaggerate = float(a.trim_prefix("--exaggerate="))
	set_cam_mode(start_mode)
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
	car = Node2D.new()
	car.z_index = 10
	if not add_selected_vehicle_visual(car):
		build_generic_replay_marker(car)

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


func build_generic_replay_marker(parent: Node2D) -> void:
	# Fallback marker for runs without a selected 3D replay visual.
	var l := CAR_LENGTH_M * PX_PER_M
	var w := CAR_WIDTH_M * PX_PER_M
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-l / 2, -w / 2), Vector2(l * 0.38, -w / 2), Vector2(l / 2, -w * 0.3),
		Vector2(l / 2, w * 0.3), Vector2(l * 0.38, w / 2), Vector2(-l / 2, w / 2)])
	body.color = Color(0.86, 0.1, 0.12)
	parent.add_child(body)
	var cabin := Polygon2D.new()
	cabin.polygon = rect_poly(-l * 0.22, -w * 0.38, l * 0.42, w * 0.76)
	cabin.color = Color(0.1, 0.1, 0.14)
	parent.add_child(cabin)
	brake_lights = Polygon2D.new()
	brake_lights.polygon = rect_poly(-l / 2, -w / 2, l * 0.05, w)
	brake_lights.color = Color(0.35, 0.0, 0.0)
	parent.add_child(brake_lights)


func add_selected_vehicle_visual(parent: Node2D) -> bool:
	## Visual choice belongs to replay metadata. It never changes vehicle identity,
	## simulation inputs, or the persistent race result.
	var selection: Dictionary = replay.get("vehicle_visual", {})
	if selection.is_empty() or str(selection.get("role", "")) != "temporary_visual_proxy":
		return false
	var asset_path := str(selection.get("asset_path", ""))
	var absolute_path := ProjectSettings.globalize_path(asset_path)
	if asset_path == "" or not FileAccess.file_exists(absolute_path):
		vehicle_visual_status = "TEMPORARY VISUAL PROXY MISSING / GENERIC MARKER SHOWN"
		return false
	var document := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var error := document.append_from_file(absolute_path, gltf_state)
	if error != OK:
		vehicle_visual_status = "TEMPORARY VISUAL PROXY FAILED TO LOAD / GENERIC MARKER SHOWN"
		push_warning("Could not load replay visual proxy %s (error %d)" % [asset_path, error])
		return false
	var model := document.generate_scene(gltf_state)
	if model == null:
		vehicle_visual_status = "TEMPORARY VISUAL PROXY FAILED TO BUILD / GENERIC MARKER SHOWN"
		return false

	var viewport := SubViewport.new()
	viewport.name = "ReplayVehicleVisualViewport"
	viewport.size = Vector2i(256, 144)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var stage := Node3D.new()
	stage.name = "ReplayVehicleVisualStage"
	viewport.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0, 0, 0, 0)
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 35, 0)
	light.light_energy = 1.4
	stage.add_child(light)
	stage.add_child(model)
	var bounds := [false, AABB()]
	collect_vehicle_visual_bounds(model, Transform3D.IDENTITY, bounds)
	if not bounds[0]:
		viewport.queue_free()
		vehicle_visual_status = "TEMPORARY VISUAL PROXY HAS NO MESH / GENERIC MARKER SHOWN"
		return false
	var model_bounds: AABB = bounds[1]
	var center := model_bounds.position + model_bounds.size * 0.5
	var largest_dimension := maxf(model_bounds.size.x, maxf(model_bounds.size.y, model_bounds.size.z))
	if largest_dimension <= 0.0:
		viewport.queue_free()
		return false
	var fit_scale := CAR_LENGTH_M / largest_dimension
	model.scale = Vector3.ONE * fit_scale
	model.position = -center * fit_scale
	var camera := Camera3D.new()
	camera.position = Vector3(3.8, 2.8, 4.8)
	camera.fov = 38.0
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	var sprite := Sprite2D.new()
	sprite.texture = viewport.get_texture()
	sprite.scale = Vector2(0.075, 0.075)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(sprite)
	vehicle_visual_status = str(selection.get("asset_label", "TEMPORARY VISUAL PROXY"))
	return true


func collect_vehicle_visual_bounds(node: Node, parent_transform: Transform3D, bounds: Array) -> void:
	var node_transform := parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform
	if node is VisualInstance3D:
		var transformed: AABB = node_transform * (node as VisualInstance3D).get_aabb()
		if bounds[0]:
			var old_bounds: AABB = bounds[1]
			bounds[1] = old_bounds.merge(transformed)
		else:
			bounds[0] = true
			bounds[1] = transformed
	for child in node.get_children():
		collect_vehicle_visual_bounds(child, node_transform, bounds)


func build_chase() -> void:
	chase = ChaseScript.new()
	add_child(chase)
	chase.build(replay)


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
	layer.layer = 2                       # above the 3D rear view (its layer is 1)
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
	hud["visual_notice"] = add_label(top, Vector2(30, 168), 17, Color(0.92, 0.78, 0.47))
	var visual_selection: Dictionary = replay.get("vehicle_visual", {})
	hud["visual_notice"].text = "%s / SIM / %s" % [
		str(visual_selection.get("asset_label", vehicle_visual_status)), str(replay["car"].get("name", "UNKNOWN VEHICLE"))]
	hud["visual_notice"].visible = not visual_selection.is_empty() or vehicle_visual_status != ""

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
		b.add_theme_font_size_override("font_size", 20)
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

	# The instrument cluster (gauge.gd "honda90s"). Scales come from the replay's own recorded numbers: the tach
	# reads a little past the recorded fuel cut with the red band from the recorded redline; the speedometer
	# reads past the recorded top speed. A channel the replay doesn't carry shows NO DATA, never a made-up value.
	var redline := float(replay["car"]["redline"])
	var fuel_cut := float(replay["car"].get("fuel_cut", redline))
	var tach: Control = GaugeScript.new()
	tach.position = Vector2(12, 34)
	tach.size = Vector2(262, 262)
	tach.max_value = clampf(ceilf((fuel_cut + 1.0) / 1000.0) * 1000.0, 7000.0, 10000.0)
	tach.major_step = 1000.0
	tach.minor_step = 500.0
	tach.label_scale = 0.001
	tach.redline_from = redline
	tach.limiter_at = fuel_cut
	tach.title = "x1000 r/min"
	dash.add_child(tach)
	hud["tach"] = tach

	var top_kmh := 0.0
	if has_channel("v"):
		for v in samples["v"]:
			top_kmh = maxf(top_kmh, float(v) * 3.6)
	var speedo: Control = GaugeScript.new()
	speedo.position = Vector2(282, 34)
	speedo.size = Vector2(262, 262)
	speedo.max_value = clampf(ceilf(top_kmh * 1.15 / 40.0) * 40.0, 160.0, 280.0)
	speedo.major_step = 20.0 if speedo.max_value <= 200.0 else 40.0
	speedo.minor_step = 10.0
	speedo.title = "km/h"
	dash.add_child(speedo)
	hud["speedo"] = speedo

	var gear_box: Control = GearBoxScript.new()
	gear_box.position = Vector2(552, 22)
	gear_box.size = Vector2(56, 84)
	dash.add_child(gear_box)
	hud["gear"] = gear_box
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
	var push_text := status_text if status_text != "" else "THEORETICAL LIMIT"
	if status_text == "" and driver != null:
		push_text = "%s PUSH" % str(driver["push"]).replace("_", " ").to_upper()
	hud["status"].text = push_text + ("   vs  %s" % rival_name.to_upper() if rival_time > 0 else "")

	for i in hud["cam_buttons"].size():
		var b: Button = hud["cam_buttons"][i]
		b.theme_type_variation = "SelectedButton" if i == cam_mode else ""
	hud["play"].text = "||" if playing and t < lap_time else ">"
	hud["speed_btn"].text = "%sx" % str(SPEEDS[speed_i])

	update_cluster()
	var has_temp := has_channel("brake_temp")
	hud["temp"].visible = has_temp
	if has_temp:
		var temp := value_at("brake_temp")
		var fade := float(replay["car"]["pad_fade_temp"])
		hud["temp"].text = "FRONT ROTOR %d C%s" % [int(temp), "   FADING" if temp > fade else ""]
		hud["temp"].add_theme_color_override("font_color", Color(1, 0.35, 0.3) if temp > fade else Color(0.8, 0.8, 0.82))
	hud["throttle"].visible = has_channel("throttle")
	hud["brake"].visible = has_channel("brake")
	if has_channel("throttle"):
		set_pedal(hud["throttle"], value_at("throttle"), Vector2(616, 70))
	if has_channel("brake"):
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


## Does the replay carry this telemetry channel (one value per sample)?
func has_channel(key: String) -> bool:
	return samples.has(key) and samples[key] is Array and (samples[key] as Array).size() == (samples["t"] as Array).size()


## The needles and the gear box show the recorded values at playback time t, unsmoothed. A missing channel is
## shown as NO DATA / "--"; nothing is estimated.
func update_cluster() -> void:
	var tach: Control = hud["tach"]
	tach.available = has_channel("rpm")
	if tach.available:
		tach.value = value_at("rpm")
	var speedo: Control = hud["speedo"]
	speedo.available = has_channel("v")
	if speedo.available:
		speedo.value = value_at("v") * 3.6
	var gear_box: Control = hud["gear"]
	gear_box.available = has_channel("gear")
	if gear_box.available:
		gear_box.gear = int(samples["gear"][idx])


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
	sync_rear()
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
	if is_instance_valid(brake_lights):
		brake_lights.color = Color(1.0, 0.1, 0.1) if braking else Color(0.35, 0.0, 0.0)


# ------------------------------------------------------------------ cameras

func set_cam_mode(mode: int) -> void:
	cam_mode = mode
	active_corner = -1
	update_camera(0.0, true)
	sync_rear()


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


## The 3D camera-car view for the current playback time (update_car has set idx and t). A pure function of t:
## no state is kept between frames, so seek, pause, restart and playback speed cannot change a picture.
## Visual only: it reads the replay, never writes it.
func sync_rear() -> void:
	if chase == null:
		return
	chase.set_active(cam_mode == CamMode.REAR)
	if cam_mode != CamMode.REAR:
		return
	chase.set_area(view_area())
	var heading := lerp_angle(float(samples["heading"][idx]), float(samples["heading"][idx + 1]), frac())
	chase.sync(t, value_at("x"), value_at("y"), heading, value_at("s"), value_at("brake") if has_channel("brake") else 0.0)


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
		KEY_5:
			set_cam_mode(CamMode.REAR)
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
	var samples_hash_before := samples.hash()               # the viewer must never alter the recorded run
	var file_hash_before := FileAccess.get_sha256(replay_path)
	print("SELFTEST samples=%d lap_time=%.2f corners=%d" % [samples["t"].size(), lap_time, corners.size()])
	if not vehicle_visual_status.is_empty():
		print("SELFTEST vehicle visual: %s" % vehicle_visual_status)
	for check_t in [0.0, lap_time * 0.25, lap_time * 0.5, lap_time * 0.75, lap_time]:
		t = check_t
		update_car()
		for mode in [CamMode.OVERVIEW, CamMode.FOLLOW, CamMode.CHASE, CamMode.TRACKSIDE, CamMode.REAR]:
			set_cam_mode(mode)
		update_hud()
		print("t=%7.2f s=%7.1f m  pos=(%7.1f, %7.1f) m  v=%5.1f km/h  gear=%s  corner_cam=%d" % [
			t, value_at("s"), car.position.x / PX_PER_M, -car.position.y / PX_PER_M,
			value_at("v") * 3.6, str(int(samples["gear"][idx])) if has_channel("gear") else "n/a", active_corner])
	var rear_ok := rear_camera_check()
	var motion_ok := motion_check(samples_hash_before, file_hash_before)
	var cluster_ok := cluster_check()
	print("SELFTEST OK" if rear_ok and motion_ok and cluster_ok else "SELFTEST FAIL (camera %s, motion %s, cluster %s)" % [rear_ok, motion_ok, cluster_ok])
	get_tree().quit()


## The cluster must show the recorded telemetry at the playback time: needles = rpm and speed, gear box = gear.
## Checked at many moments; a replay that lacks a channel must show it as unavailable.
func cluster_check() -> bool:
	var worst_rpm := 0.0
	var worst_kmh := 0.0
	var gear_mismatch := 0
	var checks := 0
	for k in 41:
		t = lap_time * k / 40.0
		update_car()
		update_hud()
		checks += 1
		if has_channel("rpm"):
			worst_rpm = maxf(worst_rpm, absf(float(hud["tach"].value) - value_at("rpm")))
		if has_channel("v"):
			worst_kmh = maxf(worst_kmh, absf(float(hud["speedo"].value) - value_at("v") * 3.6))
		if has_channel("gear") and int(hud["gear"].gear) != int(samples["gear"][idx]):
			gear_mismatch += 1
	var tach: Control = hud["tach"]
	var ok := worst_rpm < 0.01 and worst_kmh < 0.01 and gear_mismatch == 0
	print("CLUSTER tach 0..%d redline %d limiter %d | speedo 0..%d | channels rpm=%s v=%s gear=%s | %d checks, worst needle error %.4f rpm / %.4f km/h, gear mismatches %d  %s" % [
		int(tach.max_value), int(tach.redline_from), int(tach.limiter_at), int(hud["speedo"].max_value),
		has_channel("rpm"), has_channel("v"), has_channel("gear"), checks, worst_rpm, worst_kmh, gear_mismatch, "OK" if ok else "FAIL"])
	return ok


## The camera-car view over the whole run, in 0.05 s steps: the filming car must never jump relative to the
## subject, never drop to the ground, always keep the subject in frame, and keep a believable gap. Reads the
## replay only.
func rear_camera_check() -> bool:
	set_cam_mode(CamMode.REAR)
	var step := 0.05
	var worst_jump := 0.0
	var min_height := INF
	var min_d := INF
	var max_d := 0.0
	var min_gap := INF
	var max_gap := 0.0
	var off_screen := 0
	var tightest_margin := 1.0
	var prev_cam := Vector3.ZERO
	var prev_car := Vector3.ZERO
	var first := true
	var tt := 0.0
	while tt <= lap_time + 1e-6:
		t = minf(tt, lap_time)
		update_car()
		sync_rear()
		var m: Dictionary = chase.measure(t)
		if not first:                                   # how far the camera moved relative to the car in one step
			worst_jump = maxf(worst_jump, ((m["camera"] - prev_cam) - (m["car"] - prev_car)).length())
		first = false
		prev_cam = m["camera"]
		prev_car = m["car"]
		min_height = minf(min_height, float(m["height"]))
		min_d = minf(min_d, float(m["distance"]))
		max_d = maxf(max_d, float(m["distance"]))
		min_gap = minf(min_gap, float(m["gap"]))
		max_gap = maxf(max_gap, float(m["gap"]))
		if not m["on_screen"]:
			off_screen += 1
		tightest_margin = minf(tightest_margin, float(m["frame_margin"]))
		tt += step
	var ok := worst_jump < 1.0 and min_height > 0.9 and off_screen == 0 and min_d > 3.0 and tightest_margin > 0.01
	print("REARCAM model=%s  worst relative jump %.2f m/step  lens height min %.2f m  distance %.1f..%.1f m  road gap %.1f..%.1f m  off-screen steps %d  whole-car frame margin min %.1f%%  %s" % [
		chase.model_label, worst_jump, min_height, min_d, max_d, min_gap, max_gap, off_screen, tightest_margin * 100.0, "OK" if ok else "FAIL"])
	return ok


## The visual-only vehicle motion and the filming car, against the recorded run:
##  - the recorded arrays are never touched (hash before / after, and the file on disk);
##  - roll leans OUTWARD in corners (a left turn rolls the roof to the right), braking dives, accelerating squats;
##  - every visual state is a pure function of time: asking for the same moment in any order (seek, restart, any
##    playback speed) gives bit-identical poses.
func motion_check(samples_hash_before: int, file_hash_before: String) -> bool:
	var dyn = chase.dynamics
	var sm: Dictionary = dyn.summary()
	var rsm: Dictionary = chase.rig.dynamics.summary()
	var left_ok := 0
	var left_n := 0
	var right_ok := 0
	var right_n := 0
	var brake_ok := 0
	var brake_n := 0
	var accel_ok := 0
	var accel_n := 0
	for k in dyn.count:
		var ay: float = dyn.a_lat[k] / dyn.G
		var ax: float = dyn.a_long[k] / dyn.G
		if ay > 0.25:
			left_n += 1
			left_ok += 1 if dyn.roll[k] > 0.0 else 0          # left turn: roll > 0 = roof to the right = outward
		elif ay < -0.25:
			right_n += 1
			right_ok += 1 if dyn.roll[k] < 0.0 else 0
		if ax < -0.3:
			brake_n += 1
			brake_ok += 1 if dyn.pitch[k] < 0.0 else 0        # braking: nose down
		elif ax > 0.2:
			accel_n += 1
			accel_ok += 1 if dyn.pitch[k] > 0.0 else 0
	var tel_ok := samples.hash() == samples_hash_before and FileAccess.get_sha256(replay_path) == file_hash_before
	# determinism: the same moments asked for in a different order, and after a restart, give identical poses
	var times: Array = []
	for k in 25:
		times.append(lap_time * float((k * 7) % 25) / 24.0)
	var forward: Array = []
	for tq in times:
		forward.append(pose_signature(float(tq)))
	var identical := true
	for i in times.size():
		var back := times.size() - 1 - i
		if pose_signature(float(times[back])) != forward[back]:
			identical = false
	restart()
	var first_look := pose_signature(0.0)
	identical = identical and first_look == pose_signature(0.0) and first_look == forward[0 if float(times[0]) == 0.0 else 0]
	# (a damped body lags a change of load by a few frames, so the test is agreement over the samples, not every frame)
	var sign_ok := left_ok >= 0.95 * left_n and right_ok >= 0.95 * right_n and brake_ok >= 0.95 * brake_n and accel_ok >= 0.95 * accel_n
	var ok := sign_ok and identical and tel_ok and float(sm["roll_deg"]) <= 6.01
	print("DYNAMICS subject: wheelbase %.2f m (model) | peak lateral %.2f g -> roll %.1f deg | longitudinal %.2f..%.2f g -> pitch %.1f..%.1f deg | steer peak %.1f deg (kinematic, not recorded)" % [
		dyn.wheelbase_m, sm["a_lat_g"], sm["roll_deg"], sm["a_long_min_g"], sm["a_long_max_g"], sm["pitch_min_deg"], sm["pitch_max_deg"], sm["steer_deg"]])
	print("DYNAMICS camera car: roll peak %.1f deg, pitch %.1f..%.1f deg | gap target %.1f m + %.2f per m/s" % [
		rsm["roll_deg"], rsm["pitch_min_deg"], rsm["pitch_max_deg"], chase.rig.gap_m, chase.rig.gap_per_ms])
	print("MOTION signs: left turns roll outward %d/%d, right turns %d/%d, braking dives %d/%d, accelerating squats %d/%d | deterministic across seek / restart: %s | telemetry + file unchanged: %s  %s" % [
		left_ok, left_n, right_ok, right_n, brake_ok, brake_n, accel_ok, accel_n, identical, tel_ok, "OK" if ok else "FAIL"])
	return ok


## A string of the visual state at time t (subject body, steer, and the filming car), for the determinism check:
## equal strings = bit-identical poses.
func pose_signature(tq: float) -> String:
	var body: Dictionary = chase.dynamics.at(tq)
	var shot: Dictionary = chase.rig.at(tq)
	return "%s|%s|%s" % [var_to_str(body), var_to_str(shot["transform"]), var_to_str(shot["gap"])]


## Save stills: every camera at a few moments in the run, then quit.
## Needs a real (or virtual) display, not --headless.
func take_screenshots(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	playing = false
	var moments := {"start": 2.0, "r3_entry": 24.0, "hairpin": 34.5, "finish": lap_time}
	var only_cam := ""                          # --cam=rear: stills of that camera only, at start / mid / near finish
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			only_cam = a.trim_prefix("--cam=").to_lower()
	if only_cam != "":
		moments = {"start": 1.0, "mid": lap_time * 0.5, "late": lap_time * 0.9}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):                   # --at=3.0,12.5: stills at exactly these playback times
			moments = {}
			for part in a.trim_prefix("--at=").split(","):
				moments["t%05.1f" % float(part)] = float(part)
	if driver != null and only_cam == "":       # also catch any mistake on camera
		for c in driver["corners"]:
			if c["mistake"]:
				moments["mistake_" + str(c["text"]).replace(" ", "_")] = time_at_s(float(c["s_end"]))
	for moment in moments:
		t = minf(float(moments[moment]), lap_time)
		update_car()
		for mode in [CamMode.OVERVIEW, CamMode.FOLLOW, CamMode.CHASE, CamMode.TRACKSIDE, CamMode.REAR]:
			if only_cam != "" and CAM_NAMES[mode].to_lower() != only_cam:
				continue
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
