extends RefCounted
## The body shop's stock (Spire: "make the cars look better"): cosmetics for
## the DX, bought once with cash, worn or taken off any time for free. LOOKS
## ONLY: none of it reaches the sim (no downforce from a wing; the physics
## doesn't model aero yet). One item per slot on the car.
##
## The car's look travels with its parts as "look:<id>" entries in the same
## list (game.gd car_look()), so every scene that shows the DX's parts shows
## its paint and stickers too (widgets/dx_model.gd reads them).
##
## Paint names are Honda's real colors of the era. Prices are Spire's to tune.
## No tow hooks (Spire hates them; an old save's are simply ignored).

const SLOTS := {
	"paint": "Paint",
	"banner": "Windshield banner",
	"stripes": "Stripes",
	"stickers": "Stickers",
	"tint": "Window tint",
	"lip": "Front lip",
	"wing": "Wing",
	"rims": "Rim color",
	"tape": "Battle tape",
}

const ITEMS := {
	# Any respray fixes the primer fender and the sun-killed clearcoat
	"paint_frost": {"slot": "paint", "name": "Frost White, done right", "price": 450,
		"color": Color(0.93, 0.93, 0.91)},
	"paint_milano": {"slot": "paint", "name": "Milano Red", "price": 700, "color": Color(0.7, 0.05, 0.07)},
	"paint_champ": {"slot": "paint", "name": "Championship White", "price": 700, "color": Color(0.98, 0.97, 0.93)},
	"paint_blue": {"slot": "paint", "name": "Electron Blue", "price": 700, "color": Color(0.1, 0.24, 0.62)},
	"paint_black": {"slot": "paint", "name": "Flamenco Black", "price": 700, "color": Color(0.05, 0.05, 0.06)},
	"paint_yellow": {"slot": "paint", "name": "Sunlight Yellow", "price": 800, "color": Color(0.96, 0.78, 0.1)},
	"banner": {"slot": "banner", "name": "Kanjo banner", "price": 80},
	"stripes_side": {"slot": "stripes", "name": "Side stripe", "price": 150},
	"stripes_twin": {"slot": "stripes", "name": "Twin racing stripes", "price": 220},
	"stickers": {"slot": "stickers", "name": "Meet stickers", "price": 60},
	"stickers_crew": {"slot": "stickers", "name": "Crew decal (rear window)", "price": 90},
	"tint": {"slot": "tint", "name": "Limo tint", "price": 150},
	"lip": {"slot": "lip", "name": "Front lip", "price": 250},
	"wing_duck": {"slot": "wing", "name": "Ducktail spoiler", "price": 300},
	"wing_gt": {"slot": "wing", "name": "GT wing", "price": 550},
	"rims_gold": {"slot": "rims", "name": "Gold rims", "price": 150, "color": Color(0.78, 0.6, 0.2)},
	"rims_black": {"slot": "rims", "name": "Gloss black rims", "price": 150, "color": Color(0.07, 0.07, 0.08)},
	"rims_white": {"slot": "rims", "name": "Championship White rims", "price": 180, "color": Color(0.95, 0.95, 0.92)},
	"battle_tape": {"slot": "tape", "name": "Battle tape (the bumper's held on with it)", "price": 15},
}


## The look entries for the items worn ("look:<id>").
static func look_tags(worn: Dictionary) -> Array:
	var out := []
	for slot in worn:
		if ITEMS.has(worn[slot]):
			out.append("look:" + str(worn[slot]))
	return out
