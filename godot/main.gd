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
## Cameras: Chase (default) and Overview (the whole road, top-down 2D).
## Chase is 3D (widgets/chase3d.gd), filmed from a CAMERA CAR driving the road
## behind the car (camcar_*). With an opponent it's SPLIT SCREEN: him on the
## left, Faba on the right; without one, one pane fills the view. Each pane is
## a copy of this viewer in "pane" mode: it runs the same 2D world (hidden)
## to place its car and its camera car, and draws them in its own 3D world,
## its clock driven from here.
##
## Head-to-head replays carry the opponent as a "ghost" (pose samples on its own
## time base). A crashed car's run ends at its crash apex; from there it slides
## on off the road (crash_slide(), visual). The replay ends when the winner
## crosses, or at Faba's crash.
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
const RoadScript := preload("res://widgets/road.gd")
const CarSprite := preload("res://widgets/car_sprite.gd")
const RACING_FONT := preload("res://fonts/RacingSansOne-Regular.ttf")
const VT_FONT := preload("res://fonts/VT323-Regular.ttf")            # camcorder OSD
const BODY_FONT := preload("res://fonts/BarlowCondensed-Bold.ttf")
const SceneryScript := preload("res://widgets/scenery.gd")
const Chase3D := preload("res://widgets/chase3d.gd")
const SpeedBlur := preload("res://widgets/speed_blur.gdshader")
const CarAudio := preload("res://widgets/car_audio.gd")
const VhsShader := preload("res://widgets/vhs.gdshader")
const Voice := preload("res://voice.gd")
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const LABEL_SCREEN_SCALE := 0.5  # world labels (CRASHED tag): 36 px font drawn at ~18 px on screen
const MARKER_RADIUS_PX := 9.0    # car marker ring, constant size on screen
const TOP_BAR_PX := 196.0        # info bar height (screen px)
const BOTTOM_PX := 420.0         # camera buttons + dash height (screen px)
const CHASE_VIEW_M := 80.0       # meters across the screen (2D, while switching to the 3D chase)
const PANE_GAP_PX := 4.0         # the seam between the panes
const OPP_DASH_ALPHA := 0.72     # his mini gauges: smaller and see-through (Spire)

# Driving like a person, not a rail (Spire). VISUAL ONLY: the sim drives the
# centerline, and positions along the road (so every time and gap) are the
# sim's. These only move the car across its lane and turn its nose a little.
const WANDER_M := 0.22           # slow drift (grows with speed; a rookie wanders more)
# A 3 a.m. spotter run (Spire): both lanes are theirs. Out-in-out through
# every corner: the outside edge at entry, the inside at the apex, the outside
# again at the exit, then home near the middle on a long straight.
const LINE_SWING_M := 2.4        # a full out-in-out: this far each way (the road is 8 m)
const LINE_LEAD_M := 45.0        # moves out this far before a corner, back over as long after
# How much of the road a driver uses: his LINE SKILL, 0 (rookie) to 1. A
# rookie stays near his own lane and barely moves out for a corner; a good
# driver sits mid-road and uses edge to edge when the corner needs it.
const FABA_LINE_SKILL := 0.3     # Faba's still learning (driver training can raise it later)
const HOME_ROOKIE_M := 1.8       # straights: right lane, out of habit...
const HOME_PRO_M := 0.5          # ...or just right of the middle
const NEED_TIGHT_M := 20.0       # a corner this tight or tighter needs the whole swing...
const NEED_NONE_M := 160.0       # ...one this open needs none

const SLIP_RAD_PER_G := 0.09     # nose turned into the corner: ~5 deg per g of a = v^2 / r
const SWAY_MAX_DEG_S := 15.0     # selftest: the nose may turn back and forth this fast (rms)...
const WOBBLE_MAX_PX := 1.0       # ...and wobble across the shot this much (px/frame^2 rms)
const LINE_PAD_M := 80          # the smoothed tables start this far before the line (the roll-up, the camera car)
const LINE_EASE_M := 24.0        # a line change is blended over ~this far (an S-bend: no step across the road)
const BEND_EASE_M := 16.0        # a corner's curve eases in over ~this far (like a real road's transition)
const RUN_WIDE_M := 1.6          # a mistake: out toward the edge after the apex
const LANE_LIMIT_M := 3.1        # car's center: never off the asphalt (half the road is 4 m)
const WIDE_LIMIT_M := 3.7        # ...except running wide: wheels on the edge line
const G := 9.81
const V_SHAKE_REF := 40.0        # m/s (144 km/h): "fast", for the wander

# The CAMERA CAR (Spire, after the Topfoil Evo touge videos): the chase view is
# filmed from a second car driving the road behind the subject (in 3D,
# widgets/chase3d.gd: low, behind, only its HID headlights showing). A good
# driver in a matched car, but it can't quite keep up: it plans its braking
# early and corners a little slower, so the gap OPENS in the tight stuff and
# it reels the subject back in on the straights (more power). Its heading
# follows the road a beat late. Visual only: the race is the sim's.
# Tuned on real replays for a camera at road height (scratchpad prototype,
# then the selftest's CAMCAR line): the gap averages ~13-16 m, opens to ~20-24 m
# through the tight stuff, and the line of sight to the subject never leaves
# the road, even in a 15 m hairpin (in a hairpin the chord between two cars
# 26 m apart along it cuts inside the road's edge: so 24 m at most).
const CAMCAR_GAP_M := 11.0       # where it wants to sit behind the subject (two car lengths)...
const CAMCAR_MIN_GAP_M := 5.0    # ...never closer...
const CAMCAR_MAX_GAP_M := 24.0   # ...never further (he's a speck, and round a hairpin the hill's in the way)
const CAMCAR_STOP_M := 12.0      # ...and it stops this far short of a wreck...
const CAMCAR_BRAKE_HARD := 9.0   # ...standing on it (m/s^2) when the car ahead goes off
const CRASH_DECEL := 9.0         # m/s^2: a car going off sheds speed fast (dirt, brush, the hit)...
const OFF_ROAD_M := 3.5          # ...and ends up this far out past its line, over the edge
const CAMCAR_K_GAP := 0.6        # 1/s: extra speed per meter of gap error (how hard it chases)
const CAMCAR_GRIP_SHARE := 0.94  # corners at this share of the subject's own best cornering g...
const CAMCAR_GRIP_MIN := 0.65    # ...but never less (a run of fast sweepers, or a crash in the
                                 # first corner, never shows the subject's grip limit)
const CAMCAR_PLAN := 5.0         # m/s^2: how hard it PLANS to brake for a corner (early, gentle)
const CAMCAR_BRAKE := 7.0        # m/s^2: its hardest stop
const CAMCAR_ACCEL_MIN := 4.0    # m/s^2: its power, at least this...
const CAMCAR_ACCEL_SHARE := 1.05 # ...or this x the subject's best pull (a built car is still caught)
const CAMCAR_STEER := 3.5        # 1/s: its heading follows the road a beat late
const CAMCAR_LINE_SHARE := 0.85  # drives nearly the subject's line (a chase car follows his line)

# Spotters (Spire: a 3 a.m. run on public roads): a guy with a radio and a
# flashlight before each blind corner, waving the light when a car comes.
const SPOTTER_MAX_RADIUS_M := 50.0   # blind corners: the tight ones
const SPOTTERS_MAX := 4
const SPOTTER_BEFORE_M := 14.0       # stands this far before the corner...
const SPOTTER_OUT_M := 7.0           # ...on the outside, this far from the middle of the road
const SPOTTER_WAVE_M := 90.0         # waves the light when a car is this close, coming at him
const RADIO_SHOW_S := 1.6            # "SPOTTER: CLEAR" stays up this long
const RADIO_GREEN := Color(0.55, 1.0, 0.55)
const OPP_GAUGE_PX := 92.0
const OPP_BAR_PX := 36.0
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
var faba_parts: Array = []  # part ids on the DX for this race (the 3D chase shows its hood, wheels, springs)

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
var pane := ""            # "" = the full viewer; "them" / "faba" = one half of the
                          # split screen: the world only, following that car, its
                          # clock driven by the full viewer (set before adding)
var panes := []           # full viewer: the two pane viewers [them, faba]
var pane_boxes := []      # ...their SubViewportContainers
var pane_tags := []       # ...and a name + speed tag on each
var wander := {}          # "car" / "ghost" -> FastNoiseLite: each driver's own wander
var lines := {}           # "car" / "ghost" -> the smoothed racing line (build_lines)
var bend := PackedFloat32Array()   # the road's smoothed curvature (build_lines)
var spotters := []        # [{"s": distance along the road, "node": Node2D, "beam": PointLight2D, "aim": rad}]
var camcar := {"s": -CAMCAR_GAP_M, "v": 0.0, "yaw": 0.0, "t": 0.0}   # the camera car (chase view)
var camcar_grip := 0.76   # g: set at load from the subject's own cornering (CAMCAR_GRIP_SHARE)
var camcar_accel := CAMCAR_ACCEL_MIN
var flagger: Node2D
var land: Node2D           # the 2D scenery (the 3D chase reuses its coastline / drop-off)
var chase: Node3D          # a pane's 3D world (widgets/chase3d.gd)
var audio := {}            # full viewer: "car" / "ghost" -> CarAudio (each engine, live)
var last_count := 99       # the count we last beeped (3, 2, 1, 0 = GO)
var last_radio := -1       # the spotter whose call we last played
var shifts := {}           # "car" / "ghost" -> downshifts: [{"t0", "t1", "pops": [t...]}] (build_shifts)
var busted := false        # the cops (game.gd): red and blue in the chase at the end, a siren
var sore_loser := false    # jorge mode (game.gd): after Faba wins, he leans on his horn...
var next_honk := 0.0       # ...again at this real time (s)


# ------------------------------------------------------------------ setup

func _ready() -> void:
	RenderingServer.set_default_clear_color(NIGHT_SKY)
	if pane != "":                 # a chase pane: the 2D world runs (hidden), the 3D one shows
		if load_replay(replay_path) == "":
			build_world()
			set_cam_mode(CamMode.CHASE)
			visible = false
			overlay.visible = false
			chase = Chase3D.new()
			add_child(chase)
			chase.build(self)
			chase.sync(self, 0.0, true)
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
	build_audio()
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
	for who in ["car", "ghost"]:
		var nz := FastNoiseLite.new()
		nz.seed = 11 if who == "car" else 23
		nz.frequency = 0.02                     # per meter of road: a drift every ~50 m...
		nz.fractal_type = FastNoiseLite.FRACTAL_NONE   # ...and nothing finer (layered detail = a shimmy)
		wander[who] = nz
	build_lines()
	build_shifts()
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

	land = SceneryScript.new()
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
	build_spotters(cone)
	measure_subject()
	camcar_reset()


## The flagger: stands in the road just past the start line between the cars'
## noses, counts 3-2-1 with a flashlight, then steps back to the shoulder.
func build_flagger(cone: Texture2D) -> void:
	var centerline: Array = replay["track"]["centerline"]
	var a := to_world(centerline[0][0], centerline[0][1])
	var b := to_world(centerline[mini(12, centerline.size() - 1)][0], centerline[mini(12, centerline.size() - 1)][1])
	var ahead := (b - a).normalized()
	flagger = make_person(a + ahead * 9.0 * PX_PER_M, ahead.angle() + PI)   # facing the cars
	overlay.add_child(flagger)
	var beam := make_headlight(cone, 0.0)
	beam.position = flagger.position
	beam.rotation = flagger.rotation
	beam.texture_scale = 24.0 * PX_PER_M / 256.0
	lights["flagger"] = beam


## A person from above (the flagger, the spotters): shoulders, head, an arm
## holding a flashlight. Drawn big, like the cars, so he reads.
func make_person(pos: Vector2, facing: float) -> Node2D:
	var who := Node2D.new()
	who.position = pos
	who.rotation = facing
	who.z_index = 12
	who.draw.connect(func():
		var s := PX_PER_M * 2.0
		who.draw_circle(Vector2(0.15, 0.2) * s, 0.55 * s, Color(0, 0, 0, 0.4))   # shadow
		who.draw_circle(Vector2.ZERO, 0.5 * s, Color(0.12, 0.12, 0.14))          # shoulders
		who.draw_circle(Vector2.ZERO, 0.28 * s, Color(0.55, 0.42, 0.33))         # head
		who.draw_line(Vector2(0, 0.35) * s, Vector2(0.7, 0.55) * s, Color(0.12, 0.12, 0.14), 0.22 * s)
		who.draw_circle(Vector2(0.75, 0.55) * s, 0.12 * s, Color(1, 0.95, 0.8)))  # the flashlight
	return who


## Spotters before the tightest (blind) corners, on the outside, facing the
## cars coming at them; the light points back down the road at them.
func build_spotters(cone: Texture2D) -> void:
	var tight := corners.filter(func(c): return float(c["radius"]) <= SPOTTER_MAX_RADIUS_M)
	tight.sort_custom(func(x, y): return float(x["radius"]) < float(y["radius"]))
	tight = tight.slice(0, SPOTTERS_MAX)
	for c in tight:
		var s := maxf(float(c["s_start"]) - SPOTTER_BEFORE_M, 3.0)
		var dir := road_dir(s - 3.0, s + 3.0)
		var right := Vector2(-dir.y, dir.x)
		var outside := right * (-1.0 if c["direction"] == "R" else 1.0)
		var pos := road_point(s) + outside * SPOTTER_OUT_M * PX_PER_M
		var aim := (-dir - outside * 0.6).angle()          # at the cars coming up the road
		var who := make_person(pos, aim)
		overlay.add_child(who)
		var beam := make_headlight(cone, 0.0)
		beam.position = pos
		beam.rotation = aim
		beam.texture_scale = 26.0 * PX_PER_M / 256.0
		spotters.append({"s": s, "node": who, "beam": beam, "aim": aim})


## Wave the light while a car is coming at him (either car).
func update_spotters() -> void:
	var cars := [value_at("s")]
	if ghost != null:
		cars.append(ghost_s_at(t))
	var tt := Time.get_ticks_msec() / 1000.0
	for sp: Dictionary in spotters:
		var near := false
		for cs: float in cars:
			var d: float = sp["s"] - cs
			near = near or (d > -10.0 and d < SPOTTER_WAVE_M)
		var beam: PointLight2D = sp["beam"]
		beam.energy = 2.2 if near and countdown <= 0.0 else 0.0
		var wave := 0.45 * sin(tt * 7.0) if near else 0.0
		beam.rotation = float(sp["aim"]) + wave
		sp["node"].rotation = float(sp["aim"]) + wave * 0.6


## The road's centerline at distance s (world px; points are 1 m apart).
func road_point(s: float) -> Vector2:
	var n := road_pts.size()
	if s < 0.0:                                  # behind the start line: straight back
		return road_pts[0] + (road_pts[0] - road_pts[1]).normalized() * -s * PX_PER_M
	if s > n - 1:                                # past the finish: straight on
		return road_pts[n - 1] + (road_pts[n - 1] - road_pts[n - 2]).normalized() * (s - (n - 1)) * PX_PER_M
	var i := clampi(int(floor(s)), 0, n - 2)
	return road_pts[i].lerp(road_pts[i + 1], clampf(s - i, 0.0, 1.0))


## The road's direction between two distances (unit vector).
func road_dir(s_from: float, s_to: float) -> Vector2:
	var d := road_point(s_to) - road_point(s_from)
	if d.length() < 0.01:
		d = road_pts[road_pts.size() - 1] - road_pts[maxi(road_pts.size() - 2, 0)]
	return d.normalized()


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
	hud["radio"] = osd_label(layer, Vector2.ZERO, 34, RADIO_GREEN)   # "SPOTTER: CLEAR"
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


## The spotter's call on the radio as Faba goes by him (Voice.SPOTTER_CALL).
func update_radio(vp: Vector2) -> void:
	var radio: Label = hud["radio"]
	radio.visible = false
	for k in spotters.size():
		var sp: Dictionary = spotters[k]
		var passed := time_at(samples["s"], samples["t"], float(sp["s"]))
		if t >= passed and t < passed + RADIO_SHOW_S and (not dnf or passed < lap_time) and t < end_time:
			if last_radio != k and playing:
				last_radio = k
				Sound.play("squelch", -4.0)
			radio.text = "SPOTTER: %s" % Voice.SPOTTER_CALL.to_upper()
			radio.reset_size()
			radio.position = Vector2(vp.x - radio.size.x - 20, TOP_BAR_PX + 76)
			radio.visible = fmod(t - passed, 0.5) < 0.38            # crackles in and out
	return


## Camcorder viewfinder: white corner brackets around the whole frame.
func draw_viewfinder(finder: Control) -> void:
	var r := Rect2(Vector2.ZERO, finder.size).grow(-VIEWFINDER_INSET)
	var col := Color(0.95, 0.95, 0.9, 0.75)
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var inward := (r.get_center() - corner).sign()
		finder.draw_line(corner, corner + Vector2(inward.x * VIEWFINDER_ARM, 0), col, 3.0)
		finder.draw_line(corner, corner + Vector2(0, inward.y * VIEWFINDER_ARM), col, 3.0)


## The chase panes: with an opponent, two side by side (him on the left,
## Faba on the right), else one for Faba. Each is a viewer in "pane" mode in
## its own viewport with its own 3D world (chase3d.gd): its car and the camera
## car behind it. Name + speed tag at the bottom of each half.
func build_panes(layer: CanvasLayer) -> void:
	for who in ["them", "faba"] if ghost != null else ["faba"]:
		var box := SubViewportContainer.new()
		box.stretch = true
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.visible = false
		var blur := ShaderMaterial.new()          # speed blur (chase3d.gd sets how much)
		blur.shader = SpeedBlur
		box.material = blur
		layer.add_child(box)
		var sv := SubViewport.new()
		sv.own_world_3d = true                    # each half its own road, car, lights
		sv.msaa_3d = Viewport.MSAA_4X
		box.add_child(sv)
		var v: Node2D = get_script().new()
		v.replay_path = replay_path
		v.embedded = embedded
		v.faba_parts = faba_parts
		v.busted = busted
		v.pane = who
		sv.add_child(v)
		panes.append(v)
		pane_boxes.append(box)
		pane_tags.append(osd_label(layer, Vector2.ZERO, 32,
			GHOST_MARKER_COLOR if who == "them" else MARKER_COLOR))
	if ghost != null:
		build_opp_dash(layer)


## His dash, small and see-through, in his half: tach, speedo, gear, pedals.
## (Older replays have no dash for him: then there's none.)
func build_opp_dash(layer: CanvasLayer) -> void:
	if not ghost["samples"].has("rpm"):
		return
	var dash := Control.new()
	dash.modulate.a = OPP_DASH_ALPHA
	dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dash)
	var tach: Control = GaugeScript.new()
	tach.size = Vector2.ONE * OPP_GAUGE_PX
	tach.max_value = 8000.0
	tach.major_step = 2000.0
	tach.minor_step = 1000.0
	tach.label_scale = 0.001
	tach.redline_from = float(ghost.get("redline", 7000) if ghost.get("redline") != null else 7000)
	tach.title = "rpm"
	dash.add_child(tach)
	var speedo: Control = GaugeScript.new()
	speedo.position = Vector2(OPP_GAUGE_PX + 4, 0)
	speedo.size = Vector2.ONE * OPP_GAUGE_PX
	speedo.max_value = 200.0
	speedo.major_step = 50.0
	speedo.minor_step = 25.0
	speedo.title = "km/h"
	dash.add_child(speedo)
	var gear := racing_label(dash, Vector2(2 * OPP_GAUGE_PX + 10, 10), 30, Color(1.0, 0.85, 0.3))
	hud["opp"] = {"dash": dash, "tach": tach, "speedo": speedo, "gear": gear,
		"brake": add_bar(dash, Vector2(2 * OPP_GAUGE_PX + 12, 52), Vector2(8, OPP_BAR_PX), Color(0.93, 0.17, 0.24)),
		"throttle": add_bar(dash, Vector2(2 * OPP_GAUGE_PX + 24, 52), Vector2(8, OPP_BAR_PX), Color(0.3, 0.8, 0.4))}


## One of his telemetry channels at time tt (his own time base).
func ghost_at(key: String, tt: float) -> float:
	var ts: Array = ghost["samples"]["t"]
	var arr: Array = ghost["samples"][key]
	var i := clampi(ts.bsearch(tt, false) - 1, 0, ts.size() - 2)
	var t0 := float(ts[i])
	var t1 := float(ts[i + 1])
	var f := 0.0 if t1 <= t0 else clampf((tt - t0) / (t1 - t0), 0.0, 1.0)
	return lerpf(float(arr[i]), float(arr[i + 1]), f)


## Lay out the panes in the view area and update their tags (a single pane
## needs no tag: the dash under it is Faba's).
func update_panes(vp: Vector2) -> void:
	var split := is_split()
	var area := view_area()
	var n := pane_boxes.size()
	var w := (area.size.x - PANE_GAP_PX * (n - 1)) / maxf(n, 1)
	for i in n:
		var box: SubViewportContainer = pane_boxes[i]
		box.visible = split
		box.position = Vector2(i * (w + PANE_GAP_PX), area.position.y)
		box.size = Vector2(w, area.size.y)
		if panes[i].chase != null:
			box.material.set_shader_parameter("amount", panes[i].chase.blur)
			box.material.set_shader_parameter("focus", panes[i].chase.flow)
		var tag: Label = pane_tags[i]
		var them: bool = panes[i].pane == "them"
		tag.visible = split and n > 1
		var kmh := ghost_speed_at(t) * 3.6 if them else value_at("v") * 3.6
		if panes[i].subject_out():
			kmh = 0.0                                # in the trees
		tag.text = "%s  %d KM/H" % [ghost_name() if them else "FABA", roundi(kmh)]
		tag.reset_size()
		tag.position = Vector2(box.position.x + 14 if them else vp.x - tag.size.x - 14,
			area.end.y - tag.size.y - 10)
	if hud.has("opp") and not pane_tags.is_empty():
		var o: Dictionary = hud["opp"]
		o["dash"].visible = split
		o["dash"].position = Vector2(10, pane_tags[0].position.y - OPP_GAUGE_PX - 6)
		var out := bool(ghost["dnf"]) and t >= float(ghost["lap_time"])
		var alive := 0.0 if out else 1.0
		o["tach"].value = ghost_at("rpm", t) * alive
		o["speedo"].value = ghost_at("v", t) * 3.6 * alive
		var g := int(ghost_at("gear", t))
		o["gear"].text = "-" if g == 0 else str(g)
		set_bar(o["throttle"], ghost_at("throttle", t) * alive, OPP_BAR_PX)
		set_bar(o["brake"], ghost_at("brake", t) * alive, OPP_BAR_PX)


## A small vertical bar filling from the bottom (his pedals).
func set_bar(fill: ColorRect, amount: float, h: float) -> void:
	var bottom := fill.position.y + fill.size.y
	fill.size.y = h * clampf(amount, 0.0, 1.0)
	fill.position.y = bottom - fill.size.y


## The ghost's speed (m/s): its replay has distance, not speed, so take the
## slope of s(t) over 0.2 s.
func ghost_speed_at(tt: float) -> float:
	if bool(ghost["dnf"]) and tt >= float(ghost["lap_time"]):
		return 0.0
	if ghost["samples"].has("v"):
		return ghost_at("v", tt)
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
	update_radio(vp)

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
		var now := (0 if countdown <= 0.0 else clampi(n, 1, 3)) if count.visible else 99
		if now != 99 and now != last_count:          # a beep on each count, a long one on GO
			last_count = now
			Sound.play("go" if now == 0 else "beep", -3.0)
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
	update_spotters()
	fire_events(delta)
	lay_tire_marks()
	update_camera(delta, false)
	shake = maxf(shake - delta * 1.6, 0.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 16.0 * shake * shake
	if pane == "":
		update_hud()
		update_audio()
	else:
		update_intro(get_viewport_rect().size)  # hazards + the flagger's light
		for k in shift_events(subject()).y:      # flames out the exhaust, with the pops you hear
			chase.flame()
		camcar_step(delta)
		chase.sync(self, delta)
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
	update_car()
	camcar_reset()
	update_camera(0.0, true)
	if chase != null:
		update_intro(get_viewport_rect().size)
		update_spotters()
		chase.sync(self, 0.0, true)
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
			if pane == "":
				Sound.play("crash")
				Sound.buzz(140)
		else:
			crash_age += delta
	if ghost != null and bool(ghost["dnf"]):
		var gt := float(ghost["lap_time"])
		if prev_t < gt and t >= gt and pane != "faba":
			crash_fx(ghost_car.position, ghost_car.rotation)
			if pane == "":
				Sound.play("crash", -3.0 if ghost != null and is_split() else 0.0)
	if not dnf and prev_t < end_time and t >= end_time and hud.has("flash"):   # the winner's line
		var flash: ColorRect = hud["flash"]
		flash.color.a = 0.7
		create_tween().tween_property(flash, "color:a", 0.0, 0.5)
		if busted:                                # ...and a cruiser right behind the camera car
			get_tree().create_timer(0.8).timeout.connect(func(): Sound.play("siren", -3.0))
		if sore_loser:                            # jorge mode: one long blast from the loser...
			Sound.play("honk_long", -2.0)
			next_honk = Time.get_ticks_msec() / 1000.0 + 2.6
		else:
			Sound.play("horn", -5.0)              # the guys at the line lean on their horns


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
	var line := driving_line(value_at("s"), value_at("v"), "car")
	var across := line.x
	car.position = to_world(value_at("x") + sin(h) * across, value_at("y") - cos(h) * across)
	car.rotation = -h + line.y                        # flip: Godot rotates clockwise
	car.position -= Vector2.from_angle(car.rotation) * roll_back_px()   # intro: rolling up
	if crash_age >= 0.0:                              # off the road, spinning into the trees
		var slid := crash_slide(crash_age, float(samples["v"][-1]))
		var at := value_at("s")
		car.position = slid_position(at, slid, across)
		car.rotation = road_dir(at + slid.x - 1.0, at + slid.x + 1.0).angle() + line.y \
			+ 0.9 * clampf(crash_age / 0.5, 0.0, 1.0)
	var braking := value_at("brake") > 0.0
	car.braking = braking
	car.load_g = loads(value_at("s"), value_at("v"), faba_accel())
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
	var line := driving_line(ghost_s_at(t), ghost_speed_at(t), "ghost")
	var across := line.x
	ghost_car.position = to_world(x + sin(h) * across, y - cos(h) * across)
	ghost_car.rotation = -h + line.y
	var gv := ghost_speed_at(t)
	var ga := (ghost_speed_at(t + 0.1) - ghost_speed_at(maxf(t - 0.1, 0.0))) / 0.2
	ghost_car.load_g = loads(ghost_s_at(t), gv, ga)
	ghost_car.position -= Vector2.from_angle(ghost_car.rotation) * roll_back_px()
	if lights.has("ghost_hazard"):
		lights["ghost_hazard"].position = ghost_car.position
	var ghost_out := bool(ghost["dnf"]) and t >= float(ghost["lap_time"])
	if ghost_out:                                     # off the road, spinning into the trees
		var age := t - float(ghost["lap_time"])
		var slid := crash_slide(age, ghost_crash_v())
		var at := ghost_s_at(t)
		ghost_car.position = slid_position(at, slid, across)
		ghost_car.rotation = road_dir(at + slid.x - 1.0, at + slid.x + 1.0).angle() + line.y \
			+ 0.9 * clampf(age / 0.5, 0.0, 1.0)
	ghost_tag.visible = ghost_out
	var hl: PointLight2D = lights["ghost"]
	hl.position = ghost_car.position + Vector2.from_angle(ghost_car.rotation) * 2.6 * PX_PER_M
	hl.rotation = ghost_car.rotation


# ------------------------------------------------------------------ cameras

func set_cam_mode(mode: int) -> void:
	cam_mode = mode
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

	var follow := 6.0                              # 1/s: how tightly the camera tracks its target
	if pane == "" and embedded and countdown > 0.0:
		# Intro: tight on the line, the cars rolling up and the flagger
		target_pos = flagger.position.lerp(car.position, 0.5)
		target_zoom = minf(area.size.x, area.size.y) / (40.0 * PX_PER_M)
	elif cam_mode == CamMode.OVERVIEW:
		var margin := 120.0 * PX_PER_M                # room for labels outside the road
		target_zoom = minf(area.size.x / (track_size.x + margin), area.size.y / (track_size.y + margin))
		target_pos = track_center
	else:
		# Chase is the 3D panes (chase3d.gd); this 2D camera only matters for
		# the moment the panes take over: on the car, pointing up the road
		target_zoom = area.size.x / (CHASE_VIEW_M * PX_PER_M) * (1.4 if focus_out else 1.0)
		target_rot = focus.rotation + PI / 2.0

	# The view area isn't centered vertically (top bar vs bottom panel): shift
	# the camera so target_pos lands in the middle of the view area
	var screen_offset := Vector2(0, (vp.y / 2.0) - area.get_center().y)

	if cut:
		camera.zoom = Vector2.ONE * target_zoom
		camera.rotation = target_rot
	else:
		var k := 1.0 - exp(-delta * 6.0)             # smooth, frame-rate independent
		camera.zoom = camera.zoom.lerp(Vector2.ONE * target_zoom, k)
		camera.rotation = lerp_angle(camera.rotation, target_rot, 1.0 - exp(-delta * maxf(follow, 8.0)))
	var world_offset := (screen_offset / camera.zoom.x).rotated(camera.rotation)
	var final_pos := target_pos + world_offset
	if cut:
		camera.position = final_pos
	else:
		camera.position = camera.position.lerp(final_pos, 1.0 - exp(-delta * follow))
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
	last_count = 99
	last_radio = -1
	next_honk = 0.0
	camcar_reset()
	if chase != null:
		chase.reset()
	if flagger:
		flagger.visible = true
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
	for who: String in shifts:                      # downshifts: a blip each, then the pops (+ flames)
		var n_pops := 0
		var popped := 0
		for sh: Dictionary in shifts[who]:
			n_pops += sh["pops"].size()
			popped += 1 if sh["pops"].size() > 0 else 0
		print("SHIFTS %s: %d downshifts, %d popped (chance %.0f%%), %d pops" % [
			who, shifts[who].size(), popped, POP_CHANCE * 100.0, n_pops])
	# Each chase pane through the whole run at 60 fps: its camera car never on
	# the bumper, never further than the max gap, and its car always in the shot
	set_cam_mode(CamMode.CHASE)
	update_hud()
	var n := pane_boxes.size()                       # as on the phone (720 x 1280), whatever the window
	for box: SubViewportContainer in pane_boxes:
		box.size = Vector2((720.0 - PANE_GAP_PX * (n - 1)) / n, 1280.0 - TOP_BAR_PX - BOTTOM_PX)
	var failed := ""
	for p in panes:
		p.countdown = 0.0
		p.jump_to(0.0)
		var gaps := []
		var fovs := []
		var framed := 0                              # frames with the car's middle in the shot...
		var whole := 0                               # ...and all of it
		var lost := false
		var noses := []                              # deg: the car's nose vs the road, per frame
		var screen_x := []                           # px: where it sits across the shot
		var after := 0                               # frames after a crash (the replay clock's stopped):
		while p.t < p.end_time or (p.subject_out() and after < 240):   # the slide, pulling up behind
			if p.t < p.end_time:
				p.t = minf(p.t + 1.0 / 60.0, p.end_time)
			else:
				after += 1
			p.fire_events(1.0 / 60.0)
			p.prev_t = p.t
			p.update_car()
			p.update_spotters()
			p.camcar_step(1.0 / 60.0)
			p.chase.sync(p, 1.0 / 60.0)
			var gap: float = p.subject_sv().x - float(p.camcar["s"])
			gaps.append(gap)
			fovs.append(p.chase.fov)
			lost = lost or gap < CAMCAR_MIN_GAP_M - 0.01 or gap > CAMCAR_MAX_GAP_M + 0.01
			var seen: int = p.chase.subject_in_frame()
			framed += 1 if seen > 0 else 0
			whole += 1 if seen == 2 else 0
			if not p.subject_out():                  # how much the car swings (Spire: "side to side")
				var node: Node2D = p.ghost_car if p.pane == "them" else p.car
				var s: float = p.subject_sv().x
				var nose := wrapf(node.rotation - p.road_dir(s - 1.0, s + 1.0).angle(), -PI, PI)
				noses.append(rad_to_deg(nose))
				var sx: float = p.chase.cam.unproject_position(p.chase.car["root"].position + Vector3(0, 0.7, 0)).x
				screen_x.append(sx)
		var mean := 0.0
		for g in gaps:
			mean += g
		var shot := 100.0 * framed / maxf(gaps.size(), 1)
		print("CAMCAR %s (%s px): grip %.2f g, accel %.1f m/s^2, gap min %.1f / mean %.1f / max %.1f m, in the shot %.1f%% (whole car %.1f%%), fov %d-%d%s" % [
			p.pane, str(p.get_viewport().get_visible_rect().size), p.camcar_grip, p.camcar_accel, gaps.min(), mean / gaps.size(), gaps.max(), shot,
			100.0 * whole / maxf(gaps.size(), 1), roundi(fovs.min()), roundi(fovs.max()), "  LOST HIM" if lost else ""])
		# Swing: the nose vs the road (rms), how fast it turns back and forth
		# (rms deg/s), and the car's wobble across the shot (rms of the frame-
		# to-frame change in its screen speed: a smooth pan scores ~0)
		var nose_rms := 0.0
		var rate_rms := 0.0
		var wobble := 0.0
		for i in noses.size():
			nose_rms += pow(noses[i], 2.0)
			if i > 0:
				rate_rms += pow((noses[i] - noses[i - 1]) * 60.0, 2.0)
			if i > 1:
				wobble += pow(screen_x[i] - 2.0 * screen_x[i - 1] + screen_x[i - 2], 2.0)
		var nn := maxf(noses.size(), 1)
		print("SWAY %s: nose vs road %.1f deg rms, nose turning %.0f deg/s rms, wobble on screen %.2f px/frame^2 rms" % [
			p.pane, sqrt(nose_rms / nn), sqrt(rate_rms / nn), sqrt(wobble / nn)])
		# Before the smoothed lines (Oct 2026) a tight road measured 83-118 deg/s
		# and a wobble of 3.5-5.7: Spire's "swinging side to side". Now ~5 / ~0.15.
		if sqrt(rate_rms / nn) > SWAY_MAX_DEG_S or sqrt(wobble / nn) > WOBBLE_MAX_PX:
			failed = "the car swings side to side"
		if lost:
			failed = "the camera car left its gap limits"
		elif shot < 100.0 or whole < 0.98 * gaps.size():
			failed = "the car left the shot"
	if failed != "":
		print("SELFTEST FAILED: " + failed)
		get_tree().quit(1)
		return
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
	if not spotters.is_empty():                 # coming up on a spotter, his light waving
		moments["spotter"] = time_at_s(float(spotters[0]["s"]) - 30.0)
	for moment in moments:
		jump_to(minf(float(moments[moment]), end_time))
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


# ------------------------------------------------------------ driving like a person

## The corner at distance s along the road, or {} on a straight.
func corner_at_s(s: float) -> Dictionary:
	for c in corners:
		if s >= float(c["s_start"]) and s < float(c["s_end"]):
			return c
	return {}


## A driver's line skill (0 rookie .. 1): Faba's from FABA_LINE_SKILL; the
## opponent's from his consistency (sigma 0.02 steady -> 0.9, 0.033 loose -> 0.25).
func line_skill(who: String) -> float:
	if who == "car":
		return FABA_LINE_SKILL
	var sigma = ghost.get("sigma") if ghost != null else null
	return 0.6 if sigma == null else clampf(1.0 - (float(sigma) - 0.018) / 0.02, 0.25, 0.9)


## How much of the swing a corner asks for (0..1): tight AND turning a long
## way = all of it; an open kink = nothing (nobody crosses the road for it).
func corner_need(c: Dictionary) -> float:
	var tight := clampf((NEED_NONE_M - float(c["radius"])) / (NEED_NONE_M - NEED_TIGHT_M), 0.0, 1.0)
	var turn := clampf(float(c.get("angle_deg", 90.0)) / 90.0, 0.3, 1.0)
	return tight * turn


## Out-in-out (m from the middle, + = right of travel): home on a straight,
## the outside before a corner, the inside at the apex, the outside on exit,
## each corner swung as far as it needs and the driver dares (skill).
func racing_line(s: float, skill: float) -> float:
	var home := lerpf(HOME_ROOKIE_M, HOME_PRO_M, skill)
	var dare := lerpf(0.25, 1.0, skill) * LINE_SWING_M
	var prev_end := -INF
	var prev_off := home
	var next_start := INF
	var next_off := home
	for c in corners:
		var s0 := float(c["s_start"])
		var s1 := float(c["s_end"])
		var swing := (1.0 if c["direction"] == "R" else -1.0) * dare * corner_need(c)   # + = toward the inside
		if s >= s0 and s < s1:                   # in it: outside -> apex -> outside
			var p := (s - s0) / maxf(s1 - s0, 1.0)
			return home - swing * cos(TAU * p)
		if s1 <= s and s1 > prev_end:
			prev_end = s1
			prev_off = home - swing
		if s0 > s and s0 < next_start:
			next_start = s0
			next_off = home - swing
	if next_start - prev_end < 2.0 * LINE_LEAD_M:   # short gap: one smooth move between them
		return lerpf(prev_off, next_off, smoothstep(prev_end, next_start, s))
	if s < prev_end + LINE_LEAD_M:
		return lerpf(prev_off, home, smoothstep(prev_end, prev_end + LINE_LEAD_M, s))
	if s > next_start - LINE_LEAD_M:
		return lerpf(home, next_off, smoothstep(next_start - LINE_LEAD_M, next_start, s))
	return home


## Where a car is across the road and how its nose points, at distance s and
## speed v: Vector2(m from the middle, + = right of travel; rad of nose, + =
## clockwise on screen). who: "car" (Faba: his mistakes run wide) or "ghost".
## The nose follows the line: a car only moves sideways by POINTING that way
## (heading = atan of the sideways change per meter), so it steers across
## the road instead of sliding.
func driving_line(s: float, v: float, who: String) -> Vector2:
	var nz: FastNoiseLite = wander[who]
	var skill := line_skill(who)
	var sway := WANDER_M * lerpf(1.6, 0.6, skill) * (0.4 + 0.6 * clampf(v / V_SHAKE_REF, 0.0, 1.5))
	var path := func(x: float) -> float: return line_at(x, who) + nz.get_noise_1d(x) * sway
	var across: float = path.call(s)
	var nose := atan((float(path.call(s + 2.0)) - float(path.call(s - 2.0))) / 4.0)
	# Slip angle: the nose turns into the corner with lateral g (a = v^2 / r),
	# easing in and out with the road's curve (bend_at), never in one snap
	nose += SLIP_RAD_PER_G * clampf(v * v * bend_at(s) / G, -1.3, 1.3)
	var limit := LANE_LIMIT_M
	if who == "car" and driver != null:
		for m in driver["corners"]:              # ran wide: out after the apex, back over 40 m
			if not m["mistake"]:
				continue
			var mid := (float(m["s_start"]) + float(m["s_end"])) / 2.0
			var k := 0.0
			if s >= mid and s < float(m["s_end"]):
				k = (s - mid) / maxf(float(m["s_end"]) - mid, 1.0)
			elif s >= float(m["s_end"]) and s < float(m["s_end"]) + 40.0:
				k = 1.0 - (s - float(m["s_end"])) / 40.0
			if k > 0.0:
				var mc := corner_at_s(mid)
				var out := -1.0 if mc.get("direction", "R") == "R" else 1.0
				across += out * RUN_WIDE_M * k
				nose += out * 0.12 * k            # pointing out of it, wide
				limit = lerpf(LANE_LIMIT_M, WIDE_LIMIT_M, k)
	return Vector2(clampf(across, -limit, limit), nose)


## What the body feels: Vector2(longitudinal g, + = speeding up; lateral g,
## + = turning right), from its speed through the corner (a = v^2 / r) and
## its acceleration along the road.
func loads(s: float, v: float, accel: float) -> Vector2:
	return Vector2(clampf(accel / G, -1.2, 0.8), clampf(v * v * bend_at(s) / G, -1.3, 1.3))


## The smoothed tables (built once, build_lines): each driver's racing line and
## the road's curvature, 1 m apart from LINE_PAD_M before the start. The pace
## notes go straight -> full curve in one step (and an S-bend flips the line
## from one corner's outside to the next one's in one step); real roads and
## real drivers ease through those. Smoothing them is what keeps a car from
## twitching side to side.
func build_lines() -> void:
	var n := int(float(replay["track"]["length"])) + 2 * LINE_PAD_M
	bend = smooth(n, BEND_EASE_M, func(s: float) -> float:
		var c := corner_at_s(s)
		return 0.0 if c.is_empty() else (1.0 if c["direction"] == "R" else -1.0) / maxf(float(c["radius"]), 1.0))
	for who in ["car", "ghost"] if ghost != null else ["car"]:
		var skill := line_skill(who)
		lines[who] = smooth(n, LINE_EASE_M, func(s: float) -> float: return racing_line(s, skill))


## f(s) sampled every meter, then a moving average over `ease_m` twice (a
## triangle-shaped blend: the result has no corners in it).
func smooth(n: int, ease_m: float, f: Callable) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		a[i] = f.call(float(i - LINE_PAD_M))
	var half := maxi(int(ease_m / 2.0), 1)
	for pass_i in 2:
		var b := PackedFloat32Array()
		b.resize(n)
		var acc := 0.0
		var lo := 0
		var hi := -1
		for i in n:
			while hi < mini(i + half, n - 1):
				hi += 1
				acc += a[hi]
			while lo < i - half:
				acc -= a[lo]
				lo += 1
			b[i] = acc / (hi - lo + 1)
		a = b
	return a


func table_at(a: PackedFloat32Array, s: float) -> float:
	var x := clampf(s + LINE_PAD_M, 0.0, a.size() - 1.001)
	var i := int(x)
	return lerpf(a[i], a[i + 1], x - i)


## A driver's racing line at s (m across, + = right of travel), smoothed.
func line_at(s: float, who: String) -> float:
	return table_at(lines[who], s)


## The road's curvature at s (1/m, + = turning right), eased in and out.
func bend_at(s: float) -> float:
	return table_at(bend, s)


## Faba's acceleration along the road (m/s^2), from his speed samples.
func faba_accel() -> float:
	var ts: Array = samples["t"]
	var vs: Array = samples["v"]
	var dt := float(ts[idx + 1]) - float(ts[idx])
	return 0.0 if dt <= 0.0 else (float(vs[idx + 1]) - float(vs[idx])) / dt


# ------------------------------------------------------------ the camera car

## Which car this view films: a pane's own, else Faba.
func subject() -> String:
	return "ghost" if pane == "them" else "car"


## The subject's distance along the road and speed (a wreck: where its slide is).
func subject_sv() -> Vector2:
	var age := subject_crash_age()
	if subject() == "ghost":
		if age >= 0.0:
			var g := crash_slide(age, ghost_crash_v())
			return Vector2(ghost_s_at(t) + g.x, g.z)
		return Vector2(ghost_s_at(t), ghost_speed_at(t))
	if age >= 0.0:
		var f := crash_slide(age, float(samples["v"][-1]))
		return Vector2(value_at("s") + f.x, f.z)
	return Vector2(value_at("s"), value_at("v"))


## A crash, after the sim's run ends at the apex (VISUAL, both views): the car
## goes on off the road shedding speed hard (CRASH_DECEL: dirt, brush, the
## hit), out past the edge to the outside of the corner. Vector3(m along the
## road past the crash point, m out, its speed now).
func crash_slide(age: float, v0: float) -> Vector3:
	var tau := clampf(age, 0.0, v0 / CRASH_DECEL)
	var along := v0 * tau - 0.5 * CRASH_DECEL * tau * tau
	return Vector3(along, OFF_ROAD_M * smoothstep(0.0, 0.8, age), maxf(v0 - CRASH_DECEL * maxf(age, 0.0), 0.0))


## Where a sliding wreck is (world px): s_crash + its slide along the road,
## from its line across it out past the edge.
func slid_position(s_crash: float, slid: Vector3, across: float) -> Vector2:
	var s := s_crash + slid.x
	var c := corner_at_s(s_crash)
	var outside := -1.0 if c.get("direction", "R") == "R" else 1.0     # + = right of travel
	var dir := road_dir(s - 1.0, s + 1.0)
	return road_point(s) + Vector2(-dir.y, dir.x) * (across + outside * slid.y) * PX_PER_M


## His speed as he went off (his replay's last speed sample).
func ghost_crash_v() -> float:
	var gs: Dictionary = ghost["samples"]
	if gs.has("v"):
		return float(gs["v"][-1])
	var gt := float(ghost["lap_time"])
	return (ghost_s_at(gt) - ghost_s_at(gt - 0.2)) / 0.2


func subject_out() -> bool:
	if subject() == "ghost":
		return bool(ghost["dnf"]) and t >= float(ghost["lap_time"])
	return dnf and t >= lap_time


## Seconds since the subject crashed (Faba's on real time: the replay clock
## stops at his crash; his opponent's on the replay clock), < 0 if it hasn't.
func subject_crash_age() -> float:
	if not subject_out():
		return -1.0
	if subject() == "ghost":
		return t - float(ghost["lap_time"])
	return maxf(crash_age, 0.0)


## The camera car is matched to the car it films: its grip from the
## subject's best cornering g (v_min^2 / r through each corner), its power
## from the subject's best pull.
func measure_subject() -> void:
	var smp: Dictionary = ghost["samples"] if subject() == "ghost" else samples
	if not smp.has("v"):
		return
	var ss: Array = smp["s"]
	var vs: Array = smp["v"]
	var ts: Array = smp["t"]
	var best_g := 0.0
	for c in corners:
		var v_min := INF
		for i in ss.size():
			if float(ss[i]) >= float(c["s_start"]) and float(ss[i]) <= float(c["s_end"]):
				v_min = minf(v_min, float(vs[i]))
		if v_min < INF:
			best_g = maxf(best_g, v_min * v_min / float(c["radius"]) / G)
	camcar_grip = maxf(CAMCAR_GRIP_SHARE * best_g, CAMCAR_GRIP_MIN)
	var best_a := 0.0
	for i in range(1, vs.size()):
		var dt := float(ts[i]) - float(ts[i - 1])
		if dt > 0.0 and float(vs[i]) > 8.0:
			best_a = maxf(best_a, (float(vs[i]) - float(vs[i - 1])) / dt)
	camcar_accel = maxf(CAMCAR_ACCEL_MIN, CAMCAR_ACCEL_SHARE * best_a)


## Settle it where it would be: its gap behind, at the subject's speed.
func camcar_reset() -> void:
	var sv := subject_sv()
	var back := roll_back_px() / PX_PER_M if countdown > 0.0 else 0.0
	camcar["s"] = sv.x - back - CAMCAR_GAP_M
	camcar["v"] = 0.0 if countdown > 0.0 else sv.y
	camcar["yaw"] = road_dir(camcar["s"] - 2.0, camcar["s"] + 8.0).angle()
	camcar["t"] = t


## The fastest it's willing to go here: every corner within its braking
## reach, braked for at its planning rate (v^2 = v_c^2 + 2 a d), cornering
## at camcar_grip (v_c = sqrt(mu g r)).
func camcar_allow(s: float, v: float) -> float:
	var best := INF
	var reach := v * v / (2.0 * CAMCAR_PLAN) + 40.0
	for c in corners:
		var s0 := float(c["s_start"])
		if float(c["s_end"]) < s or s0 > s + reach:
			continue
		var vc := sqrt(camcar_grip * G * float(c["radius"]))
		var d := maxf(s0 - s, 0.0)
		best = minf(best, sqrt(vc * vc + 2.0 * CAMCAR_PLAN * d))
	return best


## Drive it one frame. It runs on PLAYBACK time (pause, 2x, slow-mo all
## apply), in 1/60 s steps; after a crash the replay clock stops, so it
## rolls up to the wreck on real time.
func camcar_step(delta: float) -> void:
	var play := t - float(camcar["t"])
	camcar["t"] = t
	if play < 0.0 or play > 2.0:                  # restarted / jumped: settle instead
		camcar_reset()
		return
	var sv := subject_sv()
	var out := subject_out()
	if out and t >= end_time and playing:
		play = delta                              # the clock's stopped at the crash; it isn't
	if countdown > 0.0:                           # the roll-up: it waits behind the cars, lights on
		camcar["s"] = sv.x - roll_back_px() / PX_PER_M - CAMCAR_GAP_M
		camcar["v"] = 0.0
	var steps := clampi(ceili(play * 60.0), 0, 120)
	var h := play / maxf(steps, 1)
	for i in steps:
		var cs: float = camcar["s"]
		var cv: float = camcar["v"]
		var gap := sv.x - cs
		var fv := 0.0 if out else sv.y
		var want := fv + CAMCAR_K_GAP * (gap - (CAMCAR_STOP_M if out else CAMCAR_GAP_M))
		want = clampf(minf(want, camcar_allow(cs, cv)), 0.0, INF)
		cv += clampf(want - cv, -(CAMCAR_BRAKE_HARD if out else CAMCAR_BRAKE) * h, camcar_accel * h)
		cs += cv * h
		if sv.x - cs < CAMCAR_MIN_GAP_M:          # never on his bumper
			cs = sv.x - CAMCAR_MIN_GAP_M
			cv = minf(cv, fv)
		if sv.x - cs > CAMCAR_MAX_GAP_M:          # never loses him: floors it
			cs = sv.x - CAMCAR_MAX_GAP_M
		camcar["s"] = cs
		camcar["v"] = cv
	# Its heading: the road where IT is, plus its line, turning in a beat late
	var cs2: float = camcar["s"]
	var aim := road_dir(cs2 - 2.0, cs2 + 8.0).angle() + atan((camcar_lat(cs2 + 1.5) - camcar_lat(cs2 - 1.5)) / 3.0)
	camcar["yaw"] = lerp_angle(float(camcar["yaw"]), aim, 1.0 - exp(-maxf(play, 0.0) * CAMCAR_STEER))


## Across the road (m, + = right of travel): part of the subject's line.
func camcar_lat(s: float) -> float:
	return CAMCAR_LINE_SHARE * line_at(s, subject())


## The camera car's position (world px).
func camcar_pos() -> Vector2:
	var s: float = camcar["s"]
	var along := road_dir(s - 2.0, s + 2.0)
	return road_point(s) + Vector2(-along.y, along.x) * camcar_lat(s) * PX_PER_M


## Its own cornering: Vector2(lateral g, +1 right / -1 left / 0).
func camcar_ride() -> Vector2:
	var k := bend_at(float(camcar["s"]))
	var v: float = camcar["v"]
	return Vector2(v * v * absf(k) / G, signf(k))



# ------------------------------------------------------------ sound

## Every downshift in a car's run (sim: one gear at a time while braking; the
## gear reads 0 for the 0.4 s the clutch is in): the gap (t0 -> t1) is when
## the driver blips the throttle to match revs, and just after it, off the
## gas, the exhaust MAY pop (2-5 bangs + flames, POP_CHANCE of the time; Spire:
## not every single time). The pops come from a seed per shift, so the full
## viewer's sound and each pane's flames agree.
const POP_CHANCE := 0.4
func build_shifts() -> void:
	shifts["car"] = find_downshifts(samples, "car")
	if ghost != null and ghost["samples"].has("gear"):
		shifts["ghost"] = find_downshifts(ghost["samples"], "ghost")


func find_downshifts(smp: Dictionary, who: String) -> Array:
	var out := []
	var ts: Array = smp["t"]
	var gs: Array = smp["gear"]
	var last := 0
	var gap_t := -1.0
	var rng := RandomNumberGenerator.new()
	for i in gs.size():
		var g := int(gs[i])
		if g == 0:                                   # clutch in: the shift is happening
			if gap_t < 0.0:
				gap_t = float(ts[i])
			continue
		if last > 0 and g < last:
			rng.seed = hash("%s/%d" % [who, i])      # the same pops in the picture and the sound
			var pops := []
			if rng.randf() < POP_CHANCE:                 # the blip always; the pops + flames only sometimes
				var tp := float(ts[i]) + rng.randf_range(0.04, 0.14)
				for k in rng.randi_range(2, 5):
					pops.append(tp)
					tp += rng.randf_range(0.07, 0.24)
			out.append({"t0": gap_t if gap_t >= 0.0 else float(ts[i]), "t1": float(ts[i]), "pops": pops})
		last = g
		gap_t = -1.0
	return out


## What happens to one car this frame: Vector2i(blips, pops) whose time falls
## in (prev_t, t]. Nothing on a jump (restart, a still).
func shift_events(who: String) -> Vector2i:
	if not playing or t <= prev_t or t - prev_t > 1.0 or not shifts.has(who):
		return Vector2i.ZERO
	var blips := 0
	var pops := 0
	for sh: Dictionary in shifts[who]:
		if float(sh["t0"]) > prev_t and float(sh["t0"]) <= t:
			blips += 1
		for pt: float in sh["pops"]:
			if pt > prev_t and pt <= t:
				pops += 1
	return Vector2i(blips, pops)


## Each car's engine, synthesized live (widgets/car_audio.gd), in the full
## viewer only. The broadcast's other noises fire from their moments: the
## count (update_intro), the spotters' radio (update_radio), a crash and the
## horns at the line (fire_events). Sound.play: sound.gd.
func build_audio() -> void:
	for who in ["car", "ghost"] if ghost != null else ["car"]:
		var a: AudioStreamPlayer = CarAudio.new()
		a.cylinders = CarAudio.cylinders_for(str(replay["car"]["name"]) if who == "car" else str(ghost["car"]))
		a.volume_db = 0.0 if who == "car" else -2.0
		add_child(a)
		audio[who] = a


## What each engine is doing now: off the replay's telemetry while racing;
## revving at the line during the count (his a beat after Faba's: a standoff);
## idling once it's over; dying after a crash while the wreck slides.
## Split screen pans him left and Faba right, like the picture.
func update_audio() -> void:
	# ...then he won't stop, for as long as you sit there at the line
	var now := Time.get_ticks_msec() / 1000.0
	if sore_loser and t >= end_time and next_honk > 0.0 and now >= next_honk:
		Sound.play("honk_angry", -2.0, randf_range(0.95, 1.05))
		next_honk = now + randf_range(2.2, 4.5)
	var split := is_split() and ghost != null
	var slow := clampf(SPEEDS[speed_i] * (SLOW_MO if finish_slow() else 1.0), 0.5, 1.0)
	var elapsed := COUNTDOWN_S - countdown
	for who: String in audio:
		var a: AudioStreamPlayer = audio[who]
		var them := who == "ghost"
		a.pan = (-0.6 if them else 0.6) if split else 0.0
		a.time_scale = slow
		a.gain = 1.0 if playing else 0.0                # a paused tape is silent
		a.alive = 1.0
		a.squeal = 0.0
		var ev := shift_events(who)             # downshifts: the blip, then the pops
		if ev.x > 0:
			a.blip()
		for k in ev.y:
			a.pop()
		if countdown > 0.0:
			a.speed = 0.0
			if elapsed < ROLL_S:                         # rolling up to the line
				a.rpm = 1300.0
				a.throttle = 0.15
			else:                                        # a blip on every count
				var k := fmod(elapsed - ROLL_S + (0.3 if them else 0.0), COUNT_STEP_S) / COUNT_STEP_S
				a.rpm = lerpf(1100.0, 5200.0, exp(-k * 5.0))
				a.throttle = 1.0 if k < 0.15 else 0.05
			continue
		var out := (bool(ghost["dnf"]) and t >= float(ghost["lap_time"])) if them else (dnf and t >= lap_time)
		if out:                                          # off the road: the motor dies, the tires scream
			var age := t - float(ghost["lap_time"]) if them else maxf(crash_age, 0.0)
			var v0 := ghost_crash_v() if them else float(samples["v"][-1])
			a.speed = crash_slide(age, v0).z
			a.alive = clampf(1.0 - age / 0.35, 0.0, 1.0)
			a.squeal = 1.0 if a.speed > 3.0 else 0.0
			continue
		if t >= end_time:                                # over: off the gas, idling at the line
			a.rpm = 1000.0
			a.throttle = 0.0
			a.speed = 0.0
			continue
		var s := ghost_s_at(t) if them else value_at("s")
		var v := ghost_speed_at(t) if them else value_at("v")
		if them:
			var has: bool = ghost["samples"].has("rpm")
			a.rpm = ghost_at("rpm", t) if has else clampf(1500.0 + v * 90.0, 1500.0, 7000.0)
			a.throttle = ghost_at("throttle", t) if has else 0.8
		else:
			a.rpm = value_at("rpm")
			a.throttle = value_at("throttle")
		a.speed = v
		# Tires: a squeal past ~0.7 g of cornering (a = v^2 / r), all out running wide
		a.squeal = clampf((absf(v * v * bend_at(s)) / G - 0.7) / 0.25, 0.0, 1.0)
		if not them and driver != null:
			for c in driver["corners"]:
				var mid := (float(c["s_start"]) + float(c["s_end"])) / 2.0
				if c["mistake"] and s >= mid and s <= float(c["s_end"]):
					a.squeal = 1.0
