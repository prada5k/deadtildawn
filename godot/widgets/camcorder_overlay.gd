extends Control
## A camcorder's viewfinder frame over a 3D view (HOME's garage, the replay's chase camera): corner
## brackets, small mid-edge ticks, a battery icon, and the cheap grit overlay (assets/shaders/crt_grit.gdshader).
## Text (REC, the tape counter, the game-calendar label) belongs to the screens that use this; this node only
## draws frame graphics, never blocks input, and reads no game state.

const GRIT_SHADER := "res://assets/shaders/crt_grit.gdshader"
const INK := Color(0.93, 0.92, 0.86, 0.85)       # off-white, never pure white
const INSET := 14.0
const ARM := 34.0
const TICK := 9.0

@export var show_battery := true
@export var battery_segments := 3                  # of 4
@export var grit := true
@export var scan_strength := 0.09
@export var grain_strength := 0.07
@export var vignette := 0.3


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	if grit and ResourceLoader.exists(GRIT_SHADER):
		var rect := ColorRect.new()
		rect.name = "Grit"
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.color = Color.WHITE
		var material := ShaderMaterial.new()
		material.shader = load(GRIT_SHADER)
		material.set_shader_parameter("scan_strength", scan_strength)
		material.set_shader_parameter("grain_strength", grain_strength)
		material.set_shader_parameter("vignette", vignette)
		rect.material = material
		add_child(rect)


func _draw() -> void:
	var r := Rect2(Vector2(INSET, INSET), size - Vector2(INSET, INSET) * 2.0)
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x < r.get_center().x else -1.0
		var sy := 1.0 if corner.y < r.get_center().y else -1.0
		draw_line(corner, corner + Vector2(ARM * sx, 0.0), INK, 2.0)
		draw_line(corner, corner + Vector2(0.0, ARM * sy), INK, 2.0)
	var mid := r.get_center()
	for tick: Array in [[Vector2(r.position.x, mid.y), Vector2(1, 0)], [Vector2(r.end.x, mid.y), Vector2(-1, 0)],
			[Vector2(mid.x, r.position.y), Vector2(0, 1)], [Vector2(mid.x, r.end.y), Vector2(0, -1)]]:
		draw_line(tick[0], tick[0] + tick[1] * TICK, INK * Color(1, 1, 1, 0.6), 1.5)
	if show_battery:
		draw_battery(Vector2(size.x - INSET - 70.0, INSET + 16.0))


## Four-segment battery, outline + a nub on the right; top-left corner at `at`.
func draw_battery(at: Vector2) -> void:
	var body := Rect2(at, Vector2(48, 20))
	draw_rect(body, INK, false, 2.0)
	draw_rect(Rect2(at + Vector2(48, 6), Vector2(4, 8)), INK)
	for i in 4:
		if i < battery_segments:
			draw_rect(Rect2(at + Vector2(4 + i * 10.5, 4), Vector2(8, 12)), INK)
