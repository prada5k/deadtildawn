### 4.6 Shifting rules (replaces "perfect, instant shifts")

**Assumptions:** fixed shift time (road-test value, 0.4 s) for every shift; zero drive force during a shift; driver data will replace this later.

- **Upshift:** one gear at a time, at the fuel cut or where the next gear makes more wheel force (whichever comes first).
- **Downshift while braking:** one gear at a time, each taking the shift time, only when the lower gear makes more wheel force **and** the engine lands at or below redline in it. Downshifts made while braking cost no extra time unless the braking zone is too short to finish them.
- **Kickdown under power:** same rule; loses the shift time.
- **No shifting mid-corner:** a shift already in progress finishes, but none start.

**Money shift:** downshifting into a gear where the engine would land above redline. The wheels drive the engine past its limit; the fuel cut can't prevent it (the engine isn't powering itself). Real consequence: bent valves, damaged rods. The rule above makes it impossible.

**Event detection:** steps are split exactly where the engine reaches the fuel cut and where a shift ends, so shift points don't depend on step size.

---

### 5.1 Braking grip limit (update: load transfer + load sensitivity)

**Change:** braking now uses per-axle loads with forward load transfer and per-tire load sensitivity, instead of four equally loaded tires.

**Axle loads** (braking deceleration $a$, positive):

$$N_f = mg\,\frac{b}{L} + m a \frac{h}{L} \qquad N_r = mg\,\frac{a_{cg}}{L} - m a \frac{h}{L}$$

($b/L$ = static front weight fraction; the second term is the load transferred forward.)

**Axle grip** (two tires, each carrying half the axle load, $\mu(F_z) = \mu_0 - k F_z$):

$$F_{axle} = 2\,\mu\!\left(\tfrac{N}{2}\right)\tfrac{N}{2}$$

**Deceleration** (ideal bias: every tire at its own limit):

$$m_{eff}\, a = F_{front}(a) + F_{rear}(a) + F_{drag} + F_{roll}, \qquad m_{eff} = m + \frac{4 I_w}{r_w^2}$$

$a$ appears on both sides (it sets the load transfer, which sets the grip), so it is solved by **fixed-point iteration**: guess $a$ from static grip, compute loads and grip, recompute $a$, repeat until it stops changing.

**Example (hand calc at $a$ = 8.9 m/s²):** transfer = 1112 × 8.9 × 0.5 / 2.621 ≈ 1888 N. Per tire: front 4271 N ($\mu$ = 0.836), rear 1183 N ($\mu$ = 0.991). Total grip ≈ 9490 N, vs 9967 N with four equal tires: **~4.8% less**. The overloaded fronts gain less grip than the unloaded rears lose.

**Result:** 60-0 mph = 138.1 ft (target 135-142 ft). Before this change: 132.0 ft.

**Limitations:** ideal brake bias (the real car has fixed bias and rear drums); acceleration traction and cornering still use static $\mu$ (Milestone C).

---

### 6.x Telemetry: driver inputs

- **Throttle:** 100% under power, 0% during shifts and braking. Holding a corner's limit speed needs only enough force to beat drag and rolling resistance: $\text{throttle} = F_{needed} / F_{available}$ (e.g. ~4% in the hairpin, ~27% in the L6).
- **Brake:** fraction of max braking used, $(a_{needed} - a_{coast}) / (a_{max} - a_{coast})$. In QSS the driver brakes at the limit, so it is ~100% through braking zones.
- Throttle and brake are never applied together (no left-foot braking in v0.9).
