### 6.x Corner technique (update) and feathering

**Corner speed profile** (clean corner, attempt $c$): carry speed in and ease down to the apex, then roll on to the exit.

- Entry grip use $c_{entry} = c + 0.5\,(1-c)$, easing (smoothstep) down to $c$ at the apex (midpoint of the arc)
- After the apex: easing from $c$ up to 1 (the full limit) at the exit
- Speed factor $= \sqrt{\text{grip use}}$; the apex is the slowest point

**Feathering vs braking:** coasting alone slows the car at $a_{coast} = (F_{drag} + F_{roll}) / m_{eff}$ (about 0.2 m/s² at 58 km/h). If the profile asks for gentler slowing than that, the driver needs a little throttle (less than holding speed takes), not brakes. Only slowing faster than coasting uses the brakes.

**Result (R3, Normal push):** throttle feathers 6% -> 1.4% approaching the apex, rolls on to 24%, eases to 12% at the exit; rpm dips 3740 -> 3698 then climbs to 3781. No steady throttle or rpm anywhere in a corner (tested).

**Bug found while building this:** the lap solver had labeled every capped, slowing step as braking with zero throttle, which is wrong whenever the slowdown is gentler than coasting.
