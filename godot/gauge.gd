extends Control
## Analog gauge (speedometer / tachometer), drawn in code.
##
## Sweep: 270 degrees, starting bottom-left and going clockwise.
## Set the properties, then update `value` every frame.

@export var min_value := 0.0
@export var max_value := 200.0
@export var major_step := 20.0       # numbered ticks
@export var minor_step := 10.0       # small ticks
@export var label_scale := 1.0       # number shown = tick value * label_scale (e.g. 0.001 for x1000 rpm)
@export var redline_from := INF      # values above this get a red arc
@export var title := "km/h"
@export var digital_format := "%d"   # center readout
@export var digital_scale := 1.0     # readout = value * digital_scale

var value := 0.0:
	set(v):
		value = v
		queue_redraw()                # ask Godot to call _draw() again

const START_DEG := 135.0
const SWEEP_DEG := 270.0


func angle_for(v: float) -> float:
	var f := clampf((v - min_value) / (max_value - min_value), 0.0, 1.0)
	return deg_to_rad(START_DEG + SWEEP_DEG * f)


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	var font := ThemeDB.fallback_font

	# Face and rim
	draw_circle(c, r, Color(0.06, 0.06, 0.08, 0.92))
	draw_arc(c, r, 0.0, TAU, 64, Color(0.55, 0.55, 0.6), 2.0, true)

	# Redline zone
	if redline_from < max_value:
		draw_arc(c, r * 0.86, angle_for(redline_from), angle_for(max_value), 32,
			Color(0.85, 0.12, 0.1), r * 0.08, true)

	# Ticks and numbers
	var v := min_value
	while v <= max_value + 1e-6:
		var a := angle_for(v)
		var dir := Vector2.from_angle(a)
		var is_major := is_equal_approx(fmod(v - min_value, major_step), 0.0) \
			or is_equal_approx(fmod(v - min_value, major_step), major_step)
		var inner := r * (0.74 if is_major else 0.8)
		draw_line(c + dir * inner, c + dir * r * 0.9, Color(0.9, 0.9, 0.9),
			2.5 if is_major else 1.2, true)
		if is_major:
			var text := str(int(round(v * label_scale)))
			var fs := int(r * 0.17)
			var pos := c + dir * r * 0.58
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, pos + Vector2(-w / 2.0, fs * 0.35), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.85, 0.85))
		v += minor_step

	# Digital readout and title
	var big := int(r * 0.26)
	var readout := digital_format % (value * digital_scale)
	var bw := font.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	draw_string(font, c + Vector2(-bw / 2.0, r * 0.36), readout,
		HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color.WHITE)
	var small := int(r * 0.14)
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(font, c + Vector2(-tw / 2.0, r * 0.56), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(0.7, 0.7, 0.7))

	# Needle
	var na := angle_for(value)
	var needle_color := Color(1.0, 0.25, 0.15) if value >= redline_from else Color(1.0, 0.55, 0.1)
	draw_line(c - Vector2.from_angle(na) * r * 0.12, c + Vector2.from_angle(na) * r * 0.86,
		needle_color, 3.0, true)
	draw_circle(c, r * 0.07, Color(0.2, 0.2, 0.22))
