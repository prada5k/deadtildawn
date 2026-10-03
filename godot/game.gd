extends Node
## deadtildawn: game flow and state.
##
## Hub screens are editor scenes in screens/ (warehouse, car, calendar): their
## LAYOUT is edited in Godot, their scripts only fill in data and emit
## go(target). The race-night screens (meeting, results) are still built in
## code here. Every look comes from theme.tres.
##
## The Python sim does all physics through the bridge (bridge.gd).
##
## Rules that protect the game from save-scumming:
##   - a race night's posted time is drawn once and saved
##   - the race result is applied and saved BEFORE the replay plays

const UI := preload("res://ui.gd")
const Bridge := preload("res://bridge.gd")
const TrackMap := preload("res://track_map.gd")
const PracticeChart := preload("res://widgets/practice_chart.gd")
const Viewer := preload("res://main.gd")
const IntroScene := preload("res://intro.tscn")
const WarehouseScene := preload("res://screens/warehouse.tscn")
const CarScene := preload("res://screens/car.tscn")
const CalendarScene := preload("res://screens/calendar.tscn")
const ShopScene := preload("res://screens/shop.tscn")

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 3
const START_CASH := 250
const MIN_BUY_IN := 100
const WAGER_STEP := 10
const REP_WIN := 10
const SKIP_REP_COST := 5 * REP_WIN   # chicken-out fee: five wins' worth of rep
const LOOT_CHANCE := 0.05            # chance a win also drops a random part
const LOOT_WEIGHTS := {"common": 50, "rare": 30, "epic": 15, "legendary": 5}
const RIVAL_FILE := "data/rivals/zed_280z.json"
const PUSH_ORDER := ["safe", "normal", "hard", "flat_out"]

# Calendar: a week is 7 days; race nights fall on these days (0 = Monday)
const DAY_NAMES := ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
const RACE_DAYS := [4, 5]        # Friday and Saturday nights

var state := {}            # saved: cash, rep, week, day, history, night, intro_seen
var car_stats := {}        # bridge replies, cached for the session
var track_info := {}
var practice := {}
var catalog := {}          # bridge "parts" reply (slots + parts with exact effects)
var shop_message := ""
var bridge: Node
var screen: Control        # current UI screen
var footer: VBoxContainer  # pinned area at the bottom of scrolling screens
var viewer: Node           # replay viewer while racing
var choice := {"push": "normal", "wager": MIN_BUY_IN}
var after_car_stats := "warehouse"   # where to go once car stats arrive
var after_catalog := "shop"          # where to go once the parts catalog arrives


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
		show_warehouse()


func new_state() -> Dictionary:
	return {"version": SAVE_VERSION, "cash": START_CASH, "rep": 0, "week": 1, "day": 0,
		"history": [], "night": {}, "intro_seen": false,
		"owned_parts": [], "installed": {}}


func load_game() -> void:
	state = new_state()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	state = migrate(data)


## Upgrade an older save instead of throwing it away. Each step takes a save
## from version N to N + 1, so any old save can climb to the current version.
func migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("version", 1))
	if v < 2:                        # v1 -> v2: the calendar arrives
		data["week"] = 1
		data["day"] = 0
		data["night"] = {}           # an old night has no calendar event; redraw it
		v = 2
	if v < 3:                        # v2 -> v3: parts arrive
		data["owned_parts"] = []
		data["installed"] = {}
		v = 3
	data["version"] = v
	return data


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "  "))


func reset_game() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	state = new_state()
	save_game()
	show_warehouse()


# ------------------------------------------------------------------ calendar

## Events in a given week: [{"day": int, "type": "race", "title": String}]
func events_for_week(_week: int) -> Array:
	var out := []
	for d in RACE_DAYS:
		out.append({"day": d, "type": "race", "title": "Race night vs Zed (280Z)"})
	return out


func when(week: int, day: int) -> String:
	return "%s, WEEK %d" % [DAY_NAMES[day], week]


## The next event at or after today: {"week", "day", "type", "title"}
func next_event() -> Dictionary:
	var week := int(state["week"])
	for w in range(week, week + 52):
		for e in events_for_week(w):
			if w > week or int(e["day"]) >= int(state["day"]):
				var ev: Dictionary = e.duplicate()
				ev["week"] = w
				return ev
	return {}


func upcoming_events(n: int) -> Array:
	var out := []
	var week := int(state["week"])
	for w in range(week, week + 52):
		for e in events_for_week(w):
			if w > week or int(e["day"]) >= int(state["day"]):
				var ev: Dictionary = e.duplicate()
				ev["week"] = w
				out.append(ev)
				if out.size() >= n:
					return out
	return out


## Move time to the day after an event.
func advance_past(event: Dictionary) -> void:
	var day := int(event["day"]) + 1
	var week := int(event["week"])
	if day > 6:
		day = 0
		week += 1
	state["week"] = week
	state["day"] = day


func event_key(event: Dictionary) -> String:
	return "%d-%d" % [int(event["week"]), int(event["day"])]


# ------------------------------------------------------------------ screens

func clear_screen() -> void:
	RenderingServer.set_default_clear_color(UI.BG)
	if viewer:
		viewer.queue_free()
		viewer = null
	if screen:
		screen.queue_free()
		screen = null
	footer = null


## Show an editor-built hub scene and route its go(target) signal.
func open_scene(packed: PackedScene) -> Control:
	clear_screen()
	var s: Control = packed.instantiate()
	add_child(s)
	s.go.connect(_go)
	screen = s
	return s


func _go(target: String) -> void:
	match target:
		"warehouse":
			show_warehouse()
		"car":
			show_car()
		"calendar":
			show_calendar()
		"story":
			show_intro()
		"shop":
			show_shop()
		"race":
			show_briefing()


func common_info() -> Dictionary:
	return {"cash": int(state["cash"]), "rep": int(state["rep"]), "min_buy_in": MIN_BUY_IN}


func new_screen(scroll := true) -> VBoxContainer:
	## Code-built portrait page: header (cash / rep), then a column for content.
	clear_screen()
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
	UI.label(header, UI.money(state["cash"]), "HeadingLabel",
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
	clear_screen()
	var intro: Control = IntroScene.instantiate()
	intro.finished.connect(func():
		state["intro_seen"] = true
		save_game()
		show_warehouse())
	add_child(intro)
	screen = intro


func show_warehouse() -> void:
	if state["cash"] < MIN_BUY_IN:
		show_broke()
		return
	var ev := next_event()
	var record := wins_losses()
	var info := common_info()
	info["event_title"] = "%s: RACE NIGHT" % when(ev["week"], ev["day"])
	info["event_detail"] = "%s. Minimum buy-in %s. Today is %s." % [
		ev["title"], UI.money(MIN_BUY_IN), when(state["week"], state["day"]).to_lower()]
	info["wins"] = record.x
	info["losses"] = record.y
	info["min_buy_in_text"] = UI.money(MIN_BUY_IN)
	open_scene(WarehouseScene).setup(info)


func show_car() -> void:
	if catalog.is_empty():
		show_message("THE CAR", "Checking the parts shelf...")
		after_catalog = "car"
		bridge.request("parts", ["parts"])
		return
	if car_stats.is_empty():
		show_message("THE CAR", "Strapping the DX to the dyno...")
		after_car_stats = "car"
		bridge.request("car_stats", ["car_stats"] + parts_args())
		return
	var options := {}
	for p in catalog["parts"]:
		if p["id"] in state["owned_parts"]:
			if not options.has(p["slot"]):
				options[p["slot"]] = []
			options[p["slot"]].append([p["id"], p["name"]])
	var car: Control = open_scene(CarScene)
	car.part_changed.connect(install_part)
	car.setup(common_info(), car_stats,
		{"slots": catalog["slots"], "options": options, "installed": state["installed"]})


func show_shop() -> void:
	if catalog.is_empty():
		show_message("PARTS SHOP", "Checking the parts shelf...")
		after_catalog = "shop"
		bridge.request("parts", ["parts"])
		return
	var shop: Control = open_scene(ShopScene)
	shop.buy.connect(buy_part)
	shop.setup(common_info(), catalog, state["owned_parts"], state["installed"], shop_message)
	shop_message = ""


## Installed part ids, for every sim call: the car being simulated is the car
## in the warehouse.
func parts_args() -> Array:
	var ids: Array = state["installed"].values()
	ids.sort()
	return [] if ids.is_empty() else ["--parts", ",".join(ids)]


func part_by_id(id: String) -> Dictionary:
	for p in catalog["parts"]:
		if p["id"] == id:
			return p
	return {}


## Buy and install. The shop won't spend below the race buy-in (otherwise one
## purchase could leave you unable to race at all).
func buy_part(id: String) -> void:
	var p := part_by_id(id)
	if p.is_empty() or id in state["owned_parts"]:
		return
	if int(state["cash"]) - int(p["price"]) < MIN_BUY_IN:
		shop_message = "Can't: that would leave less than the %s buy-in." % UI.money(MIN_BUY_IN)
		show_shop()
		return
	state["cash"] = int(state["cash"]) - int(p["price"])
	state["owned_parts"].append(id)
	shop_message = "Bought and installed: %s." % p["name"]
	install_part(p["slot"], id, false)
	show_shop()


## Swap what's in a slot ("" = back to stock). The car changed, so its stats
## and practice runs are stale.
func install_part(slot: String, id: String, refresh := true) -> void:
	if id == "":
		state["installed"].erase(slot)
	else:
		state["installed"][slot] = id
	car_stats = {}
	practice = {}
	save_game()
	if refresh:
		show_car()


## A win has a small chance to drop a random part you don't own (by rarity).
func roll_loot() -> String:
	if catalog.is_empty() or randf() >= LOOT_CHANCE:
		return ""
	var pool := []
	var total := 0
	for p in catalog["parts"]:
		if not p["id"] in state["owned_parts"]:
			var w: int = LOOT_WEIGHTS[p["rarity"]]
			pool.append([p["id"], w])
			total += w
	if total == 0:
		return ""
	var pick := randi() % total
	for entry in pool:
		pick -= entry[1]
		if pick < 0:
			state["owned_parts"].append(entry[0])
			return entry[0]
	return ""


func show_calendar() -> void:
	var info := common_info()
	var week := int(state["week"])
	info["week"] = week
	info["day"] = int(state["day"])
	var week_events := {}
	for e in events_for_week(week):
		week_events[int(e["day"])] = "RACE"
	info["week_events"] = week_events
	var upcoming := []
	for e in upcoming_events(5):
		upcoming.append([when(e["week"], e["day"]), e["title"]])
	info["upcoming"] = upcoming
	var past := []
	var hist: Array = state["history"]
	for i in range(hist.size() - 1, maxi(hist.size() - 6, -1), -1):
		var r: Dictionary = hist[i]
		if r.get("skipped", false):
			past.append([r.get("when", "-"), "vs %s" % r["rival"], "SKIPPED  %d rep" % int(r["rep_change"])])
		else:
			past.append([r.get("when", "-"), "vs %s" % r["rival"],
				"%s  %+d" % ["W" if r["won"] else "L", int(r["cash_change"])]])
	info["past"] = past
	open_scene(CalendarScene).setup(info)


func wins_losses() -> Vector2i:
	var w := 0
	var l := 0
	for r in state["history"]:
		if r.get("skipped", false):
			continue
		if r["won"]:
			w += 1
		else:
			l += 1
	return Vector2i(w, l)


func show_briefing() -> void:
	var ev := next_event()
	# A saved night belongs to one calendar event; a stale one gets redrawn
	if not state["night"].is_empty() and state["night"].get("event") != event_key(ev):
		state["night"] = {}
	# Draw the night's rival time once and save it (no rerolling by restarting)
	if state["night"].is_empty():
		show_message("WORD ON THE STREET", "Finding out who's running tonight.\n\nThe first time on a road, Faba runs practice laps at every push level. Give it 15-30 seconds.")
		bridge.request("rival", ["rival", "--rival", RIVAL_FILE, "--seed", str(randi() % 1000000)])
		return
	if track_info.is_empty():
		show_message("SCOUTING", "Driving the road in daylight.")
		bridge.request("track", ["track", "--track", state["night"]["track"]])
		return
	if practice.is_empty():
		show_message("PRACTICE", "Faba's running the road at every push level.")
		bridge.request("practice", ["practice", "--track", state["night"]["track"]] + parts_args())
		return
	if catalog.is_empty():
		after_catalog = "race"
		bridge.request("parts", ["parts"])
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
	map.custom_minimum_size = Vector2(0, 240)
	UI.panel(col).add_child(map)

	# Decision area, pinned at the bottom
	UI.label(footer, "PRACTICE RUNS: HOW HARD DOES FABA PUSH?", "HeadingLabel")
	UI.label(footer, "Each dot is a practice run. Left of the red line beats %s. Red dots: Faba made a mistake. Tap a row to pick it." % night["name"], "MutedLabel")
	var chart: Control = PracticeChart.new()
	chart.practice = practice["push_levels"]
	chart.posted = float(night["posted_time"])
	chart.rival_name = str(night["name"])
	chart.selected = choice["push"]
	chart.custom_minimum_size = Vector2(0, 300)
	chart.push_selected.connect(func(p): choice["push"] = p)
	UI.panel(footer).add_child(chart)

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
	UI.button(actions, "Back", show_warehouse)
	var skip := UI.button(actions, "Skip\n-%d rep" % SKIP_REP_COST, skip_night)
	if int(state["rep"]) < SKIP_REP_COST:
		skip.disabled = true
		skip.tooltip_text = "Chickening out costs %d rep. You have %d." % [SKIP_REP_COST, int(state["rep"])]
	var go := UI.button(actions, "SEND IT", send_it, "DangerButton")
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Chicken out of this race night: no money changes hands, but the scene
## notices. Costs SKIP_REP_COST rep; with less than that, you have to race.
func skip_night() -> void:
	if int(state["rep"]) < SKIP_REP_COST:
		return
	state["rep"] = int(state["rep"]) - SKIP_REP_COST
	var ev := next_event()
	state["history"].append({"when": when(ev["week"], ev["day"]), "rival": state["night"].get("name", "Zed"),
		"won": false, "skipped": true, "cash_change": 0, "rep_change": -SKIP_REP_COST})
	advance_past(ev)
	state["night"] = {}
	save_game()
	show_warehouse()


func send_it() -> void:
	show_message("LIGHTS OUT", "Faba lines up the DX.\n%s on the line, %s push." % [
		UI.money(choice["wager"]), str(choice["push"]).replace("_", " ")])
	var out := ProjectSettings.globalize_path("user://replays/race.json")
	bridge.request("race", ["race", "--track", state["night"]["track"], "--push", choice["push"],
		"--seed", str(randi() % 1000000), "--out", out] + parts_args())


## How many practice runs at this push level beat the posted time
## (shown only AFTER the race, so players can check their read).
func practice_beat(push: String, posted: float) -> Vector2i:
	var times: Array = practice["push_levels"][push]["times"]
	var n := 0
	for t in times:
		if float(t) < posted:
			n += 1
	return Vector2i(n, times.size())


func apply_result(r: Dictionary) -> Dictionary:
	## Settle the bet, move the calendar, and save immediately (before the replay).
	var night: Dictionary = state["night"]
	var ev := next_event()
	var won: bool = float(r["lap_time"]) < float(night["posted_time"])
	var wager := int(choice["wager"])
	var beat := practice_beat(r["push"], float(night["posted_time"]))
	var result := {
		"when": when(ev["week"], ev["day"]),
		"rival": night["name"], "rival_car": night["car"], "posted": night["posted_time"],
		"time": r["lap_time"], "won": won, "push": r["push"], "seed": r["seed"],
		"wager": wager, "cash_change": wager if won else -wager,
		"rep_change": REP_WIN if won else 0, "mistakes": r["mistakes"],
		"practice_beat": beat.x, "practice_runs": beat.y,
		"parts": state["installed"].values(), "loot": roll_loot() if won else ""}
	state["cash"] = int(state["cash"]) + int(result["cash_change"])
	state["rep"] = int(state["rep"]) + int(result["rep_change"])
	state["history"].append(result)
	state["night"] = {}
	advance_past(ev)
	save_game()
	return result


func show_race(replay_path: String, result: Dictionary) -> void:
	clear_screen()
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
	UI.stat_row(info, "Mistakes", "none" if result["mistakes"].is_empty() else ", ".join(result["mistakes"]))
	UI.stat_row(info, "Cash", "%s%s  ->  %s" % ["+" if won else "", UI.money(result["cash_change"]), UI.money(state["cash"])])
	UI.stat_row(info, "Rep", "+%d  ->  %d" % [result["rep_change"], state["rep"]])
	# The reveal: how good was the read? (hidden before the race on purpose)
	var reveal := UI.vbox(UI.panel(col), 4)
	UI.label(reveal, "YOUR READ", "HeadingLabel")
	UI.label(reveal, "In practice, %d of %d runs at %s push beat %s's %.2f." % [
		result["practice_beat"], result["practice_runs"], str(result["push"]).replace("_", " "),
		result["rival"], result["posted"]], "MutedLabel")
	if result.get("loot", "") != "":
		var loot := UI.vbox(UI.panel(col), 4)
		UI.label(loot, "LOOT", "HeadingLabel")
		var lp := part_by_id(result["loot"])
		UI.label(loot, "Zed's crew paid up with more than cash: %s (%s). It's in the warehouse." % [
			lp.get("name", result["loot"]), str(lp.get("rarity", "")).to_upper()])
	UI.button(footer, "BACK TO THE WAREHOUSE", show_warehouse, "AccentButton")


func show_broke() -> void:
	var record := wins_losses()
	show_message("BROKE",
		"%s left. You can't cover the %s buy-in.\n\nRecord %d W - %d L, rep %d.\n\nThe warehouse goes quiet. (Pink slips come later.)" % [
			UI.money(state["cash"]), UI.money(MIN_BUY_IN), record.x, record.y, int(state["rep"])],
		"START OVER", reset_game)


# ------------------------------------------------------------------ bridge replies

func _on_reply(tag: String, data: Dictionary) -> void:
	if not data.get("ok", false):
		show_message("THE SIM HIT A PROBLEM", str(data.get("error", "unknown error")), "BACK TO THE WAREHOUSE", show_warehouse)
		return
	match tag:
		"car_stats":
			car_stats = data
			_go(after_car_stats)
		"parts":
			catalog = data
			_go(after_catalog)
		"rival":
			data["event"] = event_key(next_event())
			state["night"] = data
			save_game()
			track_info = {}
			show_briefing()
		"track":
			track_info = data
			show_briefing()
		"practice":
			practice = data
			show_briefing()
		"race":
			var result := apply_result(data)
			show_race(data["replay"], result)


# ------------------------------------------------------------------ self-test

func game_test() -> void:
	## Headless end-to-end check: one full race night, printed. Run with
	##   godot --headless --path godot -- --gametest
	state = new_state()
	print("GAMETEST bridge: ", bridge.ready_to_use() if bridge.ready_to_use() != "" else "ok")
	print("GAMETEST migrate v1: ", migrate({"version": 1, "cash": 300, "rep": 5, "history": [], "night": {"x": 1}}))
	var ev := next_event()
	print("GAMETEST next event: %s, %s" % [when(ev["week"], ev["day"]), ev["title"]])
	bridge.request("car_stats", ["car_stats"])
	var r: Array = await bridge.replied
	print("GAMETEST car: %s, %d hp, dyno points %d" % [r[1]["name"], r[1]["hp"], r[1]["dyno"].size()])
	bridge.request("rival", ["rival", "--rival", RIVAL_FILE, "--seed", "42"])
	r = await bridge.replied
	state["night"] = r[1]
	print("GAMETEST rival: %s (%s), posted %.3f s" % [r[1]["name"], r[1]["car"], r[1]["posted_time"]])
	bridge.request("practice", ["practice", "--track", r[1]["track"]])
	r = await bridge.replied
	practice = r[1]
	print("GAMETEST practice runs: %d per push level" % practice["runs"])
	choice = {"push": "hard", "wager": 100}
	var out := ProjectSettings.globalize_path("user://replays/race.json")
	bridge.request("race", ["race", "--track", state["night"]["track"], "--push", "hard", "--seed", "9", "--out", out])
	r = await bridge.replied
	var result := apply_result(r[1])
	print("GAMETEST race: %.3f s vs %.3f s -> %s, cash %d, practice %d/%d" % [
		result["time"], result["posted"], "WIN" if result["won"] else "LOSS", state["cash"],
		result["practice_beat"], result["practice_runs"]])
	print("GAMETEST calendar after race: %s" % when(state["week"], state["day"]))
	bridge.request("parts", ["parts"])
	catalog = (await bridge.replied)[1]
	print("GAMETEST catalog: %d parts in %d slots" % [catalog["parts"].size(), catalog["slots"].size()])
	state["cash"] = 1000
	shop_message = ""
	buy_part("interior_strip")
	buy_part("tires_r_comp")                 # $1600: must be refused (cash)
	print("GAMETEST bought: owned %s, installed %s, cash %d" % [state["owned_parts"], state["installed"], state["cash"]])
	print("GAMETEST parts args: %s" % [parts_args()])
	bridge.request("car_stats", ["car_stats"] + parts_args())
	r = await bridge.replied
	print("GAMETEST car with parts: %d kg (stock 1112)" % r[1]["weight_kg"])
	print("GAMETEST migrate v2: %s" % [migrate({"version": 2, "cash": 1, "rep": 0, "week": 1, "day": 0, "history": [], "night": {}}).keys()])
	state["rep"] = 10
	skip_night()
	print("GAMETEST skip with 10 rep: rep %d, %s (blocked)" % [state["rep"], when(state["week"], state["day"])])
	state["rep"] = 60
	skip_night()
	print("GAMETEST skip with 60 rep: rep %d, %s" % [state["rep"], when(state["week"], state["day"])])
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
	bridge.request("car_stats", ["car_stats"])
	car_stats = (await bridge.replied)[1]
	show_warehouse()
	await snap(folder, "1_warehouse")
	bridge.request("parts", ["parts"])
	catalog = (await bridge.replied)[1]
	state["cash"] = 900
	state["owned_parts"] = ["interior_strip", "rsb_19", "shifter_short"]
	state["installed"] = {"interior": "interior_strip", "rear_sway": "rsb_19"}
	shop_message = "Bought and installed: Rear sway bar 19 mm."
	show_shop()
	await snap(folder, "1a_shop")
	bridge.request("car_stats", ["car_stats"] + parts_args())
	car_stats = (await bridge.replied)[1]
	show_car()
	await snap(folder, "1b_car")
	screen.get_node("Margin/Scroll").scroll_vertical = 900
	await snap(folder, "1b_car_parts")
	state["cash"] = 250
	state["owned_parts"] = []
	state["installed"] = {}
	state["history"] = [{"when": "FRI, WEEK 1", "rival": "Zed", "won": true, "cash_change": 150},
		{"when": "SAT, WEEK 1", "rival": "Zed", "won": false, "cash_change": -100}]
	state["week"] = 2
	state["day"] = 2
	show_calendar()
	await snap(folder, "1c_calendar")
	state["history"] = []
	state["week"] = 1
	state["day"] = 0
	bridge.request("rival", ["rival", "--rival", RIVAL_FILE, "--seed", "3"])
	state["night"] = (await bridge.replied)[1]
	bridge.request("track", ["track", "--track", state["night"]["track"]])
	track_info = (await bridge.replied)[1]
	bridge.request("practice", ["practice", "--track", state["night"]["track"]])
	practice = (await bridge.replied)[1]
	choice = {"push": "hard", "wager": 150}
	show_meeting()
	await snap(folder, "2_meeting")
	var out := ProjectSettings.globalize_path("user://replays/shots.json")
	bridge.request("race", ["race", "--track", state["night"]["track"], "--push", "hard", "--seed", "21", "--out", out])
	var r: Dictionary = (await bridge.replied)[1]
	var result := apply_result(r)
	show_race(out, result)
	viewer.t = viewer.lap_time
	await snap(folder, "5_race_finish")
	show_results(result)
	await snap(folder, "6_results")
	get_tree().quit()


func snap(folder: String, name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [folder, name])
	print("saved ", name)
