### 3.4 Cornering with lateral load transfer (axle-limited)

**Purpose:** a realistic cornering limit: load moves to the outside tires, and the car is limited by whichever axle runs out of grip first.

**Assumptions:** steady-state cornering, no aero, roll stiffness distribution sets how lateral transfer splits between axles (no roll-center geometry), flat road.

**Lateral load transfer** at lateral acceleration $a_y$ (moment $m a_y h$):

$$\Delta W_f = \phi_f \frac{m a_y h}{t_f} \qquad \Delta W_r = (1-\phi_f) \frac{m a_y h}{t_r}$$

$\phi_f$ = front share of roll stiffness (0.60 stock), $t$ = track width (1.47 m). Outside tire gains $\Delta W$, inside loses it.

**Wheel lift:** an axle can transfer at most its inside tire's whole load. Beyond that the inside wheel is in the air, and the extra roll moment moves to the other axle, so the four loads always sum to $mg$.

**Axle balance:** in steady cornering each axle must supply lateral force in proportion to the mass it carries (front: $m a_y \cdot b/L$). Each axle's capability:

$$a_{y,front} = \frac{F_{y,front}(a_y)}{m\, b/L} \qquad a_{y,rear} = \frac{F_{y,rear}(a_y)}{m\, a/L}$$

with $F_y = \sum \mu(F_z) F_z$ over the axle's two tires. The car's limit is the fixed point

$$a_y = \min\big(a_{y,front}(a_y),\ a_{y,rear}(a_y)\big)$$

Front saturates first = **understeer**; rear first = **oversteer**.

**Corner speed** (no aero): $v_{max} = \sqrt{a_{y,max} R}$. With no downforce, one number (the skidpad g) describes all of the car's cornering.

**Hand calc (stock, $a_y$ = 8.163 m/s²):** moment = 1112 x 8.163 x 0.5 = 4539 N·m. Front transfer 0.6 x 4539 / 1.47 = 1853 N, rear 1235 N. Tires: front 5180 / 1474 N, rear 3362 / 892 N. Front-limited at **0.832 g** (rear could hold 0.908 g).

**Results:** hairpin (R 15 m) 39.8 km/h (was 41.7), R3 58.8 km/h (was 61.6); test track lap 48.35 → 49.34 s.

**Roll stiffness sweep (sway bar physics):**

| Front roll share | Limit | Limited by |
|---|---|---|
| 0.60 (stock) | 0.832 g | front (understeer) |
| 0.50 | 0.847 g | front |
| 0.40 | 0.858 g | ~balanced (rear) |
| 0.30 | 0.837 g | rear (oversteer, inside rear wheel lifting) |

Moving roll stiffness rearward (a bigger rear sway bar) helps until the axles balance, then hurts. This is the physics behind the classic FWD Civic rear-bar mod, including its optimum, and the first natural tuning slider.

**Validation:** no measured skidpad figure found for the DX. Report-only plausibility band 0.75-0.85 g (economy cars of the era on all-season tires; general knowledge). Sim: 0.832 g, inside the band.

**Limitations:** no friction circle (combined braking + cornering), no aero, no camber/compliance, no transient (yaw) behavior.

### 4.3 FWD traction limit (update: load-sensitive front tires)

Traction now uses the front axle's two tires with load sensitivity: $F = F_{front,axle}\big(N_f(a = F/m)\big)$, solved by fixed-point iteration. Stock: 5151 N (was 5177 N with one static $\mu$). The stock car is still never traction-limited (spinning parts absorb ~950 N in 1st).
