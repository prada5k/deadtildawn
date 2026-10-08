extends RefCounted
## A person standing still, holding a camcorder (a Sony VX2000-style handheld reference: movement only; the game
## is set in 1996). Visual only: it knows nothing about the game, and the user's camera pose is untouched.
##
## offset_transform(t) is a PURE FUNCTION OF TIME: the caller composes it with its stored reference pose every
## frame (reference * offset), so the motion can never accumulate or drift away from the approved framing.
##
## What it is made of (all smooth, none of it frame-to-frame random):
##   sway         slow organic yaw / pitch (two octaves of smooth value noise, about 0.2-0.5 Hz)
##   breathing    barely-there vertical and forward/back movement, a few mm, about 0.2 Hz
##   tremor       fine hand movement, much smaller than the sway (a few Hz, smooth)
##   corrections  every 6-14 s a small framing adjustment: the aim eases to a new nearby spot and SETTLES
##                (a critically damped step), then holds; the spots are bounded, so it never wanders off
## Everything fades in over the first FADE_IN_S so the first frame is exactly the reference pose.
##
## Frame (Godot camera, local): yaw about +Y, pitch about +X (positive looks up), roll about the view axis.
## All limits are exported so they can be tuned against the real 390 x 844 render.

const FADE_IN_S := 1.5

var seed_value := 1996
var sway_yaw_deg := 0.17
var sway_pitch_deg := 0.13
var sway_roll_deg := 0.05
var sway_hz := 0.23                  # base rate of the sway noise
var tremor_deg := 0.022              # about a tenth of the sway
var tremor_hz := 5.0
var breath_y_m := 0.003
var breath_z_m := 0.002
var breath_x_m := 0.002
var breath_hz := 0.21
var correction_yaw_deg := 0.12
var correction_pitch_deg := 0.09
var correction_min_gap_s := 6.0
var correction_max_gap_s := 14.0
var correction_settle_s := 0.22      # the time constant of the settling (critically damped)

var _events: Array[Dictionary] = []          # grip corrections: {t, yaw, pitch}, generated on demand, deterministic


## Integer hash -> [-1, 1]. (32-bit mixing, no engine randomness: the same inputs always give the same output.)
static func hash_unit(i: int, salt: int) -> float:
	var x := (i * 374761393 + salt * 668265263) & 0xFFFFFFFF
	x = ((x ^ (x >> 13)) * 1274126177) & 0xFFFFFFFF
	x = x ^ (x >> 16)
	return float(x & 0xFFFFFF) / 8388607.5 - 1.0


## Smooth value noise in [-1, 1] (quintic interpolation: continuous in value, slope and curvature).
static func smooth_noise(x: float, salt: int) -> float:
	var i := int(floor(x))
	var f := x - float(i)
	var u := f * f * f * (f * (f * 6.0 - 15.0) + 10.0)
	return lerpf(hash_unit(i, salt), hash_unit(i + 1, salt), u)


## Two octaves, so it does not read as one repeating wave.
static func organic(t: float, hz: float, salt: int) -> float:
	return 0.68 * smooth_noise(t * hz, salt) + 0.32 * smooth_noise(t * hz * 2.37 + 17.3, salt + 101)


func _ensure_events(t: float) -> void:
	var last_t: float = _events[_events.size() - 1]["t"] if not _events.is_empty() else 0.0
	while _events.is_empty() or last_t <= t + 20.0:
		var k := _events.size()
		var u := hash_unit(k, seed_value + 7) * 0.5 + 0.5                      # [0, 1]
		last_t += (3.0 + 5.0 * u) if k == 0 else (correction_min_gap_s + (correction_max_gap_s - correction_min_gap_s) * u)
		_events.append({"t": last_t, "yaw": hash_unit(k, seed_value + 11) * deg_to_rad(correction_yaw_deg),
			"pitch": hash_unit(k, seed_value + 13) * deg_to_rad(correction_pitch_deg)})


## The framing correction's (yaw, pitch) at time t, in radians: from the previous spot it eases to the latest event's
## spot and settles (critically damped), then holds until the next one. The spots are bounded, so it never wanders.
func correction(t: float) -> Vector2:
	_ensure_events(t)
	var previous := Vector2.ZERO
	var current := Vector2.ZERO
	for e in _events:
		if float(e["t"]) > t:
			break
		var x := (t - float(e["t"])) / correction_settle_s
		var settled := 1.0 - exp(-x) * (1.0 + x)                       # critically damped step response
		var target := Vector2(float(e["yaw"]), float(e["pitch"]))
		current = previous.lerp(target, settled)
		previous = target
	return current


## The camera's offset from its reference pose at time t: yaw / pitch / roll (rad) and a position offset (m, camera
## local axes). Zero at t = 0, fully on after FADE_IN_S.
func offset(t: float) -> Dictionary:
	var fade := smoothstep(0.0, FADE_IN_S, t)
	var corr := correction(t)
	var yaw := deg_to_rad(sway_yaw_deg) * organic(t, sway_hz, seed_value + 1) \
		+ deg_to_rad(tremor_deg) * organic(t, tremor_hz, seed_value + 2) + corr.x
	var pitch := deg_to_rad(sway_pitch_deg) * organic(t, sway_hz * 1.17, seed_value + 3) \
		+ deg_to_rad(tremor_deg) * organic(t, tremor_hz * 1.13, seed_value + 4) + corr.y
	var roll := deg_to_rad(sway_roll_deg) * organic(t, sway_hz * 0.83, seed_value + 5)
	var pos := Vector3(breath_x_m * organic(t, breath_hz * 0.7, seed_value + 6),
		breath_y_m * organic(t, breath_hz, seed_value + 7), breath_z_m * organic(t, breath_hz * 0.8, seed_value + 8))
	return {"yaw": yaw * fade, "pitch": pitch * fade, "roll": roll * fade, "pos": pos * fade}


## offset(t) as a transform to compose AFTER the reference pose: reference * offset_transform(t).
func offset_transform(t: float) -> Transform3D:
	var o := offset(t)
	return Transform3D(Basis.from_euler(Vector3(float(o["pitch"]), float(o["yaw"]), float(o["roll"])), EULER_ORDER_YXZ), o["pos"])
