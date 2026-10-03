extends Control
## The warehouse: the main hub.
## LAYOUT lives in warehouse.tscn: open it in the editor, move or restyle
## anything. This script only fills in text and reports button presses, so
## rearranging nodes is safe as long as the node NAMES below still exist.

signal go(target: String)    # "race", "car", "calendar", "shop", "story"

@onready var header = $Margin/Column/Header
@onready var event_title: Label = $Margin/Column/NextUp/Box/EventTitle
@onready var event_detail: Label = $Margin/Column/NextUp/Box/EventDetail
@onready var record: Label = $Margin/Column/Crew/Box/Record


func _ready() -> void:
	$Margin/Column/NextUp/Box/GetReady.pressed.connect(func(): go.emit("race"))
	$Margin/Column/Nav/CarButton.pressed.connect(func(): go.emit("car"))
	$Margin/Column/Nav/CalendarButton.pressed.connect(func(): go.emit("calendar"))
	$Margin/Column/Nav/ShopButton.pressed.connect(func(): go.emit("shop"))
	$Margin/Column/StoryButton.pressed.connect(func(): go.emit("story"))


## Called by game.gd after the screen is added.
func setup(info: Dictionary) -> void:
	header.show_stats(info["cash"], info["rep"], info["min_buy_in"])
	event_title.text = info["event_title"]
	event_detail.text = info["event_detail"]
	record.text = "Record %d W - %d L   /   minimum buy-in %s" % [
		info["wins"], info["losses"], info["min_buy_in_text"]]
