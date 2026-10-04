extends Control
## The wager as cash in hand: a fan of bills that grows with the amount
## (one bill per BILL dollars, up to MAX_BILLS). Over STACKS_FROM it's real
## money: banded $1000 bundles piled up (Spire). Drawn in code.

const BILL := 50.0
const MAX_BILLS := 14
const STACKS_FROM := 2000.0      # above this: stacks instead of a fan
const BUNDLE := 1000.0           # one banded bundle
const BUNDLES_PER_PILE := 5
const MAX_PILES := 3
const PAPER := Color(0.74, 0.8, 0.66)
const INK := Color(0.24, 0.34, 0.24)
const BAND := Color(0.93, 0.88, 0.72)        # the paper strap around a bundle
const BILL_SIZE := Vector2(150, 64)
const BUNDLE_SIZE := Vector2(132, 30)        # a bundle seen from the front: long side across

var amount := 100.0:
	set(v):
		amount = v
		queue_redraw()


func _draw() -> void:
	if amount > STACKS_FROM:
		draw_stacks()
	else:
		draw_fan()


func draw_fan() -> void:
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


## Banded bundles, piled up to BUNDLES_PER_PILE high, piles side by side
## (a slight lean so it looks dropped on the table, not printed).
func draw_stacks() -> void:
	var n := clampi(int(ceil(amount / BUNDLE)), 1, BUNDLES_PER_PILE * MAX_PILES)
	var piles := ceili(float(n) / BUNDLES_PER_PILE)
	var font := get_theme_default_font()
	var gap := 8.0
	var w := BUNDLE_SIZE.x * 0.62                 # piles overlap a little, front to back
	var left := (size.x - (w * (piles - 1) + BUNDLE_SIZE.x)) / 2.0
	var i := 0
	for pile in piles:
		var in_pile := mini(BUNDLES_PER_PILE, n - pile * BUNDLES_PER_PILE)
		for k in in_pile:
			var lean := (((i * 37) % 7) - 3) * 1.6             # a few px off, bundle to bundle
			# later piles sit in front (lower), so they're drawn over the ones behind
			var pos := Vector2(left + pile * w + lean,
				size.y - 8.0 - (piles - 1 - pile) * gap - (k + 1) * (BUNDLE_SIZE.y - 2.0))
			var r := Rect2(pos, BUNDLE_SIZE)
			draw_rect(r.grow(1.5), Color(0, 0, 0, 0.4))
			draw_rect(r, PAPER.darkened(0.05 * (k % 2)))
			for e in 4:                                       # bill edges along the side
				var y := r.position.y + 6.0 + e * 5.5
				draw_line(Vector2(r.position.x + 3, y), Vector2(r.end.x - 3, y), PAPER.darkened(0.2), 1.0)
			var band := Rect2(Vector2(r.get_center().x - 18, r.position.y), Vector2(36, BUNDLE_SIZE.y))
			draw_rect(band, BAND)
			draw_rect(band, INK, false, 1.0)
			draw_string(font, band.get_center() + Vector2(-6, 7), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
			i += 1
