extends Control
## The car: the DX up on the lift (3D, widgets/lift_bay.gd), its spec sheet
## (dyno chart + stats, ink on paper), and the build sheet (what's in each slot).
## LAYOUT lives in car.tscn; this script fills in data. Stat and part rows are
## added in code (their number changes), styled by the theme.

signal go(target: String)    # "warehouse", "shop", "road"
signal part_changed(slot: String, part_id: String)   # "" = back to stock
signal part_previewed(slot: String, part_id: String) # picked one: compare before it goes on
signal compare_closed                                # "never mind"

## The comparison card: [label, stat key, format, higher is better?]. Less
## weight, a quicker 0-60 / quarter, a shorter stop are improvements.
const COMPARE := [
	["Power", "hp", "%d hp", true],
	["Torque", "torque_lbft", "%d lb-ft", true],
	["Weight", "weight_kg", "%d kg", false],
	["Power / weight", "hp_per_tonne", "%d hp/t", true],
	["0-60 mph", "zero_60_s", "%.2f s", false],
	["Quarter mile", "quarter_s", "%.2f s", false],
	["Top speed", "top_speed_mph", "%d mph", true],
	["Skidpad", "skidpad_g", "%.3f g", true],
	["60-0 mph", "sixty_zero_ft", "%d ft", false],
]

const UI := preload("res://ui.gd")
const Voice := preload("res://voice.gd")

var locked := false            # the build is locked in for tonight


func _ready() -> void:
	%ShopButton.pressed.connect(func(): go.emit("shop"))
	%CompareNo.pressed.connect(func(): compare_closed.emit())
	%ToRoad.pressed.connect(func(): go.emit("road"))


## info: common info + "parts_on" (installed part ids, for the 3D model) +
## "night": "scouting" (building for tonight's road: a way back to it),
## "locked" (the build is set for tonight: no swaps) or ""
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
	var night: String = info.get("night", "")
	locked = night == "locked"
	%ToRoad.visible = night != ""
	%ToRoad.text = "back to tonight's road  >" if night == "scouting" else "back to tonight  >"
	if locked:
		%PartsNote.text = "LOCKED IN for tonight's race. Swaps after."
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
		pick.disabled = options.is_empty() or locked
		pick.item_selected.connect(func(i): part_previewed.emit(slot, pick.get_item_metadata(i)))
		row.add_child(pick)


## Side by side: the DX now vs with the picked part on. The change in green
## when it's better, red when it's worse (theme InkGood/InkBadLabel), "same"
## when it doesn't move. c: slot, from, to, effects, damaged, now, with, slot_id, uid
func show_compare(c: Dictionary) -> void:
	%Compare.visible = true
	%CompareTitle.text = "SWAP: %s" % str(c["slot"]).to_upper()
	%CompareSwap.text = "%s  >  %s" % [c["from"], c["to"]]
	var notes: Array = c["effects"].duplicate()
	if c["damaged"]:
		notes.append("DAMAGED: does nothing until it's repaired")
	%CompareEffects.text = ",  ".join(notes)
	%CompareEffects.visible = not notes.is_empty()
	var grid: GridContainer = %CompareRows
	for child in grid.get_children():
		child.queue_free()
	for h in ["", "NOW", "WITH IT", "CHANGE"]:
		UI.label(grid, h, "InkMutedLabel").autowrap_mode = TextServer.AUTOWRAP_OFF
	var now: Dictionary = c["now"]
	var with_it: Dictionary = c["with"]
	for row in COMPARE:
		var key: String = row[1]
		var fmt: String = row[2]
		var a := float(now[key])
		var b := float(with_it[key])
		var delta := fmt % absf(b - a)
		var same := delta == fmt % 0.0                 # no change at the shown precision
		var better := (b > a) == bool(row[3])
		var cells := [row[0], fmt % a, fmt % b,
			"same" if same else ("+" if b > a else "-") + delta]
		for i in 4:
			var style := "InkMutedLabel" if i == 0 else "InkLabel"
			if i == 3:
				style = "InkMutedLabel" if same else ("InkGoodLabel" if better else "InkBadLabel")
			var l := UI.label(grid, cells[i], style)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			if i > 0:
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for conn in %CompareYes.pressed.get_connections():
		%CompareYes.pressed.disconnect(conn["callable"])
	%CompareYes.pressed.connect(func(): part_changed.emit(c["slot_id"], c["uid"]))

