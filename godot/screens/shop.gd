extends Control
## Parts: pulls, unopened parts, the commons counter, and spares.
## LAYOUT lives in shop.tscn; the sections and cards are built here (their
## number changes), using theme styles plus the rarity colors below.

signal go(target: String)       # "car"
signal pull(source: String)
signal buy(part_id: String)     # commons only
signal sell(uid: String)
signal reveal(uid: String)

const UI := preload("res://ui.gd")
const RARITY_COLORS := {
	"common": Color(0.75, 0.76, 0.8),
	"rare": Color(0.35, 0.6, 1.0),
	"epic": Color(0.72, 0.42, 1.0),
	"legendary": Color(1.0, 0.78, 0.25),
}
const SCRAP_RATE := 0.25        # keep in sync with game.gd


func _ready() -> void:
	pass


func part_by_id(catalog: Dictionary, id: String) -> Dictionary:
	for p in catalog["parts"]:
		if p["id"] == id:
			return p
	return {}


## info: cash, rep, min_buy_in; catalog: bridge "parts" reply (parts, slots,
## sources); inventory: [instances]; installed: {slot: uid}; pity: {source: n}
func setup(info: Dictionary, catalog: Dictionary, inventory: Array, installed: Dictionary,
		pity: Dictionary, message := "") -> void:
	var msg: Label = %Message
	msg.text = message
	msg.visible = message != ""
	var list: VBoxContainer = %List
	var spendable := int(info["cash"]) - int(info["min_buy_in"])

	# Pulls
	UI.label(list, "PULLS", "HeadingLabel")
	for id in catalog["sources"]:
		var src: Dictionary = catalog["sources"][id]
		var card := UI.vbox(UI.panel(list), 4)
		var top := UI.hbox(card, 10)
		var n := UI.label(top, src["name"])
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(top, UI.money(src["price"]), "HeadingLabel")
		if src.has("blurb"):
			UI.label(card, src["blurb"], "MutedLabel")
		var p: Dictionary = src["pity"]
		UI.label(card, "Guaranteed %s or better within %d pulls (%d so far)" % [
			p["rarity"], int(p["within"]), int(pity.get(id, 0))], "MutedLabel")
		var locked := int(info["rep"]) < int(src["rep_required"])
		var b := UI.button(card, "NEEDS %d REP" % int(src["rep_required"]) if locked else "PULL",
			func(): pull.emit(id), "AccentButton")
		b.disabled = locked or int(src["price"]) > spendable

	# Unopened (pulled or looted, not dynoed yet)
	var unopened := inventory.filter(func(i): return not i["revealed"])
	if not unopened.is_empty():
		UI.label(list, "UNOPENED", "HeadingLabel")
		for inst in unopened:
			var part := part_by_id(catalog, inst["part"])
			var row := UI.hbox(UI.panel(list), 10)
			var n := UI.label(row, part["name"])
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UI.label(row, str(part["rarity"]).to_upper(), "", RARITY_COLORS[part["rarity"]])
			UI.button(row, "DYNO IT", func(): reveal.emit(inst["uid"]), "AccentButton")

	# The counter: commons, new in box
	UI.label(list, "THE COUNTER (COMMONS, NEW)", "HeadingLabel")
	for part in catalog["parts"]:
		if part["rarity"] != "common":
			continue
		var card := UI.vbox(UI.panel(list), 4)
		var top := UI.hbox(card, 10)
		var n := UI.label(top, part["name"])
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(top, str(catalog["slots"][part["slot"]]), "MutedLabel")
		for line in part["effects_text"]:
			UI.label(card, line)
		var row := UI.hbox(card, 10)
		var price := UI.label(row, UI.money(part["price"]), "HeadingLabel")
		price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := UI.button(row, "BUY", func(): buy.emit(part["id"]), "AccentButton")
		b.disabled = int(part["price"]) > spendable

	# Spares: owned, revealed, not installed
	var spares := inventory.filter(func(i): return i["revealed"] and not i["uid"] in installed.values())
	UI.label(list, "SPARES", "HeadingLabel")
	if spares.is_empty():
		UI.label(list, "Nothing on the shelf.", "MutedLabel")
	for inst in spares:
		var part := part_by_id(catalog, inst["part"])
		var card := UI.vbox(UI.panel(list), 4)
		var top := UI.hbox(card, 10)
		var n := UI.label(top, "%s  (Q %d%%)" % [part["name"], int(round(float(inst["quality"]) * 100))])
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(top, str(part["rarity"]).to_upper(), "", RARITY_COLORS[part["rarity"]])
		for line in inst.get("effects_text", []):
			UI.label(card, line, "MutedLabel")
		var value := int(round(float(part["price"]) * SCRAP_RATE * (0.5 + float(inst["quality"]))))
		UI.button(card, "SELL FOR %s" % UI.money(value), func(): sell.emit(inst["uid"]))
