@tool
extends Control
## The crew's sticker (Spire: option A, a SoCal crew that runs kanjo style):
## die-cut vinyl, the crew name in a heavy italic with a colored offset
## underneath (two layers of vinyl), a small line of Japanese under it, the
## way kanjo team stickers sit on a rear quarter window. The words live in
## voice.gd (CREW_NAME, CREW_SUB). Colors from the theme variation
## (CrewSticker), DEFAULTS if it's missing.

const FONT := preload("res://fonts/DelaGothicOne-Regular.ttf")
const Voice := preload("res://voice.gd")
const DEFAULTS := {
	"vinyl": Color(0.97, 0.96, 0.93),
	"accent": Color(0.8, 0.1, 0.12),
	"shadow": Color(0.06, 0.03, 0.04, 0.55),
}
const SKEW := 0.22               # the italic lean


func _ready() -> void:
	resized.connect(queue_redraw)


func col(name: String) -> Color:
	return get_theme_color(name) if has_theme_color(name) else DEFAULTS[name]


func _draw() -> void:
	var name: String = Voice.CREW_NAME
	var sub: String = Voice.CREW_SUB
	var fs := int(size.y * 0.58)
	var w := FONT.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w > size.x * 0.92:                            # fit the width
		fs = int(fs * size.x * 0.92 / w)
		w = FONT.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2((size.x - w) / 2.0, fs * 0.95)
	# Lean it: shear around the baseline
	draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(-SKEW, 1), Vector2(base.y * SKEW, 0)))
	var off := Vector2(fs * 0.06, fs * 0.06)
	draw_string_outline(FONT, base + off * 1.6, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.12), col("shadow"))
	draw_string_outline(FONT, base + off, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.1), col("accent"))
	draw_string(FONT, base + off, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col("accent"))
	draw_string(FONT, base, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col("vinyl"))
	var sfs := int(fs * 0.34)
	var sw := FONT.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
	var sub_at := Vector2(base.x + w - sw, base.y + sfs * 1.25)
	draw_string(FONT, sub_at + Vector2(1.5, 2), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, col("shadow"))
	draw_string(FONT, sub_at, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, col("accent"))
	draw_set_transform_matrix(Transform2D.IDENTITY)
