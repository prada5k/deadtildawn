extends Control
## Home: the main hub's content, over the garage footage (the shell's stage:
## the DX in its stall): the camcorder's title, the light over the car (Spire:
## brightness buttons), the next race, GET READY.
## LAYOUT lives in warehouse.tscn. Data hooks use scene unique names (%Name),
## so you can move nodes anywhere in the editor without breaking this script,
## as long as each node keeps its name and its "Access as Unique Name" flag.

signal go(target: String)    # "race", "story"
signal light(level: int)     # the tube over the DX (Spire: brightness buttons), 0..LEVELS-1
signal strobes(on: bool)     # the strobes (once bought in the body shop)

const LEVELS := 5
var level := 3
var strobing := false


func _ready() -> void:
	%LightDown.pressed.connect(func(): set_light(level - 1))
	%LightUp.pressed.connect(func(): set_light(level + 1))
	%StrobeButton.pressed.connect(func():
		strobing = not strobing
		show_strobes()
		strobes.emit(strobing))
	%GetReady.pressed.connect(func(): go.emit("race"))
	%StoryButton.pressed.connect(func(): go.emit("story"))


func set_light(l: int) -> void:
	level = clampi(l, 0, LEVELS - 1)
	show_light()
	light.emit(level)


func show_strobes() -> void:
	%StrobeButton.theme_type_variation = "OsdOnButton" if strobing else "OsdButton"


func show_light() -> void:
	%LightLevel.text = "#".repeat(level) + ".".repeat(LEVELS - 1 - level)


## Called by game.gd after the screen is added.
func setup(info: Dictionary) -> void:
	level = int(info.get("light", 3))
	show_light()
	%StrobeButton.visible = bool(info.get("has_strobes", false))   # only once bought + worn (body shop)
	strobing = bool(info.get("strobes_on", false))
	show_strobes()
	%Caption.text = info["caption"]          # the builder's note (game.gd home_caption, voice.gd)
	%WorkOrderNo.text = "WORK ORDER #%03d" % info["order_no"]
	%When.text = info["when"]
	%EventTitle.text = info["event_kind"]
	%Stamp.text = "RIVAL" if info["event_type"] == "rival" else "OPEN"
	%EventDetail.text = info["event_detail"]
	%Record.text = "Record %d W - %d L   /   buy-in %s" % [
		info["wins"], info["losses"], info["min_buy_in_text"]]
