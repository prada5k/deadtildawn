extends Control
## WHO'S WHO (Spire: "like pokemon"): a new save asks for your name, your
## driver's name and your rival's name before the story. Blank = the default
## (Voice.NAME_DEFAULTS). The questions are in voice.gd. Full screen, no shell.
## LAYOUT lives in names.tscn; data hooks use %Name.

signal done(player: String, driver: String, rival: String)

const Voice := preload("res://voice.gd")


func _ready() -> void:
	# The questions mention the defaults: shown as typed (no name swap yet)
	for l: Label in [%PlayerAsk, %DriverAsk, %RivalAsk]:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	%PlayerAsk.text = Voice.NAME_ASK_PLAYER
	%DriverAsk.text = Voice.NAME_ASK_DRIVER
	%RivalAsk.text = Voice.NAME_ASK_RIVAL
	%Player.placeholder_text = Voice.NAME_DEFAULTS["player"]
	%Driver.placeholder_text = Voice.NAME_DEFAULTS["driver"]
	%Rival.placeholder_text = Voice.NAME_DEFAULTS["rival"]
	for e: LineEdit in [%Player, %Driver, %Rival]:
		e.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	%Go.pressed.connect(func(): done.emit(pick(%Player, "player"), pick(%Driver, "driver"), pick(%Rival, "rival")))


func pick(e: LineEdit, key: String) -> String:
	var s := e.text.strip_edges()
	return s if s != "" else String(Voice.NAME_DEFAULTS[key])
