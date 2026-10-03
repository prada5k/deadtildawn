### 4.5 Rotational inertia (effective mass)

**Purpose:** Account for the energy needed to spin up the engine and wheels, not just to move the car's mass.

**Assumptions:**
- Rigid drivetrain when the clutch is locked
- Engine inertia $I_e$ (crank + flywheel + clutch) and per-wheel inertia $I_w$ are constants
- Drivetrain losses ignored in the inertia term

**Derivation (energy method):** at road speed $v$, with overall ratio $G = i_g \cdot i_f$:

$$KE = \tfrac{1}{2} m v^2 + 4 \cdot \tfrac{1}{2} I_w \left(\frac{v}{r_w}\right)^2 + \tfrac{1}{2} I_e \left(\frac{G v}{r_w}\right)^2$$

Factor out $\tfrac{1}{2} v^2$; the bracket is the effective mass:

$$m_{eff} = m + \frac{4 I_w}{r_w^2} + \frac{I_e G^2}{r_w^2}$$

Acceleration becomes $a = (F_{drive} - F_{resist}) / m_{eff}$. The engine term scales with $G^2$, so it dominates in low gears and fades in high gears.

**When the engine term applies:** only when the clutch is locked. During a shift or launch clutch slip, the engine is decoupled: $m_{eff} = m + 4 I_w / r_w^2$.

**Example (EJ6):** $I_e = 0.12$ kg·m², $I_w = 0.8$ kg·m², $r_w = 0.298$ m, $m = 1112$ kg

| Gear | Engine term | Wheel term | $m_{eff}$ | Increase |
|---|---|---|---|---|
| 1st | 235 kg | 36 kg | 1383 kg | +24% |
| 2nd | 71 kg | 36 kg | 1219 kg | +10% |
| 3rd | 31 kg | 36 kg | 1179 kg | +6% |
| Clutch open | 0 | 36 kg | 1148 kg | +3% |

**Effect on traction:** the spinning parts absorb part of the engine's force, so the tires transmit less than the raw engine force:

$$F_{tire} = F_{engine} - \left(\frac{2 I_w}{r_w^2} + \frac{I_e G^2}{r_w^2}\right) a$$

(two driven wheels plus the engine). If $F_{tire}$ exceeds the traction limit, the tires slip: the engine and driven wheels decouple, and the car accelerates at $a = (F_{traction} - F_{resist}) / (m + 2 I_w / r_w^2)$.

**Example:** 1st gear at 4600 rpm: $F_{engine} = 5437$ N, $a = 3.78$ m/s², absorbed ≈ 957 N, so $F_{tire} \approx 4480$ N, below the 5177 N traction limit. **This supersedes the 4.3 example:** with inertia included, the stock car is not traction-limited.

**Upgrade implications:** lighter flywheels lower $I_e$; lighter or smaller wheels lower $I_w$. Mass at the rim counts nearly double (as mass and as inertia, since $I \approx m r^2$). Changing wheel size also changes $r_w$, which changes effective gearing.

**Limitations:** $I_e$ and $I_w$ are estimates. Sensitivity check: across $I_e$ = 0.10–0.15 and $I_w$ = 0.7–0.9, all validation targets still pass.
