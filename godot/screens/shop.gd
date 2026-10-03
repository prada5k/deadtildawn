extends Control
## Parts shop. LAYOUT lives in shop.tscn; the part cards are built here (their
## number comes from the catalog), using theme styles plus the rarity colors
## below. Grouped by slot.

signal go(target: String)     # "car", "warehouse"
signal buy(part_id: String)

const UI := preload("res://ui.gd")
const RARITY_COLORS := {
	"common": Color(0.75, 0.76, 0.8),
	"rare": Color(0.35, 0.6, 1.0),
	"epic": Color(0.72, 0.42, 1.0),
	"legendary": Color(1.0, 0.78, 0.25),
}


func _ready() -> void:
	$Margin/Column/TopRow/Back.pressed.connect(func(): go.emit("car"))


## info: cash, rep, min_buy_in; catalog: bridge "parts" reply;
## owned: [part ids]; installed: {slot: part id}; message: optional text
func setup(info: Dictionary, catalog: Dictionary, owned: Array, installed: Dictionary,
		message := "") -> void:
	$Margin/Column/Header.show_stats(info["cash"], info["rep"], info["min_buy_in"])
	var msg: Label = $Margin/Column/Message
	msg.text = message
	msg.visible = message != ""
	var list: VBoxContainer = $Margin/Column/Scroll/List
	var spendable := int(info["cash"]) - int(info["min_buy_in"])
	var slots: Dictionary = catalog["slots"]
	for slot in slots:
		UI.label(list, str(slots[slot]).to_upper(), "HeadingLabel")
		for p in catalog["parts"]:
			if p["slot"] != slot:
				continue
			var card := UI.vbox(UI.panel(list), 4)
			var top := UI.hbox(card, 10)
			var name := UI.label(top, p["name"])
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UI.label(top, str(p["rarity"]).to_upper(), "", RARITY_COLORS[p["rarity"]])
			for line in p["effects_text"]:
				UI.label(card, line)
			UI.label(card, p["blurb"], "MutedLabel")
			var row := UI.hbox(card, 10)
			var price := UI.label(row, UI.money(p["price"]), "HeadingLabel")
			price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if p["id"] in owned:
				UI.label(row, "INSTALLED" if installed.get(slot) == p["id"] else "OWNED", "MutedLabel")
			else:
				var b := UI.button(row, "BUY", func(): buy.emit(p["id"]), "AccentButton")
				if int(p["price"]) > spendable:
					b.disabled = true
					b.tooltip_text = "You'd be left without the %s buy-in." % UI.money(info["min_buy_in"])
