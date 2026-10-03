extends Control
## Splatter pattern for the crash slides of the intro. Drawn in code from a
## fixed random seed, so it looks hand-thrown but is identical every time.
## Change SEED for a different pattern, COLORS for a different palette.

const SEED := 87                     # 87 mph
const COLORS := [Color(0.839, 0.251, 0.271), Color(0.62, 0.13, 0.16), Color(0.45, 0.07, 0.1)]

# Each splat: center (as a fraction of the screen), size, how many drops
const SPLATS := [
	[Vector2(0.86, 0.12), 1.0, 70],
	[Vector2(0.10, 0.88), 1.2, 90],
	[Vector2(0.72, 0.78), 0.55, 40],
	[Vector2(0.18, 0.16), 0.4, 28],
	[Vector2(0.95, 0.55), 0.45, 30],
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var unit := minf(size.x, size.y)
	for splat in SPLATS:
		var center := Vector2(splat[0].x * size.x, splat[0].y * size.y)
		var scale_f: float = splat[1] * unit * 0.16
		var main_color: Color = COLORS[rng.randi() % COLORS.size()]
		# Core: overlapping blobs
		for i in 9:
			var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * scale_f * 0.45
			draw_circle(center + off, scale_f * rng.randf_range(0.25, 0.5), Color(main_color, 0.92))
		# Drops thrown outward, smaller the farther they fly
		for i in int(splat[2]):
			var ang := rng.randf() * TAU
			var dist := scale_f * (0.5 + pow(rng.randf(), 0.6) * 2.4)
			var p := center + Vector2.from_angle(ang) * dist
			var r := maxf(1.5, scale_f * 0.12 * (1.0 - dist / (scale_f * 3.0)) * rng.randf_range(0.3, 1.0))
			var c: Color = COLORS[rng.randi() % COLORS.size()]
			draw_circle(p, r, Color(c, 0.9))
			# Some drops leave a streak back toward the center
			if rng.randf() < 0.3:
				var tail := p - Vector2.from_angle(ang) * r * rng.randf_range(2.0, 5.0)
				draw_line(p, tail, Color(c, 0.75), r * 0.9, true)
