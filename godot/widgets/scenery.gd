extends Node2D
## The land around the road in the replay, dressed as a real SoCal place
## (docs/ART_DIRECTION.md, Replay). Top-down, drawn once, under the night's
## CanvasModulate (the headlights light it up as the cars pass):
##   coast:    PCH. Ocean on the west side with a cliff band and surf, Armco
##             where the road runs along the edge, coastal sage scrub inland.
##   canyon:   Malibu / Latigo. Rock walls cut into the hill on the inside of
##             corners, chaparral and oaks on the drop side.
##   mountain: Angeles Crest. Pines everywhere, and to the east the mountain
##             falls away to the valley: city lights far below.
## Glowing things (city lights) go on `glow_layer` so the night doesn't dim them.
## Feed points (world px, 1 m apart), corners (replay dicts), px_per_m,
## location, glow_layer, then add it to the tree.

const ROAD_HALF_M := 4.0
const GROUND := {"coast": Color(0.25, 0.23, 0.15), "canyon": Color(0.22, 0.18, 0.13),
	"mountain": Color(0.1, 0.14, 0.1)}
const OCEAN := Color(0.05, 0.1, 0.19)
const SURF := Color(0.85, 0.9, 0.95, 0.55)
const CLIFF := Color(0.3, 0.25, 0.21)
const ROCK := Color(0.38, 0.31, 0.26)
const ROCK_LIT := Color(0.52, 0.44, 0.36)
const ARMCO := Color(0.75, 0.76, 0.78)
const SCRUB := [Color(0.27, 0.3, 0.17), Color(0.33, 0.33, 0.2), Color(0.22, 0.25, 0.14)]
const CHAPARRAL := [Color(0.16, 0.22, 0.12), Color(0.2, 0.26, 0.14), Color(0.25, 0.27, 0.15)]
const OAK := [Color(0.12, 0.2, 0.1), Color(0.17, 0.28, 0.14)]
const PINE := [Color(0.05, 0.13, 0.08), Color(0.08, 0.18, 0.1)]
const VOID := Color(0.02, 0.02, 0.04)
const CITY := [Color(1.0, 0.75, 0.4), Color(1.0, 0.88, 0.6), Color(0.8, 0.88, 1.0)]

var points := PackedVector2Array()
var corners := []
var px_per_m := 4.0
var location := "canyon"
var glow_layer: Node = null      # an un-darkened layer for the city lights

var rng := RandomNumberGenerator.new()
var _right := PackedVector2Array()
var _grid := {}                  # coarse cells -> road points, for "is this near the road?"
var _cell := 1.0
var bounds := Rect2()
var edge := PackedVector2Array() # coast or drop-off line (top to bottom), if any
var edge_side := 0.0             # -1: west of edge is water/void, +1: east


func _ready() -> void:
	rng.seed = 96 + points.size()                   # same road -> same scenery
	_right.resize(points.size())
	bounds = Rect2(points[0], Vector2.ZERO)
	_cell = 20.0 * px_per_m
	for i in points.size():
		var a := points[maxi(i - 1, 0)]
		var b := points[mini(i + 1, points.size() - 1)]
		_right[i] = -(b - a).normalized().orthogonal()
		bounds = bounds.expand(points[i])
		var key := Vector2i(floori(points[i].x / _cell), floori(points[i].y / _cell))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(points[i])
	if location == "coast":
		edge = side_edge(-1.0, 24.0)
		edge_side = -1.0
	elif location == "mountain":
		edge = side_edge(1.0, 30.0)
		edge_side = 1.0
		add_city_lights()
	queue_redraw()


func m(x: float) -> float:
	return x * px_per_m


## Distance (px) from p to the nearest road centerline point, up to ~2 cells.
func road_distance(p: Vector2) -> float:
	var best := INF
	var key := Vector2i(floori(p.x / _cell), floori(p.y / _cell))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for q in _grid.get(key + Vector2i(dx, dy), []):
				best = minf(best, p.distance_to(q))
	return best


## A coastline / drop-off running top to bottom, `gap_m` beyond the road on
## one side (side -1 = west, +1 = east), wobbling a little, smoothed.
func side_edge(side: float, gap_m: float) -> PackedVector2Array:
	var step := m(20.0)
	var y0 := bounds.position.y - m(300.0)
	var y1 := bounds.end.y + m(300.0)
	var n := int((y1 - y0) / step) + 1
	var xs := []
	for i in n:
		var y := y0 + i * step
		var extreme := INF if side < 0 else -INF       # the road's westmost (or eastmost) x near this y
		var found := false
		for p in points:
			if absf(p.y - y) < m(60.0):
				extreme = minf(extreme, p.x) if side < 0 else maxf(extreme, p.x)
				found = true
		if not found:
			extreme = bounds.position.x if side < 0 else bounds.end.x
		xs.append(extreme + side * m(gap_m + rng.randf_range(0.0, 10.0)))
	var out := PackedVector2Array()
	for i in n:                                     # smooth: 5-point moving average
		var acc := 0.0
		var k := 0
		for j in range(maxi(i - 2, 0), mini(i + 3, n)):
			acc += float(xs[j])
			k += 1
		var x := acc / k
		out.append(Vector2(minf(x, float(xs[i])) if side < 0 else maxf(x, float(xs[i])), y0 + i * step))
	return out


## Lines along the road `d_m` off the edge, on one side (+1 right of travel), over point range.
func offset(i0: int, i1: int, side: float, d_m: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(i0, i1 + 1):
		out.append(points[i] + _right[i] * side * m(ROAD_HALF_M + d_m))
	return out


func _draw() -> void:
	var far := bounds.grow(m(500.0))
	draw_rect(far, GROUND[location])
	match location:
		"coast":
			draw_coast(far)
		"canyon":
			draw_canyon()
		"mountain":
			draw_mountain(far)


# ------------------------------------------------------------------ coast

func draw_coast(far: Rect2) -> void:
	var sea := PackedVector2Array(edge)
	sea.append(Vector2(far.position.x, edge[-1].y))
	sea.append(Vector2(far.position.x, edge[0].y))
	# Cliff band first (wider), then the sea over it, so the cliff shows as a lip
	var lip := PackedVector2Array()
	for p in edge:
		lip.append(p + Vector2(m(14.0), 0))
	lip.append(Vector2(far.position.x, edge[-1].y))
	lip.append(Vector2(far.position.x, edge[0].y))
	draw_colored_polygon(lip, CLIFF)
	draw_colored_polygon(sea, OCEAN)
	draw_polyline(edge, SURF, m(1.6), true)                   # surf on the rocks
	var swell := PackedVector2Array()
	for p in edge:
		swell.append(p - Vector2(m(9.0), 0))
	draw_polyline(swell, Color(SURF, 0.18), m(1.0), true)
	# Moonlight on the water: short glints in a band
	for i in 160:
		var y := rng.randf_range(edge[0].y, edge[-1].y)
		var x := edge_x(y) - m(rng.randf_range(30.0, 400.0))
		var w := m(rng.randf_range(2.0, 7.0))
		draw_line(Vector2(x, y), Vector2(x + w, y), Color(0.7, 0.8, 1.0, 0.25), m(0.4))
	# Armco wherever the road runs along the cliff, on the ocean side
	var run := []
	for i in points.size():
		var near := points[i].x - edge_x(points[i].y) < m(55.0)
		if near:
			run.append(i)
		if (not near or i == points.size() - 1) and run.size() > 5:
			var side := 1.0 if _right[int(run[0])].x < 0.0 else -1.0
			armco(int(run[0]), int(run[-1]), side)
		if not near:
			run = []
	scatter(SCRUB, 0.55, 1.0, 2.6, 2.0, 60.0, true)


func edge_x(y: float) -> float:
	var step := edge[1].y - edge[0].y
	var i := clampi(int((y - edge[0].y) / step), 0, edge.size() - 2)
	var f := clampf((y - edge[i].y) / step, 0.0, 1.0)
	return lerpf(edge[i].x, edge[i + 1].x, f)


func armco(i0: int, i1: int, side: float) -> void:
	var rail := offset(i0, i1, side, 1.0)
	draw_polyline(rail, Color(0, 0, 0, 0.45), m(0.7), true)    # shadow
	draw_polyline(rail, ARMCO, m(0.35), true)
	for k in range(0, rail.size(), 4):
		draw_circle(rail[k], m(0.25), ARMCO.darkened(0.4))


# ------------------------------------------------------------------ canyon

func draw_canyon() -> void:
	# Rock cut into the hill on the inside of every corner (and a bit beyond)
	for c in corners:
		var i0 := clampi(int(float(c["s_start"])) - 20, 0, points.size() - 1)
		var i1 := clampi(int(float(c["s_end"])) + 20, 0, points.size() - 1)
		var side := -1.0 if str(c["direction"]) == "L" else 1.0
		# On the inside of a tight corner the wall can't reach past the center
		var room := float(c["radius"]) - ROAD_HALF_M - 2.5
		rock_wall(i0, i1, side, clampf(room, 1.5, 14.0))
	scatter(CHAPARRAL, 0.75, 1.2, 3.2, 1.5, 55.0, true)
	scatter(OAK, 0.08, 3.0, 6.0, 6.0, 45.0, false)


func rock_wall(i0: int, i1: int, side: float, max_depth: float) -> void:
	var inner := offset(i0, i1, side, 1.2)
	var outer := PackedVector2Array()
	var n := inner.size()
	for k in n:
		var ramp := minf(k, n - 1 - k) / 12.0              # tapers in at both ends
		var depth := (6.0 + 8.0 * absf(sin(k * 0.13)) + rng.randf_range(0.0, 3.0)) * minf(ramp, 1.0)
		depth = minf(depth, max_depth)
		outer.append(points[i0 + k] + _right[i0 + k] * side * m(ROAD_HALF_M + 1.2 + depth))
	# A strip of small quads (one big polygon folds over itself in hairpins)
	for k in n - 1:
		draw_primitive(PackedVector2Array([inner[k], inner[k + 1], outer[k + 1], outer[k]]),
			PackedColorArray([ROCK, ROCK, ROCK, ROCK]), PackedVector2Array())
	draw_polyline(inner, ROCK_LIT, m(0.8), true)               # the cut face at the road
	for k in range(4, n - 4, 7):                               # cracks and ledges
		var a := inner[k].lerp(outer[k], 0.25)
		var b := inner[k].lerp(outer[k], rng.randf_range(0.6, 0.95))
		draw_line(a, b, ROCK.darkened(0.35), m(0.35))


# ------------------------------------------------------------------ mountain

func draw_mountain(far: Rect2) -> void:
	var drop := PackedVector2Array(edge)
	drop.append(Vector2(far.end.x, edge[-1].y))
	drop.append(Vector2(far.end.x, edge[0].y))
	draw_colored_polygon(drop, VOID)
	draw_polyline(edge, ROCK.darkened(0.2), m(3.0), true)      # the rim
	for k in range(0, edge.size(), 2):                         # boulders on the rim
		draw_circle(edge[k] + Vector2(rng.randf_range(-6, 2), rng.randf_range(-8, 8)) * px_per_m,
			m(rng.randf_range(1.0, 2.5)), ROCK.darkened(0.1))
	scatter(PINE, 0.9, 2.0, 4.0, 3.0, 70.0, false, true)


func add_city_lights() -> void:
	if glow_layer == null:
		return
	var lights := Node2D.new()
	lights.z_index = -50
	var dots := []
	for cluster in 14:
		var cy := rng.randf_range(edge[0].y + m(200.0), edge[-1].y - m(200.0))
		var cx := edge_x_from(cy) + m(rng.randf_range(80.0, 420.0))
		for d in 70:
			# a loose street grid: dots snap to 8 m lines
			var p := Vector2(cx + m(rng.randf_range(-70.0, 70.0)), cy + m(rng.randf_range(-50.0, 50.0)))
			if rng.randf() < 0.5:
				p.x = cx + m(snappedf((p.x - cx) / px_per_m, 8.0))
			else:
				p.y = cy + m(snappedf((p.y - cy) / px_per_m, 8.0))
			dots.append([p, CITY[rng.randi() % CITY.size()], m(rng.randf_range(1.2, 2.6))])
	lights.draw.connect(func():
		for d in dots:
			lights.draw_circle(d[0], d[2] * 2.2, Color(d[1], 0.18))
			lights.draw_circle(d[0], d[2], d[1]))
	glow_layer.add_child(lights)


func edge_x_from(y: float) -> float:
	var step := edge[1].y - edge[0].y
	var i := clampi(int((y - edge[0].y) / step), 0, edge.size() - 1)
	return edge[i].x


# ------------------------------------------------------------------ plants

## Plants along both sides of the road: every `spacing_m` along it, chance
## `density` per side, radius r0..r1 m, clear of the road, d up to `reach_m`.
## Never on the water / past the drop. pines = draw as spiky stars.
func scatter(palette: Array, density: float, r0: float, r1: float, spacing_m: float, reach_m: float,
		clumps: bool, pines := false) -> void:
	var clear := m(ROAD_HALF_M + 3.0)
	var step := maxi(int(spacing_m), 1)
	for i in range(0, points.size(), step):
		for side: float in [-1.0, 1.0]:
			if rng.randf() > density:
				continue
			var d := m(rng.randf_range(ROAD_HALF_M + 3.0, reach_m))
			var pos := points[i] + _right[i] * side * d + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)) * px_per_m
			if road_distance(pos) < clear:
				continue
			if edge_side != 0.0 and edge.size() > 1 and (pos.x - edge_x(pos.y)) * edge_side > -m(4.0):
				continue                                           # in the sea / over the edge
			var r := m(rng.randf_range(r0, r1))
			var col: Color = palette[rng.randi() % palette.size()]
			if pines:
				pine(pos, r, col)
			else:
				draw_circle(pos + Vector2(r * 0.3, r * 0.35), r, Color(0, 0, 0, 0.35))   # shadow
				draw_circle(pos, r, col)
				if clumps:
					draw_circle(pos + Vector2(-r * 0.6, r * 0.2), r * 0.7, col.darkened(0.1))
				draw_circle(pos - Vector2(r * 0.3, r * 0.3), r * 0.5, col.lightened(0.12))


func pine(pos: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var spikes := 9
	for k in spikes * 2:
		var a := TAU * k / (spikes * 2) + rng.randf_range(-0.1, 0.1)
		pts.append(pos + Vector2.from_angle(a) * (r if k % 2 == 0 else r * 0.55))
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(r * 0.35, r * 0.4))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.4))
	draw_colored_polygon(pts, col)
	draw_circle(pos - Vector2(r * 0.15, r * 0.15), r * 0.3, col.lightened(0.15))
