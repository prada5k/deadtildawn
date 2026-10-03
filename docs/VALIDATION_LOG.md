# Validation Log

Every change to the model gets a row: what changed, the physical reason, and the result. Knobs are only changed with an independent physical justification, never just to match the targets (overfitting).

## Acceptance criteria (set before tuning)

| Test | Target | Tolerance |
|---|---|---|
| 0-60 mph | 9.9 s | +/-5% |
| Quarter mile time | 17.4-17.7 s | +/-1.5% outside range |
| Quarter mile trap | 78-80 mph | +/-1.5% outside range |
| Top speed | 112 mph | Report only (low confidence) |

## Log

| # | Change | Physical reason | 0-60 | Quarter | Trap | Top speed | Result |
|---|---|---|---|---|---|---|---|
| 0 | Baseline: point mass, torque curve, gearing, FWD traction with load transfer, drag, rolling resistance, 3000 rpm launch, 0.4 s shifts | — | 8.95 s (-9.6%) | 17.13 s (-1.6%) | 82.2 mph (+2.8%) | 121.5 mph | FAIL: too fast, worst at low speed |
| 1 | Rotational inertia (effective mass), engine decoupled during shifts/clutch slip, inertia-aware traction check | Engine + wheels must be spun up; engine inertia scales with gear ratio squared, matching the low-gear error pattern | 9.93 s (+0.3%) | 17.74 s (+0.2%) | 80.2 mph (+0.3%) | 121.5 mph | PASS |

## Notes

**Change 1 sensitivity:** swept $I_e$ 0.10-0.15 kg·m² and $I_w$ 0.7-0.9 kg·m². All cases pass (0-60: 9.77-10.15 s; quarter: 17.64-17.88 s; trap: 79.8-80.5 mph). The match does not depend on the exact inertia estimates.

**Model finding:** with inertia included, the stock car is never traction-limited in a straight-line run. Plausible for 106 hp, but sensitive to $\mu$, which is not yet calibrated (Milestone C, braking target).

**Caution:** a close match can hide compensating errors (e.g. one input too high, another too low). The braking validation in Milestone B tests $\mu$ independently.

**Top speed:** sim 121.5 mph (drag-limited in 4th at ~6400 rpm) vs 112 mph listed. Consistent with the earlier drag estimate; target remains low confidence.
