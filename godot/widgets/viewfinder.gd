extends Control
## A camcorder's viewfinder OSD over the home screen's footage
## (widgets/garage_cam.gd): corner brackets, a blinking REC, tape speed and
## battery, the date and time stamp. Colors / font from the theme variation
## "Viewfinder" (line, rec, font, font_size).

const INSET := 14.0
const ARM := 46.0                 # bracket arm length (px)

var t := 0.0
var blink := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	t += delta
	var b := fmod(t, 1.2) < 0.75
	if b != blink:
		blink = b
		queue_redraw()
	if int(t) != int(t - delta):           # the clock ticks
		queue_redraw()


func _draw() -> void:
	var line := get_theme_color("line", "Viewfinder")
	var rec := get_theme_color("rec", "Viewfinder")
	var font := get_theme_font("font", "Viewfinder")
	var fs := get_theme_font_size("font_size", "Viewfinder")
	var r := Rect2(Vector2(INSET, INSET), size - Vector2(INSET, INSET) * 2.0)
	var w := 3.0
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x < r.get_center().x else -1.0
		var sy := 1.0 if c.y < r.get_center().y else -1.0
		draw_line(c, c + Vector2(ARM * sx, 0), line, w)
		draw_line(c, c + Vector2(0, ARM * sy), line, w)
	var top := r.position + Vector2(20, 20 + fs * 0.8)
	if blink:
		draw_circle(top + Vector2(8, -fs * 0.3), fs * 0.28, rec)
	draw_string(font, top + Vector2(24, 0), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, line)
	var right := "SP  ▮▮▮▯"
	var rw := font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(r.end.x - 20 - rw, top.y), right, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, line)
	var d := Time.get_datetime_dict_from_system()
	var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	var stamp := "%s %02d  %02d:%02d:%02d" % [months[int(d["month"]) - 1], d["day"], d["hour"], d["minute"], d["second"]]
	# The date up top by REC (the bottom of the screen is the menus' and the nav's)
	draw_string(font, top + Vector2(24 + font.get_string_size("REC   ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, 0), stamp,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.85), line)
