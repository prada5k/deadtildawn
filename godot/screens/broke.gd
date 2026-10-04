extends Control
## BROKE: cash fell under tonight's minimum bet. Scrap parts (off the car or
## off the shelf) for cash until you can cover it again, or start over.
## Full screen (no shell). LAYOUT lives in broke.tscn; the part rows are
## built here (their number changes). game.gd does the selling.

signal scrap(uid: String)
signal back_pressed
signal start_over

const UI := preload("res://ui.gd")
const Voice := preload("res://voice.gd")


func _ready() -> void:
	%BackInBusiness.pressed.connect(func(): back_pressed.emit())
	%StartOver.pressed.connect(func(): start_over.emit())


## info: cash, min_bet, record (text), parts: [{uid, name, value, where}]
## (where: "on the car" / "on the shelf" / "unopened" / "damaged")
func setup(info: Dictionary) -> void:
	var cash := int(info["cash"])
	var need := int(info["min_bet"])
	var short := need - cash
	%Title.text = Voice.BROKE.to_upper() if short > 0 else "BACK IN BUSINESS"
	%Text.text = ("%s left. Tonight's minimum bet is %s: you're %s short.\n\n%s" % [
		UI.money(cash), UI.money(need), UI.money(short), info["record"]]) if short > 0 else (
		"%s. That covers the %s buy-in. Don't do that again." % [UI.money(cash), UI.money(need)])
	%BackInBusiness.disabled = short > 0
	var parts: Array = info["parts"]
	%ScrapTitle.visible = not parts.is_empty()
	if parts.is_empty() and short > 0:
		UI.label(%Parts, "Nothing left to scrap. The warehouse goes quiet.", "MutedLabel")
	for p: Dictionary in parts:
		var card := PanelContainer.new()
		card.theme_type_variation = "PaperPanel"
		%Parts.add_child(card)
		var row := UI.hbox(card, 10)
		var col := UI.vbox(row, 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(col, p["name"], "InkLabel").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UI.label(col, p["where"], "InkMutedLabel")
		var b := UI.button(row, "scrap  %s" % UI.money(int(p["value"])), func(): scrap.emit(p["uid"]),
			"GaffSmallButton")
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
