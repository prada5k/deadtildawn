extends Control
## A hand-drawn dry-erase mark over its own rect: a loose circle (race nights),
## an X (days gone by), an underline (today), or a doodle (a middle finger for
## the rival, a sad face after a loss). Wobble is seeded, so a mark doesn't
## change shape when it redraws. Never blocks touches.

@export_enum("circle", "cross", "underline", "finger", "sadface") var mode := "circle"
@export var color := Color(0.78, 0.13, 0.15)
@export var width := 3.5
@export var wobble_seed := 1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = wobble_seed
	match mode:
		"circle":
			# An ellipse a bit bigger than the rect, started off-axis, with the
			# end overshooting the start like a real marker loop
			var c := size / 2.0
			var r := size / 2.0 + Vector2(3, 3)
			var a0 := rng.randf_range(-2.4, -1.6)
			var pts := PackedVector2Array()
			var n := 44
			for i in n + 1:
				var t := float(i) / n
				var a := a0 + t * (TAU + 0.45)
				var k := 1.0 + rng.randf_range(-0.03, 0.03) + 0.05 * t
				pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y) * k)
			draw_polyline(pts, color, width, true)
		"cross":
			var m := size * 0.18
			draw_line(m + jitter(rng), size - m + jitter(rng), color, width, true)
			draw_line(Vector2(size.x - m.x, m.y) + jitter(rng), Vector2(m.x, size.y - m.y) + jitter(rng),
				color, width, true)
		"underline":
			var y := size.y - 2.0
			var pts := PackedVector2Array()
			for i in 9:
				var x := lerpf(4.0, size.x - 4.0, i / 8.0)
				pts.append(Vector2(x, y + rng.randf_range(-1.5, 1.5)))
			draw_polyline(pts, color, width, true)
		"finger":
			# Fist with the middle finger up, drawn in a unit box (0..1 across the rect)
			var u := size.x                          # arc radii scale with the width
			draw_polyline(PackedVector2Array([at(0.40, 0.52), at(0.40, 0.14)]), color, width, true)
			draw_arc(at(0.50, 0.14), 0.10 * u, PI, TAU, 10, color, width, true)
			draw_polyline(PackedVector2Array([at(0.60, 0.14), at(0.60, 0.52)]), color, width, true)
			draw_arc(at(0.30, 0.52), 0.10 * u, PI, TAU, 10, color, width, true)      # folded knuckles
			draw_arc(at(0.13, 0.57), 0.08 * u, PI, TAU, 8, color, width, true)
			draw_arc(at(0.70, 0.52), 0.10 * u, PI, TAU, 10, color, width, true)
			draw_arc(at(0.87, 0.57), 0.07 * u, PI, TAU, 8, color, width, true)
			draw_polyline(PackedVector2Array([at(0.05, 0.57), at(0.1, 0.93), at(0.86, 0.94),
				at(0.94, 0.57)]), color, width, true)                               # palm
			draw_line(at(0.16, 0.73), at(0.56, 0.69), color, width, true)          # thumb
		"sadface":
			var c := size / 2.0
			var r := minf(size.x, size.y) / 2.0 - width
			draw_arc(c, r, 0.0, TAU, 32, color, width, true)
			draw_circle(c + Vector2(-0.35, -0.25) * r, width * 0.9, color)
			draw_circle(c + Vector2(0.35, -0.25) * r, width * 0.9, color)
			draw_arc(c + Vector2(0, 0.6) * r, 0.42 * r, PI * 1.15, PI * 1.85, 12, color, width, true)


## A point in the rect from unit coordinates.
func at(x: float, y: float) -> Vector2:
	return Vector2(x * size.x, y * size.y)


func jitter(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
