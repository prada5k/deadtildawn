extends Control
## TEAM (the 5th drawer): a corkboard about Faba and the builder. Two
## Polaroids (Faba's DX at the turnout, the DX on the builder's lift), Faba's
## driver card, the builder's card, the record, and memories that unlock at
## milestones (captions in voice.gd). LAYOUT lives in team.tscn; data hooks
## use scene unique names (%Name). game.gd team_info() works out the numbers.

signal go(target: String)

const UI := preload("res://ui.gd")


## info: faba / builder / record ([[name, value], ...]), memories
## ([{photo, caption, unlocked, when}]), parts_on (for the photos)
func setup(info: Dictionary) -> void:
	%FabaShot.show_parts(info["parts_on"])
	%MeShot.show_parts(info["parts_on"])
	fill(%FabaStats, info["faba"])
	fill(%BuilderStats, info["builder"])
	fill(%RecordStats, info["record"])
	var grid: GridContainer = %Memories
	for m in info["memories"]:
		polaroid(grid, m)


## Rows on an index card; money in green ink (money is always green).
func fill(box: VBoxContainer, rows: Array) -> void:
	for r in rows:
		var value: String = r[1]
		var money := value.begins_with("$") or value.begins_with("+$") or value.begins_with("-$")
		UI.stat_row(box, r[0], value, "InkMutedLabel", "InkMoneyLabel" if money else "InkLabel")


## One memory: a little Polaroid. Locked ones are blank and say "???".
func polaroid(grid: GridContainer, m: Dictionary) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "PolaroidPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.rotation = randf_range(-0.04, 0.04)
	grid.add_child(card)
	var col := UI.vbox(card, 4)
	var photo := PanelContainer.new()
	photo.theme_type_variation = "MemoryPhotoPanel"
	photo.custom_minimum_size = Vector2(0, 110)
	col.add_child(photo)
	var big := UI.label(photo, m["photo"] if m["unlocked"] else "", "MemoryPhotoLabel")
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.label(col, m["caption"] if m["unlocked"] else "???", "MarkerSmallLabel")
	if m["unlocked"]:
		UI.label(col, str(m["when"]).to_lower(), "InkMutedLabel")
