extends RefCounted
## Every line of dialog and handwriting in the game, in Spire's own words
## (docs/ART_DIRECTION.md, Voice): the builder's notes, then Faba's lines.
## Edit lines here, not in the screens.

# Home Polaroid caption: "PCH turnout, wk N. <line>". game.gd home_caption()
# picks the first that fits, top to bottom.
const HOME_SKIPPED := "bitched tf out"                    # skipped the last race night
const HOME_CRASHED := "fahhhhhhh idk how im gonna fix that"   # last race ended in the trees
const HOME_WIN_STREAK := "been locked in"                  # 3+ wins in a row
const HOME_LOSS_STREAK := "focus tf up pa come on"         # 2+ losses in a row
const HOME_STOCK := "straight shitbox"                     # no parts on
const HOME_SOME_PARTS := "still pretty rough bud"          # 1-4 parts on
const HOME_BUILT := "starting to come together actually"   # 5+ parts on
const WIN_STREAK := 3
const LOSS_STREAK := 2
const BUILT_PARTS := 5

# CAR: Sharpie note on the lift view
const LIFT := "oh shi she sitting pretty"

# $$$: scribbled on each pull flyer (by source id)
const FLYERS := {
	"junkyard": "junker",
	"swap_meet": "marketplace special",
	"crate": "brand spankin new",
}

# Dyno sheet margin note (quality %); nothing in between
const DYNO_GREAT := "yoooooo wtf!!"
const DYNO_GREAT_AT := 80
const DYNO_JUNK := "mannnnn i guess ill take it"
const DYNO_JUNK_BELOW := 25

# Whiteboard: who the middle finger is for; a skipped night on the race list
const BOARD_RIVAL := "zed"
const BOARD_SKIPPED := "bitched tf out"

# BROKE screen title
const BROKE := "you fucked it pa"


# ---------------------------------------------------------------- Faba
# Faba talks at the turnout (race night). Speech bubbles, his words.

# Meeting: what he says when you pull up
const FABA_RIVAL_NIGHT := "he doesnt want it like that"
const FABA_OPEN_NIGHT := "can we go get food after i win"

# Meeting: his take on each push level (the risk is printed under it)
const FABA_PUSH := {
	"safe": "like a granny in a z06",
	"normal": "common traffic",
	"hard": "gotta drive it like you stole",
	"flat_out": "fuck it bruh",
}

# Meeting: when you bet big (at least this share of your cash, above the buy-in)
const FABA_BIG_BET := "damnnnn mr deep pockets over here"
const BIG_BET_SHARE := 0.5

# Results
const FABA_WON := "did you expect anything else"
const FABA_LOST := "fuck that foo"
const FABA_CRASHED := "brah fuckkkkk we might be cooked"
const FABA_NO_CONTEST := "come on son"
