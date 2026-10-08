extends Control
## Analog gauge (speedometer / tachometer), drawn in code.
##
## Sweep: 270 degrees, starting bottom-left and going clockwise.
## Set the properties, then update `value` every frame.
##
## style "honda90s" (default): a restrained 1990s Japanese-hatch instrument: an off-white face with dark
## numerals, a red redline band, a thin tick where the limiter cuts in, a tapered red needle. It is only
## inspired by the period look: no logos, nothing copied from a branded cluster.
## style "classic": the original dark face with an orange needle.
##
## The needle shows exactly `value` (the recorded telemetry at the replay's current time): no smoothing, no
## damping. `available = false` (the replay has no such channel) shows NO DATA instead of a made-up reading.

@export var min_value := 0.0
@export var max_value := 200.0
@export var major_step := 20.0       # numbered ticks
@export var minor_step := 10.0       # small ticks
@export var label_scale := 1.0       # number shown = tick value * label_scale (e.g. 0.001 for x1000 rpm)
@export var redline_from := INF      # values above this get a red band / arc
@export var limiter_at := INF        # a thin tick where the rev limiter / fuel cut sits (honda90s)
@export var title := "km/h"
@export var digital_format := "%d"   # small numeric readout
@export var digital_scale := 1.0     # readout = value * digital_scale
@export_enum("honda90s", "classic") var style := "honda90s"

var value := 0.0:
	set(v):
		value = v
		queue_redraw()                # ask Godot to call _draw() again

var available := true:
	set(v):
		available = v
		queue_redraw()

const START_DEG := 135.0
const SWEEP_DEG := 270.0

const FACE := Color(0.93, 0.92, 0.87)
const HOUSING := Color(0.03, 0.03, 0.035)
const INK := Color(0.1, 0.1, 0.11)
const INK_SOFT := Color(0.32, 0.32, 0.34)
const RED := Color(0.82, 0.08, 0.07)


func angle_for(v: float) -> float:
	var f := clampf((v - min_value) / (max_value - min_value), 0.0, 1.0)
	return deg_to_rad(START_DEG + SWEEP_DEG * f)


func _draw() -> void:
	if style == "classic":
		draw_classic()
	else:
		draw_honda90s()


func is_major_tick(v: float) -> bool:
	return is_equal_approx(fmod(v - min_value, major_step), 0.0) \
		or is_equal_approx(fmod(v - min_value, major_step), major_step)


func draw_honda90s() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	var font := ThemeDB.fallback_font
	draw_circle(c, r, HOUSING)                                   # dark bezel
	draw_circle(c, r * 0.93, FACE if available else FACE.darkened(0.35))
	draw_arc(c, r * 0.93, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.5), 1.5, true)

	if redline_from < max_value:                                 # the recorded redline up to the end of the scale
		draw_arc(c, r * 0.8, angle_for(redline_from), angle_for(max_value), 32, RED, r * 0.1, true)
	if limiter_at < max_value:                                   # the recorded fuel cut / limiter
		var la := Vector2.from_angle(angle_for(limiter_at))
		draw_line(c + la * r * 0.7, c + la * r * 0.9, INK, 3.0, true)

	var v := min_value
	while v <= max_value + 1e-6:
		var a := angle_for(v)
		var dir := Vector2.from_angle(a)
		var major := is_major_tick(v)
		draw_line(c + dir * (r * 0.72 if major else r * 0.78), c + dir * r * 0.88, INK if major else INK_SOFT,
			2.6 if major else 1.2, true)
		if major:
			var text := str(int(round(v * label_scale)))
			var fs := int(r * 0.18)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := c + dir * r * 0.55
			draw_string(font, pos + Vector2(-w / 2.0, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
		v += minor_step

	var small := int(r * 0.13)
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(font, c + Vector2(-tw / 2.0, r * 0.34), title, HORIZONTAL_ALIGNMENT_LEFT, -1, small, RED)
	var readout := (digital_format % (value * digital_scale)) if available else "NO DATA"
	var rs := int(r * (0.2 if available else 0.14))
	var rw := font.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1, rs).x
	draw_string(font, c + Vector2(-rw / 2.0, r * 0.66), readout, HORIZONTAL_ALIGNMENT_LEFT, -1, rs, INK)

	if available:                                                # tapered needle with a short tail
		var dir2 := Vector2.from_angle(angle_for(value))
		var side := dir2.orthogonal()
		var tip := c + dir2 * r * 0.84
		var tail := c - dir2 * r * 0.16
		draw_colored_polygon(PackedVector2Array([tip, c + side * r * 0.035, tail + side * r * 0.025,
			tail - side * r * 0.025, c - side * r * 0.035]), RED)
	draw_circle(c, r * 0.09, HOUSING)
	draw_arc(c, r * 0.09, 0.0, TAU, 24, Color(0.55, 0.55, 0.58), 2.0, true)


func draw_classic() -> void:
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
		var is_major := is_major_tick(v)
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
