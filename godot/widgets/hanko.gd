@tool
extends Control
## The night's result as a hanko, the red ink seal (Spire picked option A: a
## SoCal crew that runs kanjo style). One character in a rounded square,
## stamped by hand: the edge a little uneven, the ink not quite even. The
## characters live in voice.gd (HANKO).
## Colors from the theme variation (Hanko), DEFAULT_INK if it's missing.

const FONT := preload("res://fonts/DelaGothicOne-Regular.ttf")
const DEFAULT_INK := Color(0.76, 0.09, 0.11, 0.9)

@export var glyph := "勝":
	set(v):
		glyph = v
		queue_redraw()


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var ink: Color = get_theme_color("ink") if has_theme_color("ink") else DEFAULT_INK
	var s := minf(size.x, size.y)
	var c := size / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(glyph)
	# The border: three uneven passes, like a seal pressed by hand
	for k in 3:
		var ring := PackedVector2Array()
		var half := s * (0.45 - k * 0.006)
		var r := s * 0.13
		for i in 41:
			var a := TAU * i / 40.0
			var q := Vector2(cos(a), sin(a))
			# a rounded square: a superellipse
			var p := Vector2(signf(q.x) * pow(absf(q.x), 0.35), signf(q.y) * pow(absf(q.y), 0.35)) * (half - r * 0.2)
			ring.append(c + p + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * s * 0.006)
		draw_polyline(ring, Color(ink, ink.a * (1.0 - k * 0.25)), s * (0.06 - k * 0.012), true)
	# The character, centered on its em box
	var fs := int(s * 0.6)
	var w := FONT.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := c.y + (FONT.get_ascent(fs) - FONT.get_descent(fs)) / 2.0
	draw_string(FONT, Vector2(c.x - w / 2.0, base), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	# Where the ink skipped: a few specks of the seal's own ground, faint
	for i in 14:
		var p := c + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)) * s
		draw_circle(p, s * rng.randf_range(0.004, 0.012), Color(ink, ink.a * 0.35))
