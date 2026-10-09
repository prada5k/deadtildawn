extends RefCounted
## Read-only visual evaluation of replay v2's clamped C2 elevation spline.
## s is horizontal centerline distance, exactly as in the Python replay contract.

var elevated := false
var length := 0.0
var knots := PackedFloat64Array()
var heights := PackedFloat64Array()
var b := PackedFloat64Array()
var c := PackedFloat64Array()
var d := PackedFloat64Array()
var start_grade := 0.0
var end_grade := 0.0


func load_track(track: Dictionary, version: int) -> bool:
	if version == 1:
		return true
	var profile: Dictionary = track.get("elevation_profile", {})
	if profile.get("interpolation", "") != "clamped_cubic_spline_c2":
		return false
	var points = profile.get("samples", [])
	if typeof(points) != TYPE_ARRAY or points.size() < 2:
		return false
	start_grade = float(profile.get("start_grade", 0.0))
	end_grade = float(profile.get("end_grade", 0.0))
	if not is_finite(start_grade) or not is_finite(end_grade):
		return false
	for point in points:
		if typeof(point) != TYPE_ARRAY or point.size() != 2:
			return false
		var s := float(point[0])
		var z := float(point[1])
		if not is_finite(s) or not is_finite(z) or (not knots.is_empty() and s <= knots[-1]):
			return false
		knots.append(s)
		heights.append(z)
	if absf(knots[0]) > 0.000001:
		return false
	length = knots[-1]
	var n := knots.size()
	var h := PackedFloat64Array()
	var delta := PackedFloat64Array()
	var lower := PackedFloat64Array()
	var diagonal := PackedFloat64Array()
	var upper := PackedFloat64Array()
	var rhs := PackedFloat64Array()
	for array in [lower, diagonal, upper, rhs]:
		array.resize(n)
	for i in n - 1:
		var width := knots[i + 1] - knots[i]
		h.append(width)
		delta.append((heights[i + 1] - heights[i]) / width)
	diagonal[0] = 2.0 * h[0]
	upper[0] = h[0]
	rhs[0] = 6.0 * (delta[0] - start_grade)
	for i in range(1, n - 1):
		lower[i] = h[i - 1]
		diagonal[i] = 2.0 * (h[i - 1] + h[i])
		upper[i] = h[i]
		rhs[i] = 6.0 * (delta[i] - delta[i - 1])
	lower[n - 1] = h[n - 2]
	diagonal[n - 1] = 2.0 * h[n - 2]
	rhs[n - 1] = 6.0 * (end_grade - delta[n - 2])
	for i in range(1, n):
		var factor := lower[i] / diagonal[i - 1]
		diagonal[i] -= factor * upper[i - 1]
		rhs[i] -= factor * rhs[i - 1]
	var second := PackedFloat64Array()
	second.resize(n)
	second[n - 1] = rhs[n - 1] / diagonal[n - 1]
	for i in range(n - 2, -1, -1):
		second[i] = (rhs[i] - upper[i] * second[i + 1]) / diagonal[i]
	for i in n - 1:
		b.append(delta[i] - h[i] * (2.0 * second[i] + second[i + 1]) / 6.0)
		c.append(second[i] / 2.0)
		d.append((second[i + 1] - second[i]) / (6.0 * h[i]))
	elevated = true
	return true


## Returns [height, dz/ds]. Beyond the course, extend its endpoint tangent.
func at(s: float) -> Vector2:
	if not elevated:
		return Vector2.ZERO
	if s < 0.0:
		return Vector2(heights[0] + start_grade * s, start_grade)
	if s > length:
		return Vector2(heights[-1] + end_grade * (s - length), end_grade)
	var lo := 0
	var hi := knots.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if knots[mid] <= s:
			lo = mid
		else:
			hi = mid
	var t := s - knots[lo]
	return Vector2(heights[lo] + t * (b[lo] + t * (c[lo] + t * d[lo])),
		b[lo] + t * (2.0 * c[lo] + 3.0 * d[lo] * t))
