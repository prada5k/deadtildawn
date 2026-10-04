extends Control
## The wager as cash in hand: a fan of bills that grows with the amount
## (one bill per BILL dollars, up to MAX_BILLS). Drawn in code.

const BILL := 50.0
const MAX_BILLS := 14
const PAPER := Color(0.74, 0.8, 0.66)
const INK := Color(0.24, 0.34, 0.24)
const BILL_SIZE := Vector2(150, 64)

var amount := 100.0:
	set(v):
		amount = v
		queue_redraw()


func _draw() -> void:
	var n := clampi(int(round(amount / BILL)), 1, MAX_BILLS)
	var pivot := Vector2(size.x / 2.0, size.y - 6.0)            # where the hand holds them
	var spread := minf(0.11 * (n - 1), 1.3)                      # radians across the fan
	var font := get_theme_default_font()
	for i in n:
		var a := -spread / 2.0 + (spread * i / maxf(n - 1, 1)) - PI / 2.0
		draw_set_transform(pivot, a + PI / 2.0, Vector2.ONE)
		# a bill standing up from the pivot, long side vertical
		var r := Rect2(Vector2(-BILL_SIZE.y / 2.0, -BILL_SIZE.x - 8.0), Vector2(BILL_SIZE.y, BILL_SIZE.x))
		draw_rect(r.grow(1.5), Color(0, 0, 0, 0.35))
		draw_rect(r, PAPER.darkened(0.08 * (i % 2)))
		draw_rect(r.grow(-5), INK, false, 1.5)
		var c := r.get_center()
		draw_circle(c, 16.0, PAPER.lightened(0.15))
		draw_arc(c, 16.0, 0.0, TAU, 20, INK, 1.5)
		draw_string(font, c + Vector2(-6, 8), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	draw_set_transform(Vector2.ZERO)
