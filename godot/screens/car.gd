extends Control
## The car: dyno chart, stat sheet, parts (coming with the loot system).
## LAYOUT lives in car.tscn; this script fills in data. Stat rows are added
## in code (one per stat) using the theme, so they restyle with it.

signal go(target: String)    # "warehouse"

const UI := preload("res://ui.gd")


func _ready() -> void:
	$Margin/Column/TopRow/Back.pressed.connect(func(): go.emit("warehouse"))


func setup(info: Dictionary, stats: Dictionary) -> void:
	$Margin/Column/Header.show_stats(info["cash"], info["rep"], info["min_buy_in"])
	$Margin/Column/CarName.text = stats["name"]
	var dyno = $Margin/Column/DynoPanel/Dyno
	dyno.dyno = stats["dyno"]
	dyno.redline = float(stats["redline"])
	dyno.queue_redraw()
	var rows: VBoxContainer = $Margin/Column/StatsPanel/Stats
	UI.stat_row(rows, "Weight", "%d kg (with Faba)" % stats["weight_kg"])
	UI.stat_row(rows, "Power / weight", "%d hp per tonne" % stats["hp_per_tonne"])
	UI.stat_row(rows, "Drivetrain", "%s, redline %d" % [stats["drivetrain"], stats["redline"]])
	UI.stat_row(rows, "0-60 mph", "%.2f s" % stats["zero_60_s"])
	UI.stat_row(rows, "Quarter mile", "%.2f s" % stats["quarter_s"])
	UI.stat_row(rows, "Top speed", "%d mph" % stats["top_speed_mph"])
	UI.stat_row(rows, "Skidpad", "%.2f g, %s" % [stats["skidpad_g"], stats["balance"]])
	UI.stat_row(rows, "60-0 mph", "%d ft" % stats["sixty_zero_ft"])
