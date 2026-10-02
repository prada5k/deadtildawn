# deadtildawn

2D mobile touge time-attack racing RPG. The player is a mechanic/engineer who builds and tunes a car; a driver friend races it. The player never drives: races are physics simulations played back as live telemetry.

The physics simulator is also my Physics 3 showcase project (due ~early December 2026): "Can first-year physics predict a real car's performance?" Derive the model from course concepts, build it, validate it against measured data for a 1996 Civic.

## How to work with me

- I am a mechanical engineering student learning engineering workflow, not just shipping code. Explain the reasoning behind design choices, not only what the code does.
- I make the large-scale decisions (scope, features, architecture direction). Offer 2-3 options with tradeoffs and a recommendation, then let me decide.
- I want to derive physics myself where possible. Guide me with hints and check my work rather than handing over answers, unless I ask for the answer.
- Give honest, direct assessments. Point out errors, scope creep, and weak assumptions.
- Work iteratively: rough version first, then refine. Don't jump ahead to later milestones without asking.

## Architecture

The sim core knows nothing about the game. Fixed interface:

```
simulate(car, track, driver, push_level) -> telemetry
```

Any future vehicle model (bicycle, full vehicle) must honor this contract.

```
sim/        physics + solver (pure Python)
data/cars/  car definitions (JSON)
data/tracks/ track files (pace-note format)
tests/      pytest tests, expected values from hand calculations
tools/      plotting, stats viewer, validation report
docs/       PHYSICS.md = the physics spec
```

## Commands

```
.venv\Scripts\activate
python -m pytest -v
```

Windows laptop, VS Code, Python 3.12, Git + GitHub.

## Conventions

- SI units everywhere inside the sim. Convert only for display. All conversions and constants live in `sim/units.py`.
- Car JSON stores inputs only, each as `{value, unit, source, confidence}`. Never store derived values (gear top speeds, power-to-weight); compute them in code.
- `Car` is a frozen dataclass. Upgrades create modified copies.
- Each physics function does one job (e.g. `wheel_force` ignores traction; the traction cap is separate).
- Every physics function gets a unit test whose expected value comes from a hand calculation documented in `docs/PHYSICS.md`. Tests name the calculation they check.
- `docs/PHYSICS.md` is the spec. If code and spec disagree, one of them is a bug. Update the spec before changing physics.
- Validation targets come from measured data, never from our own model's predictions.

## Physics model (summary; full detail in docs/PHYSICS.md)

- QSS point mass with quasi-static load transfer
- Track: flat, corner severity 1-10 maps geometrically to radius (15 m to 500 m), format `S 200, R3 90, L1 180`
- Cornering: v = sqrt(mu*g*R), downforce extension, tire load sensitivity mu = mu0 - k*Fz
- Longitudinal: torque curve -> gears -> wheel force, FWD traction limit with load transfer, drag, rolling resistance, launch RPM with clutch slip, fixed shift time
- Braking: grip limit vs brake system limit, thermal fade on front discs (rear drums assumed non-fading), fixed-point iteration
- Driver: 4 fixed push levels (target fraction f of limit, consistency sigma, mistakes when attempt > 1.0)

## Car: 1996 Honda Civic DX coupe (EJ6, D16Y7, S40 5MT, FWD)

Data and sources in `data/cars/ej6_dx_coupe_1996.json`. Sim mass ~1112 kg. Redline 6500, fuel cut 6800. Rear drums, no ABS.

Validation targets: 0-60 mph 9.9 s; quarter mile 17.4-17.7 s @ 78-80 mph; 60-0 mph 135-142 ft. Top speed 112 mph is low confidence (report only, not pass/fail).

## Status and plan

Phase 0 (setup) done. Phase 1 (physics theory) done. Now in Phase 2 (sim prototype), v0.9 milestones:

- [x] Week 1: car loader, units, torque curve, powertrain functions + tests
- [ ] Milestone A: traction limit, drag, straight-line solver; validate 0-60 / quarter mile / top speed
- [ ] Milestone B: track parser, cornering, braking, full lap (QSS forward/backward pass), telemetry plots; validate 60-0
- [ ] Milestone C: tire load sensitivity (calibrate vs braking), brake heat + fade
- [ ] Milestone D (after showcase): driver model, Monte Carlo, stats viewer

Cut line: if behind at end of week 5, drop load sensitivity from the showcase; keep brake fade.

Cut from v0.9: aero/downforce numerical solver (stock car has no downforce; keep drag), parts, betting, game UI.

## Later (not now)

v1: betting, rival ladder -> boss club, telemetry playback UI in Godot. v1.1: procedural tracks, driver stats, wear/repair, crashes, used parts market, tuning, engine swaps, elevation.
