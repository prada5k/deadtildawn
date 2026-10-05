extends Control
## SETTINGS (Spire): from the "settings" tape on the top rail. Each row is a
## setting and a tape button that flips it. game.gd owns the values
## (state["settings"], SETTINGS there lists them with their labels).
## A hub screen. LAYOUT lives in settings.tscn; data hooks use %Name.

signal go(target: String)    # hub contract: "warehouse"
signal toggle(key: String)

const UI := preload("res://ui.gd")


func _ready() -> void:
	%Back.pressed.connect(func(): go.emit("warehouse"))


## rows: [{key, label, on}]
func setup(rows: Array) -> void:
	for c in %List.get_children():
		c.queue_free()
	for r: Dictionary in rows:
		var row := UI.hbox(%List, 12)
		var l := UI.label(row, r["label"], "InkLabel")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = r["key"]
		UI.button(row, "ON" if r["on"] else "OFF", func(): toggle.emit(key), "SmallTapeButton")
