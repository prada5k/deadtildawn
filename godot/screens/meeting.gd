extends Control
## Race night, the driver meeting at the turnout: both cars parked under the
## headlights (3D, widgets/turnout_night.gd), Faba's take, the tech sheet on a
## clipboard (road map + stat card, no odds), push level, the bet, SEND IT.
## Full screen (no hub shell). LAYOUT lives in meeting.tscn; data hooks use
## scene unique names (%Name). Faba's lines come from voice.gd.
##
## This screen only reports choices (signals); game.gd keeps them and decides.

signal push_changed(push: String)
signal wager_changed(amount: int)
signal send_pressed
signal back_pressed
signal skip_pressed

const UI := preload("res://ui.gd")
const Voice := preload("res://voice.gd")
const TAP_SLOP_PX := 14.0     # moved less than this between press and release = a tap

var push := "normal"
var push_order: Array = []
var push_risk := {}            # push -> what you're risking, in plain words
var cash := 0
var min_buy_in := 0
var press_at := Vector2.ZERO   # where a touch on the map went down


func _ready() -> void:
	%SendIt.pressed.connect(func(): send_pressed.emit())
	%BackButton.pressed.connect(func(): back_pressed.emit())
	%SkipButton.pressed.connect(func(): skip_pressed.emit())
	%WagerSlider.value_changed.connect(set_wager)
	%Map.mouse_filter = Control.MOUSE_FILTER_PASS    # drags still scroll the page
	%Map.gui_input.connect(_on_map_input)
	%MapFull.gui_input.connect(_on_full_map_input)


## A tap (press and release without dragging) opens the map; a drag scrolls.
func _on_map_input(event: InputEvent) -> void:
	var p = press_release(event)
	if p == null:
		return
	if p:
		press_at = event.position
	elif event.position.distance_to(press_at) < TAP_SLOP_PX:
		open_map(true)


func _on_full_map_input(event: InputEvent) -> void:
	if press_release(event) == true:
		open_map(false)


## true on a press, false on a release, null for anything else.
func press_release(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		return event.pressed
	if event is InputEventScreenTouch:
		return event.pressed
	return null


## The road, full screen: big labels and every corner's radius. Tap to close.
func open_map(show: bool) -> void:
	%MapFull.visible = show
	if show:
		%FullMap.track = %Map.track
		%FullMap.label_size = 26
		%FullMap.details = true
		%FullMap.fit_turn = true                   # a wide road turns sideways to fill the phone
		%FullMap.queue_redraw()


## info: where, rival_night, opponent_car, faba_parts, road_info, track,
## mine / theirs (stat sheets), their_name, their_car_line, word,
## push, push_order, push_risk, wager, cash, min_buy_in, wager_step,
## can_skip, skip_cost
func setup(info: Dictionary) -> void:
	%Turnout.setup(info["opponent_car"], info["faba_parts"])
	%Where.text = info["where"]
	%FabaLine.text = Voice.FABA_RIVAL_NIGHT if info["rival_night"] else Voice.FABA_OPEN_NIGHT
	%RoadInfo.text = info["road_info"]
	%FullInfo.text = info["road_info"]
	%Map.track = info["track"]
	%Map.queue_redraw()
	fill_stats(info["mine"], info["theirs"], info["their_name"])
	%TheirCar.text = info["their_car_line"]
	%Word.text = "Word is: %s" % info["word"]

	push_order = info["push_order"]
	push_risk = info["push_risk"]
	select_push(info["push"])

	cash = int(info["cash"])
	min_buy_in = int(info["min_buy_in"])
	var slider: HSlider = %WagerSlider
	slider.min_value = min_buy_in
	slider.max_value = cash
	slider.step = info["wager_step"]
	slider.editable = cash > min_buy_in
	slider.set_value_no_signal(info["wager"])
	set_wager(info["wager"])

	%SkipButton.text = "skip  -%d rep" % int(info["skip_cost"])
	%SkipButton.disabled = not info["can_skip"]


## Stat card: three columns (what, the DX, them), ink on the tech sheet.
func fill_stats(mine: Dictionary, theirs: Dictionary, their_name: String) -> void:
	var grid: GridContainer = %Stats
	for c in grid.get_children():
		c.queue_free()
	var rows := [
		["", "FABA / DX", their_name.to_upper()],
		["Power", "%d hp" % mine["hp"], "%d hp" % theirs["hp"]],
		["Torque", "%d lb-ft" % mine["torque_lbft"], "%d lb-ft" % theirs["torque_lbft"]],
		["Weight", "%d kg" % mine["weight_kg"], "%d kg" % theirs["weight_kg"]],
		["Power / weight", "%d hp/t" % mine["hp_per_tonne"], "%d hp/t" % theirs["hp_per_tonne"]],
		["Drivetrain", str(mine["drivetrain"]), str(theirs["drivetrain"])],
		["0-60 mph", "%.2f s" % mine["zero_60_s"], "%.2f s" % theirs["zero_60_s"]],
		["Skidpad", "%.2f g" % mine["skidpad_g"], "%.2f g" % theirs["skidpad_g"]],
	]
	for i in rows.size():
		for j in 3:
			var style := "InkMutedLabel" if j == 0 else ("FlyerTitleLabel" if i == 0 else "InkLabel")
			var l := UI.label(grid, rows[i][j], style)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			if j > 0:
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Four tape tabs; the chosen one is gaffer tape. Faba says his piece.
func select_push(p: String) -> void:
	push = p
	var row: HBoxContainer = %PushRow
	for c in row.get_children():
		c.queue_free()
	for option in push_order:
		var b := UI.button(row, str(option).replace("_", " "), func():
			select_push(option)
			push_changed.emit(option), "GaffSmallButton" if option == push else "SmallTapeButton")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%PushLine.text = Voice.FABA_PUSH[push]
	%PushRisk.text = push_risk[push]


func set_wager(v: float) -> void:
	var w := int(v)
	%Cash.amount = w
	%WagerAmount.text = UI.money(w)
	%WagerOdds.text = "win +%s  /  lose -%s" % [UI.money(w), UI.money(w)]
	%BigBet.visible = w > min_buy_in and w >= cash * Voice.BIG_BET_SHARE
	wager_changed.emit(w)
