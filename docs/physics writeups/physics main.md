# deadtildawn — Physics Specification (v0.9)

This document defines the physics model for the race simulation. Every equation the sim uses should appear here first. If the code and this document disagree, one of them is a bug.

---

## 0. Conventions

**Units:** SI everywhere inside the sim (m, kg, s, N, W, rad). Convert to km/h, mph, hp, or lb-ft only for display.

**Constants**

| Symbol | Meaning | Value |
|---|---|---|
| $g$ | Gravitational acceleration | 9.81 m/s² |
| $\rho$ | Air density (sea level) | 1.225 kg/m³ |

**Sim interface (must never change between models):**

```
simulate(car, track, driver, push_level) -> telemetry
```

Telemetry = time, distance, speed, gear, RPM, longitudinal g, lateral g, brake temperature at every track step. Any future model (bicycle, full vehicle) must honor this contract so the game layer never needs rewriting.

---

## 1. Vehicle Model

**Purpose:** Choose how much of the car's behavior is simulated.

**Decision:** Quasi-steady-state (QSS) point mass with quasi-static load transfer.

**Why:**
- Point mass captures grip limits, power, drag, and braking: the things that set lap time.
- Load transfer adds the FWD traction behavior (wheelspin out of hairpins) and gives suspension upgrades a physical job later.
- QSS computes a whole run instantly; the game plays back telemetry, so no real-time physics loop is needed.

**Limitations:** No yaw, no understeer/oversteer balance, no tire slip angles, no transient behavior.

**Upgrade path:** Point mass → bicycle model → full vehicle, only when gameplay requires it.

---

## 2. Track Model

**Purpose:** Describe a track as data the sim can read.

**Assumptions:**
- Flat road (no elevation) for v0.9
- Corners begin instantly at full radius (no clothoid transitions)
- Point-to-point (touge), no loop closure needed

**Format (pace notes):** comma-separated segments.

| Token | Meaning | Example |
|---|---|---|
| `S <length>` | Straight, length in m | `S 200` |
| `<L/R><severity> <angle>` | Corner: direction, severity 1–10, turn angle in degrees | `R3 90` |

Example track: `S 200, R3 90, S 80, L1 180, S 150, R7 45`

**Severity → radius (geometric scale):**

$$R_n = 15 \cdot \left(\frac{500}{15}\right)^{\frac{n-1}{9}} \approx 15 \cdot 1.477^{\,n-1}$$

Geometric spacing makes each step raise corner speed by roughly the same percentage (~22%), since $v \propto \sqrt{R}$. Linear spacing wastes most of the scale on corners that feel alike.

| Severity | Radius (m) | Limit speed at μ = 0.9 (km/h) |
|---|---|---|
| 1 | 15 | 41 |
| 2 | 22 | 50 |
| 3 | 33 | 61 |
| 4 | 48 | 74 |
| 5 | 71 | 90 |
| 6 | 105 | 110 |
| 7 | 156 | 133 |
| 8 | 230 | 162 |
| 9 | 339 | 197 |
| 10 | 500 | 239 |

**Corner arc length:** $s = R \cdot \theta$, with $\theta$ in radians.

**Direction (L/R)** is ignored by the physics; it exists for the 2D track drawing.

**Limitations / future:** Elevation (downhill touge, hill climb), clothoid transitions, procedural generation (v1.1, same format).

---

## 3. Cornering (Lateral Dynamics)

### 3.1 Basic cornering limit

**Purpose:** Maximum speed through a corner of radius $R$.

**Assumptions:** Flat road, steady speed mid-corner, point mass, constant μ, no aero.

**Free-body diagram (viewed from behind):**
- Weight $mg$, down
- Normal force $N$, up
- Lateral tire friction $f$, horizontal, toward the corner's center

Drive force and drag act along the direction of travel and cancel at steady speed.

**Key idea:** "Centripetal force" is not a separate force. It is the *job* of providing net inward force, done here by lateral tire friction.

**Derivation:**

Vertical: $N = mg$

Required inward force: $\dfrac{mv^2}{R}$. Available friction: up to $\mu N$. At the limit they are equal:

$$\mu mg = \frac{mv^2}{R}$$

**Result:**

$$v_{max} = \sqrt{\mu g R}$$

Mass cancels: in this model, heavy and light cars corner at the same speed.

**Example:** $\mu = 0.9$, $R = 20$ m

$v = \sqrt{0.9 \times 9.81 \times 20} = 13.29$ m/s $\times 3.6 = 47.84$ km/h (~30 mph)

**Limitations:** Mass stops cancelling once downforce (3.2) or tire load sensitivity (3.3) is included.

### 3.2 Downforce

**Purpose:** Include aerodynamic load in the cornering limit.

**Change from 3.1:** Downforce adds to the normal force:

$$N = mg + \tfrac{1}{2}\rho C_L A v^2$$

**Derivation:**

$$\mu\left(mg + \tfrac{1}{2}\rho C_L A v^2\right) = \frac{mv^2}{R}$$

Collect $v^2$ terms and solve:

**Result:**

$$v^2 = \frac{\mu g R}{1 - \dfrac{\mu \rho C_L A R}{2m}}$$

**Observations:**
- Setting $C_L A = 0$ recovers 3.1.
- Mass no longer cancels: downforce is a fixed force, so lighter cars gain more grip per kg from the same aero.
- The denominator reaches zero at $R_{crit} = \dfrac{2m}{\mu \rho C_L A}$. Beyond that radius, grip never runs out (the "F1 car upside down" principle). For a Civic with $C_L A = 0.5$ m² and $m = 1112$ kg, $R_{crit} \approx 4.0$ km.

**Example:** hypothetical aero kit, $C_L A = 0.5$ m², $m = 1112$ kg, $\mu = 0.9$

| Corner | No aero | With aero | Gain |
|---|---|---|---|
| R = 20 m (hairpin) | 47.8 km/h | 48.0 km/h | +0.1 km/h |
| R = 150 m (sweeper) | 131.0 km/h | 133.5 km/h | +2.5 km/h |

Downforce scales with $v^2$, so it only pays off in fast corners.

**Aero kit tradeoff: crossover speed**

The speed at which a kit's downforce equals its own weight:

$$v^* = \sqrt{\frac{2\, m_{kit}\, g}{\rho\, C_L A}}$$

Example: 15 kg kit, $C_L A = 0.5$ m² → $v^* \approx 79$ km/h. Below this speed, the kit is mostly dead weight.

In corners, a kit's own mass is roughly neutral (it adds load and inertia in proportion). Its real costs are drag on straights, mass during acceleration, and brake heat. Whether a kit helps is track-dependent, and the lap sim decides.

**Variables**

| Symbol | Meaning | Units |
|---|---|---|
| $v$ | Speed | m/s |
| $\mu$ | Tire friction coefficient | — |
| $R$ | Corner radius | m |
| $m$ | Total mass (car + driver + fuel) | kg |
| $N$ | Normal force | N |
| $C_L A$ | Downforce area (lift coefficient × reference area) | m² |
| $C_D A$ | Drag area | m² |
| $D$ | Downforce, $\tfrac{1}{2}\rho C_L A v^2$ | N |

$C_L$ and $A$ are combined because only the product is measured in a wind tunnel or CFD.

**Limitations:** No aero balance (front/rear split). A stock EJ6 produces slight lift ($C_L A$ slightly negative); assumed 0 for v0.9.

### 3.3 Tire load sensitivity

**Purpose:** Model the real effect that μ falls as tire load rises.

**Model (per tire):**

$$\mu(F_z) = \mu_0 - k \cdot F_z$$

$F_z$ in kN. Illustrative values: $\mu_0 = 1.05$, $k = 0.05$ per kN. **To be calibrated in Phase 2** against the 60–0 braking target (implied μ ≈ 0.85–0.89).

**Cornering without aero:** each tire carries $mg/4$:

$$v^2 = gR\left(\mu_0 - \frac{k\, mg}{4}\right)$$

Mass no longer cancels: heavier cars run each tire at a lower μ.

**Example:** $m = 1112$ kg → $F_z = 2.73$ kN per tire → $\mu = 0.914$. Hairpin ($R = 20$ m): 48.2 km/h. Removing 100 kg → $\mu = 0.926$ → 48.5 km/h.

The cornering effect of weight reduction is modest. Its larger payoffs are acceleration and brake heat.

**With downforce:** $N = mg + D(v)$, giving a $v^4$ term with no clean closed form. The sim solves it numerically (bisection) for the speed where required grip = available grip.

**Limitations / future:** Lateral load transfer. In a real corner, outside tires carry more load and, because μ drops with load, total grip falls. This is the physical mechanism for suspension upgrades (sway bars, coilovers, lower CG).

---

## 4. Longitudinal Dynamics

### 4.1 Engine to road

**Wheel force:**

$$F_{drive} = \frac{T_e \cdot i_g \cdot i_f \cdot \eta}{r_w}$$

| Symbol | Meaning |
|---|---|
| $T_e$ | Engine torque at current RPM (from torque curve) |
| $i_g$ | Current gear ratio |
| $i_f$ | Final drive ratio |
| $\eta$ | Drivetrain efficiency (~0.88) |
| $r_w$ | Wheel radius |

**Engine RPM from road speed:**

$$\text{RPM} = \frac{v}{r_w} \cdot i_g \cdot i_f \cdot \frac{60}{2\pi}$$

**Example (EJ6):** 60 mph (26.82 m/s) in 2nd → 6216 RPM. Max speed per gear at 6800 RPM:

| Gear | Overall ratio | Max speed |
|---|---|---|
| 1 | 13.19 | 58 km/h (36 mph) |
| 2 | 7.23 | 106 km/h (66 mph) |
| 3 | 4.76 | 161 km/h (100 mph) |
| 4 | 3.69 | 207 km/h (129 mph) |
| 5 | 2.85 | Drag-limited |

**Gear selection:** at each speed, use the gear (under the rev limit) giving the highest wheel force. Perfect, instant shifts in v0.9; shift time arrives with transmission upgrades.

### 4.2 Net acceleration

$$m a = F_{drive} - \tfrac{1}{2}\rho C_D A v^2 - C_{rr}\, m g$$

Drive force minus aero drag minus rolling resistance. Top speed is where drag consumes all drive force.

### 4.3 FWD traction limit with load transfer

**Assumptions:** Quasi-static load transfer, flat road.

**Derivation:** Static front load is $mg \cdot \frac{b}{L}$ ($b$ = CG to rear axle, $L$ = wheelbase). Acceleration shifts load rearward by $m a \frac{h}{L}$ ($h$ = CG height):

$$N_f = mg\frac{b}{L} - ma\frac{h}{L}$$

Traction is $\mu N_f$, but $a$ depends on the drive force itself. Solving the self-limiting loop:

**Result:**

$$F_{max,FWD} = \frac{\mu\, mg\, (b/L)}{1 + \mu\, h/L}$$

**RWD for comparison** ($a$ = CG to front axle):

$$F_{max,RWD} = \frac{\mu\, mg\, (a/L)}{1 - \mu\, h/L}$$

FWD fights itself (pushing harder removes grip); RWD helps itself. When $\mu h / L \to 1$, a RWD car wheelies.

**Example (EJ6):** $m = 1112$ kg, 61% front, $h = 0.5$ m, $L = 2.621$ m, $\mu = 0.9$

- With load transfer: 5111 N → **0.47 g**
- Ignoring load transfer: 0.55 g
- RWD equivalent at 50/50: 0.54 g, despite less static load on the driven axle

**Check:** in 1st gear at peak torque, engine wheel force ≈ 5440 N > 5111 N, so the car is **traction-limited** (wheelspin). In 2nd, ≈ 2980 N, so it is power-limited.

### 4.4 Regimes

$$F_{drive,actual} = \min(F_{engine,\,best\ gear},\ F_{max,traction})$$

- **Low speed:** traction-limited. More power = more wheelspin.
- **Mid speed:** power-limited.
- **High speed:** drag-limited, up to top speed.

---

## 5. Braking

### 5.1 Grip limit

All four tires brake (unlike FWD drive):

$$m a_{brake} = \mu(mg + D) + \tfrac{1}{2}\rho C_D A v^2 + C_{rr}\, mg$$

Without aero, ≈ μg.

**Assumption (v0.9):** Ideal brake bias (front/rear braking force matches front/rear load). Adjustable bias is a later tuning feature.

Load transfers forward under braking; with load sensitivity, the uneven split costs a little grip.

### 5.2 Brake system limit

Per wheel:

$$T_{brake} = 2 \cdot \mu_{pad} \cdot F_{clamp} \cdot r_{eff}$$

Force at the road: $T_{brake} / r_w$.

$$F_{brake,actual} = \min(\text{grip limit},\ \text{brake system limit})$$

Fresh brakes are grip-limited. Fade lowers $\mu_{pad}$ until the system limit drops below the grip limit.

**Parts mapping:**
- Rotors: larger $r_{eff}$, more thermal mass
- Pads: higher $\mu_{pad}$, higher fade temperature (race pads: weak when cold)
- Calipers: higher $F_{clamp}$
- Stainless lines: no added stopping force (pedal feel only; candidate driver-confidence effect in v1.1)

### 5.3 Brake fade (thermal model)

**Heat per stop:**

$$Q = \tfrac{1}{2} m (v_1^2 - v_2^2)$$

**Example:** 1112 kg, 120 → 50 km/h: $Q \approx 511$ kJ. ~70% to the fronts → ~179 kJ per front rotor. Rotor ≈ 5 kg cast iron ($c \approx 460$ J/kg·K):

$$\Delta T = \frac{Q}{m_r c} \approx 78\ °\text{C per stop}$$

**Temperature over time:**

$$m_r c \frac{dT}{dt} = P_{brake} - h(v) A_r (T - T_{ambient})$$

Cooling depends on airflow, so it is weak at low speed.

**Pad friction vs temperature:** constant within the operating window; falls above the fade temperature.

Fade depends on heat in vs heat out over time. Worst case on a touge: long fast straight into a hairpin (largest Δv, no recovery time after).

### 5.4 Fixed-point iteration

QSS finds braking points with a backward pass, but brake temperature depends on history. Solution:

1. Run the lap with cold brakes
2. Compute the temperature trace
3. Rerun with those temperatures
4. Repeat until lap time converges (typically 2–4 passes)

Any model with memory (tire temperature, fuel load) needs this treatment.

---

## 6. Driver Model (v0.9 / v1)

**Purpose:** Turn push level into pace and mistakes. No driver stats in v1 (fixed baseline driver).

**Model:**
- Push level sets target fraction of the limit, $f$, applied to all grip use (cornering, braking, traction).
- Each corner, actual attempt $\sim \mathcal{N}(f, \sigma)$. $\sigma$ = consistency.
- Mistake when attempt > 1.0:

$$P(\text{mistake per corner}) = 1 - \Phi\!\left(\frac{1-f}{\sigma}\right)$$

**Push levels** ($\sigma = 0.02$, 15-corner run):

| Level | $f$ | Mistake / corner | ≥1 mistake / run |
|---|---|---|---|
| Safe | 0.92 | ~0.003% | ~0% |
| Normal | 0.95 | 0.6% | ~9% |
| Hard | 0.97 | 6.7% | ~65% |
| Flat out | 0.99 | 31% | ~100% |

Corner speed scales with $\sqrt{f}$: Normal → Flat out gains only ~2% in corners. **$\sigma$ is the main balancing knob** (flat out is too punishing at 0.02).

**Mistake cost:** corner speed drops to a fraction of the limit plus recovery time, scaled by how far over the limit the attempt was. No crash physics in v1.

**v1.1 hooks:** Composure → lowers $\sigma$. Bravery → shifts $f$. Risk becomes harder for the player to judge (hidden numbers, indirect signals).

---

## 7. Validation Targets

Stock 1996 Honda Civic DX coupe (EJ6, D16Y7, 5MT). See `data/cars/ej6_dx_coupe_1996.json` for inputs and sources.

| Test | Target | Cross-check |
|---|---|---|
| 0–60 mph | 9.9 s | — |
| Quarter mile | 17.4–17.7 s @ 78–80 mph | — |
| Top speed | 112 mph | ⚠️ Open: limiter or drag-limited? Rough drag calc predicts ~120 mph |
| 60–0 mph | 135–142 ft | Implies 0.85–0.89 g → consistent with μ ≈ 0.9 ✅ |

---

## 8. Decisions Log

| Decision | Choice |
|---|---|
| Vehicle model | QSS point mass + quasi-static load transfer |
| Track | Flat, geometric 1–10 radius scale, pace-note format |
| Tire load sensitivity | Included in v0.9 |
| Brake fade | Included (thermal model + iteration) |
| Brake bias | Ideal (v0.9) |
| Shifting | Perfect, instant (v0.9) |
| Driver | Fixed baseline, 4 fixed push levels |
| Elevation | Later (downhill / hill climb variants) |

## 9. Open Questions

- [ ] Top speed 112 mph: limiter or drag-limited?
- [ ] Rev limit 6800: redline or fuel-cut?
- [ ] Sources for wheelbase, weight split, gear ratios, performance targets
- [ ] Calibrate $\mu_0$ and $k$ against braking target
- [ ] Rear brakes on DX: drums? (affects brake model)
- [ ] Torque curve: find a dyno chart (currently two anchor points)