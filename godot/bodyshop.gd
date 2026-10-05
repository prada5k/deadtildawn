extends RefCounted
## The body shop's stock (Spire: "make the cars look better"): cosmetics for
## the DX, bought once with cash, worn or taken off any time for free. LOOKS
## ONLY: none of it reaches the sim (no downforce from a spoiler; the physics
## doesn't model aero yet). One item per slot on the car.
##
## The car's look travels with its parts as "look:<id>" entries in the same
## list (game.gd car_look()), so every scene that shows the DX's parts shows
## its paint and its add-ons too (widgets/dx_model.gd reads them).
##
## The list is Spire's (Oct 2026, kanjo refresh). Paint names are Honda's real
## colors. Prices are Spire's to tune. Gone for now: windshield banners,
## stripes, stickers (brand stickers come back with sponsors), tow hooks
## (Spire hates them). An old save's removed items are simply ignored.

const SLOTS := {
	"paint": "Paint",
	"tint": "Window tint",
	"windows": "Side windows",
	"front": "Front bumper",
	"rear": "Rear bumper",
	"holes": "Bumper holes",
	"wing": "Spoiler",
	"rims": "Rim color",
	"fogs": "Fog lights",
	"exhaust": "Exhaust tip",
	"plates": "Plates",
	"tape": "Battle tape",
}

const ITEMS := {
	# Any respray fixes the primer fender and the sun-killed clearcoat
	"paint_frost": {"slot": "paint", "name": "Frost White, done right", "price": 450,
		"color": Color(0.93, 0.93, 0.91)},
	"paint_milano": {"slot": "paint", "name": "Milano Red", "price": 700, "color": Color(0.7, 0.05, 0.07)},
	"paint_blue": {"slot": "paint", "name": "Electron Blue", "price": 700, "color": Color(0.1, 0.24, 0.62)},
	"paint_black": {"slot": "paint", "name": "Night Crystal Black", "price": 700, "color": Color(0.04, 0.04, 0.06)},
	"paint_yellow": {"slot": "paint", "name": "Sunlight Yellow", "price": 800, "color": Color(0.96, 0.78, 0.1)},
	"paint_midori": {"slot": "paint", "name": "Midori Green", "price": 800, "color": Color(0.06, 0.42, 0.24)},
	"paint_pink": {"slot": "paint", "name": "Pale pink", "price": 800, "color": Color(0.95, 0.74, 0.78)},
	"tint": {"slot": "tint", "name": "Limo tint", "price": 150},
	"window_nets": {"slot": "windows", "name": "Window nets, no glass", "price": 120},
	"lip": {"slot": "front", "name": "Front lip", "price": 250},
	"splitter": {"slot": "front", "name": "Splitter", "price": 350},
	"bumperless_front": {"slot": "front", "name": "Bumperless front", "price": 60},
	"bumperless_rear": {"slot": "rear", "name": "Bumperless rear", "price": 60},
	"bumper_holes": {"slot": "holes", "name": "Holes cut in the bumpers", "price": 40},
	"roof_spoiler": {"slot": "wing", "name": "Mugen-style roof spoiler", "price": 400},
	"rims_gold": {"slot": "rims", "name": "Gold", "price": 150, "color": Color(0.78, 0.6, 0.2)},
	"rims_black": {"slot": "rims", "name": "Gloss black", "price": 150, "color": Color(0.07, 0.07, 0.08)},
	"rims_white": {"slot": "rims", "name": "White", "price": 150, "color": Color(0.95, 0.95, 0.92)},
	"rims_chrome": {"slot": "rims", "name": "Chrome", "price": 220, "color": Color(0.9, 0.91, 0.93), "chrome": true},
	"rims_bronze": {"slot": "rims", "name": "Bronze", "price": 180, "color": Color(0.55, 0.4, 0.2)},
	"rims_yellow": {"slot": "rims", "name": "Yellow", "price": 180, "color": Color(0.95, 0.8, 0.1)},
	"fogs_yellow": {"slot": "fogs", "name": "Yellow fog lights", "price": 180},
	"tip_canister": {"slot": "exhaust", "name": "Canister tip", "price": 120},
	"tip_burnt": {"slot": "exhaust", "name": "Burnt titanium tip", "price": 160},
	"tip_dual": {"slot": "exhaust", "name": "Dual tips", "price": 140},
	"plates_bent": {"slot": "plates", "name": "Bent plates, front and rear", "price": 20},
	"battle_tape": {"slot": "tape", "name": "Battle tape (the bumper's held on with it)", "price": 15},
}


## The look entries for the items worn ("look:<id>").
static func look_tags(worn: Dictionary) -> Array:
	var out := []
	for slot in worn:
		if ITEMS.has(worn[slot]):
			out.append("look:" + str(worn[slot]))
	return out
