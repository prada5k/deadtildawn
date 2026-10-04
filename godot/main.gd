extends Node2D
## deadtildawn replay viewer.
##
## Plays back a lap exported by tools/export_replay.py (or run_all.py).
## The physics lives in Python; this script only draws and animates.
## Builds the whole scene in code, so main.tscn is just this script.
##
## Portrait layout (720 x 1280): info bar on top, camera / playback buttons
## and the dash (gauges, gear, pedals) at the bottom. Touch or mouse works;
## keys too: 1-2 cameras, C cycle, Space pause, R restart, Up/Down speed.
##
## Cameras: Chase (default: the car always points up, the world turns around
## it) and Overview (the whole road). With an opponent, Chase is SPLIT SCREEN:
## him on the left, Faba on the right, each pane a copy of this viewer in
## "pane" mode (its own world, a chase camera on its car, the clock driven
## from here). Crashes cut tight onto the wreck; a single chase (no opponent)
## cuts to the finish line at the end.
##
## Head-to-head replays carry the opponent as a "ghost" (pose samples on its own
## time base), drawn translucent. A crashed car stops at its crash apex; the
## replay ends when Faba finishes or crashes.
##
## Night: the world (scenery, road, tire marks) sits under a moonlit
## CanvasModulate and is lit by each car's headlights (PointLight2D). Cars,
## labels and effects live on an overlay CanvasLayer that follows the camera,
## so they stay readable. The scenery is the road's PLACE (replay "location":
## coast / canyon / mountain, widgets/scenery.gd).
##
## Broadcast (Best Motoring / VHS tape, widgets/vhs.gdshader): REC + camcorder
## timestamp, viewfinder brackets, camcorder-menu buttons (OsdButton), yellow
## caption boxes, a gap tower and a live gap bar. The race
## intro rolls both cars up to the line with hazards on while a flagger counts
## 3-2-1 with a flashlight. The finish goes slow-mo, cuts to a camera on the
## line, and holds until the second car crosses. Also: tire marks, crash
## sparks/smoke/shake, a finish flash.
##
## Command line (after "--"):
##   --replay=<path>   play this replay instead of replays/latest.json
##   --selftest        step through the replay headless, print checks, quit
##   --shots=<folder>  save stills from every camera at several moments, quit

const REPLAY_PATH := "res://replays/latest.json"
const REPLAY_FORMAT := "deadtildawn-replay"
const SUPPORTED_VERSION := 1

const PX_PER_M := 4.0            # world scale: 1 m = 4 px
const ROAD_WIDTH_M := 8.0        # two-lane mountain road (two 4 m lanes)
const LANE_OFFSET_M := 2.0       # car drives the center of the right-hand lane
const RoadScript := preload("res://widgets/road.gd")
const CarSprite := preload("res://widgets/car_sprite.gd")
const RACING_FONT := preload("res://fonts/RacingSansOne-Regular.ttf")
const VT_FONT := preload("res://fonts/VT323-Regular.ttf")            # camcorder OSD
const BODY_FONT := preload("res://fonts/BarlowCondensed-Bold.ttf")
const SceneryScript := preload("res://widgets/scenery.gd")
const VhsShader := preload("res://widgets/vhs.gdshader")
const Voice := preload("res://voice.gd")
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const LABEL_SCREEN_SCALE := 0.5  # world labels (CRASHED tag): 36 px font drawn at ~18 px on screen
const MARKER_RADIUS_PX := 9.0    # car marker ring, constant size on screen
const TOP_BAR_PX := 196.0        # info bar height (screen px)
const BOTTOM_PX := 420.0         # camera buttons + dash height (screen px)
const CHASE_VIEW_M := 80.0       # meters across the screen in chase mode
const CHASE_LOOKAHEAD_M := 22.0  # chase camera looks ahead so the car sits low on screen
const PANE_VIEW_M := 46.0        # split screen: meters across one (half-width) pane
const PANE_GAP_PX := 4.0         # the seam between the panes
const PEDAL_H := 210.0
const BRAKE_X := 616.0        # pedal bars, in the car's order: brake left, throttle right
const THROTTLE_X := 656.0
const GaugeScript := preload("res://gauge.gd")
const MARKER_COLOR := Color(1.0, 0.85, 0.2)
const GHOST_MARKER_COLOR := Color(0.45, 0.7, 1.0)
const WIN_COLOR := Color(0.46, 0.77, 0.4)
const LOSS_COLOR := Color(0.93, 0.17, 0.24)
const BANNER_COLOR := Color(1.0, 0.9, 0.4)
const INK := Color(0.06, 0.025, 0.03)

# Night
const NIGHT_SKY := Color(0.02, 0.025, 0.03)    # beyond the scenery
const MOONLIGHT := Color(0.4, 0.43, 0.6)      # CanvasModulate: everything unlit (bright enough to read the place)
const HEADLIGHT_COLOR := Color(1.0, 0.93, 0.74)
const HEADLIGHT_RANGE_M := 60.0
const HEADLIGHT_HALF_ANGLE := 0.5              # rad (~29 deg)
const HAZARD := Color(1.0, 0.55, 0.1)

# Broadcast
const ROLL_S := 1.6              # intro: the cars roll up to the line...
const ROLL_M := 14.0             # ...from this far back
const COUNT_STEP_S := 0.8        # then the flagger counts 3, 2, 1
const COUNTDOWN_S := ROLL_S + 3 * COUNT_STEP_S
const FINISH_SLOW_M := 45.0      # slow-mo once the leader is this close to the line
const SLOW_MO := 0.3
const FINISH_VIEW_M := 70.0      # finish-line camera
const GAP_BAR_RANGE_S := 1.0     # gap bar: full deflection at 1 s
const MARK_COLOR := Color(0.02, 0.02, 0.02, 0.55)
const CAPTION_YELLOW := Color(1.0, 0.86, 0.18)
const CAPTION_BG := Color(0.0, 0.0, 0.0, 0.72)
const REC_RED := Color(1.0, 0.16, 0.12)
const SPLIT_SHOW_S := 3.0        # s of playback a split caption stays up
const VIEWFINDER_INSET := 8.0     # px from the screen edge to the corner brackets
const VIEWFINDER_ARM := 44.0      # px each bracket arm
const LOCATION_NAMES := {"coast": "PACIFIC COAST HWY", "canyon": "LATIGO CANYON RD",
	"mountain": "ANGELES CREST HWY"}
const CLOCK_START_S := 23 * 3600 + 51 * 60 + 40   # the tape's clock at the green: 23:51:40

signal finished_viewing     # embedded mode: player pressed Continue after the finish

enum CamMode { OVERVIEW, CHASE }
const CAM_NAMES := ["Overview", "Chase"]

# Set these before adding the viewer to the tree (game.gd does); defaults = standalone
var replay_path := REPLAY_PATH
var embedded := false       # inside the game: Continue button, broadcast cameras

var replay: Dictionary = {}
var samples: Dictionary = {}
var corners: Array = []
var driver = null          # Dictionary, or null for a theoretical-limit run
var lap_time := 0.0        # finish time, or the crash time for a DNF
var dnf := false
var ghost = null           # Dictionary (opponent: name, lap_time, dnf, samples), or null

var t := 0.0              # playback time (s)
var idx := 0              # current sample index (t is between idx and idx + 1)
var playing := true
var speed_i := 2          # index into SPEEDS (1x)
var cam_mode: int = CamMode.CHASE

var camera: Camera2D
var car: Node2D            # CarSprite
var overlay: CanvasLayer   # follows the camera; not darkened by the night
var lights := {}           # "car"/"ghost" -> headlight PointLight2D; "car_tail" -> taillight
var ghost_s: Array = []    # ghost distance along the road per sample
var countdown := 0.0       # start lights: > 0 while counting down (playback held at t = 0)
var prev_t := 0.0          # for events that fire once when t crosses a time
var crash_age := -1.0      # real seconds since Faba crashed (< 0: hasn't)
var shake := 0.0           # camera shake, decays
var marks: Node2D          # tire marks (world)
var puff: Texture2D        # soft round particle (sparks, smoke)
var mark_lines := [null, null]   # the Line2D each rear tire is drawing, or null
var track_center := Vector2.ZERO
var track_size := Vector2.ONE
var hud := {}             # name -> HUD node
var marker: Node2D
var ghost_car: Node2D
var ghost_marker: Node2D
var ghost_tag: Label      # "CRASHED" over a ghost that went off
var location := "canyon"  # replay "location" (older replays: canyon)
var road_pts := PackedVector2Array()
var end_time := 0.0       # replay ends: Faba's finish/crash, or the ghost's finish if later
var finish_cut := false   # the finish-line camera has taken over (single chase)
var crash_cut := false    # the crash camera has taken over
var pane := ""            # "" = the full viewer; "them" / "faba" = one half of the
                          # split screen: the world only, following that car, its
                          # clock driven by the full viewer (set before adding)
var panes := []           # full viewer: the two pane viewers [them, faba]
var pane_boxes := []      # ...their SubViewportContainers
var pane_tags := []       # ...and a name + speed tag on each
var flagger: Node2D


# ------------------------------------------------------------------ setup

func _ready() -> void:
	RenderingServer.set_default_clear_color(NIGHT_SKY)
	if pane != "":                 # one half of the split screen: the world only
		if load_replay(replay_path) == "":
			build_world()
			set_cam_mode(CamMode.CHASE)
		return
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--replay="):
			replay_path = a.trim_prefix("--replay=")
	var err := load_replay(replay_path)
	if err != "":
		show_message(err)
		return
	build_world()
	build_hud()
	set_cam_mode(CamMode.CHASE)                 # Spire: chase by default, game and viewer
	countdown = COUNTDOWN_S
	for a in args:
		if a == "--selftest" or a.begins_with("--shots="):
			countdown = 0.0                         # stills and checks start racing at once
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
	dnf = bool(data.get("dnf", false))     # optional, like ghost
	ghost = data.get("ghost")
	location = str(data.get("location", "canyon")) if data.get("location") != null else "canyon"
	# The race is over when the winner crosses (Spire): the other car stops
	# where he is. A crash ends it at the crash (Faba's) or at Faba's finish.
	end_time = lap_time
	if ghost != null and not dnf and not bool(ghost["dnf"]):
		end_time = minf(lap_time, float(ghost["lap_time"]))
	if ghost != null:
		ghost_s = ghost["samples"].get("s", [])
		if ghost_s.is_empty():                 # older replays: distance from the points
			var gx: Array = ghost["samples"]["x"]
			var gy: Array = ghost["samples"]["y"]
			ghost_s = [0.0]
			for i in range(1, gx.size()):
				ghost_s.append(ghost_s[-1] + Vector2(gx[i] - gx[i - 1], gy[i] - gy[i - 1]).length())
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

	road_pts = pts
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

	# No corner labels (Spire): the severity-colored curbs say it

	# Start and finish lines across the road
	add_child(cross_line(0))
	add_child(cross_line(centerline.size() - 1))


## The race world: the place, the road, both cars, their lights, a camera.
## The full viewer has one (Overview, single chase); each split-screen pane
## has its own copy in its own viewport.
func build_world() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 1
	overlay.follow_viewport_enabled = true      # moves with the camera like the world
	add_child(overlay)
	build_track()
	build_night()
	build_car()
	build_camera()
	# Split screen: each half shows only its own car (Spire: no ghosts)
	if pane == "them":
		hide_car(car, ["car", "car_tail", "car_hazard"])
		marks.visible = false                   # Faba's tire marks
	elif pane == "faba" and ghost != null:
		hide_car(ghost_car, ["ghost", "ghost_hazard"])
		ghost_tag.modulate.a = 0.0


## Take a car out of this view: the sprite and its lights (it still moves, unseen).
func hide_car(c: Node2D, light_keys: Array) -> void:
	c.modulate.a = 0.0
	for k in light_keys:
		if lights.has(k):
			lights[k].enabled = false


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


## Ring around a car that stays the same size on screen (visible when zoomed out).
func make_ring(color: Color) -> Node2D:
	var node := Node2D.new()
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 33:
		pts.append(Vector2.from_angle(TAU * i / 32.0) * MARKER_RADIUS_PX)
	ring.points = pts
	ring.width = 3.0
	ring.default_color = color
	node.add_child(ring)
	return node


func make_car(car_name: String) -> Node2D:
	var c: Node2D = CarSprite.new()
	c.profile = CarSprite.profile_for(car_name)
	c.px_per_m = PX_PER_M
	return c


## Night: moonlight over everything in the world layer, the road's place
## around it (widgets/scenery.gd), and somewhere for the tire marks to go.
func build_night() -> void:
	var dark := CanvasModulate.new()
	dark.color = MOONLIGHT
	add_child(dark)

	var land: Node2D = SceneryScript.new()
	land.points = road_pts
	land.corners = corners
	land.px_per_m = PX_PER_M
	land.location = location
	land.glow_layer = overlay              # city lights glow through the night
	land.z_index = -20
	add_child(land)

	marks = Node2D.new()
	marks.z_index = 1
	add_child(marks)


## A headlight cone texture: light starts at the center and shines to +x
## (a 512 px square, so the light node sits exactly on the car's nose).
func cone_texture() -> ImageTexture:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0, y - n / 2.0)
			var r := d.length() / (n / 2.0)
			var a := 0.0
			if r < 1.0 and d.x > 0.0:
				var ang := absf(d.angle())
				a = smoothstep(HEADLIGHT_HALF_ANGLE, HEADLIGHT_HALF_ANGLE * 0.55, ang) * pow(1.0 - r, 1.4)
			a = maxf(a, 0.35 * pow(maxf(1.0 - r * 7.0, 0.0), 2.0))   # a little spill around the nose
			img.set_pixel(x, y, Color(a, a, a, a))
	return ImageTexture.create_from_image(img)


func glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func make_headlight(cone: Texture2D, energy: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = cone
	l.texture_scale = HEADLIGHT_RANGE_M * PX_PER_M / 256.0
	l.color = HEADLIGHT_COLOR
	l.energy = energy
	add_child(l)
	return l


func build_car() -> void:
	var cone := cone_texture()
	var glow := glow_texture()
	puff = glow
	# The ghost first, underneath: when the cars overlap, Faba's stays on top
	if ghost != null:
		ghost_car = make_car(str(ghost["car"]))
		ghost_car.z_index = 8
		overlay.add_child(ghost_car)
		ghost_marker = make_ring(GHOST_MARKER_COLOR)
		ghost_marker.z_index = 9
		overlay.add_child(ghost_marker)
		ghost_tag = Label.new()
		ghost_tag.text = "CRASHED"
		ghost_tag.add_theme_font_override("font", RACING_FONT)
		ghost_tag.add_theme_font_size_override("font_size", 36)
		ghost_tag.add_theme_color_override("font_color", LOSS_COLOR)
		ghost_tag.add_theme_color_override("font_outline_color", Color.BLACK)
		ghost_tag.add_theme_constant_override("outline_size", 10)
		ghost_tag.z_index = 21
		ghost_tag.visible = false
		overlay.add_child(ghost_tag)
		lights["ghost"] = make_headlight(cone, 0.9)

	car = make_car(str(replay["car"]["name"]))
	car.z_index = 10
	overlay.add_child(car)
	marker = make_ring(MARKER_COLOR)
	marker.z_index = 11
	overlay.add_child(marker)
	lights["car"] = make_headlight(cone, 1.15)
	var tail := PointLight2D.new()               # red glow on the road behind; flares when braking
	tail.texture = glow
	tail.texture_scale = 7.0 * PX_PER_M / 64.0
	tail.color = Color(1.0, 0.1, 0.08)
	tail.energy = 0.5
	add_child(tail)
	lights["car_tail"] = tail
	# Hazards for the roll-up (blink until the flagger drops the light)
	for who in ["car", "ghost"] if ghost != null else ["car"]:
		var hz := PointLight2D.new()
		hz.texture = glow
		hz.texture_scale = 9.0 * PX_PER_M / 64.0
		hz.color = HAZARD
		hz.energy = 0.0
		add_child(hz)
		lights[who + "_hazard"] = hz
	build_flagger(cone)


## The flagger: stands in the road just past the start line between the cars'
## noses, counts 3-2-1 with a flashlight, then steps back to the shoulder.
func build_flagger(cone: Texture2D) -> void:
	var centerline: Array = replay["track"]["centerline"]
	var a := to_world(centerline[0][0], centerline[0][1])
	var b := to_world(centerline[mini(12, centerline.size() - 1)][0], centerline[mini(12, centerline.size() - 1)][1])
	var ahead := (b - a).normalized()
	flagger = Node2D.new()
	flagger.position = a + ahead * 9.0 * PX_PER_M
	flagger.rotation = ahead.angle() + PI                  # facing the cars
	flagger.z_index = 12
	flagger.draw.connect(func():
		var s := PX_PER_M * 2.0                                # drawn big, like the cars, so he reads
		flagger.draw_circle(Vector2(0.15, 0.2) * s, 0.55 * s, Color(0, 0, 0, 0.4))   # shadow
		flagger.draw_circle(Vector2.ZERO, 0.5 * s, Color(0.12, 0.12, 0.14))          # shoulders
		flagger.draw_circle(Vector2.ZERO, 0.28 * s, Color(0.55, 0.42, 0.33))         # head
		flagger.draw_line(Vector2(0, 0.35) * s, Vector2(0.7, 0.55) * s, Color(0.12, 0.12, 0.14), 0.22 * s)
		flagger.draw_circle(Vector2(0.75, 0.55) * s, 0.12 * s, Color(1, 0.95, 0.8)))  # the flashlight
	overlay.add_child(flagger)
	var beam := make_headlight(cone, 0.0)
	beam.position = flagger.position
	beam.rotation = flagger.rotation
	beam.texture_scale = 24.0 * PX_PER_M / 256.0
	lights["flagger"] = beam


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


func racing_label(parent: Node, pos: Vector2, size: int, color := Color.WHITE) -> Label:
	var label := add_label(parent, pos, size, color)
	label.add_theme_font_override("font", RACING_FONT)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", maxi(4, size / 7))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 4)
	return label


## Camcorder on-screen display text (VT323, hard shadow, no outline).
func osd_label(parent: Node, pos: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_override("font", VT_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## A 2000s touge-video caption: white bold text in a black box, yellow edge.
func caption(parent: Node, pos: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.98, 0.98, 0.95))
	var box := StyleBoxFlat.new()
	box.bg_color = CAPTION_BG
	box.border_width_left = 6
	box.border_color = CAPTION_YELLOW
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 2
	box.content_margin_bottom = 4
	label.add_theme_stylebox_override("normal", box)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2                       # above the overlay (cars, labels)
	add_child(layer)
	build_panes(layer)                    # first: everything else draws over them

	# Top: the tape. REC + camcorder clock, the race caption, the lap clock
	var top := ColorRect.new()
	top.color = Color(0.0, 0.0, 0.0, 0.55)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)
	hud["top"] = top
	hud["rec"] = osd_label(top, Vector2(24, 18), 40, REC_RED)
	hud["rec"].text = "* REC"
	hud["stamp"] = osd_label(top, Vector2(0, 18), 34, Color(0.95, 0.95, 0.9))
	hud["caption"] = caption(top, Vector2(24, 70), 26)
	var place: String = LOCATION_NAMES.get(location, "CANYON ROAD")
	hud["caption"].text = "%s  //  %s" % [place, ("FABA vs %s" % ghost_name()) if ghost != null else "FABA"]
	hud["clock"] = racing_label(top, Vector2(24, 112), 54, CAPTION_YELLOW)
	hud["status"] = osd_label(top, Vector2(0, 128), 30, Color(0.95, 0.95, 0.9))

	# Bottom: camera + playback buttons, then the dash
	var bottom := ColorRect.new()
	bottom.color = Color(0.05, 0.03, 0.035, 1.0)
	layer.add_child(bottom)
	hud["bottom"] = bottom

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	bottom.add_child(buttons)
	hud["buttons"] = buttons
	hud["cam_buttons"] = []
	for i in CAM_NAMES.size():
		var b := Button.new()
		b.text = CAM_NAMES[i].to_upper()
		b.theme_type_variation = "OsdButton"            # camcorder menu: white box, inverted when on
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(set_cam_mode.bind(i))
		buttons.add_child(b)
		hud["cam_buttons"].append(b)
	var play := Button.new()
	play.theme_type_variation = "OsdButton"
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(toggle_play)
	buttons.add_child(play)
	hud["play"] = play
	var speed := Button.new()
	speed.theme_type_variation = "OsdButton"
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

	hud["gear"] = racing_label(dash, Vector2(556, 18), 76, Color(1.0, 0.85, 0.3))
	hud["gear_caption"] = add_label(dash, Vector2(552, 104), 16, Color(0.6, 0.61, 0.66))
	hud["gear_caption"].text = "GEAR"
	hud["brake"] = add_bar(dash, Vector2(BRAKE_X, 70), Vector2(30, PEDAL_H), Color(0.93, 0.17, 0.24))
	hud["throttle"] = add_bar(dash, Vector2(THROTTLE_X, 70), Vector2(30, PEDAL_H), Color(0.3, 0.8, 0.4))

	hud["banner"] = caption(layer, Vector2.ZERO, 40)
	hud["banner_gap"] = racing_label(layer, Vector2.ZERO, 96, CAPTION_YELLOW)
	hud["mistake"] = caption(layer, Vector2.ZERO, 26)
	hud["split"] = caption(layer, Vector2.ZERO, 30)      # lower third: who won the last section, why
	hud["count"] = racing_label(layer, Vector2.ZERO, 150, CAPTION_YELLOW)   # 3, 2, 1, GO
	build_tower(layer)
	build_gap_bar(layer)
	var tape := CanvasLayer.new()          # the VHS look over everything, under nothing
	tape.layer = 50
	add_child(tape)
	var vhs := ColorRect.new()
	vhs.set_anchors_preset(Control.PRESET_FULL_RECT)
	vhs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = VhsShader
	vhs.material = mat
	var finder := Control.new()
	finder.set_anchors_preset(Control.PRESET_FULL_RECT)
	finder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	finder.draw.connect(draw_viewfinder.bind(finder))
	finder.resized.connect(finder.queue_redraw)
	tape.add_child(finder)
	tape.add_child(vhs)
	var flash := ColorRect.new()            # finish flash, full screen
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(flash)
	hud["flash"] = flash
	if embedded:
		var cont := Button.new()
		cont.text = "KEEP GOING >"
		cont.theme_type_variation = "OsdBigButton"
		cont.visible = false
		cont.pressed.connect(func(): finished_viewing.emit())
		layer.add_child(cont)
		hud["continue"] = cont


## Split caption (replay "splits", sim/breakdown.py): once BOTH cars are
## through a corner, who took time in that section and why, e.g.
## "R3 90  //  ZED +0.18  //  ACCELERATION". Not for the run to the line
## (the finish has its own result).
func update_split(vp: Vector2) -> void:
	var label: Label = hud["split"]
	label.visible = false
	var splits = replay.get("splits")
	if not splits is Array or ghost == null or t >= end_time:   # the result takes over at the end
		return
	for sp: Dictionary in splits:
		var at := maxf(float(sp["t_me"]), float(sp["t_them"]))
		if sp["name"] == "FINISH" or t < at or t >= at + SPLIT_SHOW_S:
			continue
		var gain := float(sp["gain"])
		var who := "FABA" if gain > 0.0 else ghost_name().to_upper()
		var line := "DEAD EVEN" if absf(gain) < 0.005 else "%s +%.2f  //  %s" % [
			who, absf(gain), str(Voice.CAUSE_TAGS.get(sp["top_cause"], sp["top_cause"])).to_upper()]
		label.text = "%s  //  %s" % [str(sp["name"]).to_upper(), line]
		label.reset_size()
		label.position = Vector2((vp.x - label.size.x) / 2.0, vp.y - BOTTOM_PX - label.size.y - 70.0)
		label.visible = true


## Camcorder viewfinder: white corner brackets around the whole frame.
func draw_viewfinder(finder: Control) -> void:
	var r := Rect2(Vector2.ZERO, finder.size).grow(-VIEWFINDER_INSET)
	var col := Color(0.95, 0.95, 0.9, 0.75)
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var inward := (r.get_center() - corner).sign()
		finder.draw_line(corner, corner + Vector2(inward.x * VIEWFINDER_ARM, 0), col, 3.0)
		finder.draw_line(corner, corner + Vector2(0, inward.y * VIEWFINDER_ARM), col, 3.0)


## Split screen (Chase with an opponent): two panes side by side, him on the
## left and Faba on the right, each a viewer in "pane" mode with its own copy
## of the world and a chase camera on its car. Name + speed tag at the bottom.
func build_panes(layer: CanvasLayer) -> void:
	if ghost == null:
		return
	for who in ["them", "faba"]:
		var box := SubViewportContainer.new()
		box.stretch = true
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.visible = false
		layer.add_child(box)
		var sv := SubViewport.new()
		box.add_child(sv)
		var v: Node2D = get_script().new()
		v.replay_path = replay_path
		v.embedded = embedded
		v.pane = who
		sv.add_child(v)
		panes.append(v)
		pane_boxes.append(box)
		pane_tags.append(osd_label(layer, Vector2.ZERO, 32,
			GHOST_MARKER_COLOR if who == "them" else MARKER_COLOR))


## Lay out the panes in the view area and update their tags.
func update_panes(vp: Vector2) -> void:
	var split := is_split()
	var area := view_area()
	var half := (area.size.x - PANE_GAP_PX) / 2.0
	for i in pane_boxes.size():
		var box: SubViewportContainer = pane_boxes[i]
		box.visible = split
		box.position = Vector2(i * (half + PANE_GAP_PX), area.position.y)
		box.size = Vector2(half, area.size.y)
		var tag: Label = pane_tags[i]
		tag.visible = split
		var kmh := ghost_speed_at(t) * 3.6 if i == 0 else value_at("v") * 3.6
		tag.text = "%s  %d KM/H" % [ghost_name() if i == 0 else "FABA", roundi(kmh)]
		tag.reset_size()
		tag.position = Vector2(box.position.x + 14 if i == 0 else vp.x - tag.size.x - 14,
			area.end.y - tag.size.y - 10)


## The ghost's speed (m/s): its replay has distance, not speed, so take the
## slope of s(t) over 0.2 s.
func ghost_speed_at(tt: float) -> float:
	if bool(ghost["dnf"]) and tt >= float(ghost["lap_time"]):
		return 0.0
	return (ghost_s_at(tt + 0.1) - ghost_s_at(maxf(tt - 0.1, 0.0))) / (tt + 0.1 - maxf(tt - 0.1, 0.0))


## Broadcast gap tower: running order, live interval to the leader, OUT for a
## crash. Tape-era graphic: black box, yellow position numbers, digital gaps.
func build_tower(layer: CanvasLayer) -> void:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CAPTION_BG
	style.border_width_top = 4
	style.border_color = CAPTION_YELLOW
	style.content_margin_left = 12
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var rows := []
	for i in 2 if ghost != null else 1:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		var pos := racing_label(row, Vector2.ZERO, 28, CAPTION_YELLOW)
		pos.custom_minimum_size.x = 24
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(8, 26)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		var name := osd_label(row, Vector2.ZERO, 34, Color.WHITE)
		name.custom_minimum_size.x = 120
		var gap := osd_label(row, Vector2.ZERO, 34, CAPTION_YELLOW)
		gap.custom_minimum_size.x = 96
		gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rows.append({"pos": pos, "chip": chip, "name": name, "gap": gap})
	hud["tower"] = box
	hud["tower_rows"] = rows


## Live gap bar (close races): the needle leans toward whoever's ahead, full
## deflection at GAP_BAR_RANGE_S; the interval in the middle.
func build_gap_bar(layer: CanvasLayer) -> void:
	if ghost == null:
		return
	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size = Vector2(300, 46)
	bar.draw.connect(func():
		var w := bar.size.x
		var h := 18.0
		var y := 4.0
		bar.draw_rect(Rect2(0, y, w, h), CAPTION_BG)
		var lead: float = bar.get_meta("lead", 0.0)        # + = Faba ahead (s)
		var f := clampf(lead / GAP_BAR_RANGE_S, -1.0, 1.0)
		var mid := w / 2.0
		var col := MARKER_COLOR if f >= 0.0 else GHOST_MARKER_COLOR
		bar.draw_rect(Rect2(mid, y, -f * mid, h), col)     # Faba leads -> fills to the left
		bar.draw_line(Vector2(mid, 0), Vector2(mid, y + h + 4), Color.WHITE, 2.0)
		bar.draw_rect(Rect2(0, y, w, h), CAPTION_YELLOW, false, 2.0)
		bar.draw_string(VT_FONT, Vector2(4, y + h + 22), "FABA", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, MARKER_COLOR)
		bar.draw_string(VT_FONT, Vector2(w - 90, y + h + 22), ghost_name().left(8),
			HORIZONTAL_ALIGNMENT_RIGHT, 86, 24, GHOST_MARKER_COLOR))
	layer.add_child(bar)
	hud["gap_bar"] = bar
	hud["gap_text"] = osd_label(layer, Vector2.ZERO, 30, Color.WHITE)


func update_tower(vp: Vector2) -> void:
	var box: PanelContainer = hud["tower"]
	box.visible = t < end_time                 # the finish banner takes over at the end
	box.reset_size()
	box.position = Vector2(18, TOP_BAR_PX + 14)
	var entries := [{"name": "FABA", "color": MARKER_COLOR, "s": value_at("s"),
		"out": dnf and t >= lap_time, "ss": samples["s"], "ts": samples["t"]}]
	if ghost != null:
		entries.append({"name": ghost_name(), "color": GHOST_MARKER_COLOR, "s": ghost_s_at(t),
			"out": bool(ghost["dnf"]) and t >= float(ghost["lap_time"]),
			"ss": ghost_s, "ts": ghost["samples"]["t"]})
	# Running order: whoever's further down the road; a crashed car drops to the back
	entries.sort_custom(func(a, b): return (not a["out"] and b["out"]) \
		or (a["out"] == b["out"] and float(a["s"]) > float(b["s"])))
	var rows: Array = hud["tower_rows"]
	for i in rows.size():
		var e: Dictionary = entries[i]
		var row: Dictionary = rows[i]
		row["pos"].text = str(i + 1)
		row["chip"].color = e["color"]
		row["name"].text = e["name"]
		if e["out"]:
			row["gap"].text = "OUT"
			row["gap"].add_theme_color_override("font_color", LOSS_COLOR)
		elif i == 0:
			row["gap"].text = "LEADER" if entries.size() > 1 else ""
			row["gap"].add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
		else:
			# Interval: how long ago the leader passed the spot where this car is now
			var lead: Dictionary = entries[0]
			var passed := time_at(lead["ss"], lead["ts"], float(e["s"]))
			row["gap"].text = "+%.2f" % maxf(t - passed, 0.0)
			row["gap"].add_theme_color_override("font_color", CAPTION_YELLOW)
	# Gap bar: + when Faba leads
	if hud.has("gap_bar"):
		var bar: Control = hud["gap_bar"]
		var lead_s := 0.0
		var both_running: bool = not entries[0]["out"] and not entries[entries.size() - 1]["out"]
		if entries.size() > 1 and both_running:
			var trail: Dictionary = entries[1]
			var lead_e: Dictionary = entries[0]
			lead_s = maxf(t - time_at(lead_e["ss"], lead_e["ts"], float(trail["s"])), 0.0)
			if lead_e["name"] != "FABA":
				lead_s = -lead_s
		bar.set_meta("lead", lead_s)
		bar.visible = t < end_time and countdown <= 0.0 and both_running
		bar.position = Vector2(vp.x - bar.size.x - 18, TOP_BAR_PX + 14)
		bar.queue_redraw()
		var gt: Label = hud["gap_text"]
		gt.visible = bar.visible
		gt.text = "%+.2f" % lead_s
		gt.reset_size()
		gt.position = Vector2(bar.position.x + (bar.size.x - gt.size.x) / 2.0, TOP_BAR_PX + 40)


## Time a car reached distance s, from its (monotonic) s and t samples.
func time_at(ss: Array, ts: Array, s_target: float) -> float:
	var i := clampi(ss.bsearch(s_target) - 1, 0, ss.size() - 2)
	var s0 := float(ss[i])
	var s1 := float(ss[i + 1])
	var f := 0.0 if s1 <= s0 else clampf((s_target - s0) / (s1 - s0), 0.0, 1.0)
	return lerpf(float(ts[i]), float(ts[i + 1]), f)


func ghost_s_at(tt: float) -> float:
	var ts: Array = ghost["samples"]["t"]
	var i := clampi(ts.bsearch(tt, false) - 1, 0, ts.size() - 2)
	var t0 := float(ts[i])
	var t1 := float(ts[i + 1])
	var f := 0.0 if t1 <= t0 else clampf((tt - t0) / (t1 - t0), 0.0, 1.0)
	return lerpf(float(ghost_s[i]), float(ghost_s[i + 1]), f)


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

	hud["clock"].text = "%.2f" % t
	var push_text := "THEORETICAL LIMIT"
	if driver != null:
		push_text = "%s PUSH" % str(driver["push"]).replace("_", " ").to_upper()
	hud["status"].text = push_text
	hud["status"].reset_size()
	hud["status"].position.x = vp.x - hud["status"].size.x - 24
	# Camcorder: blinking REC, the tape's clock running with the race
	hud["rec"].visible = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
	var secs := CLOCK_START_S + int(t)
	hud["stamp"].text = "OCT 04 2026  %02d:%02d:%02d" % [secs / 3600 % 24, secs / 60 % 60, secs % 60]
	hud["stamp"].reset_size()
	hud["stamp"].position.x = vp.x - hud["stamp"].size.x - 24
	update_tower(vp)
	update_intro(vp)
	update_panes(vp)

	for i in hud["cam_buttons"].size():
		var b: Button = hud["cam_buttons"][i]
		b.theme_type_variation = "OsdOnButton" if i == cam_mode else "OsdButton"
	hud["play"].text = "PAUSE" if playing and t < end_time else "PLAY"
	hud["speed_btn"].text = "%sx" % str(SPEEDS[speed_i])

	var gear := int(samples["gear"][idx])
	hud["gear"].text = "-" if gear == 0 else str(gear)
	var alive := 1.0 if crash_age < 0.0 else maxf(1.0 - crash_age / 0.6, 0.0)   # stalls after a crash
	hud["tach"].value = value_at("rpm") * alive
	hud["speedo"].value = value_at("v") * 3.6 * alive

	var temp := value_at("brake_temp")
	var fade := float(replay["car"]["pad_fade_temp"])
	hud["temp"].text = "FRONT ROTOR %d C%s" % [int(temp), "   FADING" if temp > fade else ""]
	hud["temp"].add_theme_color_override("font_color", Color(1, 0.35, 0.3) if temp > fade else Color(0.8, 0.8, 0.82))
	set_pedal(hud["throttle"], value_at("throttle") * alive, Vector2(THROTTLE_X, 70))
	set_pedal(hud["brake"], value_at("brake"), Vector2(BRAKE_X, 70))

	# Finish (or crash) caption, the gap big, and Continue
	var banner: Label = hud["banner"]
	var over := t >= end_time
	banner.visible = over
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var result := banner_result()
	banner.text = result["text"]
	banner.add_theme_color_override("font_color", result["color"])
	banner.reset_size()
	banner.position = Vector2((vp.x - banner.size.x) / 2, TOP_BAR_PX + 30)
	var big: Label = hud["banner_gap"]
	big.visible = over and result["gap"] != ""
	big.text = result["gap"]
	big.reset_size()
	big.position = Vector2((vp.x - big.size.x) / 2, TOP_BAR_PX + 40 + banner.size.y)
	if hud.has("continue"):
		var cont: Button = hud["continue"]
		cont.visible = over
		cont.reset_size()
		cont.size.x = vp.x - 120
		cont.position = Vector2(60, TOP_BAR_PX + 60 + banner.size.y + big.size.y)

	update_split(vp)

	# Mistake callout: from the apex of a mistaken corner until shortly after it
	var mistake: Label = hud["mistake"]
	mistake.visible = false
	if driver != null and t < lap_time:
		var s_now := value_at("s")
		for c in driver["corners"]:
			var s0 := float(c["s_start"])
			var s1 := float(c["s_end"])
			if c["mistake"] and s_now >= (s0 + s1) / 2.0 and s_now <= s1 + 40.0:
				mistake.text = "FABA RUNS WIDE AT %s" % str(c["text"]).to_upper()
				mistake.reset_size()
				mistake.position = Vector2((vp.x - mistake.size.x) / 2, TOP_BAR_PX + 120)
				mistake.visible = true


func ghost_name() -> String:
	return str(ghost["name"]).to_upper()


## End-of-replay caption. Same rule as the bridge's race result: a DNF never
## wins, and if both cars crash nobody wins (no contest). "gap" is the big
## number under it ("" when there isn't one).
func banner_result() -> Dictionary:
	var head := "CRASHED AT %s" % str(replay.get("crash_corner", "")).to_upper() if dnf \
		else "FINISH  %.2f" % lap_time
	if ghost == null:
		return {"text": head, "color": LOSS_COLOR if dnf else Color.WHITE, "gap": ""}
	var ghost_dnf := bool(ghost["dnf"])
	var ghost_time := float(ghost["lap_time"])
	var line := ""
	var gap := ""
	var color := LOSS_COLOR
	if dnf and ghost_dnf:
		line = "NO CONTEST: %s CRASHED TOO" % ghost_name()
		color = CAPTION_YELLOW
	elif dnf:
		line = "%s WINS" % ghost_name()
	elif ghost_dnf:
		line = "BEAT %s: HE CRASHED AT %s" % [ghost_name(), str(ghost["crash_corner"]).to_upper()]
		color = WIN_COLOR
	else:
		var won := lap_time < ghost_time
		line = "%s %s" % ["BEAT" if won else "LOST TO", ghost_name()]
		gap = "%s%.2f" % ["-" if won else "+", absf(lap_time - ghost_time)]
		color = WIN_COLOR if won else LOSS_COLOR
		if not won:                       # the replay stopped at HIS line: his time on top
			head = "%s  %.2f" % [ghost_name(), ghost_time]
	return {"text": head + "\n" + line, "color": color, "gap": gap}


## Intro: the roll-up with hazards, then the flagger's 3-2-1 and GO.
func update_intro(vp: Vector2) -> void:
	var elapsed := COUNTDOWN_S - countdown
	if hud.has("count"):
		var count: Label = hud["count"]
		var n := 3 - int((elapsed - ROLL_S) / COUNT_STEP_S)
		count.visible = (countdown > 0.0 and elapsed >= ROLL_S) or (countdown <= 0.0 and t < 0.6 and hud.has("intro_used"))
		count.text = "GO" if countdown <= 0.0 else str(clampi(n, 1, 3))
		count.reset_size()
		count.position = Vector2((vp.x - count.size.x) / 2.0, TOP_BAR_PX + 120)
	var blink := countdown > 0.0 and fmod(elapsed, 0.5) < 0.25
	for who in ["car", "ghost"]:
		if lights.has(who + "_hazard"):
			lights[who + "_hazard"].energy = 1.3 if blink else 0.0
	# Flashlight: up on each count, a big sweep down on GO, then off
	var beam: PointLight2D = lights["flagger"]
	var k := fmod(elapsed - ROLL_S, COUNT_STEP_S) / COUNT_STEP_S if elapsed >= ROLL_S else 1.0
	beam.energy = (2.4 * (1.0 - k) if countdown > 0.0 and elapsed >= ROLL_S else 0.0) \
		+ (3.0 * maxf(1.0 - t / 0.4, 0.0) if countdown <= 0.0 and t < 0.4 else 0.0)
	# After the start he walks off to the shoulder
	if countdown <= 0.0 and t > 0.5:
		flagger.visible = false
		beam.energy = 0.0


func set_pedal(fill: ColorRect, amount: float, base: Vector2) -> void:
	# Vertical bar that fills from the bottom
	var h := PEDAL_H * clampf(amount, 0.0, 1.0)
	fill.size = Vector2(30, h)
	fill.position = Vector2(base.x, base.y + PEDAL_H - h)


func toggle_play() -> void:
	if t >= end_time:
		restart()
	else:
		playing = not playing


# ------------------------------------------------------------------ playback

func _process(delta: float) -> void:
	if samples.is_empty() or camera == null:
		return
	if pane == "":                         # a pane's clock is set by the full viewer
		if countdown > 0.0:                # intro: the clock waits for the flagger
			hud["intro_used"] = true
			if playing:
				countdown = maxf(countdown - delta, 0.0)
		elif playing:
			t = minf(t + delta * SPEEDS[speed_i] * (SLOW_MO if finish_slow() else 1.0), end_time)
		sync_panes()
	update_car()
	fire_events(delta)
	lay_tire_marks()
	update_camera(delta, false)
	shake = maxf(shake - delta * 1.6, 0.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 16.0 * shake * shake
	if pane == "":
		update_hud()
	else:
		update_intro(get_viewport_rect().size)  # hazards + the flagger's light
	prev_t = t


## The panes run on the full viewer's clock (they're processed after it).
## In split screen the full viewer's own world is hidden.
func sync_panes() -> void:
	var split := is_split()
	visible = not split
	overlay.visible = not split
	for p in panes:
		p.t = t
		p.countdown = countdown
		p.playing = playing


## Jump playback to tt (stills, tests): move the cars, snap every camera.
func jump_to(tt: float) -> void:
	t = tt
	finish_cut = false
	update_car()
	update_camera(0.0, true)
	for p in panes:
		p.countdown = countdown
		p.jump_to(tt)


## Finish slow-mo: from when the leader is FINISH_SLOW_M from the line until
## both are across (or the replay ends). Not for crashes.
func finish_slow() -> bool:
	if dnf or t >= end_time:
		return false
	var length := float(replay["track"]["length"])
	var lead_s := value_at("s")
	if ghost != null and not bool(ghost["dnf"]):
		lead_s = maxf(lead_s, ghost_s_at(t))
	return lead_s >= length - FINISH_SLOW_M


## One-off moments: crashes (sparks, smoke, shake) and the finish flash.
func fire_events(delta: float) -> void:
	if dnf and t >= lap_time:
		if crash_age < 0.0:
			crash_age = 0.0
			if pane != "them":                  # not in his half: Faba isn't there
				crash_fx(car.position, car.rotation)
		else:
			crash_age += delta
	if ghost != null and bool(ghost["dnf"]):
		var gt := float(ghost["lap_time"])
		if prev_t < gt and t >= gt and pane != "faba":
			crash_fx(ghost_car.position, ghost_car.rotation)
	if not dnf and prev_t < end_time and t >= end_time and hud.has("flash"):   # the winner's line
		var flash: ColorRect = hud["flash"]
		flash.color.a = 0.7
		create_tween().tween_property(flash, "color:a", 0.0, 0.5)


func crash_fx(pos: Vector2, heading: float) -> void:
	shake = 1.0
	var sparks := CPUParticles2D.new()
	sparks.position = pos
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.amount = 70
	sparks.lifetime = 0.7
	sparks.direction = Vector2.from_angle(heading)
	sparks.spread = 70.0
	sparks.gravity = Vector2.ZERO
	sparks.initial_velocity_min = 60.0
	sparks.initial_velocity_max = 220.0
	sparks.damping_min = 120.0
	sparks.damping_max = 220.0
	sparks.texture = puff
	sparks.scale_amount_min = 0.03
	sparks.scale_amount_max = 0.07
	var hot := Gradient.new()
	hot.set_color(0, Color(1.0, 0.95, 0.6))
	hot.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	sparks.color_ramp = hot
	sparks.z_index = 30
	overlay.add_child(sparks)
	var smoke := CPUParticles2D.new()
	smoke.position = pos
	smoke.amount = 40
	smoke.lifetime = 3.0
	smoke.direction = Vector2.UP
	smoke.spread = 180.0
	smoke.gravity = Vector2.ZERO
	smoke.initial_velocity_min = 4.0
	smoke.initial_velocity_max = 18.0
	smoke.texture = puff
	smoke.scale_amount_min = 0.25
	smoke.scale_amount_max = 0.6
	var grow := Curve.new()                  # puffs swell as they drift
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.0))
	smoke.scale_amount_curve = grow
	var grey := Gradient.new()
	grey.set_color(0, Color(0.55, 0.55, 0.55, 0.55))
	grey.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	smoke.color_ramp = grey
	smoke.z_index = 29
	overlay.add_child(smoke)
	sparks.emitting = true
	smoke.emitting = true
	get_tree().create_timer(2.5).timeout.connect(func():
		if is_instance_valid(smoke):
			smoke.emitting = false)


## Black tire marks from Faba's rear tires while braking hard or running wide
## (after the apex of a mistaken corner).
func lay_tire_marks() -> void:
	var skid := playing and t > 0.0 and t < lap_time and value_at("brake") > 0.5
	if not skid and driver != null and t < lap_time:
		var s_now := value_at("s")
		for c in driver["corners"]:
			var s0 := float(c["s_start"])
			var s1 := float(c["s_end"])
			if c["mistake"] and s_now >= (s0 + s1) / 2.0 and s_now <= s1:
				skid = true
	var nose := Vector2.from_angle(car.rotation)
	for i in 2:
		if not skid:
			mark_lines[i] = null
			continue
		var side := -1.0 if i == 0 else 1.0
		var p := car.position - nose * 1.3 * PX_PER_M * CarSprite.VISUAL_SCALE \
			+ nose.orthogonal() * side * 0.7 * PX_PER_M * CarSprite.VISUAL_SCALE
		if mark_lines[i] == null:
			var line := Line2D.new()
			line.width = 0.35 * PX_PER_M * CarSprite.VISUAL_SCALE
			line.default_color = MARK_COLOR
			marks.add_child(line)
			mark_lines[i] = line
		var l: Line2D = mark_lines[i]
		if l.points.is_empty() or l.points[-1].distance_to(p) > 2.0:
			l.add_point(p)


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
	car.position -= Vector2.from_angle(car.rotation) * roll_back_px()   # intro: rolling up
	if crash_age >= 0.0:                              # spun into the trees
		car.rotation += 0.9 * clampf(crash_age / 0.5, 0.0, 1.0)
	var braking := value_at("brake") > 0.0
	car.braking = braking
	var nose := Vector2.from_angle(car.rotation)
	var front := car.position + nose * 2.6 * PX_PER_M
	var hl: PointLight2D = lights["car"]
	hl.position = front
	hl.rotation = car.rotation
	var tail: PointLight2D = lights["car_tail"]
	tail.position = car.position - nose * 3.4 * PX_PER_M
	tail.energy = 1.6 if braking else 0.45
	if lights.has("car_hazard"):
		lights["car_hazard"].position = car.position
	if ghost != null:
		update_ghost()


## Intro roll-up: how far behind the line the cars still are (px), easing in.
func roll_back_px() -> float:
	var elapsed := COUNTDOWN_S - countdown
	if countdown <= 0.0 or elapsed >= ROLL_S:
		return 0.0
	var f := elapsed / ROLL_S
	return ROLL_M * PX_PER_M * pow(1.0 - f, 2.0)


## The ghost has its own (coarser) time base, so look up its pose by time.
## Past its last sample it stays put: at the finish, or at the crash apex.
func update_ghost() -> void:
	var gs: Dictionary = ghost["samples"]
	var ts: Array = gs["t"]
	var i := clampi(ts.bsearch(t, false) - 1, 0, ts.size() - 2)
	var t0 := float(ts[i])
	var t1 := float(ts[i + 1])
	var f := 0.0 if t1 <= t0 else clampf((t - t0) / (t1 - t0), 0.0, 1.0)
	var h := lerp_angle(float(gs["heading"][i]), float(gs["heading"][i + 1]), f)
	var x := lerpf(float(gs["x"][i]), float(gs["x"][i + 1]), f)
	var y := lerpf(float(gs["y"][i]), float(gs["y"][i + 1]), f)
	ghost_car.position = to_world(x + sin(h) * LANE_OFFSET_M, y - cos(h) * LANE_OFFSET_M)
	ghost_car.rotation = -h
	ghost_car.position -= Vector2.from_angle(ghost_car.rotation) * roll_back_px()
	if lights.has("ghost_hazard"):
		lights["ghost_hazard"].position = ghost_car.position
	var ghost_out := bool(ghost["dnf"]) and t >= float(ghost["lap_time"])
	if ghost_out:
		ghost_car.rotation += 0.9 * clampf((t - float(ghost["lap_time"])) / 0.5, 0.0, 1.0)
	ghost_tag.visible = ghost_out
	var hl: PointLight2D = lights["ghost"]
	hl.position = ghost_car.position + Vector2.from_angle(ghost_car.rotation) * 2.6 * PX_PER_M
	hl.rotation = ghost_car.rotation


# ------------------------------------------------------------------ cameras

func set_cam_mode(mode: int) -> void:
	cam_mode = mode
	crash_cut = false
	update_camera(0.0, true)


func view_area() -> Rect2:
	## Screen area between the top bar and the bottom panel (a pane: all of it).
	var vp := get_viewport_rect().size
	if pane != "":
		return Rect2(Vector2.ZERO, vp)
	return Rect2(0, TOP_BAR_PX, vp.x, vp.y - TOP_BAR_PX - BOTTOM_PX)


## Split screen: Chase with an opponent shows two panes (him left, Faba right).
func is_split() -> bool:
	return pane == "" and cam_mode == CamMode.CHASE and not panes.is_empty()


func update_camera(delta: float, snap: bool) -> void:
	var vp := get_viewport_rect().size
	var area := view_area()
	# The car this camera follows: a pane's own car, else Faba
	var focus: Node2D = ghost_car if pane == "them" else car
	var focus_out: bool = (crash_age >= 0.0 if focus == car
		else (bool(ghost["dnf"]) and t >= float(ghost["lap_time"])))
	var target_pos := focus.position
	var target_zoom := area.size.x / (CHASE_VIEW_M * PX_PER_M)
	var target_rot := 0.0
	var cut := snap

	var length := float(replay["track"]["length"])
	if pane == "" and embedded and countdown > 0.0:
		# Intro: tight on the line, the cars rolling up and the flagger
		target_pos = flagger.position.lerp(car.position, 0.5)
		target_zoom = minf(area.size.x, area.size.y) / (40.0 * PX_PER_M)
	elif pane == "" and cam_mode == CamMode.CHASE and not dnf and (finish_slow() or (t >= lap_time and t <= end_time)):
		# Single chase (no opponent): one cut to the finish line, then hold
		if not finish_cut:
			finish_cut = true
			cut = true
		var centerline: Array = replay["track"]["centerline"]
		var fin: Array = centerline[centerline.size() - 1]
		target_pos = to_world(fin[0], fin[1])
		target_zoom = minf(area.size.x, area.size.y) / (FINISH_VIEW_M * PX_PER_M)
	elif cam_mode == CamMode.CHASE and focus_out and length > 0.0:
		# Crash cam: cut tight onto the wreck
		if not crash_cut:
			crash_cut = true
			cut = true
		target_zoom = minf(area.size.x, area.size.y) / (45.0 * PX_PER_M)
	elif cam_mode == CamMode.OVERVIEW:
		var margin := 120.0 * PX_PER_M                # room for labels outside the road
		target_zoom = minf(area.size.x / (track_size.x + margin), area.size.y / (track_size.y + margin))
		target_pos = track_center
	else:
		# Chase: the car always points up (the camera turns with it) and the
		# camera looks ahead so the car sits low on screen. A pane is half as
		# wide, so it shows fewer meters across (cars stay a readable size).
		var view_m := PANE_VIEW_M if pane != "" else CHASE_VIEW_M
		target_zoom = area.size.x / (view_m * PX_PER_M)
		target_rot = focus.rotation + PI / 2.0
		target_pos = focus.position + Vector2.from_angle(focus.rotation) * CHASE_LOOKAHEAD_M * PX_PER_M

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


## Keep the car markers and the CRASHED tag a constant size on screen
## (world size = screen size / zoom), and upright when the camera rotates.
func rescale_overlays() -> void:
	var inv := 1.0 / camera.zoom.x
	marker.position = car.position
	marker.scale = Vector2.ONE * inv
	marker.visible = cam_mode == CamMode.OVERVIEW
	if ghost != null:
		ghost_marker.position = ghost_car.position
		ghost_marker.scale = marker.scale
		ghost_marker.visible = marker.visible
		ghost_tag.scale = Vector2.ONE * LABEL_SCREEN_SCALE * inv
		ghost_tag.pivot_offset = ghost_tag.size / 2.0
		ghost_tag.rotation = camera.rotation
		ghost_tag.reset_size()
		# Centered just above the car on screen, whatever the camera's rotation
		var above := Vector2(0, -(MARKER_RADIUS_PX + 20.0) * inv).rotated(camera.rotation)
		ghost_tag.position = ghost_car.position + above - ghost_tag.size / 2.0


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if pane != "":
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			set_cam_mode(CamMode.OVERVIEW)
		KEY_2:
			set_cam_mode(CamMode.CHASE)
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
			if embedded and t >= end_time:
				finished_viewing.emit()


func restart() -> void:
	t = 0.0
	prev_t = 0.0
	idx = 0
	playing = true
	countdown = COUNTDOWN_S
	crash_age = -1.0
	finish_cut = false
	if flagger:
		flagger.visible = true
	crash_cut = false
	mark_lines = [null, null]
	for child in marks.get_children():
		child.queue_free()
	for p in panes:
		p.restart()


func show_message(text: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := add_label(layer, Vector2(40, 200), 28)
	label.text = text


# ------------------------------------------------------------------ self-test

## Headless check: step through the replay and every camera, print what
## the viewer sees, then quit. Run with:  godot --headless -- --selftest
func self_test() -> void:
	print("SELFTEST samples=%d lap_time=%.2f end=%.2f corners=%d location=%s" % [samples["t"].size(),
		lap_time, end_time, corners.size(), location])
	for check_t in [0.0, lap_time * 0.25, lap_time * 0.5, lap_time * 0.75, lap_time]:
		t = check_t
		update_car()
		for mode in [CamMode.OVERVIEW, CamMode.CHASE]:
			set_cam_mode(mode)
		update_hud()
		print("t=%7.2f s=%7.1f m  pos=(%7.1f, %7.1f) m  v=%5.1f km/h  gear=%d  cam=%d" % [
			t, value_at("s"), car.position.x / PX_PER_M, -car.position.y / PX_PER_M,
			value_at("v") * 3.6, int(samples["gear"][idx]), cam_mode])
		if ghost != null:
			print("          ghost pos=(%7.1f, %7.1f) m  crashed_tag=%s" % [
				ghost_car.position.x / PX_PER_M, -ghost_car.position.y / PX_PER_M, ghost_tag.visible])
	print("BANNER " + banner_result()["text"].replace("\n", " | "))
	print("SELFTEST OK")
	get_tree().quit()


## Save stills: every camera at a few moments in the run, then quit.
## Needs a real (or virtual) display, not --headless.
func take_screenshots(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	playing = false
	var moments := {"start": 2.0, "r3_entry": 24.0, "hairpin": 34.5, "finish": end_time}
	if driver != null:                          # also catch any mistake on camera
		for c in driver["corners"]:
			if c["mistake"]:
				moments["mistake_" + str(c["text"]).replace(" ", "_")] = time_at_s(float(c["s_end"]))
	for moment in moments:
		t = minf(float(moments[moment]), end_time)
		update_car()
		for mode in [CamMode.OVERVIEW, CamMode.CHASE]:
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
