extends Node2D
## A two-lane mountain road drawn from the track centerline:
##   curbs (outer edges, corners only): stripes in the corner's severity color
##   asphalt, white edge lines, dashed yellow center line (two lanes).
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

	# Dashed yellow center line: two lanes
	var k := 0
	while k < n - 1:
		var k1 := mini(k + DASH_M, n - 1)
		draw_polyline(points.slice(k, k1 + 1), CENTER_LINE, CENTER_W_M * px_per_m, true)
		k += DASH_M + GAP_M
