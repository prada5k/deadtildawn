### 5.2 Brake system limit (capacity ratio model, v0.9)

**Model:** the front brakes can make at most

$$F_{cap}(T) = C \cdot F_{front,grip,ref} \cdot \frac{\mu_{pad}(T)}{\mu_{pad,cold}}$$

where $C$ = 1.3 (cold brakes can make 1.3x the force needed to reach front grip, i.e. lock the wheels) and $F_{front,grip,ref}$ is the front axle grip at cold max braking. Front braking force = min(front grip, $F_{cap}$). Rear drums: grip-limited, no fade (v0.9).

**Why a ratio:** one physically meaningful number instead of the full hydraulic chain (pedal ratio, master cylinder, caliper piston area, clamp force, rotor radius). The hydraulic chain arrives with brake upgrade parts.

### 5.3 Brake fade (thermal model)

**Pad friction vs temperature:** flat at 0.40 up to the fade onset (350 C), then falling 0.001 per C, floor 0.10.

**Fade is a threshold:** capacity only drops below grip once $\mu_{pad} < 0.40 / 1.3 = 0.308$, i.e. above ~442 C. Between 350 and 442 C the pads are fading but the brakes still have margin, so stopping distance is unchanged ("fine, fine, fine, then soft").

**Rotor energy balance** (one front rotor, lumped temperature):

$$m_r c \frac{dT}{dt} = P_{in} - hA(v)\,(T - T_{amb})$$

- $P_{in}$ = front brake force x speed / 2 (two front rotors). The front share comes from the braking model (load transfer, ~75% under hard braking), not a fixed constant.
- $hA(v) = 4 + 1.15\,v$ W/K: Newton's law of cooling, more airflow at speed.

**Exact step solution** (constant $P$ and $v$ over a step): exponential approach to $T_\infty = T_{amb} + P/hA$:

$$T(t + \Delta t) = T_\infty + (T - T_\infty)\, e^{-\Delta t / \tau}, \qquad \tau = \frac{m_r c}{hA}$$

**Cooling time constant:** $\tau$ = 2300 / 38.5 ≈ 60 s at 30 m/s; 2300 / 4 ≈ 575 s (~10 min) parked.

**Hand calc (one 60-0 stop, cold, no cooling):** KE = ½ x 1148 x 26.82² ≈ 413 kJ; minus ~10 kJ to drag and rolling resistance ≈ 403 kJ; x 0.75 front / 2 rotors ≈ 151 kJ per rotor; ΔT = 151000 / (5 x 460) ≈ **65.7 C**. Sim: 65.0 C.

**Repeated stops, no cooling (hand calc vs sim):** fade onset during stop 5 ((350-30)/65.7 = 4.87); first longer stop is stop 7 ((440-30)/65.7 = 6.24). Sim: stop 5 ends at 355 C; stop 7 is 142.2 ft vs 138.1 ft. Both match.

**Thermal equilibrium:** with repeated runs, heat in per run eventually equals heat out per run, so rotor temperature levels off. Test track: peak settles at ~337 C (never fades). Switchbacks (7 hairpins from ~123 km/h): peak settles at ~420 C, just under the ~442 C bite point. On flat roads the stock brakes survive; downhill (gravity adding energy) is where touge brakes fade.

### 5.4 Fixed-point iteration (implemented)

Braking capacity depends on rotor temperature, which depends on all the braking before it, but the backward pass runs in reverse. So:

1. Pass 1: envelope assuming rotors stay at the starting temperature; forward pass computes the temperature trace
2. Pass n: envelope using the previous pass's temperatures; forward pass again
3. Stop when lap time changes by < 1e-6 s

When fade never bites, it converges in 2 passes. Weak pads (onset 200 C) on the switchbacks: 6 passes, +0.20 s.

**Back-to-back runs:** each run starts with the rotors at the previous run's finish temperature.
