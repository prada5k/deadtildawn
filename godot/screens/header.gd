extends HBoxContainer
## Shared top bar (brand, cash, rep). It's its own scene, instanced into every
## hub screen: restyle it once in header.tscn and every screen changes.

const UI := preload("res://ui.gd")


func show_stats(cash: int, rep: int, min_buy_in: int) -> void:
	$Cash.text = UI.money(cash)
	$Cash.add_theme_color_override("font_color", UI.GOOD if cash >= min_buy_in else UI.BAD)
	$Rep.text = "REP %d" % rep
