extends Node
## CONTRABAND96: game flow and state.
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
const ShellScene := preload("res://screens/shell.tscn")
const LOCATIONS := {
	"home": "GARAGE 1 / OXNARD, CA",
	"car": "THE CIVIC // CHASSIS_CONFIG",
	"calendar": "THE CALENDAR // TIMELINE",
	"team": "TEAM // CONTACTS",
	"shop": "SHOP // PARTS & CLASSIFIEDS",
}

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 10
const START_CASH := 2500
const MIN_BUY_IN := 100
const WAGER_STEP := 10
const REP_WIN := 10
const SKIP_REP_COST := 5 * REP_WIN   # chicken-out fee: five wins' worth of rep
const RIVAL_FILE := "data/rivals/zed_280z.json"
const PUSH_ORDER := ["safe", "normal", "hard", "flat_out"]

# Calendar day is zero-based: 0 = Monday, 6 = Sunday.
const DAY_NAMES := ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
const CALENDAR_ACTIVE_STATUSES := ["upcoming", "available"]
const CALENDAR_TERMINAL_STATUSES := ["completed", "cancelled"]

var state := {}            # saved: cash, followers, week, day, history, night
var car_stats := {}        # bridge replies, cached for the session
var track_info := {}
var practice := {}
var catalog := {}          # bridge "parts" reply (slots + parts with exact effects)
var shop_message := ""
var car_message := ""
var selected_test_road := "LOCAL_STRAIGHT" # Transient list section; never saved.
var bridge: Node
var screen: Control        # current UI screen (the shell while in the hub)
var shell: Control         # persistent hub shell (top rail, ribbon, bottom nav)
var hub_content: Control   # the hub screen currently inside the shell
var footer: VBoxContainer  # pinned area at the bottom of scrolling screens
var viewer: Node           # replay viewer while racing
var latest_test_result := {}
var pending_test := {}
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
	if "--testlogtest" in args:
		test_log_test()
		return
	if "--calendartest" in args:
		calendar_test()
		return
	if "--worktest" in args:
		work_test()
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
	show_warehouse()


func new_state() -> Dictionary:
	return {"version": SAVE_VERSION, "cash": START_CASH, "followers": 0, "rep": 0, "week": 1, "day": 0,
		"civic": {"chassis_id": "CHASSIS_0001", "base_car_id": "eg6_sir_ii_1995", "installed": {}},
		"history": [], "night": {},
		"inventory": [], "next_uid": 1,
		"market": {"seeded": false, "used_listings": []},
		"calendar": initial_calendar(1, 0),
		"garage_work": {"next_work_id": 1, "orders": []},
		"test_log": {"next_id": 1, "runs": []}}


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
	if v < 4:                        # v3 -> v4: every part becomes a rolled instance
		var inv := []
		var uid_of := {}
		var n := 1
		for id in data.get("owned_parts", []):
			var uid := "p%d" % n
			n += 1
			inv.append({"uid": uid, "part": id, "quality": 0.5, "revealed": true,
				"source": "shop"})
			uid_of[id] = uid
		var installed := {}
		for slot in data.get("installed", {}):
			var id: String = data["installed"][slot]
			if uid_of.has(id):
				installed[slot] = uid_of[id]
		data.erase("owned_parts")
		data["inventory"] = inv
		data["installed"] = installed
		data["pity"] = {}
		data["next_uid"] = n
		v = 4
	if v < 5:                        # v4 -> v5: CONTRABAND96 identity migration
		# Keep legacy rep temporarily because the old wager/gacha loop still reads it.
		# Followers are now the visible identity; rep will disappear when those systems retire.
		data["followers"] = int(data.get("rep", 0))
		data["rep"] = int(data.get("rep", 0))
		data.erase("intro_seen")
		v = 5
	if not data.has("rep"):
		data["rep"] = int(data.get("followers", 0))
	if v < 6:                        # v5 -> v6: permanent player Civic identity
		v = 6
	var civic: Dictionary = data.get("civic", {})
	if not civic.has("chassis_id"):
		civic["chassis_id"] = "CHASSIS_0001"
	if not civic.has("base_car_id"):
		civic["base_car_id"] = "eg6_sir_ii_1995"
	if v < 7:                        # v6 -> v7: fixed-spec physical ownership
		var owned := []
		var known_uids := {}
		var next_uid := maxi(1, int(data.get("next_uid", 1)))
		for old in data.get("inventory", []):
			if typeof(old) != TYPE_DICTIONARY:
				continue
			var uid := str(old.get("uid", ""))
			var part := str(old.get("part", ""))
			if uid == "" or part == "" or known_uids.has(uid):
				continue
			known_uids[uid] = true
			owned.append({"uid": uid, "part": part, "source": "legacy",
				"acquired_price": 0, "acquired_week": 0, "acquired_day": 0})
			if uid.begins_with("p") and uid.substr(1).is_valid_int():
				next_uid = maxi(next_uid, int(uid.substr(1)) + 1)
		var installed := {}
		for slot in data.get("installed", {}):
			var uid := str(data["installed"][slot])
			if known_uids.has(uid):
				installed[slot] = uid
		civic["installed"] = installed
		data["inventory"] = owned
		data["next_uid"] = next_uid
		data["market"] = {"seeded": false, "used_listings": []}
		data.erase("installed")
		data.erase("pity")
		v = 7
	if not civic.has("installed"):
		civic["installed"] = {}
	if v < 8:                        # v7 -> v8: persistent controlled-test history
		data["test_log"] = {"next_id": 1, "runs": []}
		v = 8
	var test_log = data.get("test_log", {})
	if typeof(test_log) != TYPE_DICTIONARY:
		test_log = {}
	var runs = test_log.get("runs", [])
	if typeof(runs) != TYPE_ARRAY:
		runs = []
	var next_test_id := maxi(1, int(test_log.get("next_id", 1)))
	for run in runs:
		if typeof(run) != TYPE_DICTIONARY:
			continue
		var run_id := str(run.get("run_id", ""))
		if run_id.begins_with("TEST_") and run_id.trim_prefix("TEST_").is_valid_int():
			next_test_id = maxi(next_test_id, int(run_id.trim_prefix("TEST_")) + 1)
	test_log["runs"] = runs
	test_log["next_id"] = next_test_id
	data["test_log"] = test_log
	data["week"] = maxi(1, int(data.get("week", 1)))
	data["day"] = clampi(int(data.get("day", 0)), 0, 6)
	if v < 9:                        # v8 -> v9: persistent calendar events
		data["calendar"] = initial_calendar(int(data["week"]), int(data["day"]))
		v = 9
	data["calendar"] = normalize_calendar_data(data.get("calendar", {}),
		int(data["week"]), int(data["day"]))
	if v < 10:                       # v9 -> v10: pending physical garage work
		data["garage_work"] = {"next_work_id": 1, "orders": []}
		v = 10
	var work: Dictionary = data.get("garage_work", {})
	var orders: Array = work.get("orders", [])
	var next_work_id := maxi(1, int(work.get("next_work_id", 1)))
	for order in orders:
		var work_id := str(order.get("work_id", ""))
		if work_id.begins_with("WORK_") and work_id.trim_prefix("WORK_").is_valid_int():
			next_work_id = maxi(next_work_id, int(work_id.trim_prefix("WORK_")) + 1)
	data["garage_work"] = {"next_work_id": next_work_id, "orders": orders}
	data["civic"] = civic
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

const OPEN_STYLES := ["technical", "balanced", "flowing"]


func absolute_day(week: int, day: int) -> int:
	return (week - 1) * 7 + day


func calendar_date_after(week: int, day: int, offset: int) -> Dictionary:
	var ordinal := absolute_day(week, day) + offset
	return {"week": floori(float(ordinal) / 7.0) + 1, "day": ordinal % 7}


func initial_calendar(week: int, day: int) -> Dictionary:
	## Minimal deterministic fixtures for the persistent calendar foundation.
	## They communicate world texture only; neither event grants an action or reward.
	var garage_date := calendar_date_after(week, day, 1)
	var meet_date := calendar_date_after(week, day, 3)
	return {"next_event_id": 3, "events": [
		{"event_id": "EVENT_000001", "type": "garage", "title": "GARAGE NIGHT",
			"scheduled_week": garage_date["week"], "scheduled_day": garage_date["day"],
			"location_id": "GARAGE_1", "road_id": "", "status": "upcoming",
			"description": "An open evening at the garage."},
		{"event_id": "EVENT_000002", "type": "meet", "title": "OXNARD PARKING LOT MEET",
			"scheduled_week": meet_date["week"], "scheduled_day": meet_date["day"],
			"location_id": "OXNARD_MEET", "road_id": "", "status": "upcoming",
			"description": "A local meet notice. No competition is scheduled."},
	]}


func calendar_status_for_date(event: Dictionary, week: int, day: int) -> String:
	var current := absolute_day(week, day)
	var scheduled := absolute_day(int(event["scheduled_week"]), int(event["scheduled_day"]))
	if scheduled > current:
		return "upcoming"
	if scheduled == current:
		return "available"
	return "missed"


func normalize_calendar_data(value, week: int, day: int) -> Dictionary:
	var calendar: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	var source_events = calendar.get("events", [])
	if typeof(source_events) != TYPE_ARRAY:
		source_events = []
	var events := []
	var known_ids := {}
	var next_id := maxi(1, int(calendar.get("next_event_id", 1)))
	for raw in source_events:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = raw.duplicate(true)
		var event_id := str(event.get("event_id", ""))
		if event_id == "" or known_ids.has(event_id):
			continue
		known_ids[event_id] = true
		if event_id.begins_with("EVENT_") and event_id.trim_prefix("EVENT_").is_valid_int():
			next_id = maxi(next_id, int(event_id.trim_prefix("EVENT_")) + 1)
		event["type"] = str(event.get("type", "world"))
		event["title"] = str(event.get("title", "UNTITLED EVENT"))
		event["scheduled_week"] = maxi(1, int(event.get("scheduled_week", week)))
		event["scheduled_day"] = clampi(int(event.get("scheduled_day", day)), 0, 6)
		event["location_id"] = str(event.get("location_id", ""))
		event["road_id"] = str(event.get("road_id", ""))
		event["description"] = str(event.get("description", ""))
		var status := str(event.get("status", "upcoming"))
		if status not in CALENDAR_TERMINAL_STATUSES:
			status = calendar_status_for_date(event, week, day)
		event["status"] = status
		events.append(event)
	return {"next_event_id": next_id, "events": events}


func refresh_calendar_event_statuses() -> void:
	state["calendar"] = normalize_calendar_data(state.get("calendar", {}),
		int(state["week"]), int(state["day"]))


func sorted_calendar_events() -> Array:
	var events: Array = state["calendar"]["events"].duplicate(true)
	events.sort_custom(func(a, b):
		var a_date := absolute_day(int(a["scheduled_week"]), int(a["scheduled_day"]))
		var b_date := absolute_day(int(b["scheduled_week"]), int(b["scheduled_day"]))
		return a_date < b_date or (a_date == b_date and str(a["event_id"]) < str(b["event_id"])))
	return events


func next_calendar_event() -> Dictionary:
	refresh_calendar_event_statuses()
	for event in sorted_calendar_events():
		if event["status"] in CALENDAR_ACTIVE_STATUSES:
			return event
	return {}


func upcoming_calendar_events(limit: int) -> Array:
	refresh_calendar_event_statuses()
	var out := []
	for event in sorted_calendar_events():
		if event["status"] in CALENDAR_ACTIVE_STATUSES:
			out.append(event)
			if out.size() >= limit:
				break
	return out


func calendar_events_for_week(week: int) -> Array:
	refresh_calendar_event_statuses()
	return sorted_calendar_events().filter(func(event): return int(event["scheduled_week"]) == week)


func advance_days(days, reason: String) -> bool:
	## The only authoritative clock mutation. Events are available for their
	## scheduled day and become missed, without a penalty, once that day passes.
	if typeof(days) != TYPE_INT or int(days) < 0 or reason.strip_edges() == "":
		return false
	if int(days) == 0:
		return true
	var target := calendar_date_after(int(state["week"]), int(state["day"]), int(days))
	state["week"] = target["week"]
	state["day"] = target["day"]
	refresh_calendar_event_statuses()
	complete_due_work()
	# A cached legacy race night cannot survive an intentional date change.
	state["night"] = {}
	track_info = {}
	practice = {}
	save_game()
	return true


## Dormant prototype race scheduling. It remains available to existing
## regression tooling but no longer supplies HOME or CALENDAR content.
func legacy_race_events_for_week(week: int) -> Array:
	return [
		{"day": 4, "type": "rival", "title": "Zed (280Z) on his home road"},
		{"day": 5, "type": "open", "title": "Open road (%s), street racer" % OPEN_STYLES[(week - 1) % 3]},
	]


func when(week: int, day: int) -> String:
	return "%s, WEEK %d" % [DAY_NAMES[day], week]


func next_legacy_race_event() -> Dictionary:
	var week := int(state["week"])
	for w in range(week, week + 52):
		for e in legacy_race_events_for_week(w):
			if w > week or int(e["day"]) >= int(state["day"]):
				var ev: Dictionary = e.duplicate()
				ev["week"] = w
				return ev
	return {}

func advance_past_legacy_race(event: Dictionary) -> bool:
	var current := absolute_day(int(state["week"]), int(state["day"]))
	var after_event := absolute_day(int(event["week"]), int(event["day"])) + 1
	return advance_days(maxi(0, after_event - current), "legacy race resolved")


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
	shell = null
	hub_content = null
	footer = null


## Show a hub screen inside the persistent shell. The shell is created once;
## moving between hub tabs swaps only its content slot.
func open_hub(packed: PackedScene, tab: String) -> Control:
	if shell == null:
		clear_screen()
		shell = ShellScene.instantiate()
		add_child(shell)
		shell.go.connect(_go)
		screen = shell
	shell.set_home_mode(tab == "home")
	shell.set_stats(int(state["cash"]), int(state["followers"]))
	shell.set_location(LOCATIONS[tab], tab)
	hub_content = packed.instantiate()
	hub_content.go.connect(_go)
	shell.set_content(hub_content)
	return hub_content


func _go(target: String) -> void:
	match target:
		"warehouse", "home":
			show_warehouse()
		"car":
			show_car()
		"calendar":
			show_calendar()
		"team":
			show_message("TEAM", "Contacts and relationships will grow here. For now, the garage is quiet.", "HOME", show_warehouse)
		"shop":
			show_shop()
		"local_straight":
			start_local_straight()
		"local_curves":
			start_local_curves()
		"test_log":
			show_test_log()
		"race":
			show_briefing()


func common_info() -> Dictionary:
	return {"cash": int(state["cash"]), "followers": int(state["followers"]), "rep": int(state.get("rep", 0)), "min_buy_in": MIN_BUY_IN}


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
	var brand := UI.label(header, "CONTRABAND96", "HeadingLabel")
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(header, UI.money(state["cash"]), "HeadingLabel",
		UI.GOOD if state["cash"] >= MIN_BUY_IN else UI.BAD)
	UI.label(header, "%d FOLLOWERS" % int(state["followers"]), "HeadingLabel", Color.WHITE)

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
	var ev := next_calendar_event()
	var info := common_info()
	info["civic"] = state["civic"].duplicate(true)
	info["civic"]["work_in_progress"] = active_work_orders()
	var installed_uids: Array = state["civic"]["installed"].values()
	var owned_spares := 0
	for owned in state["inventory"]:
		if str(owned.get("uid", "")) not in installed_uids:
			owned_spares += 1
	info["owned_spares"] = owned_spares
	info["today"] = when(state["week"], state["day"])
	info["tape_date"] = "%s / WEEK %02d" % [DAY_NAMES[int(state["day"])], int(state["week"])]
	info["next_calendar"] = "NO SCHEDULED ITEMS" if ev.is_empty() else "%s / %s" % [
		when(int(ev["scheduled_week"]), int(ev["scheduled_day"])), ev["title"]]
	info["test_count"] = state["test_log"]["runs"].size()
	open_hub(WarehouseScene, "home").setup(info)


func show_car() -> void:
	if catalog.is_empty():
		show_message("THE CAR", "Checking the parts shelf...")
		after_catalog = "car"
		bridge.request("parts", ["shop_catalog"])
		return
	if car_stats.is_empty():
		show_message("THE CAR", "Strapping the EG6 to the dyno...")
		after_car_stats = "car"
		bridge.request("car_stats", ["car_stats"] + parts_args())
		return
	# Dropdown options per slot: every compatible physical part you own.
	var options := {}
	for inst in state["inventory"]:
		var p := part_by_id(inst["part"])
		if p.is_empty():
			continue
		if not options.has(p["slot"]):
			options[p["slot"]] = []
		options[p["slot"]].append([inst["uid"], p["name"]])
	var car: Control = open_hub(CarScene, "car")
	car.part_changed.connect(install_part)
	car.setup(common_info(), car_stats,
		{"slots": catalog["slots"], "options": options, "installed": state["civic"]["installed"],
		"active_work": active_work_orders(), "message": car_message})


func show_shop() -> void:
	if catalog.is_empty():
		show_message("PARTS", "Checking the parts shelf...")
		after_catalog = "shop"
		bridge.request("parts", ["shop_catalog"])
		return
	var shop: Control = open_hub(ShopScene, "shop")
	shop.buy_retail.connect(buy_retail)
	shop.buy_used.connect(buy_used)
	shop.setup(common_info(), catalog, state["inventory"], state["civic"]["installed"],
		state["market"]["used_listings"], shop_message)
	shop_message = ""


## Installed fixed-spec definitions for every sim call.
func parts_args() -> Array:
	var entries := []
	for slot in state["civic"]["installed"]:
		var inst := instance(state["civic"]["installed"][slot])
		if not inst.is_empty():
			entries.append(inst["part"])
	entries.sort()
	return [] if entries.is_empty() else ["--parts", ",".join(entries)]


func installed_configuration_snapshot() -> Array:
	## Resolve the authoritative installed UID map into a stable run snapshot.
	var installed := []
	var slots: Array = state["civic"]["installed"].keys()
	slots.sort()
	for slot in slots:
		var uid := str(state["civic"]["installed"][slot])
		var owned := instance(uid)
		if not owned.is_empty():
			installed.append({"slot": slot, "owned_uid": uid,
				"definition_id": str(owned["part"])})
	return installed


func local_test_snapshot(data: Dictionary, run_id := "", replay_ref := "") -> Dictionary:
	return {
		"run_id": run_id,
		"road_id": data["road_id"],
		"road": data["road"].duplicate(true),
		"chassis_id": state["civic"]["chassis_id"],
		"base_car_id": state["civic"]["base_car_id"],
		"calendar": {"week": int(state["week"]), "day": int(state["day"]),
			"label": when(int(state["week"]), int(state["day"]))},
		"installed": installed_configuration_snapshot(),
		"conditions": data["conditions"].duplicate(true),
		"vehicle_state": data["vehicle_state"].duplicate(true),
		"measurement_scope": data.get("measurement_scope", {}).duplicate(true),
		"measurements": data["measurements"].duplicate(true),
		"replay": replay_ref if replay_ref != "" else data["replay"],
	}


func next_test_run_id() -> String:
	var next_id := maxi(1, int(state["test_log"].get("next_id", 1)))
	for run in state["test_log"]["runs"]:
		var existing := str(run.get("run_id", ""))
		if existing.begins_with("TEST_") and existing.trim_prefix("TEST_").is_valid_int():
			next_id = maxi(next_id, int(existing.trim_prefix("TEST_")) + 1)
	return "TEST_%06d" % next_id


func prepare_test_run(road_id: String) -> Dictionary:
	var run_id := next_test_run_id()
	return {"run_id": run_id, "road_id": road_id,
		"replay": "user://replays/tests/%s.json" % run_id}


func complete_test_run(data: Dictionary, prepared: Dictionary) -> Dictionary:
	if prepared.is_empty() or str(prepared.get("road_id", "")) != str(data.get("road_id", "")):
		return {}
	var result := local_test_snapshot(data, str(prepared["run_id"]), str(prepared["replay"]))
	state["test_log"]["runs"].append(result.duplicate(true))
	state["test_log"]["next_id"] = int(str(prepared["run_id"]).trim_prefix("TEST_")) + 1
	save_game()
	return result


func start_local_straight() -> void:
	show_message("LOCAL STRAIGHT", "Setting up %s for a controlled quarter-mile run.\n\nFixed road. Fixed conditions. Reference driver. $0." % state["civic"]["chassis_id"])
	pending_test = prepare_test_run("LOCAL_STRAIGHT")
	var out := ProjectSettings.globalize_path(pending_test["replay"])
	bridge.request("local_straight", ["local_straight", "--out", out] + parts_args())


func start_local_curves() -> void:
	show_message("LOCAL CURVES", "Setting up %s for a controlled handling run.\n\nFixed road. Fixed conditions. Reference driver. $0." % state["civic"]["chassis_id"])
	pending_test = prepare_test_run("LOCAL_CURVES")
	var out := ProjectSettings.globalize_path(pending_test["replay"])
	bridge.request("local_curves", ["local_curves", "--out", out] + parts_args())


func part_by_id(id: String) -> Dictionary:
	for p in catalog["parts"]:
		if p["id"] == id:
			return p
	return {}


func instance(uid: String) -> Dictionary:
	for inst in state["inventory"]:
		if inst["uid"] == uid:
			return inst
	return {}


func accept_shop_catalog(data: Dictionary) -> void:
	catalog = data
	var market: Dictionary = state["market"]
	var changed := false
	if not market.get("seeded", false):
		market["used_listings"] = data["initial_used"].duplicate(true)
		market["seeded"] = true
		changed = true
	var valid_inventory := []
	var by_uid := {}
	for inst in state["inventory"]:
		if typeof(inst) != TYPE_DICTIONARY or not inst.has("uid") or not inst.has("part"):
			continue
		var p := part_by_id(str(inst["part"]))
		var uid := str(inst["uid"])
		if p.is_empty() or uid == "" or by_uid.has(uid):
			continue
		by_uid[uid] = p
		valid_inventory.append(inst)
	if valid_inventory.size() != state["inventory"].size():
		state["inventory"] = valid_inventory
		changed = true
	var valid_installed := {}
	for slot in state["civic"]["installed"]:
		var uid := str(state["civic"]["installed"][slot])
		if by_uid.has(uid) and by_uid[uid]["slot"] == slot and not uid in valid_installed.values():
			valid_installed[slot] = uid
	if valid_installed != state["civic"]["installed"]:
		state["civic"]["installed"] = valid_installed
		changed = true
	if changed:
		save_game()


func add_instance(part_id: String, source: String, price: int,
		seller_id := "", listing_id := "") -> Dictionary:
	var uid := "p%d" % int(state["next_uid"])
	while not instance(uid).is_empty():
		state["next_uid"] = int(state["next_uid"]) + 1
		uid = "p%d" % int(state["next_uid"])
	var inst := {"uid": uid, "part": part_id, "source": source,
		"acquired_price": price, "acquired_week": int(state["week"]),
		"acquired_day": int(state["day"])}
	if seller_id != "":
		inst["seller_id"] = seller_id
		inst["listing_id"] = listing_id
	state["next_uid"] = int(state["next_uid"]) + 1
	state["inventory"].append(inst)
	return inst


func buy_retail(id: String) -> void:
	if not id in catalog["retail_ids"]:
		return
	var p := part_by_id(id)
	if p.is_empty() or int(state["cash"]) < int(p["price"]):
		shop_message = "Not enough cash for that part."
		show_shop()
		return
	state["cash"] = int(state["cash"]) - int(p["price"])
	add_instance(id, "retail", int(p["price"]))
	save_game()
	shop_message = "Bought %s. Find it under CAR to install." % p["name"]
	show_shop()


func buy_used(listing_id: String) -> void:
	var listings: Array = state["market"]["used_listings"]
	for i in listings.size():
		var listing: Dictionary = listings[i]
		if listing["listing_id"] != listing_id:
			continue
		var p := part_by_id(listing["part"])
		if p.is_empty() or int(state["cash"]) < int(listing["price"]):
			shop_message = "Not enough cash for that listing."
			show_shop()
			return
		state["cash"] = int(state["cash"]) - int(listing["price"])
		add_instance(listing["part"], "used", int(listing["price"]),
			listing["seller_id"], listing_id)
		listings.remove_at(i)
		save_game()
		shop_message = "Bought %s. Find it under CAR to install." % p["name"]
		show_shop()
		return


## Whole-day, provisional garage reservations are supplied by the active
## market data. There is no sub-day clock or daily action cap.
func active_work_orders() -> Array:
	return state["garage_work"]["orders"].filter(func(order): return order["status"] == "active")


func queue_part_work(slot: String, uid: String) -> bool:
	if catalog.is_empty() or not catalog["slots"].has(slot):
		return false
	var installed: Dictionary = state["civic"]["installed"]
	var operation := "remove" if uid == "" else "install"
	var owned_uid := str(installed.get(slot, "")) if operation == "remove" else uid
	if owned_uid == "":
		return false
	var owned := instance(owned_uid)
	var part := {} if owned.is_empty() else part_by_id(str(owned["part"]))
	if part.is_empty() or part.get("slot", "") != slot:
		return false
	if operation == "install" and (installed.has(slot) or owned_uid in installed.values()):
		return false
	for pending in active_work_orders():
		if pending["slot"] == slot or pending["owned_uid"] == owned_uid:
			return false
	var duration := int(catalog.get("work_days_by_slot", {}).get(slot, {}).get(operation, 0))
	if duration < 1:
		return false
	var due := calendar_date_after(int(state["week"]), int(state["day"]), duration)
	var work: Dictionary = state["garage_work"]
	var order := {"work_id": "WORK_%06d" % int(work["next_work_id"]),
		"chassis_id": str(state["civic"]["chassis_id"]), "operation": operation,
		"slot": slot, "owned_uid": owned_uid, "definition_id": str(owned["part"]),
		"start_week": int(state["week"]), "start_day": int(state["day"]),
		"duration_days": duration, "due_week": int(due["week"]), "due_day": int(due["day"]),
		"status": "active"}
	work["next_work_id"] = int(work["next_work_id"]) + 1
	work["orders"].append(order)
	save_game()
	return true


func complete_due_work() -> void:
	var today := absolute_day(int(state["week"]), int(state["day"]))
	for order in state["garage_work"]["orders"]:
		if order["status"] != "active" or absolute_day(int(order["due_week"]), int(order["due_day"])) > today:
			continue
		var slot := str(order["slot"])
		var uid := str(order["owned_uid"])
		var owned := instance(uid)
		var installed: Dictionary = state["civic"]["installed"]
		var valid := str(order["chassis_id"]) == str(state["civic"]["chassis_id"])
		valid = valid and not owned.is_empty() and str(owned.get("part", "")) == str(order["definition_id"])
		if order["operation"] == "install":
			valid = valid and not installed.has(slot) and uid not in installed.values()
			if valid:
				installed[slot] = uid
		elif order["operation"] == "remove":
			valid = valid and str(installed.get(slot, "")) == uid
			if valid:
				installed.erase(slot)
		else:
			valid = false
		order["status"] = "completed" if valid else "cancelled"
		order["finished_week"] = int(order["due_week"])
		order["finished_day"] = int(order["due_day"])
		if valid:
			car_stats = {}
			practice = {}


## CAR requests a job; only complete_due_work mutates civic.installed.
func install_part(slot: String, uid: String, refresh := true) -> void:
	if queue_part_work(slot, uid):
		var order: Dictionary = state["garage_work"]["orders"].back()
		car_message = "%s QUEUED / %s / DUE %s" % [str(order["operation"]).to_upper(),
			str(order["work_id"]), when(int(order["due_week"]), int(order["due_day"]))]
	else:
		car_message = "WORK NOT QUEUED / REMOVE AN INSTALLED PART FIRST OR FINISH ACTIVE WORK."
	if refresh:
		show_car()


func show_calendar() -> void:
	var info := common_info()
	var week := int(state["week"])
	info["week"] = week
	info["day"] = int(state["day"])
	info["today"] = when(week, int(state["day"]))
	var week_events := {}
	for event in calendar_events_for_week(week):
		var event_day := int(event["scheduled_day"])
		var labels: Array = week_events.get(event_day, [])
		labels.append(str(event["type"]).to_upper())
		week_events[event_day] = labels
	info["week_events"] = week_events
	info["upcoming"] = upcoming_calendar_events(8)
	var past_events := []
	for event in sorted_calendar_events():
		if event["status"] not in CALENDAR_ACTIVE_STATUSES:
			past_events.append(event)
	info["past_events"] = past_events
	var legacy_history := []
	var hist: Array = state["history"]
	for i in range(hist.size() - 1, maxi(hist.size() - 6, -1), -1):
		var r: Dictionary = hist[i]
		if not r.has("rival"):
			continue
		if r.get("skipped", false):
			legacy_history.append([r.get("when", "-"), "vs %s" % r["rival"], "SKIPPED"])
		else:
			legacy_history.append([r.get("when", "-"), "vs %s" % r["rival"],
				"%s  %+d" % ["W" if r["won"] else "L", int(r["cash_change"])]])
	info["legacy_history"] = legacy_history
	var calendar: Control = open_hub(CalendarScene, "calendar")
	calendar.advance_day.connect(func():
		if advance_days(1, "calendar development control"):
			show_calendar())
	calendar.setup(info)


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
	if int(state["cash"]) < MIN_BUY_IN:
		show_message("RACE NIGHT", "The current wager needs %s. Your Civic and garage remain available." % UI.money(MIN_BUY_IN),
			"BACK TO HOME", show_warehouse)
		return
	var ev := next_legacy_race_event()
	# A saved night belongs to one calendar event; a stale one gets redrawn
	if not state["night"].is_empty() and state["night"].get("event") != event_key(ev):
		state["night"] = {}
	# Draw the night's rival time once and save it (no rerolling by restarting)
	if state["night"].is_empty():
		show_message("WORD ON THE STREET", "Finding out who's running tonight.\n\nThe first time on a road, Faba runs practice laps at every push level. Give it 15-30 seconds.")
		var seed := str(randi() % 1000000)
		if ev["type"] == "open":
			bridge.request("night", ["street", "--week", str(ev["week"]), "--seed", seed])
		else:
			bridge.request("night", ["rival", "--rival", RIVAL_FILE, "--seed", seed])
		return
	if track_info.is_empty():
		show_message("SCOUTING", "Driving the road in daylight.")
		bridge.request("track", ["track", "--track", state["night"]["track"]])
		return
	if catalog.is_empty():
		after_catalog = "race"
		bridge.request("parts", ["shop_catalog"])
		return
	if practice.is_empty():
		show_message("PRACTICE", "Faba's running the road at every push level.")
		bridge.request("practice", ["practice", "--track", state["night"]["track"]] + parts_args())
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
	state["followers"] = int(state["rep"])
	var ev := next_legacy_race_event()
	state["history"].append({"when": when(ev["week"], ev["day"]), "rival": state["night"].get("name", "Zed"),
		"won": false, "skipped": true, "cash_change": 0, "rep_change": -SKIP_REP_COST})
	state["night"] = {}
	advance_past_legacy_race(ev)
	show_warehouse()


func send_it() -> void:
	show_message("LIGHTS OUT", "Faba lines up the EG6.\n%s on the line, %s push." % [
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
	var ev := next_legacy_race_event()
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
		"parts": parts_args()}
	state["cash"] = int(state["cash"]) + int(result["cash_change"])
	state["rep"] = int(state["rep"]) + int(result["rep_change"])
	state["followers"] = int(state["rep"])
	state["history"].append(result)
	state["night"] = {}
	advance_past_legacy_race(ev)
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
	UI.button(footer, "BACK TO HOME", show_warehouse, "AccentButton")


func show_local_straight_replay(result: Dictionary) -> void:
	clear_screen()
	viewer = Viewer.new()
	viewer.replay_path = result["replay"]
	viewer.embedded = true
	viewer.status_text = "REFERENCE DRIVER"
	viewer.finished_viewing.connect(show_test_results.bind(result))
	add_child(viewer)


func show_test_results(result: Dictionary, from_log := false) -> void:
	var col := new_screen()
	UI.spacer(col, false).custom_minimum_size.y = 24
	UI.label(col, "TEST RESULTS", "TitleLabel", UI.ACCENT)
	UI.label(col, "LOCAL STRAIGHT", "BigNumberLabel")
	UI.label(col, "Controlled standing-start quarter mile / fixed dry baseline", "MutedLabel")
	if str(result.get("run_id", "")) != "":
		UI.label(col, "%s / %s" % [result["run_id"], test_calendar_summary(result)], "MutedLabel")

	var measurements: Dictionary = result["measurements"]
	var measured := UI.vbox(UI.panel(col), 6)
	UI.label(measured, "MEASURED", "HeadingLabel")
	UI.stat_row(measured, "0-60 mph", "%.3f s" % float(measurements["zero_60_s"]))
	UI.stat_row(measured, "Quarter mile", "%.3f s" % float(measurements["quarter_mile_s"]))
	UI.stat_row(measured, "Trap speed", "%.1f mph" % float(measurements["quarter_mile_trap_mph"]))
	UI.stat_row(measured, "60-0 braking", "%.1f ft" % float(measurements["sixty_zero_ft"]))

	var config := UI.vbox(UI.panel(col), 6)
	UI.label(config, "CIVIC CONFIGURATION", "HeadingLabel")
	if str(result.get("run_id", "")) != "":
		UI.stat_row(config, "Run", str(result["run_id"]))
		UI.stat_row(config, "Date", test_calendar_summary(result))
	UI.stat_row(config, "Chassis", str(result["chassis_id"]))
	UI.stat_row(config, "Base car", str(result["base_car_id"]))
	var installed: Array = result["installed"]
	UI.stat_row(config, "Installed", "stock" if installed.is_empty() else "%d physical part%s" % [
		installed.size(), "" if installed.size() == 1 else "s"])
	for part in installed:
		UI.label(config, "%s / %s / %s" % [part["slot"], part["owned_uid"], part["definition_id"]], "MutedLabel")

	var conditions: Dictionary = result["conditions"]
	UI.label(col, "%s / %.0f C / %s" % [
		str(conditions["surface"]).to_upper(), float(conditions["ambient_c"]),
		str(conditions["reference_driver"]).to_upper()], "MutedLabel")
	if from_log:
		add_historical_test_details(col, result)
	add_test_result_footer(result, from_log)


func show_local_curves_replay(result: Dictionary) -> void:
	clear_screen()
	viewer = Viewer.new()
	viewer.replay_path = result["replay"]
	viewer.embedded = true
	viewer.status_text = "REFERENCE DRIVER"
	viewer.finished_viewing.connect(show_curves_results.bind(result))
	add_child(viewer)


func show_curves_results(result: Dictionary, from_log := false) -> void:
	var col := new_screen()
	UI.spacer(col, false).custom_minimum_size.y = 24
	UI.label(col, "TEST RESULTS", "TitleLabel", UI.ACCENT)
	UI.label(col, "LOCAL CURVES", "BigNumberLabel")
	UI.label(col, "Controlled handling route / fixed dry baseline", "MutedLabel")
	if str(result.get("run_id", "")) != "":
		UI.label(col, "%s / %s" % [result["run_id"], test_calendar_summary(result)], "MutedLabel")

	var measurements: Dictionary = result["measurements"]
	var measured := UI.vbox(UI.panel(col), 6)
	UI.label(measured, "MEASURED", "HeadingLabel")
	UI.stat_row(measured, "Total", "%.3f s" % float(measurements["total_time_s"]))
	UI.stat_row(measured, "Peak speed", "%.1f mph" % float(measurements["peak_speed_mph"]))
	UI.stat_row(measured, "Braking zones", str(int(measurements["braking_zones"])))
	UI.stat_row(measured, "Braking distance", "%.1f m" % float(measurements["braking_distance_m"]))
	UI.stat_row(measured, "Braking time", "%.3f s" % float(measurements["braking_time_s"]))
	UI.stat_row(measured, "Peak brake", "%.1f%%" % (float(measurements["peak_brake"]) * 100.0))

	for corner in measurements["corners"]:
		var panel := UI.vbox(UI.panel(col), 4)
		UI.label(panel, "CORNER %d / %s" % [int(corner["index"]), corner["pace_note"]], "HeadingLabel")
		UI.stat_row(panel, "Time", "%.3f s" % float(corner["time_s"]))
		UI.stat_row(panel, "Entry", "%.1f mph" % float(corner["entry_mph"]))
		UI.stat_row(panel, "Minimum", "%.1f mph" % float(corner["minimum_mph"]))
		UI.stat_row(panel, "Exit", "%.1f mph" % float(corner["exit_mph"]))

	var config := UI.vbox(UI.panel(col), 6)
	UI.label(config, "CIVIC CONFIGURATION", "HeadingLabel")
	if str(result.get("run_id", "")) != "":
		UI.stat_row(config, "Run", str(result["run_id"]))
		UI.stat_row(config, "Date", test_calendar_summary(result))
	UI.stat_row(config, "Chassis", str(result["chassis_id"]))
	UI.stat_row(config, "Base car", str(result["base_car_id"]))
	var installed: Array = result["installed"]
	UI.stat_row(config, "Installed", "stock" if installed.is_empty() else "%d physical part%s" % [
		installed.size(), "" if installed.size() == 1 else "s"])
	for part in installed:
		UI.label(config, "%s / %s / %s" % [part["slot"], part["owned_uid"], part["definition_id"]], "MutedLabel")

	var conditions: Dictionary = result["conditions"]
	UI.label(col, "%s / %.0f C / %s / SEED %d" % [
		str(conditions["surface"]).to_upper(), float(conditions["ambient_c"]),
		str(conditions["reference_driver"]).to_upper(), int(conditions["driver_seed"])], "MutedLabel")
	if from_log:
		add_historical_test_details(col, result)
	add_test_result_footer(result, from_log)


func add_historical_test_details(col: VBoxContainer, result: Dictionary) -> void:
	var road: Dictionary = result.get("road", {})
	var road_panel := UI.vbox(UI.panel(col), 4)
	UI.label(road_panel, "ROAD SNAPSHOT", "HeadingLabel")
	UI.stat_row(road_panel, "Geometry version", str(road.get("geometry_version", "unknown")))
	var geometry_hash := str(road.get("geometry_sha256", "unknown"))
	var wrapped_hash := geometry_hash if geometry_hash.length() <= 32 else "%s\n%s" % [geometry_hash.left(32), geometry_hash.substr(32)]
	UI.label(road_panel, "SHA-256 /\n%s" % wrapped_hash, "MutedLabel")
	var scope: Dictionary = result.get("measurement_scope", {})
	var scope_keys: Array = scope.keys()
	scope_keys.sort()
	for key in scope_keys:
		UI.label(road_panel, "%s / %s" % [str(key).to_upper(), scope[key]], "MutedLabel")

	var conditions: Dictionary = result.get("conditions", {})
	var condition_panel := UI.vbox(UI.panel(col), 4)
	UI.label(condition_panel, "CONDITIONS SNAPSHOT", "HeadingLabel")
	var condition_keys: Array = conditions.keys()
	condition_keys.sort()
	for key in condition_keys:
		UI.stat_row(condition_panel, str(key).replace("_", " ").capitalize(), str(conditions[key]))

	var vehicle: Dictionary = result.get("vehicle_state", {})
	var vehicle_panel := UI.vbox(UI.panel(col), 4)
	UI.label(vehicle_panel, "PHYSICAL VEHICLE SNAPSHOT", "HeadingLabel")
	var vehicle_keys: Array = vehicle.keys()
	vehicle_keys.sort()
	for key in vehicle_keys:
		UI.stat_row(vehicle_panel, str(key).replace("_", " ").capitalize(), str(vehicle[key]))


func test_replay_available(result: Dictionary) -> bool:
	var replay_ref := str(result.get("replay", ""))
	return replay_ref != "" and FileAccess.file_exists(replay_ref)


func add_test_result_footer(result: Dictionary, from_log: bool) -> void:
	if from_log:
		if test_replay_available(result):
			UI.button(footer, "WATCH REPLAY", watch_logged_test.bind(result), "AccentButton")
		else:
			UI.label(footer, "REPLAY FILE UNAVAILABLE", "MutedLabel")
		UI.button(footer, "BACK TO TEST LOG", show_test_log)
	else:
		UI.button(footer, "TEST LOG", show_test_log)
	UI.button(footer, "BACK TO HOME", show_warehouse)


func watch_logged_test(result: Dictionary) -> void:
	if not test_replay_available(result):
		show_test_detail(str(result.get("run_id", "")))
		return
	if result["road_id"] == "LOCAL_STRAIGHT":
		show_local_straight_replay(result)
	elif result["road_id"] == "LOCAL_CURVES":
		show_local_curves_replay(result)
	else:
		viewer = Viewer.new()
		viewer.replay_path = result["replay"]
		viewer.embedded = true
		viewer.status_text = "REFERENCE DRIVER"
		viewer.finished_viewing.connect(show_test_detail.bind(str(result["run_id"])))
		add_child(viewer)


func find_test_run(run_id: String) -> Dictionary:
	for run in state["test_log"]["runs"]:
		if str(run.get("run_id", "")) == run_id:
			return run
	return {}


func test_measurement_summary(result: Dictionary) -> String:
	var measurements: Dictionary = result.get("measurements", {})
	var values := []
	if result.get("road_id", "") == "LOCAL_STRAIGHT":
		if measurements.has("quarter_mile_s"):
			values.append("1/4 %.3f s" % float(measurements["quarter_mile_s"]))
		if measurements.has("zero_60_s"):
			values.append("0-60 %.3f s" % float(measurements["zero_60_s"]))
		if measurements.has("quarter_mile_trap_mph"):
			values.append("TRAP %.1f mph" % float(measurements["quarter_mile_trap_mph"]))
	elif result.get("road_id", "") == "LOCAL_CURVES":
		if measurements.has("total_time_s"):
			values.append("TOTAL %.3f s" % float(measurements["total_time_s"]))
		if measurements.has("peak_speed_mph"):
			values.append("PEAK %.1f mph" % float(measurements["peak_speed_mph"]))
	else:
		var keys: Array = measurements.keys()
		keys.sort()
		for key in keys:
			values.append("%s %s" % [str(key).to_upper().replace("_", " "), str(measurements[key])])
	return " / ".join(values) if not values.is_empty() else "MEASUREMENTS NOT RECORDED"


func test_runs_for_section(section: String) -> Array:
	var runs: Array = state["test_log"]["runs"].duplicate()
	runs.reverse()
	if section == "OTHER":
		return runs.filter(func(run): return str(run.get("road_id", "")) not in ["LOCAL_STRAIGHT", "LOCAL_CURVES"])
	return runs.filter(func(run): return str(run.get("road_id", "")) == section)


func test_run_counts() -> Dictionary:
	return {"LOCAL_STRAIGHT": test_runs_for_section("LOCAL_STRAIGHT").size(),
		"LOCAL_CURVES": test_runs_for_section("LOCAL_CURVES").size(),
		"OTHER": test_runs_for_section("OTHER").size()}


func test_configuration_summary(result: Dictionary) -> String:
	if not result.has("installed") or typeof(result["installed"]) != TYPE_ARRAY:
		return "CONFIGURATION NOT RECORDED"
	var installed: Array = result.get("installed", [])
	if installed.is_empty():
		return "STOCK"
	var definitions := []
	for part in installed:
		definitions.append(str(part.get("definition_id", "unknown")))
	return ", ".join(definitions)


func test_calendar_summary(result: Dictionary) -> String:
	if not result.has("calendar") or typeof(result["calendar"]) != TYPE_DICTIONARY:
		return "DATE NOT RECORDED"
	var calendar: Dictionary = result.get("calendar", {})
	if not calendar.has("week") or not calendar.has("day"):
		return "DATE NOT RECORDED"
	var day := int(calendar.get("day", 0))
	var day_name: String = DAY_NAMES[day] if day >= 0 and day < DAY_NAMES.size() else "DAY"
	return "%s / WEEK %02d / DAY %02d" % [day_name, int(calendar.get("week", 0)), day + 1]


func show_test_log() -> void:
	var col := new_screen()
	UI.spacer(col, false).custom_minimum_size.y = 24
	UI.label(col, "TEST LOG", "TitleLabel", UI.ACCENT)
	UI.label(col, "CONTROLLED RUN HISTORY / RAW OBSERVATIONS", "MutedLabel")
	var counts := test_run_counts()
	var tabs := UI.hbox(col, 8)
	for section in ["LOCAL_STRAIGHT", "LOCAL_CURVES", "OTHER"]:
		if section == "OTHER" and int(counts[section]) == 0:
			continue
		var label := "%s / %d" % [section.replace("_", " "), int(counts[section])]
		var tab := UI.button(tabs, label, select_test_log_section.bind(section),
			"SelectedButton" if selected_test_road == section else "")
		tab.flat = true
		tab.focus_mode = Control.FOCUS_NONE
	var runs := test_runs_for_section(selected_test_road)
	if runs.is_empty():
		var empty_text := "NO LOCAL STRAIGHT RUNS RECORDED." if selected_test_road == "LOCAL_STRAIGHT" else "NO LOCAL CURVES RUNS RECORDED." if selected_test_road == "LOCAL_CURVES" else "NO OTHER ROAD RUNS RECORDED."
		UI.label(col, empty_text, "MutedLabel")
	else:
		for run in runs:
			var panel := UI.vbox(UI.panel(col), 4)
			UI.label(panel, "%s / %s" % [run.get("run_id", "UNKNOWN"), run.get("road_id", "UNKNOWN")], "HeadingLabel")
			UI.label(panel, "%s / %s" % [test_calendar_summary(run), test_configuration_summary(run)], "MutedLabel")
			UI.label(panel, test_measurement_summary(run))
			UI.button(panel, "OPEN RUN", show_test_detail.bind(str(run.get("run_id", ""))))
	UI.button(footer, "BACK TO HOME", show_warehouse, "AccentButton")


func select_test_log_section(section: String) -> void:
	if section in ["LOCAL_STRAIGHT", "LOCAL_CURVES", "OTHER"]:
		selected_test_road = section
		show_test_log()


func show_other_test_results(result: Dictionary, from_log := true) -> void:
	var col := new_screen()
	UI.spacer(col, false).custom_minimum_size.y = 24
	UI.label(col, "TEST RESULTS / OTHER ROAD", "TitleLabel", UI.ACCENT)
	UI.label(col, str(result.get("road_id", "UNKNOWN ROAD")), "BigNumberLabel")
	UI.label(col, "%s / %s" % [str(result.get("run_id", "UNKNOWN RUN")), test_calendar_summary(result)], "MutedLabel")
	var measurements: Dictionary = result.get("measurements", {})
	var measured := UI.vbox(UI.panel(col), 6)
	UI.label(measured, "RECORDED MEASUREMENTS", "HeadingLabel")
	var keys: Array = measurements.keys()
	keys.sort()
	if keys.is_empty():
		UI.label(measured, "MEASUREMENTS NOT RECORDED", "MutedLabel")
	for key in keys:
		UI.stat_row(measured, str(key).replace("_", " ").capitalize(), str(measurements[key]))
	var installed_value = result.get("installed", null)
	var config := UI.vbox(UI.panel(col), 6)
	UI.label(config, "CIVIC CONFIGURATION", "HeadingLabel")
	UI.stat_row(config, "Chassis", str(result.get("chassis_id", "NOT RECORDED")))
	UI.stat_row(config, "Base car", str(result.get("base_car_id", "NOT RECORDED")))
	if typeof(installed_value) == TYPE_ARRAY:
		var installed: Array = installed_value
		UI.stat_row(config, "Installed", "stock" if installed.is_empty() else "%d physical part%s" % [installed.size(), "" if installed.size() == 1 else "s"])
		for part in installed:
			UI.label(config, "%s / %s / %s" % [part.get("slot", ""), part.get("owned_uid", ""), part.get("definition_id", "")], "MutedLabel")
	else:
		UI.stat_row(config, "Installed", "CONFIGURATION NOT RECORDED")
	add_historical_test_details(col, result)
	add_test_result_footer(result, from_log)


func show_test_detail(run_id: String) -> void:
	var result := find_test_run(run_id)
	if result.is_empty():
		show_message("TEST LOG", "Run %s is no longer available." % run_id, "BACK TO TEST LOG", show_test_log)
		return
	if result["road_id"] == "LOCAL_STRAIGHT":
		show_test_results(result, true)
	elif result["road_id"] == "LOCAL_CURVES":
		show_curves_results(result, true)
	else:
		show_other_test_results(result, true)
	reset_screen_scroll.call_deferred()


func reset_screen_scroll() -> void:
	if not is_instance_valid(screen):
		return
	for node in screen.find_children("*", "ScrollContainer", true, false):
		node.scroll_horizontal = 0
		node.scroll_vertical = 0


# ------------------------------------------------------------------ bridge replies

func _on_reply(tag: String, data: Dictionary) -> void:
	if not data.get("ok", false):
		if tag in ["local_straight", "local_curves"]:
			pending_test = {}
		show_message("THE SIM HIT A PROBLEM", str(data.get("error", "unknown error")), "BACK TO HOME", show_warehouse)
		return
	match tag:
		"car_stats":
			car_stats = data
			_go(after_car_stats)
		"parts":
			accept_shop_catalog(data)
			_go(after_catalog)
		"night":
			data["event"] = event_key(next_legacy_race_event())
			state["night"] = data
			save_game()
			track_info = {}            # a new night can be a new road:
			practice = {}              # drop the old road's map and practice runs
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
		"local_straight":
			latest_test_result = complete_test_run(data, pending_test)
			pending_test = {}
			show_local_straight_replay(latest_test_result)
		"local_curves":
			latest_test_result = complete_test_run(data, pending_test)
			pending_test = {}
			show_local_curves_replay(latest_test_result)


# ------------------------------------------------------------------ self-test

func game_test_reply_ok(reply: Array) -> bool:
	if reply[1].get("ok", false):
		return true
	var message := "GAMETEST FAIL %s: %s" % [reply[0], reply[1].get("error", "unknown bridge error")]
	push_error(message)
	print(message)
	get_tree().quit(1)
	return false


func test_log_fail(message: String) -> void:
	var full := "TESTLOGTEST FAIL %s" % message
	push_error(full)
	print(full)
	get_tree().quit(1)


func test_log_test() -> void:
	## Headless save-v8 regression for controlled test history:
	##   godot --headless --path godot -- --testlogtest
	var legacy_v7 := {
		"version": 7, "cash": 1840, "followers": 23, "rep": 23,
		"week": 4, "day": 2, "history": [{"event": "legacy"}], "night": {},
		"civic": {"chassis_id": "CHASSIS_0042", "base_car_id": "eg6_sir_ii_1995",
			"installed": {"rear_sway": "p7"}},
		"inventory": [{"uid": "p7", "part": "rsb_19", "source": "used"}],
		"next_uid": 8, "market": {"seeded": true, "used_listings": [{"listing_id": "KEEP"}]},
	}
	var migrated := migrate(legacy_v7.duplicate(true))
	if int(migrated["version"]) != SAVE_VERSION or migrated["test_log"] != {"next_id": 1, "runs": []}:
		test_log_fail("v7 migration did not preserve the empty test_log")
		return
	for key in ["cash", "followers", "rep", "week", "day", "history", "night", "civic", "inventory", "next_uid", "market"]:
		if migrated[key] != legacy_v7[key]:
			test_log_fail("v7 migration changed %s" % key)
			return

	state = new_state()
	state["inventory"] = [{"uid": "p77", "part": "rsb_19", "source": "retail",
		"acquired_price": 320, "acquired_week": 1, "acquired_day": 0}]
	state["next_uid"] = 78
	var unchanged := {"cash": state["cash"], "followers": state["followers"],
		"rep": state["rep"], "week": state["week"], "day": state["day"],
		"history": state["history"].duplicate(true), "inventory": state["inventory"].duplicate(true)}
	var run_specs := [
		{"road": "LOCAL_STRAIGHT", "command": "local_straight", "installed": false},
		{"road": "LOCAL_STRAIGHT", "command": "local_straight", "installed": true},
		{"road": "LOCAL_CURVES", "command": "local_curves", "installed": true},
		{"road": "LOCAL_CURVES", "command": "local_curves", "installed": false},
	]
	for spec in run_specs:
		state["civic"]["installed"] = {"rear_sway": "p77"} if spec["installed"] else {}
		var prepared := prepare_test_run(spec["road"])
		var out := ProjectSettings.globalize_path(prepared["replay"])
		bridge.request("test_log_run", [spec["command"], "--out", out] + parts_args())
		var reply: Array = await bridge.replied
		if not game_test_reply_ok(reply):
			return
		var completed := complete_test_run(reply[1], prepared)
		if completed.is_empty():
			test_log_fail("could not complete %s" % prepared["run_id"])
			return

	var runs: Array = state["test_log"]["runs"]
	if runs.size() != 4 or int(state["test_log"]["next_id"]) != 5:
		test_log_fail("four runs or next ID were not persisted")
		return
	for i in runs.size():
		var expected_id := "TEST_%06d" % (i + 1)
		var run: Dictionary = runs[i]
		if run["run_id"] != expected_id or run["replay"] != "user://replays/tests/%s.json" % expected_id:
			test_log_fail("unstable ID or replay reference for run %d" % i)
			return
		if run["road"]["road_id"] != run["road_id"] or str(run["road"]["geometry_sha256"]).length() != 64:
			test_log_fail("missing road identity/hash for %s" % expected_id)
			return
		if run["conditions"].is_empty() or run["vehicle_state"].is_empty() or run["measurements"].is_empty() or run["measurement_scope"].is_empty():
			test_log_fail("incomplete physical snapshot for %s" % expected_id)
			return
		for forbidden in ["reward", "cash", "followers", "rep", "xp", "won", "loot"]:
			if run.has(forbidden):
				test_log_fail("controlled test recorded forbidden progression field %s" % forbidden)
				return
	if not runs[0]["installed"].is_empty() or runs[1]["installed"] != [{"slot": "rear_sway", "owned_uid": "p77", "definition_id": "rsb_19"}]:
		test_log_fail("historical UID/definition configuration snapshots changed")
		return
	if runs[0]["measurements"] != runs[1]["measurements"]:
		# The rear sway changes physical state but is not expected to alter the straight metric.
		test_log_fail("identical straight behavior changed from a roll-only component")
		return
	if runs[2]["measurements"] == runs[3]["measurements"]:
		test_log_fail("curves did not preserve the installed physical effect")
		return
	for key in unchanged:
		if state[key] != unchanged[key]:
			test_log_fail("controlled tests changed %s" % key)
			return
	var replay_refs := {}
	for run in runs:
		replay_refs[run["replay"]] = true
	if replay_refs.size() != 4:
		test_log_fail("replay references are not unique")
		return
	var original_replay: String = runs[0]["replay"]
	runs[0]["replay"] = "user://replays/tests/MISSING.json"
	if test_replay_available(runs[0]):
		test_log_fail("missing replay was reported as available")
		return
	show_test_detail(runs[0]["run_id"])
	runs[0]["replay"] = original_replay
	# Compare against the JSON-round-tripped shape; Godot parses JSON numbers as
	# floats even when the in-memory snapshot was constructed with ints.
	var expected_runs: Array = JSON.parse_string(JSON.stringify(runs))
	save_game()
	load_game()
	var loaded_runs: Array = state["test_log"]["runs"]
	if loaded_runs.size() != expected_runs.size() or int(state["test_log"]["next_id"]) != 5:
		test_log_fail("test history changed across save/reload")
		return
	for i in expected_runs.size():
		for key in ["run_id", "road_id", "road", "chassis_id", "base_car_id", "calendar",
			"installed", "conditions", "vehicle_state", "measurement_scope", "measurements", "replay"]:
			if loaded_runs[i][key] != expected_runs[i][key]:
				test_log_fail("%s changed across save/reload for run %d" % [key, i])
				return
	var saved_test_log: Dictionary = state["test_log"].duplicate(true)
	if test_runs_for_section("LOCAL_STRAIGHT").map(func(run): return run["run_id"]) != ["TEST_000002", "TEST_000001"] or test_runs_for_section("LOCAL_CURVES").map(func(run): return run["run_id"]) != ["TEST_000004", "TEST_000003"]:
		test_log_fail("road filters or reverse-chronological ordering failed")
		return
	if test_run_counts() != {"LOCAL_STRAIGHT": 2, "LOCAL_CURVES": 2, "OTHER": 0}:
		test_log_fail("road section counts failed")
		return
	if not test_measurement_summary(loaded_runs[0]).contains("1/4") or not test_measurement_summary(loaded_runs[0]).contains("0-60") or not test_measurement_summary(loaded_runs[0]).contains("TRAP") or not test_measurement_summary(loaded_runs[2]).contains("TOTAL") or not test_measurement_summary(loaded_runs[2]).contains("PEAK"):
		test_log_fail("road-specific measurement emphasis failed")
		return
	selected_test_road = "LOCAL_CURVES"
	show_test_log()
	show_test_detail("TEST_000004")
	if selected_test_road != "LOCAL_CURVES":
		test_log_fail("opening a run lost the selected road section")
		return
	show_test_log()
	state["test_log"]["runs"] = [{"run_id": "TEST_OTHER", "road_id": "LOCAL_DRAG",
		"calendar": {}, "measurements": {}, "replay": "user://missing/other.json"}]
	if test_run_counts() != {"LOCAL_STRAIGHT": 0, "LOCAL_CURVES": 0, "OTHER": 1} or test_measurement_summary(state["test_log"]["runs"][0]) != "MEASUREMENTS NOT RECORDED" or test_calendar_summary(state["test_log"]["runs"][0]) != "DATE NOT RECORDED" or test_configuration_summary(state["test_log"]["runs"][0]) != "CONFIGURATION NOT RECORDED" or test_replay_available(state["test_log"]["runs"][0]):
		test_log_fail("unknown road, missing measurements, or missing replay handling failed")
		return
	var incomplete_straight := test_measurement_summary({"road_id": "LOCAL_STRAIGHT", "measurements": {"quarter_mile_s": 17.4, "zero_60_s": 9.1}})
	if incomplete_straight.contains("TRAP") or incomplete_straight.contains("0.0"):
		test_log_fail("missing straight measurement was fabricated")
		return
	select_test_log_section("LOCAL_STRAIGHT")
	if not test_screen_has_label("NO LOCAL STRAIGHT RUNS RECORDED."):
		test_log_fail("LOCAL STRAIGHT empty state is missing")
		return
	select_test_log_section("LOCAL_CURVES")
	if not test_screen_has_label("NO LOCAL CURVES RUNS RECORDED."):
		test_log_fail("LOCAL CURVES empty state is missing")
		return
	select_test_log_section("OTHER")
	show_test_detail("TEST_OTHER")
	if not test_screen_has_label("LOCAL_DRAG") or not test_screen_has_label("REPLAY FILE UNAVAILABLE") or selected_test_road != "OTHER":
		test_log_fail("unknown road detail is inaccessible or selection was lost")
		return
	state["test_log"] = saved_test_log
	selected_test_road = "LOCAL_STRAIGHT"
	print("TESTLOGTEST runs: TEST_000001..TEST_000004; straight 2; curves 2")
	print("TESTLOGTEST road filters, counts, ordering, empty states, OTHER, details, missing replay")
	print("TESTLOGTEST OK")
	get_tree().quit()


func test_screen_has_label(expected: String) -> bool:
	if not is_instance_valid(screen):
		return false
	for node in screen.find_children("*", "Label", true, false):
		if str(node.text) == expected:
			return true
	return false


func calendar_test_fail(message: String) -> void:
	var full := "CALENDARTEST FAIL %s" % message
	push_error(full)
	print(full)
	get_tree().quit(1)


func work_test_fail(message: String) -> void:
	var full := "WORKTEST FAIL %s" % message
	push_error(full)
	print(full)
	get_tree().quit(1)


func work_test() -> void:
	## Headless save-v10 and physical installation regression.
	var v9 := {"version": 9, "week": 2, "day": 6, "cash": 1912,
		"followers": 12, "rep": 12, "history": [{"old": true}], "night": {},
		"civic": {"chassis_id": "CHASSIS_0001", "base_car_id": "eg6_sir_ii_1995", "installed": {}},
		"inventory": [{"uid": "p7", "part": "rsb_19", "source": "retail"}], "next_uid": 8,
		"market": {"seeded": true, "used_listings": [{"listing_id": "USED_KEEP", "part": "rsb_19", "seller_name": "Local", "note": "Used bar", "price": 200}]},
		"calendar": initial_calendar(2, 6),
		"test_log": {"next_id": 2, "runs": [{"run_id": "TEST_000001", "calendar": {"week": 1, "day": 0}, "replay": "keep.json"}]}}
	state = migrate(v9.duplicate(true))
	if state["version"] != 10 or state["garage_work"] != {"next_work_id": 1, "orders": []}:
		work_test_fail("v9 migration did not create empty garage work")
		return
	for key in v9:
		if key != "version" and state[key] != v9[key]:
			work_test_fail("v9 migration changed %s" % key)
			return
	var protected := {"cash": state["cash"], "followers": state["followers"],
		"rep": state["rep"], "history": state["history"].duplicate(true),
		"inventory": state["inventory"].duplicate(true), "market": state["market"].duplicate(true),
		"test_log": state["test_log"].duplicate(true)}
	protected = JSON.parse_string(JSON.stringify(protected))
	bridge.request("work_catalog", ["shop_catalog"])
	var response: Array = await bridge.replied
	if not game_test_reply_ok(response):
		return
	accept_shop_catalog(response[1])
	bridge.request("work_car_stats", ["car_stats"])
	response = await bridge.replied
	if not game_test_reply_ok(response):
		return
	car_stats = response[1]
	var start_date := [state["week"], state["day"]]
	show_warehouse()
	show_car()
	show_shop()
	show_test_log()
	if [state["week"], state["day"]] != start_date:
		work_test_fail("browsing advanced time")
		return
	if not queue_part_work("rear_sway", "p7") or queue_part_work("rear_sway", "p7") or queue_part_work("shifter", "p7"):
		work_test_fail("install or conflicting work validation")
		return
	var first: Dictionary = state["garage_work"]["orders"][0]
	if first["work_id"] != "WORK_000001" or first["due_week"] != 3 or first["due_day"] != 0 or not state["civic"]["installed"].is_empty() or parts_args() != []:
		work_test_fail("install changed physical state before completion or wrong rollover")
		return
	show_warehouse()
	if hub_content.current_civic_state().get("work_in_progress", []).size() != 1:
		work_test_fail("HOME did not receive active work state")
		return
	save_game()
	load_game()
	if active_work_orders().size() != 1 or state["garage_work"]["orders"][0]["work_id"] != "WORK_000001":
		work_test_fail("mid-job reload lost or duplicated work")
		return
	first = state["garage_work"]["orders"][0]
	advance_days(3, "work regression multi-day")
	if state["week"] != 3 or state["day"] != 2 or state["civic"]["installed"] != {"rear_sway": "p7"} or parts_args() != ["--parts", "rsb_19"]:
		work_test_fail("multi-day completion did not install the owned UID")
		return
	if first["status"] != "completed" or first["finished_week"] != 3 or first["finished_day"] != 0:
		work_test_fail("completion status/date is wrong")
		return
	bridge.request("work_stock_stats", ["car_stats"])
	response = await bridge.replied
	if not game_test_reply_ok(response):
		return
	var stock_roll := float(response[1]["skidpad_g"])
	bridge.request("work_installed_stats", ["car_stats"] + parts_args())
	response = await bridge.replied
	if not game_test_reply_ok(response):
		return
	if float(response[1]["skidpad_g"]) <= stock_roll:
		work_test_fail("installed UID did not reach EG6 physics")
		return
	if not queue_part_work("rear_sway", "") or queue_part_work("rear_sway", ""):
		work_test_fail("remove or conflicting remove validation")
		return
	if state["civic"]["installed"] != {"rear_sway": "p7"}:
		work_test_fail("removal happened before completion")
		return
	advance_days(1, "work regression remove")
	advance_days(2, "work regression no duplicate completion")
	if not state["civic"]["installed"].is_empty() or parts_args() != [] or state["inventory"] != protected["inventory"] or active_work_orders().size() != 0:
		work_test_fail("removal lost ownership or completion repeated")
		return
	if state["garage_work"]["orders"].size() != 2 or state["garage_work"]["next_work_id"] != 3:
		work_test_fail("work IDs or order history changed")
		return
	for key in protected:
		if JSON.parse_string(JSON.stringify(state[key])) != protected[key]:
			work_test_fail("work changed protected state %s" % key)
			return
	save_game()
	load_game()
	if state["garage_work"]["orders"].size() != 2 or state["garage_work"]["orders"][0]["status"] != "completed" or state["garage_work"]["orders"][1]["status"] != "completed":
		work_test_fail("completed orders changed on reload")
		return
	state["inventory"].append({"uid": "p8", "part": "shifter_short", "source": "test"})
	if not queue_part_work("rear_sway", "p7") or not queue_part_work("shifter", "p8") or active_work_orders().size() != 2:
		work_test_fail("non-conflicting same-day jobs were not allowed")
		return
	advance_days(1, "work regression concurrent jobs")
	if state["civic"]["installed"] != {"rear_sway": "p7", "shifter": "p8"} or active_work_orders().size() != 0:
		work_test_fail("same-day jobs did not both complete")
		return
	print("WORKTEST v9 -> v10; WORK_000001 install, WORK_000002 remove; UID p7 preserved")
	print("WORKTEST before/after EG6 physics; multi-day rollover; parallel jobs; no duplicate completion")
	print("WORKTEST OK")
	get_tree().quit()


func calendar_test() -> void:
	## Headless save-v9 and day-level calendar regression:
	##   godot --headless --path godot -- --calendartest
	var historical_test := {
		"run_id": "TEST_000044", "road_id": "LOCAL_STRAIGHT",
		"calendar": {"week": 2, "day": 6, "label": "SUN, WEEK 2"},
		"replay": "user://replays/tests/TEST_000044.json",
	}
	var legacy_v8 := {
		"version": 8, "cash": 1875, "followers": 19, "rep": 19,
		"week": 2, "day": 6, "history": [{"legacy": true}], "night": {"saved": true},
		"civic": {"chassis_id": "CHASSIS_0001", "base_car_id": "eg6_sir_ii_1995",
			"installed": {"rear_sway": "p9"}},
		"inventory": [{"uid": "p9", "part": "rsb_19", "source": "used"}],
		"next_uid": 10,
		"market": {"seeded": true, "used_listings": [{"listing_id": "USED_KEEP"}]},
		"test_log": {"next_id": 45, "runs": [historical_test.duplicate(true)]},
	}
	var migrated := migrate(legacy_v8.duplicate(true))
	if int(migrated["version"]) != SAVE_VERSION or migrated["calendar"].has("week") or migrated["calendar"].has("day"):
		calendar_test_fail("v8 migration did not create a calendar with top-level time authority")
		return
	for key in ["cash", "followers", "rep", "week", "day", "history", "night", "civic",
		"inventory", "next_uid", "market", "test_log"]:
		if migrated[key] != legacy_v8[key]:
			calendar_test_fail("v8 migration changed %s" % key)
			return
	var events: Array = migrated["calendar"]["events"]
	if events.size() != 2 or events.map(func(event): return event["event_id"]) != ["EVENT_000001", "EVENT_000002"]:
		calendar_test_fail("fixture event IDs are missing or unstable")
		return
	var migrated_again := migrate(migrated.duplicate(true))
	if migrated_again["calendar"]["events"].size() != 2:
		calendar_test_fail("reload migration duplicated calendar events")
		return

	state = migrated
	var protected := {
		"cash": state["cash"], "followers": state["followers"], "rep": state["rep"],
		"history": state["history"].duplicate(true), "inventory": state["inventory"].duplicate(true),
		"market": state["market"].duplicate(true), "civic": state["civic"].duplicate(true),
		"test_log": state["test_log"].duplicate(true),
	}
	var starting_date := [state["week"], state["day"]]
	if advance_days(-1, "invalid negative") or advance_days(1.5, "invalid fractional") or advance_days(1, ""):
		calendar_test_fail("invalid day advancement was accepted")
		return
	if [state["week"], state["day"]] != starting_date:
		calendar_test_fail("invalid advancement changed the canonical date")
		return
	show_warehouse()
	show_calendar()
	show_test_log()
	if [state["week"], state["day"]] != starting_date:
		calendar_test_fail("HOME, CALENDAR, or TEST LOG browsing advanced time")
		return

	if events[0]["status"] != "upcoming" or events[1]["status"] != "upcoming":
		calendar_test_fail("new event status is not upcoming")
		return
	if not advance_days(1, "calendar regression rollover"):
		calendar_test_fail("valid advancement was rejected")
		return
	if int(state["week"]) != 3 or int(state["day"]) != 0 or state["calendar"]["events"][0]["status"] != "available":
		calendar_test_fail("Sunday-to-Monday rollover or available status failed")
		return
	advance_days(1, "calendar regression pass first event")
	if state["calendar"]["events"][0]["status"] != "missed" or state["calendar"]["events"][1]["status"] != "upcoming":
		calendar_test_fail("passed event did not become missed deterministically")
		return
	advance_days(1, "calendar regression reach second event")
	if state["calendar"]["events"][1]["status"] != "available":
		calendar_test_fail("second event did not become available on its date")
		return
	advance_days(1, "calendar regression pass second event")
	if state["calendar"]["events"][1]["status"] != "missed":
		calendar_test_fail("second event did not become missed after its date")
		return
	for key in protected:
		if state[key] != protected[key]:
			calendar_test_fail("day advancement changed protected state %s" % key)
			return
	if state.has("xp") or state.has("loot"):
		calendar_test_fail("calendar introduced progression or loot state")
		return
	var expected_calendar := normalize_calendar_data(
		JSON.parse_string(JSON.stringify(state["calendar"])), int(state["week"]), int(state["day"]))
	save_game()
	load_game()
	if state["calendar"] != expected_calendar or int(state["week"]) != 3 or int(state["day"]) != 3:
		calendar_test_fail("calendar IDs, statuses, or date changed across reload")
		return
	var loaded_test: Dictionary = state["test_log"]["runs"][0]
	var loaded_stamp: Dictionary = loaded_test["calendar"]
	if int(loaded_stamp["week"]) != 2 or int(loaded_stamp["day"]) != 6 or loaded_stamp["label"] != "SUN, WEEK 2" or loaded_test["replay"] != historical_test["replay"]:
		calendar_test_fail("historical TEST LOG timestamp or replay reference changed")
		return
	print("CALENDARTEST events: EVENT_000001, EVENT_000002; upcoming -> available -> missed")
	print("CALENDARTEST rollover: SUN WEEK 02 -> MON WEEK 03")
	print("CALENDARTEST OK")
	get_tree().quit()


func game_test() -> void:
	## Headless end-to-end check: one full race night, printed. Run with
	##   godot --headless --path godot -- --gametest
	state = new_state()
	if state["civic"]["chassis_id"] != "CHASSIS_0001" or state["civic"]["base_car_id"] != "eg6_sir_ii_1995":
		push_error("GAMETEST FAIL new Civic identity")
		get_tree().quit(1)
		return
	print("GAMETEST bridge: ", bridge.ready_to_use() if bridge.ready_to_use() != "" else "ok")
	print("GAMETEST migrate v1: ", migrate({"version": 1, "cash": 300, "rep": 5, "history": [], "night": {"x": 1}}))
	var v5 := migrate({"version": 5, "followers": 17})
	if int(v5["followers"]) != 17 or int(v5["rep"]) != 17 or v5["civic"]["chassis_id"] != "CHASSIS_0001" or v5["civic"]["base_car_id"] != "eg6_sir_ii_1995":
		push_error("GAMETEST FAIL v5 Civic/rep recovery: %s" % v5)
		get_tree().quit(1)
		return
	var assigned := migrate({"version": 5, "rep": 3, "civic": {"chassis_id": "CHASSIS_0042", "base_car_id": "existing_car"}})
	if assigned["civic"]["chassis_id"] != "CHASSIS_0042" or assigned["civic"]["base_car_id"] != "existing_car":
		push_error("GAMETEST FAIL existing Civic identity preservation")
		get_tree().quit(1)
		return
	var v6 := migrate({"version": 6, "civic": {"chassis_id": "CHASSIS_0043"}})
	if v6["civic"]["chassis_id"] != "CHASSIS_0043" or v6["civic"]["base_car_id"] != "eg6_sir_ii_1995":
		push_error("GAMETEST FAIL v6 base car repair")
		get_tree().quit(1)
		return
	print("GAMETEST migrate v5: followers %d, rep %d" % [v5["followers"], v5["rep"]])
	var ev := next_legacy_race_event()
	print("GAMETEST next event: %s, %s" % [when(ev["week"], ev["day"]), ev["title"]])
	bridge.request("car_stats", ["car_stats"])
	var r: Array = await bridge.replied
	if not game_test_reply_ok(r):
		return
	print("GAMETEST car: %s, %d hp, dyno points %d" % [r[1]["name"], r[1]["hp"], r[1]["dyno"].size()])
	var stock_skidpad_g := float(r[1]["skidpad_g"])
	bridge.request("rival", ["rival", "--rival", RIVAL_FILE, "--seed", "42"])
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	state["night"] = r[1]
	print("GAMETEST rival: %s (%s), posted %.3f s" % [r[1]["name"], r[1]["car"], r[1]["posted_time"]])
	bridge.request("practice", ["practice", "--track", r[1]["track"]])
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	practice = r[1]
	print("GAMETEST practice runs: %d per push level" % practice["runs"])
	choice = {"push": "hard", "wager": 100}
	var out := ProjectSettings.globalize_path("user://replays/race.json")
	bridge.request("race", ["race", "--track", state["night"]["track"], "--push", "hard", "--seed", "9", "--out", out])
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	var result := apply_result(r[1])
	if int(state["followers"]) != int(state["rep"]):
		push_error("GAMETEST FAIL race followers/rep synchronization")
		get_tree().quit(1)
		return
	print("GAMETEST race: %.3f s vs %.3f s -> %s, cash %d, practice %d/%d" % [
		result["time"], result["posted"], "WIN" if result["won"] else "LOSS", state["cash"],
		result["practice_beat"], result["practice_runs"]])
	print("GAMETEST calendar after race: %s" % when(state["week"], state["day"]))
	bridge.request("parts", ["shop_catalog"])
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	accept_shop_catalog(r[1])
	if catalog.has("sources") or catalog["parts"].any(func(p): return p.has("rarity")):
		push_error("GAMETEST FAIL active shop exposes gacha data")
		get_tree().quit(1)
		return
	print("GAMETEST EG6 catalog: %d compatible parts, %d retail, %d used" % [
		catalog["parts"].size(), catalog["retail_ids"].size(), state["market"]["used_listings"].size()])
	var local_out := ProjectSettings.globalize_path("user://replays/local_straight_gametest.json")
	bridge.request("local_straight_stock", ["local_straight", "--out", local_out])
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	var stock_local: Dictionary = r[1]
	if stock_local["road_id"] != "LOCAL_STRAIGHT" or stock_local["vehicle_state"]["car_id"] != "eg6_sir_ii_1995":
		push_error("GAMETEST FAIL LOCAL STRAIGHT road or game-car identity")
		get_tree().quit(1)
		return
	var curves_out := ProjectSettings.globalize_path("user://replays/local_curves_gametest.json")
	bridge.request("local_curves_stock", ["local_curves", "--out", curves_out])
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	var stock_curves: Dictionary = r[1]
	if stock_curves["road_id"] != "LOCAL_CURVES" or stock_curves["vehicle_state"]["car_id"] != "eg6_sir_ii_1995":
		push_error("GAMETEST FAIL LOCAL CURVES road or game-car identity")
		get_tree().quit(1)
		return
	state["cash"] = START_CASH
	state["rep"] = 0
	shop_message = ""
	var market_date := [state["week"], state["day"]]
	buy_retail("rsb_19")
	if state["cash"] != START_CASH - 320 or state["inventory"].size() != 1 or not state["civic"]["installed"].is_empty():
		push_error("GAMETEST FAIL retail cash, instance, or spare state")
		get_tree().quit(1)
		return
	var retail_uid: String = state["inventory"][0]["uid"]
	if state["inventory"][0]["part"] != "rsb_19" or state["inventory"][0].has("quality") or state.has("pity"):
		push_error("GAMETEST FAIL retail definition or gacha fields")
		get_tree().quit(1)
		return
	var listings_before: int = state["market"]["used_listings"].size()
	buy_used("USED_0003")
	if state["cash"] != START_CASH - 320 - 240 or state["inventory"].size() != 2 or state["market"]["used_listings"].size() != listings_before - 1:
		push_error("GAMETEST FAIL used purchase transaction")
		get_tree().quit(1)
		return
	var used_uid: String = state["inventory"][1]["uid"]
	if used_uid == retail_uid or state["inventory"][1]["part"] != "rsb_19" or state["inventory"][1]["listing_id"] != "USED_0003":
		push_error("GAMETEST FAIL used instance identity/provenance")
		get_tree().quit(1)
		return
	var cash_after_used := int(state["cash"])
	buy_used("USED_0003")
	accept_shop_catalog(catalog)
	if state["cash"] != cash_after_used or state["inventory"].size() != 2 or state["market"]["used_listings"].size() != listings_before - 1:
		push_error("GAMETEST FAIL purchased used listing reappeared")
		get_tree().quit(1)
		return
	install_part("rear_sway", retail_uid, false)
	if not state["civic"]["installed"].is_empty() or parts_args() != [] or active_work_orders().size() != 1:
		push_error("GAMETEST FAIL installation did not remain pending")
		get_tree().quit(1)
		return
	if [state["week"], state["day"]] != market_date:
		push_error("GAMETEST FAIL buying or queueing work advanced calendar time")
		get_tree().quit(1)
		return
	advance_days(1, "gametest complete installation")
	if state["civic"]["installed"].get("rear_sway", "") != retail_uid or parts_args() != ["--parts", "rsb_19"]:
		push_error("GAMETEST FAIL owned UID to installed definition at completion")
		get_tree().quit(1)
		return
	var before_test := {
		"cash": state["cash"], "followers": state["followers"],
		"history": state["history"].duplicate(true), "inventory": state["inventory"].duplicate(true),
		"week": state["week"], "day": state["day"],
	}
	bridge.request("local_straight_a", ["local_straight", "--out", local_out] + parts_args())
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	var local_a: Dictionary = r[1]
	bridge.request("local_straight_b", ["local_straight", "--out", local_out] + parts_args())
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	var local_b: Dictionary = r[1]
	var local_snapshot := local_test_snapshot(local_a)
	if local_a["measurements"] != local_b["measurements"] or local_a["vehicle_state"] != local_b["vehicle_state"]:
		push_error("GAMETEST FAIL LOCAL STRAIGHT repeatability")
		get_tree().quit(1)
		return
	if float(local_a["vehicle_state"]["front_roll_stiffness_fraction"]) == float(stock_local["vehicle_state"]["front_roll_stiffness_fraction"]):
		push_error("GAMETEST FAIL LOCAL STRAIGHT did not receive physical part state")
		get_tree().quit(1)
		return
	if local_snapshot["chassis_id"] != "CHASSIS_0001" or local_snapshot["base_car_id"] != "eg6_sir_ii_1995" or local_snapshot["installed"] != [{"slot": "rear_sway", "owned_uid": retail_uid, "definition_id": "rsb_19"}]:
		push_error("GAMETEST FAIL LOCAL STRAIGHT ownership snapshot: %s" % local_snapshot)
		get_tree().quit(1)
		return
	bridge.request("local_curves_a", ["local_curves", "--out", curves_out] + parts_args())
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	var curves_a: Dictionary = r[1]
	bridge.request("local_curves_b", ["local_curves", "--out", curves_out] + parts_args())
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	var curves_b: Dictionary = r[1]
	var curves_snapshot := local_test_snapshot(curves_a)
	if curves_a["measurements"] != curves_b["measurements"] or curves_a["vehicle_state"] != curves_b["vehicle_state"]:
		push_error("GAMETEST FAIL LOCAL CURVES repeatability")
		get_tree().quit(1)
		return
	if float(stock_curves["vehicle_state"]["front_roll_stiffness_fraction"]) != 0.60 or float(curves_a["vehicle_state"]["front_roll_stiffness_fraction"]) != 0.48:
		push_error("GAMETEST FAIL LOCAL CURVES rear sway physical state")
		get_tree().quit(1)
		return
	if curves_snapshot["chassis_id"] != "CHASSIS_0001" or curves_snapshot["base_car_id"] != "eg6_sir_ii_1995" or curves_snapshot["installed"] != [{"slot": "rear_sway", "owned_uid": retail_uid, "definition_id": "rsb_19"}]:
		push_error("GAMETEST FAIL LOCAL CURVES ownership snapshot: %s" % curves_snapshot)
		get_tree().quit(1)
		return
	if state["cash"] != before_test["cash"] or state["followers"] != before_test["followers"] or state["history"] != before_test["history"] or state["inventory"] != before_test["inventory"] or state["week"] != before_test["week"] or state["day"] != before_test["day"]:
		push_error("GAMETEST FAIL local testing changed rewards, ownership, record, or calendar")
		get_tree().quit(1)
		return
	print("GAMETEST LOCAL STRAIGHT: 0-60 %.3f s, quarter %.3f s @ %.1f mph, 60-0 %.1f ft" % [
		local_a["measurements"]["zero_60_s"], local_a["measurements"]["quarter_mile_s"],
		local_a["measurements"]["quarter_mile_trap_mph"], local_a["measurements"]["sixty_zero_ft"]])
	print("GAMETEST LOCAL CURVES: stock %.3f s, rsb_19 %.3f s, roll %.2f -> %.2f" % [
		stock_curves["measurements"]["total_time_s"], curves_a["measurements"]["total_time_s"],
		stock_curves["vehicle_state"]["front_roll_stiffness_fraction"],
		curves_a["vehicle_state"]["front_roll_stiffness_fraction"]])
	bridge.request("car_stats", ["car_stats"] + parts_args())
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	var retail_stats: Dictionary = r[1]
	if float(retail_stats["skidpad_g"]) <= stock_skidpad_g:
		push_error("GAMETEST FAIL installed UID did not change EG6 physical behavior")
		get_tree().quit(1)
		return
	car_stats = retail_stats
	show_warehouse()
	var browse_date := [state["week"], state["day"]]
	var home_civic: Dictionary = hub_content.current_civic_state()
	var expected_home_civic: Dictionary = state["civic"].duplicate(true)
	expected_home_civic["work_in_progress"] = []
	if not shell.is_home_mode() or shell.navigation_labels() != ["CAR", "CALENDAR", "HOME", "TEAM", "SHOP"] or not hub_content.has_node("%LocalStraightButton") or not hub_content.has_node("%LocalCurvesButton") or not hub_content.has_node("%TestLogButton") or home_civic != expected_home_civic or hub_content.current_vehicle_visual_state() != expected_home_civic:
		push_error("GAMETEST FAIL HOME Civic state or navigation")
		get_tree().quit(1)
		return
	_go("car")
	if shell == null or shell.is_home_mode():
		push_error("GAMETEST FAIL CAR inherited HOME overlay mode")
		get_tree().quit(1)
		return
	_go("home")
	if hub_content.current_civic_state() != home_civic:
		push_error("GAMETEST FAIL HOME did not reapply Civic state after CAR")
		get_tree().quit(1)
		return
	_go("shop")
	if shell == null or shell.is_home_mode():
		push_error("GAMETEST FAIL SHOP inherited HOME overlay mode")
		get_tree().quit(1)
		return
	_go("home")
	if hub_content.current_civic_state() != home_civic:
		push_error("GAMETEST FAIL HOME did not reapply Civic state after SHOP")
		get_tree().quit(1)
		return
	_go("calendar")
	if shell == null or shell.is_home_mode():
		push_error("GAMETEST FAIL CALENDAR inherited HOME overlay mode")
		get_tree().quit(1)
		return
	show_test_log()
	show_warehouse()
	if [state["week"], state["day"]] != browse_date:
		push_error("GAMETEST FAIL HOME, CAR, SHOP, CALENDAR, or TEST LOG browsing advanced time")
		get_tree().quit(1)
		return
	_go("team")
	if screen == null or shell != null:
		push_error("GAMETEST FAIL TEAM placeholder navigation")
		get_tree().quit(1)
		return
	show_warehouse()
	print("GAMETEST HOME Civic: %s / %s / %s" % [
		home_civic["chassis_id"], home_civic["base_car_id"], home_civic["installed"]])
	install_part("rear_sway", "", false)
	advance_days(1, "gametest remove retail bar")
	install_part("rear_sway", used_uid, false)
	advance_days(1, "gametest install used bar")
	if state["inventory"].size() != 2 or parts_args() != ["--parts", "rsb_19"]:
		push_error("GAMETEST FAIL replacement duplicated/destroyed an item")
		get_tree().quit(1)
		return
	bridge.request("car_stats", ["car_stats"] + parts_args())
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	if r[1]["skidpad_g"] != retail_stats["skidpad_g"] or r[1]["zero_60_s"] != retail_stats["zero_60_s"]:
		push_error("GAMETEST FAIL source/history altered fixed-spec physics")
		get_tree().quit(1)
		return
	install_part("rear_sway", "", false)
	advance_days(1, "gametest remove used bar")
	if state["inventory"].size() != 2 or not state["civic"]["installed"].is_empty():
		push_error("GAMETEST FAIL uninstall destroyed an owned item")
		get_tree().quit(1)
		return
	install_part("rear_sway", used_uid, false)
	advance_days(1, "gametest reinstall used bar")
	print("GAMETEST physical parts: retail %s, used %s, installed %s, cash %d" % [
		retail_uid, used_uid, state["civic"]["installed"], state["cash"]])
	var old_save := migrate({"version": 6, "cash": 400, "rep": 0, "week": 2, "day": 1,
		"inventory": [{"uid": "p44", "part": "rsb_19", "quality": 0.99, "revealed": false,
			"source": "crate"}, {"uid": "p45", "part": "fd_44", "quality": 0.2}],
		"installed": {"rear_sway": "p44", "final_drive": "missing"}, "next_uid": 2})
	if old_save["inventory"].size() != 2 or old_save["inventory"][0].has("quality") or old_save["next_uid"] != 46:
		push_error("GAMETEST FAIL legacy inventory normalization")
		get_tree().quit(1)
		return
	var live_state := state
	state = old_save
	accept_shop_catalog(catalog)
	if state["inventory"].size() != 1 or state["inventory"][0]["uid"] != "p44" or state["civic"]["installed"] != {"rear_sway": "p44"} or parts_args() != ["--parts", "rsb_19"]:
		push_error("GAMETEST FAIL incompatible/dangling legacy installation cleanup")
		get_tree().quit(1)
		return
	state = live_state
	print("GAMETEST migrate v3: %s" % [migrate({"version": 3, "cash": 1, "rep": 0, "week": 1, "day": 0,
		"history": [], "night": {}, "owned_parts": ["rsb_19"], "installed": {"rear_sway": "rsb_19"}})])
	bridge.request("night", ["street", "--week", "3", "--seed", "8"])
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	print("GAMETEST open road week 3: %s in a %s on %s, posted %.2f" % [r[1]["name"], r[1]["car"], r[1]["style"], r[1]["posted_time"]])
	print("GAMETEST migrate v2: %s" % [migrate({"version": 2, "cash": 1, "rep": 0, "week": 1, "day": 0, "history": [], "night": {}}).keys()])
	state["rep"] = 10
	skip_night()
	print("GAMETEST skip with 10 rep: rep %d, %s (blocked)" % [state["rep"], when(state["week"], state["day"])])
	state["rep"] = 60
	skip_night()
	if int(state["followers"]) != int(state["rep"]):
		push_error("GAMETEST FAIL skip followers/rep synchronization")
		get_tree().quit(1)
		return
	print("GAMETEST skip with 60 rep: rep %d, %s" % [state["rep"], when(state["week"], state["day"])])
	save_game()
	load_game()
	if state["civic"]["chassis_id"] != "CHASSIS_0001" or state["civic"]["base_car_id"] != "eg6_sir_ii_1995" or state["civic"]["installed"].get("rear_sway", "") != used_uid or state["inventory"].size() != 2 or state["inventory"][0]["uid"] != retail_uid or state["inventory"][1]["uid"] != used_uid or state["market"]["used_listings"].size() != listings_before - 1 or state["market"]["used_listings"].any(func(listing): return listing["listing_id"] == "USED_0003"):
		push_error("GAMETEST FAIL Civic parts/listings lost on save/reload")
		get_tree().quit(1)
		return
	print("GAMETEST Civic identity: %s / %s (new, migrated, reloaded)" % [state["civic"]["chassis_id"], state["civic"]["base_car_id"]])
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
	var prepared_straight := prepare_test_run("LOCAL_STRAIGHT")
	var local_out := ProjectSettings.globalize_path(prepared_straight["replay"])
	bridge.request("local_straight", ["local_straight", "--out", local_out])
	var local_data: Dictionary = (await bridge.replied)[1]
	var local_result := complete_test_run(local_data, prepared_straight)
	show_local_straight_replay(local_result)
	viewer.t = viewer.lap_time
	await snap(folder, "1a_local_straight_finish")
	show_test_results(local_result)
	await snap(folder, "1b_local_straight_results")
	show_warehouse()
	var prepared_curves := prepare_test_run("LOCAL_CURVES")
	var curves_out := ProjectSettings.globalize_path(prepared_curves["replay"])
	bridge.request("local_curves", ["local_curves", "--out", curves_out])
	var curves_data: Dictionary = (await bridge.replied)[1]
	var curves_result := complete_test_run(curves_data, prepared_curves)
	show_local_curves_replay(curves_result)
	viewer.t = viewer.lap_time
	await snap(folder, "1c_local_curves_finish")
	show_curves_results(curves_result)
	await snap(folder, "1d_local_curves_results")
	show_test_log()
	await snap(folder, "1e_test_log")
	show_test_detail(local_result["run_id"])
	await snap(folder, "1f_test_log_straight_detail")
	show_test_detail(curves_result["run_id"])
	await snap(folder, "1g_test_log_curves_detail")
	show_warehouse()
	bridge.request("parts", ["shop_catalog"])
	accept_shop_catalog((await bridge.replied)[1])
	var b := add_instance("rsb_19", "retail", 320)
	add_instance("shifter_short", "retail", 300)
	state["civic"]["installed"] = {"rear_sway": b["uid"]}
	shop_message = "Bought Rear sway bar 19 mm."
	show_shop()
	await snap(folder, "1a_shop")
	bridge.request("car_stats", ["car_stats"] + parts_args())
	car_stats = (await bridge.replied)[1]
	show_car()
	await snap(folder, "1b_car")
	hub_content.get_node("%Scroll").scroll_vertical = 900
	await snap(folder, "1b_car_parts")
	state["cash"] = START_CASH
	state["rep"] = 0
	state["inventory"] = []
	state["civic"]["installed"] = {}
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
