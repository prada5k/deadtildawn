extends RefCounted
## The footage is shot from a SEPARATE virtual car following the subject: windshield-height camera, a gap that
## breathes as the subject accelerates and brakes, a lens that tracks the subject a beat late.
##
## It is a presentation device: it reads the recorded run (subject distance, speed, position) and decides where a
## filming car would be. It never writes anything back.
##
## PATH LOGIC. The camera car drives the road's CENTERLINE (slightly left of the subject's lane), so it follows the
## roadway and cannot cut a corner; the road is extended straight behind the start line so it can start a gap back.
## Its speed is a gap controller on distance along the road:
##     target = s_subject - (gap + gap_per_ms * v_subject)
##     a = clamp( kp * (target - s_cam) + kd * (v_subject - v_cam), -max_brake, +max_accel )
## so it falls back when the subject launches, catches up, and closes under braking, within believable limits
## (a real car can only accelerate and brake so hard). Its body roll / pitch come from the same vehicle-dynamics
## layer as the subject's (softer), plus deterministic vibration. The lens aims at the subject through a
## first-order lag (the operator's reaction), so in a turn the subject drifts across the frame.
##
## DETERMINISM: everything is integrated ONCE on a fixed 1/60 s grid from the recorded arrays; at(t) is a pure
## function of playback time (seek, pause, restart and speed changes cannot change a frame).

const VehicleDynamics := preload("res://widgets/vehicle_dynamics.gd")
const RoadElevation := preload("res://widgets/road_elevation.gd")

const GRID_S := 1.0 / 60.0
const SUBSTEPS := 2

# ---- configurable ----
var gap_m := 7.8                       # filming gap behind the subject (m, along the road) at rest
var gap_per_ms := 0.10                 # extra gap per m/s of speed
var catch_up_kp := 1.2                 # 1/s^2: how hard it closes a gap error
var catch_up_kd := 2.2                 # 1/s: how hard it matches the subject's speed
var max_accel_ms2 := 4.5               # what a filming car can do
var max_brake_ms2 := 8.5
var lane_offset_m := 1.5               # the camera car's lateral position, + = right of the centerline (the subject runs at +2.0)
var subject_lane_m := 2.0
var lens_lag_s := 0.3                  # the operator's reaction: time constant of the lens tracking the subject
var dash_height_m := 1.15              # windshield / dashboard height
var dash_forward_m := 0.35             # lens ahead of the camera car's centre
var subject_aim_height_m := 0.8        # where on the subject the lens points
var fov_deg := 37.0
var roll_share := 0.7                  # how much of the camera car's body roll reaches the picture
var pitch_share := 0.6
var road_extension_m := 60.0           # straight road behind the start line

var dynamics := VehicleDynamics.new()

# the road, extended: positions (replay frame: x east, y north), distance along it, heading
var road_pts: Array[Vector2] = []
var road_s := PackedFloat64Array()
var road_h := PackedFloat64Array()
var elevation := RoadElevation.new()

# the camera car, on the grid
var t0 := 0.0
var count := 0
var cam_pos := PackedVector3Array()    # the camera car's centre on the road, world (x, 0, -y)
var cam_s := PackedFloat64Array()
var cam_v := PackedFloat64Array()
var cam_gap := PackedFloat64Array()
var cam_heading := PackedFloat64Array()
var aim_yaw := PackedFloat64Array()    # the lens, after the reaction lag
var aim_pitch := PackedFloat64Array()


func _init() -> void:
	dynamics.roll_deg_per_g = 3.2      # a hatch / sedan used as a camera car: softer, calmer than the subject
	dynamics.roll_limit_deg = 4.0
	dynamics.pitch_deg_per_g = 1.4
	dynamics.pitch_limit_deg = 2.0
	dynamics.roll_freq_hz = 1.1
	dynamics.pitch_freq_hz = 1.3
	dynamics.heave_amp_m = 0.0         # (its vibration is added in at())
	dynamics.wheelbase_m = 2.7


## centerline: the replay's road points ([x, y] every ~1 m from s = 0). The other arrays are the recorded run.
func build(centerline: Array, ts_in: Array, ss_in: Array, xs_in: Array, ys_in: Array, hs_in: Array, vs_in: Array, elevation_in = null) -> void:
	elevation = elevation_in if elevation_in != null else RoadElevation.new()
	build_road(centerline)
	var n := ts_in.size()
	var ts := PackedFloat64Array()
	var ss := PackedFloat64Array()
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	var hs := PackedFloat64Array()
	var vs := PackedFloat64Array()
	for a: PackedFloat64Array in [ts, ss, xs, ys, hs, vs]:
		a.resize(n)
	var prev := float(hs_in[0])
	var unwrapped := prev
	for i in n:
		ts[i] = float(ts_in[i]); ss[i] = float(ss_in[i]); xs[i] = float(xs_in[i]); ys[i] = float(ys_in[i]); vs[i] = float(vs_in[i])
		var h := float(hs_in[i])
		unwrapped += wrapf(h - prev, -PI, PI)
		prev = h
		hs[i] = unwrapped
	t0 = ts[0]
	var t_end := ts[n - 1]
	count = int(ceil((t_end - t0) / GRID_S)) + 1
	for a: PackedFloat64Array in [cam_s, cam_v, cam_gap, cam_heading, aim_yaw, aim_pitch]:
		a.resize(count)
	cam_pos.resize(count)

	# 1. the camera car's motion along the road: a gap controller
	var s_cam := float(ss[0]) - gap_m
	var v_cam := 0.0
	var dt := GRID_S / SUBSTEPS
	for k in count:
		var t := t0 + k * GRID_S
		if k > 0:
			for sub in SUBSTEPS:
				var tt := t - GRID_S + (sub + 1) * dt
				var s_sub := VehicleDynamics.lerp_series(ts, ss, tt)
				var v_sub := VehicleDynamics.lerp_series(ts, vs, tt)
				var target := s_sub - (gap_m + gap_per_ms * v_sub)
				var accel := clampf(catch_up_kp * (target - s_cam) + catch_up_kd * (v_sub - v_cam), -max_brake_ms2, max_accel_ms2)
				v_cam = maxf(v_cam + accel * dt, 0.0)
				s_cam += v_cam * dt
		cam_s[k] = s_cam
		cam_v[k] = v_cam
		cam_gap[k] = VehicleDynamics.lerp_series(ts, ss, t) - s_cam
		var on_road := road_at(s_cam)
		var pos2: Vector2 = on_road["pos"] + on_road["right"] * lane_offset_m
		cam_pos[k] = Vector3(pos2.x, float(on_road["height"]), -pos2.y)
		cam_heading[k] = on_road["heading"]

	# 2. the camera car's own body motion, from the same dynamics layer
	var grid_t: Array = []
	var grid_s: Array = []
	var grid_h: Array = []
	var grid_v: Array = []
	for k in count:
		grid_t.append(t0 + k * GRID_S)
		grid_s.append(cam_s[k])
		grid_h.append(cam_heading[k])
		grid_v.append(cam_v[k])
	dynamics.build(grid_t, grid_s, grid_h, grid_v)

	# 3. the lens: aims at the subject through a first-order lag (the operator's reaction)
	var blend := 1.0 - exp(-GRID_S / maxf(lens_lag_s, 1e-3))
	for k in count:
		var t := t0 + k * GRID_S
		var eye := eye_position(k)
		var h_sub := VehicleDynamics.lerp_series(ts, hs, t)
		var sub_height := elevation.at(VehicleDynamics.lerp_series(ts, ss, t)).x
		var subject := Vector3(VehicleDynamics.lerp_series(ts, xs, t) + sin(h_sub) * subject_lane_m, sub_height + subject_aim_height_m,
			-VehicleDynamics.lerp_series(ts, ys, t) + cos(h_sub) * subject_lane_m)
		var d := subject - eye
		var want_yaw := atan2(-d.z, d.x)
		var want_pitch := atan2(d.y, Vector2(d.x, d.z).length())
		if k == 0:
			aim_yaw[0] = want_yaw
			aim_pitch[0] = want_pitch
		else:
			aim_yaw[k] = aim_yaw[k - 1] + wrapf(want_yaw - aim_yaw[k - 1], -PI, PI) * blend
			aim_pitch[k] = aim_pitch[k - 1] + (want_pitch - aim_pitch[k - 1]) * blend


## The lens position before body motion: ahead of the camera car's centre, at windshield height.
func eye_position(k: int) -> Vector3:
	var h: float = cam_heading[k]
	var grade := elevation.at(cam_s[k]).y
	return cam_pos[k] + Vector3(cos(h), grade, -sin(h)).normalized() * dash_forward_m + Vector3(0.0, dash_height_m, 0.0)


# ------------------------------------------------------------------ the road

## Centerline points -> polyline with distance and heading, extended straight behind the start.
func build_road(centerline: Array) -> void:
	var pts: Array[Vector2] = []
	for p in centerline:
		pts.append(Vector2(float(p[0]), float(p[1])))
	var first_dir := (pts[1] - pts[0]).normalized()
	var ext_count := int(road_extension_m)
	road_pts.clear()
	for k in range(ext_count, 0, -1):
		road_pts.append(pts[0] - first_dir * float(k))
	road_pts.append_array(pts)
	var n := road_pts.size()
	road_s.resize(n)
	road_h.resize(n)
	var s := -float(ext_count)
	road_s[0] = s
	for i in range(1, n):
		# v2's axis is the exported horizontal sampling distance. Rounded XY points
		# are only a drawing approximation and must not redefine the elevation axis.
		s = (minf(float(i - ext_count), elevation.length) if elevation.elevated and i >= ext_count
			else s + road_pts[i].distance_to(road_pts[i - 1]))
		road_s[i] = s
	for i in n:                                         # heading: a short central difference, unwrapped
		var d := road_pts[mini(i + 2, n - 1)] - road_pts[maxi(i - 2, 0)]
		road_h[i] = atan2(d.y, d.x)
	for i in range(1, n):
		road_h[i] = road_h[i - 1] + wrapf(road_h[i] - road_h[i - 1], -PI, PI)


## The road at distance s: {pos, heading, right}. Beyond the ends it continues straight.
func road_at(s: float) -> Dictionary:
	var n := road_pts.size()
	if s <= road_s[0] or s >= road_s[n - 1]:
		var i := 0 if s <= road_s[0] else n - 1
		var over := s - road_s[i]
		var h: float = road_h[i]
		var p := road_pts[i] + Vector2(cos(h), sin(h)) * over
		var vertical := elevation.at(s)
		return {"pos": p, "heading": h, "right": Vector2(sin(h), -cos(h)), "height": vertical.x, "grade": vertical.y}
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if road_s[mid] <= s:
			lo = mid
		else:
			hi = mid
	var f := (s - road_s[lo]) / maxf(road_s[hi] - road_s[lo], 1e-6)
	var heading := lerpf(road_h[lo], road_h[hi], f)
	var vertical := elevation.at(s)
	return {"pos": road_pts[lo].lerp(road_pts[hi], f), "heading": heading,
		"right": Vector2(sin(heading), -cos(heading)), "height": vertical.x, "grade": vertical.y}


# ------------------------------------------------------------------ playback

static func grid_vec3(arr: PackedVector3Array, f: float) -> Vector3:
	var i := int(f)
	if i >= arr.size() - 1:
		return arr[arr.size() - 1]
	return arr[i].lerp(arr[i + 1], f - i)


## Camera vibration, deterministic (a function of time and the camera car's speed only): ARTISTIC. Returns
## (pitch rad, roll rad, vertical m).
static func vibration(t: float, v: float) -> Vector3:
	var amp := 0.15 + 0.85 * clampf(v / 30.0, 0.0, 1.0)
	var pitch := deg_to_rad(0.09) * amp * (0.6 * sin(TAU * 6.1 * t + 0.3) + 0.4 * sin(TAU * 13.7 * t + 1.9))
	var roll := deg_to_rad(0.07) * amp * (0.5 * sin(TAU * 7.7 * t + 2.2) + 0.5 * sin(TAU * 17.3 * t + 0.8))
	var lift := 0.010 * amp * (0.6 * sin(TAU * 9.3 * t) + 0.4 * sin(TAU * 21.1 * t + 1.1))
	return Vector3(pitch, roll, lift)


## The camera at playback time t (a pure function of t): {transform, fov, gap, speed, yaw, pitch, roll}.
func at(t: float) -> Dictionary:
	var f := clampf((t - t0) / GRID_S, 0.0, float(count - 1))
	var i := int(f)
	var j := mini(i + 1, count - 1)
	var w := f - i
	var centre := grid_vec3(cam_pos, f)
	var heading := lerp_angle(cam_heading[i], cam_heading[j], w)
	var speed := lerpf(cam_v[i], cam_v[j], w)
	var body := dynamics.at(t)
	var vib := vibration(t, speed)
	var yaw := lerp_angle(aim_yaw[i], aim_yaw[j], w)
	var pitch: float = lerpf(aim_pitch[i], aim_pitch[j], w) + float(body["pitch"]) * pitch_share + vib.x
	var roll: float = float(body["roll"]) * roll_share + vib.y
	var grade := elevation.at(lerpf(cam_s[i], cam_s[j], w)).y
	var eye := centre + Vector3(cos(heading), grade, -sin(heading)).normalized() * dash_forward_m + Vector3(0.0, dash_height_m + vib.z, 0.0)
	# basis: yaw about +Y (a forward of (cos yaw, 0, -sin yaw) is a Godot rotation.y of yaw - 90 deg), then pitch, then roll
	# (roof to the right = clockwise seen from behind = negative rotation about the view axis)
	var basis := Basis.from_euler(Vector3(pitch, yaw - PI / 2.0, -roll), EULER_ORDER_YXZ)
	return {"transform": Transform3D(basis, eye), "fov": fov_deg, "gap": lerpf(cam_gap[i], cam_gap[j], w), "speed": speed,
		"yaw": yaw, "pitch": pitch, "roll": roll, "centre": centre}
