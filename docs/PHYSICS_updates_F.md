### 6.z Human timing (launch reaction, shift durations)

A real driver doesn't launch or shift like a machine. Each run with a driver
now draws, from its own random stream (seed `"{seed}-timing"`, so the corner
plan is unchanged):

- **Launch reaction** $r \sim \mathcal{N}(0.20, 0.07)$ s, clipped to [0.10, 0.45] s: the car sits at the line for $r$ after the green. Every telemetry sample moves later by $r$ (the first sample, at the line, is at $t = r$) and the lap time includes it.
- **Shift duration:** shift $n$ lasts $t_{shift} \cdot k_n$, with $k_n \sim \mathcal{N}(1, 0.175)$ clipped to [0.6, 1.6] (a 0.40 s shift: $\pm$0.07 s).

Runs without a driver (all validation targets: 0-60, quarter mile, 60-0, top speed, skidpad) are unchanged.

**Hand calc, and a correction.** Independent variances add:

$$\sigma_{run}^2 \approx \sigma_{corners}^2 + \sigma_r^2 + \sum_n \left(\frac{\partial t}{\partial t_{shift,n}}\right)^2 \sigma_{shift}^2$$

Claude first predicted $\partial t / \partial t_{shift} \approx 1$ (a 0.07 s longer shift = 0.07 s slower), which gave $\sigma_{run} \approx 0.2$ s. That's wrong: during a shift the car coasts instead of accelerating, so a shift that's $\Delta t$ longer leaves it $a\,\Delta t$ slower ($\approx 2\ \text{m/s}^2 \times 0.07\ \text{s} = 0.14$ m/s) for the rest of that straight, and the time lost is about $(\Delta v / v)\, t_{straight} \approx (0.14/25) \times 5 \approx 0.03$ s, not 0.07 s. Only the reaction adds straight to the lap. Measured (test track, 30 runs): $\sigma$ went 0.083 -> 0.109 s (safe), 0.105 -> 0.108 s (normal); Zed 0.100 -> 0.127 s. Mean lap +0.20 s (the reaction), the same for every driver, so head-to-head odds only change through the spread.

Tests: draws reproducible and bounded; 2000 draws average 0.20 s and 1.00 (hand calc); first sample at $t = r$; the corner plan's first attempt is still the first gauss draw of `random.Random(seed)`.

### 6.w Matchmaking: tuning opponents to a target

Game design (Spire): a well-played night should be about a coin flip.
`sim/matchmaking.py`:

1. **Match:** the street racer is picked at random among the 3 whose car (as authored, condition 1) is closest to the player's power-to-weight $P_{peak}/m$. Hand calc, stock DX: $105 \times 745.7 / 1112 = 70.4$ W/kg (tested).
2. **Tune:** run the player at every push level and the opponent at a ladder of engine conditions $c$; $\text{odds}(c) = \max_{push} P(\text{player} < \text{opponent})$. Stronger engine, faster opponent, so odds fall with $c$. Find the crossing of the target and interpolate linearly between the rungs:

$$c^* = c_0 + (c_1 - c_0)\,\frac{o_0 - \text{target}}{o_0 - o_1}$$

**Why two passes (coarse 0.35-2.2, then 12 rungs inside the bracket).** The run spread is ~0.1 s, but the engine moves Zed's time ~1.3 s per 0.1 of condition (test track: 0.70 -> 50.53 s, 0.80 -> 49.22 s). The odds of two near-normal runs depend on the gap in means over $\sqrt{\sigma_p^2 + \sigma_o^2} \approx 0.17$ s, so they go from ~0.9 to ~0.1 over about $\pm 0.2$ s of mean gap, which is a condition window of only $\approx 0.03$. That is the "odds cliff" from 6.y. A coarse ladder (17% steps) lands anywhere on it; the fine pass doesn't.

**Noise.** 40 runs per job: near the cliff a single estimate wanders $\pm 0.1$. `measure_odds()` checks a tuning with a FRESH 200-run sample (different seeds). Results: Zed tuned to 0.5 vs stock DX measures 0.5 $\pm$ 0.12 (tested); the calibrated base condition (target 0.45) measures 0.40 (200 runs a side). In the game, a night's odds are therefore 0.5 $\pm$ ~0.1.

**Speed.** All jobs (4 push levels + 12 + 12 conditions) run in a process pool: a tuned street night takes ~7 s on the 20-core laptop (the "word on the street" screen). `tools/calibrate_opponents.py` uses the same tuner.

**Rivals** use the same tuning, but only after the player beats them, and never lower than before (`--retune`): building between rival nights is how the player climbs.

### 6.y (update) Opponent drivers

Every opponent's $\sigma$ +0.008 and skill moved halfway to 1.0 (Spire: "opponents have greater sigma"). Low skill shrank the target $f$, which made low-skill drivers safe instead of sloppy (the "opponents almost never crash" finding). With skill near 1 and more $\sigma$, opponents make mistakes and crash like Faba does. All conditions recalibrated (VALIDATION_LOG).
