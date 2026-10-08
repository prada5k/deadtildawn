extends Control
## The car: dyno chart, stat sheet, and physical parts installation.
## LAYOUT lives in car.tscn; this script fills in data. Stat rows are added
## in code (one per stat) using the theme, so they restyle with it.

signal go(target: String)    # "warehouse", "shop"
signal part_changed(slot: String, part_id: String)   # "" = back to stock

const UI := preload("res://ui.gd")


func _ready() -> void:
	%ShopButton.pressed.connect(func(): go.emit("shop"))


## parts: {"slots": {slot: name}, "options": {slot: [[id, name], ...]}, "installed": {slot: id}}
func setup(info: Dictionary, stats: Dictionary, parts := {}) -> void:
	%CarName.text = stats["name"]
	%WorkMessage.text = str(parts.get("message", ""))
	if %WorkMessage.text == "":
		%WorkMessage.text = "SELECT A PART OR STOCK TO QUEUE GARAGE WORK. ADVANCE THE CALENDAR TO FINISH IT."
	var dyno = %Dyno
	dyno.dyno = stats["dyno"]
	dyno.redline = float(stats["redline"])
	dyno.queue_redraw()
	var rows: VBoxContainer = %Stats
	UI.stat_row(rows, "Weight", "%d kg (with Faba)" % stats["weight_kg"])
	UI.stat_row(rows, "Power / weight", "%d hp per tonne" % stats["hp_per_tonne"])
	UI.stat_row(rows, "Drivetrain", "%s, redline %d" % [stats["drivetrain"], stats["redline"]])
	UI.stat_row(rows, "0-60 mph", "%.2f s" % stats["zero_60_s"])
	UI.stat_row(rows, "Quarter mile", "%.2f s" % stats["quarter_s"])
	UI.stat_row(rows, "Top speed", "%d mph" % stats["top_speed_mph"])
	UI.stat_row(rows, "Skidpad", "%.2f g, %s" % [stats["skidpad_g"], stats["balance"]])
	UI.stat_row(rows, "60-0 mph", "%d ft" % stats["sixty_zero_ft"])
	if not parts.is_empty():
		build_parts_list(parts)


## One row per slot: slot name + a dropdown of Stock and every owned part.
func build_parts_list(parts: Dictionary) -> void:
	var list: VBoxContainer = %PartsList
	var pending_by_slot := {}
	for order in parts.get("active_work", []):
		pending_by_slot[order["slot"]] = order
	for slot in parts["slots"]:
		var row := UI.hbox(list, 10)
		var name := UI.label(row, parts["slots"][slot], "MutedLabel")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pick := OptionButton.new()
		pick.custom_minimum_size.x = 330
		pick.add_item("Stock")
		pick.set_item_metadata(0, "")
		var options: Array = parts["options"].get(slot, [])
		for i in options.size():
			pick.add_item(options[i][1])
			pick.set_item_metadata(i + 1, options[i][0])
			if parts["installed"].get(slot, "") == options[i][0]:
				pick.select(i + 1)
		pick.disabled = pending_by_slot.has(slot) or (options.is_empty() and not parts["installed"].has(slot))
		pick.item_selected.connect(func(i): part_changed.emit(slot, pick.get_item_metadata(i)))
		row.add_child(pick)
		if pending_by_slot.has(slot):
			var order: Dictionary = pending_by_slot[slot]
			UI.label(list, "%s %s / %s / DUE %s, WEEK %d" % [
				str(order["operation"]).to_upper(), str(order["definition_id"]),
				str(order["work_id"]), ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"][int(order["due_day"])],
				int(order["due_week"])], "MutedLabel")
