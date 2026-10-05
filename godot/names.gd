extends Translation
## The names the player picked for a new save (Spire: "like pokemon"): the
## driver (default Faba) and the rival (default Zed). Every piece of text on
## screen goes through Godot's translation step (Labels, Buttons, Label3Ds
## auto-translate), so this one hook swaps the names everywhere: dialog,
## the story, captions, the HUD. The case is kept: FABA / Faba / faba.
## game.gd registers it (TranslationServer) and calls set_names().

const DRIVER := "Faba"
const RIVAL := "Zed"

var _swaps := []              # [RegEx, replacement by case]


func set_names(driver: String, rival: String) -> void:
	_swaps.clear()
	for pair: Array in [[DRIVER, driver], [RIVAL, rival]]:
		var from: String = pair[0]
		var to: String = pair[1].strip_edges()
		if to == "" or to == from:
			continue
		for variant: Array in [[from.to_upper(), to.to_upper()], [from.to_lower(), to.to_lower()], [from, to]]:
			var re := RegEx.new()
			re.compile("\\b" + variant[0] + "\\b")       # whole words: "Zed", never "realized"
			_swaps.append([re, variant[1]])


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	if _swaps.is_empty():
		return src_message
	var s := String(src_message)
	for sw: Array in _swaps:
		s = (sw[0] as RegEx).sub(s, sw[1], true)
	return StringName(s)
