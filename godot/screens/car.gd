extends Control
## The car: dyno chart, stat sheet, parts (coming with the loot system).
## LAYOUT lives in car.tscn; this script fills in data. Stat rows are added
## in code (one per stat) using the theme, so they restyle with it.

signal go(target: String)    # "warehouse", "shop"
signal part_changed(slot: String, part_id: String)   # "" = back to stock

const UI := preload("res://ui.gd")


func _ready() -> void:
	$Margin/Scroll/Column/TopRow/Back.pressed.connect(func(): go.emit("warehouse"))
	$Margin/Scroll/Column/PartsPanel/Box/ShopButton.pressed.connect(func(): go.emit("shop"))


## parts: {"slots": {slot: name}, "options": {slot: [[id, name], ...]}, "installed": {slot: id}}
func setup(info: Dictionary, stats: Dictionary, parts := {}) -> void:
	$Margin/Scroll/Column/Header.show_stats(info["cash"], info["rep"], info["min_buy_in"])
	$Margin/Scroll/Column/CarName.text = stats["name"]
	var dyno = $Margin/Scroll/Column/DynoPanel/Dyno
	dyno.dyno = stats["dyno"]
	dyno.redline = float(stats["redline"])
	dyno.queue_redraw()
	var rows: VBoxContainer = $Margin/Scroll/Column/StatsPanel/Stats
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
	var list: VBoxContainer = $Margin/Scroll/Column/PartsPanel/Box/PartsList
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
		pick.disabled = options.is_empty()
		pick.item_selected.connect(func(i): part_changed.emit(slot, pick.get_item_metadata(i)))
		row.add_child(pick)
