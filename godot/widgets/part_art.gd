@tool
extends Control
## A part's picture (Spire: "give parts their own pictures"), drawn in code
## like a sticker in a 90s parts catalog: flat colors, a thick ink outline.
## Every part in data/parts/catalog.json has its own drawing (a 4-1 header
## isn't a 4-2-1; forged wheels aren't the lightweight ones); an unknown id
## draws a plain box. No image files: like the cars, it's all code.
##
## Set `part_id` (and `halo`, the rarity color glowing behind it, or
## transparent for none). Drawn in a 100 x 100 box scaled to fit the control.
## Colors come from the theme variation (PartArt), like the other drawn
## widgets; DEFAULTS if it's missing.

@export var part_id := "":
	set(v):
		part_id = v
		queue_redraw()
@export var halo := Color(0, 0, 0, 0):
	set(v):
		halo = v
		queue_redraw()
## The rarity's name (common / rare / epic / legendary): a picture at
## GLOW_DIR/<rarity>.png replaces the drawn glow (Spire's halftone art).
@export var rarity := "":
	set(v):
		rarity = v
		queue_redraw()
var glow_spin := 0.0:            # the glow turning (radians; the reveal animates it)
	set(v):
		glow_spin = v
		queue_redraw()
var glow_scale := 1.0:           # and breathing
	set(v):
		glow_scale = v
		queue_redraw()

const GLOW_DIR := "res://textures/glow/"
const RAYS := {"rare": 0, "epic": 12, "legendary": 18}   # the burst behind the better pulls

const DEFAULTS := {
	"ink": Color(0.102, 0.078, 0.086),
	"metal": Color(0.74, 0.75, 0.77),
	"metal_dark": Color(0.38, 0.39, 0.42),
	"rubber": Color(0.16, 0.15, 0.16),
	"red": Color(0.78, 0.16, 0.14),
	"yellow": Color(0.96, 0.78, 0.18),
	"bronze": Color(0.66, 0.5, 0.26),
	"carbon": Color(0.14, 0.14, 0.16),
	"paper": Color(0.93, 0.9, 0.82),
}

const IMAGE_DIR := "res://textures/parts/"   # <part id>.png here replaces the drawing (docs/PART_IMAGES.md)
static var _images := {}         # part id -> Texture2D, or null (none): looked up once

var _s := 1.0                    # px per unit of the 100-unit box
var _o := Vector2.ZERO           # where the box starts
var _lw := 2.0                   # ink line width (px)


func _ready() -> void:
	resized.connect(queue_redraw)


func col(name: String) -> Color:
	return get_theme_color(name) if has_theme_color(name) else DEFAULTS[name]


func p(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _s


func pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for a: Vector2 in arr:
		out.append(p(a.x, a.y))
	return out


## A filled shape with an ink outline.
func blob(arr: Array, fill: Color) -> void:
	var poly := pts(arr)
	draw_colored_polygon(poly, fill)
	poly.append(poly[0])
	draw_polyline(poly, col("ink"), _lw, true)


## A pipe / bar / wire along points: ink underneath, color on top.
func tube(arr: Array, w: float, fill: Color) -> void:
	var line := pts(arr)
	draw_polyline(line, col("ink"), w * _s + 2.0 * _lw, true)
	for q in [line[0], line[-1]]:
		draw_circle(q, (w * _s) / 2.0 + _lw, col("ink"))
	draw_polyline(line, fill, w * _s, true)
	for q in [line[0], line[-1]]:
		draw_circle(q, (w * _s) / 2.0, fill)


func disc(c: Vector2, r: float, fill: Color) -> void:
	draw_circle(p(c.x, c.y), r * _s + _lw, col("ink"))
	draw_circle(p(c.x, c.y), r * _s, fill)


## A gear: teeth between r_in and r_out.
func gear(c: Vector2, r_in: float, r_out: float, teeth: int, fill: Color) -> void:
	var arr := []
	for k in teeth * 4:
		var a := TAU * k / (teeth * 4)
		var r := r_out if k % 4 in [1, 2] else r_in
		arr.append(c + Vector2.from_angle(a) * r)
	blob(arr, fill)


func box(x0: float, y0: float, x1: float, y1: float, fill: Color) -> void:
	blob([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)], fill)


func text(s: String, at: Vector2, size_u: float, color: Color) -> void:
	var font: Font = get_theme_font("font") if has_theme_font("font") else ThemeDB.fallback_font
	var fs := maxi(int(size_u * _s), 6)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, p(at.x, at.y) - Vector2(w / 2.0, -fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw() -> void:
	_s = minf(size.x, size.y) / 100.0
	_o = (size - Vector2(100, 100) * _s) / 2.0
	_lw = maxf(1.2, 2.0 * _s)
	if halo.a > 0.0:                                 # the rarity, glowing behind it
		draw_glow()
	var img := image_for(part_id)
	if img != null:                                  # the real (cartoonized) picture, fit and centered
		var side := minf(size.x, size.y)
		draw_texture_rect(img, Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side)), false)
		return
	match part_id:
		"intake_short_ram":
			tube([Vector2(10, 30), Vector2(46, 30), Vector2(58, 40), Vector2(60, 52)], 10, col("metal"))
			filter_cone(Vector2(60, 56), 1.0)
		"intake_cold_air":
			tube([Vector2(10, 22), Vector2(50, 22), Vector2(68, 30), Vector2(70, 52), Vector2(58, 66), Vector2(44, 68)],
				10, col("metal"))
			filter_cone(Vector2(42, 72), 0.85)
		"header_421":
			header(false)
		"header_41_race":
			header(true)
		"cams_street":
			cams(false)
		"cams_race":
			cams(true)
		"ecu_street_tune":
			box(16, 24, 84, 80, col("metal_dark"))
			box(10, 38, 18, 66, col("rubber"))                  # the plug
			for k in 5:
				box(11, 40.0 + k * 5.0, 15, 42.0 + k * 5.0, col("metal"))
			box(30, 34, 72, 56, col("paper"))                   # the tuner's sticker
			text("TUNED", Vector2(51, 45), 10, col("red"))
			box(36, 62, 54, 74, col("rubber"))                  # the chip
		"flywheel_light":
			gear(Vector2(50, 50), 42, 46, 48, col("metal_dark"))
			disc(Vector2(50, 50), 40, col("metal"))
			for k in 6:                                         # lightening holes
				disc(Vector2(50, 50) + Vector2.from_angle(TAU * k / 6.0 + 0.5) * 26.0, 6.5, col("paper"))
			disc(Vector2(50, 50), 11, col("metal_dark"))
			for k in 6:
				disc(Vector2(50, 50) + Vector2.from_angle(TAU * k / 6.0) * 7.0, 1.4, col("ink"))
		"shifter_short":
			shifter(false)
		"shifter_race":
			shifter(true)
		"fd_44":
			final_drive("4.4")
		"fd_49":
			final_drive("4.9")
		"tires_300tw":
			tire(36, false)
		"tires_200tw":
			tire(18, false)
		"tires_r_comp":
			tire(0, true)
		"wheels_light":
			wheel(7, col("metal"), 5.0)
		"wheels_forged":
			wheel(10, col("bronze"), 3.2)
		"rsb_19":
			sway_bar(7.0, "19 MM")
		"rsb_24":
			sway_bar(10.0, "24 MM")
		"springs_lowering":
			coil(col("red"), 30, 70, 10, 92)
		"coilovers_street":
			disc(Vector2(50, 12), 9, col("metal_dark"))          # top mount
			box(44, 16, 56, 94, col("metal_dark"))              # the shock body
			box(47, 16, 53, 40, col("metal"))
			coil(col("yellow"), 32, 68, 26, 78)
			box(34, 76, 66, 82, col("red"))                     # the adjuster collars
			box(36, 22, 64, 27, col("red"))
		"interior_strip":
			blob([Vector2(12, 46), Vector2(20, 30), Vector2(80, 30), Vector2(88, 46), Vector2(88, 78), Vector2(12, 78)],
				col("metal_dark"))                              # the rear bench
			box(12, 60, 88, 78, col("rubber"))
			tube([Vector2(18, 22), Vector2(82, 86)], 5, col("red"))   # crossed out in Sharpie
			tube([Vector2(82, 22), Vector2(18, 86)], 5, col("red"))
			text("-40 KG", Vector2(50, 96), 13, col("ink"))
		"hood_carbon":
			hood()
		"seats_buckets":
			blob([Vector2(28, 92), Vector2(26, 70), Vector2(34, 66), Vector2(30, 12), Vector2(50, 6), Vector2(66, 14),
				Vector2(66, 62), Vector2(82, 66), Vector2(84, 84), Vector2(72, 92)], col("rubber"))
			tube([Vector2(36, 18), Vector2(40, 62)], 3, col("red"))  # bolster stitching
			for y: float in [24.0, 40.0]:                       # harness slots
				box(42, y, 56, y + 6, col("ink"))
		_:
			box(20, 26, 80, 80, Color(0.62, 0.48, 0.32))         # an unknown part: a box
			text("?", Vector2(50, 54), 30, col("ink"))


## The glow behind the part: Spire's picture for the rarity if there is one
## (turning slowly), else a halftone glow drawn here: a soft core, a burst of
## rays for epic and up, and print dots that shrink toward the edge.
func draw_glow() -> void:
	var c := p(50, 50)
	var tex := load_image(GLOW_DIR + rarity + ".png", "glow:" + rarity) if rarity != "" else null
	if tex != null:
		var side := minf(size.x, size.y) * 1.25 * glow_scale     # a bit past the edges: no hard corners
		draw_set_transform(c, glow_spin, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-Vector2(side, side) / 2.0, Vector2(side, side)), false, Color(1, 1, 1, halo.a))
		draw_set_transform(Vector2.ZERO)
		return
	var r_max := 64.0 * glow_scale                                  # spills past the picture
	for k in 4:                                                    # the soft core
		draw_circle(c, (14.0 + k * 7.0) * glow_scale * _s, Color(halo, halo.a * 0.10))
	var rays: int = RAYS.get(rarity, 0)
	for k in rays:                                                 # the burst, every other wedge
		var a0 := glow_spin + TAU * k / rays
		var a1 := a0 + TAU / rays * 0.45
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * r_max * 1.3 * _s,
			c + Vector2.from_angle(a1) * r_max * 1.3 * _s]), Color(halo, halo.a * 0.16))
	var step := 4.2                                                # halftone: a dot grid at 45 degrees
	var n := int(r_max / step) + 1
	var rot := Vector2.from_angle(PI / 4.0)
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var q := Vector2(i, j) * step
			q = Vector2(q.x * rot.x - q.y * rot.y, q.x * rot.y + q.y * rot.x)
			var d := q.length() / r_max
			if d >= 1.0:
				continue
			var dot_r := step * 0.48 * (1.0 - d) * (1.0 - d)            # big in the middle, gone at the edge
			if dot_r * _s > 0.4:
				draw_circle(c + q * _s, dot_r * _s, Color(halo, halo.a * 0.55))


## The image for a part, if one's been made: imported (the editor / F5), or a
## loose PNG (just dropped in, not imported yet). Looked up once per id.
static func image_for(id: String) -> Texture2D:
	if id == "":
		return null
	return load_image(IMAGE_DIR + id + ".png", id)


## A picture at `path` (imported, or a loose PNG not imported yet), or null;
## looked up once and remembered under `key`.
static func load_image(path: String, key: String) -> Texture2D:
	if not _images.has(key):
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		elif FileAccess.file_exists(path):
			var im := Image.load_from_file(ProjectSettings.globalize_path(path))
			if im != null:
				tex = ImageTexture.create_from_image(im)
		_images[key] = tex
	return _images[key]


## A conical pleated air filter, its open end at `top`.
func filter_cone(top: Vector2, k: float) -> void:
	var w0 := 8.0 * k
	var w1 := 18.0 * k
	var h := 30.0 * k
	blob([top + Vector2(-w0, 0), top + Vector2(w0, 0), top + Vector2(w1, h), top + Vector2(-w1, h)], col("red"))
	for i in range(1, 6):                                       # the pleats
		var f := i / 6.0
		tube([top + Vector2(lerpf(-w0, w0, f), 2), top + Vector2(lerpf(-w1, w1, f), h - 2)], 0.6, col("ink"))
	box(top.x - w1 - 1, top.y + h - 1, top.x + w1 + 1, top.y + h + 4, col("metal_dark"))
	box(top.x - w0 - 2, top.y - 3, top.x + w0 + 2, top.y + 2, col("metal_dark"))   # the clamp


## Exhaust header: a flange with four ports, the tubes, the collector.
## 4-1: four long tubes into one; 4-2-1: pairs merge, then the two merge.
func header(four_one: bool) -> void:
	var ports := [Vector2(22, 20), Vector2(40, 20), Vector2(60, 20), Vector2(78, 20)]
	var tint := col("metal")
	var burnt := col("bronze")                                  # the heat marks
	if four_one:
		for q: Vector2 in ports:
			tube([q, Vector2(q.x, 40), Vector2(50 + (q.x - 50) * 0.25, 72)], 7, tint)
		blob([Vector2(42, 70), Vector2(58, 70), Vector2(54, 94), Vector2(46, 94)], burnt)
	else:
		for pair: Array in [[0, 1, 31.0], [2, 3, 69.0]]:
			for i: int in [pair[0], pair[1]]:
				var q: Vector2 = ports[i]
				tube([q, Vector2(q.x, 34), Vector2(pair[2], 52)], 7, tint)
			tube([Vector2(pair[2], 52), Vector2(pair[2], 62), Vector2(50, 78)], 8, burnt)
		blob([Vector2(44, 76), Vector2(56, 76), Vector2(54, 94), Vector2(46, 94)], tint)
	box(10, 12, 90, 22, col("metal_dark"))
	for q: Vector2 in ports:
		disc(q - Vector2(0, 3), 3.0, col("ink"))


## A camshaft: a shaft with egg-shaped lobes (bigger noses = more lift).
func cams(race: bool) -> void:
	tube([Vector2(6, 50), Vector2(94, 50)], 6, col("metal"))
	var nose := 13.0 if race else 9.5
	for k in 8:
		var c := Vector2(12.0 + k * 10.8, 50)
		var up := -1.0 if k % 2 == 0 else 1.0
		var arr := []
		for i in 24:
			var a := TAU * i / 24.0
			var r := 6.5 + maxf(0.0, cos(a)) * (nose - 6.5)       # the lobe's nose points one way
			arr.append(c + Vector2(sin(a) * 4.5, -cos(a) * r * up))
		blob(arr, col("metal"))
	if race:
		box(6, 70, 94, 78, col("red"))
		text("HIGH RPM", Vector2(50, 75), 7, col("paper"))


## A short shifter: lever, knob, boot (a race one: shorter, red, bushings).
func shifter(race: bool) -> void:
	blob([Vector2(28, 92), Vector2(72, 92), Vector2(60, 72), Vector2(40, 72)], col("rubber"))
	var top := 40.0 if race else 28.0
	tube([Vector2(50, 74), Vector2(50, top)], 5, col("metal"))
	if race:
		for y: float in [64.0, 70.0]:
			box(42, y, 58, y + 4, col("yellow"))                # the bushings
	disc(Vector2(50, top - 8), 13, col("red") if race else col("rubber"))
	for i in 3:                                                 # the shift pattern on the knob
		tube([Vector2(44 + i * 6, top - 14), Vector2(44 + i * 6, top - 2)], 0.8, col("paper"))
	tube([Vector2(44, top - 8), Vector2(56, top - 8)], 0.8, col("paper"))


## A ring and pinion with the ratio stamped on it.
func final_drive(ratio: String) -> void:
	gear(Vector2(42, 50), 32, 38, 34, col("metal"))
	disc(Vector2(42, 50), 20, col("metal_dark"))
	for k in 8:
		disc(Vector2(42, 50) + Vector2.from_angle(TAU * k / 8.0) * 15.0, 1.6, col("ink"))
	gear(Vector2(84, 50), 9, 13, 10, col("metal_dark"))
	text(ratio, Vector2(42, 50), 16, col("paper"))


## A tire from the side: grooves in the tread (fewer = stickier); an
## R-compound is near slick with yellow letters.
func tire(grooves: int, r_comp: bool) -> void:
	disc(Vector2(50, 50), 45, col("rubber"))
	for k in grooves:
		var a := TAU * k / grooves
		tube([Vector2(50, 50) + Vector2.from_angle(a) * 40.0, Vector2(50, 50) + Vector2.from_angle(a) * 45.0],
			2.4 if grooves > 20 else 4.0, col("ink"))
	if r_comp:
		for k in 10:                                            # the sidewall letters
			var a := TAU * k / 10.0
			tube([Vector2(50, 50) + Vector2.from_angle(a) * 36.0, Vector2(50, 50) + Vector2.from_angle(a + 0.3) * 36.0],
				2.5, col("yellow"))
	disc(Vector2(50, 50), 28, col("metal_dark"))
	disc(Vector2(50, 50), 8, col("metal"))


## A wheel: rim, spokes, lug nuts.
func wheel(spokes: int, color: Color, spoke_w: float) -> void:
	disc(Vector2(50, 50), 44, col("rubber"))
	disc(Vector2(50, 50), 37, color)
	disc(Vector2(50, 50), 32, col("ink"))
	for k in spokes:
		var a := TAU * k / spokes - PI / 2.0
		tube([Vector2(50, 50) + Vector2.from_angle(a) * 8.0, Vector2(50, 50) + Vector2.from_angle(a) * 33.0],
			spoke_w, color)
	disc(Vector2(50, 50), 10, color)
	for k in 4:
		disc(Vector2(50, 50) + Vector2.from_angle(TAU * k / 4.0 + 0.4) * 6.0, 1.5, col("ink"))


## A rear sway bar: the U-shaped torsion bar, its bushings, the size.
func sway_bar(w: float, label: String) -> void:
	tube([Vector2(14, 78), Vector2(14, 44), Vector2(28, 28), Vector2(72, 28), Vector2(86, 44), Vector2(86, 78)],
		w, col("red"))
	for x: float in [36.0, 64.0]:
		box(x - 5, 28 - w / 2.0 - 3, x + 5, 28 + w / 2.0 + 3, col("rubber"))
	for x: float in [14.0, 86.0]:
		disc(Vector2(x, 80), 4, col("metal"))
	text(label, Vector2(50, 56), 12, col("ink"))


## A coil spring, wound from y0 to y1 between x0 and x1.
## The strands going back behind the spring are shaded darker and drawn
## first, so it reads as a coil, not a zigzag.
func coil(color: Color, x0: float, x1: float, y0: float, y1: float) -> void:
	var turns := 7
	var step := (y1 - y0) / (turns * 2)
	for back: bool in [true, false]:
		for i in turns * 2:
			if (i % 2 == 1) != back:
				continue
			var a := Vector2(x0 if i % 2 == 0 else x1, y0 + i * step)
			var b := Vector2(x1 if i % 2 == 0 else x0, y0 + (i + 1) * step)
			tube([a, b], 6, color.darkened(0.4) if back else color)


## A carbon hood, top down: the weave, two vents.
func hood() -> void:
	var outline := [Vector2(16, 14), Vector2(84, 14), Vector2(94, 74), Vector2(84, 90), Vector2(16, 90), Vector2(6, 74)]
	blob(outline, col("carbon"))
	var poly := PackedVector2Array(outline)
	var light := col("carbon").lightened(0.18)
	for y in range(16, 90, 6):                                  # the 2x2 twill, inside the outline
		for x in range(8, 94, 6):
			if (x / 6 + y / 6) % 2 == 0 and Geometry2D.is_point_in_polygon(Vector2(x + 3, y + 3), poly):
				draw_rect(Rect2(p(x, y), Vector2(5, 5) * _s), light)
	for x: float in [30.0, 58.0]:
		box(x, 40, x + 12, 46, col("ink"))
	var ring := pts(outline)
	ring.append(ring[0])
	draw_polyline(ring, col("ink"), _lw, true)
