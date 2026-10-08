extends Control
## Physical parts shop. The scene owns layout; game.gd owns cash, inventory,
## listings and save transactions.

signal go(target: String)
signal buy_retail(part_id: String)
signal buy_used(listing_id: String)

const UI := preload("res://ui.gd")
const DAY_NAMES := ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]


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
		used_listings: Array, deliveries: Array, message := "") -> void:
	var msg: Label = %Message
	msg.text = message
	msg.visible = message != ""
	var list: VBoxContainer = %List
	var cash := int(info["cash"])

	UI.label(list, "RETAIL / AVAILABLE TO ORDER / %d-DAY DELIVERY ESTIMATE" % int(catalog.get("retail_delivery_days", 0)), "HeadingLabel")
	for id in catalog["retail_ids"]:
		var part := part_by_id(catalog, id)
		var card := part_card(list, catalog, part)
		var row := UI.hbox(card, 10)
		var price := UI.label(row, UI.money(part["price"]), "HeadingLabel")
		price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var buy := UI.button(row, "ORDER", func(): buy_retail.emit(id), "AccentButton")
		buy.disabled = int(part["price"]) > cash

	UI.label(list, "USED / AVAILABLE LISTINGS", "HeadingLabel")
	var available_count := used_listings.filter(func(item): return item.get("status", "available") == "available").size()
	if available_count == 0:
		UI.label(list, "No current listings.", "MutedLabel")
	for listing in used_listings:
		if listing.get("status", "available") != "available":
			continue
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

	UI.label(list, "PURCHASED / IN TRANSIT", "HeadingLabel")
	var transit_count := deliveries.filter(func(order): return order.get("status", "") == "in_transit").size()
	if transit_count == 0:
		UI.label(list, "Nothing is on the way.", "MutedLabel")
	for order in deliveries:
		if order.get("status", "") != "in_transit":
			continue
		var part := part_by_id(catalog, str(order.get("definition_id", "")))
		var name := str(part.get("name", order.get("definition_id", "PART")))
		var date := "%s, WEEK %d" % [DAY_NAMES[int(order["arrival_day"])], int(order["arrival_week"])]
		UI.label(list, "%s / %s / %s / ARRIVES %s" % [name, order["owned_uid"], order["delivery_id"], date], "MutedLabel")

	UI.label(list, "SOLD / UNAVAILABLE LISTINGS", "HeadingLabel")
	var unavailable := used_listings.filter(func(item): return item.get("status", "available") != "available")
	if unavailable.is_empty():
		UI.label(list, "No sold or expired listings.", "MutedLabel")
	for listing in unavailable:
		var status := str(listing.get("status", "unavailable")).to_upper().replace("_", " ")
		var part := part_by_id(catalog, str(listing.get("part", "")))
		var part_name := str(part.get("name", listing.get("part", "PART")))
		UI.label(list, "%s / %s / %s / %s" % [str(listing.get("listing_id", "")), part_name, str(listing.get("seller_name", "")), status], "MutedLabel")

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
