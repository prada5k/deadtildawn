extends Control
## Race night, step 1 (Spire): tonight's road, before anyone knows who's
## running. The map with the corner key, and the DX as it sits. Build for the
## road in CAR, then LOCK IT IN: the build is set for the night and THEN the
## opponent is matched to it (game.gd lock_build()).
## A hub screen (in the shell). LAYOUT lives in scout.tscn; hooks use %Name.

signal go(target: String)    # hub contract
signal car_pressed
signal lock_pressed
signal skip_pressed

const UI := preload("res://ui.gd")
const Voice := preload("res://voice.gd")


func _ready() -> void:
	%WorkOnCar.pressed.connect(func(): car_pressed.emit())
	%LockIn.pressed.connect(func(): lock_pressed.emit())
	%SkipButton.pressed.connect(func(): skip_pressed.emit())


## info: where, road_info, track (bridge "track" reply), stats (car_stats),
## read (bridge "road_read": what the road rewards, for this build),
## parts_on (count), can_skip, skip_cost
func setup(info: Dictionary) -> void:
	%Where.text = info["where"]
	%RoadInfo.text = info["road_info"]
	%Map.track = info["track"]
	%Map.labels = false                         # colors + the key, no corner names (Spire)
	%Map.queue_redraw()
	var read: Dictionary = info["read"]
	%ReadNote.text = Voice.ROAD_KIND.get(read["kind"], "")
	var tight: Variant = read["tightest"]
	for row in [
		["Straights", "%d%% of the road" % roundi(float(read["straight_share"]) * 100)],
		["Full throttle", "%d%% of the run" % roundi(float(read["full_throttle"]) * 100)],
		["On the brakes", "%d%% of the run" % roundi(float(read["braking"]) * 100)],
		["Longest straight", "%d m" % roundi(float(read["longest_straight"]))],
		["Tightest", "none" if tight == null else "%s  (%d m)" % [tight["text"], roundi(float(tight["radius"]))]],
		["Hairpins", str(read["hairpins"])],
	]:
		UI.stat_row(%Read, row[0], row[1], "InkMutedLabel", "InkLabel")
	var s: Dictionary = info["stats"]
	for row in [
		["Power", "%d hp, %d lb-ft" % [s["hp"], s["torque_lbft"]]],
		["Weight", "%d kg  (%d hp/t)" % [s["weight_kg"], s["hp_per_tonne"]]],
		["0-60 mph", "%.2f s" % s["zero_60_s"]],
		["Skidpad", "%.2f g" % s["skidpad_g"]],
		["Parts on", str(info["parts_on"])],
	]:
		UI.stat_row(%BuildStats, row[0], row[1], "InkMutedLabel", "InkLabel")
	%SkipButton.text = "skip  -%d rep" % int(info["skip_cost"])
	%SkipButton.disabled = not info["can_skip"]
