extends RefCounted
## Every line of dialog and handwriting in the game, in Spire's own words
## (docs/ART_DIRECTION.md, Voice): the builder's notes, then Faba's lines.
## Edit lines here, not in the screens.

# WHO'S WHO (a new save, before the story): the three names. DRAFT (Claude).
const NAME_ASK_PLAYER := "your name. the one on the tape"
const NAME_ASK_DRIVER := "who drives? (the one who got you back on your feet)"
const NAME_ASK_RIVAL := "and who's the rival? the one you're gonna beat"
const NAME_DEFAULTS := {"player": "you", "driver": "Faba", "rival": "Zed"}

# Home caption (the camcorder's title over the garage footage):
# "<HOME_PLACE>, wk N. <line>". game.gd home_caption() picks the first line
# that fits, top to bottom.
const HOME_PLACE := "the garage"                          # DRAFT (Claude): was "PCH turnout" before the garage
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
const DYNO_GREAT_AT := 85
const DYNO_JUNK := "mannnnn i guess ill take it"
const DYNO_JUNK_BELOW := 20

# Whiteboard: who the middle finger is for; a skipped night on the race list
const BOARD_RIVAL := "zed"
const BOARD_SKIPPED := "bitched tf out"

# BROKE screen title
const BROKE := "pockets empty pa"


# ---------------------------------------------------------------- Faba
# Faba talks at the turnout (race night). Speech bubbles, his words.

# Meeting: what he says when you pull up
const FABA_RIVAL_NIGHT := "he doesnt the smoke"
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
const FABA_WON := "light work"
const FABA_LOST := "fuck that foo"
const FABA_CRASHED := "brah fuckkkkk we might be cooked"
const FABA_NO_CONTEST := "come on son"
# HOW TO RACE (screens/tutorial.tscn; Spire: "jorge says it's too difficult").
# [title, body, Faba's line]. DRAFTS by Claude -- Spire rewrites. The push
# numbers are real: a stock DX at each push, 300 races vs street racers
# matched to a coin flip, on a flowing, a balanced and a technical road
# (Oct 2026). If the physics changes, rerun it and update page 4.
const TUTORIAL := [
	["A race night",
		"1. Look at tonight's road.\n2. Build the DX for it.\n3. Lock the build in.\n4. Find out who you're racing.\n5. Pick how hard Faba pushes, and what you bet.\n6. Watch.\n\nYou never touch the wheel. The race is physics: the same math for every car. Your calls are the build, the push and the bet. That's the whole game.",
		"you build it, i drive it. that's the deal"],
	["Read the road",
		"FULL THROTTLE is how much of the run Faba's foot is flat. High (60%+) means the motor decides it: intake, header, cams, tune, gearing.\n\nLow (under 50%), or hairpins, means the corners decide it: tires, weight, sway bar, springs.\n\nLess weight helps everywhere: faster in a straight line AND through the corners.",
		"look at the road before you touch a wrench"],
	["Build for it",
		"Tap a slot on the build sheet. The swap card shows the DX now vs with that part: green is better, red is worse.\n\nWatch 0-60 and the quarter mile for power, skidpad for grip. A junk roll (low %) can be WORSE than stock, so don't bolt on everything you own.\n\n\"take it all off\" puts the car back to stock in one tap.",
		"green good, red bad. even i get that"],
	["How hard Faba pushes",
		"From the sim (300 races each, vs racers matched to you):\n\nSAFE: wins ~43%. Never crashes.\nNORMAL: wins ~49-51%. Never crashes.\nHARD: wins 42-52%. Crashes about 1 in 100. Only worth it on fast, flowing roads.\nFLAT OUT: wins only 20-36%. Crashes 1 in 5.\n\nNORMAL is the call most nights. A crash costs the bet, 20 rep, $150 for the tow, and can break your parts.",
		"flat out is how we end up in a tree. ask me how i know"],
	["The bet",
		"Even money: win what you bet, lose what you bet.\n\nStreet racers are matched to make it a coin flip, so bet small and often. Keep enough for the next minimum bet plus a cushion: drop under the minimum and you're BROKE.\n\nRivals AREN'T matched. When your card beats his (more power per tonne AND more skidpad), that's the night to bet big.",
		"don't bet the rent"],
	["After the race",
		"WHERE IT WENT shows where the time went and why:\n\nCORNER SPEED lost: more grip (tires, less weight).\nACCELERATION or CORNER EXIT lost: more power, less weight.\nBRAKING lost: less weight, better tires.\nRAN WIDE: Faba pushed too hard. Back it off.\n\nFix the biggest one first. Lost by a few hundredths? That's luck. Lost by half a second? That's the build.",
		"the sheet don't lie"],
]

# The body shop (screens/bodyshop.tscn): the note on the sheet, and what the
# kanjo banner across the windshield says. DRAFTS by Claude -- Spire's words.
const BODYSHOP_NOTE := "Looks only. The sim doesn't care what color it is. Faba does."

# The crew (Spire: option A, a SoCal crew that runs kanjo style). Its name on
# the sticker (home, TEAM), the windshield banner and the rear-window decal.
# The Japanese under it: 環状族 (kanjo-zoku, "loop tribe", what the Osaka loop
# crews are called). DRAFTS by Claude -- Spire names the crew. Have a Japanese
# speaker check any Japanese before it's anywhere permanent.
const CREW_NAME := "contraband96"
const CREW_SUB := "環状族  ·  SOCAL"
const BANNER_TEXT := CREW_NAME
# The results hanko (red seal): win, loss (a crash too), no contest
const HANKO := {"win": "勝", "loss": "負", "no_contest": "引"}

# The cops (3% of races that finish): pulled over on the way down the hill.
# A citation on the results screen. DRAFTS by Claude -- Spire rewrites.
const COPS_TITLE := "CITATION"
const COPS_CHARGES := ["SPEEDING  (CVC 22350)", "RECKLESS DRIVING  (CVC 23103)"]
const COPS_SEIZED := "the winnings went in an evidence bag"
const FABA_COPS := "spotter didnt do his job bruh chp got us"

# Jorge mode (code "jorge", Spire): you win, he doesn't pay. What he says, and
# the receipt's note
const JORGE_LINE := "fuck you jorge"
const JORGE_RECEIPT := "slashed your tires, spit on ur shoe, and drove away"

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
	["faba", "race?"],
	["me", "been done with that..."],
	["faba", "damn alr"],
	["when", "AUG 2023"],
	["faba", "u ever gonna run it again?"],
	["me", "nah cant drive"],
	["when", "OCT 2026"],
	["faba", "i just got laid off"],
	["me", "bro what"],
	["me", "whats the move"],
	["faba", "96 5speed civic"],
	["faba", "lets run it back"],
	["me", "i cant drive tho"],
	["faba", "i can"],
	["me", "alr then"],
]
const STORY_FA5 := "2009 Honda Civic Si (FA5)"
const STORY_BOSS := "2009 Nissan 370Z"
