extends Control
## Track layout drawn inside a UI box: straights gray, corners colored by
## severity (1 = red hairpin ... 10 = green kink), labels outside each turn.
## The road line, start/finish markers and font come from the theme when the
## node's type variation defines them ("InkTrackMap": ink on the clipboard);
## otherwise the dark-screen defaults.
##
## With `sections` (sim/breakdown.py, after a race) it's a dominance map
## instead: each section in the color of the car that was faster there
## (theme colors "faster" = Faba, "slower" = them), corner labels in ink.

var track := {}        # bridge "track" reply (or a replay's "track")
var label_size := 15   # corner / START / FINISH labels (px); bigger on the full-screen map
var details := false   # also print each corner's radius under its name
var fit_turn := false  # turn the map 90 degrees when that makes it bigger (full screen)
var turned := false    # (set while drawing)


## Map space: x east, y down (north up); turned 90 degrees clockwise if `turned`.
func to_map(x: float, y: float) -> Vector2:
	var v := Vector2(x, -y)
	return Vector2(-v.y, v.x) if turned else v
var sections := []     # optional: breakdown sections [{s_end, gain, ...}]


func col(name: String, fallback: Color) -> Color:
	return get_theme_color(name) if has_theme_color(name) else fallback


func severity_color(sev: int) -> Color:
	var red := Color(0.84, 0.16, 0.17)
	var yellow := col("severity_mid", Color(1.0, 0.88, 0.5))   # darker in ink, or it vanishes on paper
	var green := Color(0.1, 0.6, 0.32)
	var f := (sev - 1) / 9.0
	return red.lerp(yellow, f * 2.0) if f < 0.5 else yellow.lerp(green, (f - 0.5) * 2.0)


func _draw() -> void:
	if track.is_empty():
		return
	var pts: Array = track["centerline"]
	var pad := 70.0 * label_size / 15.0
	var fit := func(turn: bool) -> Array:          # [scale, lo, hi] with or without the turn
		turned = turn
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in pts:
			var v := to_map(p[0], p[1])
			lo = lo.min(v)
			hi = hi.max(v)
		var s := minf((size.x - 2 * pad) / maxf(hi.x - lo.x, 1.0), (size.y - 2 * pad) / maxf(hi.y - lo.y, 1.0))
		return [s, lo, hi]
	var best: Array = fit.call(false)
	if fit_turn:
		var turn_fit: Array = fit.call(true)
		if turn_fit[0] > best[0] * 1.15:           # only when it's clearly bigger
			best = turn_fit
		else:
			turned = false
	var scale_f: float = best[0]
	var offset: Vector2 = size / 2.0 - (best[1] + best[2]) / 2.0 * scale_f

	var screen := PackedVector2Array()
	for p in pts:
		screen.append(to_map(p[0], p[1]) * scale_f + offset)
	draw_polyline(screen, col("line", Color(0.45, 0.45, 0.48)), 7.0, true)
	var faster := col("faster", Color(0.3, 0.55, 1.0))
	var slower := col("slower", Color(0.9, 0.2, 0.2))
	var s0 := 0
	for sec in sections:                                  # centerline points are 1 m apart
		var s1 := mini(int(float(sec["s_end"])), screen.size() - 1)
		if s1 > s0:
			var part := screen.slice(s0, s1 + 1)
			draw_polyline(part, faster if float(sec["gain"]) >= 0.0 else slower, 10.0, true)
		s0 = s1

	var font := get_theme_font("font") if has_theme_font("font") else ThemeDB.fallback_font
	var marker := col("marker", Color.WHITE)
	for c in track["corners"]:
		var sev_col := marker if not sections.is_empty() else severity_color(int(c["severity"]))
		var arc := PackedVector2Array()
		for i in range(int(c["s_start"]), mini(int(c["s_end"]) + 1, screen.size())):
			arc.append(screen[i])
		if arc.size() > 1 and sections.is_empty():
			draw_polyline(arc, sev_col, 7.0, true)
		var mid := to_map(c["mid"][0], c["mid"][1]) * scale_f + offset
		var out := to_map(c["outward"][0], c["outward"][1])
		var lines: Array = [c["text"]]
		if details and c.has("radius"):
			lines.append("R %d m" % int(c["radius"]))
		var pos := mid + out * 2.0 * label_size
		for k in lines.size():
			var text: String = lines[k]
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
			var y := label_size * (0.33 + k - (lines.size() - 1) / 2.0)
			draw_string(font, pos + Vector2(-w / 2.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, sev_col)

	var k := label_size / 15.0
	draw_circle(screen[0], 7.0 * k, marker)
	draw_string(font, screen[0] + Vector2(-20, -14) * k, "START", HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, marker)
	draw_rect(Rect2(screen[screen.size() - 1] - Vector2(6, 6) * k, Vector2(12, 12) * k), marker)
	draw_string(font, screen[screen.size() - 1] + Vector2(10, 4) * k, "FINISH", HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, marker)
