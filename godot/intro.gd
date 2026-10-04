extends Control
## The story (Spire's words: voice.gd STORY_*). Two parts:
##   1. The tape: old touge footage of the $50k night (the FA5 and the
##      Nissan club's 370Z at the turnout, widgets/turnout_night.gd) with
##      camcorder OSD and Best Motoring style captions. The crash is the
##      tape glitching out, then static, then nothing.
##   2. Faba's texts: a phone thread over six years, ending with the DX and
##      the warehouse. Messages pop in one at a time.
## Then the title. Tap to move on; "skip" ends it. LAYOUT lives in
## intro.tscn; the words live in voice.gd.

signal finished

const Voice := preload("res://voice.gd")
const UI := preload("res://ui.gd")
const MESSAGE_GAP_S := 0.7       # between messages popping in

var tape_i := -1                 # current tape caption
var block := 0                   # current day in the thread
var typing := false              # messages still popping in
var title_shown := false


func _ready() -> void:
	%Skip.pressed.connect(func(): finished.emit())
	%Footage.setup(Voice.STORY_BOSS, [], Voice.STORY_FA5)
	%Footage.frame("chase")                    # portrait: over the FA5's shoulder
	next_slide()


func _gui_input(event: InputEvent) -> void:
	# Typed as bool: `event` is a generic InputEvent, so Godot can't infer it
	var tapped: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		next_slide()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
		next_slide()


## One tap: the next tape caption, the next day of texts, the title, or done.
func next_slide() -> void:
	if title_shown:
		finished.emit()
		return
	if tape_i < Voice.STORY_TAPE.size() - 1:
		tape_i += 1
		show_tape(Voice.STORY_TAPE[tape_i])
		return
	if not %Phone.visible:
		%Tape.visible = false
		%Phone.visible = true
		show_block()
		return
	if typing:
		typing = false                       # tap while typing: the rest of the day at once
		return
	if block < day_starts().size():
		show_block()
		return
	show_title()


func show_tape(slide: Dictionary) -> void:
	%Stamp.text = slide["stamp"]
	%Caption.text = slide["caption"]
	var caption: Label = %Caption
	caption.modulate.a = 0.0
	create_tween().tween_property(caption, "modulate:a", 1.0, 0.35)
	var tape: ShaderMaterial = $Tape/Grain.material
	var black: ColorRect = %Blackout
	match slide["shot"]:
		"glitch":                                 # the tape starts to go
			tape.set_shader_parameter("band", 0.6)
			tape.set_shader_parameter("bleed", 6.0)
		"static":                                 # gone: black, heavy tracking noise
			tape.set_shader_parameter("band", 1.4)
			tape.set_shader_parameter("bleed", 10.0)
			black.color.a = 0.85
		"black":                                  # tape stopped
			tape.set_shader_parameter("band", 0.0)
			tape.set_shader_parameter("bleed", 0.0)
			black.color.a = 1.0
			%Play.text = "STOP []"
		_:
			tape.set_shader_parameter("band", 0.08)
			tape.set_shader_parameter("bleed", 1.6)
			black.color.a = 0.0
	%Hint.text = "tap"


## Indexes in STORY_TEXTS where each day ("when") starts.
func day_starts() -> Array:
	var out := []
	for i in Voice.STORY_TEXTS.size():
		if Voice.STORY_TEXTS[i][0] == "when":
			out.append(i)
	return out


## Pop in the next day of the thread, one message at a time.
func show_block() -> void:
	var starts := day_starts()
	var i0: int = starts[block]
	var i1: int = starts[block + 1] if block + 1 < starts.size() else Voice.STORY_TEXTS.size()
	block += 1
	typing = true
	for i in range(i0, i1):
		var msg: Array = Voice.STORY_TEXTS[i]
		add_message(msg[0], msg[1])
		if typing and i < i1 - 1:
			await get_tree().create_timer(MESSAGE_GAP_S).timeout
	typing = false
	%Hint.text = "tap"


func add_message(who: String, text: String) -> void:
	var thread: VBoxContainer = %Thread
	if who == "when":
		var day := UI.label(thread, text, "TextWhenLabel")
		day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END if who == "me" else BoxContainer.ALIGNMENT_BEGIN
		thread.add_child(row)
		var bubble := PanelContainer.new()
		bubble.theme_type_variation = "TextMePanel" if who == "me" else "TextFabaPanel"
		row.add_child(bubble)
		var label := Label.new()
		label.theme_type_variation = "TextLabel"
		label.text = text
		bubble.add_child(label)
		bubble.modulate.a = 0.0
		create_tween().tween_property(bubble, "modulate:a", 1.0, 0.2)
	await get_tree().process_frame                   # scroll to the newest message
	var sc: ScrollContainer = %Scroll
	sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func show_title() -> void:
	title_shown = true
	%Phone.visible = false
	%Title.visible = true
	%Title.modulate.a = 0.0
	create_tween().tween_property(%Title, "modulate:a", 1.0, 0.6)
	%Hint.text = "tap to start"
