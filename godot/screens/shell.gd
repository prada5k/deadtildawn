extends Control
## The hub shell: the garage wall that stays on screen while you move between
## the hub screens (pegboard, taped name, cash receipt, Dymo location label, and
## the tool-chest drawer nav). game.gd creates it once
## and swaps ONLY the content slot, so the nav never rebuilds or flickers.
## LAYOUT lives in shell.tscn; data hooks use scene unique names (%Name), so
## nodes can be moved around freely in the editor.

signal go(target: String)    # "shop", "car", "warehouse", "calendar"

const UI := preload("res://ui.gd")

@onready var nav := {
	"shop": %ShopButton, "car": %CarButton, "warehouse": %WarehouseButton,
	"calendar": %CalendarButton,
}


func _ready() -> void:
	for target in nav:
		nav[target].pressed.connect(func(): go.emit(target))
	# %ExtraNavButton is the TEAM drawer (Polaroid board, docs/ART_DIRECTION.md): disabled for now


func set_stats(cash: int, rep: int, min_buy_in: int) -> void:
	%Cash.text = UI.money(cash)
	# Printed on the receipt: dark ink colors that read on white paper
	%Cash.add_theme_color_override("font_color", UI.INK if cash >= min_buy_in else UI.INK_BAD)
	%Rep.text = "REP %d" % rep


func set_location(text: String, tab: String) -> void:
	%LocationLabel.text = text
	for target in nav:
		nav[target].theme_type_variation = "DrawerOpenButton" if target == tab else "DrawerButton"


## Replace the content slot's screen with a new one (the old one is freed).
func set_content(screen: Control) -> void:
	for child in %ContentSlot.get_children():
		child.queue_free()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	%ContentSlot.add_child(screen)
