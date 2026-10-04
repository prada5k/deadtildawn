# Validation Log

Every change to the model gets a row: what changed, the physical reason, and the result. Knobs are only changed with an independent physical justification, never just to match the targets (overfitting).

## Acceptance criteria (set before tuning)

| Test | Target | Tolerance |
|---|---|---|
| 0-60 mph | 9.9 s | +/-5% |
| Quarter mile time | 17.4-17.7 s | +/-1.5% outside range |
| Quarter mile trap | 78-80 mph | +/-1.5% outside range |
| 60-0 mph braking | 135-142 ft | +/-1.5% outside range |
| Skidpad | 0.75-0.85 g | Report only (plausibility band, no measured DX data) |
| Top speed | 112 mph | Report only (low confidence) |

## Log

| # | Change | Physical reason | 0-60 | Quarter | Trap | 60-0 | Top speed | Result |
|---|---|---|---|---|---|---|---|---|
| 0 | Baseline: point mass, torque curve, gearing, FWD traction with load transfer, drag, rolling resistance, 3000 rpm launch, 0.4 s shifts | — | 8.95 s (-9.6%) | 17.13 s (-1.6%) | 82.2 mph (+2.8%) | — | 121.5 mph | FAIL: too fast, worst at low speed |
| 1 | Rotational inertia (effective mass), engine decoupled during shifts/clutch slip, inertia-aware traction check | Engine + wheels must be spun up; engine inertia scales with gear ratio squared, matching the low-gear error pattern | 9.93 s (+0.3%) | 17.74 s (+0.2%) | 80.2 mph (+0.3%) | — | 121.5 mph | PASS |
| 2 | Refactor into dynamics.py; event detection at fuel cut and shift end; braking test added (grip-limited, ideal bias, wheel inertia, drag, rolling resistance) | Shift points exact at 6800 rpm; braking validates mu independently of the engine model | 9.92 s (+0.2%) | 17.74 s (+0.2%) | 80.3 mph (+0.3%) | 132.0 ft (-2.2%) | 121.5 mph | FAIL: braking too short (mu too high, or missing physics) |
| 3 | Braking with forward load transfer + per-tire load sensitivity (fixed-point iteration); sequential shifting with no money shifts | Overloaded front tires gain less grip than unloaded rears lose (predicted ~4.8% grip loss, ~138 ft) | 9.92 s (+0.2%) | 17.74 s (+0.2%) | 80.3 mph (+0.3%) | 138.1 ft (in range) | 121.5 mph | PASS |
| 4 | Brake heat + fade: rotor energy balance, pad mu vs temperature, capacity ratio 1.3, fixed-point iteration over the lap | Heat from braking must go somewhere; pads lose friction when hot | 9.92 s (+0.2%) | 17.74 s (+0.2%) | 80.3 mph (+0.3%) | 138.1 ft (cold, unchanged) | 121.5 mph | PASS (fade checked by hand calcs; no measured fade data exists) |
| 5 | Cornering: lateral load transfer (roll stiffness split, wheel lift), per-tire load sensitivity, axle-limited balance; load-sensitive FWD traction | Outside tires gain less grip than inside tires lose; the most-loaded axle saturates first (understeer) | 9.92 s (+0.2%) | 17.74 s (+0.2%) | 80.3 mph (+0.3%) | 138.1 ft (unchanged) | 121.5 mph | PASS; skidpad 0.832 g (report-only band 0.75-0.85 g) |
| 6 | RWD traction option (`Car.drivetrain`; load-sensitive rear axle, fixed point); crash model (attempt > 1.025 = DNF, run ends at the apex) | A RWD car's driven axle gains load under acceleration; a big enough overshoot leaves the road instead of running wide | 9.92 s (+0.2%) | 17.74 s (+0.2%) | 80.3 mph (+0.3%) | 138.1 ft (unchanged) | 121.5 mph | PASS (stock DX is FWD: unchanged); RWD hand calc 5926 N = sim at constant mu |

## Notes

**Change 1 sensitivity:** swept $I_e$ 0.10-0.15 kg·m² and $I_w$ 0.7-0.9 kg·m². All cases pass (0-60: 9.77-10.15 s; quarter: 17.64-17.88 s; trap: 79.8-80.5 mph). The match does not depend on the exact inertia estimates.

**Model finding:** with inertia included, the stock car is never traction-limited in a straight-line run. Plausible for 106 hp, but sensitive to $\mu$, which is not yet calibrated (Milestone C, braking target).

**Caution:** a close match can hide compensating errors (e.g. one input too high, another too low). The braking validation in Milestone B tests $\mu$ independently.

**Top speed:** sim 121.5 mph (drag-limited in 4th at ~6400 rpm) vs 112 mph listed. Consistent with the earlier drag estimate; target remains low confidence.

**Change 2, braking result:** the sim stops ~2.2% short of the measured range. Hand prediction (grip + wheel inertia, no drag) was 135.9 ft; drag and rolling resistance shorten it to 132.0 ft. Leading hypothesis: missing physics, not a wrong mu. Under braking, ~1.9 kN of load transfers to the front axle; with tire load sensitivity, the overloaded fronts gain less grip than the rears lose. Estimated total grip loss: ~4.8%, which would land the stop near ~138 ft (mid-range). This is the dynamic load sensitivity planned for Milestone C. Other possible contributors: non-ideal real brake bias, a no-ABS driver unable to hold peak grip.

**Change 3:** braking landed at 138.1 ft, matching the ~138 ft prediction made *before* the code was written. Acceleration results unchanged (the stock car is never traction-limited, and braking physics doesn't affect acceleration). Lap time on the test track: 48.31 s -> 48.35 s (longer braking zones, sequential downshifts).

**Change 4 (fade):** no published fade data exists for a 1996 DX, so the model is checked by energy hand calcs made before coding: 65.7 C per 60-0 stop (sim 65.0), fade onset during stop 5, first longer stop = stop 7 (both exact). Cold results unchanged. Finding: on flat roads the stock brakes reach thermal equilibrium below the point where fade costs distance (test track ~337 C, switchbacks ~420 C vs ~442 C bite point).

**Change 5 (cornering):** predicted before coding: ~6.7% less grip than four equal tires, ~0.85 g, hairpin ~40.3 km/h. First model (all four tires peak together): 0.859 g, -6.0%, 40.5 km/h. Adding axle balance (each axle must carry its share of the mass laterally) made the stock car front-limited at 0.832 g, inside the plausibility band. A test caught a bug: with a stiff rear the inside rear wheel lifts, and the clamped load was being lost (loads no longer summed to mg); fixed by moving the excess roll moment to the front axle. Straight-line and braking results unchanged; test track lap 48.35 -> 49.34 s.

## Phase 2 exit: sensitivity study

Each input changed 10% in its "better" direction (and the reverse), one at a time. Lap time change:

| Input | Test track (49.34 s) | Switchbacks (161.52 s) |
|---|---|---|
| Mass -10% | -1.08 s (#1) | -3.61 s (#1) |
| Tire grip +10% | -0.97 s (#2) | -2.60 s (#3) |
| Power +10% | -0.86 s (#3) | -3.20 s (#2) |
| Front roll share -10% | -0.11 s | -0.27 s |
| Rotating inertia -10% | -0.10 s | -0.36 s |
| Shift time -10% | -0.05 s | -0.26 s |
| Drag -10% | -0.05 s | -0.24 s |
| Brake capacity +10% | 0 | 0 |
| Pad fade temp +10% | 0 | 0 |

Predictions (Spire, before running): test track mass > power > drag > grip > brakes; switchbacks grip > mass > power > drag > brakes.

Every input has a distinct, explainable effect (zero bars included: brakes never reach their capacity or fade on flat roads). Phase 2 exit criterion met.

## Milestone D: driver model

Not validated against measured data (no driver data exists); checked against Spire's tuning targets instead. Analytic per-run mistake chances: exactly 2.0 / 5.0 / 35.0 / 75.0%. Sampled (20,000 plans per level): within 1.5% of target. Monte Carlo on the test track: 3 / 7 / 34 / 77% of runs had a mistake. Theoretical-limit runs (no driver) are unchanged, so all validation results stand.

## Head-to-head: RWD, crashes, opponents

Not validated against measured data (no RWD car or crash data exists); checked against hand calcs and Spire's targets.

- **RWD traction:** 50/50 DX, constant mu 0.9: hand calc 5926 N, sim 5926 N (same to 0.1 N). With load-sensitive tires 5815 N (0.53 g). Same car FWD at 50/50: 4325 N (0.40 g). Tested.
- **Crash rates** (analytic, per 5-corner run): 0.02 / 0.09 / 2.1 / 12.2% (safe / normal / hard / flat out). Sampled: 100,000 flat-out corners within 4 standard errors of 2.56% per corner. Tested.
- **Opponent calibration** (engine condition, bisection, 40 runs per side): Zed's saved condition 0.7621 gives best-push odds 0.38 (target 0.45). The odds are a cliff: 0.76 -> 0.49, 0.77 -> 0.09 (table in PHYSICS_updates_E.md), so 7 bisection steps can't land on the target. The test checks +/-0.10 as a drift alarm.
- **Found while testing:** opponents almost never crash. Skill scales the target ($f 	imes$ skill), so "flat out" Cutter (skill 0.92) aims at 0.907 of the limit, below Faba's Safe (0.947): 0.0006% per run vs Faba's 12.2% flat out. The riskiest opponent (Kiki, hard, skill 1.0) crashes ~0.5% of runs.
- **Bug fixed:** `driver_study` built histogram bins from max(times) = inf once any run crashed (garbage plot, inf in the table). It now plots finished runs and reports the crash rate.
