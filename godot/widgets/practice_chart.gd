extends Control
## Driver meeting chart: one row per push level, one dot per practice run,
## against the rival's posted time. No percentages; the player reads the chart.
## Dots left of the line beat the rival. Red dots = runs with a mistake.
## Tap a row to pick that push level.

signal push_selected(push: String)

const ORDER := ["safe", "normal", "hard", "flat_out"]
const NAMES := {"safe": "SAFE", "normal": "NORMAL", "hard": "HARD", "flat_out": "FLAT OUT"}
const LABEL_W := 112.0
const AXIS_H := 46.0
const ACCENT := Color(0.976, 0.957, 0.961)   # #F9F4F5: selection is light; red means danger here
const RIVAL := Color(0.93, 0.2, 0.26)

var practice := {}        # push -> {"times": [...], "mistakes": [...]}
var posted := 0.0
var rival_name := "RIVAL"
var selected := "normal"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func row_height() -> float:
	return (size.y - AXIS_H) / ORDER.size()


func _draw() -> void:
	if practice.is_empty():
		return
	var font := ThemeDB.fallback_font
	# Zoom on the decision zone: the fastest run through the bulk of all runs
	# (85th percentile), always including the rival's line. Slower runs (mostly
	# mistakes) are pinned to the right edge so they don't squash the scale.
	var all_times := []
	for p in ORDER:
		for t in practice[p]["times"]:
			all_times.append(float(t))
	all_times.sort()
	var lo := minf(posted, all_times[0])
	var hi := maxf(posted, all_times[int(all_times.size() * 0.85)])
	var pad := (hi - lo) * 0.08 + 0.02
	lo -= pad
	hi += pad
	var plot_w := size.x - LABEL_W - 22.0     # leave room for off-scale arrows
	var x_of := func(t: float) -> float: return LABEL_W + (t - lo) / (hi - lo) * plot_w
	var rh := row_height()

	for r in ORDER.size():
		var push: String = ORDER[r]
		var top := r * rh
		var is_sel := push == selected
		draw_rect(Rect2(0, top + 2, size.x, rh - 4),
			Color(ACCENT, 0.16) if is_sel else Color(1, 1, 1, 0.035))
		if is_sel:
			draw_rect(Rect2(0, top + 2, 4, rh - 4), ACCENT)
		draw_string(font, Vector2(12, top + rh / 2 + 7), NAMES[push],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, ACCENT if is_sel else Color(0.85, 0.85, 0.88))
		var times: Array = practice[push]["times"]
		var mistakes: Array = practice[push]["mistakes"]
		for j in times.size():
			# Spread dots vertically (fixed pattern) so overlapping runs stay visible
			var jitter := (((j * 37) % 13) / 12.0 - 0.5) * rh * 0.6
			var c := RIVAL if mistakes[j] else (Color.WHITE if is_sel else Color(0.7, 0.7, 0.74))
			var t_run := float(times[j])
			if t_run > hi:
				# Off the scale: a small arrow at the right edge ("way slower")
				var y := top + rh / 2 + jitter
				var xe := size.x - 10.0
				draw_colored_polygon(PackedVector2Array([Vector2(xe - 6, y - 4), Vector2(xe, y), Vector2(xe - 6, y + 4)]), Color(c, 0.85))
			else:
				draw_circle(Vector2(x_of.call(t_run), top + rh / 2 + jitter), 3.6, Color(c, 0.85))

	# Rival's posted time
	var xp: float = x_of.call(posted)
	draw_line(Vector2(xp, 0), Vector2(xp, size.y - AXIS_H), RIVAL, 2.5)
	var tag := "%s %.2f" % [rival_name.to_upper(), posted]
	var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, Vector2(clampf(xp - tw / 2, LABEL_W, size.x - tw), size.y - AXIS_H + 18),
		tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, RIVAL)

	# Time axis
	var axis_y := size.y - AXIS_H + 2
	draw_line(Vector2(LABEL_W, axis_y), Vector2(size.x - 8, axis_y), Color(1, 1, 1, 0.3), 1.0)
	var step := 0.1 if hi - lo < 0.6 else (0.2 if hi - lo < 1.6 else 0.5)
	var t := ceilf(lo / step) * step
	while t <= hi:
		var x: float = x_of.call(t)
		draw_line(Vector2(x, axis_y), Vector2(x, axis_y + 5), Color(1, 1, 1, 0.4), 1.0)
		var s := "%.1f" % t
		draw_string(font, Vector2(x - 12, axis_y + 40), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.6, 0.6, 0.65))
		t += step
	draw_string(font, Vector2(4, axis_y + 40), "faster  <", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.6, 0.6, 0.65))
	draw_string(font, Vector2(size.x - 70, axis_y + 40), "> slower", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.6, 0.6, 0.65))


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if not pressed:
		return
	var row := int(event.position.y / row_height())
	if row >= 0 and row < ORDER.size():
		selected = ORDER[row]
		queue_redraw()
		push_selected.emit(selected)
