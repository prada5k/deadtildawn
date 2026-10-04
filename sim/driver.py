"""Driver model: push level, consistency, mistakes, corner technique.

See docs/PHYSICS.md section 6.

- Push level sets f, the fraction of the car's limit the driver aims for.
- Each corner, the actual attempt ~ Normal(f, sigma). sigma = consistency.
- Attempt above 1.0 = more than the tires can give = a mistake.
- Corner technique: the driver carries speed in and trail-brakes down to the
  apex (grip use falls from c_entry to c), then rolls on the throttle after the
  apex, reaching the full limit at the exit. Speed (and rpm) is never steady
  through a corner.
- A mistake: the car runs wide at the apex and scrubs speed, worse the further
  over the limit the attempt was.
- Corrections: real drivers never hold one speed mid-corner. Each corner gets
  smooth, seeded speed corrections (a few sine waves along the arc) sized by
  the driver's consistency sigma. They never push past the car's limit, and
  they cost a little time, so a calmer driver is slightly faster.
"""
import math
from dataclasses import dataclass
from statistics import NormalDist

SIGMA_DEFAULT = 0.02          # starting driver (Spire's friend, v1); v1.1 driver stat

# Push levels are tuned so that, with sigma = 0.02, a 5-corner run has these
# chances of at least one mistake (Spire's tuning). f is the driver's intent and
# stays fixed; a more consistent driver (smaller sigma) makes fewer mistakes.
REFERENCE_SIGMA = 0.02
REFERENCE_CORNERS = 5
RUN_MISTAKE_TARGETS = {"safe": 0.02, "normal": 0.05, "hard": 0.35, "flat_out": 0.75}

APEX_FRACTION = 0.5           # roll on the throttle after the corner's midpoint
ENTRY_CARRY = 0.5             # entry grip use = c + 0.5 * (1 - c): carry speed in, trail-brake to the apex
MISTAKE_BASE_LOSS = 0.10      # running wide costs at least 10% of corner speed...
MISTAKE_LOSS_PER_OVERSHOOT = 3.0   # ...plus 3% per 1% the attempt was over the limit
MISTAKE_FLOOR = 0.5           # never below half the corner's limit speed

CORRECTION_WAVELENGTHS = (9.0, 15.0, 23.0)   # m, along the corner arc
CORRECTION_PER_SIGMA = 0.4    # total correction amplitude = 0.4 x sigma (0.8% of speed at sigma 0.02)
CRASH_MARGIN = 0.025          # an attempt more than 2.5% over the limit is a CRASH (DNF)


def per_corner_probability(run_probability, corners=REFERENCE_CORNERS):
    """P(mistake in one corner) from P(at least one mistake in `corners` corners):
    1 - (1 - p)^n = P_run  ->  p = 1 - (1 - P_run)^(1/n)."""
    return 1 - (1 - run_probability) ** (1 / corners)


def target_fraction(run_probability, sigma=REFERENCE_SIGMA):
    """f such that P(attempt > 1) = per-corner probability, attempt ~ N(f, sigma):
    1 - Phi((1 - f) / sigma) = p  ->  f = 1 - sigma * Phi^-1(1 - p)."""
    p = per_corner_probability(run_probability)
    return 1 - sigma * NormalDist().inv_cdf(1 - p)


PUSH_LEVELS = {name: target_fraction(p) for name, p in RUN_MISTAKE_TARGETS.items()}


@dataclass(frozen=True)
class Driver:
    name: str = "Friend"
    sigma: float = SIGMA_DEFAULT
    push: str = "normal"
    skill: float = 1.0      # fraction of the push level's target a driver can actually reach

    @property
    def f(self):
        return PUSH_LEVELS[self.push] * self.skill

    def crash_chance_per_corner(self):
        """Analytic P(attempt > 1 + CRASH_MARGIN)."""
        if self.sigma <= 0:
            return 0.0 if self.f <= 1 + CRASH_MARGIN else 1.0
        return 1 - NormalDist(self.f, self.sigma).cdf(1.0 + CRASH_MARGIN)

    def mistake_chance_per_corner(self):
        """Analytic P(attempt > 1) for this driver at this push level."""
        if self.sigma <= 0:
            return 0.0 if self.f <= 1 else 1.0
        return 1 - NormalDist(self.f, self.sigma).cdf(1.0)


@dataclass
class CornerAttempt:
    text: str
    attempt: float      # fraction of the limit the driver tried to use
    mistake: bool
    s_start: float
    s_end: float
    corrections: tuple = ()   # ((amplitude, wavelength_m, phase_rad), ...)
    crash: bool = False       # so far over the limit that the car leaves the road


def correction(a, s):
    """Driver speed correction (fraction) at track position s inside corner a."""
    return sum(amp * math.sin(2 * math.pi * (s - a.s_start) / wl + ph)
               for amp, wl, ph in a.corrections)


def plan_corners(driver, corners, rng):
    """Draw one attempt per corner. corners: [(text, s_start, s_end), ...]."""
    plan = []
    amp_each = CORRECTION_PER_SIGMA * driver.sigma / len(CORRECTION_WAVELENGTHS)
    for text, s0, s1 in corners:
        attempt = rng.gauss(driver.f, driver.sigma) if driver.sigma > 0 else driver.f
        fixes = tuple((amp_each * rng.uniform(0.5, 1.5), wl, rng.uniform(0, 2 * math.pi))
                      for wl in CORRECTION_WAVELENGTHS) if driver.sigma > 0 else ()
        plan.append(CornerAttempt(text, attempt, attempt > 1.0, s0, s1, fixes,
                                  crash=attempt > 1.0 + CRASH_MARGIN))
    return plan


def corner_speed_factor(attempt, u):
    """Fraction of the corner's limit speed at fraction u (0-1) through it."""
    if attempt > 1.0:                                   # mistake
        if u < APEX_FRACTION:
            return 1.0                                  # in too hot, still holding on
        overshoot = attempt - 1.0
        loss = MISTAKE_BASE_LOSS + MISTAKE_LOSS_PER_OVERSHOOT * overshoot
        return max(1.0 - loss, MISTAKE_FLOOR)           # ran wide, scrubbed speed
    c = attempt
    if u < APEX_FRACTION:                               # entry: trail-brake down to the apex
        c_entry = c + ENTRY_CARRY * (1 - c)
        x = u / APEX_FRACTION
        return math.sqrt(c_entry + (c - c_entry) * _smoothstep(x))   # grip ~ v^2
    x = (u - APEX_FRACTION) / (1 - APEX_FRACTION)       # exit: squeeze on, ease to the limit
    return math.sqrt(c + (1 - c) * _smoothstep(x))


def _smoothstep(x):
    """0 -> 1 with zero slope at both ends (no sudden pedal stabs)."""
    return x * x * (3 - 2 * x)


def apply_plan(grid, v_limit, plan):
    """Scale the corner speed limits by the driver's plan."""
    out = list(v_limit)
    for i, (s, cid) in enumerate(zip(grid.s, grid.corner_id)):
        if cid < 0:
            continue
        a = plan[cid]
        u = 0.0 if a.s_end <= a.s_start else min(max((s - a.s_start) / (a.s_end - a.s_start), 0.0), 1.0)
        factor = corner_speed_factor(a.attempt, u) * (1 + correction(a, s))
        out[i] = v_limit[i] * min(factor, 1.0)            # corrections never beat physics
    return out
