extends Control
## First-launch intro. Tap / click / Enter / Space advances; SKIP ends it.
##
## Edit the STORY here (SLIDES). Edit the LOOK in intro.tscn (open it in
## Godot: select a node, change it in the Inspector) and in theme.tres.

signal finished

const STORY_BG := Color(0.475, 0.502, 0.443)    # #798071
const STORY_TEXT := Color(0.102, 0.059, 0.063)  # #1A0F10
const ACCENT := Color(0.839, 0.251, 0.271)      # #D64045 (kickers, title)
const FADE_S := 0.6

const SLIDES := [
	{"kicker": "SOCAL CANYONS  /  SIX YEARS AGO",
	 "body": "Everyone on the mountain knew the FA5.\n\nEveryone knew who built it.\n\nAnd who drove it."},
	{"kicker": "2009 CIVIC SI  /  FA5",
	 "body": "Your car. Your build. Your line through every corner on the mountain."},
	{"kicker": "THE LAST RUN",
	 "body": "A $50,000 pot. Final run of the night.\n\nYou were winning."},
	{"kicker": "", "body": "One corner too hot.\n\nThe tires let go.", "bg": "crash"},
	{"kicker": "87 MPH", "body": "Into a tree.", "bg": "crash"},
	{"kicker": "", "body": "You should have died.\n\nThe FA5 burned. Your right leg never came back the same."},
	{"kicker": "AFTER", "body": "Faba got you back on your feet.\n\nYou walked away from the scene. You didn't look back."},
	{"kicker": "SIX YEARS LATER",
	 "body": "Faba quits his corporate job.\n\nBuys a bone-stock '95 Civic SiR-II hatch. Five-speed."},
	{"kicker": "THE WAREHOUSE",
	 "body": "He spends his savings on a warehouse. Home, garage, headquarters.\n\n\"You build it. I drive it.\""},
	{"kicker": "", "body": "DEADTILDAWN", "title": true},
]

@onready var kicker: Label = $Margin/Column/Kicker
@onready var body: Label = $Margin/Column/Body
@onready var hint: Label = $Hint
@onready var background: ColorRect = $Background
@onready var splatter: Control = $Splatter

var index := -1


func _ready() -> void:
	$Skip.pressed.connect(func(): finished.emit())
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


func next_slide() -> void:
	index += 1
	if index >= SLIDES.size():
		finished.emit()
		return
	show_slide(SLIDES[index])


func show_slide(slide: Dictionary) -> void:
	kicker.text = slide.get("kicker", "")
	kicker.visible = kicker.text != ""
	body.text = slide["body"]
	var is_title: bool = slide.get("title", false)
	body.add_theme_font_size_override("font_size", 96 if is_title else 46)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if is_title else HORIZONTAL_ALIGNMENT_LEFT
	body.add_theme_color_override("font_color", ACCENT if is_title else STORY_TEXT)
	kicker.add_theme_color_override("font_color", ACCENT)
	hint.text = "tap to start" if index == SLIDES.size() - 1 else "tap to continue"

	# Fade the text in; shift the background for the crash slides
	kicker.modulate.a = 0.0
	body.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(kicker, "modulate:a", 1.0, FADE_S)
	tween.tween_property(body, "modulate:a", 1.0, FADE_S).set_delay(0.15)
	background.color = STORY_BG
	# Crash slides: the splatter fades in over the background
	var crash: bool = slide.get("bg", "") == "crash"
	tween.tween_property(splatter, "modulate:a", 1.0 if crash else 0.0, 0.25)



