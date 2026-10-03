# deadtildawn

2D mobile touge racing RPG (portrait). Story: six years ago the player was a legend of the SoCal canyon scene in a self-built 2009 Civic Si (FA5). In a $50k race, one corner too hot at 87 mph: the car hit a tree and burned, and the player survived but lost strength and feel in the right leg and left the scene. Best friend **Faba** got them back on their feet. Six years later Faba quits his corporate job, buys a stock '96 Civic DX coupe 5MT, and spends his savings on a warehouse (home + HQ): "You build it. I drive it." The player never drives: races are physics simulations shown as a broadcast-style replay with live telemetry. (Intro text lives in `godot/intro.gd` SLIDES.)

The physics simulator is also my Physics 3 showcase project (due ~early December 2026): "Can first-year physics predict a real car's performance?"

## How to work with me

- I'm a mechanical engineering student learning engineering workflow, not just shipping code. Explain the reasoning behind design choices, not only what the code does.
- I make the large-scale decisions (scope, features, architecture direction). Offer 2-3 options with tradeoffs and a recommendation, then let me decide.
- I like to derive physics myself and predict results before code runs. Hand calcs become tests.
- Give honest, direct assessments. Point out errors, scope creep, and weak assumptions.
- Work iteratively: rough version first, then refine. Don't jump ahead to later milestones without asking.
- When you hand me files, tell me exactly where each one goes in the repo.

## Architecture

- **Python (`sim/`) is the physics engine and the reference implementation.** A lap run returns telemetry. Any future vehicle model must honor that interface.
- **Godot (`godot/`) is the game.** `game.tscn` (game.gd) runs the vertical slice; `main.tscn` (main.gd) is the replay viewer, used standalone or embedded in the race screen. Godot does no physics: it calls `tools/game_bridge.py` (Python) in a background thread (`bridge.gd`) and reads one JSON reply per command (versioned contract, tested in `tests/test_bridge.py`). Replays use the `deadtildawn-replay` format (`tools/export_replay.py`, tested in `tests/test_tools.py`).
- **Hub screens are editor scenes** in `godot/screens/` (warehouse, car, calendar, plus a shared `header.tscn` instanced into each). Layout lives in the `.tscn` (Spire edits these in the editor); each script only fills in data and emits `go(target)`, which `game.gd` routes. Keep node names stable or update the script's paths. Race-night screens (meeting, results) are still code-built in `game.gd`.
- **Menus:** ALL styling lives in `godot/theme.tres` (Rajdhani font; type variations TitleLabel, HeadingLabel, MutedLabel, BigNumberLabel, AccentButton, DangerButton, SelectedButton, TodayPanel, EventDayPanel). Never hard-code colors or sizes in screens; add a theme variation. Spire is learning the editor: prefer editor-editable scenes (`.tscn`) for new screens (see `intro.tscn`, `docs/LEARNING_GODOT.md`). Labels only wrap inside columns (the wrap trap); a screen's main action goes in the pinned footer.
- **Palette (Spire):** menu body text #F9F4F5, accent / kicker / DEADTILDAWN title #D64045, #1A0F10 instead of black (app background, text on accent buttons). Story: background #798071, text #1A0F10, kicker and title #D64045; crash slides add a splatter (`widgets/splatter.gd`). In the practice chart, red means danger (rival line, mistakes), so selection is light, not accent. Viewer HUD and gauges keep their own colors for now.
- **Road (viewer):** `widgets/road.gd` draws a two-lane road: asphalt, white edge lines, dashed yellow center line, curbs on both outer edges through corners striped in the corner's severity color. The car drives the right-hand lane (`LANE_OFFSET_M = 2`); visual only, physics uses the centerline radius (a real racing line is a future physics upgrade).
- **Viewer cameras:** Overview, Follow, Chase (car always points up, world rotates; needs `Camera2D.ignore_rotation = false`), TV (corner cameras; follows the car between them). Touch buttons for camera, pause, speed.
- **Odds and races use identical solver settings** (`GAME_DS = 0.5` m in the bridge) or the odds lie. Monte Carlo distributions are cached in `runs/cache/`, keyed by car + track + settings + a hash of the sim source code (any sim change invalidates old odds automatically).
- **Anti save-scum:** tonight's rival posted time is drawn once and saved; race results are applied and saved before the replay plays.
- **Planned (Phase 4):** port the sim to GDScript so the game runs on iPhone (Python can't run there). Python stays the reference; regression tests must show both versions give the same results. Don't start the port without asking.

```
sim/          physics + solvers (pure Python)
data/cars/    car definitions (JSON, inputs only, each value with source + confidence)
data/tracks/  pace-note tracks (test_track.txt, switchbacks.txt)
tests/        pytest; expected values come from hand calcs in docs/PHYSICS.md
tools/        run_all, validation, plots, maps, comparison, fade test, replay export
docs/         PHYSICS.md (the spec), VALIDATION_LOG.md (every model change + results)
godot/        game (game.gd, bridge.gd, ui.gd, track_map.gd) + replay viewer (main.gd, gauge.gd)
data/rivals/  rival definitions (name, car, track, difficulty)
runs/         generated reports (gitignored)
```

## Commands

```
.venv\Scripts\activate
python -m pytest -v                                   # ~141 tests, ~90 s
python tools/run_all.py [--track FILE] [--mass -100] [--runs 4]
python tools/validate_straight.py                     # validation table only
python tools/export_replay.py [track]                 # -> godot/replays/latest.json
python tools/run_all.py --push hard --seed 7 --rival 49.55   # driven run + odds
python tools/driver_study.py --rival 49.55            # push-level odds only
python tools/sensitivity.py                           # tornado charts
```
Game: open `godot/project.godot` in Godot 4.5+, press F5 (needs the repo's .venv with the requirements installed). Viewer alone: open main.tscn, press F6.
Godot checks: `godot --headless --path godot -- --gametest` (one full night through the bridge); `godot --headless --path godot res://main.tscn -- --selftest` (viewer); stills: `-- --gameshots=<folder>` or `res://main.tscn -- --shots=<folder>` (need a display).

Windows laptop (ASUS Vivobook S14), VS Code, Python 3.14, Git + GitHub.

## Conventions

- SI units inside the sim; convert only for display (`sim/units.py`).
- Car JSON stores inputs only. Never store values the model can compute (e.g. the front brake heat share comes from the braking model).
- `Car` is a frozen dataclass; variants via `dataclasses.replace` (upgrades, comparisons).
- One job per function; physics functions get hand-calc unit tests.
- `docs/PHYSICS.md` is the spec. Update it before or with physics changes.
- Validation targets come from measured data, never from our own predictions. Acceptance criteria are set before tuning. No knob-turning to match data (overfitting); only physically justified changes, each logged in `docs/VALIDATION_LOG.md`.
- Low-confidence targets are report-only (top speed, skidpad).
- Models with memory or circular dependencies use fixed-point iteration (brake temperature over a lap, load transfer vs grip).
- Numerical results must be step-size converged (tests check this).

## Physics model (detail in docs/PHYSICS.md)

- QSS point mass, distance-based integration with event detection (fuel cut, shift end)
- Track: flat; pace notes like `S 200, R7 65, L1 180`; severity 1-10 = radius 15-500 m (geometric); strict parser; crossing detection
- Longitudinal: digitized torque curve, gearing, launch rpm with clutch slip, 0.4 s shifts (road-test value), rotational inertia (effective mass), drag, rolling resistance, FWD traction with load transfer + load-sensitive tires
- Shifting: sequential only; downshift only if the engine lands at or below redline (no money shifts); no mid-corner shifts
- Cornering: lateral load transfer (roll stiffness split, wheel lift), per-tire load sensitivity, axle-limited (stock car understeers at 0.832 g)
- Braking: forward load transfer + load sensitivity, ideal bias; brake capacity ratio 1.3; rotor thermal model (Newton cooling), pad fade above 350 C; fixed-point iteration over the lap; back-to-back runs carry rotor temperature
- Driver: push level sets f; attempt ~ N(f, sigma) per corner; attempt > 1 = mistake (runs wide, scrubs speed); corner technique: carry speed in and ease down to the apex, then roll on to the exit (speed and rpm never steady in a corner); slowing gentler than coasting = feathered partial throttle, not brakes; brakes at f of max; seeded runs
- Not yet: friction circle, elevation, aero balance, suspension dynamics

## Car: 1996 Honda Civic DX coupe (EJ6, D16Y7, S40 5MT, FWD)

Sim mass 1112 kg. Redline 6500, fuel cut 6800. Rear drums, no ABS. All graded validation targets pass: 0-60 9.92 s (target 9.9), quarter 17.74 s @ 80.3 mph, 60-0 138.1 ft. Top speed 121.5 mph and skidpad 0.832 g are report-only.

## Status and plan

- [x] Phase 0: setup
- [x] Phase 1: physics theory
- [x] Milestone A: straight-line sim, validated
- [x] Milestone B: track parser, lap solver, braking validation, sequential shifting, maps, comparison tool, run_all reports
- [x] Milestone C: brake heat and fade; cornering load transfer + load sensitivity
- [x] Godot replay viewer (3 cameras, analog gauges)
- [x] Phase 2 exit: sensitivity study (mass > grip ~ power >> rest; brakes zero on flat roads)
- [x] Milestone D: driver model (push levels, sigma 0.02, physical mistakes, slow in / fast out, Monte Carlo odds)
- [x] Vertical slice v0.1: garage, briefing + driver meeting (odds per push, wager), Send It, broadcast replay vs rival time, results, save, broke screen
- [x] Portrait UI pass: theme + Rajdhani font, intro story scene, warehouse HQ, pinned-footer driver meeting, chase camera, touch camera controls
- [x] Hub scenes (warehouse, car with dyno chart, calendar), weekly calendar (race nights Fri + Sat, skip allowed), save migration v1 -> v2, practice-run dot chart replaces win % (revealed after the race as "your read")
- [x] Parts v1: 24 parts in 14 slots (engine: intake/header/cams/ECU/flywheel; trans: shifter/final drive; tires; wheels; suspension: rear sway bar/springs; weight: interior/hood/seats). Shop (exact specs, no lap times), install via car-screen dropdowns, 5% loot chance per win, save v3
- [x] Procedural track generator v1 (`sim/trackgen.py`, `tools/gen_tracks.py`): seeded, styles technical / balanced / flowing, rejects crossings and near misses (min clearance 22 m between road centerlines), never two straights in a row. Not yet wired into the game.
- [x] Gacha core (Python): rolled part instances (`sim/gacha.py`: hidden quality q in [0,1]; benefits scale up and drawbacks scale down with q; q = 0.5 = catalog numbers; fixed-spec parts like final drives and sway bars don't roll), in-world pull sources (`data/parts/pulls.json`: junkyard $80 / swap meet $250 / sealed crate $650, rarity weights, quality ranges, pity per source), bridge `pull` command and `--parts id@quality`.
- [x] Gacha in Godot: Parts screen (pulls with rep gates + pity, unopened parts, commons counter, spares to sell for scrap), dyno reveal screen, inventory of rolled instances (save v4: `inventory`, `installed` slot -> uid, `pity`), install by instance. Loot: 5% per win, via the hidden "loot" pull source. Rep gates: swap meet 30, crate 100 (Spire will retune).
- [x] Weekly calendar: Friday = rival on his home road; Saturday = this week's generated open road (style rotates technical / balanced / flowing) vs a random street racer (`data/street_racers.json`, posted time anchored to the stock car, best-push odds 35-60%).
- [ ] NEXT: simulated rivals + consequences (decided): the driver meeting shows a stat card comparing your car with the opponent's (no practice chart, no percentages); opponents are simulated (own car + driver, own randomness) instead of posted times. Pushing harder risks CRASHES (DNF = wager lost, damage or destruction of installed parts, repair bills) and every loss costs rep. Theme: easy to lose, easy to wipe progress.
- [x] UI overhaul v1 (Spire's brief): persistent hub shell `screens/shell.tscn` (top rail: avatar, driver name, cash, rep; red location ribbon; content slot; bottom nav: $ / CAR / WHSE / CAL / XTR reserved). game.gd creates the shell once and swaps only its content (`open_hub(scene, tab)`); race-night screens (meeting, reveal, results, replay) take the full screen. Hub scenes (warehouse, car, calendar, shop) are content-only and use scene unique names (%Name) for every data hook. 3D hero pedestal `widgets/pedestal.gd`: low-poly '96 Civic coupe from primitives on a turntable (SubViewport), placeholder until a real model. Theme: zero corner radius. Spire edits scenes locally: ask for his latest scene files before changing them; never overwrite blindly.
- Godot version: Spire uses Godot 4.6 (scene files carry `unique_id`). Test with 4.6.1.
- Parking lot: blueprinting (duplicates raise build level). Dropped: call cards (Spire: the fun is building the team and watching it perform).
- [ ] Spire: UI styling pass (colors, buttons, layout of the hub scenes)
- [ ] Next: rival ladder (Zed becomes easy after one or two good parts), tuning keys/sliders, brakes + aero slots (need elevation / downforce physics)
- [ ] Showcase materials (poster/slides, demo)
- [ ] Phase 3: game systems design; Phase 4: Godot game + GDScript port; Phase 5: iPhone

## Game scope

**Loop:** pre-race (inspect track profile, install parts, tune sliders, set wager, "Send It") -> race (broadcast replay + live HUD) -> results (cash, rep).

**Driver meeting design:** no win percentages. The player reads a practice-run chart (60 dots per push level vs the rival's posted-time line; red = mistake runs; axis zoomed on the decision zone, slow outliers pinned as edge arrows). After the race, results reveal how many practice runs beat the rival ("your read") so players can calibrate. `odds` in the bridge is for dev tools only.

**Inspiration:** Hothead's Big Win series (Big Win Racing / Football): build a team, open packs, play impact cards, watch a simulated race. deadtildawn keeps the pack-and-sim loop but has NO real-money purchases, and the physics (not stat bars) decides races.

**Procedural tracks:** `generate(seed, style)` returns pace notes; same seed + style = same road. Style knobs live in the STYLES table (severity weights, corner angles by band, straight lengths, same-direction and linked-corner chances, length range). Lesson: a road is only "technical" if corners are packed together (long straights make any road a power track).

**Parts:** catalog in `data/parts/catalog.json`; `sim/parts.py` `apply_parts(car, parts)` returns a modified copy (stock car untouched, validation unaffected). Effects are changes to real sim inputs (torque_scale, torque_shape, mass_kg, engine/wheel inertia, shift_time_s, final_drive, mu_scale [scales mu at every load], load_k_scale, crr_scale, roll_front, cg_height_m); unknown effects fail loudly. One part per slot. Rarity = specialization (e.g. the 4.9 final drive is slower on tight roads; the 24 mm rear bar overshoots the roll-balance optimum). Realistic magnitudes: bolt-ons are a few hp; tires and weight are the big wins. The shop shows exact specs, never lap times. Bridge takes `--parts a,b` for car_stats / practice / race; the practice cache key includes the parts and the catalog. **Rival times are anchored to the stock car** (upgrades never make the rival faster). The shop won't spend below the race buy-in (design call, revisitable). Loot: 5% per win, weighted common 50 / rare 30 / epic 15 / legendary 5.

**Calendar:** week + day (Mon-Sun). Race nights Fri and Sat vs the current rival; other days empty until parts/repairs. Skipping a race night costs 50 rep (5x a win, the "chicken-out fee"); with less than 50 rep you must race. Skips are logged in history but don't count as losses. Saves carry a version and are migrated step by step (`migrate()` in game.gd); never wipe a save on a format change.

**Economy (slice):** start $250, minimum buy-in $100, even-money payouts vs single racers, +10 rep per win. Boss battles (later): the lower-rep underdog puts up more. Rival difficulty: posted time set so the player's best push level wins ~45% on an average night, plus nightly randomness (0.10 s). At even money that is a losing bet without upgrades: intentional pressure. Goal: hard, every win should feel earned.

**Rival club (Nissan ladder, later):** 280Z -> Sentra SE-R -> 240SX -> R33 GT-R -> R35 GT-R -> 370Z (final boss, above the GT-Rs; inspired by the friend's car). Race each rival several times (e.g. 3); rivals upgrade in proportion to the player, then the player moves up. Slice: one rival, "Zed", 1977 280Z (placeholder name, `data/rivals/zed_280z.json`), posted time only. Later: simulated rival car + driver (both can make mistakes, both on the road).

**v1:** cash + rep, wagers, rival ladder -> boss club, parts where rarity is not superiority (specialized tradeoffs), first tuning sliders (roll stiffness / sway bar), 4 fixed push levels, broadcast replay.

**v1.1:** pink slip permadeath (deletes the save on a loss), CanyonList used market with scam risk (hidden defects in the physics), wear and repairs, "getting snuffed" (rival flees: $0 cash, double rep), sponsors, driver training points and stats, elevation (downhill / hill climb), procedural tracks, engine swaps, harder-to-judge risk.

**Later:** crashes and repairs, surface bumps (suspension dynamics), turbo lag (boost model), merch.

Design notes: tuning keys (better parts unlock more sliders); show odds before pink-slip races; watch for rep farming via snuffed events. Brake parts do nothing on flat roads (no fade, tire-limited stops): they need elevation, faster cars, or back-to-back runs to matter. Aero matters only at speed. Push level is a variance choice: favorites play safe, underdogs push.
