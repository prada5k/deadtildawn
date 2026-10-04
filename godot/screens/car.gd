extends Control
## The car: the DX up on the lift (3D, widgets/lift_bay.gd), its spec sheet
## (dyno chart + stats, ink on paper), and the build sheet (what's in each slot).
## LAYOUT lives in car.tscn; this script fills in data. Stat and part rows are
## added in code (their number changes), styled by the theme.

signal go(target: String)    # "warehouse", "shop"
signal part_changed(slot: String, part_id: String)   # "" = back to stock

const UI := preload("res://ui.gd")
const Voice := preload("res://voice.gd")


func _ready() -> void:
	%ShopButton.pressed.connect(func(): go.emit("shop"))


## info: common info + "parts_on" (installed part ids, for the 3D model)
## parts: {"slots": {slot: name}, "options": {slot: [[id, name], ...]}, "installed": {slot: id}}
func setup(info: Dictionary, stats: Dictionary, parts := {}) -> void:
	%Lift.show_parts(info.get("parts_on", []))
	%LiftNote.text = Voice.LIFT
	%CarName.text = stats["name"]
	var dyno = %Dyno
	dyno.dyno = stats["dyno"]
	dyno.redline = float(stats["redline"])
	dyno.queue_redraw()
	var rows: VBoxContainer = %Stats
	for row in [
		["Weight", "%d kg (with Faba)" % stats["weight_kg"]],
		["Power / weight", "%d hp per tonne" % stats["hp_per_tonne"]],
		["Drivetrain", "%s, redline %d" % [stats["drivetrain"], stats["redline"]]],
		["0-60 mph", "%.2f s" % stats["zero_60_s"]],
		["Quarter mile", "%.2f s" % stats["quarter_s"]],
		["Top speed", "%d mph" % stats["top_speed_mph"]],
		["Skidpad", "%.2f g, %s" % [stats["skidpad_g"], stats["balance"]]],
		["60-0 mph", "%d ft" % stats["sixty_zero_ft"]],
	]:
		UI.stat_row(rows, row[0], row[1], "InkMutedLabel", "InkLabel")
	if not parts.is_empty():
		build_parts_list(parts)


## One row per slot: slot name + a tape label you tap to pick Stock or any
## owned part for it.
func build_parts_list(parts: Dictionary) -> void:
	var list: VBoxContainer = %PartsList
	for slot in parts["slots"]:
		var row := UI.hbox(list, 10)
		var name := UI.label(row, parts["slots"][slot], "InkLabel")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pick := OptionButton.new()
		pick.theme_type_variation = "PartPickButton"
		pick.custom_minimum_size.x = 330
		pick.clip_text = true
		pick.add_item("stock")
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
