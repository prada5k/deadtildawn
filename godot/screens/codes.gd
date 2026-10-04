extends Control
## Codes, for testing (Spire): a note to write a code on, and the cheat sheet
## (tap a code to write it in). Open it by tapping FABA's name tape 5 times
## in the hub, or the ` key. game.gd owns the codes (CODES, enter_code());
## this screen only emits what was punched in.
## LAYOUT lives in codes.tscn; data hooks use %Name.

signal go(target: String)    # (hub screen contract; unused here)
signal entered(code: String)
signal confirmed             # the second step of a code that asks first

const UI := preload("res://ui.gd")


func _ready() -> void:
	%Enter.pressed.connect(punch)
	%Field.text_submitted.connect(func(_t): punch())
	%Confirm.pressed.connect(func(): confirmed.emit())


## codes: {code: what it does}; message: the result of the last code;
## confirm: text for the confirm button ("" = hidden).
func setup(codes: Dictionary, message: String, confirm := "") -> void:
	%Message.text = message
	%Message.visible = message != ""
	%Confirm.text = confirm
	%Confirm.visible = confirm != ""
	for code in codes:
		var row := UI.hbox(%List, 12)
		var b := UI.button(row, code, fill.bind(code), "SmallTapeButton")
		b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var what := UI.label(row, codes[code], "InkLabel")
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Tapping the cheat sheet writes the code in; punching it in is still yours.
func fill(code: String) -> void:
	%Field.text = code
	%Field.caret_column = code.length()


func punch() -> void:
	var code: String = %Field.text
	if code.strip_edges() != "":
		entered.emit(code)
