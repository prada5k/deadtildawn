extends RefCounted
## Shared UI helpers. Every look (colors, fonts, button styles) comes from
## res://theme.tres, so restyle the game there, not here.
##
## Type variations defined in the theme:
##   Labels:  TitleLabel, HeadingLabel, MutedLabel, BigNumberLabel
##   Buttons: AccentButton (orange), DangerButton (red, SEND IT), SelectedButton
## Garage props (paper, tape, whiteboard, corkboard...): see the theme itself.

const BG := Color(0.102, 0.059, 0.063)    # #1A0F10 (instead of black)
const ACCENT := Color(0.839, 0.251, 0.271)  # #D64045 deadtildawn red
const GOOD := Color(0.46, 0.77, 0.4)
const BAD := Color(0.93, 0.17, 0.24)
const MUTED := Color(0.6, 0.61, 0.66)
const INK := Color(0.102, 0.078, 0.086)       # #1A1416, ink on paper
const INK_BAD := Color(0.7, 0.15, 0.17)       # red ink


## The garage behind the hub screens (widgets/garage_cam.gd, owned by the shell).
static func stage(from: Node) -> Node:
	return from.get_tree().get_first_node_in_group("stage")


## A drag on a see-through area of a screen walks the stage's camera round
## the car on the lift (CAR, body shop). Only sideways drags: vertical swipes
## still scroll.
static func drag_orbit(from: Control, event: InputEvent) -> void:
	var rel := Vector2.ZERO
	if event is InputEventScreenDrag:
		rel = (event as InputEventScreenDrag).relative
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		rel = (event as InputEventMouseMotion).relative
	if rel != Vector2.ZERO and absf(rel.x) > absf(rel.y):
		var s := stage(from)
		if s != null:
			s.orbit(rel.x)
		from.accept_event()


static func label(parent: Node, text: String, variation := "", color = null) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	# Wrap only inside columns. A wrapping label has no natural width, so in a
	# row (HBoxContainer) nothing gives it one and it collapses to one
	# character per line. In a column it wraps to the column's width.
	if not parent is HBoxContainer:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color != null:
		l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


static func panel(parent: Node) -> PanelContainer:
	var p := PanelContainer.new()
	parent.add_child(p)
	return p


static func vbox(parent: Node, gap := 10) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", gap)
	parent.add_child(b)
	return b


static func hbox(parent: Node, gap := 10) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", gap)
	parent.add_child(b)
	return b


static func button(parent: Node, text: String, on_press: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## name_style / value_style: theme variations ("InkMutedLabel" / "InkLabel" on paper).
static func stat_row(parent: Node, name: String, value: String, name_style := "MutedLabel",
		value_style := "") -> HBoxContainer:
	var row := hbox(parent, 12)
	var n := label(row, name, name_style)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := label(row, value, value_style)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return row


static func spacer(parent: Node, expand := true) -> Control:
	var c := Control.new()
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c


static func money(x: float) -> String:
	var sign := "-" if x < 0 else ""
	return "%s$%d" % [sign, int(abs(x))]
