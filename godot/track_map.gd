extends Control
## Track layout drawn inside a UI box: straights gray, corners colored by
## severity (1 = red hairpin ... 10 = green kink), labels outside each turn.

var track := {}        # bridge "track" reply


func severity_color(sev: int) -> Color:
	var red := Color(0.84, 0.16, 0.17)
	var yellow := Color(1.0, 0.88, 0.5)
	var green := Color(0.1, 0.6, 0.32)
	var f := (sev - 1) / 9.0
	return red.lerp(yellow, f * 2.0) if f < 0.5 else yellow.lerp(green, (f - 0.5) * 2.0)


func _draw() -> void:
	if track.is_empty():
		return
	var pts: Array = track["centerline"]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		var v := Vector2(p[0], -p[1])
		lo = lo.min(v)
		hi = hi.max(v)
	var pad := 70.0
	var scale_f := minf((size.x - 2 * pad) / maxf(hi.x - lo.x, 1.0), (size.y - 2 * pad) / maxf(hi.y - lo.y, 1.0))
	var offset := size / 2.0 - (lo + hi) / 2.0 * scale_f

	var screen := PackedVector2Array()
	for p in pts:
		screen.append(Vector2(p[0], -p[1]) * scale_f + offset)
	draw_polyline(screen, Color(0.45, 0.45, 0.48), 7.0, true)

	var font := ThemeDB.fallback_font
	for c in track["corners"]:
		var col := severity_color(int(c["severity"]))
		var arc := PackedVector2Array()
		for i in range(int(c["s_start"]), mini(int(c["s_end"]) + 1, screen.size())):
			arc.append(screen[i])
		if arc.size() > 1:
			draw_polyline(arc, col, 7.0, true)
		var mid := Vector2(c["mid"][0], -c["mid"][1]) * scale_f + offset
		var out := Vector2(c["outward"][0], -c["outward"][1])
		var text: String = c["text"]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var pos := mid + out * 30.0
		draw_string(font, pos + Vector2(-w / 2.0, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)

	draw_circle(screen[0], 7.0, Color.WHITE)
	draw_string(font, screen[0] + Vector2(-20, -14), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	draw_rect(Rect2(screen[screen.size() - 1] - Vector2(6, 6), Vector2(12, 12)), Color.WHITE)
	draw_string(font, screen[screen.size() - 1] + Vector2(10, 4), "FINISH", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
