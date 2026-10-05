extends Control
## Home: the main hub's content (the shell around it is the garage wall).
## A taped Polaroid of the DX at a canyon turnout (3D, widgets/overlook.gd,
## updates as parts go on), the next race as a shop work order, GET READY.
## LAYOUT lives in warehouse.tscn. Data hooks use scene unique names (%Name),
## so you can move nodes anywhere in the editor without breaking this script,
## as long as each node keeps its name and its "Access as Unique Name" flag.

signal go(target: String)    # "race", "story"

const GarageCam := preload("res://widgets/garage_cam.gd")

## The full-screen footage behind everything (the shell puts it behind the
## top rail and the nav too): the DX in the garage, on tape.
var garage := GarageCam.new()


func backdrop() -> Control:
	return garage


func _ready() -> void:
	%GetReady.pressed.connect(func(): go.emit("race"))
	%StoryButton.pressed.connect(func(): go.emit("story"))


## Called by game.gd after the screen is added.
func setup(info: Dictionary) -> void:
	var parts: Array = info.get("parts", [])
	garage.show_parts(parts)
	garage.show_parked_car(info.get("parked_car", true))
	%Caption.text = info["caption"]          # the builder's note (game.gd home_caption, voice.gd)
	%WorkOrderNo.text = "WORK ORDER #%03d" % info["order_no"]
	%When.text = info["when"]
	%EventTitle.text = info["event_kind"]
	%Stamp.text = "RIVAL" if info["event_type"] == "rival" else "OPEN"
	%EventDetail.text = info["event_detail"]
	%Record.text = "Record %d W - %d L   /   buy-in %s" % [
		info["wins"], info["losses"], info["min_buy_in_text"]]
