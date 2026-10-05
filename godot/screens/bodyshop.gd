extends Control
## THE BODY SHOP (Spire: "make the cars look better"): cosmetics for the DX
## (bodyshop.gd). The DX up on the lift shows the car as it'll look: tap
## "try" on anything to see it on, then buy it; what you own you wear or take
## off for free. Looks only, none of it reaches the sim.
## A hub screen. LAYOUT lives in bodyshop.tscn; data hooks use %Name.

signal go(target: String)    # hub contract: "car"
signal buy(id: String)
signal wear(id: String)
signal take_off(slot: String)

const UI := preload("res://ui.gd")
const BodyShop := preload("res://bodyshop.gd")
const Voice := preload("res://voice.gd")

var info := {}
var trying := ""             # the item on preview ("" = none)


func _ready() -> void:
	%Lift.lower()                # the car comes down to the floor: easier to see what you're putting on it
	%Back.pressed.connect(func(): go.emit("car"))
	%Buy.pressed.connect(func():
		if trying != "":
			buy.emit(trying))


## info: parts (installed part ids), owned ([ids]), worn ({slot: id}),
## spendable (cash over the buy-in), message
func setup(i: Dictionary) -> void:
	info = i
	%Note.text = Voice.BODYSHOP_NOTE
	%Message.text = info.get("message", "")
	%Message.visible = %Message.text != ""
	var list: VBoxContainer = %List
	for c in list.get_children():
		c.queue_free()
	var owned: Array = info["owned"]
	var worn: Dictionary = info["worn"]
	for slot in BodyShop.SLOTS:
		var head := UI.label(list, str(BodyShop.SLOTS[slot]).to_upper(), "InkHeadingLabel")
		head.add_theme_font_size_override("font_size", 22)
		for id in BodyShop.ITEMS:
			var item: Dictionary = BodyShop.ITEMS[id]
			if item["slot"] != slot:
				continue
			var row := UI.hbox(list, 10)
			var name := UI.label(row, item["name"], "InkLabel")
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if worn.get(slot, "") == id:
				UI.label(row, "ON", "InkMutedLabel")
				UI.button(row, "take off", func(): take_off.emit(slot), "SmallTapeButton")
			elif id in owned:
				UI.button(row, "wear", func(): wear.emit(id), "SmallTapeButton")
			else:
				UI.label(row, UI.money(int(item["price"])), "InkMoneyLabel")
				UI.button(row, "try", func(): try_on(id), "SmallTapeButton")
	show_car()


## Preview an item on the car (in its slot, over whatever's worn there).
func try_on(id: String) -> void:
	trying = id
	show_car()


func show_car() -> void:
	var worn: Dictionary = info["worn"].duplicate()
	if trying != "":
		worn[BodyShop.ITEMS[trying]["slot"]] = trying
	%Lift.show_parts(info["parts"] + BodyShop.look_tags(worn))
	%TryBar.visible = trying != ""
	if trying != "":
		var item: Dictionary = BodyShop.ITEMS[trying]
		%TryName.text = item["name"]
		%Buy.text = "buy it  %s" % UI.money(int(item["price"]))
		%Buy.disabled = int(item["price"]) > int(info["spendable"])
