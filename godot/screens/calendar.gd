extends Control
## The persistent calendar: this week's days, scheduled world events, and
## historical notices. game.gd owns time and event state.
## LAYOUT lives in calendar.tscn. Day cells and list rows are added in code
## (their number changes), styled by the theme: a day with an event uses the
## "EventDayPanel" variation, today uses "TodayPanel".

signal go(target: String)
signal advance_day
signal inspect_event(event_id: String)

const UI := preload("res://ui.gd")
const DAY_NAMES := ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]


func _ready() -> void:
	%AdvanceDayButton.pressed.connect(func(): advance_day.emit())


func event_date(event: Dictionary) -> String:
	return "%s / WEEK %02d / DAY %02d" % [
		DAY_NAMES[int(event["scheduled_day"])], int(event["scheduled_week"]),
		int(event["scheduled_day"]) + 1]


func event_card(parent: VBoxContainer, event: Dictionary) -> void:
	var card := UI.vbox(UI.panel(parent), 4)
	UI.label(card, str(event["title"]), "HeadingLabel")
	UI.label(card, "%s / %s / %s" % [event["event_id"], event["type"],
		str(event["status"]).to_upper()], "MutedLabel")
	UI.label(card, event_date(event), "MutedLabel")
	var place := str(event.get("location_id", ""))
	var road := str(event.get("road_id", ""))
	if place != "" or road != "":
		UI.label(card, "LOCATION / %s%s" % [place if place != "" else "UNSPECIFIED",
			" / ROAD %s" % road if road != "" else ""], "MutedLabel")
	if str(event.get("description", "")) != "":
		UI.label(card, str(event["description"]), "MutedLabel")
	if str(event.get("type", "")) == "time_attack":
		UI.button(card, "INSPECT TIME ATTACK", func(): inspect_event.emit(str(event["event_id"])), "AccentButton")


func setup(info: Dictionary) -> void:
	%WeekLabel.text = "WEEK %02d" % info["week"]
	%CurrentDate.text = "TODAY / %s / DAY %02d" % [info["today"], int(info["day"]) + 1]

	var days: HBoxContainer = %Days
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
		var labels: Array = info["week_events"].get(d, [])
		var mark := UI.label(box, "\n".join(labels) if has_event else "-",
			"HeadingLabel" if has_event else "MutedLabel")
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.autowrap_mode = TextServer.AUTOWRAP_OFF

	var up: VBoxContainer = %Upcoming
	if info["upcoming"].is_empty():
		UI.label(up, "No scheduled items.", "MutedLabel")
	for event in info["upcoming"]:
		event_card(up, event)
	var past: VBoxContainer = %Past
	if info["past_events"].is_empty():
		UI.label(past, "No passed or closed events.", "MutedLabel")
	for event in info["past_events"]:
		event_card(past, event)
	var legacy: VBoxContainer = %LegacyHistory
	%LegacyPanel.visible = not info["legacy_history"].is_empty()
	for row in info["legacy_history"]:
		UI.stat_row(legacy, "%s   %s" % [row[0], row[1]], row[2])
