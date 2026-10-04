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
	"swap_meet": "facebook marketplace special",
	"crate": "brand spankin new",
	"import": "straight off the boat",       # DRAFT (Claude): Spire's line goes here
}

# $$$: the printed line on each pull flyer (the pick-n-pull line). DRAFTS:
# these are the old data-file blurbs plus one for the import -- Spire rewrites.
const PULL_BLURBS := {
	"junkyard": "Pick-n-pull. Cheap, mostly common, often worn.",
	"swap_meet": "Some guy's garage cleanout. Mystery box, cash only.",
	"crate": "Unopened, from a shop closing down. No commons.",
	"import": "JDM parts in a shipping crate. No commons, mostly the good stuff.",
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

# Meeting: when you bet big (at least this share of the max bet you can make,
# above the minimum)
const FABA_BIG_BET := "damnnnn mr deep pockets over here"
const BIG_BET_SHARE := 0.75

# Results
const FABA_WON := "did you expect anything else"
const FABA_LOST := "fuck that foo"
const FABA_CRASHED := "brah fuckkkkk we might be cooked"
const FABA_NO_CONTEST := "come on son"

# Results: why it went that way (sim/breakdown.py "verdict": the cause behind
# the biggest loss, or the biggest gain on a win). Said under the breakdown
# sheet. DRAFTS by Claude -- Spire rewrites them.
const FABA_WHY_LOST := {
	"launch": "i was sleeping at the green my bad",
	"accel": "he just walked us on the straights, we need more motor",
	"exit": "he was getting off the corners way better than us",
	"braking": "he was out braking me every time",
	"corner": "he was carrying way more speed thru the turns",
	"mistake": "i sent it too hot and blew the corner",     # Faba ran wide
	"crash": "",                                             # FABA_CRASHED says it
}
const FABA_WHY_WON := {
	"launch": "got the jump on him off the line",
	"accel": "she pulled on him every straight",
	"exit": "we were getting off the corners clean",
	"braking": "i was out braking him all night",
	"corner": "we were carrying way more speed thru the turns",
	"mistake": "he blew a corner and i was right there",    # he ran wide
	"their_crash": "he put it in the trees lol",
}

# The breakdown (results sheet + the replay's split captions): what each
# cause is called, and where it happened (%s = the corner's pace note)
const CAUSE_TAGS := {
	"launch": "launch", "accel": "acceleration", "exit": "corner exit",
	"braking": "braking", "corner": "corner speed", "mistake": "ran wide",
}
const CAUSE_WHERE := {
	"launch": "off the line", "accel": "on the run to %s", "exit": "out of %s",
	"braking": "into %s", "corner": "through %s", "mistake": "at %s",
}
# The road screen: the builder's read of tonight's road (sim/roadread.py
# "kind"), in Sharpie under the map. DRAFTS by Claude -- Spire rewrites.
const ROAD_KIND := {
	"power": "power road. motor wins this one",
	"grip": "all turns. tires, suspension, weight",
	"both": "bit of everything on this one",
}

# The replay: what the spotters say on the radio as Faba goes by (before the
# blind corners). DRAFT -- Spire's word.
const SPOTTER_CALL := "clear"

const FINISH_NAME := "the line"       # "acceleration on the run to the line"
# A swing reads "<tag> <where>": "corner speed through R3 90", "Faba ran wide at R7 65"


# ---------------------------------------------------------------- TEAM board
# Memories: Polaroids that unlock at milestones. DRAFTS in Spire's style
# (Claude wrote these from his sample lines) -- Spire rewrites them.
# id: [photo text, caption]
const MEMORIES := {
	"first_win": ["W", "first W. faba wouldnt shut up about it"],
	"first_crash": ["!!", "we dont talk about this one"],
	"beat_rival": ["ZED", "zed finally caught one"],
	"streak3": ["3", "three straight. locked in fr"],
	"big_bet": ["$$$", "bet half the shop on it lmao"],
	"legendary": ["Q", "pulled a unicorn out the crate"],
}
const MEMORY_ORDER := ["first_win", "first_crash", "beat_rival", "streak3", "big_bet", "legendary"]


# ---------------------------------------------------------------- the story (intro)
# DRAFTS by Claude in Spire's style -- Spire rewrites every line.
# Part 1, the tape: old touge footage, Best Motoring style captions.
# shot: "turnout" (the FA5 and the 370 at the turnout), "glitch" (the tape
# starts to go), "static" (it's gone), "black" (tape stopped).
const STORY_TAPE := [
	{"stamp": "NOV 14 2020  23:41", "shot": "turnout", "caption": "socal canyons. six years ago"},
	{"stamp": "NOV 14 2020  23:42", "shot": "turnout", "caption": "everybody on the mountain knew the FA5. i built it. i drove it"},
	{"stamp": "NOV 14 2020  23:44", "shot": "turnout", "caption": "50k on the line. the nissan club's top dog in his 370"},
	{"stamp": "NOV 14 2020  23:51", "shot": "turnout", "caption": "last run of the night. i was up on him"},
	{"stamp": "NOV 14 2020  23:52", "shot": "glitch", "caption": "one corner too hot"},
	{"stamp": "NOV 14 2020  23:52", "shot": "static", "caption": "87 mph. into a tree"},
	{"stamp": "", "shot": "black", "caption": "the FA5 burned. my right leg never came back right"},
]
# Part 2, Faba's texts. ["when", date] starts a new day in the thread;
# ["faba", text] or ["me", text] is a message.
const STORY_TEXTS := [
	["when", "MAR 2021"],
	["faba", "u up?"],
	["me", "cant sleep"],
	["faba", "im outside. bringing food"],
	["when", "AUG 2023"],
	["faba", "u ever think about going back up the mountain"],
	["me", "no"],
	["when", "OCT 2026"],
	["faba", "i quit my job lol"],
	["me", "????"],
	["faba", "and i bought a civic"],
	["me", "bro what"],
	["faba", "96 DX. 5 speed. stock as hell"],
	["faba", "and a warehouse"],
	["faba", "you build it. i drive it"],
	["me", "the 370 still running the mountain?"],
	["faba", "every friday"],
	["me", "send me the address"],
]
const STORY_FA5 := "2009 Honda Civic Si (FA5)"
const STORY_BOSS := "2009 Nissan 370Z"
