# deadtildawn

2D mobile touge racing RPG. The player is a gifted mechanic who can no longer drive (career-ending injury to the throttle leg in a canyon crash). The player's friend drives. The player builds, tunes, and coaches, turning a stock 1996 Civic into a giant-killer against wealthy underground car clubs. The player never drives: races are physics simulations shown as a broadcast-style replay with live telemetry.

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
- **Godot (`godot/`) is currently a replay viewer only.** It reads `replay.json` (format `deadtildawn-replay`, versioned; contract in `tools/export_replay.py`, tested in `tests/test_tools.py`). It does no physics.
- **Planned (Phase 4):** port the sim to GDScript so the game runs on iPhone (Python can't run there). Python stays the reference; regression tests must show both versions give the same results. Don't start the port without asking.

```
sim/          physics + solvers (pure Python)
data/cars/    car definitions (JSON, inputs only, each value with source + confidence)
data/tracks/  pace-note tracks (test_track.txt, switchbacks.txt)
tests/        pytest; expected values come from hand calcs in docs/PHYSICS.md
tools/        run_all, validation, plots, maps, comparison, fade test, replay export
docs/         PHYSICS.md (the spec), VALIDATION_LOG.md (every model change + results)
godot/        replay viewer (main.gd builds the scene in code; gauge.gd)
runs/         generated reports (gitignored)
```

## Commands

```
.venv\Scripts\activate
python -m pytest -v                                   # ~127 tests, ~50 s
python tools/run_all.py [--track FILE] [--mass -100] [--runs 4]
python tools/validate_straight.py                     # validation table only
python tools/export_replay.py [track]                 # -> godot/replays/latest.json
python tools/run_all.py --push hard --seed 7 --rival 49.55   # driven run + odds
python tools/driver_study.py --rival 49.55            # push-level odds only
python tools/sensitivity.py                           # tornado charts
```
Godot viewer: open `godot/project.godot` in Godot 4.5+, press F5. Headless check: `godot --headless --path godot -- --selftest`. Stills: `-- --shots=<folder>` (needs a display).

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
- Driver: push level sets f; attempt ~ N(f, sigma) per corner; attempt > 1 = mistake (runs wide, scrubs speed); slow in / fast out; brakes at f of max; seeded runs
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
- [ ] Vertical slice: Godot game screens calling the Python sim on the laptop (garage, briefing, wager + push, Send It, replay, results); GDScript port later
- [ ] Showcase materials (poster/slides, demo)
- [ ] Phase 3: game systems design; Phase 4: Godot game + GDScript port; Phase 5: iPhone

## Game scope

**Loop:** pre-race (inspect track profile, install parts, tune sliders, set wager, "Send It") -> race (broadcast replay + live HUD) -> results (cash, rep).

**v1:** cash + rep, wagers, rival ladder -> boss club, parts where rarity is not superiority (specialized tradeoffs), first tuning sliders (roll stiffness / sway bar), 4 fixed push levels, broadcast replay.

**v1.1:** pink slip permadeath (deletes the save on a loss), CanyonList used market with scam risk (hidden defects in the physics), wear and repairs, "getting snuffed" (rival flees: $0 cash, double rep), sponsors, driver training points and stats, elevation (downhill / hill climb), procedural tracks, engine swaps, harder-to-judge risk.

**Later:** crashes and repairs, surface bumps (suspension dynamics), turbo lag (boost model), merch.

Design notes: tuning keys (better parts unlock more sliders); show odds before pink-slip races; watch for rep farming via snuffed events. Brake parts do nothing on flat roads (no fade, tire-limited stops): they need elevation, faster cars, or back-to-back runs to matter. Aero matters only at speed. Push level is a variance choice: favorites play safe, underdogs push.
