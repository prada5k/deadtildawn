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
const IntroScene := preload("res://intro.tscn")

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
var footer: VBoxContainer  # pinned area at the bottom of scrolling screens
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
		show_message("CAN'T START THE SIM", problem)
		return
	if not state.get("intro_seen", false):
		show_intro()
	else:
		show_garage()


func new_state() -> Dictionary:
	return {"version": SAVE_VERSION, "cash": START_CASH, "rep": 0, "history": [], "night": {},
		"intro_seen": false}


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

func new_screen(scroll := true) -> VBoxContainer:
	## Portrait page: header (cash / rep), then a column for the content.
	RenderingServer.set_default_clear_color(UI.BG)
	if viewer:
		viewer.queue_free()
		viewer = null
	if screen:
		screen.queue_free()
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		root.add_theme_constant_override("margin_" + side, 32)
	root.add_theme_constant_override("margin_top", 48)
	root.add_theme_constant_override("margin_bottom", 40)
	add_child(root)
	screen = root
	var page := UI.vbox(root, 18)

	var header := UI.hbox(page, 16)
	var brand := UI.label(header, "DEADTILDAWN", "HeadingLabel")
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var money := UI.label(header, UI.money(state["cash"]), "HeadingLabel",
		UI.GOOD if state["cash"] >= MIN_BUY_IN else UI.BAD)
	UI.label(header, "REP %d" % int(state["rep"]), "HeadingLabel", Color.WHITE)

	if not scroll:
		return page
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(sc)
	var col := UI.vbox(sc, 18)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Pinned footer below the scroll area: a screen's main action stays on
	# screen no matter how much content scrolls above it.
	footer = UI.vbox(page, 10)
	return col


func show_message(title: String, text: String, button_text := "", action := Callable()) -> void:
	var col := new_screen(false)
	UI.spacer(col)
	UI.label(col, title, "TitleLabel")
	UI.label(col, text, "MutedLabel")
	UI.spacer(col)
	if button_text != "":
		UI.button(col, button_text, action, "AccentButton")


func show_intro() -> void:
	if viewer:
		viewer.queue_free()
		viewer = null
	if screen:
		screen.queue_free()
	var intro: Control = IntroScene.instantiate()
	intro.finished.connect(func():
		state["intro_seen"] = true
		save_game()
		show_garage())
	add_child(intro)
	screen = intro


func show_garage() -> void:
	if state["cash"] < MIN_BUY_IN:
		show_broke()
		return
	if car_stats.is_empty():
		show_message("THE WAREHOUSE", "Putting the car on the dyno...")
		bridge.request("car_stats", ["car_stats"])
		return
	var col := new_screen()
	UI.label(col, "THE WAREHOUSE", "TitleLabel")
	UI.label(col, "HQ. Faba's savings, your tools.", "MutedLabel")

	var car := UI.vbox(UI.panel(col), 6)
	UI.label(car, car_stats["name"], "HeadingLabel")
	UI.label(car, "Bone stock. Every number from the sim.", "MutedLabel")
	UI.stat_row(car, "Power", "%d hp @ %d" % [car_stats["hp"], car_stats["hp_rpm"]])
	UI.stat_row(car, "Torque", "%d lb-ft @ %d" % [car_stats["torque_lbft"], car_stats["torque_rpm"]])
	UI.stat_row(car, "Weight", "%d kg" % car_stats["weight_kg"])
	UI.stat_row(car, "Power / weight", "%d hp/t" % car_stats["hp_per_tonne"])
	UI.stat_row(car, "0-60 mph", "%.2f s" % car_stats["zero_60_s"])
	UI.stat_row(car, "Quarter mile", "%.2f s" % car_stats["quarter_s"])
	UI.stat_row(car, "Top speed", "%d mph" % car_stats["top_speed_mph"])
	UI.stat_row(car, "Skidpad", "%.2f g, %s" % [car_stats["skidpad_g"], car_stats["balance"]])
	UI.stat_row(car, "60-0 mph", "%d ft" % car_stats["sixty_zero_ft"])

	var crew := UI.vbox(UI.panel(col), 6)
	UI.label(crew, "THE CREW", "HeadingLabel")
	var record := wins_losses()
	UI.stat_row(crew, "Driver", "Faba")
	UI.stat_row(crew, "Record", "%d W - %d L" % [record.x, record.y])
	UI.stat_row(crew, "Minimum buy-in", UI.money(MIN_BUY_IN))

	UI.button(col, "TONIGHT'S RACE", show_briefing, "AccentButton")
	UI.button(col, "Replay the story", show_intro)


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
		show_message("WORD ON THE STREET", "Finding out who's running tonight.\n\nThe first time on a road, Faba runs it in his head at every push level. Give it 15-30 seconds.")
		bridge.request("rival", ["rival", "--rival", RIVAL_FILE, "--seed", str(randi() % 1000000)])
		return
	if track_info.is_empty():
		show_message("SCOUTING", "Driving the road in daylight.")
		bridge.request("track", ["track", "--track", state["night"]["track"]])
		return
	if odds.is_empty():
		show_message("DRIVER MEETING", "Running the numbers on every push level.")
		bridge.request("odds", ["odds", "--track", state["night"]["track"], "--posted", str(state["night"]["posted_time"])])
		return
	show_meeting()


func show_meeting() -> void:
	var night: Dictionary = state["night"]
	var col := new_screen()
	UI.label(col, "TONIGHT", "TitleLabel")

	var rival := UI.vbox(UI.panel(col), 4)
	UI.label(rival, "%s  /  %s" % [str(night["name"]).to_upper(), night["car"]], "HeadingLabel", UI.BAD)
	UI.label(rival, "%.2f s" % night["posted_time"], "BigNumberLabel")
	UI.label(rival, "posted time  /  %s  /  %d m, %d corners" % [
		night["club"], int(track_info["length"]), track_info["corners"].size()], "MutedLabel")

	var map: Control = TrackMap.new()
	map.track = track_info
	map.custom_minimum_size = Vector2(0, 290)
	UI.panel(col).add_child(map)

	UI.label(footer, "HOW HARD DOES FABA PUSH?", "HeadingLabel")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	footer.add_child(grid)
	for push in PUSH_ORDER:
		var o: Dictionary = odds["push_levels"][push]
		var text := "%s\nwin %d%%\nmistake %d%%" % [push.replace("_", " ").to_upper(),
			int(round(o["win"] * 100)), int(round(o["mistake_rate"] * 100))]
		var b := UI.button(grid, text, _on_push.bind(push),
			"SelectedButton" if push == choice["push"] else "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cash := int(state["cash"])
	choice["wager"] = clampi(int(choice["wager"]), MIN_BUY_IN, cash)
	var wager_label := UI.label(footer, "", "HeadingLabel", Color.WHITE)
	var slider := HSlider.new()
	slider.min_value = MIN_BUY_IN
	slider.max_value = cash
	slider.step = WAGER_STEP
	slider.value = choice["wager"]
	slider.custom_minimum_size.y = 40
	slider.editable = cash > MIN_BUY_IN
	var set_wager := func(v):
		choice["wager"] = int(v)
		wager_label.text = "WAGER %s   (win +%s / lose -%s)" % [UI.money(v), UI.money(v), UI.money(v)]
	slider.value_changed.connect(set_wager)
	footer.add_child(slider)
	set_wager.call(choice["wager"])

	var actions := UI.hbox(footer, 10)
	UI.button(actions, "Back", show_garage)
	var go := UI.button(actions, "SEND IT", send_it, "DangerButton")
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _on_push(push: String) -> void:
	choice["push"] = push
	show_meeting()


func send_it() -> void:
	show_message("LIGHTS OUT", "Faba lines up the DX.\n%s on the line, %s push." % [
		UI.money(choice["wager"]), str(choice["push"]).replace("_", " ")])
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
	UI.spacer(col, false).custom_minimum_size.y = 40
	var big := UI.label(col, "YOU WON" if won else "YOU LOST", "TitleLabel", UI.GOOD if won else UI.BAD)
	big.add_theme_font_size_override("font_size", 96)
	var margin := absf(float(result["time"]) - float(result["posted"]))
	UI.label(col, "%s by %.3f s" % ["Ahead" if won else "Behind", margin], "BigNumberLabel")
	var info := UI.vbox(UI.panel(col), 6)
	UI.stat_row(info, "Faba", "%.3f s" % result["time"])
	UI.stat_row(info, str(result["rival"]), "%.3f s" % result["posted"])
	UI.stat_row(info, "Push", str(result["push"]).replace("_", " "))
	UI.stat_row(info, "Odds going in", "%d%%" % int(round(float(result["odds"]) * 100)))
	UI.stat_row(info, "Mistakes", "none" if result["mistakes"].is_empty() else ", ".join(result["mistakes"]))
	UI.stat_row(info, "Cash", "%s%s  ->  %s" % ["+" if won else "", UI.money(result["cash_change"]), UI.money(state["cash"])])
	UI.stat_row(info, "Rep", "+%d  ->  %d" % [result["rep_change"], state["rep"]])
	UI.button(col, "BACK TO THE WAREHOUSE", show_garage, "AccentButton")


func show_broke() -> void:
	var record := wins_losses()
	show_message("BROKE",
		"%s left. You can't cover the %s buy-in.\n\nRecord %d W - %d L, rep %d.\n\nThe warehouse goes quiet. (Pink slips come later.)" % [
			UI.money(state["cash"]), UI.money(MIN_BUY_IN), record.x, record.y, int(state["rep"])],
		"START OVER", reset_game)


# ------------------------------------------------------------------ bridge replies

func _on_reply(tag: String, data: Dictionary) -> void:
	if not data.get("ok", false):
		show_message("THE SIM HIT A PROBLEM", str(data.get("error", "unknown error")), "BACK TO THE WAREHOUSE", show_garage)
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
	show_intro()
	await snap(folder, "0a_intro")
	for i in 3:
		screen.next_slide()
	await get_tree().create_timer(0.8).timeout
	await snap(folder, "0b_intro_crash")
	for i in 6:
		screen.next_slide()
	await get_tree().create_timer(0.8).timeout
	await snap(folder, "0c_intro_title")
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
