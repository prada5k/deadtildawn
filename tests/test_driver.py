"""Tests for the driver model (PHYSICS.md 6)."""
import random
from pathlib import Path

import pytest

from sim.car import load_car
from sim.driver import (PUSH_LEVELS, RUN_MISTAKE_TARGETS, CornerAttempt, Driver,
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

def test_slow_in_fast_out_factor():
    # Clean corner at c = 0.96: entry sqrt(0.96) = 0.980, exit back to 1.0
    assert corner_speed_factor(0.96, 0.2) == pytest.approx(0.9798, abs=1e-4)
    assert corner_speed_factor(0.96, 1.0) == pytest.approx(1.0)


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
