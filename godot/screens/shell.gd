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

const SLIDE_PX := 26.0        # a new screen slides up into place from this far down...
const SLIDE_S := 0.16         # ...this fast, fading in
const COUNT_S := 0.7          # cash and rep count to their new value over this long

var taps := 0
var last_tap_ms := 0
var animate := true           # off for the automated stills and tests (game.gd still_mode)
var cash_shown := -1          # what the receipt shows (counting toward the real value)
var rep_shown := -1
var counter: Tween

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


## Cash and rep on the receipt. A change counts up (or down) to the new
## number, and the receipt jumps a little when you've gained.
func set_stats(cash: int, rep: int, min_buy_in: int) -> void:
	if not animate or cash_shown < 0 or (cash == cash_shown and rep == rep_shown):
		cash_shown = cash
		rep_shown = rep
		show_stats(cash, rep)
		return
	var gained := cash > cash_shown or rep > rep_shown
	var c0 := cash_shown
	var r0 := rep_shown
	cash_shown = cash
	rep_shown = rep
	if counter != null:
		counter.kill()
	counter = create_tween()
	counter.tween_method(func(f: float): show_stats(roundi(lerpf(c0, cash, f)), roundi(lerpf(r0, rep, f))),
		0.0, 1.0, COUNT_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if gained:
		var r: Control = %Receipt
		r.pivot_offset = r.size / 2.0
		var pop := create_tween()
		pop.tween_property(r, "scale", Vector2(1.08, 1.08), 0.08)
		pop.tween_property(r, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func show_stats(cash: int, rep: int) -> void:
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
	# A screen with its own full-screen backdrop (home: the garage on tape)
	# puts it behind everything, the top rail and the nav included; the others
	# get the pegboard wall.
	for child in %Backdrop.get_children():
		child.queue_free()
	var backdrop: Control = screen.backdrop() if screen.has_method("backdrop") else null
	if backdrop != null:
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		%Backdrop.add_child(backdrop)
	%Pegboard.visible = backdrop == null
	%ShopLight.visible = backdrop == null
	if animate:                              # slide up into place, fading in
		screen.modulate.a = 0.0
		screen.position.y = SLIDE_PX
		var tw := screen.create_tween().set_parallel()
		tw.tween_property(screen, "modulate:a", 1.0, SLIDE_S)
		tw.tween_property(screen, "position:y", 0.0, SLIDE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
