"""Reading a road on the scout screen (sim/roadread.py). Hand calcs from the
pace notes; the throttle share from a run of the stock DX."""
from pathlib import Path

import pytest

from sim.car import load_car
from sim.lap import run_lap
from sim.roadread import road_read
from sim.track import discretize, load_track, parse_pace_notes

ROOT = Path(__file__).parent.parent
CAR = load_car(ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json")


def read(segments):
    return road_read(segments, run_lap(CAR, discretize(segments, 0.5)))


def test_test_track_by_the_pace_notes():
    # S 200, R7 65, S 40, L6 25, S 120, R3 90, S 90, L1 180, S 200, L5 45, S 40
    # Straights: 200+40+120+90+200+40 = 690 m. Corners, R_n = 15 (500/15)^((n-1)/9):
    #   R7 155.4 m x 65 deg = 176.3   L6 105.2 x 25 = 45.9   R3 32.7 x 90 = 51.4
    #   L1 15.0 x 180 = 47.1          L5 71.3 x 45 = 56.0    -> 376.7 m
    # Straight share 690 / 1066.7 = 0.647; hairpins (<= 25 m): L1 only
    r = read(load_track(ROOT / "data" / "tracks" / "test_track.txt"))
    assert r["length"] == pytest.approx(1066.7, abs=0.5)
    assert r["straight_share"] == pytest.approx(0.647, abs=0.003)
    assert r["longest_straight"] == 200.0
    assert r["tightest"] == {"text": "L1 180", "radius": 15.0}
    assert r["corners"] == 5 and r["hairpins"] == 1


def test_a_straight_is_a_power_road():
    # 400 m of nothing but straight: full throttle except the shifts (~0.4 s
    # each, 2-3 of them in ~19 s), never on the brakes
    r = read(parse_pace_notes("S 400"))
    assert r["full_throttle"] > 0.85 and r["braking"] == 0.0
    assert r["kind"] == "power" and r["tightest"] is None


def test_hairpins_make_a_grip_road():
    r = read(parse_pace_notes("S 60, L1 180, S 60, R1 180, S 60, L1 180, S 60"))
    assert r["hairpins"] == 3 and r["kind"] == "grip"
    assert r["braking"] > 0.0
