extends Control
## Parts ($$$): a corkboard of pull flyers, the bench (unopened boxes), the
## counter's receipt pad (commons, new), and the shelf (spares).
## LAYOUT lives in shop.tscn; the sections and cards are built here (their
## number changes), styled by theme variations (CorkPanel, Flyer*Panel,
## CardboardPanel, ReceiptPanel, PaperPanel...), plus the rarity inks below.

signal go(target: String)       # "car"
signal pull(source: String)
signal buy(part_id: String)     # commons only
signal sell(uid: String)
signal reveal(uid: String)
signal repair(uid: String)      # damaged in a crash: off the car until repaired

const UI := preload("res://ui.gd")
const PartArt := preload("res://widgets/part_art.gd")
const Voice := preload("res://voice.gd")
const PIN := preload("res://textures/pin.png")
const PIC_PX := 112            # a part's picture on the counter + the shelf (Spire: bigger)
const BENCH_PIC_PX := 96       # an unopened box on the bench
# Rarity as ink on paper (darker than the reveal's glow colors in game.gd)
const RARITY_INK := {
	"common": Color(0.36, 0.36, 0.4),
	"rare": Color(0.12, 0.3, 0.7),
	"epic": Color(0.45, 0.18, 0.62),
	"legendary": Color(0.7, 0.45, 0.0),
}
const FLYERS := ["FlyerYellowPanel", "FlyerPinkPanel", "FlyerBluePanel"]
const SCRAP_RATE := 0.25        # keep in sync with game.gd
const REPAIR_RATE := 0.30       # keep in sync with game.gd


func part_by_id(catalog: Dictionary, id: String) -> Dictionary:
	for p in catalog["parts"]:
		if p["id"] == id:
			return p
	return {}


## A section header: Sharpie on a strip of masking tape, slightly crooked.
func tape_header(parent: Node, text: String, tilt := -0.015) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "TapeLabel"
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.rotation = tilt
	parent.add_child(l)
	return l


## A label that wraps to its column's width.
func wrap_label(parent: Node, s: String, style: String, color = null) -> Label:
	var l := UI.label(parent, s, style, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## info: cash, rep, min_buy_in; catalog: bridge "parts" reply (parts, slots,
## sources); inventory: [instances]; installed: {slot: uid}; pity: {source: n}
func setup(info: Dictionary, catalog: Dictionary, inventory: Array, installed: Dictionary,
		pity: Dictionary, message := "") -> void:
	var msg: Label = %Message
	msg.text = message
	msg.visible = message != ""
	var list: VBoxContainer = %List
	var spendable := int(info["cash"]) - int(info["min_buy_in"])

	# Damaged in a crash: first, because it's what you need after a bad night
	var damaged := inventory.filter(func(i): return i.get("damaged", false))
	if not damaged.is_empty():
		tape_header(list, "busted")
		for inst in damaged:
			var part := part_by_id(catalog, inst["part"])
			var card := UI.vbox(paper(list, "PaperPanel", 0.006), 4)
			var top := UI.hbox(card, 10)
			var n := UI.label(top, "%s  (Q %d%%)" % [part["name"], int(round(float(inst["quality"]) * 100))],
				"InkLabel")
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var stamp := UI.label(top, "DAMAGED", "StampLabel")
			stamp.rotation = 0.1
			wrap_label(card, "In its slot but off the car until repaired."
				if inst["uid"] in installed.values() else "On the shelf, broken.", "InkMutedLabel")
			var cost := int(round(float(part["price"]) * REPAIR_RATE))
			var b := UI.button(card, "repair it  %s" % UI.money(cost),
				func(): repair.emit(inst["uid"]), "GaffSmallButton")
			b.size_flags_horizontal = Control.SIZE_SHRINK_END
			b.disabled = cost > spendable

	# Pulls: flyers pinned on the corkboard
	tape_header(list, "pulls", 0.012)
	var cork := PanelContainer.new()
	cork.theme_type_variation = "CorkPanel"
	list.add_child(cork)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 22)
	cork.add_child(grid)
	var i := 0
	for id in catalog["sources"]:
		flyer(grid, id, catalog["sources"][id], i, int(info["rep"]), spendable, int(pity.get(id, 0)))
		i += 1

	# The bench: pulled or looted boxes, not dynoed yet
	var unopened := inventory.filter(func(inst): return not inst["revealed"])
	if not unopened.is_empty():
		tape_header(list, "on the bench")
		for inst in unopened:
			var part := part_by_id(catalog, inst["part"])
			var box := PanelContainer.new()
			box.theme_type_variation = "CardboardPanel"
			box.rotation = -0.008
			list.add_child(box)
			var row := UI.hbox(box, 10)
			picture(row, "", BENCH_PIC_PX)               # unopened: still a box
			var col := UI.vbox(row, 0)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			wrap_label(col, part["name"], "FlyerTitleLabel")
			UI.label(col, str(part["rarity"]).to_upper(), "InkMutedLabel", RARITY_INK[part["rarity"]])
			var b := UI.button(row, "dyno it", func(): reveal.emit(inst["uid"]), "GaffSmallButton")
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# The counter: commons, new in box, on a receipt pad
	tape_header(list, "the counter", 0.01)
	var pad := UI.vbox(paper(list, "ReceiptPanel", -0.004), 4)
	var shop_name := UI.label(pad, "CANYON AUTO PARTS", "InkHeadingLabel")
	shop_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := UI.label(pad, "COUNTER  //  NEW IN BOX  //  NO RETURNS", "InkMutedLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for part in catalog["parts"]:
		if part["rarity"] != "common":
			continue
		UI.label(pad, "- - - - - - - - - - - - - - - - - - - - - - - - - - -", "InkMutedLabel") \
			.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var top := UI.hbox(pad, 10)
		picture(top, part["id"], PIC_PX)
		var n := UI.label(top, part["name"], "InkLabel")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(top, str(catalog["slots"][part["slot"]]).to_upper(), "InkMutedLabel")
		for line in part["effects_text"]:
			wrap_label(pad, line, "FlyerTextLabel")
		var row := UI.hbox(pad, 10)
		var price := UI.label(row, UI.money(part["price"]), "InkMoneyBigLabel")
		price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := UI.button(row, "buy", func(): buy.emit(part["id"]), "SmallTapeButton")
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = int(part["price"]) > spendable

	# The shelf: owned, revealed, not installed, not damaged (those are above)
	var spares := inventory.filter(func(inst): return (inst["revealed"] and not inst.get("damaged", false)
		and not inst["uid"] in installed.values()))
	tape_header(list, "the shelf", -0.01)
	var shelf := UI.vbox(paper(list, "PaperPanel", 0.004), 6)
	if spares.is_empty():
		UI.label(shelf, "Nothing on the shelf.", "InkMutedLabel")
	for inst in spares:
		var part := part_by_id(catalog, inst["part"])
		var top := UI.hbox(shelf, 10)
		picture(top, part["id"], PIC_PX)
		var n := UI.label(top, "%s  (Q %d%%)" % [part["name"], int(round(float(inst["quality"]) * 100))],
			"InkLabel")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(top, str(part["rarity"]).to_upper(), "InkMutedLabel", RARITY_INK[part["rarity"]])
		for line in inst.get("effects_text", []):
			wrap_label(shelf, line, "FlyerTextLabel")
		var value := int(round(float(part["price"]) * SCRAP_RATE * (0.5 + float(inst["quality"]))))
		var b := UI.button(shelf, "scrap it  %s" % UI.money(value), func(): sell.emit(inst["uid"]),
			"SmallTapeButton")
		b.size_flags_horizontal = Control.SIZE_SHRINK_END


## A part's picture (widgets/part_art.gd), px square; "" = a plain box.
func picture(parent: Node, id: String, px: float) -> Control:
	var pic: Control = PartArt.new()
	pic.theme_type_variation = "PartArt"
	pic.custom_minimum_size = Vector2(px, px)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.part_id = id
	parent.add_child(pic)
	return pic


## A paper-ish panel (variation) with a slight tilt.
func paper(parent: Node, variation: String, tilt: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.rotation = tilt
	parent.add_child(p)
	return p


## One pull source as a flyer pinned to the cork: name, price, blurb, pity, PULL.
func flyer(grid: GridContainer, id: String, src: Dictionary, index: int, rep: int,
		spendable: int, pity_count: int) -> void:
	var sheet := paper(grid, FLYERS[index % FLYERS.size()], [-0.025, 0.02, 0.012][index % 3])
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := UI.vbox(sheet, 4)
	var pin := TextureRect.new()
	pin.texture = PIN
	pin.custom_minimum_size = Vector2(30, 30)
	pin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(pin)
	wrap_label(col, str(src["name"]).to_upper(), "FlyerTitleLabel")
	UI.label(col, UI.money(src["price"]), "FlyerPriceLabel")
	if Voice.FLYERS.has(id):                     # the builder's scribble (own line: it wraps)
		wrap_label(col, Voice.FLYERS[id], "MarkerLabel").rotation = -0.05
	wrap_label(col, Voice.PULL_BLURBS.get(id, ""), "FlyerTextLabel")
	var p: Dictionary = src["pity"]
	wrap_label(col, "Sure %s or better within %d pulls (%d so far)" % [p["rarity"], int(p["within"]), pity_count],
		"InkMutedLabel")
	UI.spacer(col)
	if rep < int(src["rep_required"]):
		var stamp := UI.label(col, "NEEDS %d REP" % int(src["rep_required"]), "StampLabel")
		stamp.autowrap_mode = TextServer.AUTOWRAP_OFF    # shrunk + wrapping = one letter per line
		stamp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stamp.rotation = -0.08
	else:
		var b := UI.button(col, "pull", func(): pull.emit(id), "GaffSmallButton")
		b.disabled = int(src["price"]) > spendable
