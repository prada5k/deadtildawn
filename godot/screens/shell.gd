extends Control
## The hub shell: the garage wall that stays on screen while you move between
## the hub screens (pegboard, taped name, cash receipt, Dymo location label, and
## the tool-chest drawer nav). game.gd creates it once
## and swaps ONLY the content slot, so the nav never rebuilds or flickers.
## LAYOUT lives in shell.tscn; data hooks use scene unique names (%Name), so
## nodes can be moved around freely in the editor.

signal go(target: String)    # "shop", "car", "warehouse", "calendar", "team"

const UI := preload("res://ui.gd")

@onready var nav := {
	"shop": %ShopButton, "car": %CarButton, "warehouse": %WarehouseButton,
	"calendar": %CalendarButton, "team": %ExtraNavButton,
}


func _ready() -> void:
	for target in nav:
		nav[target].pressed.connect(func(): go.emit(target))
	# %ExtraNavButton is the TEAM drawer (the Polaroid board)


func set_stats(cash: int, rep: int, min_buy_in: int) -> void:
	%Cash.text = UI.money(cash)              # money is always green, rep always orange (theme)
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
