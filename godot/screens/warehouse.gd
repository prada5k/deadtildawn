extends Control
## The warehouse: the main hub's content (the shell around it provides the top
## rail, location ribbon, and bottom nav).
## LAYOUT lives in warehouse.tscn. Data hooks use scene unique names (%Name),
## so you can move nodes anywhere in the editor without breaking this script,
## as long as each node keeps its name and its "Access as Unique Name" flag.

signal go(target: String)    # "race", "story"

@onready var event_title: Label = %EventTitle
@onready var event_detail: Label = %EventDetail
@onready var record: Label = %Record


func _ready() -> void:
	%GetReady.pressed.connect(func(): go.emit("race"))
	%StoryButton.pressed.connect(func(): go.emit("story"))


## Called by game.gd after the screen is added.
func setup(info: Dictionary) -> void:
	event_title.text = info["event_title"]
	event_detail.text = info["event_detail"]
	record.text = "Record %d W - %d L   /   minimum buy-in %s" % [
		info["wins"], info["losses"], info["min_buy_in_text"]]
