extends Control
## The calendar: a dry-erase whiteboard in the shop. This week's days (gone-by
## days crossed out, today underlined, race nights circled in red), what's
## coming up, and the last races (W in green, L in red).
## LAYOUT lives in calendar.tscn. Day cells and rows are added in code (their
## number changes); marker colors come from the theme's Whiteboard*Label styles.

signal go(target: String)    # "warehouse"

const UI := preload("res://ui.gd")
const MarkerMark := preload("res://widgets/marker_mark.gd")
const Voice := preload("res://voice.gd")
const DAY_NAMES := ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]


## A marker color, read from a theme label style (no colors in screens).
func ink(style: String) -> Color:
	return get_theme_color("font_color", style)


func mark(parent: Control, mode: String, style: String, wobble: int) -> void:
	var m: Control = MarkerMark.new()
	m.mode = mode
	m.color = ink(style)
	m.wobble_seed = wobble
	parent.add_child(m)


## Top corner of the board: a middle finger for the rival, or a sad face
## right after a loss.
func doodle(lost: bool) -> void:
	%Doodle.text = "" if lost else Voice.BOARD_RIVAL
	var m: Control = MarkerMark.new()
	m.mode = "sadface" if lost else "finger"
	m.color = ink("WhiteboardSmallLabel")
	m.width = 3.5
	m.custom_minimum_size = Vector2(58, 58) if lost else Vector2(62, 84)
	m.rotation = 0.08
	%Doodle.add_sibling(m)


## "FRI, WEEK 2" -> "FRI wk 2" (fits a whiteboard row)
func short_when(when: String) -> String:
	return when.replace(", WEEK ", " wk ")


## info: cash/rep/min_buy_in, week, day, week_events ({day: label}),
## upcoming ([[when, what], ...]), past ([[when, who, result, amount, "money" | "rep"], ...])
func setup(info: Dictionary) -> void:
	%WeekLabel.text = "WEEK %d" % info["week"]
	doodle(info.get("last_lost", false))

	var days: HBoxContainer = %Days
	for d in 7:
		var cell := MarginContainer.new()      # stacks the text and the mark over each other
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		days.add_child(cell)
		var box := UI.vbox(cell, 2)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		var day_label := UI.label(box, DAY_NAMES[d], "WhiteboardSmallLabel")
		day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var has_event: bool = info["week_events"].has(d)
		var what := UI.label(box, info["week_events"][d] if has_event else " ", "WhiteboardRedSmallLabel")
		what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		what.autowrap_mode = TextServer.AUTOWRAP_OFF
		if has_event and d >= info["day"]:
			mark(cell, "circle", "WhiteboardRedLabel", d + 7 * int(info["week"]))
		if d < info["day"]:
			mark(cell, "cross", "WhiteboardSmallLabel", d)
		elif d == info["day"]:
			mark(cell, "underline", "WhiteboardBlueLabel", d)

	var up: VBoxContainer = %Upcoming
	for row in info["upcoming"]:
		UI.stat_row(up, short_when(row[0]), row[1], "WhiteboardBlueLabel", "WhiteboardSmallLabel")
	var past: VBoxContainer = %Past
	if info["past"].is_empty():
		UI.label(past, "nothing yet", "WhiteboardSmallLabel")
	for row in info["past"]:
		var line := UI.hbox(past, 14)
		var who := UI.label(line, "%s   %s" % [short_when(row[0]), row[1]], "WhiteboardSmallLabel")
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(line, row[2], "WhiteboardSmallLabel")
		# money in green marker, rep in orange, always
		UI.label(line, row[3], "WhiteboardGreenLabel" if row[4] == "money" else "WhiteboardOrangeLabel")
