extends Node2D
## Top-down car silhouette for the replay, drawn in code. +x is the front.
## Each model gets its own proportions (long-hood Z cars, mid-engine MR2,
## short CRX), paint and livery; profile_for(car_name) picks one by keyword.
##
## Sizes are in meters; px_per_m and VISUAL_SCALE turn them into pixels.

const VISUAL_SCALE := 1.35     # drawn a bit bigger than life so it reads on a phone
const GLASS := Color(0.07, 0.09, 0.12)
const TIRE := Color(0.04, 0.04, 0.04)
const HEADLIGHT := Color(1.0, 0.95, 0.75)
const TAIL_OFF := Color(0.45, 0.03, 0.03)
const TAIL_ON := Color(1.0, 0.12, 0.1)

# keyword in the car's name -> profile overrides (see DEFAULT for the fields)
const PROFILES := {
	"Civic": {"paint": Color(0.78, 0.09, 0.11), "banner": true},
	"280Z": {"length": 4.4, "width": 1.63, "cabin_front": -0.06, "cabin_rear": -0.4,
		"nose": 0.18, "paint": Color(0.9, 0.45, 0.08), "stripes": Color(0.08, 0.08, 0.08)},
	"CRX": {"length": 3.76, "width": 1.66, "cabin_front": 0.12, "cabin_rear": -0.36,
		"paint": Color(0.93, 0.93, 0.9), "stripes": Color(0.8, 0.1, 0.12)},
	"Miata": {"length": 3.95, "width": 1.68, "cabin_front": -0.02, "cabin_rear": -0.3,
		"paint": Color(0.97, 0.8, 0.15), "open_top": true},
	"AE86": {"length": 4.2, "width": 1.63, "paint": Color(0.95, 0.95, 0.93),
		"skirts": Color(0.08, 0.08, 0.08)},
	"Integra": {"length": 4.38, "width": 1.71, "paint": Color(0.22, 0.42, 0.33)},
	"Mustang": {"length": 4.56, "width": 1.74, "cabin_front": -0.04, "cabin_rear": -0.36,
		"nose": 0.14, "paint": Color(0.9, 0.9, 0.92), "stripes": Color(0.12, 0.2, 0.6)},
	"RSX": {"length": 4.37, "width": 1.73, "paint": Color(0.14, 0.34, 0.85)},
	"Eclipse": {"length": 4.49, "width": 1.74, "paint": Color(0.25, 0.8, 0.25),
		"stripes": Color(0.1, 0.1, 0.1)},
	"GTI": {"length": 4.15, "width": 1.73, "cabin_front": 0.14, "cabin_rear": -0.42,
		"paint": Color(0.12, 0.2, 0.52)},
	"MR2": {"length": 4.17, "width": 1.69, "cabin_front": 0.22, "cabin_rear": -0.14,
		"paint": Color(0.92, 0.92, 0.9), "skirts": Color(0.12, 0.12, 0.12)},
	"Mazdaspeed": {"length": 4.5, "width": 1.77, "cabin_front": 0.14, "cabin_rear": -0.4,
		"paint": Color(0.45, 0.47, 0.5), "stripes": Color(0.8, 0.12, 0.12)},
	"Prelude": {"length": 4.52, "width": 1.75, "paint": Color(0.72, 0.73, 0.76)},
	"Camaro": {"length": 4.9, "width": 1.88, "cabin_front": -0.04, "cabin_rear": -0.36,
		"nose": 0.2, "paint": Color(0.42, 0.14, 0.52), "stripes": Color(0.95, 0.95, 0.95)},
}
const DEFAULT := {
	"length": 4.45, "width": 1.70,          # m
	"cabin_front": 0.08, "cabin_rear": -0.34,   # cabin span, fractions of length from center
	"nose": 0.1, "tail": 0.06,              # how much the corners taper (fraction of width)
	"paint": Color(0.7, 0.7, 0.72),
	"stripes": null,                        # twin racing stripes over hood, roof and deck
	"skirts": null,                         # two-tone lower body (AE86 panda)
	"banner": false,                        # kanjo windshield banner
	"open_top": false,
}

var profile := DEFAULT.duplicate()
var px_per_m := 4.0
var braking := false:
	set(b):
		if b != braking:
			braking = b
			queue_redraw()


static func profile_for(car_name: String) -> Dictionary:
	var p := DEFAULT.duplicate()
	for key in PROFILES:
		if car_name.contains(key):
			p.merge(PROFILES[key], true)
			break
	return p


func _ready() -> void:
	queue_redraw()


func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * px_per_m * VISUAL_SCALE


func quad(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([m(x0, y0), m(x1, y0), m(x1, y1), m(x0, y1)])


func _draw() -> void:
	var L: float = profile["length"]
	var W: float = profile["width"]
	var hl := L / 2.0
	var hw := W / 2.0
	var paint: Color = profile["paint"]
	var nose: float = profile["nose"] * W
	var tail: float = profile["tail"] * W

	# Soft shadow under the car, then the wheels peeking out
	draw_colored_polygon(quad(-hl - 0.15, -hw - 0.1, hl + 0.2, hw + 0.25), Color(0, 0, 0, 0.35))
	var axle := L * 0.31
	for x in [axle, -axle]:
		for y in [-hw, hw]:
			draw_colored_polygon(quad(x - 0.33, y - 0.12, x + 0.33, y + 0.12), TIRE)

	# Body: tapered nose and tail
	var body := PackedVector2Array([
		m(-hl, -hw + tail), m(-hl + 0.25, -hw), m(hl - 0.45, -hw), m(hl, -hw + nose),
		m(hl, hw - nose), m(hl - 0.45, hw), m(-hl + 0.25, hw), m(-hl, hw - tail)])
	draw_colored_polygon(body, paint)
	if profile["skirts"] != null:            # two-tone: darker lower sides
		draw_colored_polygon(quad(-hl + 0.2, -hw, hl - 0.4, -hw + 0.22), profile["skirts"])
		draw_colored_polygon(quad(-hl + 0.2, hw - 0.22, hl - 0.4, hw), profile["skirts"])
	# Highlight down the spine: reads as a curved body, not a flat tile
	draw_colored_polygon(quad(-hl + 0.3, -hw * 0.35, hl - 0.3, hw * 0.35), paint.lightened(0.12))

	# Cabin: windshield, roof, rear glass
	var cf: float = profile["cabin_front"] * L
	var cr: float = profile["cabin_rear"] * L
	var cw := hw * 0.86
	draw_colored_polygon(PackedVector2Array([m(cr, -cw), m(cf, -cw * 0.88), m(cf, cw * 0.88), m(cr, cw)]), GLASS)
	if not profile["open_top"]:
		var roof_f := cf - (cf - cr) * 0.3
		var roof_r := cr + (cf - cr) * 0.18
		draw_colored_polygon(quad(roof_r, -cw * 0.8, roof_f, cw * 0.8), paint.darkened(0.08))
	else:                                    # convertible: two seats
		for y in [-cw * 0.45, cw * 0.45]:
			draw_colored_polygon(quad(cr + 0.15, y - 0.22, cr + 0.75, y + 0.22), Color(0.15, 0.12, 0.1))
	if profile["banner"]:                    # windshield banner, kanjo style
		draw_colored_polygon(quad(cf - 0.2, -cw * 0.9, cf, cw * 0.9), Color(0.05, 0.05, 0.05))
		draw_line(m(cf - 0.1, -cw * 0.7), m(cf - 0.1, cw * 0.7), Color(0.95, 0.95, 0.95), 1.0)
	# Mirrors
	for y in [-hw - 0.12, hw + 0.12]:
		draw_colored_polygon(quad(cf - 0.15, y - 0.07, cf + 0.05, y + 0.07), paint.darkened(0.2))

	# Livery: twin racing stripes, nose to tail (over the roof too)
	if profile["stripes"] != null:
		for y in [-0.28, 0.12]:
			draw_colored_polygon(quad(-hl + 0.05, y, hl - 0.05, y + 0.16), profile["stripes"])

	# Lights
	for y in [-hw + 0.18, hw - 0.48]:
		draw_colored_polygon(quad(hl - 0.12, y, hl, y + 0.3), HEADLIGHT)
		draw_colored_polygon(quad(-hl, y, -hl + 0.1, y + 0.3), TAIL_ON if braking else TAIL_OFF)
