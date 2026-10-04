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
const MeetingScene := preload("res://screens/meeting.tscn")
const ResultsScene := preload("res://screens/results.tscn")
const ShellScene := preload("res://screens/shell.tscn")
const GritShader := preload("res://widgets/grit.gdshader")
const LOCATIONS := {
	"warehouse": "THE WAREHOUSE",       # Dymo label-maker strips
	"car": "BAY 1 // THE DX",
	"calendar": "THE WHITEBOARD",
	"shop": "PARTS $$$",
}

const SAVE_PATH := "user://save.json"
const TEST_SAVE_PATH := "user://test_save.json"   # --gametest / --gameshots: never touch the real save
const SAVE_VERSION := 5
const START_CASH := 250
const MIN_BUY_IN := 100
const WAGER_STEP := 10
const REP_WIN := 10
const SKIP_REP_COST := 5 * REP_WIN   # chicken-out fee: five wins' worth of rep
const LOOT_CHANCE := 0.05            # chance a win also drops an unopened part ("loot" pull)
const SCRAP_RATE := 0.25             # selling a spare: price x rate x (0.5 + quality)
const NEW_QUALITY := 0.5             # shop parts are new in box: exactly the catalog spec
const REP_LOSS := -5                 # every loss costs rep (half a win)
const REP_CRASH := -20               # putting it in the trees costs more
const BODY_REPAIR := 150             # tow + body work after any crash
const DAMAGE_CHANCE := 0.40          # per installed part, on a crash
const DESTROY_CHANCE := 0.10         # per installed part, on a crash
const REPAIR_RATE := 0.30            # repairing a damaged part: 30% of its price
const RIVAL_FILE := "data/rivals/zed_280z.json"
const PUSH_ORDER := ["safe", "normal", "hard", "flat_out"]
const RARITY_COLORS := {
	"common": Color(0.75, 0.76, 0.8), "rare": Color(0.35, 0.6, 1.0),
	"epic": Color(0.72, 0.42, 1.0), "legendary": Color(1.0, 0.78, 0.25)}

# Calendar: a week is 7 days; race nights fall on these days (0 = Monday)
const DAY_NAMES := ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
const RACE_DAYS := [4, 5]        # Friday and Saturday nights

var save_path := SAVE_PATH
var state := {}            # saved: cash, rep, week, day, history, night, intro_seen
var car_stats := {}        # bridge replies, cached for the session
var track_info := {}
var catalog := {}          # bridge "parts" reply (slots + parts with exact effects)
var shop_message := ""
var pending_race := {}     # race reply + result, held while a loot pull resolves
var pull_paid := 0         # price of the pull in flight: refunded if the sim fails
var bridge: Node
var screen: Control        # current UI screen (the shell while in the hub)
var shell: Control         # persistent hub shell (top rail, ribbon, bottom nav)
var hub_content: Control   # the hub screen currently inside the shell
var viewer: Node           # replay viewer while racing
var choice := {"push": "normal", "wager": MIN_BUY_IN}
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
		"inventory": [], "installed": {}, "pity": {}, "next_uid": 1}


func load_game() -> void:
	state = new_state()
	if not FileAccess.file_exists(save_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
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
	data["version"] = v
	return data


func save_game() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "  "))


func reset_game() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
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
		add_child(shell)
		shell.go.connect(_go)
		screen = shell
	shell.set_stats(int(state["cash"]), int(state["rep"]), MIN_BUY_IN)
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
		"race":
			show_briefing()


func common_info() -> Dictionary:
	return {"cash": int(state["cash"]), "rep": int(state["rep"]), "min_buy_in": MIN_BUY_IN}


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
	if state["cash"] < MIN_BUY_IN:
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
	info["min_buy_in_text"] = UI.money(MIN_BUY_IN)
	info["parts"] = installed_part_ids()
	info["caption"] = "PCH turnout, wk %d. %s" % [int(state["week"]), home_caption(info["parts"].size())]
	open_hub(WarehouseScene, "warehouse").setup(info)


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
	var info := common_info()
	info["parts_on"] = installed_part_ids()
	car.setup(info, car_stats,
		{"slots": catalog["slots"], "options": options, "installed": state["installed"]})


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
	shop.repair.connect(repair_instance)
	shop.reveal.connect(func(uid): show_reveal(instance(uid), "dyno"))
	shop.setup(common_info(), catalog, state["inventory"], state["installed"],
		state["pity"], shop_message)
	shop_message = ""


## Installed parts for every sim call, as id@quality: the car being simulated
## is the exact car in the warehouse, rolls included.
func parts_args() -> Array:
	var entries := []
	for slot in state["installed"]:
		var inst := instance(state["installed"][slot])
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


func can_spend(amount: int) -> bool:
	## The game never lets you spend below the race buy-in (soft-lock guard).
	return int(state["cash"]) - amount >= MIN_BUY_IN


## The counter sells commons, new in box (exactly the catalog spec).
func buy_part(id: String) -> void:
	var p := part_by_id(id)
	if p.is_empty() or p["rarity"] != "common":
		return
	if not can_spend(int(p["price"])):
		shop_message = "Can't: that would leave less than the %s buy-in." % UI.money(MIN_BUY_IN)
		show_shop()
		return
	state["cash"] = int(state["cash"]) - int(p["price"])
	var inst := add_instance(id, NEW_QUALITY, true, "shop", p["effects_text"])
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
		shop_message = "Can't: that would leave less than the %s buy-in." % UI.money(MIN_BUY_IN)
		show_shop()
		return
	state["cash"] = int(state["cash"]) - int(src["price"])
	pull_paid = int(src["price"])
	save_game()                                   # paid: a crash or quit can't refund it
	show_message("PULLING", "%s..." % src["name"])
	bridge.request("pull", ["pull", "--source", source, "--seed", str(randi() % 1000000)]
		+ pity_args())


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
	r.setup({"from": src_name, "rarity": p["rarity"], "rarity_color": RARITY_COLORS[p["rarity"]],
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
		shop_message = "Can't: the repair would leave less than the %s buy-in." % UI.money(MIN_BUY_IN)
		show_shop()
		return
	state["cash"] = int(state["cash"]) - cost
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
	var value := int(round(float(p["price"]) * SCRAP_RATE * (0.5 + float(inst["quality"]))))
	state["cash"] = int(state["cash"]) + value
	state["inventory"].erase(inst)
	save_game()
	shop_message = "Sold %s for %s." % [p["name"], UI.money(value)]
	show_shop()


## Swap what's in a slot ("" = back to stock). The car changed, so its stats
## are stale.
func install_part(slot: String, uid: String, refresh := true) -> void:
	if uid == "":
		state["installed"].erase(slot)
	else:
		state["installed"][slot] = uid
	car_stats = {}
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
			past.append([r.get("when", "-"), "vs %s" % r["rival"], "%s  %d rep" % [Voice.BOARD_SKIPPED, int(r["rep_change"])]])
		else:
			past.append([r.get("when", "-"), "vs %s" % r["rival"],
				"%s  %+d" % ["W" if r["won"] else "L", int(r["cash_change"])]])
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


func show_briefing() -> void:
	var ev := next_event()
	# A saved night belongs to one calendar event; a stale one gets redrawn
	if not state["night"].is_empty() and state["night"].get("event") != event_key(ev):
		state["night"] = {}
	# Draw the night's opponent once and save it (no rerolling by restarting)
	if state["night"].is_empty():
		show_message("WORD ON THE STREET", "Finding out who's running tonight.")
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
	if car_stats.is_empty():
		show_message("SIZING UP", "Putting both cars side by side.")
		after_car_stats = "race"
		bridge.request("car_stats", ["car_stats"] + parts_args())
		return
	if catalog.is_empty():
		after_catalog = "race"
		bridge.request("parts", ["parts"])
		return
	show_meeting()


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
	var cash := int(state["cash"])
	choice["wager"] = clampi(int(choice["wager"]), MIN_BUY_IN, cash)
	m.setup({
		"where": "%s // %s" % [when(ev["week"], ev["day"]).replace(",", ""),
			"%s'S HOME ROAD" % str(night["name"]).to_upper() if rival_night else "OPEN ROAD"],
		"rival_night": rival_night,
		"opponent_car": night["car"], "faba_parts": installed_part_ids(),
		"road_info": "%s  /  %d m, %d corners" % [night["club"], int(track_info["length"]),
			track_info["corners"].size()],
		"track": track_info, "mine": car_stats, "theirs": night["stats"],
		"their_name": night["name"],
		"their_car_line": "%s (%s engine)" % [night["car"], night["condition"]],
		"word": night["driver_read"],
		"push": choice["push"], "push_order": PUSH_ORDER, "push_risk": PUSH_TALK,
		"wager": choice["wager"], "cash": cash, "min_buy_in": MIN_BUY_IN, "wager_step": WAGER_STEP,
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
		"won": false, "skipped": true, "cash_change": 0, "rep_change": -SKIP_REP_COST})
	advance_past(ev)
	state["night"] = {}
	save_game()
	show_warehouse()


func send_it() -> void:
	show_message("LIGHTS OUT", "Faba lines up the DX next to %s's %s.\n%s on the line, %s push." % [
		state["night"]["name"], state["night"]["car"], UI.money(choice["wager"]),
		str(choice["push"]).replace("_", " ")])
	var out := ProjectSettings.globalize_path("user://replays/race.json")
	bridge.request("race", ["race", "--track", state["night"]["track"], "--push", choice["push"],
		"--seed", str(randi() % 1000000), "--out", out,
		"--opponent", state["night"]["opponent"], "--opp-seed", str(randi() % 1000000)] + parts_args())


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
	var rep_change := REP_WIN if won else (REP_CRASH if r["dnf"] else REP_LOSS)
	var result := {
		"when": when(ev["week"], ev["day"]),
		"rival": night["name"], "rival_car": night["car"],
		"time": r["lap_time"], "dnf": r["dnf"], "crash_corner": r["crash_corner"],
		"opponent_time": r["opponent_time"], "opponent_dnf": r["opponent_dnf"],
		"opponent_crash_corner": r["opponent_crash_corner"],
		"won": won, "no_contest": no_contest, "push": r["push"], "seed": r["seed"],
		"wager": wager, "cash_change": cash_change, "rep_change": rep_change,
		"mistakes": r["mistakes"], "parts": parts_args(), "loot": "", "damage": {}}
	state["cash"] = int(state["cash"]) + cash_change
	state["rep"] = maxi(int(state["rep"]) + rep_change, 0)
	if r["dnf"]:
		result["damage"] = crash_damage()
		car_stats = {}                   # the car changed (parts damaged or gone)
	state["history"].append(result)
	state["night"] = {}
	advance_past(ev)
	save_game()
	return result


func show_race(replay_path: String, result: Dictionary) -> void:
	clear_screen()
	viewer = Viewer.new()
	viewer.replay_path = replay_path        # the opponent rides along as the replay's ghost
	viewer.embedded = true
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
	r.setup(result, {"cash": int(state["cash"]), "rep": int(state["rep"]),
		"faba_parts": installed_part_ids(), "loot_text": loot_text})


func show_broke() -> void:
	var record := wins_losses()
	show_message(Voice.BROKE.to_upper(),
		"%s left. You can't cover the %s buy-in.\n\nRecord %d W - %d L, rep %d.\n\nThe warehouse goes quiet. (Pink slips come later.)" % [
			UI.money(state["cash"]), UI.money(MIN_BUY_IN), record.x, record.y, int(state["rep"])],
		"START OVER", reset_game)


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
		"parts":
			catalog = data
			_go(after_catalog)
		"night":
			data["event"] = event_key(next_event())
			state["night"] = data
			save_game()
			track_info = {}            # a new night can be a new road: drop the old map
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
			var result := apply_result(data)
			if result["won"] and randf() < LOOT_CHANCE:
				# The rival paid up in parts too: roll it before the replay starts
				pending_race = {"replay": data["replay"], "result": result}
				bridge.request("loot", ["pull", "--source", "loot", "--seed", str(randi() % 1000000)])
			else:
				show_race(data["replay"], result)


# ------------------------------------------------------------------ self-test

var test_failures := 0     # game_test only


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
	print("GAMETEST bridge: ", bridge.ready_to_use() if bridge.ready_to_use() != "" else "ok")
	print("GAMETEST migrate v1: ", migrate({"version": 1, "cash": 300, "rep": 5, "history": [], "night": {"x": 1}}))
	var ev := next_event()
	print("GAMETEST next event: %s, %s" % [when(ev["week"], ev["day"]), ev["title"]])
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
	# Hand calc: start $250 and 0 rep; +-$100 wager; a crash also pays $150 body
	var expect_cash := 250 + (0 if race["no_contest"] else (100 if race["won"] else -100)) \
		- (150 if race["dnf"] else 0)
	check(int(state["cash"]) == maxi(expect_cash, 0), "race cash %d (expect %d)" % [state["cash"], expect_cash])
	var replay = JSON.parse_string(FileAccess.get_file_as_string(out))
	check(replay is Dictionary and replay.get("ghost") is Dictionary
		and replay["ghost"]["samples"]["t"].size() > 10, "replay carries the opponent as a ghost")
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
	# A damaged part stays in its slot but is off the car until repaired.
	# Hand calc: rsb_19 is $180, repair 30% = $54: $500 -> $446.
	var c := add_instance("rsb_19", 0.5, true, "shop")
	state["installed"] = {"rear_sway": c["uid"]}
	c["damaged"] = true
	check(parts_args().is_empty(), "a damaged part is off the car")
	state["cash"] = 500
	repair_instance(c["uid"])
	check(int(state["cash"]) == 446 and not c["damaged"] and parts_args().size() == 2,
		"repair: cash %d (expect 446), back on the car %s" % [state["cash"], parts_args()])
	print("GAMETEST migrate v3: %s" % [migrate({"version": 3, "cash": 1, "rep": 0, "week": 1, "day": 0,
		"history": [], "night": {}, "owned_parts": ["rsb_19"], "installed": {"rear_sway": "rsb_19"}})])
	bridge.request("night", ["street", "--week", "3", "--seed", "8"])
	r = await bridge.replied
	print("GAMETEST open road week 3: %s in a %s (%d hp) on %s" % [r[1]["name"], r[1]["car"],
		r[1]["stats"]["hp"], r[1]["style"]])
	check(r[1].has("opponent") and not r[1].has("posted_time"), "street night is a stat card")
	var old_night := migrate({"version": 4, "cash": 1, "rep": 0, "week": 1, "day": 0, "history": [],
		"installed": {}, "inventory": [], "pity": {}, "next_uid": 1,
		"night": {"name": "Zed", "posted_time": 49.6, "event": "1-4"}})
	check(old_night["night"].is_empty() and old_night["version"] == 5, "v4 -> v5 redraws an old posted-time night")
	print("GAMETEST migrate v2: %s" % [migrate({"version": 2, "cash": 1, "rep": 0, "week": 1, "day": 0, "history": [], "night": {}}).keys()])
	state["rep"] = 10
	skip_night()
	print("GAMETEST skip with 10 rep: rep %d, %s (blocked)" % [state["rep"], when(state["week"], state["day"])])
	state["rep"] = 60
	skip_night()
	print("GAMETEST skip with 60 rep: rep %d, %s" % [state["rep"], when(state["week"], state["day"])])
	print("GAMETEST OK" if test_failures == 0 else "GAMETEST FAILED: %d checks" % test_failures)
	get_tree().quit(0 if test_failures == 0 else 1)


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
	state["history"] = []
	state["week"] = 1
	state["day"] = 0
	bridge.request("rival", ["rival", "--rival", RIVAL_FILE, "--seed", "3"])
	state["night"] = (await bridge.replied)[1]
	bridge.request("track", ["track", "--track", state["night"]["track"]])
	track_info = (await bridge.replied)[1]
	bridge.request("car_stats", ["car_stats"])        # parts were cleared above: stock card
	car_stats = (await bridge.replied)[1]
	choice = {"push": "hard", "wager": 150}
	show_meeting()
	await snap(folder, "2_meeting")
	var sc: ScrollContainer = screen.get_node("%Scroll")
	sc.scroll_vertical = 2000
	await snap(folder, "2_meeting_bet")
	var out := ProjectSettings.globalize_path("user://replays/shots.json")
	bridge.request("race", ["race", "--track", state["night"]["track"], "--push", "hard", "--seed", "21",
		"--out", out, "--opponent", state["night"]["opponent"], "--opp-seed", "21"])
	var r: Dictionary = (await bridge.replied)[1]
	var result := apply_result(r)
	show_race(out, result)
	viewer.t = viewer.lap_time * 0.5
	await snap(folder, "5_race_mid")
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
