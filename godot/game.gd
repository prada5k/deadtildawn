extends Node
## deadtildawn vertical slice: garage -> briefing -> driver meeting -> race -> results.
##
## The Python sim does all physics through the bridge (bridge.gd). This script
## owns the game state (cash, rep, history) and the screens.
##
## Rules that protect the game from save-scumming:
##   - tonight's rival posted time is drawn once and saved
##   - the race result is applied and saved BEFORE the replay plays

const UI := preload("res://ui.gd")
const Bridge := preload("res://bridge.gd")
const TrackMap := preload("res://track_map.gd")
const Viewer := preload("res://main.gd")

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const START_CASH := 250
const MIN_BUY_IN := 100
const WAGER_STEP := 10
const REP_WIN := 10
const RIVAL_FILE := "data/rivals/zed_280z.json"
const PUSH_ORDER := ["safe", "normal", "hard", "flat_out"]

var state := {}            # saved: cash, rep, history, night
var car_stats := {}        # bridge replies, cached for the session
var track_info := {}
var odds := {}
var bridge: Node
var screen: Control        # current UI screen
var viewer: Node           # replay viewer while racing
var choice := {"push": "normal", "wager": MIN_BUY_IN}


# ------------------------------------------------------------------ setup

func _ready() -> void:
	RenderingServer.set_default_clear_color(UI.BG)
	bridge = Bridge.new()
	add_child(bridge)
	load_game()
	var args := OS.get_cmdline_user_args()
	if "--gametest" in args:
		game_test()           # the test awaits replies itself: don't also run the game's handler
		return
	for a in args:
		if a.begins_with("--gameshots="):
			game_shots(a.trim_prefix("--gameshots="))
			return
	bridge.replied.connect(_on_reply)
	var problem: String = bridge.ready_to_use()
	if problem != "":
		show_message("Can't start the sim", problem)
		return
	show_garage()


func new_state() -> Dictionary:
	return {"version": SAVE_VERSION, "cash": START_CASH, "rep": 0, "history": [], "night": {}}


func load_game() -> void:
	state = new_state()
	if FileAccess.file_exists(SAVE_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if typeof(data) == TYPE_DICTIONARY and int(data.get("version", 0)) == SAVE_VERSION:
			state = data


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "  "))


func reset_game() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	state = new_state()
	save_game()
	show_garage()


# ------------------------------------------------------------------ screens

func new_screen() -> VBoxContainer:
	RenderingServer.set_default_clear_color(UI.BG)
	if viewer:
		viewer.queue_free()
		viewer = null
	if screen:
		screen.queue_free()
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 28)
	add_child(root)
	screen = root
	var col := UI.vbox(root, 10)
	var header := UI.hbox(col, 24)
	UI.label(header, "DEADTILDAWN", 26, UI.ACCENT)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	UI.label(header, "Cash %s" % UI.money(state["cash"]), 22, UI.GOOD if state["cash"] >= MIN_BUY_IN else UI.BAD)
	UI.label(header, "Rep %d" % int(state["rep"]), 22)
	return col


func show_message(title: String, text: String, button_text := "", action := Callable()) -> void:
	var col := new_screen()
	UI.label(col, title, 30, UI.ACCENT)
	var body := UI.label(col, text, 18, UI.MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if button_text != "":
		UI.button(col, button_text, action)


func show_garage() -> void:
	if state["cash"] < MIN_BUY_IN:
		show_broke()
		return
	if car_stats.is_empty():
		show_message("Garage", "Putting the car on the dyno...")
		bridge.request("car_stats", ["car_stats"])
		return
	var col := new_screen()
	UI.label(col, "THE GARAGE", 30)
	var row := UI.hbox(col, 20)

	var sheet := UI.vbox(UI.panel(row), 6)
	UI.label(sheet, car_stats["name"], 22, UI.ACCENT)
	UI.label(sheet, "Stock. Every number from the sim.", 14, UI.MUTED)
	UI.stat_row(sheet, "Power", "%d hp @ %d rpm" % [car_stats["hp"], car_stats["hp_rpm"]])
	UI.stat_row(sheet, "Torque", "%d lb-ft @ %d rpm" % [car_stats["torque_lbft"], car_stats["torque_rpm"]])
	UI.stat_row(sheet, "Weight", "%d kg (with driver)" % car_stats["weight_kg"])
	UI.stat_row(sheet, "Power / weight", "%d hp per tonne" % car_stats["hp_per_tonne"])
	UI.stat_row(sheet, "Drivetrain", "%s, redline %d" % [car_stats["drivetrain"], car_stats["redline"]])
	UI.stat_row(sheet, "0-60 mph", "%.2f s" % car_stats["zero_60_s"])
	UI.stat_row(sheet, "Quarter mile", "%.2f s" % car_stats["quarter_s"])
	UI.stat_row(sheet, "Top speed", "%d mph" % car_stats["top_speed_mph"])
	UI.stat_row(sheet, "Skidpad", "%.3f g (%s)" % [car_stats["skidpad_g"], car_stats["balance"]])
	UI.stat_row(sheet, "60-0 mph", "%d ft" % car_stats["sixty_zero_ft"])

	var side := UI.vbox(UI.panel(row), 10)
	side.custom_minimum_size.x = 420
	UI.label(side, "THE CREW", 20, UI.ACCENT)
	var record := wins_losses()
	UI.label(side, "Record: %d W - %d L" % [record.x, record.y], 18)
	UI.label(side, "Minimum buy-in: %s" % UI.money(MIN_BUY_IN), 16, UI.MUTED)
	var story := UI.label(side, "You can't drive anymore. Your friend can.\nYou build it, you call the push, you bet the rent.", 15, UI.MUTED)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.button(side, "TONIGHT'S RACE  >", show_briefing, 22)


func wins_losses() -> Vector2i:
	var w := 0
	var l := 0
	for r in state["history"]:
		if r["won"]:
			w += 1
		else:
			l += 1
	return Vector2i(w, l)


func show_briefing() -> void:
	# Draw tonight's rival once and save it (no rerolling by restarting)
	if state["night"].is_empty():
		show_message("Word on the street...", "Finding out who's running tonight.\n\nFirst time on a track the crew studies every push level (~15-30 s).")
		bridge.request("rival", ["rival", "--rival", RIVAL_FILE, "--seed", str(randi() % 1000000)])
		return
	if track_info.is_empty():
		show_message("Scouting the road...", "Driving the course in daylight.")
		bridge.request("track", ["track", "--track", state["night"]["track"]])
		return
	if odds.is_empty():
		show_message("Driver meeting...", "Running the numbers on every push level.")
		bridge.request("odds", ["odds", "--track", state["night"]["track"], "--posted", str(state["night"]["posted_time"])])
		return
	show_meeting()


func show_meeting() -> void:
	var night: Dictionary = state["night"]
	var col := new_screen()
	UI.label(col, "TONIGHT: %s" % str(track_info["name"]).get_basename().replace("_", " ").to_upper(), 30)
	var row := UI.hbox(col, 20)

	var map_panel := UI.panel(row)
	var map: Control = TrackMap.new()
	map.track = track_info
	map.custom_minimum_size = Vector2(560, 440)
	map_panel.add_child(map)

	var side := UI.vbox(row, 12)
	var rival := UI.vbox(UI.panel(side), 4)
	UI.label(rival, "RIVAL", 14, UI.MUTED)
	UI.label(rival, "%s  -  %s" % [night["name"], night["car"]], 22, UI.BAD)
	UI.label(rival, "Posted time: %.2f s" % night["posted_time"], 20)
	UI.label(rival, "%s   |   %d m, %d corners" % [night["club"], int(track_info["length"]), track_info["corners"].size()], 14, UI.MUTED)

	var meet := UI.vbox(UI.panel(side), 8)
	UI.label(meet, "DRIVER MEETING: how hard do we push?", 16, UI.ACCENT)
	var push_box := UI.vbox(meet, 6)
	for push in PUSH_ORDER:
		var o: Dictionary = odds["push_levels"][push]
		var text := "%-9s  win %3d%%   avg %.2f s   mistake %d%%" % [
			push.replace("_", " ").to_upper(), int(round(o["win"] * 100)), o["mean"], int(round(o["mistake_rate"] * 100))]
		var b := UI.button(push_box, text, _on_push.bind(push), 16,
			UI.ACCENT if push == choice["push"] else UI.MUTED)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var cash := int(state["cash"])
	choice["wager"] = clampi(int(choice["wager"]), MIN_BUY_IN, cash)
	var wager_label := UI.label(meet, "", 18)
	var slider := HSlider.new()
	slider.min_value = MIN_BUY_IN
	slider.max_value = cash
	slider.step = WAGER_STEP
	slider.value = choice["wager"]
	slider.custom_minimum_size.x = 380
	slider.editable = cash > MIN_BUY_IN
	slider.value_changed.connect(func(v):
		choice["wager"] = int(v)
		wager_label.text = "Wager: %s   (win +%s / lose -%s)" % [UI.money(v), UI.money(v), UI.money(v)])
	meet.add_child(slider)
	wager_label.text = "Wager: %s   (win +%s / lose -%s)" % [UI.money(choice["wager"]), UI.money(choice["wager"]), UI.money(choice["wager"])]

	var actions := UI.hbox(side, 10)
	UI.button(actions, "< Garage", show_garage, 16, UI.MUTED)
	var go := UI.button(actions, "SEND IT", send_it, 28, UI.BAD)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _on_push(push: String) -> void:
	choice["push"] = push
	show_meeting()


func send_it() -> void:
	show_message("Lights out", "Your friend lines up. %s at %s push." % [UI.money(choice["wager"]), str(choice["push"]).replace("_", " ")])
	var out := ProjectSettings.globalize_path("user://replays/race.json")
	bridge.request("race", ["race", "--track", state["night"]["track"], "--push", choice["push"],
		"--seed", str(randi() % 1000000), "--out", out])


func apply_result(r: Dictionary) -> Dictionary:
	## Settle the bet and save immediately (before the replay plays).
	var night: Dictionary = state["night"]
	var won: bool = float(r["lap_time"]) < float(night["posted_time"])
	var wager := int(choice["wager"])
	var result := {
		"rival": night["name"], "rival_car": night["car"], "posted": night["posted_time"],
		"time": r["lap_time"], "won": won, "push": r["push"], "seed": r["seed"],
		"wager": wager, "cash_change": wager if won else -wager,
		"rep_change": REP_WIN if won else 0, "mistakes": r["mistakes"],
		"odds": odds["push_levels"][r["push"]]["win"]}
	state["cash"] = int(state["cash"]) + int(result["cash_change"])
	state["rep"] = int(state["rep"]) + int(result["rep_change"])
	state["history"].append(result)
	state["night"] = {}               # tomorrow is a new night
	save_game()
	return result


func show_race(replay_path: String, result: Dictionary) -> void:
	if screen:
		screen.queue_free()
		screen = null
	viewer = Viewer.new()
	viewer.replay_path = replay_path
	viewer.rival_name = result["rival"]
	viewer.rival_time = float(result["posted"])
	viewer.embedded = true
	viewer.finished_viewing.connect(show_results.bind(result))
	add_child(viewer)


func show_results(result: Dictionary) -> void:
	var col := new_screen()
	var won: bool = result["won"]
	UI.label(col, "YOU WON" if won else "YOU LOST", 44, UI.GOOD if won else UI.BAD)
	var margin := absf(float(result["time"]) - float(result["posted"]))
	UI.label(col, "%.3f s  vs  %s's %.3f s   (%s by %.3f s)" % [
		result["time"], result["rival"], result["posted"], "ahead" if won else "behind", margin], 22)
	var info := UI.vbox(UI.panel(col), 6)
	UI.stat_row(info, "Push level", str(result["push"]).replace("_", " "))
	UI.stat_row(info, "Odds before the race", "%d%%" % int(round(float(result["odds"]) * 100)))
	UI.stat_row(info, "Mistakes", "none" if result["mistakes"].is_empty() else ", ".join(result["mistakes"]))
	UI.stat_row(info, "Cash", "%s  ->  %s" % [("+" if won else "") + UI.money(result["cash_change"]), UI.money(state["cash"])])
	UI.stat_row(info, "Rep", "+%d  ->  %d" % [result["rep_change"], state["rep"]])
	UI.button(col, "Back to the garage", show_garage, 20)


func show_broke() -> void:
	var record := wins_losses()
	show_message("BROKE",
		"%s left. You can't cover the %s buy-in.\nRecord: %d W - %d L, rep %d.\n\nThe crew is done. (Pink slips come later.)" % [
			UI.money(state["cash"]), UI.money(MIN_BUY_IN), record.x, record.y, int(state["rep"])],
		"Start over", reset_game)


# ------------------------------------------------------------------ bridge replies

func _on_reply(tag: String, data: Dictionary) -> void:
	if not data.get("ok", false):
		show_message("The sim hit a problem", str(data.get("error", "unknown error")), "Back to garage", show_garage)
		return
	match tag:
		"car_stats":
			car_stats = data
			show_garage()
		"rival":
			state["night"] = data
			save_game()
			track_info = {}
			odds = {}
			show_briefing()
		"track":
			track_info = data
			show_briefing()
		"odds":
			odds = data
			show_briefing()
		"race":
			var result := apply_result(data)
			show_race(data["replay"], result)


# ------------------------------------------------------------------ self-test

func game_test() -> void:
	## Headless end-to-end check: one full night, printed. Run with
	##   godot --headless --path godot -- --gametest
	state = new_state()
	print("GAMETEST bridge: ", bridge.ready_to_use() if bridge.ready_to_use() != "" else "ok")
	bridge.request("car_stats", ["car_stats"])
	var r: Array = await bridge.replied
	print("GAMETEST car: %s, %d hp, 0-60 %.2f s" % [r[1]["name"], r[1]["hp"], r[1]["zero_60_s"]])
	bridge.request("rival", ["rival", "--rival", RIVAL_FILE, "--seed", "42"])
	r = await bridge.replied
	state["night"] = r[1]
	print("GAMETEST rival: %s (%s), posted %.3f s" % [r[1]["name"], r[1]["car"], r[1]["posted_time"]])
	bridge.request("odds", ["odds", "--track", r[1]["track"], "--posted", str(r[1]["posted_time"])])
	r = await bridge.replied
	odds = r[1]
	for push in PUSH_ORDER:
		print("GAMETEST odds %-9s win %.2f" % [push, odds["push_levels"][push]["win"]])
	choice = {"push": "hard", "wager": 100}
	var out := ProjectSettings.globalize_path("user://replays/race.json")
	bridge.request("race", ["race", "--track", state["night"]["track"], "--push", "hard", "--seed", "9", "--out", out])
	r = await bridge.replied
	var result := apply_result(r[1])
	print("GAMETEST race: %.3f s vs %.3f s -> %s, cash %d, rep %d" % [
		result["time"], result["posted"], "WIN" if result["won"] else "LOSS", state["cash"], state["rep"]])
	print("GAMETEST replay exists: ", FileAccess.file_exists(out))
	print("GAMETEST OK")
	get_tree().quit()



## Stills of every screen for review (needs a display, not --headless):
##   godot --path godot -- --gameshots=<folder>
func game_shots(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	state = new_state()
	bridge.request("car_stats", ["car_stats"])
	car_stats = (await bridge.replied)[1]
	show_garage()
	await snap(folder, "1_garage")
	bridge.request("rival", ["rival", "--rival", RIVAL_FILE, "--seed", "3"])
	state["night"] = (await bridge.replied)[1]
	bridge.request("track", ["track", "--track", state["night"]["track"]])
	track_info = (await bridge.replied)[1]
	bridge.request("odds", ["odds", "--track", state["night"]["track"], "--posted", str(state["night"]["posted_time"])])
	odds = (await bridge.replied)[1]
	choice = {"push": "hard", "wager": 150}
	show_meeting()
	await snap(folder, "2_meeting")
	var out := ProjectSettings.globalize_path("user://replays/shots.json")
	bridge.request("race", ["race", "--track", state["night"]["track"], "--push", "hard", "--seed", "21", "--out", out])
	var r: Dictionary = (await bridge.replied)[1]
	var result := apply_result(r)
	show_race(out, result)
	await snap(folder, "3_race_start")
	viewer.t = viewer.lap_time * 0.55
	viewer.playing = false
	await snap(folder, "4_race_mid")
	viewer.t = viewer.lap_time
	await snap(folder, "5_race_finish")
	show_results(result)
	await snap(folder, "6_results")
	state["cash"] = 40
	show_garage()
	await snap(folder, "7_broke")
	get_tree().quit()


func snap(folder: String, name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [folder, name])
	print("saved ", name)
