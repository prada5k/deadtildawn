extends RefCounted
## An aging fluorescent tube: mostly steady, with an occasional short stutter. level(t) is a PURE FUNCTION OF TIME
## in [floor_level, 1]: a faint constant instability plus infrequent BURSTS of 2-4 brief dips. Dips are soft-edged
## (a few ms), never reach black (floor_level), and never strobe (bursts are seconds apart and under a second long).
## Deterministic: the same time always gives the same level. Multiply a light's energy and its tube's emission by it.

var seed_value := 7
var first_burst_s := 4.0              # the first stutter, so a quick look at HOME sees one
var min_gap_s := 14.0                 # then one every 14-34 s (infrequent)
var max_gap_s := 34.0
var floor_level := 0.4                # never darker than this (the room stays readable, no blackout)
var hum := 0.02                       # a faint constant instability, +-2%

const Handheld := preload("res://widgets/handheld_motion.gd")

var _bursts: Array[Array] = []                # each burst: Array of dips [start_s, duration_s, level]
var _burst_ends: Array[float] = []


func _unit(i: int, salt: int) -> float:
	return Handheld.hash_unit(i, seed_value + salt) * 0.5 + 0.5      # [0, 1]


func _ensure(t: float) -> void:
	var cursor: float = _burst_ends[_burst_ends.size() - 1] if not _burst_ends.is_empty() else 0.0
	while cursor <= t + 30.0:
		var k := _bursts.size()
		var start := (first_burst_s + 2.0 * _unit(0, 3)) if k == 0 else cursor + min_gap_s + (max_gap_s - min_gap_s) * _unit(k, 3)
		var dips: Array = []
		var at := start
		for d in 2 + int(_unit(k, 5) * 3.0):                          # 2, 3 or 4 dips
			var duration := 0.04 + 0.06 * _unit(k * 8 + d, 7)
			dips.append([at, duration, lerpf(0.45, 0.85, _unit(k * 8 + d, 9))])
			at += duration + 0.06 + 0.16 * _unit(k * 8 + d, 11)
		_bursts.append(dips)
		cursor = at
		_burst_ends.append(cursor)


## The tube's brightness multiplier at time t.
func level(t: float) -> float:
	_ensure(t)
	var out := 1.0 + hum * Handheld.smooth_noise(t * 7.0, seed_value + 21)
	for i in _bursts.size():
		if _burst_ends[i] < t - 1.0:
			continue
		if float(_bursts[i][0][0]) > t + 1.0:
			break
		for dip: Array in _bursts[i]:
			var w := smoothstep(float(dip[0]), float(dip[0]) + 0.012, t) * (1.0 - smoothstep(float(dip[0]) + float(dip[1]), float(dip[0]) + float(dip[1]) + 0.03, t))
			out = minf(out, lerpf(1.0, float(dip[2]), w))
	return clampf(out, floor_level, 1.0 + hum)
