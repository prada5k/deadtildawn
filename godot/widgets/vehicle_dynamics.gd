extends RefCounted
## Visual-only vehicle dynamics for replay footage: how a road car's BODY moves, derived from a recorded run.
## Reusable for any vehicle visual (the subject car and the camera car use the same layer with their own
## parameters).
##
## WHAT IS MEASURED vs APPROXIMATED
##   input (recorded by the sim):   time t, distance s, heading h, speed v    -> nothing here changes them
##   derived from the input:        longitudinal accel a_x = dv/dt
##                                  yaw rate r = dh/dt;  lateral accel a_y = v * r;  path curvature k = r / v
##   approximated (visual only):    body roll / pitch = a damped second-order response to a_y / a_x
##                                  front steer = atan(wheelbase * k) (kinematic / Ackermann, NO steering was recorded)
##                                  heave = road-texture micro-motion (artistic: the road has no roughness data)
## Nothing here simulates individual springs or dampers: no spring, damper or elevation data exists.
##
## DETERMINISM: every series is computed ONCE, up front, on a fixed 1/60 s grid with fixed sub-steps, from the
## recorded arrays only. at(t) is a pure function of playback time, so pause, seek, restart and playback speed
## can never change what the body does at a given moment, and nothing depends on the frame rate.
##
## Frame (matches the car models: nose +X, up +Y, right +Z):
##   roll  > 0  tilts the roof to the car's right (rotation about +X);  a left turn gives roll > 0 (leans outward)
##   pitch > 0  lifts the nose (rotation about +Z);  braking gives pitch < 0 (dive), accelerating pitch > 0 (squat)
##   steer > 0  turns the front wheels to the left (rotation about +Y)

const GRID_S := 1.0 / 60.0
const SUBSTEPS := 4                    # integration sub-steps per grid step (1/240 s): fixed, never frame-dependent
const DIFF_WINDOW_S := 0.12            # accelerations are central differences over +-this (smooth, not sample-noisy)
const G := 9.81

# ---- parameters (per vehicle visual; defaults = a 1990s FWD compact on road springs) ----
var roll_deg_per_g := 4.0              # steady-state body roll per g of lateral acceleration (restrained road car)
var roll_limit_deg := 6.0
var pitch_deg_per_g := 1.6             # steady-state pitch per g of longitudinal acceleration
var pitch_limit_deg := 2.4
var roll_freq_hz := 1.3                # the body's natural frequencies and damping ratios (road-car feel: a little overshoot)
var roll_zeta := 0.5
var pitch_freq_hz := 1.5
var pitch_zeta := 0.5
var wheelbase_m := 2.6                 # measured from the model's wheel positions by the viewer
var steer_limit_deg := 32.0
var heave_amp_m := 0.004               # peak road-texture micro-motion at speed (ARTISTIC)
var heave_speed_ms := 30.0             # speed at which the micro-motion reaches full amplitude

# ---- results, on the grid ----
var t0 := 0.0
var count := 0
var a_long := PackedFloat64Array()     # m/s^2
var a_lat := PackedFloat64Array()      # m/s^2, + = to the left
var steer := PackedFloat64Array()      # rad
var roll := PackedFloat64Array()       # rad
var pitch := PackedFloat64Array()      # rad
var heave := PackedFloat64Array()      # m


## Linear interpolation of a sampled series at time tq (clamped to the ends). `hint` speeds up the search.
static func lerp_series(ts: PackedFloat64Array, vals: PackedFloat64Array, tq: float) -> float:
	var n := ts.size()
	if tq <= ts[0]:
		return vals[0]
	if tq >= ts[n - 1]:
		return vals[n - 1]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:                                  # binary search: a replay is ~2000 samples
		var mid := (lo + hi) >> 1
		if ts[mid] <= tq:
			lo = mid
		else:
			hi = mid
	var span := ts[hi] - ts[lo]
	return vals[lo] if span <= 0.0 else lerpf(vals[lo], vals[hi], (tq - ts[lo]) / span)


## Build from a recorded run: ts (s), ss (m), hs (rad, CCW from east), vs (m/s). Arrays may be sparse and uneven
## (a replay sample is every 0.5 m of road: seconds apart at launch).
func build(ts_in: Array, ss_in: Array, hs_in: Array, vs_in: Array) -> void:
	var n := ts_in.size()
	var ts := PackedFloat64Array()
	var ss := PackedFloat64Array()
	var hs := PackedFloat64Array()
	var vs := PackedFloat64Array()
	ts.resize(n); ss.resize(n); hs.resize(n); vs.resize(n)
	var prev_h := float(hs_in[0])
	var unwrapped := prev_h
	for i in n:
		ts[i] = float(ts_in[i])
		ss[i] = float(ss_in[i])
		vs[i] = float(vs_in[i])
		var h := float(hs_in[i])
		unwrapped += wrapf(h - prev_h, -PI, PI)         # continuous heading, no 2*pi jumps
		prev_h = h
		hs[i] = unwrapped
	t0 = ts[0]
	var t_end := ts[n - 1]
	count = int(ceil((t_end - t0) / GRID_S)) + 1
	for arr: PackedFloat64Array in [a_long, a_lat, steer, roll, pitch, heave]:
		arr.resize(count)

	var roll_target := PackedFloat64Array()
	var pitch_target := PackedFloat64Array()
	roll_target.resize(count)
	pitch_target.resize(count)
	for k in count:
		var t := t0 + k * GRID_S
		var w0 := maxf(t - DIFF_WINDOW_S, t0)
		var w1 := minf(t + DIFF_WINDOW_S, t_end)
		var width := maxf(w1 - w0, 1e-6)
		var ax := (lerp_series(ts, vs, w1) - lerp_series(ts, vs, w0)) / width
		var yaw_rate := (lerp_series(ts, hs, w1) - lerp_series(ts, hs, w0)) / width
		var v := lerp_series(ts, vs, t)
		var ay := v * yaw_rate
		a_long[k] = ax
		a_lat[k] = ay
		# kinematic steering: delta = atan(L * kappa), kappa = yaw_rate / v; faded in above walking pace
		var kappa := yaw_rate / maxf(v, 0.5)
		var fade := clampf((v - 0.5) / 2.0, 0.0, 1.0)
		steer[k] = clampf(atan(wheelbase_m * kappa) * fade, -deg_to_rad(steer_limit_deg), deg_to_rad(steer_limit_deg))
		roll_target[k] = clampf(deg_to_rad(roll_deg_per_g) * (ay / G), -deg_to_rad(roll_limit_deg), deg_to_rad(roll_limit_deg))
		pitch_target[k] = clampf(deg_to_rad(pitch_deg_per_g) * (ax / G), -deg_to_rad(pitch_limit_deg), deg_to_rad(pitch_limit_deg))
		# road-texture heave: a few incommensurate waves of DISTANCE (so a bump belongs to a place on the road),
		# growing with speed. Artistic: no roughness data exists.
		var s := lerp_series(ts, ss, t)
		var texture := 0.55 * sin(s * 2.31 + 0.7) + 0.3 * sin(s * 5.17 + 2.1) + 0.15 * sin(s * 11.9 + 4.4)
		heave[k] = heave_amp_m * clampf(v / heave_speed_ms, 0.0, 1.0) * texture
	integrate_response(roll_target, roll, roll_freq_hz, roll_zeta)
	integrate_response(pitch_target, pitch, pitch_freq_hz, pitch_zeta)


## x'' = w^2 (target - x) - 2 zeta w x'   (a damped second-order body response), semi-implicit Euler at a fixed step,
## starting at rest. The target between grid points is interpolated linearly.
func integrate_response(target: PackedFloat64Array, out: PackedFloat64Array, freq_hz: float, zeta: float) -> void:
	var w := TAU * freq_hz
	var dt := GRID_S / SUBSTEPS
	var x := 0.0
	var xd := 0.0
	out[0] = 0.0
	for k in range(1, count):
		for sub in SUBSTEPS:
			var f := (sub + 1.0) / SUBSTEPS
			var tgt := lerpf(target[k - 1], target[k], f)
			xd += (w * w * (tgt - x) - 2.0 * zeta * w * xd) * dt
			x += xd * dt
		out[k] = x


func grid_value(arr: PackedFloat64Array, t: float) -> float:
	var f := clampf((t - t0) / GRID_S, 0.0, float(count - 1))
	var i := int(f)
	if i >= count - 1:
		return arr[count - 1]
	return lerpf(arr[i], arr[i + 1], f - i)


## The body state at playback time t (a pure function of t).
func at(t: float) -> Dictionary:
	return {
		"roll": grid_value(roll, t), "pitch": grid_value(pitch, t), "steer": grid_value(steer, t),
		"heave": grid_value(heave, t), "a_long_g": grid_value(a_long, t) / G, "a_lat_g": grid_value(a_lat, t) / G,
	}


## Extremes for the self-test / report.
func summary() -> Dictionary:
	var out := {"roll_deg": 0.0, "pitch_min_deg": 0.0, "pitch_max_deg": 0.0, "steer_deg": 0.0, "a_lat_g": 0.0, "a_long_min_g": 0.0, "a_long_max_g": 0.0}
	for k in count:
		out["roll_deg"] = maxf(out["roll_deg"], absf(rad_to_deg(roll[k])))
		out["pitch_min_deg"] = minf(out["pitch_min_deg"], rad_to_deg(pitch[k]))
		out["pitch_max_deg"] = maxf(out["pitch_max_deg"], rad_to_deg(pitch[k]))
		out["steer_deg"] = maxf(out["steer_deg"], absf(rad_to_deg(steer[k])))
		out["a_lat_g"] = maxf(out["a_lat_g"], absf(a_lat[k]) / G)
		out["a_long_min_g"] = minf(out["a_long_min_g"], a_long[k] / G)
		out["a_long_max_g"] = maxf(out["a_long_max_g"], a_long[k] / G)
	return out
