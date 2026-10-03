extends RefCounted
## Shared UI helpers so every screen has the same look.

const BG := Color(0.09, 0.1, 0.11)
const PANEL := Color(0.14, 0.15, 0.17)
const ACCENT := Color(1.0, 0.55, 0.1)       # deadtildawn orange
const GOOD := Color(0.46, 0.77, 0.4)
const BAD := Color(0.93, 0.17, 0.24)
const MUTED := Color(0.65, 0.66, 0.7)


static func label(parent: Node, text: String, size := 18, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


static func panel(parent: Node, color := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)
	return p


static func vbox(parent: Node, gap := 8) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", gap)
	parent.add_child(b)
	return b


static func hbox(parent: Node, gap := 8) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", gap)
	parent.add_child(b)
	return b


static func button(parent: Node, text: String, on_press: Callable, size := 20,
		color := ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color.darkened(0.35)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(12)
	var hover := normal.duplicate()
	hover.bg_color = color.darkened(0.15)
	var pressed := normal.duplicate()
	pressed.bg_color = color
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


static func stat_row(parent: Node, name: String, value: String) -> void:
	var row := hbox(parent, 12)
	var n := label(row, name, 17, MUTED)
	n.custom_minimum_size.x = 200
	label(row, value, 17)


static func money(x: float) -> String:
	var sign := "-" if x < 0 else ""
	return "%s$%d" % [sign, int(abs(x))]
