"""Tests for the driver model (PHYSICS.md 6)."""
import random
from pathlib import Path

import pytest

from sim.car import load_car
from sim.driver import (CRASH_MARGIN, PUSH_LEVELS, RUN_MISTAKE_TARGETS, CornerAttempt, Driver,
                        corner_speed_factor, per_corner_probability, plan_corners)
from sim.lap import run_lap
from sim.track import discretize, load_track

ROOT = Path(__file__).parent.parent
CAR_FILE = ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json"
TRACK = ROOT / "data" / "tracks" / "test_track.txt"


@pytest.fixture(scope="module")
def car():
    return load_car(CAR_FILE)


@pytest.fixture(scope="module")
def grid():
    return discretize(load_track(TRACK), 0.1)


# ---------- push-level tuning (Spire's targets) ----------

def test_per_corner_probability():
    # 1 - (1 - 0.75)^(1/5) = 0.2421 per corner for 75% per 5-corner run
    assert per_corner_probability(0.75) == pytest.approx(0.2421, abs=1e-4)


@pytest.mark.parametrize("push", list(RUN_MISTAKE_TARGETS))
def test_push_levels_hit_run_targets_analytically(push):
    p = Driver(push=push).mistake_chance_per_corner()
    assert 1 - (1 - p) ** 5 == pytest.approx(RUN_MISTAKE_TARGETS[push], abs=1e-6)


def test_push_levels_ordered():
    f = PUSH_LEVELS
    assert f["safe"] < f["normal"] < f["hard"] < f["flat_out"] < 1.0


@pytest.mark.parametrize("push", list(RUN_MISTAKE_TARGETS))
def test_sampled_mistake_rates_match_targets(push):
    # Draw 20,000 five-corner plans: the sampled rate must match the target
    rng = random.Random(42)
    corners = [("C", 0, 1)] * 5
    d = Driver(push=push)
    runs = 20000
    hits = sum(any(a.mistake for a in plan_corners(d, corners, rng)) for _ in range(runs))
    assert hits / runs == pytest.approx(RUN_MISTAKE_TARGETS[push], abs=0.015)


def test_more_consistent_driver_makes_fewer_mistakes():
    rookie, trained = Driver(push="hard", sigma=0.02), Driver(push="hard", sigma=0.012)
    assert trained.mistake_chance_per_corner() < rookie.mistake_chance_per_corner()


# ---------- corner technique ----------

def test_corner_technique_factor():
    # Clean corner at c = 0.96: entry grip 0.96 + 0.5 * 0.04 = 0.98 -> sqrt = 0.990,
    # trail-brake to the apex sqrt(0.96) = 0.980, roll on to the exit 1.0
    assert corner_speed_factor(0.96, 0.0) == pytest.approx(0.98995, abs=1e-4)
    assert corner_speed_factor(0.96, 0.5) == pytest.approx(0.97980, abs=1e-4)
    assert corner_speed_factor(0.96, 1.0) == pytest.approx(1.0)


def test_apex_is_the_slowest_point():
    f = [corner_speed_factor(0.96, u / 20) for u in range(21)]
    assert min(f) == pytest.approx(f[10])
    assert all(b <= a for a, b in zip(f[:10], f[1:11]))     # slowing to the apex
    assert all(b >= a for a, b in zip(f[10:], f[11:]))      # speeding up after


def test_mistake_factor():
    # 1% over the limit: lose 10% + 3 x 1% = 13% after the apex
    assert corner_speed_factor(1.01, 0.2) == 1.0
    assert corner_speed_factor(1.01, 0.8) == pytest.approx(0.87)
    assert corner_speed_factor(1.5, 0.8) == pytest.approx(0.5)      # floor


# ---------- lap behaviour ----------

def test_no_driver_is_the_theoretical_limit(car, grid):
    limit = run_lap(car, grid).lap_time
    assert run_lap(car, grid, driver=Driver(push="flat_out", sigma=0.0)).lap_time > limit


def test_same_seed_same_run(car, grid):
    a = run_lap(car, grid, driver=Driver(push="hard"), seed=7).lap_time
    b = run_lap(car, grid, driver=Driver(push="hard"), seed=7).lap_time
    assert a == b


def test_different_seeds_differ(car, grid):
    times = {run_lap(car, grid, driver=Driver(push="hard"), seed=s).lap_time for s in range(5)}
    assert len(times) == 5


def test_clean_pace_ordered_by_push(car, grid):
    # With no randomness, pushing harder is always faster
    t = {p: run_lap(car, grid, driver=Driver(push=p, sigma=0.0)).lap_time for p in PUSH_LEVELS}
    assert t["flat_out"] < t["hard"] < t["normal"] < t["safe"]


def test_corner_speed_rises_toward_exit(car, grid):
    # Slow in, fast out: in the hairpin, exit speed > entry speed
    lap = run_lap(car, grid, driver=Driver(push="normal", sigma=0.0))
    text, s0, s1 = grid.corners[3]                     # L1 180
    v = [vi for si, vi in zip(lap.telemetry.s, lap.telemetry.v) if s0 + 1 <= si <= s1 - 1]
    assert v[-1] > v[0] * 1.01


def test_throttle_varies_in_corner(car, grid):
    # Spire's observation: real drivers don't hold one throttle position mid-corner
    lap = run_lap(car, grid, driver=Driver(push="normal", sigma=0.0))
    text, s0, s1 = grid.corners[2]                     # R3 90
    th = [x for si, x in zip(lap.telemetry.s, lap.telemetry.throttle) if s0 + 1 <= si <= s1 - 1]
    assert max(th) - min(th) > 0.1


def test_mistake_costs_time(car, grid):
    d = Driver(push="hard", sigma=0.0)
    clean = [CornerAttempt(t, d.f, False, a, b) for t, a, b in grid.corners]
    messy = list(clean)
    t, a, b = grid.corners[3]
    messy[3] = CornerAttempt(t, 1.01, True, a, b)       # mistake in the hairpin
    t_clean = run_lap(car, grid, driver=d, plan=clean).lap_time
    t_messy = run_lap(car, grid, driver=d, plan=messy).lap_time
    assert t_messy > t_clean + 0.2



# ---------- driver corrections (Spire: throttle should never hold steady) ----------

def test_throttle_never_holds_steady_in_any_corner(car, grid):
    lap = run_lap(car, grid, driver=Driver(push="normal"), seed=1)
    tel = lap.telemetry
    for text, s0, s1 in grid.corners:
        th = [x for si, x, lim in zip(tel.s, tel.throttle, tel.limit)
              if s0 + 1 <= si <= (s0 + s1) / 2 and lim == "corner"]   # entry half, where it used to be flat
        if len(th) > 10:
            longest_flat = max_run_of_equal(th)
            assert longest_flat < 15, f"{text}: throttle flat for {longest_flat} samples"


def max_run_of_equal(xs, tol=1e-4):
    best = run = 1
    for a, b in zip(xs, xs[1:]):
        run = run + 1 if abs(a - b) < tol else 1
        best = max(best, run)
    return best


def test_corrections_never_exceed_the_limit(car, grid):
    lap = run_lap(car, grid, driver=Driver(push="flat_out"), seed=3)
    for v, vmax in zip(lap.telemetry.v, lap.v_limit):
        assert v <= vmax + 1e-9


def test_calmer_driver_is_slightly_faster(car, grid):
    # Same intent, same corners: corrections cost a little time
    from sim.driver import CornerAttempt
    d = Driver(push="hard")
    plan = run_lap(car, grid, driver=d, seed=2).corner_log
    calm = [CornerAttempt(a.text, a.attempt, a.mistake, a.s_start, a.s_end, ()) for a in plan]
    t_busy = run_lap(car, grid, driver=d, plan=plan).lap_time
    t_calm = run_lap(car, grid, driver=d, plan=calm).lap_time
    assert 0 < t_busy - t_calm < 0.2



def test_rpm_never_steady_in_a_corner(car, grid):
    # Spire's rule: the engine should never sit at one rpm through a corner.
    # Check every 10 m window inside every corner: rpm must change.
    lap = run_lap(car, grid, driver=Driver(push="normal", sigma=0.0))
    tel = lap.telemetry
    for text, s0, s1 in grid.corners:
        pts = [(s, r, g) for s, r, g in zip(tel.s, tel.rpm, tel.gear) if s0 + 1 <= s <= s1 - 1]
        for i in range(0, len(pts) - 100, 50):                 # 10 m windows (ds = 0.1)
            window = [r for _, r, g in pts[i:i + 100] if g != 0]
            if len(window) > 50:
                assert max(window) - min(window) > 5, f"steady rpm in {text} near {pts[i][0]:.0f} m"


def test_feathering_into_the_apex(car, grid):
    # Entry half of a clean corner: the car slows gently, LESS than drag and
    # rolling resistance alone would slow it, so the driver feathers a little
    # throttle (rising toward the apex), with no brakes.
    lap = run_lap(car, grid, driver=Driver(push="normal", sigma=0.0))
    text, s0, s1 = grid.corners[2]                     # R3 90
    mid = (s0 + s1) / 2
    entry = [(th, br) for s, th, br in zip(lap.telemetry.s, lap.telemetry.throttle, lap.telemetry.brake)
             if s0 + 3 <= s <= mid - 3]
    assert all(br == 0.0 for _, br in entry)
    assert all(0.0 < th < 0.2 for th, _ in entry)
    assert max(th for th, _ in entry) - min(th for th, _ in entry) > 0.02   # never steady


# ---------- crashes (attempt > 1 + CRASH_MARGIN = DNF) ----------

@pytest.mark.parametrize("push, per_run", [
    ("safe", 0.00024), ("normal", 0.0009), ("hard", 0.0207), ("flat_out", 0.1217)])
def test_crash_chance_per_run(push, per_run):
    # Spire's crash table: P(attempt > 1.025) per corner from the normal tail,
    # then 1 - (1 - p)^5 for a 5-corner run
    p = Driver(push=push).crash_chance_per_corner()
    assert 1 - (1 - p) ** 5 == pytest.approx(per_run, rel=0.02)


def test_sampled_crashes_match_the_analytic_rate():
    # Monte Carlo check of plan_corners against the analytic tail. Flat out:
    # p = 0.0256 per corner; 100 000 corners -> standard error 0.0005.
    driver = Driver(push="flat_out")
    corners = [("R5 100", 0.0, 50.0)] * 1000
    rng = random.Random(3)
    crashes = sum(a.crash for _ in range(100) for a in plan_corners(driver, corners, rng))
    p = driver.crash_chance_per_corner()
    assert crashes / 100_000 == pytest.approx(p, abs=4 * (p * (1 - p) / 100_000) ** 0.5)


def test_every_crash_is_also_a_mistake():
    plan = plan_corners(Driver(push="flat_out"), [("R5 100", 0.0, 50.0)] * 5000, random.Random(4))
    crashes = [a for a in plan if a.crash]
    assert crashes and all(a.mistake and a.attempt > 1 + CRASH_MARGIN for a in crashes)


def test_skill_scales_the_target_and_the_risk():
    # skill < 1: the driver can only reach part of the push level's target,
    # so a less skilled driver at the same push is slower AND crashes less
    full = Driver(push="hard")
    weak = Driver(push="hard", skill=0.95)
    assert weak.f == pytest.approx(PUSH_LEVELS["hard"] * 0.95)
    assert weak.crash_chance_per_corner() < full.crash_chance_per_corner()


# ---------- human timing: launch reaction + shift durations ----------

def test_timing_draws_are_reproducible_and_bounded():
    from sim.driver import REACTION_RANGE, SHIFT_RANGE, draw_timing
    a, b = draw_timing(7), draw_timing(7)
    assert a == b and draw_timing(8) != a
    assert REACTION_RANGE[0] <= a.reaction <= REACTION_RANGE[1]
    assert all(SHIFT_RANGE[0] <= f <= SHIFT_RANGE[1] for f in a.shift_factors)


def test_timing_averages_out():
    # Hand calc: the draws are N(0.20 s, 0.07 s) and N(1, 0.175), clipped
    # almost symmetrically, so 2000 reactions average 0.20 s within ~0.01 s
    # and the shift factors average 1.0 within ~0.01.
    from sim.driver import REACTION_MEAN, draw_timing
    draws = [draw_timing(s) for s in range(2000)]
    assert sum(d.reaction for d in draws) / 2000 == pytest.approx(REACTION_MEAN, abs=0.01)
    assert sum(d.shift_factors[0] for d in draws) / 2000 == pytest.approx(1.0, abs=0.01)


def test_reaction_delays_the_whole_run(car, grid):
    # The car leaves the line `reaction` seconds after the green: the first
    # sample is at t = reaction and the lap includes it.
    from sim.driver import draw_timing
    lap = run_lap(car, grid, driver=Driver(push="normal", sigma=0.0), seed=3)
    r = draw_timing(3).reaction
    assert lap.telemetry.t[0] == pytest.approx(r) and lap.lap_time == lap.telemetry.t[-1]


def test_the_corner_plan_ignores_timing(car, grid):
    # Timing has its own random stream: the first corner's attempt is still the
    # first gauss draw from random.Random(seed), exactly as before timing existed
    d = Driver(push="hard")
    lap = run_lap(car, grid, driver=d, seed=11)
    assert lap.corner_log[0].attempt == pytest.approx(random.Random(11).gauss(d.f, d.sigma))
