extends Control
## The hub shell: everything that stays on screen while you move between the
## hub screens (top rail, location ribbon, bottom nav). game.gd creates it once
## and swaps ONLY the content slot, so the nav never rebuilds or flickers.
## LAYOUT lives in shell.tscn; data hooks use scene unique names (%Name), so
## nodes can be moved around freely in the editor.

signal go(target: String)    # "car", "calendar", "home", "team", "shop"

const UI := preload("res://ui.gd")

@onready var nav := {
	"car": %CarButton, "calendar": %CalendarButton, "home": %WarehouseButton,
	"team": %ExtraNavButton, "shop": %ShopButton,
}


func _ready() -> void:
	for target in nav:
		nav[target].pressed.connect(func(): go.emit(target))


func set_stats(cash: int, followers: int, min_buy_in: int) -> void:
	%Cash.text = UI.money(cash)
	%Cash.add_theme_color_override("font_color", UI.GOOD if cash >= min_buy_in else UI.BAD)
	%Rep.text = "%d FOLLOWERS" % followers


func set_location(text: String, tab: String) -> void:
	%LocationLabel.text = text
	for target in nav:
		nav[target].theme_type_variation = "SelectedButton" if target == tab else ""


## Replace the content slot's screen with a new one (the old one is freed).
func set_content(screen: Control) -> void:
	for child in %ContentSlot.get_children():
		child.queue_free()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	%ContentSlot.add_child(screen)
