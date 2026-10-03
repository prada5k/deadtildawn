extends Control
## The calendar: this week's days, what's coming up, and past races.
## LAYOUT lives in calendar.tscn. Day cells and list rows are added in code
## (their number changes), styled by the theme: a day with an event uses the
## "EventDayPanel" variation, today uses "TodayPanel".

signal go(target: String)    # "warehouse"

const UI := preload("res://ui.gd")
const DAY_NAMES := ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]


func _ready() -> void:
	$Margin/Column/TopRow/Back.pressed.connect(func(): go.emit("warehouse"))


## info: cash/rep/min_buy_in, week, day, week_events ({day: label}),
## upcoming ([[when, what], ...]), past ([[when, what, result], ...])
func setup(info: Dictionary) -> void:
	$Margin/Column/Header.show_stats(info["cash"], info["rep"], info["min_buy_in"])
	$Margin/Column/WeekLabel.text = "WEEK %d" % info["week"]

	var days: HBoxContainer = $Margin/Column/Days
	for d in 7:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var has_event: bool = info["week_events"].has(d)
		if d == info["day"]:
			cell.theme_type_variation = "TodayPanel"
		elif has_event:
			cell.theme_type_variation = "EventDayPanel"
		days.add_child(cell)
		var box := UI.vbox(cell, 4)
		var name := UI.label(box, DAY_NAMES[d], "MutedLabel")
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var mark := UI.label(box, info["week_events"][d] if has_event else "-",
			"HeadingLabel" if has_event else "MutedLabel")
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.autowrap_mode = TextServer.AUTOWRAP_OFF

	var up: VBoxContainer = $Margin/Column/UpcomingPanel/Upcoming
	for row in info["upcoming"]:
		UI.stat_row(up, row[0], row[1])
	var past: VBoxContainer = $Margin/Column/PastPanel/Past
	if info["past"].is_empty():
		UI.label(past, "No races yet.", "MutedLabel")
	for row in info["past"]:
		UI.stat_row(past, "%s   %s" % [row[0], row[1]], row[2])
