extends Control
## Analog gauge (speedometer / tachometer), drawn in code, styled after a
## '90s Honda Type R cluster: white face, black numerals, red needle, and the
## redline zone's ticks and numbers in red.
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

@export_group("Colors")
@export var face_color := Color("f4f1ea")      # warm white, like an aged cluster
@export var ink_color := Color("111111")       # numerals and ticks
@export var red_color := Color("d7191f")       # needle, redline zone
@export var bezel_color := Color("16130f")
@export var bezel_edge_color := Color("4a4540")

var value := 0.0:
	set(v):
		value = v
		queue_redraw()                # ask Godot to call _draw() again

const START_DEG := 135.0
const SWEEP_DEG := 270.0
const FONT := preload("res://fonts/Rajdhani-Bold.ttf")


func angle_for(v: float) -> float:
	var f := clampf((v - min_value) / (max_value - min_value), 0.0, 1.0)
	return deg_to_rad(START_DEG + SWEEP_DEG * f)


func centered_text(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(FONT, pos + Vector2(-w / 2.0, font_size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	var face_r := r * 0.9

	# Bezel, then the white face with a thin inner shadow line
	draw_circle(c, r, bezel_color)
	draw_arc(c, r - 1.0, 0.0, TAU, 96, bezel_edge_color, 2.0, true)
	draw_circle(c, face_r, face_color)
	draw_arc(c, face_r, 0.0, TAU, 96, Color(0, 0, 0, 0.35), 2.0, true)

	# Redline zone: a red band along the outer edge of the face
	if redline_from < max_value:
		draw_arc(c, face_r * 0.95, angle_for(redline_from), angle_for(max_value), 32,
			red_color, face_r * 0.07, true)

	# Ticks and numbers (red once they're in the redline zone)
	var v := min_value
	while v <= max_value + 1e-6:
		var a := angle_for(v)
		var dir := Vector2.from_angle(a)
		var is_major := is_equal_approx(fmod(v - min_value, major_step), 0.0) \
			or is_equal_approx(fmod(v - min_value, major_step), major_step)
		var ink := red_color if v >= redline_from else ink_color
		var inner := face_r * (0.76 if is_major else 0.84)
		draw_line(c + dir * inner, c + dir * face_r * 0.91, ink, 3.5 if is_major else 1.6, true)
		if is_major:
			centered_text(c + dir * face_r * 0.6, str(int(round(v * label_scale))),
				int(face_r * 0.22), ink)
		v += minor_step

	# Title and digital readout, low in the dead zone under the hub (clear of
	# the numerals and the needle's sweep)
	centered_text(c + Vector2(0, face_r * 0.27), title, int(face_r * 0.12), ink_color.lightened(0.35))
	centered_text(c + Vector2(0, face_r * 0.64), digital_format % (value * digital_scale),
		int(face_r * 0.24), ink_color)

	# Needle: tapered, with a short counterweight tail, over a black hub
	var na := angle_for(value)
	var d := Vector2.from_angle(na)
	var n := d.orthogonal()
	var tip := c + d * face_r * 0.9
	var tail := c - d * face_r * 0.2
	draw_colored_polygon(PackedVector2Array([tail + n * face_r * 0.035, tip + n * 1.2,
		tip - n * 1.2, tail - n * face_r * 0.035]), red_color)
	draw_circle(c, face_r * 0.1, ink_color)
	draw_circle(c, face_r * 0.04, Color(0.3, 0.3, 0.3))

	# Glass: a faint highlight across the top-left of the face
	draw_arc(c, face_r * 0.8, deg_to_rad(200), deg_to_rad(250), 24, Color(1, 1, 1, 0.25),
		face_r * 0.1, true)
