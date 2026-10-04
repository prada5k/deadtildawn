extends Node2D
## A two-lane mountain road drawn from the track centerline:
##   asphalt, white edge lines, dashed yellow center line (two lanes; a public
##   road at 3 a.m., no curbs), chevron signs along the outside of every corner
##   (Spire): the corner's severity color behind a black ">" pointing the way
##   the road turns, or a U-turn arrow for a hairpin.
## Feed it `points` (world px, 1 m apart), `corners` (replay corner dicts) and
## `px_per_m`, then add it to the tree. Everything is drawn once in _draw().

const ASPHALT := Color(0.2, 0.2, 0.215)
const EDGE_LINE := Color(0.93, 0.92, 0.9)
const CENTER_LINE := Color(0.96, 0.78, 0.15)

const ROAD_W_M := 8.0          # two 4 m lanes
const EDGE_LINE_W_M := 0.3
const CENTER_W_M := 0.35       # wider than real (0.1 m) so it reads when zoomed out
const DASH_M := 3              # centerline points are 1 m apart
const GAP_M := 6
const CHEVRON_EVERY_M := 10.0  # one sign about every 10 m through a corner...
const CHEVRONS_MIN := 3        # ...at least 3, at most 8
const CHEVRONS_MAX := 8
const SIGN_ACROSS_M := 4.2     # sign face, across the road (drawn big so it reads)
const SIGN_ALONG_M := 3.0      # ...and along it
const SIGN_OUT_M := 4.2        # sign center, past the edge of the asphalt
const CHEVRON_INK := Color(0.05, 0.04, 0.04)
const HAIRPIN_M := 25.0        # radius at or under this: the sign shows a U-turn
const POST_EVERY_M := 20       # reflector posts down both edges: they flick by, so speed reads
const POST_OUT_M := 1.0        # past the edge of the asphalt
const POST_M := 0.9            # post, seen from above (drawn big, like the cars, so it reads)
const POST_WHITE := Color(0.92, 0.92, 0.88)
const REFLECTOR := Color(1.0, 0.62, 0.15)

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
	# The chevron signs on their own node, unshaded: reflective signs read at
	# night (the moonlight's CanvasModulate doesn't dim them)
	var signs := Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	signs.material = mat
	signs.draw.connect(func():
		draw_posts(signs)
		for c in corners:
			draw_chevrons(signs, c, points.size()))
	add_child(signs)
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


## A row of chevron signs on the outside of one corner. The arrow points to
## the inside (the way the road goes): ">" in a right-hander as the driver
## sees it, "<" in a left-hander.
func draw_chevrons(on: CanvasItem, c: Dictionary, n: int) -> void:
	var s0 := float(c["s_start"])
	var s1 := float(c["s_end"])
	var count := clampi(int(round((s1 - s0) / CHEVRON_EVERY_M)), CHEVRONS_MIN, CHEVRONS_MAX)
	var inward := 1.0 if c["direction"] == "R" else -1.0     # +1 = toward the right of travel
	var col: Color = severity_color.call(int(c["severity"]))
	var out_m := ROAD_W_M / 2.0 + SIGN_OUT_M
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
		on.draw_colored_polygon(face, CHEVRON_INK)              # dark rim
		var inner := PackedVector2Array()
		for q in face:
			inner.append(center + (q - center) * 0.84)
		on.draw_colored_polygon(inner, col)
		if float(c["radius"]) <= HAIRPIN_M:
			draw_hairpin_arrow(on, center, u, w, a, b)
		else:
			# The arrow: tail corners on the back side, tip toward the inside
			on.draw_polyline(PackedVector2Array([center - u * a * 0.4 - w * b * 0.6, center + u * a * 0.42,
				center - u * a * 0.4 + w * b * 0.6]), CHEVRON_INK, 0.6 * px_per_m)




## The hairpin sign: an arrow that goes up the road, turns over the top the
## way the road goes, and comes back down (a U-turn). u: toward the inside
## (the way it turns), w: along the road (up the sign), both in px per m.
func draw_hairpin_arrow(on: CanvasItem, center: Vector2, u: Vector2, w: Vector2, a: float, b: float) -> void:
	var r := a * 0.3                                   # the U's radius (m)
	var top := center + w * b * 0.2                   # center of the turn over the top (+w = up the road)
	var pts := PackedVector2Array([center - u * r - w * b * 0.6])    # the near leg, from the bottom
	for k in 13:                                       # over the top, toward the inside
		var ang := PI * k / 12.0
		pts.append(top - u * r * cos(ang) + w * r * sin(ang))
	var tip := center + u * r - w * b * 0.25           # back down the far leg
	pts.append(tip)
	on.draw_polyline(pts, CHEVRON_INK, 0.5 * px_per_m)
	var head := 0.6                                    # arrowhead at the end, pointing back down
	on.draw_colored_polygon(PackedVector2Array([tip - w * head * 1.3, tip - u * head, tip + u * head]),
		CHEVRON_INK)


## Reflector posts every POST_EVERY_M down both edges (white post, amber
## reflector on the side facing traffic). Unshaded, so they catch the eye at
## night and tick past at a rate that says how fast you're going.
func draw_posts(on: CanvasItem) -> void:
	var half := ROAD_W_M / 2.0 + POST_OUT_M
	var k := POST_EVERY_M
	while k < points.size() - 1:
		var right := _right[k]
		var along := right.orthogonal()
		for side: float in [-1.0, 1.0]:
			var c := points[k] + right * side * half * px_per_m
			var r := POST_M / 2.0 * px_per_m
			on.draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), POST_WHITE)
			on.draw_circle(c - along * r * 0.6, r * 0.45, REFLECTOR)
		k += POST_EVERY_M

