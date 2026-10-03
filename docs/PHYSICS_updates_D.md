## 6. Driver Model (implemented, replaces the Phase 1 draft)

**Purpose:** turn push level into pace, consistency, and mistakes, so races have real risk.

**Model:**
- Push level sets the intent $f$, the fraction of the car's limit the driver aims for.
- Each corner, the attempt $\sim \mathcal{N}(f, \sigma)$. $\sigma$ = driver consistency (0.02 for the starting driver; a v1.1 driver stat).
- Attempt > 1.0 (more than the tires can give) = a mistake:

$$P(\text{mistake per corner}) = 1 - \Phi\!\left(\frac{1-f}{\sigma}\right)$$

**Tuning (Spire's targets):** chance of at least one mistake in a 5-corner run. Per corner: $p = 1 - (1 - P_{run})^{1/5}$, then $f = 1 - \sigma\,\Phi^{-1}(1 - p)$ with $\sigma$ = 0.02:

| Push | $P_{run}$ | Per corner | $f$ |
|---|---|---|---|
| Safe | 2% | 0.40% | 0.947 |
| Normal | 5% | 1.0% | 0.954 |
| Hard | 35% | 8.3% | 0.972 |
| Flat out | 75% | 24% | 0.986 |

$f$ is fixed per push level (intent); a more consistent driver (smaller $\sigma$) gets fewer mistakes at the same pace. Why $\sigma$ = 0.02 and not 0.015: a target mistake rate fixes the margin in units of $\sigma$, so a small $\sigma$ squeezes all push levels to nearly the same pace.

**Corner technique (slow in, fast out):** a clean corner with attempt $c$:
- Before the apex (first half of the arc): speed factor $\sqrt{c}$ (grip use $c$, $v \propto \sqrt{\text{grip}}$)
- After the apex: $\sqrt{c + (1-c)\,\text{smoothstep}(x)}$, rising to the full limit at the exit

This is why the throttle varies through a corner (roll-on after the apex) instead of holding one value.

**Mistake (physical):** in at the limit, then after the apex the car runs wide and scrubs speed: factor $\max(1 - 0.10 - 3\,(attempt - 1),\ 0.5)$ for the rest of the corner. The slow exit costs time down the next straight, handled by the solver.

**Braking:** the driver brakes at fraction $f$ of the car's maximum deceleration.

**Monte Carlo (test track, 150 runs each):**

| Push | Mean | Spread | Best | Worst | Runs with a mistake |
|---|---|---|---|---|---|
| Safe | 49.67 s | 0.10 | 49.50 | 50.26 | 3% |
| Normal | 49.64 s | 0.12 | 49.46 | 50.32 | 7% |
| Hard | 49.66 s | 0.27 | 49.39 | 50.92 | 34% |
| Flat out | 50.00 s | 0.50 | 49.34 | 51.82 | 77% |

**Finding:** pushing harder barely changes the average; it widens the spread. Flat out has the worst mean but the best best-case. The favorite should protect the lead (Normal / Safe); the underdog needs variance (Hard / Flat out). Example: vs a rival at 49.55 s, win odds are Safe 4%, Normal 15%, Hard 54%, Flat out 23%.

**Reproducibility:** every driven run has a seed, recorded in the summary and the replay.
