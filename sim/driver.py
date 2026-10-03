"""Driver model: push level, consistency, mistakes, corner technique.

See docs/PHYSICS.md section 6.

- Push level sets f, the fraction of the car's limit the driver aims for.
- Each corner, the actual attempt ~ Normal(f, sigma). sigma = consistency.
- Attempt above 1.0 = more than the tires can give = a mistake.
- Slow in, fast out: the driver enters a clean corner using fraction c of the
  grip (speed ~ sqrt(c)), then rolls on throttle after the apex, reaching the
  full limit at the exit.
- A mistake: the car runs wide at the apex and scrubs speed, worse the further
  over the limit the attempt was.
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
MISTAKE_BASE_LOSS = 0.10      # running wide costs at least 10% of corner speed...
MISTAKE_LOSS_PER_OVERSHOOT = 3.0   # ...plus 3% per 1% the attempt was over the limit
MISTAKE_FLOOR = 0.5           # never below half the corner's limit speed


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

    @property
    def f(self):
        return PUSH_LEVELS[self.push]

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


def plan_corners(driver, corners, rng):
    """Draw one attempt per corner. corners: [(text, s_start, s_end), ...]."""
    plan = []
    for text, s0, s1 in corners:
        attempt = rng.gauss(driver.f, driver.sigma) if driver.sigma > 0 else driver.f
        plan.append(CornerAttempt(text, attempt, attempt > 1.0, s0, s1))
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
    if u < APEX_FRACTION:
        return math.sqrt(c)                             # slow in (grip ~ v^2)
    x = (u - APEX_FRACTION) / (1 - APEX_FRACTION)
    ramp = x * x * (3 - 2 * x)                          # smoothstep: squeeze on, then ease to the limit
    return math.sqrt(c + (1 - c) * ramp)                # fast out


def apply_plan(grid, v_limit, plan):
    """Scale the corner speed limits by the driver's plan."""
    out = list(v_limit)
    for i, (s, cid) in enumerate(zip(grid.s, grid.corner_id)):
        if cid < 0:
            continue
        a = plan[cid]
        u = 0.0 if a.s_end <= a.s_start else min(max((s - a.s_start) / (a.s_end - a.s_start), 0.0), 1.0)
        out[i] = v_limit[i] * corner_speed_factor(a.attempt, u)
    return out
