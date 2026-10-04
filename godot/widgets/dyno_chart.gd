extends Control
## Dyno chart: torque (lb-ft) and power (hp) against rpm, from the sim's
## torque curve. Feed it `dyno` = [[rpm, torque_lbft, hp], ...].
## Colors and font come from the theme when the node has a theme type variation
## that defines them (e.g. "InkDynoChart": ink on the paper spec sheet);
## otherwise the dark-screen defaults below.

const DEFAULTS := {
	"torque": Color(1.0, 0.55, 0.1),
	"power": Color(0.92, 0.92, 0.95),
	"grid": Color(1, 1, 1, 0.08),
	"text": Color(0.6, 0.6, 0.65),
	"redline": Color(0.9, 0.15, 0.15, 0.12),
}

var dyno := []
var redline := 6500.0


## A theme color if the variation defines it, else the default.
func col(name: String) -> Color:
	return get_theme_color(name) if has_theme_color(name) else DEFAULTS[name]


func _draw() -> void:
	if dyno.is_empty():
		return
	var font := get_theme_font("font") if has_theme_font("font") else ThemeDB.fallback_font
	var torque_color := col("torque")
	var power_color := col("power")
	var text := col("text")
	var left := 44.0
	var bottom := 30.0
	var top := 34.0
	var w := size.x - left - 12.0
	var h := size.y - bottom - top
	var rpm_lo := float(dyno[0][0])
	var rpm_hi := float(dyno[dyno.size() - 1][0])
	var y_hi := 0.0
	for p in dyno:
		y_hi = maxf(y_hi, maxf(float(p[1]), float(p[2])))
	y_hi = ceilf(y_hi * 1.15 / 20.0) * 20.0
	var pt := func(rpm: float, v: float) -> Vector2:
		return Vector2(left + (rpm - rpm_lo) / (rpm_hi - rpm_lo) * w, top + h - v / y_hi * h)

	var v := 0.0
	while v <= y_hi:
		var y: float = pt.call(rpm_lo, v).y
		draw_line(Vector2(left, y), Vector2(left + w, y), col("grid"), 1.0)
		draw_string(font, Vector2(4, y + 5), str(int(v)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, text)
		v += 20.0
	var rpm := ceilf(rpm_lo / 1000.0) * 1000.0
	while rpm <= rpm_hi:
		var x: float = pt.call(rpm, 0).x
		draw_string(font, Vector2(x - 6, size.y - 8), str(int(rpm / 1000)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, text)
		rpm += 1000.0
	draw_string(font, Vector2(left + w - 70, size.y - 8), "rpm x1000", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text)

	var xr: float = pt.call(redline, 0).x
	draw_rect(Rect2(xr, top, left + w - xr, h), col("redline"))

	var tq := PackedVector2Array()
	var hp := PackedVector2Array()
	var best_tq: Array = dyno[0]   # typed: Array elements have no known type
	var best_hp: Array = dyno[0]
	for p in dyno:
		tq.append(pt.call(float(p[0]), float(p[1])))
		hp.append(pt.call(float(p[0]), float(p[2])))
		if float(p[1]) > float(best_tq[1]):
			best_tq = p
		if float(p[2]) > float(best_hp[2]):
			best_hp = p
	draw_polyline(tq, torque_color, 3.0, true)
	draw_polyline(hp, power_color, 3.0, true)
	draw_string(font, Vector2(left, 22), "TORQUE  %d lb-ft @ %d" % [int(best_tq[1]), int(best_tq[0])],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, torque_color)
	draw_string(font, Vector2(left + w * 0.55, 22), "POWER  %d hp @ %d" % [int(best_hp[2]), int(best_hp[0])],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, power_color)
