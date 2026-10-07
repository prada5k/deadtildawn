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


func set_stats(cash: int, followers: int) -> void:
	%Cash.text = "CASH ON HAND %s" % UI.money(cash)
	%Cash.remove_theme_color_override("font_color")
	%Rep.text = "%d FOLLOWERS" % followers


## HOME lets its 3D hero run behind the top metadata. Other tabs keep the
## conventional padded shell presentation.
func set_home_mode(enabled: bool) -> void:
	%ContentMargin.add_theme_constant_override("margin_left", 0 if enabled else 24)
	%ContentMargin.add_theme_constant_override("margin_top", 0 if enabled else 184)
	%ContentMargin.add_theme_constant_override("margin_right", 0 if enabled else 24)
	%ContentMargin.add_theme_constant_override("margin_bottom", 0 if enabled else 18)
	%TopRail.visible = not enabled
	%LocationRibbon.visible = not enabled
	set_meta("home_mode", enabled)


func is_home_mode() -> bool:
	return bool(get_meta("home_mode", false))


func navigation_labels() -> Array:
	return [%CarButton.text, %CalendarButton.text, %WarehouseButton.text,
		%ExtraNavButton.text, %ShopButton.text]


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
