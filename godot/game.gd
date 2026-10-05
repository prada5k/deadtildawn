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
## Races are head-to-head: Faba and the night's opponent both run the road in
## the sim, and the replay shows the opponent as a ghost car.
##
## Rules that protect the game from save-scumming:
##   - a race night's opponent is drawn once and saved
##   - the race result (and any crash damage) is applied and saved BEFORE the
##     replay plays

const UI := preload("res://ui.gd")
const Voice := preload("res://voice.gd")
const Bridge := preload("res://bridge.gd")
const TrackMap := preload("res://track_map.gd")
const Viewer := preload("res://main.gd")
const IntroScene := preload("res://intro.tscn")
const WarehouseScene := preload("res://screens/warehouse.tscn")
const CarScene := preload("res://screens/car.tscn")
const CalendarScene := preload("res://screens/calendar.tscn")
const ShopScene := preload("res://screens/shop.tscn")
const RevealScene := preload("res://screens/reveal.tscn")
const TeamScene := preload("res://screens/team.tscn")
const MeetingScene := preload("res://screens/meeting.tscn")
const ResultsScene := preload("res://screens/results.tscn")
const CodesScene := preload("res://screens/codes.tscn")
const TutorialScene := preload("res://screens/tutorial.tscn")
const BodyShopScene := preload("res://screens/bodyshop.tscn")
const BodyShop := preload("res://bodyshop.gd")
const BrokeScene := preload("res://screens/broke.tscn")
const SettingsScene := preload("res://screens/settings.tscn")
## The settings screen's rows: key -> [label, default]. Stored in state["settings"]
## (an optional key: older saves just get the defaults).
const SETTINGS := {
	"parked_car": ["the other car parked in the garage (home)", true],
	"sound": ["sound", true],
}
const ScoutScene := preload("res://screens/scout.tscn")
const ShellScene := preload("res://screens/shell.tscn")
const GritShader := preload("res://widgets/grit.gdshader")
const LOCATIONS := {
	"warehouse": "THE WAREHOUSE",       # Dymo label-maker strips
	"car": "BAY 1 // THE DX",
	"calendar": "THE WHITEBOARD",
	"shop": "PARTS $$$",
	"team": "THE BOARD",
	"codes": "THE BACK ROOM",
	"road": "TONIGHT'S ROAD",
	"tutorial": "HOW TO RACE",
	"bodyshop": "BAY 2 // BODY SHOP",
	"settings": "SETTINGS",
}

const SAVE_PATH := "user://save.json"
const TEST_SAVE_PATH := "user://test_save.json"   # --gametest / --gameshots: never touch the real save
const SAVE_VERSION := 6
const START_CASH := 200
const MIN_BUY_IN := 100             # the first minimum bet (see min_bet())
const MIN_BET_STEP := 100            # +$100 for every rival night behind you (Spire)
const MAX_BET_MULT := 5              # max bet = 5x tonight's minimum (Spire)
const WAGER_STEP := 10
const REP_OPEN_WIN := 4             # beating a street racer on an open road
const REP_RIVAL_WIN := 15            # beating the rival: the night that moves you up
const SKIP_REP_COST := 50            # chicken-out fee
const LOOT_CHANCE := 0.05            # chance a win also drops an unopened part ("loot" pull)
const COPS_CHANCE := 0.03            # a race that finishes gets pulled over on the way out (Spire)...
const COPS_FINE_MINS := 3            # ...a fine of this many of tonight's minimum bets, no winnings
const JORGE_CONDITION := 0.7         # jorge mode: his engine at this share of its torque...
const JORGE_TRIES := 15              # ...and a race Faba doesn't win is run again (new seeds) up to this often
const JORGE_LOOT_Q := 0.0            # ...and every win drops a part rolled at 0% (Spire)
const SCRAP_RATE := 0.25             # selling a spare: price x rate x (0.5 + quality)
const NEW_QUALITY := 0.5             # shop parts are new in box: exactly the catalog spec
const REP_LOSS := -5                 # every loss costs rep (half a win)
const REP_CRASH := -20               # putting it in the trees costs more
const BODY_REPAIR := 150             # tow + body work after any crash
const DAMAGE_CHANCE := 0.40          # per installed part, on a crash
const DESTROY_CHANCE := 0.10         # per installed part, on a crash
const REPAIR_RATE := 0.30            # repairing a damaged part: 30% of its price
const RIVAL_FILE := "data/rivals/zed_280z.json"
const RIVAL_ID := "zed_280z"           # the rival file's id (state["rivals"] key)
const PUSH_ORDER := ["safe", "normal", "hard", "flat_out"]
const RARITY_COLORS := {
	"common": Color(0.75, 0.76, 0.8), "rare": Color(0.35, 0.6, 1.0),
	"epic": Color(0.72, 0.42, 1.0), "legendary": Color(1.0, 0.78, 0.25)}

# Calendar: a week is 7 days; race nights fall on these days (0 = Monday)
const DAY_NAMES := ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
const RACE_DAYS := [4, 5, 6]     # Fri + Sat open roads, every 2nd Sunday the rival

var save_path := SAVE_PATH
var state := {}            # saved: cash, rep, week, day, history, night, intro_seen
var car_stats := {}        # bridge replies, cached for the session
var track_info := {}
var catalog := {}          # bridge "parts" reply (slots + parts with exact effects)
var shop_message := ""
var pending_race := {}     # race reply + result, held while a loot pull resolves
var jorge_tries := 0
var still_mode := false    # --gametest / --gameshots: no transitions or count-ups (they'd blur the stills)       # jorge mode: races re-run tonight so Faba wins
var pull_paid := 0         # price of the pull in flight: refunded if the sim fails
var bridge: Node
var screen: Control        # current UI screen (the shell while in the hub)
var shell: Control         # persistent hub shell (top rail, ribbon, bottom nav)
var hub_content: Control   # the hub screen currently inside the shell
var viewer: Node           # replay viewer while racing
var last_replay := ""      # the replay just watched (results reads its track for the map)
var choice := {"push": "normal", "wager": MIN_BUY_IN}
var compare := {}          # CAR: a swap being looked at: {slot, uid, stats (with it)}
var road_read := {}        # the road screen's read of tonight's road (bridge road_read)
var road_read_for := ""    # ...for which road + build (it depends on the parts)
var after_car_stats := "warehouse"   # where to go once car stats arrive
var after_catalog := "shop"          # where to go once the parts catalog arrives


# ------------------------------------------------------------------ setup

func _ready() -> void:
	RenderingServer.set_default_clear_color(UI.BG)
	bridge = Bridge.new()
	add_child(bridge)
	add_grit()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--gametest" or a.begins_with("--gameshots="):
			save_path = TEST_SAVE_PATH
			still_mode = true
	load_game()
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
		"inventory": [], "installed": {}, "pity": {}, "next_uid": 1,
		"rivals": {}, "stats": {}}


func load_game() -> void:
	state = new_state()
	if not FileAccess.file_exists(save_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(data) != TYPE_DICTIONARY:
		return
	state = migrate(data)
	Sound.muted = state.get("mute", false)     # code "mute" (an optional key: older saves just don't have it)


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
			inv.append({"uid": uid, "part": id, "quality": NEW_QUALITY, "revealed": true,
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
	if v < 5:                        # v4 -> v5: head to head (a night is a stat card)
		var night: Dictionary = data.get("night", {})
		if not night.is_empty() and not night.has("opponent"):
			data["night"] = {}       # an old posted-time night: redraw it as a card
		v = 5
	if v < 6:                        # v5 -> v6: new schedule (4 open : 1 rival), tuned
		data["night"] = {}           # opponents, rival progress, team stats
		data["rivals"] = {}
		data["stats"] = {}
		v = 6
	data["version"] = v
	return data


func save_game() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "  "))


## A fresh save. story: play the intro again (the startover code) instead of
## going straight to the warehouse (BROKE's START OVER).
func reset_game(story := false) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	state = new_state()
	save_game()
	car_stats = {}
	track_info = {}
	if story:
		show_intro()
	else:
		show_warehouse()


# ------------------------------------------------------------------ calendar

## Events in a given week: [{"day", "type", "title", "road"?}]. Friday and
## Saturday: open roads vs street racers (two different generated roads a
## week). Every 2nd Sunday: the rival on his home road. 4 open : 1 rival.
## Open road n's style rotates technical -> balanced -> flowing (the bridge
## generates the same road for the same n); style also picks the replay's place.
const OPEN_STYLES := ["technical", "balanced", "flowing"]
const RIVAL_EVERY_WEEKS := 2


func events_for_week(week: int) -> Array:
	var out := []
	for i in 2:
		var road := 2 * (week - 1) + i + 1               # open road number: 1, 2, 3, ...
		out.append({"day": 4 + i, "type": "open", "road": road,
			"title": "Open road (%s), street racer" % OPEN_STYLES[(road - 1) % 3]})
	if week % RIVAL_EVERY_WEEKS == 0:
		out.append({"day": 6, "type": "rival", "title": "Zed (280Z) on his home road"})
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
	shell = null
	hub_content = null


## Film grain + vignette over every screen (widgets/grit.gdshader): the
## late-90s / 2000s tuner-video look. Never blocks touches.
func add_grit() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GritShader
	rect.material = mat
	layer.add_child(rect)


## Show a hub screen inside the persistent shell. The shell is created once;
## moving between hub tabs swaps only its content slot.
func open_hub(packed: PackedScene, tab: String) -> Control:
	if shell == null:
		clear_screen()
		shell = ShellScene.instantiate()
		shell.animate = not still_mode           # stills and tests: no slides, no counting
		add_child(shell)
		shell.go.connect(_go)
		screen = shell
	shell.set_stats(int(state["cash"]), int(state["rep"]), min_bet())
	shell.set_location(LOCATIONS[tab], tab)
	hub_content = packed.instantiate()
	hub_content.go.connect(_go)
	shell.set_content(hub_content)
	return hub_content


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
		"team":
			show_team()
		"race", "road":
			show_briefing()
		"codes":
			show_codes()
		"settings":
			show_settings()
		"bodyshop":
			show_bodyshop()
		"fullbuild":                         # the code was waiting on the catalog
			enter_code("fullbuild")
		"broke":
			show_broke()


func common_info() -> Dictionary:
	return {"cash": int(state["cash"]), "rep": int(state["rep"]), "min_buy_in": min_bet()}


## A note on its own: loading, LIGHTS OUT, BROKE. Dymo title over a paper
## slip, centered; an optional gaffer-tape button.
func show_message(title: String, text: String, button_text := "", action := Callable()) -> void:
	clear_screen()
	var root := CenterContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	screen = root
	var col := UI.vbox(root, 14)
	col.custom_minimum_size.x = 600
	var t := UI.label(col, title, "DymoLabel")
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var slip := PanelContainer.new()
	slip.theme_type_variation = "PaperPanel"
	slip.rotation = -0.01
	col.add_child(slip)
	UI.label(slip, text, "InkLabel").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if button_text != "":
		UI.button(col, button_text, action, "GaffButton")


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
	if state["cash"] < min_bet():
		show_broke()
		return
	var ev := next_event()
	var record := wins_losses()
	var info := common_info()
	info["week"] = int(state["week"])
	info["when"] = when(ev["week"], ev["day"])
	info["event_type"] = ev["type"]
	info["event_kind"] = "Rival night" if ev["type"] == "rival" else "Open road"
	info["order_no"] = state["history"].size() + 1       # one work order per race night
	info["event_detail"] = "%s. Today is %s." % [ev["title"], when(state["week"], state["day"]).to_lower()]
	info["wins"] = record.x
	info["losses"] = record.y
	info["min_buy_in_text"] = UI.money(min_bet())
	info["parts"] = car_look()
	info["parked_car"] = setting("parked_car")
	info["caption"] = "%s, wk %d. %s" % [Voice.HOME_PLACE, int(state["week"]), home_caption(installed_part_ids().size())]
	open_hub(WarehouseScene, "warehouse").setup(info)


## A setting's value (state["settings"], SETTINGS' default when unset). Sound
## is the same switch as the "mute" code.
func setting(key: String) -> bool:
	if key == "sound":
		return not state.get("mute", false)
	return bool(state.get("settings", {}).get(key, SETTINGS[key][1]))


func show_settings() -> void:
	var s: Control = open_hub(SettingsScene, "settings")
	var rows := []
	for key in SETTINGS:
		rows.append({"key": key, "label": SETTINGS[key][0], "on": setting(key)})
	s.setup(rows)
	s.toggle.connect(func(key: String):
		if key == "sound":
			state["mute"] = setting("sound")
			Sound.muted = state["mute"]
		else:
			if not state.has("settings"):
				state["settings"] = {}
			state["settings"][key] = not setting(key)
		save_game()
		show_settings())


## The builder's note on the home Polaroid (voice.gd): what happened last
## night beats how built the car is.
func home_caption(parts_on: int) -> String:
	var hist: Array = state["history"]
	if not hist.is_empty():
		var last: Dictionary = hist[-1]
		if last.get("skipped", false):
			return Voice.HOME_SKIPPED
		if last.get("dnf", false):
			return Voice.HOME_CRASHED
	var races := hist.filter(func(r): return not r.get("skipped", false) and not r.get("no_contest", false))
	if streak(races, true) >= Voice.WIN_STREAK:
		return Voice.HOME_WIN_STREAK
	if streak(races, false) >= Voice.LOSS_STREAK:
		return Voice.HOME_LOSS_STREAK
	if parts_on == 0:
		return Voice.HOME_STOCK
	return Voice.HOME_BUILT if parts_on >= Voice.BUILT_PARTS else Voice.HOME_SOME_PARTS


## How many races in a row, counting back from the latest, were wins (or losses).
func streak(races: Array, wins: bool) -> int:
	var n := 0
	for i in range(races.size() - 1, -1, -1):
		if bool(races[i]["won"]) != wins:
			break
		n += 1
	return n


## The body shop: what's owned and what's worn (an optional save key:
## older saves just don't have one yet).
func look_state() -> Dictionary:
	if not state.has("look"):
		state["look"] = {"owned": [], "worn": {}}
	return state["look"]


## Everything the 3D DX shows: its parts and its looks ("look:<id>").
func car_look() -> Array:
	return installed_part_ids() + BodyShop.look_tags(look_state()["worn"])


func show_bodyshop(message := "") -> void:
	var lk := look_state()
	var bs: Control = open_hub(BodyShopScene, "bodyshop")
	bs.buy.connect(buy_look)
	bs.wear.connect(func(id):
		lk["worn"][BodyShop.ITEMS[id]["slot"]] = id
		save_game()
		show_bodyshop())
	bs.take_off.connect(func(slot):
		lk["worn"].erase(slot)
		save_game()
		show_bodyshop())
	bs.setup({"parts": installed_part_ids(), "owned": lk["owned"], "worn": lk["worn"],
		"spendable": int(state["cash"]) - min_bet(), "message": message})


## Buy a cosmetic and put it on. Same rule as parts: never below the buy-in.
func buy_look(id: String) -> void:
	var item: Dictionary = BodyShop.ITEMS.get(id, {})
	if item.is_empty() or id in look_state()["owned"]:
		return
	if not can_spend(int(item["price"])):
		show_bodyshop("Can't: that would leave less than the %s buy-in." % UI.money(min_bet()))
		return
	state["cash"] = int(state["cash"]) - int(item["price"])
	stat_add("spent", int(item["price"]))
	look_state()["owned"].append(id)
	look_state()["worn"][item["slot"]] = id
	save_game()
	Sound.play("cash")
	show_bodyshop("%s: done." % item["name"])


## Part ids on the car right now (installed and not damaged): for the 3D model.
func installed_part_ids() -> Array:
	var ids := []
	for slot in state["installed"]:
		var inst := instance(state["installed"][slot])
		if not inst.is_empty() and not inst.get("damaged", false):
			ids.append(inst["part"])
	return ids


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
	# Dropdown options per slot: every revealed part you own, with its quality
	var options := {}
	for inst in state["inventory"]:
		if not inst["revealed"]:
			continue
		var p := part_by_id(inst["part"])
		if not options.has(p["slot"]):
			options[p["slot"]] = []
		options[p["slot"]].append([inst["uid"], "%s  (Q %d%%)%s" % [p["name"], quality_pct(inst),
			"  DAMAGED" if inst.get("damaged", false) else ""]])
	var car: Control = open_hub(CarScene, "car")
	car.part_changed.connect(install_part)
	car.part_previewed.connect(preview_part)
	car.strip_pressed.connect(strip_car)
	car.compare_closed.connect(func():
		compare = {}
		show_car())
	var info := common_info()
	info["parts_on"] = car_look()
	var night: Dictionary = state["night"]
	info["night"] = ("locked" if build_locked() else
		("scouting" if not night.is_empty() and night.get("event") == event_key(next_event()) else ""))
	car.setup(info, car_stats,
		{"slots": catalog["slots"], "options": options, "installed": state["installed"],
		"pictures": installed_pictures()})
	if not compare.is_empty():
		var inst := instance(compare["uid"])
		var old := instance(state["installed"].get(compare["slot"], ""))
		car.show_compare({
			"slot": catalog["slots"].get(compare["slot"], compare["slot"]),
			"from": part_label(old), "to": part_label(inst),
			"effects": inst.get("effects_text", []), "damaged": inst.get("damaged", false),
			"now": car_stats, "with": compare["stats"], "slot_id": compare["slot"], "uid": compare["uid"],
			"part": inst.get("part", ""), "rarity_color": RARITY_COLORS.get(part_by_id(inst.get("part", "")).get("rarity", ""),
				Color(0, 0, 0, 0)), "rarity": part_by_id(inst.get("part", "")).get("rarity", "")})


## Slot -> the part id on it (the build sheet draws each one's picture).
func installed_pictures() -> Dictionary:
	var out := {}
	for slot in state["installed"]:
		var inst := instance(state["installed"][slot])
		if not inst.is_empty():
			out[slot] = inst["part"]
	return out


## "Cold air intake (Q 62%)", or "stock" for an empty slot.
func part_label(inst: Dictionary) -> String:
	if inst.is_empty():
		return "stock"
	return "%s (Q %d%%)" % [part_by_id(inst["part"]).get("name", inst["part"]), quality_pct(inst)]


## Picked a part in CAR: dyno the DX with it on (bridge car_stats, ~0.3 s)
## and show the swap side by side before anything changes.
func preview_part(slot: String, uid: String) -> void:
	if build_locked():
		show_car()
		return
	var trial: Dictionary = state["installed"].duplicate()
	if uid == "":
		trial.erase(slot)
	else:
		trial[slot] = uid
	compare = {"slot": slot, "uid": uid}
	bridge.request("compare", ["car_stats"] + parts_args(trial))


func show_shop() -> void:
	if catalog.is_empty():
		show_message("PARTS", "Checking the parts shelf...")
		after_catalog = "shop"
		bridge.request("parts", ["parts"])
		return
	var shop: Control = open_hub(ShopScene, "shop")
	shop.buy.connect(buy_part)
	shop.pull.connect(do_pull)
	shop.sell.connect(sell_instance)
	shop.sell_all.connect(sell_all_spares)
	shop.repair.connect(repair_instance)
	shop.reveal.connect(func(uid): show_reveal(instance(uid), "dyno"))
	shop.setup(common_info(), catalog, state["inventory"], state["installed"],
		state["pity"], shop_message)
	shop_message = ""


## Installed parts for every sim call, as id@quality: the car being simulated
## is the exact car in the warehouse, rolls included.
## installed: a what-if build (the parts comparison); default = the car as it is.
func parts_args(installed = null) -> Array:
	var build: Dictionary = state["installed"] if installed == null else installed
	var entries := []
	for slot in build:
		var inst := instance(build[slot])
		if not inst.is_empty() and not inst.get("damaged", false):   # damaged = off the car
			entries.append("%s@%.4f" % [inst["part"], float(inst["quality"])])
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


func quality_pct(inst: Dictionary) -> int:
	return int(round(float(inst["quality"]) * 100))


func add_instance(part_id: String, quality: float, revealed: bool, source: String,
		effects_text := []) -> Dictionary:
	var inst := {"uid": "p%d" % int(state["next_uid"]), "part": part_id, "quality": quality,
		"revealed": revealed, "source": source, "effects_text": effects_text}
	state["next_uid"] = int(state["next_uid"]) + 1
	state["inventory"].append(inst)
	return inst


## Tonight's minimum bet: $100 until the first rival night is behind you,
## then MIN_BET_STEP more for every rival night (raced or skipped). It's also
## the BROKE line and the floor no purchase can take you under.
func min_bet() -> int:
	var rival_nights: int = state["history"].filter(func(r): return r.get("rival_night", false)).size()
	return MIN_BUY_IN + MIN_BET_STEP * rival_nights


func max_bet() -> int:
	return min_bet() * MAX_BET_MULT


func can_spend(amount: int) -> bool:
	## The game never lets you spend below the race buy-in (soft-lock guard).
	return int(state["cash"]) - amount >= min_bet()


## The counter sells commons, new in box (exactly the catalog spec).
func buy_part(id: String) -> void:
	var p := part_by_id(id)
	if p.is_empty() or p["rarity"] != "common":
		return
	if not can_spend(int(p["price"])):
		shop_message = "Can't: that would leave less than the %s buy-in." % UI.money(min_bet())
		show_shop()
		return
	state["cash"] = int(state["cash"]) - int(p["price"])
	stat_add("spent", int(p["price"]))
	var inst := add_instance(id, NEW_QUALITY, true, "shop", p["effects_text"])
	if build_locked():
		shop_message = "Bought %s. It goes on after tonight (the build's locked in)." % p["name"]
		save_game()
	else:
		shop_message = "Bought and installed: %s." % p["name"]
		install_part(p["slot"], inst["uid"], false)
	show_shop()


## Pull from an in-world source: rep gate, cash, then the bridge rolls it.
func do_pull(source: String) -> void:
	var src: Dictionary = catalog["sources"][source]
	if int(state["rep"]) < int(src["rep_required"]):
		shop_message = "%s needs %d rep." % [src["name"], int(src["rep_required"])]
		show_shop()
		return
	if not can_spend(int(src["price"])):
		shop_message = "Can't: that would leave less than the %s buy-in." % UI.money(min_bet())
		show_shop()
		return
	state["cash"] = int(state["cash"]) - int(src["price"])
	stat_add("spent", int(src["price"]))
	stat_add("pulls", 1)
	pull_paid = int(src["price"])
	save_game()                                   # paid: a crash or quit can't refund it
	show_message("PULLING", "%s..." % src["name"])
	var god := ["--quality", "1.0"] if state.get("godroll", false) else []   # the godroll code
	bridge.request("pull", ["pull", "--source", source, "--seed", str(randi() % 1000000)]
		+ pity_args() + god)


## Pity counters for the bridge: ["--pity", "source=N,source=N"], or nothing
## when there are none. Not JSON (Windows command lines strip its double
## quotes), and never an empty argument (Windows drops it, leaving --pity
## without a value).
func pity_args() -> Array:
	var items := []
	for source in state["pity"]:
		items.append("%s=%d" % [source, int(state["pity"][source])])
	return [] if items.is_empty() else ["--pity", ",".join(items)]


func on_pulled(data: Dictionary) -> void:
	pull_paid = 0
	state.erase("godroll")                        # one pull only
	state["pity"] = data["pity"]
	var inst := add_instance(data["part"], float(data["quality"]), false, data["source"],
		data["effects_text"])
	save_game()
	show_reveal(inst)


## The reveal on the workbench (screens/reveal.tscn). stage: "box" = a fresh
## pull, still taped shut; "dyno" = straight to the dyno printout (a part off
## the bench); "sheet" = already dynoed, everything shown.
## Dynoing marks the part revealed and saves before the sheet prints.
func show_reveal(inst: Dictionary, stage := "box") -> void:
	var p := part_by_id(inst["part"])
	clear_screen()
	var r: Control = RevealScene.instantiate()
	add_child(r)
	screen = r
	var reveal_now := func():
		if not inst["revealed"]:
			note_roll(inst, p)
		inst["revealed"] = true
		save_game()
	r.dyno_pressed.connect(func():
		reveal_now.call()
		r.print_sheet())
	r.leave_pressed.connect(show_shop)
	r.install_pressed.connect(func():
		install_part(p["slot"], inst["uid"], false)
		shop_message = "Installed: %s (Q %d%%)." % [p["name"], quality_pct(inst)]
		show_shop())
	if stage == "dyno" or inst["revealed"]:
		reveal_now.call()
	var src_name: String = catalog["sources"].get(inst["source"], {}).get("name", "Loot drop") 		if inst["source"] != "shop" else "Parts counter"
	r.setup({"id": p["id"], "from": src_name, "rarity": p["rarity"], "rarity_color": RARITY_COLORS[p["rarity"]],
		"name": p["name"], "slot": str(catalog["slots"][p["slot"]]), "quality_pct": quality_pct(inst),
		"effects": inst["effects_text"], "blurb": p["blurb"]}, stage)


## Repair a damaged part (it's off the car until repaired).
func repair_instance(uid: String) -> void:
	var inst := instance(uid)
	if inst.is_empty() or not inst.get("damaged", false):
		return
	var p := part_by_id(inst["part"])
	var cost := int(round(float(p["price"]) * REPAIR_RATE))
	if not can_spend(cost):
		shop_message = "Can't: the repair would leave less than the %s buy-in." % UI.money(min_bet())
		show_shop()
		return
	state["cash"] = int(state["cash"]) - cost
	stat_add("spent", cost)
	stat_add("repairs", 1)
	inst["damaged"] = false
	car_stats = {}
	save_game()
	shop_message = "Repaired %s for %s." % [p["name"], UI.money(cost)]
	show_shop()


## Sell a spare for scrap. Installed parts must be swapped out first.
func sell_instance(uid: String) -> void:
	var inst := instance(uid)
	if inst.is_empty() or uid in state["installed"].values():
		return
	var p := part_by_id(inst["part"])
	var value := scrap_value(inst)
	state["cash"] = int(state["cash"]) + value
	state["inventory"].erase(inst)
	save_game()
	shop_message = "Sold %s for %s." % [p["name"], UI.money(value)]
	show_shop()


## Scrap every spare on the shelf at once (Spire): revealed, not on the car,
## not damaged (the shelf's own rule). Returns what it paid.
func scrap_all_spares() -> int:
	var paid := 0
	var n := 0
	for inst in state["inventory"].duplicate():
		if inst["revealed"] and not inst.get("damaged", false) and not inst["uid"] in state["installed"].values():
			paid += scrap_value(inst)
			state["inventory"].erase(inst)
			n += 1
	state["cash"] = int(state["cash"]) + paid
	stat_add("scrapped", n)
	save_game()
	return paid


func sell_all_spares() -> void:
	shop_message = "Scrapped the whole shelf for %s." % UI.money(scrap_all_spares())
	show_shop()


## Every part off the car at once (Spire: no compare card): they all go back
## to the spares, the DX is stock. Not while the build's locked in.
func strip_car() -> void:
	strip_all()
	show_car()


## Returns false (nothing changes) while the build's locked in.
func strip_all() -> bool:
	if build_locked():
		return false
	state["installed"] = {}
	car_stats = {}
	compare = {}
	save_game()
	return true


## Swap what's in a slot ("" = back to stock). The car changed, so its stats
## are stale.
func install_part(slot: String, uid: String, refresh := true) -> void:
	if build_locked():                       # locked in for tonight: nothing goes on or off
		if refresh:
			show_car()
		return
	if uid == "":
		state["installed"].erase(slot)
	else:
		state["installed"][slot] = uid
	car_stats = {}
	if compare.get("slot", "") == slot and compare.get("uid", "?") == uid and compare.has("stats"):
		car_stats = compare["stats"]         # already dynoed it with this part on
	compare = {}
	save_game()
	if refresh:
		show_car()


# ------------------------------------------------------------------ team

## TEAM stats that history alone can't give (saved in state["stats"]).
func stat_add(key: String, amount: int) -> void:
	state["stats"][key] = int(state["stats"].get(key, 0)) + amount


## A dynoed roll: remember the best one; a legendary is a memory.
func note_roll(inst: Dictionary, part: Dictionary) -> void:
	var best: Dictionary = state["stats"].get("best_roll", {})
	if best.is_empty() or float(inst["quality"]) > float(best["q"]):
		state["stats"]["best_roll"] = {"name": part["name"], "q": float(inst["quality"])}
	if part.get("rarity", "") == "legendary":
		unlock("legendary")


func unlock(memory: String) -> void:
	var mem: Dictionary = state["stats"].get("memories", {})
	if not mem.has(memory):
		mem[memory] = when(state["week"], state["day"])
		state["stats"]["memories"] = mem


## Milestones from a race result (and the bet behind it).
func note_memories(result: Dictionary) -> void:
	state["stats"]["biggest_bet"] = maxi(int(state["stats"].get("biggest_bet", 0)), int(result["wager"]))
	if result["won"]:
		unlock("first_win")
		if result.get("rival_night", false):
			unlock("beat_rival")
	if result["dnf"]:
		unlock("first_crash")
	var races: Array = state["history"].filter(func(r): return (not r.get("skipped", false)
		and not r.get("no_contest", false)))
	if streak(races, true) >= 3:
		unlock("streak3")
	if (int(result["wager"]) >= int(result.get("top_bet", 1 << 30)) * Voice.BIG_BET_SHARE
			and int(result["wager"]) > int(result.get("min_bet", MIN_BUY_IN))):
		unlock("big_bet")


## Everything the board shows, worked out from history + stats.
func team_info() -> Dictionary:
	var races: Array = state["history"].filter(func(r): return not r.get("skipped", false))
	var wins := races.filter(func(r): return r["won"]).size()
	var crashes := races.filter(func(r): return r.get("dnf", false)).size()
	var mistakes := 0
	var pushes := {}
	var best := {}                       # road -> best finished time
	var vs := {}                         # rival -> [wins, losses]
	var net := 0
	for r in races:
		mistakes += r.get("mistakes", []).size()
		pushes[r.get("push", "?")] = int(pushes.get(r.get("push", "?"), 0)) + 1
		net += int(r.get("cash_change", 0))
		var road: String = str(r.get("track", "")).get_file().get_basename().replace("_", " ")
		if road != "" and not r.get("dnf", false) and r.has("time"):
			best[road] = minf(float(best.get(road, INF)), float(r["time"]))
		if r.get("rival_night", false):
			var rec: Array = vs.get(r["rival"], [0, 0])
			rec[0 if r["won"] else 1] += 1
			vs[r["rival"]] = rec
	var fav := "-"
	for k in pushes:
		if fav == "-" or int(pushes[k]) > int(pushes[fav]):
			fav = k
	var st: Dictionary = state["stats"]
	var roll: Dictionary = st.get("best_roll", {})
	var mem: Dictionary = st.get("memories", {})
	var memories := []
	for id in Voice.MEMORY_ORDER:
		memories.append({"photo": Voice.MEMORIES[id][0], "caption": Voice.MEMORIES[id][1],
			"unlocked": mem.has(id), "when": mem.get(id, "")})
	var best_rows := []
	for road in best:
		best_rows.append([road, "%.2f s" % best[road]])
	var vs_rows := []
	for name in vs:
		vs_rows.append(["vs %s" % name, "%d - %d" % [vs[name][0], vs[name][1]]])
	return {
		"faba": [["Races", str(races.size())], ["Wins", str(wins)], ["Crashes", str(crashes)],
			["Mistakes per race", "%.1f" % (float(mistakes) / maxi(races.size(), 1))],
			["Favorite push", str(fav).replace("_", " ")]] + best_rows,
		"builder": [["Pulls", str(int(st.get("pulls", 0)))],
			["Best roll", "-" if roll.is_empty() else "%s (Q %d%%)" % [roll["name"], int(round(float(roll["q"]) * 100))]],
			["Spent on the car", UI.money(int(st.get("spent", 0)))],
			["Parts lost to crashes", str(int(st.get("destroyed", 0)))],
			["Repairs", str(int(st.get("repairs", 0)))]],
		"record": [["Record", "%d W - %d L" % [wins, races.size() - wins]],
			["Net cash", "%s%s" % ["+" if net > 0 else "", UI.money(net)]],
			["Biggest bet", UI.money(int(st.get("biggest_bet", 0)))]] + vs_rows,
		"memories": memories,
		"parts_on": car_look(),
	}


func show_team() -> void:
	open_hub(TeamScene, "team").setup(team_info())


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
		# [when, who, result, amount, "money" or "rep"]
		if r.get("skipped", false):
			past.append([r.get("when", "-"), "vs %s" % r["rival"], Voice.BOARD_SKIPPED,
				"%d rep" % int(r["rep_change"]), "rep"])
		else:
			var mark := "NC" if r.get("no_contest", false) else ("W" if r["won"] else "L")
			past.append([r.get("when", "-"), "vs %s" % r["rival"], mark,
				"%s%s" % ["+" if int(r["cash_change"]) > 0 else "", UI.money(int(r["cash_change"]))], "money"])
	info["past"] = past
	var races := hist.filter(func(r): return not r.get("skipped", false) and not r.get("no_contest", false))
	info["last_lost"] = not races.is_empty() and not races[-1]["won"]     # sad face on the board
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


## Race night, in Spire's order: 1. the road (scout it), 2. build for it in
## CAR, 3. LOCK IT IN, 4. the opponent is matched to that build (street
## racers tuned to a coin flip; the rival as he is), 5. the meeting. Each step
## is saved, so restarting never rerolls anything.
func show_briefing() -> void:
	var ev := next_event()
	# A saved night belongs to one calendar event; a stale one gets redrawn
	if not state["night"].is_empty() and state["night"].get("event") != event_key(ev):
		state["night"] = {}
	var night: Dictionary = state["night"]
	if night.is_empty():
		show_message("TONIGHT", "Pulling up tonight's road.")
		bridge.request("road", ["road", "--road", str(ev["road"])] if ev["type"] == "open"
			else ["road", "--rival", RIVAL_FILE])
		return
	if track_info.is_empty():
		show_message("SCOUTING", "Driving the road in daylight.")
		bridge.request("track", ["track", "--track", night["track"]])
		return
	if car_stats.is_empty():
		show_message("SIZING UP", "Putting the DX on the scales.")
		after_car_stats = "race"
		bridge.request("car_stats", ["car_stats"] + parts_args())
		return
	if not night.has("parts"):
		var key := "%s %s" % [night["track"], parts_args()]
		if road_read_for != key:             # what the road rewards, for the DX as built now
			show_message("SCOUTING", "Walking the road with a notebook.")
			road_read_for = key
			bridge.request("road_read", ["road_read", "--track", night["track"]] + parts_args())
			return
		show_scout()                         # build for the road, then lock it in
		return
	if not night.has("opponent"):
		show_message("WORD ON THE STREET", "Finding out who's running tonight.")
		var seed := str(randi() % 1000000)
		if ev["type"] == "open":
			# Matched to the locked build, tuned to a coin flip
			bridge.request("night", ["street", "--road", str(ev["road"]), "--seed", seed, "--tune"]
				+ night["parts"])
		else:
			bridge.request("night", rival_args(seed))
		return
	if catalog.is_empty():
		after_catalog = "race"
		bridge.request("parts", ["parts"])
		return
	show_meeting()


## Step 1: tonight's road and the DX as it sits (screens/scout.tscn).
func show_scout() -> void:
	if not state.get("tutorial_seen", false) and not test_running:
		state["tutorial_seen"] = true                # the first race night: how it works, once
		save_game()
		show_tutorial(show_scout)
		return
	var ev := next_event()
	var night: Dictionary = state["night"]
	var s: Control = open_hub(ScoutScene, "road")
	s.car_pressed.connect(show_car)
	s.lock_pressed.connect(lock_build)
	s.skip_pressed.connect(skip_night)
	s.howto_pressed.connect(show_tutorial.bind(show_scout))
	s.setup({
		"where": "%s // %s" % [when(ev["week"], ev["day"]).to_lower().replace(",", ""),
			ev["title"].to_lower()],
		"road_info": "%d m, %d corners" % [int(track_info["length"]), track_info["corners"].size()],
		"track": track_info, "stats": car_stats, "read": road_read,
		"parts_on": installed_part_ids().size(),
		"can_skip": int(state["rep"]) >= SKIP_REP_COST, "skip_cost": SKIP_REP_COST,
	})


## Step 3: the build is set for the night (installs refused until it's over),
## and the opponent gets matched to exactly this car.
func lock_build() -> void:
	state["night"]["parts"] = parts_args()
	save_game()
	if not test_running:
		show_briefing()


## Locked in for tonight: from LOCK IT IN until the race (or a skip) clears the night.
func build_locked() -> bool:
	var night: Dictionary = state["night"]
	return night.has("parts") and night.get("event", "") == event_key(next_event())


## The rival's card: his saved engine (he keeps what he had), re-tuned
## against the DX as it is now only if Faba beat him last time. Rivals never
## fully keep up: building between rival nights is how you climb.
func rival_args(seed: String) -> Array:
	var args := ["rival", "--rival", RIVAL_FILE, "--seed", seed]
	var r: Dictionary = state["rivals"].get(RIVAL_ID, {})
	if r.has("condition"):
		args += ["--condition", str(r["condition"])]
	if r.get("retune", false):
		args += ["--retune"] + parts_args()
	return args


## Push levels as Faba describes them: no numbers, just what you're risking.
const PUSH_TALK := {
	"safe": "Well inside the limit. Won't crash. Won't win much either.",
	"normal": "A steady pace. Mistakes are rare.",
	"hard": "Right at the edge. Faster, and a real chance of going off.",
	"flat_out": "Over the edge on purpose. Fastest if it sticks. If it doesn't, the car is in the trees.",
}


func show_meeting() -> void:
	var night: Dictionary = state["night"]
	var ev := next_event()
	var rival_night: bool = night.get("id", "") != "street"
	clear_screen()
	var m: Control = MeetingScene.instantiate()
	add_child(m)
	screen = m
	m.push_changed.connect(func(p): choice["push"] = p)
	m.wager_changed.connect(func(w): choice["wager"] = w)
	m.send_pressed.connect(send_it)
	m.back_pressed.connect(show_warehouse)
	m.skip_pressed.connect(skip_night)
	m.howto_pressed.connect(show_tutorial.bind(show_meeting))
	var cash := int(state["cash"])
	choice["wager"] = clampi(int(choice["wager"]), min_bet(), mini(cash, max_bet()))
	m.setup({
		"where": "%s // %s" % [when(ev["week"], ev["day"]).replace(",", ""),
			"%s'S HOME ROAD" % str(night["name"]).to_upper() if rival_night else "OPEN ROAD"],
		"rival_night": rival_night,
		"opponent_car": night["car"], "faba_parts": car_look(),
		"road_info": "%s  /  %d m, %d corners" % [night["club"], int(track_info["length"]),
			track_info["corners"].size()],
		"track": track_info, "mine": car_stats, "theirs": night["stats"],
		"their_name": night["name"],
		"their_car_line": "%s (%s engine)" % [night["car"], night["condition"]],
		"word": night["driver_read"],
		"push": choice["push"], "push_order": PUSH_ORDER, "push_risk": PUSH_TALK,
		"wager": choice["wager"], "cash": cash, "min_buy_in": min_bet(), "max_bet": max_bet(),
		"wager_step": WAGER_STEP,
		"can_skip": int(state["rep"]) >= SKIP_REP_COST, "skip_cost": SKIP_REP_COST,
	})


## Chicken out of this race night: no money changes hands, but the scene
## notices. Costs SKIP_REP_COST rep; with less than that, you have to race.
func skip_night() -> void:
	if int(state["rep"]) < SKIP_REP_COST:
		return
	state["rep"] = int(state["rep"]) - SKIP_REP_COST
	var ev := next_event()
	state["history"].append({"when": when(ev["week"], ev["day"]), "rival": state["night"].get("name", "Zed"),
		"won": false, "skipped": true, "cash_change": 0, "rep_change": -SKIP_REP_COST,
		"rival_night": ev["type"] == "rival"})
	advance_past(ev)
	state["night"] = {}
	save_game()
	show_warehouse()


func send_it() -> void:
	show_message("LIGHTS OUT", "Faba lines up the DX next to %s's %s.\n%s on the line, %s push." % [
		state["night"]["name"], state["night"]["car"], UI.money(choice["wager"]),
		str(choice["push"]).replace("_", " ")])
	jorge_tries = 0
	request_race()


## Run tonight's race in the sim (a new seed each call). Jorge mode rigs it
## (Spire: he wins every time): the other guy's motor is down to
## JORGE_CONDITION of itself, and a run Faba doesn't win (a crash, mostly)
## is run again with new seeds before anything is settled (_on_reply "race").
func request_race() -> void:
	var out := ProjectSettings.globalize_path("user://replays/race.json")
	var condition := float(state["night"]["engine_condition"])
	if state.get("jorge", false):
		condition *= JORGE_CONDITION
	bridge.request("race", ["race", "--track", state["night"]["track"], "--push", choice["push"],
		"--seed", str(randi() % 1000000), "--out", out,
		"--opponent", state["night"]["opponent"], "--opp-seed", str(randi() % 1000000),
		"--opp-condition", str(condition),
		"--location", str(state["night"].get("location", "canyon"))] + parts_args())


## Consequences of a crash: body repair, and a damage roll on every installed
## part (DAMAGE_CHANCE damaged, DESTROY_CHANCE destroyed outright).
func crash_damage() -> Dictionary:
	var damaged := []
	var destroyed := []
	for slot in state["installed"].keys():
		var inst := instance(state["installed"][slot])
		if inst.is_empty():
			continue
		var roll := randf()
		var name: String = part_by_id(inst["part"]).get("name", inst["part"])
		if roll < DESTROY_CHANCE:
			destroyed.append(name)
			state["installed"].erase(slot)
			state["inventory"].erase(inst)
		elif roll < DESTROY_CHANCE + DAMAGE_CHANCE:
			inst["damaged"] = true
			damaged.append(name)
	stat_add("destroyed", destroyed.size())
	var body := mini(BODY_REPAIR, int(state["cash"]))   # can't go below $0
	state["cash"] = int(state["cash"]) - body
	return {"damaged": damaged, "destroyed": destroyed, "body_repair": body}


func apply_result(r: Dictionary) -> Dictionary:
	## Settle everything, move the calendar, and save BEFORE the replay plays.
	var night: Dictionary = state["night"]
	var ev := next_event()
	var won: bool = r["won"]
	var no_contest: bool = r["no_contest"]
	var wager := int(choice["wager"])
	var cash_change := 0 if no_contest else (wager if won else -wager)
	var stiffed: bool = won and not no_contest and state.get("jorge", false)   # jorge mode: he won't pay
	if stiffed:
		cash_change = 0
	# The cops (COPS_CHANCE, or the "heat" code): speeding + reckless driving.
	# A win pays nothing (the cash is evidence); a loss still costs the wager.
	# Not after a crash: the tow ticket is enough.
	# (Tests and stills: only the heat code calls them, so a 3% roll can't flip a hand calc.)
	var busted: bool = not r["dnf"] and not no_contest and (state.get("heat", false)
		or (not still_mode and randf() < COPS_CHANCE))
	state.erase("heat")
	if busted and won:
		cash_change = 0
	var rival_night: bool = night.get("id", "") != "street"
	var rep_change: int = ((REP_RIVAL_WIN if rival_night else REP_OPEN_WIN) if won
		else (REP_CRASH if r["dnf"] else REP_LOSS))
	var result := {
		"when": when(ev["week"], ev["day"]),
		"rival": night["name"], "rival_car": night["car"],
		"time": r["lap_time"], "dnf": r["dnf"], "crash_corner": r["crash_corner"],
		"opponent_time": r["opponent_time"], "opponent_dnf": r["opponent_dnf"],
		"opponent_crash_corner": r["opponent_crash_corner"],
		"won": won, "no_contest": no_contest, "push": r["push"], "seed": r["seed"],
		"wager": wager, "cash_change": cash_change, "rep_change": rep_change,
		"mistakes": r["mistakes"], "parts": parts_args(), "loot": "", "damage": {},
		"track": night.get("track", ""), "rival_night": rival_night,
		"top_bet": mini(int(state["cash"]), max_bet()), "min_bet": min_bet(),   # before this night counts
		"breakdown": r.get("breakdown", {}), "stiffed": stiffed}
	state["cash"] = int(state["cash"]) + cash_change
	if busted:                           # the fine, but never below $0
		var fine := mini(COPS_FINE_MINS * int(result["min_bet"]), maxi(int(state["cash"]), 0))
		state["cash"] = int(state["cash"]) - fine
		result["cops"] = {"fine": fine, "seized": won and not stiffed and wager > 0}
		stat_add("tickets", 1)
	state["rep"] = maxi(int(state["rep"]) + rep_change, 0)
	if r["dnf"]:
		result["damage"] = crash_damage()
		car_stats = {}                   # the car changed (parts damaged or gone)
	if rival_night and won:              # beat him: he upgrades before the next time
		var rv: Dictionary = state["rivals"].get(night["id"], {})
		rv["retune"] = true
		state["rivals"][night["id"]] = rv
	state["history"].append(result)
	note_memories(result)
	state["night"] = {}
	advance_past(ev)
	save_game()
	return result


func show_race(replay_path: String, result: Dictionary) -> void:
	clear_screen()
	viewer = Viewer.new()
	viewer.replay_path = replay_path        # the opponent rides along as the replay's ghost
	viewer.embedded = true
	viewer.busted = result.has("cops")                # the cops: lights and a siren at the end
	viewer.sore_loser = result.get("stiffed", false)   # jorge mode: he leans on his horn after
	# The DX as it raced (the result saved the build before any crash damage)
	var raced: Array = result.get("parts", [])
	if raced.size() == 2:
		for entry: String in str(raced[1]).split(","):
			viewer.faba_parts.append(entry.get_slice("@", 0))
	viewer.faba_parts.append_array(BodyShop.look_tags(look_state()["worn"]))   # and the paint, the stickers
	last_replay = replay_path
	viewer.finished_viewing.connect(show_results.bind(result))
	add_child(viewer)


func show_results(result: Dictionary) -> void:
	clear_screen()
	var r: Control = ResultsScene.instantiate()
	add_child(r)
	screen = r
	r.done_pressed.connect(show_warehouse)
	var loot_text := ""
	if result.get("loot", "") != "":
		var lp := part_by_id(result["loot"])
		loot_text = "%s paid up with more than cash: an unopened %s %s. It's on the bench in $$$." % [
			result["rival"], str(lp.get("rarity", "")), lp.get("name", result["loot"])]
		if result.get("stiffed", false):         # jorge mode: no cash, just a box of junk
			loot_text = "%s won't pay. He threw a box at you instead: an unopened %s %s. It's on the bench in $$$." % [
				result["rival"], str(lp.get("rarity", "")), lp.get("name", result["loot"])]
	var replay = JSON.parse_string(FileAccess.get_file_as_string(last_replay)) 		if FileAccess.file_exists(last_replay) else null
	r.setup(result, {"cash": int(state["cash"]), "rep": int(state["rep"]),
		"faba_parts": car_look(), "loot_text": loot_text,
		"track": replay["track"] if replay is Dictionary else {}})


## BROKE: under tonight's minimum bet. Scrap parts (even off the car) to get
## back over it, or start over (screens/broke.tscn).
func show_broke() -> void:
	if catalog.is_empty():                   # part names + prices for the scrap list
		show_message("BROKE", "Counting what's left...")
		after_catalog = "broke"
		bridge.request("parts", ["parts"])
		return
	var record := wins_losses()
	var parts := []
	for inst in state["inventory"]:
		var p := part_by_id(inst["part"])
		var where := "on the shelf"
		if inst["uid"] in state["installed"].values():
			where = "on the car"
		if not inst["revealed"]:
			where = "unopened"
		if inst.get("damaged", false):
			where = "damaged"
		parts.append({"uid": inst["uid"], "name": p.get("name", inst["part"]), "value": scrap_value(inst),
			"where": where})
	parts.sort_custom(func(a, b): return int(a["value"]) > int(b["value"]))
	clear_screen()
	var b: Control = BrokeScene.instantiate()
	add_child(b)
	screen = b
	b.scrap.connect(scrap_to_survive)
	b.back_pressed.connect(show_warehouse)
	b.start_over.connect(reset_game)
	b.setup({"cash": int(state["cash"]), "min_bet": min_bet(), "parts": parts,
		"record": "Record %d W - %d L, rep %d." % [record.x, record.y, int(state["rep"])]})


## Scrap anything to stay alive, even a part off the car.
func scrap_to_survive(uid: String) -> void:
	var inst := instance(uid)
	if inst.is_empty():
		return
	for slot in state["installed"].keys():
		if state["installed"][slot] == uid:
			state["installed"].erase(slot)
			car_stats = {}                    # the car changed
	state["cash"] = int(state["cash"]) + scrap_value(inst)
	state["inventory"].erase(inst)
	stat_add("scrapped", 1)
	save_game()
	show_broke()


## What a part fetches as scrap: price x SCRAP_RATE x (0.5 + quality).
func scrap_value(inst: Dictionary) -> int:
	var p := part_by_id(inst["part"])
	return int(round(float(p.get("price", 0)) * SCRAP_RATE * (0.5 + float(inst["quality"]))))


# ------------------------------------------------------------------ codes (testing)

## Cheat codes, for testing (Spire). The CODES screen opens from the hub by
## tapping FABA's name tape 5 times, or with the ` key (any screen but a race
## or the intro). Case and spaces don't matter. Each use is counted in
## stats["cheats"], so a save always knows it was helped.
const CODES := {
	"deeppockets": "+$10,000 cash",
	"clout": "+100 rep (opens the swap meet and the sealed crate)",
	"fullbuild": "one new copy of every part, in your spares",
	"godroll": "your next pull rolls 100% quality",
	"fixit": "repairs every damaged part, free",
	"skipnight": "skips the next race night, no rep cost",
	"rivalnight": "jumps the calendar to the next rival night",
	"beatzed": "Zed acts like you beat him: he re-tunes to your build next time",
	"memories": "unlocks every TEAM memory",
	"broke": "cash to $0 to see the BROKE screen (scrap parts there to get back)",
	"startover": "wipes the save and starts the story over (asks first)",
	"jorge": "jorge mode on / off: Faba wins every race, the other guy won't pay up, throws you a 0% part instead, and leans on his horn",
	"mute": "sound off / on",
	"heat": "the next race that finishes gets pulled over (the cops event)",
}
const CHEAT_CASH := 10000
const CHEAT_REP := 100


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_QUOTELEFT:
		return
	var in_intro := screen != null and screen.scene_file_path == IntroScene.resource_path
	if viewer == null and not in_intro:          # never mid-race or mid-story
		show_codes()


## HOW TO RACE (voice.gd TUTORIAL), then back to `after`.
func show_tutorial(after: Callable) -> void:
	var tut: Control = open_hub(TutorialScene, "tutorial")
	tut.done.connect(after)
	tut.setup(Voice.TUTORIAL)


func show_codes(message := "", confirm := "") -> void:
	var codes: Control = open_hub(CodesScene, "codes")
	codes.entered.connect(enter_code)
	codes.confirmed.connect(reset_game.bind(true))
	codes.setup(CODES, message, confirm)


func enter_code(raw: String) -> void:
	var code := raw.to_lower().replace(" ", "")
	if not CODES.has(code):
		show_codes("Nothing happened. (\"%s\" isn't a code.)" % raw.strip_edges())
		return
	if code == "startover":                  # asks first: the confirm button resets
		show_codes("This wipes the save: cash, rep, parts, the calendar, the TEAM board. The story plays again.",
			"WIPE IT")
		return
	if code == "fullbuild" and catalog.is_empty():
		show_message("PARTS", "Checking the parts shelf...")
		after_catalog = "fullbuild"           # comes back through _go("fullbuild")
		bridge.request("parts", ["parts"])
		return
	stat_add("cheats", 1)
	var msg := ""
	match code:
		"deeppockets":
			state["cash"] = int(state["cash"]) + CHEAT_CASH
			msg = "%s in the envelope." % UI.money(CHEAT_CASH)
		"clout":
			state["rep"] = int(state["rep"]) + CHEAT_REP
			msg = "+%d rep." % CHEAT_REP
		"fullbuild":
			for p in catalog["parts"]:
				add_instance(p["id"], NEW_QUALITY, true, "shop", p["effects_text"])
			msg = "%d parts, new in box, in your spares ($$$). Put them on in CAR." % catalog["parts"].size()
		"godroll":
			state["godroll"] = true
			msg = "The next pull rolls 100%."
		"fixit":
			var n := 0
			for inst in state["inventory"]:
				if inst.get("damaged", false):
					inst["damaged"] = false
					n += 1
			car_stats = {}
			msg = "Fixed %d part%s." % [n, "" if n == 1 else "s"]
		"skipnight":
			var ev := next_event()
			advance_past(ev)
			state["night"] = {}
			msg = "Skipped %s. Nobody saw a thing." % when(ev["week"], ev["day"])
		"rivalnight":
			for i in 20:                         # at most 20 nights ahead
				var ev := next_event()
				if ev["type"] == "rival":
					break
				advance_past(ev)
			state["night"] = {}
			var rv := next_event()
			msg = "Next up: %s, %s." % [rv["title"], when(rv["week"], rv["day"])]
		"beatzed":
			var r: Dictionary = state["rivals"].get(RIVAL_ID, {})
			r["retune"] = true
			state["rivals"][RIVAL_ID] = r
			msg = "Zed heard about it. He's working on the 280Z."
		"memories":
			for m in Voice.MEMORY_ORDER:
				unlock(m)
			msg = "Every memory is on the board (TEAM)."
		"broke":
			state["cash"] = 0
			save_game()
			show_broke()
			return
		"jorge":
			state["jorge"] = not state.get("jorge", false)
			msg = "Jorge mode is %s." % ("ON. Win and see what happens" if state["jorge"] else "off")
		"heat":
			state["heat"] = true
			msg = "Somebody called it in. The next race gets pulled over."
		"mute":
			state["mute"] = not state.get("mute", false)
			Sound.muted = state["mute"]
			msg = "Sound %s." % ("off" if state["mute"] else "on")
	save_game()
	show_codes(msg)


# ------------------------------------------------------------------ bridge replies

func _on_reply(tag: String, data: Dictionary) -> void:
	if not data.get("ok", false):
		var refund := ""
		if tag == "pull" and pull_paid > 0:
			# Our bug, not the player's choice: give the money back
			state["cash"] = int(state["cash"]) + pull_paid
			save_game()
			refund = "

The pull was refunded (%s)." % UI.money(pull_paid)
			pull_paid = 0
		show_message("THE SIM HIT A PROBLEM", str(data.get("error", "unknown error")) + refund,
			"BACK TO THE WAREHOUSE", show_warehouse)
		return
	match tag:
		"car_stats":
			car_stats = data
			_go(after_car_stats)
		"road_read":
			road_read = data
			show_briefing()
		"compare":                           # the DX with the part being looked at
			compare["stats"] = data
			show_car()
		"parts":
			catalog = data
			_go(after_catalog)
		"road":                              # race night, step 1: just the road
			data["event"] = event_key(next_event())
			state["night"] = data
			save_game()
			track_info = {}                  # a new night is a new road: drop the old map
			show_briefing()
		"night":                             # the opponent, matched to the locked build
			var night: Dictionary = state["night"]
			for k in data:
				if k not in ["ok", "bridge_version"]:
					night[k] = data[k]
			if data["id"] != "street":       # remember the rival's engine (he keeps it)
				state["rivals"][data["id"]] = {"condition": data["engine_condition"], "retune": false}
			save_game()
			show_briefing()
		"pull":
			on_pulled(data)
		"loot":
			var r: Dictionary = pending_race["result"]
			var inst := add_instance(data["part"], float(data["quality"]), false, "loot",
				data["effects_text"])
			r["loot"] = inst["part"]
			state["history"][-1]["loot"] = inst["part"]
			save_game()
			show_race(pending_race["replay"], r)
		"track":
			track_info = data
			show_briefing()
		"race":
			var jorge: bool = state.get("jorge", false)
			if jorge and not data["won"] and jorge_tries < JORGE_TRIES:
				jorge_tries += 1                 # jorge mode: that one didn't happen
				request_race()
				return
			var result := apply_result(data)
			if result["won"] and (jorge or randf() < LOOT_CHANCE):
				# The rival paid up in parts too: roll it before the replay starts.
				# Jorge mode: every win, and it's always a 0% part
				pending_race = {"replay": data["replay"], "result": result}
				var junk := ["--quality", str(JORGE_LOOT_Q)] if jorge else []
				bridge.request("loot", ["pull", "--source", "loot", "--seed", str(randi() % 1000000)] + junk)
			else:
				show_race(data["replay"], result)


# ------------------------------------------------------------------ self-test

var test_failures := 0     # game_test only
var test_running := false  # game_test: don't navigate


## One pass/fail line. Expected values come from hand calcs in the comments.
func check(ok: bool, what: String) -> void:
	print("GAMETEST %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		test_failures += 1


func game_test() -> void:
	## Headless end-to-end check: one full race night plus the game rules,
	## printed. Exits with code 1 if any check fails. Run with
	##   godot --headless --path godot -- --gametest
	state = new_state()
	test_running = true
	print("GAMETEST bridge: ", bridge.ready_to_use() if bridge.ready_to_use() != "" else "ok")
	print("GAMETEST migrate v1: ", migrate({"version": 1, "cash": 300, "rep": 5, "history": [], "night": {"x": 1}}))
	var ev := next_event()
	print("GAMETEST next event: %s, %s" % [when(ev["week"], ev["day"]), ev["title"]])
	# Schedule hand calc: open roads Fri + Sat every week, the rival every 2nd
	# Sunday -> weeks 1-2 hold 4 open nights and 1 rival night (4 : 1)
	var two_weeks := events_for_week(1) + events_for_week(2)
	check(two_weeks.filter(func(e): return e["type"] == "open").size() == 4
		and two_weeks.filter(func(e): return e["type"] == "rival").size() == 1
		and int(two_weeks[-1]["day"]) == 6 and int(two_weeks[3]["road"]) == 4,
		"schedule: 4 open (roads 1-4) and 1 rival (week 2, Sunday)")
	bridge.request("car_stats", ["car_stats"])
	var r: Array = await bridge.replied
	print("GAMETEST car: %s, %d hp, dyno points %d" % [r[1]["name"], r[1]["hp"], r[1]["dyno"].size()])
	bridge.request("rival", ["rival", "--rival", RIVAL_FILE, "--seed", "42"])
	r = await bridge.replied
	var card: Dictionary = r[1]
	state["night"] = card
	print("GAMETEST rival: %s (%s), %d hp, %s engine, '%s'" % [card["name"], card["car"],
		card["stats"]["hp"], card["condition"], card["driver_read"]])
	check(not card.has("posted_time"), "rival card has no posted time (head-to-head)")
	choice = {"push": "hard", "wager": 100}
	var out := ProjectSettings.globalize_path("user://replays/race.json")
	bridge.request("race", ["race", "--track", card["track"], "--push", "hard", "--seed", "9",
		"--out", out, "--opponent", card["opponent"], "--opp-seed", "9"])
	r = await bridge.replied
	var race: Dictionary = r[1]
	var result := apply_result(race)
	print("GAMETEST race: %s vs %s -> %s, cash %d, rep %d" % [
		"DNF" if race["dnf"] else "%.3f s" % race["lap_time"],
		"DNF" if race["opponent_dnf"] else "%.3f s" % race["opponent_time"],
		"NO CONTEST" if result["no_contest"] else ("WIN" if result["won"] else "LOSS"),
		state["cash"], state["rep"]])
	# Hand calc: start $200 and 0 rep; +-$100 wager; a crash also pays $150 body
	var expect_cash := 200 + (0 if race["no_contest"] else (100 if race["won"] else -100)) \
		- (150 if race["dnf"] else 0)
	check(int(state["cash"]) == maxi(expect_cash, 0), "race cash %d (expect %d)" % [state["cash"], expect_cash])
	var replay = JSON.parse_string(FileAccess.get_file_as_string(out))
	check(replay is Dictionary and replay.get("ghost") is Dictionary
		and replay["ghost"]["samples"]["t"].size() > 10, "replay carries the opponent as a ghost")
	# Why did I lose: the buckets add up to the gap (rounding: 6 buckets x 0.0005 s)
	var bd: Dictionary = result.get("breakdown", {})
	var bucket_sum := 0.0
	for g in bd.get("totals", {}).values():
		bucket_sum += float(g)
	check(not bd.is_empty() and absf(bucket_sum - float(bd["gap"])) < 0.01
		and replay["splits"] is Array and replay["splits"].size() == bd["sections"].size(),
		"breakdown saved with the result (%s, gap %+.3f s) and splits in the replay" % [
			bd.get("verdict", "?"), float(bd.get("gap", 0.0))])
	print("GAMETEST calendar after race: %s" % when(state["week"], state["day"]))
	bridge.request("parts", ["parts"])
	catalog = (await bridge.replied)[1]
	print("GAMETEST catalog: %d parts in %d slots" % [catalog["parts"].size(), catalog["slots"].size()])
	state["cash"] = 1000
	state["rep"] = 0
	shop_message = ""
	buy_part("interior_strip")
	buy_part("cams_race")                    # not a common: the counter won't sell it
	print("GAMETEST bought: %s, installed %s, cash %d" % [
		state["inventory"].map(func(i): return i["part"]), state["installed"], state["cash"]])
	state["cash"] = 1000
	do_pull("crate")                         # needs 100 rep: refused
	print("GAMETEST crate at 0 rep refused: cash still %d" % state["cash"])
	state["pity"] = {}                                   # a new game: no counters yet
	bridge.request("pull", ["pull", "--source", "junkyard", "--seed", "3"] + pity_args())
	check((await bridge.replied)[1]["ok"], "first pull of a new game (empty pity)")
	state["pity"] = {"junkyard": 2.0, "crate": 5.0}      # floats, like a loaded save
	bridge.request("pull", ["pull", "--source", "junkyard", "--seed", "3"] + pity_args())
	var pr: Dictionary = (await bridge.replied)[1]
	check(pr["ok"] and int(pr["pity"]["crate"]) == 5, "pity counters reach the bridge (%s)" % [pity_args()])
	state["pity"] = pr["pity"]
	var inst := add_instance(pr["part"], float(pr["quality"]), false, "junkyard", pr["effects_text"])
	print("GAMETEST pulled: %s (%s), quality %.2f, pity %s" % [pr["name"], pr["rarity"], pr["quality"], pr["pity"]])
	install_part(pr["slot"], inst["uid"], false)
	print("GAMETEST parts args: %s" % [parts_args()])
	bridge.request("car_stats", ["car_stats"] + parts_args())
	r = await bridge.replied
	print("GAMETEST car with parts: %d kg (stock 1112)" % r[1]["weight_kg"])
	install_part(pr["slot"], "", false)
	var cash_before := int(state["cash"])
	sell_instance(inst["uid"])
	print("GAMETEST sold spare: +%d cash" % (int(state["cash"]) - cash_before))

	# A crash, forced (a real one is a 2% roll at hard push): the consequences.
	# Hand calc: $500 - $100 wager - $150 body = $250; rep 30 - 20 = 10.
	seed(1)
	state["inventory"] = []
	var a := add_instance("interior_strip", 0.5, true, "shop")
	var b := add_instance("rsb_19", 0.5, true, "shop")
	state["installed"] = {"interior": a["uid"], "rear_sway": b["uid"]}
	state["cash"] = 500
	state["rep"] = 30
	state["night"] = card
	choice = {"push": "flat_out", "wager": 100}
	var crashed := {"won": false, "no_contest": false, "dnf": true, "crash_corner": "R3 90",
		"lap_time": 30.0, "opponent_time": 49.5, "opponent_dnf": false, "opponent_crash_corner": "",
		"push": "flat_out", "seed": 0, "mistakes": ["R3 90"]}
	var dmg: Dictionary = apply_result(crashed)["damage"]
	print("GAMETEST crash damage: damaged %s, destroyed %s" % [dmg["damaged"], dmg["destroyed"]])
	check(int(state["cash"]) == 250, "crash cash %d (expect 250)" % state["cash"])
	check(int(state["rep"]) == 10, "crash rep %d (expect 10)" % state["rep"])
	check(state["installed"].size() == 2 - dmg["destroyed"].size(), "destroyed parts leave the car")
	# Both crash = no contest: wager back, but the body bill and crash rep still hit.
	# Hand calc: $500 - $0 - $150 = $350; rep 30 - 20 = 10.
	state["inventory"] = []
	state["installed"] = {}
	state["cash"] = 500
	state["rep"] = 30
	state["night"] = card
	crashed["no_contest"] = true
	crashed["opponent_dnf"] = true
	var nc := apply_result(crashed)
	check(int(state["cash"]) == 350 and int(state["rep"]) == 10 and not nc["won"],
		"no contest: cash %d (expect 350), rep %d (expect 10)" % [state["cash"], state["rep"]])
	# Rep hand calc: a rival win is +15 and makes him re-tune; a street win is +4.
	var won_race := crashed.duplicate()
	won_race.merge({"won": true, "no_contest": false, "dnf": false, "opponent_dnf": false}, true)
	state["rep"] = 0
	state["rivals"] = {}
	state["night"] = card
	apply_result(won_race)
	check(int(state["rep"]) == 15 and state["rivals"][card["id"]].get("retune", false),
		"rival win: rep %d (expect 15), he re-tunes next time" % state["rep"])
	check(rival_args("1").has("--retune"), "the next rival card asks for a re-tune")
	var street_card := card.duplicate()
	street_card["id"] = "street"
	state["night"] = street_card
	apply_result(won_race)
	check(int(state["rep"]) == 19, "street win: rep %d (expect 15 + 4 = 19)" % state["rep"])
	# Jorge mode: a win, but he doesn't pay (the rep still counts)
	state["jorge"] = true
	state["night"] = street_card
	var cash_jorge := int(state["cash"])
	var stiffed := apply_result(won_race)
	check(int(state["cash"]) == cash_jorge and stiffed["stiffed"] and int(stiffed["cash_change"]) == 0
		and int(state["rep"]) == 23, "jorge mode: won, cash %d (expect %d, unpaid), rep %d (expect 23)" % [
		state["cash"], cash_jorge, state["rep"]])
	# ...and it's rigged: his motor at JORGE_CONDITION of itself. Through the
	# real sim, Faba (hard push) should beat him nearly every run on his own,
	# before the re-runs (request_race) catch the rest (a crash)
	var jorge_wins := 0
	for k in 5:
		bridge.request("race", ["race", "--track", card["track"], "--push", "hard", "--seed", str(100 + k),
			"--out", out, "--opponent", card["opponent"], "--opp-seed", str(200 + k),
			"--opp-condition", str(float(card["engine_condition"]) * JORGE_CONDITION)])
		jorge_wins += 1 if (await bridge.replied)[1]["won"] else 0
	check(jorge_wins >= 4, "jorge mode: Faba beat the down-on-power Zed %d of 5 (expect 4+; re-runs catch the rest)" % jorge_wins)
	state["jorge"] = false
	# The cops ("heat" forces it): a win pays nothing, and the fine is 3 of
	# tonight's minimum bets. Hand calc: the calendar's past rival nights here,
	# min bet $500 -> fine $1500, from $5000 -> $3500
	state["night"] = street_card
	state["cash"] = 5000
	state["heat"] = true
	var cited := apply_result(won_race)
	var fine := COPS_FINE_MINS * int(cited["min_bet"])
	check(cited.has("cops") and int(cited["cash_change"]) == 0 and int(state["cash"]) == 5000 - fine
		and not state.has("heat"), "cops: pulled over after a win, no winnings, fine $%d, cash %d (expect %d)" % [
		fine, state["cash"], 5000 - fine])
	state["cash"] = 100                         # ...and a fine never takes cash below $0
	state["heat"] = true
	state["night"] = street_card
	apply_result(won_race)
	check(int(state["cash"]) == 0, "cops: the fine stops at $0 (cash %d)" % state["cash"])
	# A damaged part stays in its slot but is off the car until repaired.
	# Hand calc: rsb_19 is $320, repair 30% = $96, from $500 over tonight's minimum bet.
	var c := add_instance("rsb_19", 0.5, true, "shop")
	state["installed"] = {"rear_sway": c["uid"]}
	c["damaged"] = true
	check(parts_args().is_empty(), "a damaged part is off the car")
	state["cash"] = min_bet() + 500
	repair_instance(c["uid"])
	check(int(state["cash"]) == min_bet() + 404 and not c["damaged"] and parts_args().size() == 2,
		"repair: cash %d (expect %d), back on the car %s" % [state["cash"], min_bet() + 404, parts_args()])
	print("GAMETEST migrate v3: %s" % [migrate({"version": 3, "cash": 1, "rep": 0, "week": 1, "day": 0,
		"history": [], "night": {}, "owned_parts": ["rsb_19"], "installed": {"rear_sway": "rsb_19"}})])
	bridge.request("night", ["street", "--road", "3", "--seed", "8", "--tune"])
	r = await bridge.replied
	print("GAMETEST open road 3 (tuned): %s in a %s (%d hp, condition %.3f) on %s" % [r[1]["name"],
		r[1]["car"], r[1]["stats"]["hp"], r[1]["engine_condition"], r[1]["style"]])
	check(r[1].has("opponent") and not r[1].has("posted_time") and r[1]["tuned"],
		"street night is a tuned stat card")
	var old_night := migrate({"version": 4, "cash": 1, "rep": 0, "week": 1, "day": 0, "history": [],
		"installed": {}, "inventory": [], "pity": {}, "next_uid": 1,
		"night": {"name": "Zed", "posted_time": 49.6, "event": "1-4"}})
	check(old_night["night"].is_empty() and old_night["version"] == SAVE_VERSION,
		"v4 -> current redraws an old posted-time night")
	var v5 := migrate({"version": 5, "cash": 1, "rep": 0, "week": 2, "day": 4, "history": [],
		"installed": {}, "inventory": [], "pity": {}, "next_uid": 1, "night": {"name": "Zed", "event": "2-4"}})
	check(v5["night"].is_empty() and v5.has("rivals") and v5.has("stats") and v5["version"] == 6,
		"v5 -> v6: new schedule redraws the night, adds rival progress + team stats")
	print("GAMETEST migrate v2: %s" % [migrate({"version": 2, "cash": 1, "rep": 0, "week": 1, "day": 0, "history": [], "night": {}}).keys()])
	state["rep"] = 10
	skip_night()
	print("GAMETEST skip with 10 rep: rep %d, %s (blocked)" % [state["rep"], when(state["week"], state["day"])])
	state["rep"] = 60
	skip_night()
	print("GAMETEST skip with 60 rep: rep %d, %s" % [state["rep"], when(state["week"], state["day"])])

	# Minimum bet: $100 until a rival night is behind you, +$100 per rival
	# night after that; max = 5x. Hand calc: 2 rival nights -> $300 / $1500.
	var saved_history: Array = state["history"]
	state["history"] = [{"rival_night": false}]
	check(min_bet() == 100 and max_bet() == 500, "min bet $%d, max $%d before any rival night (expect 100 / 500)" % [min_bet(), max_bet()])
	state["history"] = [{"rival_night": true}, {"rival_night": false}, {"rival_night": true, "skipped": true}]
	check(min_bet() == 300 and max_bet() == 1500, "min bet $%d, max $%d after 2 rival nights (expect 300 / 1500)" % [min_bet(), max_bet()])
	state["history"] = saved_history

	# BROKE: scrap a part off the car. Hand calc: rsb_19 $320 x 0.25 x (0.5 + 0.5) = $80
	var scrap_me := add_instance("rsb_19", 0.5, true, "shop")
	state["installed"] = {"rear_sway": scrap_me["uid"]}
	state["cash"] = 0
	scrap_to_survive(scrap_me["uid"])
	check(int(state["cash"]) == 80 and state["installed"].is_empty() and instance(scrap_me["uid"]).is_empty(),
		"broke: scrapped the sway bar off the car for $%d (expect 80)" % state["cash"])
	# Scrap them all: two spares at $80 each = $160; the one on the car stays
	# (on a shelf of its own: the other tests' parts are put back after)
	var saved_inventory: Array = state["inventory"]
	var saved_installed: Dictionary = state["installed"]
	state["inventory"] = []
	var keep := add_instance("rsb_19", 0.5, true, "shop")
	state["installed"] = {"rear_sway": keep["uid"]}
	add_instance("rsb_19", 0.5, true, "shop")
	add_instance("rsb_19", 0.5, true, "shop")
	state["cash"] = 0
	var inv_before: int = state["inventory"].size()
	scrap_all_spares()
	check(int(state["cash"]) == 160 and instance(keep["uid"]).size() > 0 and state["inventory"].size() == inv_before - 2,
		"scrap them all: two spares for $%d (expect 160), the one on the car kept" % state["cash"])
	state["inventory"] = saved_inventory
	state["installed"] = saved_installed
	state["cash"] = 500

	# Parts comparison: the what-if build is sent to the sim, the car itself doesn't change
	var what_if := add_instance("intake_cold_air", 0.62, true, "shop")
	var before := parts_args()
	var trial_build: Dictionary = state["installed"].duplicate()
	trial_build["intake"] = what_if["uid"]
	check("intake_cold_air@0.6200" in ",".join(parts_args(trial_build)) and parts_args() == before,
		"comparison: the what-if build has the intake, the car doesn't")

	# Race night order (Spire): the road, then the build is locked, then the opponent
	state["night"] = {}
	state["installed"] = {}
	var tonight := next_event()
	bridge.request("road", ["road", "--road", str(tonight.get("road", 1))] if tonight["type"] == "open"
		else ["road", "--rival", RIVAL_FILE])
	var road_card: Dictionary = (await bridge.replied)[1]
	check(road_card["ok"] and not road_card.has("opponent"), "night step 1: the road (%s), no opponent yet" % road_card["track"])
	state["night"] = road_card
	state["night"]["event"] = event_key(tonight)
	check(not build_locked(), "the build is open while scouting")
	var strip_me := add_instance("rsb_19", 0.5, true, "shop")
	state["installed"] = {"rear_sway": strip_me["uid"]}
	check(strip_all() and state["installed"].is_empty() and instance(strip_me["uid"]).size() > 0,
		"take it all off: the car's stock, the part's back in the spares")
	# The body shop: a buy goes on the car and into the look; never below the buy-in.
	# Hand calc: min bet + $700 cash, Milano Red $700 -> exactly the buy-in left
	state["cash"] = min_bet() + 700
	state.erase("look")
	buy_look("paint_milano")
	buy_look("battle_tape")                               # $15: would cross the buy-in
	check(int(state["cash"]) == min_bet() and "look:paint_milano" in car_look()
		and not "battle_tape" in look_state()["owned"],
		"body shop: Milano Red bought and worn, cash at the buy-in (%d), the battle tape refused" % state["cash"])
	state.erase("look")
	lock_build()
	var lock_part := add_instance("rsb_24", 0.5, true, "shop")
	install_part("rear_sway", lock_part["uid"], false)
	check(build_locked() and state["installed"].is_empty() and state["night"]["parts"] == [] and not strip_all(),
		"locked in: a part can't go on until the night's over")
	state["night"] = {}

	# Codes (testing). Case and spaces don't matter; unknown codes do nothing.
	var cash0 := int(state["cash"])
	var cheats0 := int(state["stats"].get("cheats", 0))
	enter_code("Deep Pockets")
	check(int(state["cash"]) == cash0 + CHEAT_CASH, "code deeppockets: cash %d (expect %d)" % [state["cash"], cash0 + CHEAT_CASH])
	enter_code("nope")
	check(int(state["cash"]) == cash0 + CHEAT_CASH and int(state["stats"]["cheats"]) == cheats0 + 1,
		"unknown code changes nothing")
	enter_code("rivalnight")
	check(next_event()["type"] == "rival" and state["night"].is_empty(), "code rivalnight: next up is %s" % next_event()["title"])
	c["damaged"] = true
	enter_code("fixit")
	check(not c["damaged"], "code fixit repairs for free")
	var inv0: int = state["inventory"].size()
	enter_code("fullbuild")
	check(state["inventory"].size() == inv0 + catalog["parts"].size(), "code fullbuild: +%d parts" % catalog["parts"].size())
	enter_code("godroll")
	check(state.get("godroll", false), "code godroll: the next pull is forced to 100% (bridge --quality, tests/test_bridge.py)")
	check(int(state["stats"]["cheats"]) == cheats0 + 5, "codes are counted (%d)" % state["stats"]["cheats"])
	# Settings: the parked car defaults on; a flip turns it off and is saved in state
	state.erase("settings")
	var parked_default := setting("parked_car")
	state["settings"] = {"parked_car": false}
	check(parked_default and not setting("parked_car") and setting("sound") == not state.get("mute", false),
		"settings: parked car on by default, off once flipped; sound = the mute code")
	state.erase("settings")
	print("GAMETEST OK" if test_failures == 0 else "GAMETEST FAILED: %d checks" % test_failures)
	get_tree().quit(0 if test_failures == 0 else 1)


## The stills skip through the intro; it may have ended on its own already.
func intro_next() -> void:
	if screen != null and screen.has_method("next_slide"):
		screen.next_slide()


## Stills of every screen for review (needs a display, not --headless):
##   godot --path godot -- --gameshots=<folder>
func game_shots(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	state = new_state()
	show_intro()
	await get_tree().create_timer(0.5).timeout
	await snap(folder, "0a_intro")
	for i in 4:                                   # to "one corner too hot": the tape glitching
		intro_next()
	await get_tree().create_timer(0.8).timeout
	await snap(folder, "0b_intro_crash")
	for i in 3:                                   # past the tape: Faba's texts
		intro_next()
	await get_tree().create_timer(2.5).timeout
	await snap(folder, "0c_intro_texts")
	intro_next()
	await get_tree().create_timer(2.0).timeout
	intro_next()
	await get_tree().create_timer(8.0).timeout
	await snap(folder, "0d_intro_texts_late")
	bridge.request("car_stats", ["car_stats"])
	car_stats = (await bridge.replied)[1]
	show_warehouse()
	await snap(folder, "1_warehouse")
	bridge.request("parts", ["parts"])
	catalog = (await bridge.replied)[1]
	state["cash"] = 900
	state["rep"] = 40
	var a := add_instance("interior_strip", 0.5, true, "shop", part_by_id("interior_strip")["effects_text"])
	var b := add_instance("rsb_19", 0.5, true, "shop", part_by_id("rsb_19")["effects_text"])
	add_instance("shifter_short", 0.71, true, "junkyard", ["shift time 0.40 s -> 0.31 s"])
	add_instance("cams_street", 0.62, false, "swap_meet", ["+5.9 hp peak"])
	state["installed"] = {"interior": a["uid"], "rear_sway": b["uid"]}
	shop_message = "Bought and installed: Rear sway bar 19 mm."
	show_shop()
	await snap(folder, "1a_shop")
	bridge.request("car_stats", ["car_stats"] + parts_args())
	car_stats = (await bridge.replied)[1]
	show_car()
	await snap(folder, "1b_car")
	hub_content.get_node("%Scroll").scroll_vertical = 900
	await snap(folder, "1b_car_parts")
	look_state()["owned"] = ["paint_milano", "banner"]          # the body shop: two owned, one on trial
	look_state()["worn"] = {"paint": "paint_milano", "banner": "banner"}
	show_bodyshop()
	hub_content.try_on("wing_duck")
	await snap(folder, "1c_bodyshop")
	state.erase("look")
	var trial: Dictionary = state["installed"].duplicate()     # the swap comparison
	var spare_cams := add_instance("intake_cold_air", 0.62, true, "shop", part_by_id("intake_cold_air")["effects_text"])
	trial["intake"] = spare_cams["uid"]
	trial.erase("interior")                                   # and one that's worse: stock interior
	bridge.request("car_stats", ["car_stats"] + parts_args(trial))
	compare = {"slot": "intake", "uid": spare_cams["uid"], "stats": (await bridge.replied)[1]}
	show_car()
	await snap(folder, "1b_car_compare")
	compare = {}
	bridge.request("pull", ["pull", "--source", "swap_meet", "--seed", "4"])
	var pr: Dictionary = (await bridge.replied)[1]
	var pulled := add_instance(pr["part"], float(pr["quality"]), false, "swap_meet", pr["effects_text"])
	show_reveal(pulled)
	await snap(folder, "1d_pull")
	screen.open_box()
	await get_tree().create_timer(0.8).timeout
	await snap(folder, "1d_pull_open")
	screen.dyno_pressed.emit()
	await get_tree().create_timer(2.0).timeout
	await snap(folder, "1e_dyno_reveal")
	var great := pulled.duplicate()                # stills only: a great roll gets a margin note
	great["quality"] = 0.86
	show_reveal(great, "sheet")
	await snap(folder, "1e_dyno_great")
	state["inventory"].erase(great)
	state["cash"] = 250
	state["rep"] = 0
	state["inventory"] = []
	state["installed"] = {}
	state["history"] = [{"when": "FRI, WEEK 1", "rival": "Zed", "won": true, "cash_change": 150},
		{"when": "SAT, WEEK 1", "rival": "Zed", "won": false, "cash_change": -100}]
	state["week"] = 2
	state["day"] = 2
	show_calendar()
	await snap(folder, "1c_calendar")
	state["history"] = [state["history"][0]]      # last race a win: the rival gets the finger
	show_calendar()
	await snap(folder, "1c_calendar_win")
	state["stats"] = {"pulls": 3, "spent": 900, "repairs": 1, "biggest_bet": 150,
		"best_roll": {"name": "Cold air intake", "q": 0.86},
		"memories": {"first_win": "FRI, WEEK 1", "big_bet": "SAT, WEEK 1"}}
	state["history"][0]["rival_night"] = true
	state["history"][0]["track"] = "data/tracks/test_track.txt"
	state["history"][0]["time"] = 49.62
	show_team()
	await snap(folder, "1f_team")
	hub_content.get_node("%Scroll").scroll_vertical = 2000
	await snap(folder, "1f_team_memories")
	state["stats"] = {}
	state["history"] = []
	state["week"] = 1
	state["day"] = 0
	bridge.request("road", ["road", "--rival", RIVAL_FILE])
	state["night"] = (await bridge.replied)[1]
	state["night"]["event"] = event_key(next_event())
	bridge.request("track", ["track", "--track", state["night"]["track"]])
	track_info = (await bridge.replied)[1]
	bridge.request("car_stats", ["car_stats"])        # parts were cleared above: stock card
	car_stats = (await bridge.replied)[1]
	bridge.request("road_read", ["road_read", "--track", state["night"]["track"]])
	road_read = (await bridge.replied)[1]
	show_tutorial(func(): pass)                              # HOW TO RACE: page 1 and the push page
	await snap(folder, "2a_tutorial")
	hub_content.turn(3)
	await snap(folder, "2a_tutorial_push")
	state["tutorial_seen"] = true
	show_scout()
	await snap(folder, "2a_road")
	hub_content.get_node("%Scroll").scroll_vertical = 500
	await snap(folder, "2a_road_read")
	bridge.request("rival", ["rival", "--rival", RIVAL_FILE, "--seed", "3"])
	state["night"].merge((await bridge.replied)[1], true)
	state["night"]["parts"] = []
	choice = {"push": "hard", "wager": 150}
	show_meeting()
	await snap(folder, "2_meeting")
	var sc: ScrollContainer = screen.get_node("%Scroll")
	sc.scroll_vertical = 2000
	await snap(folder, "2_meeting_bet")
	screen.set_wager(3500)                                   # over $2000: stacks, not a fan
	await snap(folder, "2_meeting_stacks")
	screen.set_wager(150)
	screen.open_map(true)                                    # the road, full screen
	await snap(folder, "2_meeting_map")
	screen.open_map(false)
	var out := ProjectSettings.globalize_path("user://replays/shots.json")
	bridge.request("race", ["race", "--track", state["night"]["track"], "--push", "hard", "--seed", "21",
		"--out", out, "--opponent", state["night"]["opponent"], "--opp-seed", "21",
		"--location", str(state["night"].get("location", "canyon"))])
	var r: Dictionary = (await bridge.replied)[1]
	var result := apply_result(r)
	show_race(out, result)
	await get_tree().process_frame
	viewer.countdown = viewer.COUNTDOWN_S - 0.7                  # rolling up, hazards on
	await snap(folder, "5_race_rollup")
	viewer.countdown = viewer.COUNTDOWN_S - 2.0                  # the flagger: "3"
	await snap(folder, "5_race_count")
	viewer.countdown = 0.0
	await jump_replay(viewer.lap_time * 0.5)
	await snap(folder, "5_race_mid")
	await jump_replay(minf(viewer.lap_time, viewer.end_time) - 0.2)   # slow-mo at the line
	await snap(folder, "5_race_finishline")
	await jump_replay(viewer.end_time)
	await snap(folder, "5_race_finish")
	var first_split: Dictionary = result["breakdown"]["sections"][0]        # the split caption
	await jump_replay(maxf(float(first_split["t_me"]), float(first_split["t_them"])) + 0.5)
	await snap(folder, "5_race_split")
	show_results(result)
	await get_tree().create_timer(1.0).timeout                # the stamp, then the seal
	await snap(folder, "6_results")
	var rs: ScrollContainer = screen.find_child("Scroll", true, false)
	rs.scroll_vertical = 520
	await snap(folder, "6_results_why")
	var stiffed := result.duplicate()                       # jorge mode: he won't pay
	stiffed.merge({"won": true, "no_contest": false, "stiffed": true, "cash_change": 0}, true)
	show_results(stiffed)
	await snap(folder, "6_results_jorge")
	show_codes("$10,000 in the envelope.")
	await snap(folder, "7_codes")
	state["cash"] = 40                                       # BROKE: scrap your way back
	var keep := add_instance("interior_strip", 0.6, true, "shop")
	add_instance("header_421", 0.4, true, "junkyard")
	add_instance("cams_street", 0.7, false, "swap_meet")
	state["installed"] = {"interior": keep["uid"]}
	show_broke()
	await snap(folder, "8_broke")
	state["cash"] = 900
	state["rep"] = 130
	show_shop()                                              # the four pull flyers
	await snap(folder, "9_shop_pulls")
	get_tree().quit()


## Stills: jump the replay clock, move the cars there, then snap the camera
## onto them (it would otherwise still be gliding over).
func jump_replay(tt: float) -> void:
	viewer.jump_to(tt)                       # the split-screen panes too
	await get_tree().process_frame


func snap(folder: String, name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [folder, name])
	print("saved ", name)
