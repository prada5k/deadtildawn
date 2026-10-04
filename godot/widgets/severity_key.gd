extends Control
## The key beside the meeting's road map: corner colors from tight to fast,
## with the radius each color means. Same colors as the map (track_map.gd),
## read from the same theme variation (InkTrackMap).
##
## Severity n (1-10) is a radius on a geometric scale, like the sim's pace
## notes (sim/track.py): R_n = 15 * (500/15)^((n-1)/9) m.

const TrackMap := preload("res://track_map.gd")
const STOPS := [[1, "hairpin"], [4, "tight"], [7, "fast"], [10, "kink"]]
const R_MIN := 15.0
const R_MAX := 500.0
const BAR_W := 14.0


static func radius(sev: int) -> float:
	return R_MIN * pow(R_MAX / R_MIN, (sev - 1) / 9.0)


func _draw() -> void:
	var mid: Color = get_theme_color("severity_mid") if has_theme_color("severity_mid") else Color(1.0, 0.88, 0.5)
	var ink: Color = get_theme_color("marker") if has_theme_color("marker") else Color.WHITE
	var font := get_theme_font("font") if has_theme_font("font") else ThemeDB.fallback_font
	var fs := 16
	var top := 34.0
	var bottom := size.y - 16.0
	draw_string(font, Vector2(0, 18), "CORNERS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	# The bar: severity 1 (red) at the top down to 10 (green), in 9 bands
	var band := (bottom - top) / 9.0
	for i in 9:
		var c0 := TrackMap.severity_ink(i + 1, mid)
		var c1 := TrackMap.severity_ink(i + 2, mid)
		var y := top + band * i
		var pts := PackedVector2Array([Vector2(0, y), Vector2(BAR_W, y), Vector2(BAR_W, y + band), Vector2(0, y + band)])
		draw_polygon(pts, PackedColorArray([c0, c0, c1, c1]))
	for s in STOPS:
		var sev: int = s[0]
		var y := top + band * (sev - 1)
		draw_line(Vector2(BAR_W, y), Vector2(BAR_W + 6, y), ink, 2.0)
		draw_string(font, Vector2(BAR_W + 10, y - 2), s[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			TrackMap.severity_ink(sev, mid))
		draw_string(font, Vector2(BAR_W + 10, y + fs - 2), "%d m" % roundi(radius(sev)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, ink)
