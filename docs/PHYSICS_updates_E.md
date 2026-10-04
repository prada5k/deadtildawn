### 4.3 RWD traction limit (implemented: load-sensitive rear tires)

`Car.drivetrain` is "FWD" (default) or "RWD"; `forces.traction_limit` picks the driven axle.

**RWD:** accelerating moves load ONTO the driven rear axle, so pushing harder adds grip (the opposite of FWD):

$$N_r = mg\frac{a}{L} + ma\frac{h}{L}, \qquad F_{max,RWD} = \frac{\mu\, mg\, (a/L)}{1 - \mu\, h/L} \quad (\text{constant } \mu)$$

With load-sensitive tires the loaded rears lose some $\mu$, so solve $F = \text{axle\_grip}(N_r(a = F/m))$ by fixed-point iteration (same method as FWD, C2).

**Check (EJ6 at 50/50, RWD):** $\mu = 0.9$ constant: $0.9 \cdot 1112 \cdot 9.81 \cdot 0.5 / (1 - 0.9 \cdot 0.5/2.621) = 4908.8 / 0.8283 = $ **5926 N** (0.54 g, matches the 4.3 example). Sim with load sensitivity: **5815 N** (0.53 g). Same car as FWD at 50/50: 4325 N (0.40 g): RWD puts down 34% more.

The stock DX is FWD, so every validation result is unchanged.

### 6.x Crashes (DNF)

**Model:** an attempt more than `CRASH_MARGIN` = 2.5% over the limit is a crash, not just a mistake. Every crash is also a mistake.

$$P(\text{crash per corner}) = 1 - \Phi\!\left(\frac{1 + 0.025 - f}{\sigma}\right)$$

| Push | $f$ | Per corner | Per 5-corner run |
|---|---|---|---|
| Safe | 0.947 | 0.005% | 0.02% |
| Normal | 0.954 | 0.018% | 0.09% |
| Hard | 0.972 | 0.42% | 2.1% |
| Flat out | 0.986 | 2.6% | 12.2% |

Sampled check: 100,000 flat-out corners crash at the analytic rate within 4 standard errors (tested).

**Driver skill:** the target is $f = f_{push} \times \text{skill}$. A driver with skill < 1 can only reach part of the push level's target, so they are slower AND crash less. (Open question: should low skill raise $\sigma$ instead?)

**What a crash does to the run:** the run ends at the crash corner's apex (midpoint of the arc). Telemetry is cut there, `lap_time` = time of the crash (kept for the replay), `dnf` = True. Compare runs with `finish_time()`: $\infty$ for a DNF, so a DNF never beats a finished run. Monte Carlo: DNF times are $\infty$; mean and spread use finished runs only; `dnf_rate` counts the rest.

**Head to head:** P(win) compares every pair of sampled runs, $p < o$. Both DNF: nobody wins (no contest).

### 6.y Opponents

An opponent = the base car + changes (the same effects parts use, plus drivetrain and weight split) + an authored driver (push, $\sigma$, skill). Difficulty is tuned only by engine **condition** (scales torque; the stat card shows the true resulting hp), calibrated by bisection so a stock DX at its best push level has the opponent's target odds (`tools/calibrate_opponents.py`, 40 runs each, fixed seeds).

**Finding: the odds are a cliff.** Zed on his home road, best-push odds vs condition:

| Condition | 0.72 | 0.74 | 0.75 | 0.76 | 0.7621 (saved) | 0.77 | 0.78 |
|---|---|---|---|---|---|---|---|
| Odds | 1.00 | 0.94 | 0.77 | 0.49 | 0.38 | 0.09 | 0.00 |

Both drivers are very consistent next to the gap a little power makes (Zed $\sigma_t$ = 0.05 s, Faba at Hard 0.25 s, on a 49.5 s run). A 1% engine change moves the odds by ~0.4, and one $350 part (strip the interior, -0.40 s) takes the odds from 0.38 to 0.78.
