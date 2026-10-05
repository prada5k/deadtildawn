extends Control
## HOW TO RACE (Spire: "jorge says it's too difficult"): a few pages on how to
## approach a race night, one at a time, with Faba's take on each. It opens
## by itself the first race night, and from "how to race?" on the road and
## the meeting. The words live in voice.gd (TUTORIAL); this only pages them.
## A hub screen. LAYOUT lives in tutorial.tscn; data hooks use %Name.

signal go(target: String)    # hub contract (unused here)
signal done                  # read it (or skipped it): back to where they were

var pages: Array = []        # [[title, body, faba's line], ...]
var at := 0


func _ready() -> void:
	%Back.pressed.connect(func(): turn(-1))
	%Next.pressed.connect(func(): turn(1))
	%SkipAll.pressed.connect(func(): done.emit())


func setup(all: Array) -> void:
	pages = all
	at = 0
	show_page()


func turn(step: int) -> void:
	if at + step >= pages.size():
		done.emit()
		return
	at = clampi(at + step, 0, pages.size() - 1)
	show_page()


func show_page() -> void:
	var pg: Array = pages[at]
	%Count.text = "%d / %d" % [at + 1, pages.size()]
	%Title.text = pg[0]
	%Body.text = pg[1]
	%FabaLine.text = pg[2]
	%Back.disabled = at == 0
	%Next.text = "got it" if at == pages.size() - 1 else "next  >"
	%Scroll.scroll_vertical = 0
