extends Control
## The pull reveal, on the workbench: a taped box (OPEN IT) -> the part and its
## rarity -> DYNO IT prints a dot-matrix sheet with the hidden quality and exact
## numbers. Full screen (no hub shell). LAYOUT lives in reveal.tscn; data hooks
## use scene unique names (%Name).
##
## Stages: "box" (fresh pull: closed box), "dyno" (part out, the sheet prints
## now), "sheet" (already dynoed: everything shown, no animation).

signal dyno_pressed            # game.gd marks the part revealed, then calls print_sheet()
signal install_pressed
signal leave_pressed           # later / keep as spare

const LINE_DELAY := 0.11       # s between printed lines (the print head)
const JUNK_PCT := 20           # a roll under this % gets the sad trombone when the sheet's done
const Voice := preload("res://voice.gd")

var data := {}


func _ready() -> void:
	%OpenButton.pressed.connect(open_box)
	%DynoButton.pressed.connect(func(): dyno_pressed.emit())
	%LaterButton.pressed.connect(func(): leave_pressed.emit())
	%InstallButton.pressed.connect(func(): install_pressed.emit())
	%KeepButton.pressed.connect(func(): leave_pressed.emit())


## info: id, from, rarity, rarity_color, name, slot, quality_pct, effects ([str]), blurb
func setup(info: Dictionary, stage: String) -> void:
	data = info
	%From.text = "FROM: %s" % str(info["from"]).to_upper()
	%ShipLabel.text = "%s\nAS IS  //  NO RETURNS" % str(info["from"]).to_upper()
	%Rarity.text = str(info["rarity"]).to_upper()
	%Rarity.add_theme_color_override("font_color", info["rarity_color"])
	%PartName.text = info["name"]
	%PartPic.part_id = info.get("id", "")
	%PartPic.halo = info["rarity_color"]
	%Slot.text = info["slot"]
	show_stage(stage)
	if stage == "dyno":
		print_sheet()


func show_stage(stage: String) -> void:
	%Box.visible = stage == "box"
	%Part.visible = stage != "box"
	%Sheet.visible = stage == "sheet"
	%OpenButton.visible = stage == "box"
	%DynoButton.visible = false
	%LaterButton.visible = false
	%InstallButton.visible = stage == "sheet"
	%KeepButton.visible = stage == "sheet"
	if stage == "sheet":
		fill_sheet(false)


## Shake the box, it pops, the part comes out with its rarity.
func open_box() -> void:
	%OpenButton.disabled = true
	Sound.play("box")
	var box: Control = %Box
	box.pivot_offset = box.size / 2.0
	var tw := create_tween()
	for a: float in [0.07, -0.07, 0.05, -0.04]:
		tw.tween_property(box, "rotation", a, 0.05)
	tw.tween_property(box, "scale", Vector2(1.15, 0.8), 0.06)
	tw.tween_property(box, "scale", Vector2(0.1, 0.1), 0.1)
	tw.tween_callback(func():
		box.visible = false
		%OpenButton.visible = false
		%Part.visible = true
		%DynoButton.visible = true
		%LaterButton.visible = true
		pop(%Part))


## A quick overshoot scale-in (physical, under 0.3 s).
func pop(node: Control) -> void:
	await get_tree().process_frame               # let the container size it first
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Print the dyno sheet, line by line.
func print_sheet() -> void:
	%DynoButton.visible = false
	%LaterButton.visible = false
	%Part.visible = true
	%Sheet.visible = true
	fill_sheet(true)


func fill_sheet(animate: bool) -> void:
	var lines: VBoxContainer = %SheetLines
	for c in lines.get_children():
		c.queue_free()
	var rows := [
		"DEADTILDAWN DYNO // BAY 1",
		"--------------------------------",
		"PART     %s" % data["name"],
		"SLOT     %s" % data["slot"],
		"QUALITY %d%%" % int(data["quality_pct"]),
		"--------------------------------",
	]
	for e in data["effects"]:
		rows.append(str(e))
	rows.append("--------------------------------")
	rows.append(str(data["blurb"]))
	var labels := []
	var note_text := margin_note(int(data["quality_pct"]))
	for r in rows:
		var l := Label.new()
		# the quality line prints double size, like a dot-matrix header
		l.theme_type_variation = "DotMatrixBigLabel" if r.begins_with("QUALITY") else "DotMatrixLabel"
		l.text = r
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lines.add_child(l)
		labels.append(l)
	# The builder's pen note in the margin, once the print is done
	var note := Label.new()
	note.theme_type_variation = "MarkerLabel"
	note.text = note_text
	note.rotation = -0.04
	note.visible = note_text != "" and not animate
	lines.add_child(note)
	if not animate:
		return
	%InstallButton.visible = false
	%KeepButton.visible = false
	for l: Label in labels:
		l.visible_ratio = 0.0
	var tw := create_tween()
	for l: Label in labels:
		tw.tween_callback(Sound.play.bind("print", -6.0))   # the print head, line by line
		tw.tween_property(l, "visible_ratio", 1.0, LINE_DELAY)
	tw.tween_callback(func():
		# the verdict, by ear: under 20% is junk (Spire)
		Sound.play("bummer" if int(data["quality_pct"]) < JUNK_PCT else "decent", -2.0)
		note.visible = note_text != ""
		%InstallButton.visible = true
		%KeepButton.visible = true)


## voice.gd: a great roll or a junk roll gets a note; the middle gets nothing.
func margin_note(quality_pct: int) -> String:
	if quality_pct >= Voice.DYNO_GREAT_AT:
		return Voice.DYNO_GREAT
	if quality_pct < Voice.DYNO_JUNK_BELOW:
		return Voice.DYNO_JUNK
	return ""
