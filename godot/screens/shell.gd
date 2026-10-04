extends Control
## The hub shell: the garage wall that stays on screen while you move between
## the hub screens (pegboard, taped name, cash receipt, Dymo location label, and
## the tool-chest drawer nav). game.gd creates it once
## and swaps ONLY the content slot, so the nav never rebuilds or flickers.
## LAYOUT lives in shell.tscn; data hooks use scene unique names (%Name), so
## nodes can be moved around freely in the editor.

signal go(target: String)    # "shop", "car", "warehouse", "calendar", "team", "codes"

const UI := preload("res://ui.gd")
const CODE_TAPS := 5          # taps on FABA's name tape that open the codes (testing)
const CODE_TAP_GAP_MS := 1500 # max time between them

var taps := 0
var last_tap_ms := 0

@onready var nav := {
	"shop": %ShopButton, "car": %CarButton, "warehouse": %WarehouseButton,
	"calendar": %CalendarButton, "team": %ExtraNavButton,
}


func _ready() -> void:
	for target in nav:
		nav[target].pressed.connect(func(): go.emit(target))
	# %ExtraNavButton is the TEAM drawer (the Polaroid board)
	%DriverName.mouse_filter = Control.MOUSE_FILTER_STOP
	%DriverName.gui_input.connect(_on_name_tape)


## Hidden: tap the name tape CODE_TAPS times quickly for the codes screen.
func _on_name_tape(event: InputEvent) -> void:
	var tapped: bool = ((event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed))
	if not tapped:
		return
	var now := Time.get_ticks_msec()
	taps = taps + 1 if now - last_tap_ms < CODE_TAP_GAP_MS else 1
	last_tap_ms = now
	if taps >= CODE_TAPS:
		taps = 0
		go.emit("codes")


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
