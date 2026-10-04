# deadtildawn

2D mobile touge racing RPG (portrait, iPhone target). Story: six years ago the player was a legend of the SoCal canyon scene in a self-built 2009 Civic Si (FA5). In a $50k race, one corner too hot at 87 mph: the car hit a tree and burned, and the player survived but lost strength and feel in the right leg and left the scene. Best friend **Faba** got them back on their feet. Six years later Faba quits his corporate job, buys a stock '96 Civic DX coupe 5MT, and spends his savings on a warehouse (home + HQ): "You build it. I drive it." The player never drives: races are physics simulations shown as a broadcast-style replay with live telemetry. (Intro text lives in `godot/intro.gd` SLIDES.)

The physics simulator is also Spire's Physics 3 showcase project at Oxnard College (due ~early December 2026): "Can first-year physics predict a real car's performance?"

## How to work with me (Spire)

- I'm a mechanical engineering student. I want to LEARN engineering workflow and skills, not just have you do everything. Explain the reasoning behind design choices, teach the concepts (Godot, Python, testing, git), and give me parts to do myself when it makes sense.
- I make the large-scale decisions (scope, features, architecture direction, game design). Offer 2-3 options with tradeoffs and a recommendation, then let me decide. Ask before big changes.
- I like to derive physics myself and predict results before code runs. Hand calcs become tests.
- Give honest, direct assessments. Point out errors, scope creep, weak assumptions, and your own mistakes.
- Work iteratively: rough version first, then refine. Don't jump ahead to later milestones without asking.
- **I edit Godot scenes in the editor.** Always read a scene/theme file's current contents before changing it; never regenerate a `.tscn` from memory. Keep my layout and styling; change only what the task needs.

## Architecture

- **Python (`sim/`) is the physics engine and the reference implementation.** A lap run returns telemetry. Godot does NO physics.
- **Godot (`godot/`) is the game.** `game.tscn` (`game.gd`) owns state, save, calendar, and flow; `main.tscn` (`main.gd`) is the replay viewer, used standalone or embedded in the race screen. Godot calls `tools/game_bridge.py` (Python) in a background thread (`bridge.gd`) and reads one JSON reply per command (versioned contract, tested in `tests/test_bridge.py`). Replays use the `deadtildawn-replay` format (`tools/export_replay.py`; optional fields like `ghost`, `dnf` keep old viewers working).
- **Hub shell (garage workbench, `docs/ART_DIRECTION.md` is the art bible):** `screens/shell.tscn` is the persistent hub frame: pegboard wall + shop light, taped avatar/name, a receipt for cash/rep, a Dymo label for the location, and a tool-chest bottom nav (drawers with masking-tape labels: `$$$` / car / home / cal / team; open drawer = `DrawerOpenButton`). `game.gd` creates it once and swaps only its content (`open_hub(scene, tab)`), so the nav never rebuilds. Hub screens (`screens/warehouse`, `car`, `calendar`, `shop`) are content-only editor scenes; scripts only fill in data and emit `go(target)`. **Every data hook uses scene unique names (`%Name`)**, so nodes can be rearranged in the editor safely. Hub screens: home = Polaroid + work order; CAR = 3D lift + paper spec sheet + build sheet (tape pickers); `$$$` = flyers on a corkboard, the bench (unopened), a receipt-pad counter, the shelf; CAL = dry-erase whiteboard (`widgets/marker_mark.gd` draws circles / X's / underlines). The pull reveal is `screens/reveal.tscn` (full screen, no shell): box on the workbench -> OPEN IT -> DYNO IT prints a dot-matrix sheet (`show_reveal(inst, stage)`, stage box/dyno/sheet). Race night is full screen (no shell): `screens/meeting.tscn` (night turnout 3D hero `widgets/turnout_night.gd` with both cars nose to nose, Faba's speech bubble, clipboard tech sheet with an ink track map + stat card, push tabs with Faba's line + the risk, the bet as a fan of bills `widgets/cash_stack.gd`, SEND IT in red gaffer tape; it only emits signals, game.gd keeps `choice`) and `screens/results.tscn` (stamped verdict over the turnout, Faba's reaction, receipt, tow ticket, loot box). The replay is `main.gd`. `show_message()` is a Dymo title over a paper slip (loading, LIGHTS OUT, BROKE).
- **Theme:** ALL styling lives in `godot/theme.tres`. Fonts: Racing Sans One (titles, headings, big numbers, buttons; dark outline + shadow), Barlow Condensed (body; replaced Rajdhani), Permanent Marker (Sharpie), Doto (dot-matrix, dyno sheet only; variable font via FontVariation). Garage variations: GaffButton / GaffSmallButton (Sharpie on orange gaffer tape = main actions), GaffRedButton (SEND IT), SpeechPanel + SpeechLabel (Faba talking), ClipboardPanel, VerdictLabel (big rubber stamp), InkTrackMap, SmallTapeButton, PartPickButton (OptionButton), WhiteboardPanel + Whiteboard*Label (marker colors), CorkPanel, Flyer{Yellow,Pink,Blue}Panel + FlyerTitle/Text/PriceLabel, CardboardPanel, BenchPanel, DotMatrixPanel + DotMatrix(Big)Label, InkDynoChart (custom-drawn widgets read colors from their variation), TapeLabel, TapeButton, DymoLabel, InkLabel / InkMutedLabel / InkHeadingLabel (ink on paper), MarkerLabel (the builder's handwriting), StampLabel, PaperPanel, PolaroidPanel, ReceiptPanel, ToolChestPanel, DrawerButton / DrawerOpenButton; older: TitleLabel, HeadingLabel (burnt orange), MutedLabel, BigNumberLabel, RibbonLabel, StoryLabel, AccentButton (orange, slanted, lip), DangerButton, SelectedButton, TodayPanel, EventDayPanel. Textures in `godot/textures/` (CC0 ambientCG + generated; CREDITS.md). Dark text never gets the dark outline (it smears). Never hard-code the builder's notes in screens: add them to `voice.gd`. `game.gd add_grit()` = film grain + vignette over every screen. Never hard-code colors or sizes in screens; add a theme variation. Palette: SoCal canyon dusk (see ART_DIRECTION.md); #1A0F10 instead of black. Story screens: background #798071, text #1A0F10; crash slides add `widgets/splatter.gd`.
- **3D car:** `widgets/dx_model.gd` builds Faba's DX in code (EJ6 side profile extruded with CSG; Frost White, faded roof/hood, primer fender, steelies, missing hubcap; `build(part_ids)` shows hood/wheels/springs). `widgets/overlook.gd` = home hero (DX at a PCH turnout at dusk, still camera). `widgets/lift_bay.gd` = CAR hero (DX on a two-post lift in a dim bay, dusk through the roll-up door; sideways drag orbits within YAW_MIN..YAW_MAX, vertical swipes still scroll; `lights_on = false`). `widgets/pedestal.gd` is unused now. Placeholder until a real .glb.
- **Viewer (night broadcast):** world layer under a moonlit `CanvasModulate`, lit by each car's headlight `PointLight2D` (cone texture made in code) + a red taillight glow that flares under braking; grass and trees (`tree_spots`, seeded). Cars (`widgets/car_sprite.gd`: per-model top-down silhouettes and liveries, picked by keyword in the car name, drawn 1.35x), labels and effects sit on an overlay `CanvasLayer` (`follow_viewport_enabled`) so night doesn't darken them. Broadcast: 3-lamp start countdown (`countdown`), gap tower (running order + interval, OUT on a crash; ghost samples carry `s`), tire marks under hard braking/mistakes, crash = sparks/smoke/spin/shake + crash cam + gauges stall, finish flash. Gauges (`gauge.gd`): Type R cluster (white face, black numerals, red needle + redline). `widgets/road.gd` draws a two-lane road (asphalt, white edges, dashed yellow center, curbs on the outer edges striped in each corner's severity color). Car drives the right lane (`LANE_OFFSET_M = 2`, visual only). Cameras: Overview, Follow, Chase (car points up, world rotates; `Camera2D.ignore_rotation = false`), TV (corner cams, follows the car between them). Touch buttons for camera/pause/speed.
- **Solver settings:** anything the game compares uses `GAME_DS = 0.5` m (bridge). Monte Carlo caches in `runs/cache/` are keyed by car + parts + catalog + track + settings + a hash of the sim source.
- **Anti save-scum:** a race night's opponent is drawn once and saved; race results and consequences are applied and saved BEFORE the replay plays. Pull costs are saved before the pull resolves.
- **Saves are versioned** (`SAVE_VERSION`, currently 5) and migrated step by step in `migrate()`. Never wipe a save on a format change; add a migration step.
- **Planned (Phase 4):** port the sim to GDScript so the game runs on iPhone (Python can't run there). Python stays the reference; regression tests must show both give the same results. Don't start without asking.

```
sim/            physics + solvers (pure Python): car, forces, powertrain, dynamics, brakes,
                track, lap, straight, braking, driver, montecarlo, metrics, telemetry,
                parts, gacha, trackgen, opponents
data/cars/      car definitions (JSON inputs, each value with source + confidence)
data/tracks/    pace-note tracks; generated/ = procedural roads (open_week_N.txt are runtime cache)
data/parts/     catalog.json (24 parts, 14 slots), pulls.json (pull sources, pity, rep gates)
data/opponents.json   game-tuned opponent cars + drivers (+ calibrated engine condition)
data/rivals/    rival nights (which opponent, home road, payout)
tests/          pytest; expected values come from hand calcs in the physics spec
tools/          game_bridge, run_all, validation, plots, maps, compare, fade test, sensitivity,
                driver_study, export_replay, gen_tracks, calibrate_opponents
docs/           physics spec = `physics writeups/physics main.md` + `PHYSICS_updates_*.md` (one per
                milestone, section-numbered); VALIDATION_LOG.md (every model change), LEARNING_GODOT.md
godot/          game.gd, bridge.gd, ui.gd, main.gd (viewer), gauge.gd, track_map.gd,
                intro.tscn/.gd, screens/ (shell, warehouse, car, calendar, shop, header),
                widgets/ (pedestal, road, splatter, dyno_chart, practice_chart [unused now])
runs/           generated reports + caches (gitignored)
```

## Commands

```
.venv\Scripts\activate
python -m pytest -q                                   # ~205 tests, ~2 min (split by file if slow)
python tools/run_all.py [--track FILE] [--mass -100] [--runs 4]
python tools/validate_straight.py                     # validation table only
python tools/export_replay.py [track]                 # -> godot/replays/latest.json
python tools/gen_tracks.py [--style technical --count 9]   # procedural road sheet
python tools/calibrate_opponents.py [--only zed_280z]       # re-tune opponent engine condition
python tools/game_bridge.py <command> ...             # see the bridge docstring
```
Godot: the laptop has **4.7.2** (`Downloads/Program Installations/Godot_v4.7.2-stable_win64.exe/`; use the `_console.exe` for headless); project is on 4.7; scene files carry `unique_id`. Game: open `godot/project.godot`, F5 (needs the repo's .venv). Viewer alone: open main.tscn, F6.
Headless checks: `godot --headless --path godot -- --gametest` (one full night through the bridge); `godot --headless --path godot res://main.tscn -- --selftest` (viewer). Stills (need a display): `-- --gameshots=<folder>`, `res://main.tscn -- --shots=<folder>`.
Laptop: Windows (ASUS Vivobook S14), VS Code, Python 3.14, Git + GitHub (private repo `deadtildawn`).

## Conventions

- SI units inside the sim; convert only for display (`sim/units.py`).
- Car JSON stores inputs only. `Car` is a frozen dataclass; variants via `dataclasses.replace` (parts, opponents) — the stock car is never modified.
- One job per function; physics functions get hand-calc unit tests. The physics spec (`docs/physics writeups/physics main.md` + `docs/PHYSICS_updates_*.md`) gets an update file with physics changes. Log every model change in `docs/VALIDATION_LOG.md`.
- Validation targets come from measured data, never our own predictions. No knob-turning to match data.
- Fixed-point iteration for circular models (brake temperature over a lap, load transfer vs grip, traction).
- Results must be step-size converged. Game comparisons always use `GAME_DS`.
- Data files fail loudly on typos (unknown effects/slots raise).
- GDScript gotcha (hit 5x): `:=` can't infer a type from untyped Array elements or generic `InputEvent` fields. Type explicitly (`var x: float = ...`, `for side: float in [...]`).
- Godot layout gotchas: a PanelContainer stretches every child over each other (put ONE container inside); a wrapping Label inside an HBoxContainer, or with a SHRINK size flag anywhere, collapses to one character per line (`UI.label` wraps by default in columns: turn it off for stamps/tags).

## Physics model (detail in the physics spec, see docs/)

- QSS point mass, distance-based integration with event detection (fuel cut, shift end)
- Track: flat; pace notes like `S 200, R7 65, L1 180`; severity 1-10 = radius 15-500 m (geometric); strict parser; crossing detection
- Longitudinal: digitized torque curve, gearing, launch with clutch slip, 0.4 s shifts, rotational inertia (effective mass), drag, rolling resistance, **FWD or RWD traction** (`traction_limit`; load transfer + load-sensitive tires, fixed point). RWD check: 50/50 car, constant mu 0.9 hand calc 5926 N; sim with load sensitivity 5815 N.
- Shifting: sequential only; no money shifts; no mid-corner shifts
- Cornering: lateral load transfer (roll stiffness split), per-tire load sensitivity, axle-limited (stock DX understeers at 0.832 g)
- Braking: forward load transfer + load sensitivity; capacity ratio 1.3; rotor thermal model, pad fade above 350 C
- Driver: push level f (safe 0.947 / normal 0.954 / hard 0.972 / flat out 0.986) x driver `skill`; attempt ~ N(f, sigma) per corner; attempt > 1 = mistake (runs wide); **attempt > 1.025 = CRASH (DNF)**: the run ends at that corner's apex (`lap.dnf`, `lap.crash_corner`; compare runs with `finish_time()`, inf for DNF). Crash chance per 5-corner run: 0.02% / 0.09% / 2.1% / 12.2%. Corner technique: carry speed in, ease to the apex, roll on to the exit (rpm never steady); gentle slowing = feathered throttle, not brakes.
- Not yet: friction circle, elevation, aero/downforce, suspension dynamics, racing line (car follows the centerline)

## Car: 1996 Honda Civic DX coupe (EJ6, D16Y7, S40 5MT, FWD)

Sim mass 1112 kg. Redline 6500, fuel cut 6800. All graded validation targets pass: 0-60 9.92 s (target 9.9), quarter 17.74 s @ 80.3 mph, 60-0 138.1 ft. Top speed 121.5 mph and skidpad 0.832 g are report-only.

## Game design (current)

**Loop:** warehouse (hub) -> parts (pulls, counter, spares) -> calendar -> race night: briefing -> driver meeting (stat card, push, wager) -> SEND IT -> broadcast replay -> results (cash, rep, damage).

**Inspiration:** Hothead's Big Win series (build a team, open packs, watch a simulated race). NO real-money purchases; the physics, not stat bars, decides races. Dropped: call cards.

**Driver meeting (decided):** NO percentages and no practice chart (Spire: the chart was "win % made visual", too easy). The player sees a **stat card**: the DX vs the opponent's car (power, torque, weight, power/weight, drivetrain, 0-60, skidpad), the opponent's engine condition (tired/worn/healthy/fresh), and a one-line driver read ("Sharp, drives a steady pace..."). Push levels are described in words with what you're risking (`PUSH_TALK`). Every choice must carry severe consequences: easy to lose, easy to wipe progress.

**Opponents (decided):** simulated head-to-head. Each opponent = base car + changes (`data/opponents.json`: same effects as parts, plus drivetrain and weight split) + an authored driver (push, sigma, skill). Difficulty is tuned by engine `condition` (scales output; the stat card shows the true resulting hp), calibrated by `tools/calibrate_opponents.py` so a STOCK DX at its best push level has each opponent's `target_odds` (Zed 0.45 on his home road; street racers 0.35-0.60 on a balanced reference road). Opponents never track the player's upgrades (yet).

**Consequences (decided):** win +10 rep; any loss -5 rep; crash (DNF) -20 rep, wager lost, $150 body/tow, and EVERY installed part rolls: 10% destroyed, 40% damaged (off the car until repaired; repair = 30% of price). Both crash = no contest (wager returned, damage still applies). Rep floor 0; cash floor 0 -> BROKE screen. Skip a race night: -50 rep (5x a win), impossible below 50 rep.

**Parts + gacha:** catalog `data/parts/catalog.json` (24 parts, 14 slots: intake, header, cams, ECU, flywheel, shifter, final drive, tires, wheels, rear sway bar, springs, interior, hood, seats). `sim/parts.py apply_parts` returns a modified copy. Every owned part is a rolled INSTANCE (`sim/gacha.py`): hidden quality q in [0,1]; benefits scale up and drawbacks down with q; q = 0.5 = catalog numbers; fixed-spec parts (final drive, sway bars) don't roll. Pulls (`data/parts/pulls.json`): junkyard $80 (rep 0), swap meet $250 (rep 30), sealed crate $650 (rep 100) with rarity weights, quality ranges, and pity (guaranteed rarity within N pulls). New pulls are unopened until the free **dyno reveal**. The counter sells commons new (q 0.5). Spares sell for scrap (price x 0.25 x (0.5 + q)). Loot: 5% per win via the hidden "loot" source. The game never lets you spend below the $100 buy-in. Exact specs shown, never lap times. Bridge passes parts as `--parts id@quality,...`.

**Calendar:** week + day. Friday: the rival on his home road. Saturday: this week's generated open road (`open_road(week)`, style rotates technical/balanced/flowing) vs a random street racer from `opponents.json["street"]`.

**Procedural tracks:** `sim/trackgen.generate(seed, style)` -> pace notes; rejects crossings and near misses (min clearance 22 m); never two straights in a row. Lesson: "technical" requires packed corners.

**Economy:** start $250, $100 minimum buy-in, even money vs single racers. Boss battles (later): the lower-rep underdog puts up more.

**Rival club (Nissan ladder, later):** 280Z (Zed, rung 1, tired 124 hp L28) -> Sentra SE-R -> 240SX -> R33 GT-R -> R35 GT-R -> 370Z (final boss, inspired by Spire's best friend's car). Race each rival several times; rivals upgrade in proportion to the player, then the player moves up.

## Status

- [x] Phases 0-2, Milestones A-D (physics validated, driver model, sensitivity study)
- [x] Vertical slice, portrait UI, intro story, hub scenes, calendar, save migrations v1->v5
- [x] Parts v1 + gacha (pulls, pity, dyno reveal, rolled instances, counter, spares)
- [x] Procedural track generator; weekly open roads
- [x] UI overhaul v1: persistent hub shell, 3D pedestal, zero-radius theme
- [ ] **IN PROGRESS: head-to-head opponents + crashes** (see below)
- [ ] Rival ladder (Nissan club), tuning keys/sliders, pink slips, brakes + aero (need elevation / downforce)
- [ ] **Art direction (docs/ART_DIRECTION.md):** step 1 foundation + home DONE; step 2 CAR lift, `$$$` corkboard + reveal, CAL whiteboard DONE; step 3 race night at the turnout DONE (rough pass, awaiting Spire's feedback; the opponent is the DX body in his replay paint until per-car models exist); next: replay locations, TEAM board. Builder's-voice lines (Spire's own words) live in `godot/voice.gd`: home caption (game.gd `home_caption()`: skipped > crashed > win streak > loss streak > parts on), lift note, flyer scribbles, dyno margin note, whiteboard doodles (middle finger for the rival, sad face after a loss), BROKE title. Faba's lines (meeting: rival/open night, one per push level, big bet; results: won/lost/crashed/no contest) are in the same file.
- [ ] Showcase materials (poster/slides, demo) — due early Dec 2026
- [ ] Phase 4: GDScript port; Phase 5: iPhone

## IN PROGRESS: head-to-head opponents + crashes (pick up here)

**Done (Python, tested where noted):**
- RWD traction: `Car.drivetrain` ("FWD"/"RWD", default FWD), `forces.traction_limit_rwd_ls`, `forces.traction_limit` used by `dynamics.car_constants`.
- Crash model: `driver.CRASH_MARGIN`, `CornerAttempt.crash`, `Driver.skill`, `Driver.crash_chance_per_corner()`; `lap._apply_crash` truncates telemetry at the crash apex; `lap.finish_time()`; `montecarlo.Distribution` treats DNF as inf (`finished`, `dnf_rate`; mean/stdev over finished runs).
- Opponents: `data/opponents.json` (13 opponents, conditions calibrated), `sim/opponents.py` (`opponent_car`, `opponent_driver`, `driver_read`, `condition_label`, `head_to_head`), `tools/calibrate_opponents.py`.
- Bridge: `stat_sheet(car)`, `opponent_card(oid)`; `rival` and `street` now return a stat card (NO posted time); `race --opponent ID --opp-seed N` runs both cars and returns `won`, `no_contest`, `dnf`, `crash_corner`, `opponent_time`, `opponent_dnf`, `opponent_crash_corner`; replay carries `ghost` {name, car, lap_time, dnf, crash_corner, samples{t,x,y,heading}} plus `dnf`/`crash_corner`.
- `data/rivals/zed_280z.json` now points at opponent `zed_280z`.

**Done (Godot):** `game.gd` head-to-head flow (briefing -> stat-card meeting -> race with `--opponent` -> consequences -> results); shop DAMAGED section + `repair`; viewer ghost car (own time base, translucent, blue ring, CRASHED tag), crash/no-contest banner using the bridge's win rule, `--replay=<path>` flag; `game_test()` has pass/fail `check()`s with hand-calc expectations (crash, no contest, repair) and exits 1 on failure; test runs use `user://test_save.json`, never the real save.

**Done (tests + docs):** 205 tests pass (RWD hand calc, crash rates, DNF lap, `tests/test_opponents.py`, head-to-head bridge contract). Spec update `docs/PHYSICS_updates_E.md`; VALIDATION_LOG row 6 + notes. `driver_study` plot fixed for DNF runs. `data/street_racers.json` deleted.

**Remaining:**
1. Spire: play a few nights by hand (F5) to judge difficulty. Headless checks pass.
2. Decide (see open questions): opponent crash risk, the odds cliff, close-race readability in the replay.
3. ~~Update the shop.tscn Note label~~ done (art step 2).

**Open design questions:** should opponents upgrade as the player does (ladder rule)? Should a crash ever destroy the car itself (pink-slip-like)? Retune rep gates and crash numbers after playtesting. **Opponents almost never crash:** skill multiplies the push target, so "flat out" Cutter (skill 0.92) aims below Faba's Safe; should low skill raise sigma instead? **Odds cliff:** Zed's odds go 0.49 -> 0.09 for a 1% engine change; one $350 part takes them 0.38 -> 0.78 (PHYSICS_updates_E 6.y). **Close races are unreadable in the replay:** both cars share a lane and overlap; options: ghost in the other lane, a live gap readout, or both.

## Parking lot

Blueprinting (duplicates raise a part's build level), CanyonList used market with scam risk, wear, sponsors, driver training (lowers sigma), elevation (downhill/hill climb), engine swaps, turbo lag, surface bumps, getting snuffed (rival flees: $0, double rep), real racing line.
