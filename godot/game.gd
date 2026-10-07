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
	"home": "GARAGE 1 // OXNARD, CA",
	"car": "THE CIVIC // CHASSIS_CONFIG",
	"calendar": "THE CALENDAR // TIMELINE",
	"team": "TEAM // CONTACTS",
	"shop": "SHOP // PARTS & CLASSIFIEDS",
}

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 7
const START_CASH := 2500
const MIN_BUY_IN := 100
const WAGER_STEP := 10
const REP_WIN := 10
const SKIP_REP_COST := 5 * REP_WIN   # chicken-out fee: five wins' worth of rep
const RIVAL_FILE := "data/rivals/zed_280z.json"
const PUSH_ORDER := ["safe", "normal", "hard", "flat_out"]

# Calendar: a week is 7 days; race nights fall on these days (0 = Monday)
const DAY_NAMES := ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
const RACE_DAYS := [4, 5]        # Friday and Saturday nights

var state := {}            # saved: cash, followers, week, day, history, night
var car_stats := {}        # bridge replies, cached for the session
var track_info := {}
var practice := {}
var catalog := {}          # bridge "parts" reply (slots + parts with exact effects)
var shop_message := ""
var bridge: Node
var screen: Control        # current UI screen (the shell while in the hub)
var shell: Control         # persistent hub shell (top rail, ribbon, bottom nav)
var hub_content: Control   # the hub screen currently inside the shell
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
	show_warehouse()


func new_state() -> Dictionary:
	return {"version": SAVE_VERSION, "cash": START_CASH, "followers": 0, "rep": 0, "week": 1, "day": 0,
		"civic": {"chassis_id": "CHASSIS_0001", "base_car_id": "eg6_sir_ii_1995", "installed": {}},
		"history": [], "night": {},
		"inventory": [], "next_uid": 1,
		"market": {"seeded": false, "used_listings": []}}


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

## Events in a given week: [{"day", "type", "title"}]. Friday: the rival on
## his home road. Saturday: this week's generated open road vs a street racer.
const OPEN_STYLES := ["technical", "balanced", "flowing"]


func events_for_week(week: int) -> Array:
	return [
		{"day": 4, "type": "rival", "title": "Zed (280Z) on his home road"},
		{"day": 5, "type": "open", "title": "Open road (%s), street racer" % OPEN_STYLES[(week - 1) % 3]},
	]


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
	shell.set_stats(int(state["cash"]), int(state["followers"]), MIN_BUY_IN)
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
	var ev := next_event()
	var record := wins_losses()
	var info := common_info()
	info["event_title"] = "%s: %s" % [when(ev["week"], ev["day"]),
		"RIVAL NIGHT" if ev["type"] == "rival" else "OPEN ROAD"]
	info["event_detail"] = "%s. Minimum buy-in %s. Today is %s." % [
		ev["title"], UI.money(MIN_BUY_IN), when(state["week"], state["day"]).to_lower()]
	info["wins"] = record.x
	info["losses"] = record.y
	info["min_buy_in_text"] = UI.money(MIN_BUY_IN)
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
		{"slots": catalog["slots"], "options": options, "installed": state["civic"]["installed"]})


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


## Swap what's in a slot ("" = back to stock). The car changed, so its stats
## and practice runs are stale.
func install_part(slot: String, uid: String, refresh := true) -> void:
	if uid == "":
		state["civic"]["installed"].erase(slot)
	else:
		var inst := instance(uid)
		if inst.is_empty() or part_by_id(inst["part"]).get("slot", "") != slot:
			return
		if uid in state["civic"]["installed"].values() and state["civic"]["installed"].get(slot, "") != uid:
			return
		state["civic"]["installed"][slot] = uid
	car_stats = {}
	practice = {}
	save_game()
	if refresh:
		show_car()


func show_calendar() -> void:
	var info := common_info()
	var week := int(state["week"])
	info["week"] = week
	info["day"] = int(state["day"])
	var week_events := {}
	for e in events_for_week(week):
		week_events[int(e["day"])] = "RIVAL" if e["type"] == "rival" else "OPEN"
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
	open_hub(CalendarScene, "calendar").setup(info)


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
	var ev := next_event()
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
	var ev := next_event()
	state["history"].append({"when": when(ev["week"], ev["day"]), "rival": state["night"].get("name", "Zed"),
		"won": false, "skipped": true, "cash_change": 0, "rep_change": -SKIP_REP_COST})
	advance_past(ev)
	state["night"] = {}
	save_game()
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
		"parts": parts_args()}
	state["cash"] = int(state["cash"]) + int(result["cash_change"])
	state["rep"] = int(state["rep"]) + int(result["rep_change"])
	state["followers"] = int(state["rep"])
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
	UI.button(footer, "BACK TO THE WAREHOUSE", show_warehouse, "AccentButton")


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
			accept_shop_catalog(data)
			_go(after_catalog)
		"night":
			data["event"] = event_key(next_event())
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


# ------------------------------------------------------------------ self-test

func game_test_reply_ok(reply: Array) -> bool:
	if reply[1].get("ok", false):
		return true
	var message := "GAMETEST FAIL %s: %s" % [reply[0], reply[1].get("error", "unknown bridge error")]
	push_error(message)
	print(message)
	get_tree().quit(1)
	return false


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
	var ev := next_event()
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
	state["cash"] = START_CASH
	state["rep"] = 0
	shop_message = ""
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
	if state["civic"]["installed"].get("rear_sway", "") != retail_uid or parts_args() != ["--parts", "rsb_19"]:
		push_error("GAMETEST FAIL owned UID to installed definition")
		get_tree().quit(1)
		return
	bridge.request("car_stats", ["car_stats"] + parts_args())
	r = await bridge.replied
	if not game_test_reply_ok(r):
		return
	var retail_stats: Dictionary = r[1]
	if float(retail_stats["skidpad_g"]) <= stock_skidpad_g:
		push_error("GAMETEST FAIL installed UID did not change EG6 physical behavior")
		get_tree().quit(1)
		return
	install_part("rear_sway", used_uid, false)
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
	if state["inventory"].size() != 2 or not state["civic"]["installed"].is_empty():
		push_error("GAMETEST FAIL uninstall destroyed an owned item")
		get_tree().quit(1)
		return
	install_part("rear_sway", used_uid, false)
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
