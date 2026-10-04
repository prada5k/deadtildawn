extends Node2D
## A two-lane mountain road drawn from the track centerline:
##   curbs (outer edges, corners only): stripes in the corner's severity color
##   asphalt, white edge lines, dashed yellow center line (two lanes),
##   chevron signs along the outside of every corner (Spire): the corner's
##   severity color behind a black ">" pointing the way the road turns.
## Feed it `points` (world px, 1 m apart), `corners` (replay corner dicts) and
## `px_per_m`, then add it to the tree. Everything is drawn once in _draw().

const ASPHALT := Color(0.2, 0.2, 0.215)
const EDGE_LINE := Color(0.93, 0.92, 0.9)
const CENTER_LINE := Color(0.96, 0.78, 0.15)
const CURB_LIGHT := Color(0.976, 0.957, 0.961)     # #F9F4F5

const ROAD_W_M := 8.0          # two 4 m lanes
const EDGE_LINE_W_M := 0.3
const CENTER_W_M := 0.35       # wider than real (0.1 m) so it reads when zoomed out
const DASH_M := 3              # centerline points are 1 m apart
const GAP_M := 6
const CURB_W_M := 1.2
const CURB_STRIPE_M := 2       # alternate color / white every 2 m
const CHEVRON_EVERY_M := 10.0  # one sign about every 10 m through a corner...
const CHEVRONS_MIN := 3        # ...at least 3, at most 8
const CHEVRONS_MAX := 8
const SIGN_ACROSS_M := 2.6     # sign face, across the road (drawn big so it reads)
const SIGN_ALONG_M := 1.9      # ...and along it
const SIGN_OUT_M := 2.2        # sign center, past the curb
const CHEVRON_INK := Color(0.05, 0.04, 0.04)

var points := PackedVector2Array()
var corners := []
var px_per_m := 4.0
var severity_color: Callable   # int -> Color

var _right := PackedVector2Array()   # unit normal pointing to the right of travel


func _ready() -> void:
	_right.resize(points.size())
	for i in points.size():
		var a := points[maxi(i - 1, 0)]
		var b := points[mini(i + 1, points.size() - 1)]
		_right[i] = -(b - a).normalized().orthogonal()   # orthogonal() = left of travel on screen
	queue_redraw()


func offset_line(i0: int, i1: int, d_m: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(i0, i1 + 1):
		out.append(points[i] + _right[i] * d_m * px_per_m)
	return out


func _draw() -> void:
	var n := points.size()
	if n < 2:
		return
	var half := ROAD_W_M / 2.0

	# Curbs on both edges through every corner, striped severity color / white
	for c in corners:
		var i0 := clampi(int(floor(float(c["s_start"]))), 0, n - 1)
		var i1 := clampi(int(ceil(float(c["s_end"]))), 0, n - 1)
		var col: Color = severity_color.call(int(c["severity"]))
		for side: float in [-1.0, 1.0]:   # typed: array elements have no type
			var d := side * (half + CURB_W_M / 2.0)
			var k := i0
			var stripe := 0
			while k < i1:
				var k1 := mini(k + CURB_STRIPE_M, i1)
				draw_polyline(offset_line(k, k1, d), col if stripe % 2 == 0 else CURB_LIGHT,
					CURB_W_M * px_per_m, true)
				k = k1
				stripe += 1

	# Asphalt
	draw_polyline(points, ASPHALT, ROAD_W_M * px_per_m, true)

	# White edge lines, just inside each edge
	for side: float in [-1.0, 1.0]:   # typed: array elements have no type
		draw_polyline(offset_line(0, n - 1, side * (half - 0.35)), EDGE_LINE,
			EDGE_LINE_W_M * px_per_m, true)

	# Chevron signs on the outside of each corner
	for c in corners:
		draw_chevrons(c, n)

	# Dashed yellow center line: two lanes
	var k := 0
	while k < n - 1:
		var k1 := mini(k + DASH_M, n - 1)
		draw_polyline(points.slice(k, k1 + 1), CENTER_LINE, CENTER_W_M * px_per_m, true)
		k += DASH_M + GAP_M


## A row of chevron signs on the outside of one corner. The arrow points to
## the inside (the way the road goes): ">" in a right-hander as the driver
## sees it, "<" in a left-hander.
func draw_chevrons(c: Dictionary, n: int) -> void:
	var s0 := float(c["s_start"])
	var s1 := float(c["s_end"])
	var count := clampi(int(round((s1 - s0) / CHEVRON_EVERY_M)), CHEVRONS_MIN, CHEVRONS_MAX)
	var inward := 1.0 if c["direction"] == "R" else -1.0     # +1 = toward the right of travel
	var col: Color = severity_color.call(int(c["severity"]))
	var out_m := ROAD_W_M / 2.0 + CURB_W_M + SIGN_OUT_M
	for k in count:
		var s := s0 + (s1 - s0) * (k + 0.5) / count
		var i := clampi(int(round(s)), 0, n - 1)
		var right := _right[i]
		var along := right.orthogonal()                         # direction of travel
		var center := points[i] - right * inward * out_m * px_per_m
		var u := right * inward * px_per_m                      # +u: the way the road turns
		var w := along * px_per_m
		var a := SIGN_ACROSS_M / 2.0
		var b := SIGN_ALONG_M / 2.0
		var face := PackedVector2Array([center - u * a - w * b, center + u * a - w * b,
			center + u * a + w * b, center - u * a + w * b])
		draw_colored_polygon(face, CHEVRON_INK)                 # dark rim
		var inner := PackedVector2Array()
		for q in face:
			inner.append(center + (q - center) * 0.84)
		draw_colored_polygon(inner, col)
		# The arrow: tail corners on the back side, tip toward the inside
		draw_polyline(PackedVector2Array([center - u * a * 0.45 - w * b * 0.62, center + u * a * 0.45,
			center - u * a * 0.45 + w * b * 0.62]), CHEVRON_INK, 0.42 * px_per_m)

