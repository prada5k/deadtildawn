extends Control
## Physical parts shop. The scene owns layout; game.gd owns cash, inventory,
## listings and save transactions.

signal go(target: String)
signal buy_retail(part_id: String)
signal buy_used(listing_id: String)

const UI := preload("res://ui.gd")


func part_by_id(catalog: Dictionary, id: String) -> Dictionary:
	for p in catalog["parts"]:
		if p["id"] == id:
			return p
	return {}


func part_card(list: VBoxContainer, catalog: Dictionary, part: Dictionary) -> VBoxContainer:
	var card := UI.vbox(UI.panel(list), 4)
	var top := UI.hbox(card, 10)
	var name := UI.label(top, part["name"])
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(top, str(catalog["slots"][part["slot"]]), "MutedLabel")
	for line in part["effects_text"]:
		UI.label(card, line, "MutedLabel")
	return card


func setup(info: Dictionary, catalog: Dictionary, inventory: Array, installed: Dictionary,
		used_listings: Array, message := "") -> void:
	var msg: Label = %Message
	msg.text = message
	msg.visible = message != ""
	var list: VBoxContainer = %List
	var cash := int(info["cash"])

	UI.label(list, "RETAIL", "HeadingLabel")
	for id in catalog["retail_ids"]:
		var part := part_by_id(catalog, id)
		var card := part_card(list, catalog, part)
		var row := UI.hbox(card, 10)
		var price := UI.label(row, UI.money(part["price"]), "HeadingLabel")
		price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var buy := UI.button(row, "BUY", func(): buy_retail.emit(id), "AccentButton")
		buy.disabled = int(part["price"]) > cash

	UI.label(list, "USED", "HeadingLabel")
	if used_listings.is_empty():
		UI.label(list, "No current listings.", "MutedLabel")
	for listing in used_listings:
		var part := part_by_id(catalog, listing["part"])
		if part.is_empty():
			continue
		var card := part_card(list, catalog, part)
		UI.label(card, "%s  //  %s" % [listing["seller_name"], listing["note"]], "MutedLabel")
		var row := UI.hbox(card, 10)
		var price := UI.label(row, UI.money(listing["price"]), "HeadingLabel")
		price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var buy := UI.button(row, "BUY LISTING", func(): buy_used.emit(listing["listing_id"]), "AccentButton")
		buy.disabled = int(listing["price"]) > cash

	UI.label(list, "OWNED PARTS", "HeadingLabel")
	if inventory.is_empty():
		UI.label(list, "Nothing on the shelf yet.", "MutedLabel")
	for inst in inventory:
		var part := part_by_id(catalog, inst["part"])
		if part.is_empty():
			continue
		var card := UI.vbox(UI.panel(list), 4)
		var location := "INSTALLED" if inst["uid"] in installed.values() else "ON SHELF"
		UI.label(card, "%s  //  %s" % [part["name"], location])
		UI.label(card, "%s  /  %s" % [inst["uid"], inst["source"]], "MutedLabel")
