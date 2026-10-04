"""Tests for opponents (sim/opponents.py, data/opponents.json) and how
head-to-head races treat crashes."""
import math
import sys
from pathlib import Path

import pytest

from sim.car import load_car
from sim.driver import PUSH_LEVELS
from sim.montecarlo import Distribution
from sim.opponents import (condition_label, driver_read, head_to_head, load_opponents,
                           opponent_car, opponent_driver)

ROOT = Path(__file__).parent.parent
CAR_FILE = ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json"
INF = math.inf


@pytest.fixture(scope="module")
def base():
    return load_car(CAR_FILE)


@pytest.fixture(scope="module")
def data():
    return load_opponents()


# ---------- head to head: a DNF never wins ----------

def test_head_to_head_counts_every_pair():
    # player [50, 52] vs opponent [51]: 50 < 51 wins, 52 doesn't -> 1/2
    assert head_to_head([50.0, 52.0], [51.0]) == 0.5


def test_dnf_never_beats_a_finished_run():
    assert head_to_head([INF], [60.0]) == 0.0          # you crashed, he finished
    assert head_to_head([60.0], [INF]) == 1.0          # he crashed, you finished


def test_both_crash_is_not_a_win():
    # No contest: nobody beats anybody (the game returns the wager)
    assert head_to_head([INF], [INF]) == 0.0


def test_distribution_ignores_dnfs_for_mean_and_spread():
    # times [50, inf, 52]: finished [50, 52], mean 51, stdev sqrt(2) = 1.414, DNF 1/3
    d = Distribution("hard", [50.0, INF, 52.0], [False, True, False])
    assert d.finished == [50.0, 52.0]
    assert d.mean == 51.0
    assert d.stdev == pytest.approx(math.sqrt(2))
    assert d.dnf_rate == pytest.approx(1 / 3)


# ---------- the opponent data ----------

def test_every_opponent_builds(base, data):
    for oid, spec in data["opponents"].items():
        car = opponent_car(base, spec)
        driver = opponent_driver(spec)
        assert car.name == spec["car"] and car.drivetrain in ("FWD", "RWD"), oid
        assert driver.push in PUSH_LEVELS and 0 < driver.skill <= 1.05, oid
        assert condition_label(spec) in ("tired", "worn", "healthy", "fresh"), oid
        assert driver_read(spec).endswith("."), oid


def test_street_list_points_at_real_opponents(data):
    assert data["street"] and set(data["street"]) <= set(data["opponents"])


def test_opponent_never_changes_the_stock_car(base, data):
    # Car is frozen; opponents are copies (dataclasses.replace)
    mass = base.mass
    for spec in data["opponents"].values():
        opponent_car(base, spec)
    assert base.mass == mass and base.drivetrain == "FWD"


def test_condition_scales_the_engine(base, data):
    spec = dict(data["opponents"]["zed_280z"])
    weak = opponent_car(base, {**spec, "condition": 0.7})
    strong = opponent_car(base, {**spec, "condition": 1.0})
    assert max(weak.torque_nm) == pytest.approx(0.7 * max(strong.torque_nm))


# ---------- difficulty (slow: ~12 s) ----------

def test_zed_odds_near_target(base, data):
    # A STOCK DX at its best push level vs Zed on his home road, measured with
    # a big FRESH sample (200 runs a side, not the tuner's seeds): the
    # calibration must hold up on races it never saw. Tolerance 0.12: the
    # tuner itself uses 40 runs, and near the odds cliff that lands within
    # about +-0.1 (sim/matchmaking.py). Catches a physics change that quietly
    # makes Zed much easier or harder: recalibrate if it fails.
    sys.path.insert(0, str(ROOT / "tools"))
    from calibrate_opponents import reference_grid
    from sim.matchmaking import measure_odds
    spec = data["opponents"]["zed_280z"]
    assert measure_odds(base, base, spec, reference_grid(data, spec)) ==         pytest.approx(spec["target_odds"], abs=0.12)
