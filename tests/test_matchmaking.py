"""Matchmaking: matched street racers and nightly engine tuning (sim/matchmaking.py).
Expected values are hand calcs; the tuning test checks the RESULT with fresh
seeds (not the seeds the tuner used)."""
import random
from pathlib import Path

import pytest

from sim.car import load_car
from sim.matchmaking import (condition_for_odds, match_opponent, measure_odds, power_to_weight,
                             tune)
from sim.opponents import load_opponents, opponent_car
from sim.track import discretize, load_track
from sim.units import HP_TO_W

ROOT = Path(__file__).parent.parent
CAR_FILE = ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json"


@pytest.fixture(scope="module")
def base():
    return load_car(CAR_FILE)


def test_interpolates_between_rungs():
    # Hand calc: odds 0.6 at c=1.0, 0.4 at c=1.5; target 0.5 is halfway -> c = 1.25
    curve = [(0.5, 0.8), (1.0, 0.6), (1.5, 0.4), (2.0, 0.2)]
    assert condition_for_odds(curve, 0.5) == pytest.approx(1.25)
    # Exactly on a rung's odds: the bracket is (0.8 > 0.6 >= 0.6) -> c = 1.0
    assert condition_for_odds(curve, 0.6) == pytest.approx(1.0)


def test_clamps_at_the_ladder_ends():
    curve = [(0.5, 0.3), (1.0, 0.2)]
    assert condition_for_odds(curve, 0.5) == 0.5      # even the weakest engine is too strong
    curve = [(0.5, 0.9), (1.0, 0.8)]
    assert condition_for_odds(curve, 0.5) == 1.0      # even the strongest can't stop us


def test_dx_power_to_weight(base):
    # Hand calc: the stock DX makes ~105 hp at 6000 rpm (dyno) in a 1112 kg sim car:
    # 105 x 745.7 W / 1112 kg = 70.4 W/kg
    assert power_to_weight(base) == pytest.approx(105 * HP_TO_W / 1112, rel=0.03)


def test_match_picks_among_the_closest(base):
    data = load_opponents()
    pool = {oid: data["opponents"][oid] for oid in data["street"]}
    ptw = {oid: power_to_weight(opponent_car(base, dict(pool[oid], condition=1.0))) for oid in pool}
    closest = sorted(pool, key=lambda oid: abs(ptw[oid] - power_to_weight(base)))[:3]
    picks = {match_opponent(base, base, pool, random.Random(s)) for s in range(30)}
    assert picks <= set(closest) and len(picks) > 1


def test_tuned_night_is_about_a_coin_flip(base):
    """Tune Zed against the stock DX to 50%, then check with a big FRESH
    sample (200 runs a side). Tolerance 0.12: the tuner uses 40 runs per
    job, and near the odds cliff that lands within about +-0.1."""
    spec = load_opponents()["opponents"]["zed_280z"]
    grid = discretize(load_track(ROOT / "data/tracks/test_track.txt"), 0.5)
    c, curve = tune(base, base, spec, grid, 0.5)
    assert all(o0 >= o1 - 0.15 for (_, o0), (_, o1) in zip(curve, curve[1:]))   # stronger -> lower odds
    assert measure_odds(base, base, dict(spec, condition=c), grid) == pytest.approx(0.5, abs=0.12)
