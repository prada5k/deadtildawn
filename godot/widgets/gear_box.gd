extends Control
## The replay's gear indicator: a small dark box with the current gear. The sim reads 0 while a shift is in
## progress (it takes 0.4 s), shown as "-". `available = false` (no gear channel in the replay) shows "--".

var gear := 0:
	set(v):
		if v != gear:
			gear = v
			queue_redraw()

var available := true:
	set(v):
		available = v
		queue_redraw()

const BOX := Color(0.03, 0.03, 0.035)
const EDGE := Color(0.55, 0.55, 0.58)
const DIGIT := Color(0.94, 0.92, 0.85)
const CAPTION := Color(0.62, 0.62, 0.66)


func _draw() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = BOX
	style.border_color = EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	draw_style_box(style, Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	var text := ("-" if gear == 0 else str(gear)) if available else "--"
	var fs := int(size.y * 0.5)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - w) / 2.0, size.y * 0.62), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DIGIT)
	var cap_fs := int(size.y * 0.15)
	var cw := font.get_string_size("GEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs).x
	draw_string(font, Vector2((size.x - cw) / 2.0, size.y * 0.88), "GEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs, CAPTION)
