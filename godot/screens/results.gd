extends Control
## Race night, after: back at the turnout. A rubber-stamp verdict over the
## photo, Faba's reaction (voice.gd), WHERE IT WENT (the breakdown: who was
## faster where, the biggest swings, time by cause, Faba's take on why), the
## night's receipt (times, cash, rep),
## a tow ticket if it ended in the trees, and the loot box if they paid up in
## parts. Full screen. LAYOUT lives in results.tscn; data hooks use %Name.

signal done_pressed

const UI := preload("res://ui.gd")
const Voice := preload("res://voice.gd")


func _ready() -> void:
	%Done.pressed.connect(func(): done_pressed.emit())


## result: game.gd apply_result() record; info: cash, rep, faba_parts,
## loot_text, track (the replay's track, for the map; may be empty)
func setup(result: Dictionary, info: Dictionary) -> void:
	%Turnout.setup(result["rival_car"], info["faba_parts"])
	var won: bool = result["won"]
	var verdict := "YOU WON" if won else ("NO CONTEST" if result["no_contest"] else
		("CRASHED" if result["dnf"] else "YOU LOST"))
	%Verdict.text = verdict
	%FabaLine.text = (Voice.FABA_WON if won else (Voice.FABA_NO_CONTEST if result["no_contest"] else
		(Voice.FABA_CRASHED if result["dnf"] else Voice.FABA_LOST)))
	stamp()

	%Gap.visible = not result["dnf"] and not result["opponent_dnf"]
	if %Gap.visible:
		var gap := absf(float(result["time"]) - float(result["opponent_time"]))
		%Gap.text = "%s by %.3f s" % ["Ahead" if won else "Behind", gap]

	# The receipt
	var lines: VBoxContainer = %Lines
	var head := UI.label(lines, "RACE NIGHT  //  %s" % str(result["when"]), "InkMutedLabel")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var faba := "DNF (off at %s)" % result["crash_corner"] if result["dnf"] else "%.3f s" % result["time"]
	var them := "DNF (off at %s)" % result["opponent_crash_corner"] if result["opponent_dnf"] \
		else "%.3f s" % result["opponent_time"]
	for row in [
		["Faba", faba],
		["%s (%s)" % [result["rival"], result["rival_car"]], them],
		["Push", str(result["push"]).replace("_", " ")],
		["Mistakes", "none" if result["mistakes"].is_empty() else ", ".join(result["mistakes"])],
	]:
		UI.stat_row(lines, row[0], row[1], "InkMutedLabel", "InkLabel")
	# money is always green, rep always orange
	UI.stat_row(lines, "Cash", "%s%s  ->  %s" % ["+" if result["cash_change"] > 0 else "",
		UI.money(result["cash_change"]), UI.money(info["cash"])], "InkMutedLabel", "InkMoneyLabel")
	UI.stat_row(lines, "Rep", "%+d  ->  %d" % [result["rep_change"], info["rep"]], "InkMutedLabel", "InkRepLabel")

	# Tow ticket
	var dmg: Dictionary = result.get("damage", {})
	%Damage.visible = not dmg.is_empty()
	if not dmg.is_empty():
		var box: VBoxContainer = %DamageLines
		var t := UI.label(box, "TOW TICKET", "StampLabel")
		t.autowrap_mode = TextServer.AUTOWRAP_OFF
		t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		UI.stat_row(box, "Tow + body work", "-%s" % UI.money(dmg["body_repair"]), "InkMutedLabel", "InkMoneyLabel")
		for n in dmg["destroyed"]:
			UI.label(box, "DESTROYED: %s" % n, "InkLabel", UI.INK_BAD)
		for n in dmg["damaged"]:
			UI.label(box, "Damaged: %s (off the car until it's repaired in $$$)" % n, "InkLabel")
		if dmg["destroyed"].is_empty() and dmg["damaged"].is_empty():
			UI.label(box, "The parts survived. This time.", "InkMutedLabel")

	%Loot.visible = info["loot_text"] != ""
	%LootLine.text = info["loot_text"]
	fill_breakdown(result, info.get("track", {}))


## Why it went that way (sim/breakdown.py, via the race reply). Gains are
## Faba's: + = he took time, - = he lost it.
func fill_breakdown(result: Dictionary, track: Dictionary) -> void:
	var bd: Dictionary = result.get("breakdown", {})
	%Breakdown.visible = not bd.is_empty()
	%FabaWhySays.visible = false
	if bd.is_empty():                       # older saves, or no opponent
		return
	var them: String = result["rival"]
	var map: Control = %SplitMap
	map.visible = not track.is_empty()
	map.track = track
	map.sections = bd["sections"]
	map.queue_redraw()
	%MapKey.text = "blue: Faba faster  /  red: %s faster" % them
	if not bd["complete"]:
		%MapKey.text += "
(up to the crash)"
	for it: Dictionary in bd["swings"]:
		gain_row(%Swings, swing_text(it, them), float(it["gain"]))
	var totals: Dictionary = bd["totals"]
	var causes := totals.keys().filter(func(c): return absf(float(totals[c])) >= 0.005)
	causes.sort_custom(func(a, b): return float(totals[a]) > float(totals[b]))
	for c in causes:
		gain_row(%Totals, str(Voice.CAUSE_TAGS.get(c, c)), float(totals[c]))
	var why: Dictionary = Voice.FABA_WHY_WON if result["won"] else Voice.FABA_WHY_LOST
	var line: String = why.get(bd["verdict"], "")
	%FabaWhySays.visible = line != "" and not result["no_contest"]
	%FabaWhy.text = line


## "corner speed through R3 90", "Faba ran wide at R7 65", "launch off the line"
func swing_text(it: Dictionary, them: String) -> String:
	var cause: String = it["cause"]
	var where: String = Voice.FINISH_NAME if it["where"] == "FINISH" else str(it["where"])
	var w: String = Voice.CAUSE_WHERE.get(cause, "")
	var place := (w % where) if "%s" in w else w
	if cause == "mistake":
		var who: String = {"me": "Faba", "them": them, "both": "both"}.get(it["mistake_by"], "")
		return "%s %s %s" % [who, Voice.CAUSE_TAGS["mistake"], place]
	return "%s %s" % [Voice.CAUSE_TAGS.get(cause, cause), place]


## One line of the sheet: what, then the time in ink (red when Faba lost it).
func gain_row(parent: Node, text: String, gain: float) -> void:
	var row := UI.stat_row(parent, text, "%+.2f s" % gain, "InkLabel", "InkLabel")
	if gain < 0.0:
		(row.get_child(1) as Label).add_theme_color_override("font_color", UI.INK_BAD)


## The verdict lands like a rubber stamp: big, then thunk.
func stamp() -> void:
	var v: Label = %Verdict
	await get_tree().process_frame
	v.pivot_offset = v.size / 2.0
	v.scale = Vector2(2.2, 2.2)
	v.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(v, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(v, "modulate:a", 1.0, 0.12)
