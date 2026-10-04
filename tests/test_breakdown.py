"""Why did I lose (sim/breakdown.py). Synthetic runs with hand-calc answers
first, then real sim runs for the bookkeeping (the buckets add up to the gap)."""
import dataclasses
import math
from pathlib import Path
from types import SimpleNamespace

import pytest

from sim.breakdown import CAUSES, breakdown
from sim.car import load_car
from sim.driver import CornerAttempt, Driver, draw_timing
from sim.lap import run_lap
from sim.telemetry import Telemetry
from sim.track import discretize, load_track, parse_pace_notes

ROOT = Path(__file__).parent.parent
CAR_FILE = ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json"
TRACK = ROOT / "data" / "tracks" / "test_track.txt"
DS = 0.5


def fake_run(v_of_s, length, t0=0.0, brake=None, corner_log=(), dnf=False):
    """A run with speed v(s), timed the way the sim steps (average speed per
    interval), starting the clock at t0 (the launch reaction)."""
    s = [i * DS for i in range(int(round(length / DS)) + 1)]
    v = [v_of_s(x) for x in s]
    t = [t0]
    for i in range(len(s) - 1):
        t.append(t[-1] + 2 * DS / (v[i] + v[i + 1]))
    tel = Telemetry(s=s, t=t, v=v, brake=[brake(x) if brake else 0.0 for x in s])
    return SimpleNamespace(telemetry=tel, corner_log=list(corner_log), dnf=dnf)


def total(bd):
    return sum(bd["totals"].values())


def test_constant_speeds_are_all_exit_speed():
    # Hand calc: 100 m at 25 vs 20 m/s: 100/20 - 100/25 = 1.0 s. Neither car
    # accelerates, so it's all the speed they came in with (exit), none accel.
    straight = parse_pace_notes("S 100")
    bd = breakdown(straight, fake_run(lambda s: 25.0, 100), fake_run(lambda s: 20.0, 100))
    assert bd["gap"] == pytest.approx(1.0, abs=1e-3)
    assert bd["totals"]["exit"] == pytest.approx(1.0, abs=1e-3)
    assert bd["totals"]["accel"] == pytest.approx(0.0, abs=1e-3)
    assert bd["verdict"] == "exit" and bd["complete"]


def test_harder_acceleration_is_all_accel():
    # Same entry 20 m/s; a = 3 vs 2 m/s^2 over 100 m. Kinematics, t = (v - v0)/a:
    #   them: (sqrt(400 + 2*2*100) - 20)/2 = 4.1421 s
    #   me:   (sqrt(400 + 2*3*100) - 20)/3 = 3.8743 s      -> 0.2678 s, all accel
    straight = parse_pace_notes("S 100")
    me = fake_run(lambda s: math.sqrt(400 + 6 * s), 100)
    them = fake_run(lambda s: math.sqrt(400 + 4 * s), 100)
    bd = breakdown(straight, me, them)
    assert bd["gap"] == pytest.approx(0.2678, abs=0.003)
    assert bd["totals"]["exit"] == pytest.approx(0.0, abs=1e-9)    # same entry speed
    assert bd["totals"]["accel"] == pytest.approx(0.2678, abs=0.003)


def test_faster_exit_same_acceleration_is_all_exit():
    # Work-energy: same a = 2 m/s^2, entry 22 vs 20 m/s:
    #   them: (sqrt(400 + 400) - 20)/2 = 4.1421 s
    #   me:   (sqrt(484 + 400) - 22)/2 = 3.8661 s          -> 0.2761 s, all exit
    # The what-if v'^2 = v_them^2 + (22^2 - 20^2) IS my run, so accel ~ 0.
    straight = parse_pace_notes("S 100")
    me = fake_run(lambda s: math.sqrt(484 + 4 * s), 100)
    them = fake_run(lambda s: math.sqrt(400 + 4 * s), 100)
    bd = breakdown(straight, me, them)
    assert bd["gap"] == pytest.approx(0.2761, abs=0.003)
    assert bd["totals"]["exit"] == pytest.approx(0.2761, abs=0.003)
    assert bd["totals"]["accel"] == pytest.approx(0.0, abs=1e-3)


def corner_track():
    segs = parse_pace_notes("S 50, R5 50, S 50")
    return segs, segs[1].text


def test_corner_speed_goes_in_the_corner_bucket():
    # Hand calc: 20 vs 18 m/s through a 50 m corner: 50/18 - 50/20 = 0.278 s
    segs, name = corner_track()
    me = fake_run(lambda s: 20.0, 150)
    them = fake_run(lambda s: 18.0 if 50 <= s < 100 else 20.0, 150)
    bd = breakdown(segs, me, them)
    assert [sec["name"] for sec in bd["sections"]] == [name, "FINISH"]
    corner = bd["sections"][0]
    assert corner["causes"]["corner"] == pytest.approx(0.278, abs=0.01)
    assert corner["v_min_me"] == 20.0 and corner["v_min_them"] == 18.0
    assert bd["verdict"] == "corner"
    assert bd["swings"][0]["cause"] == "corner" and bd["swings"][0]["where"] == name


def test_running_wide_is_a_mistake():
    segs, name = corner_track()
    wide = CornerAttempt(text=name, attempt=1.01, mistake=True, s_start=50.0, s_end=100.0)
    me = fake_run(lambda s: 20.0, 150)
    them = fake_run(lambda s: 18.0 if 50 <= s < 100 else 20.0, 150, corner_log=[wide])
    bd = breakdown(segs, me, them)
    assert bd["sections"][0]["mistake_by"] == "them"
    assert bd["totals"]["mistake"] == pytest.approx(0.278, abs=0.01)
    assert bd["totals"]["corner"] == 0.0


def test_a_wide_exit_counts_as_the_mistake():
    # They run wide (18 vs 20 m/s) and leave the corner slower, both then
    # accelerating at 2 m/s^2. Corner: 50/18 - 50/20 = 0.278 s. Exit straight
    # (kinematics, 50 m): (sqrt(324 + 200) - 18)/2 - (sqrt(400 + 200) - 20)/2
    #   = 2.4454 - 2.2474 = 0.198 s. All of it is the mistake, none "exit".
    segs, name = corner_track()
    wide = CornerAttempt(text=name, attempt=1.01, mistake=True, s_start=50.0, s_end=100.0)
    me = fake_run(lambda s: 20.0 if s < 100 else math.sqrt(400 + 4 * (s - 100)), 150)
    them = fake_run(lambda s: 20.0 if s < 50 else (18.0 if s < 100 else math.sqrt(324 + 4 * (s - 100))),
                    150, corner_log=[wide])
    bd = breakdown(segs, me, them)
    assert bd["totals"]["mistake"] == pytest.approx(0.278 + 0.198, abs=0.012)
    assert bd["totals"]["exit"] == pytest.approx(0.0, abs=1e-9)
    top = bd["swings"][0]
    assert (top["where"], top["cause"], top["mistake_by"]) == (name, "mistake", "them")
    assert top["gain"] == pytest.approx(0.476, abs=0.012)


def test_braking_bucket():
    # Them on the brakes (doesn't matter how hard) over the last 20 m, 18 m/s:
    # 20/18 - 20/20 = 0.111 s in braking
    straight = parse_pace_notes("S 100")
    me = fake_run(lambda s: 20.0, 100)
    them = fake_run(lambda s: 18.0 if s >= 80 else 20.0, 100, brake=lambda s: 1.0 if s >= 79.5 else 0.0)
    bd = breakdown(straight, me, them)
    assert bd["totals"]["braking"] == pytest.approx(0.111, abs=0.01)


def test_launch_and_the_buckets_add_up():
    # Reactions 0.20 vs 0.31 s: 0.11 s off the line; the rest is the 1.0 s of exit
    straight = parse_pace_notes("S 100")
    bd = breakdown(straight, fake_run(lambda s: 25.0, 100, t0=0.20),
                   fake_run(lambda s: 20.0, 100, t0=0.31))
    assert bd["launch"] == pytest.approx(0.11, abs=1e-9)
    assert bd["gap"] == pytest.approx(1.11, abs=1e-3)
    assert total(bd) == pytest.approx(bd["gap"], abs=2e-3)       # rounding only


# ------------------------------------------------------------------ real runs

@pytest.fixture(scope="module")
def setup():
    car = load_car(CAR_FILE)
    segs = load_track(TRACK)
    return car, segs, discretize(segs, DS)


def test_identical_runs_have_no_gap(setup):
    car, segs, grid = setup
    a = run_lap(car, grid, driver=Driver(push="normal"), seed=3)
    b = run_lap(car, grid, driver=Driver(push="normal"), seed=3)
    bd = breakdown(segs, a, b)
    assert bd["gap"] == 0.0 and all(g == 0.0 for g in bd["totals"].values())


def test_a_lighter_car_wins_on_acceleration(setup):
    # Theoretical limit (no driver, no reaction): 250 kg lighter mostly helps
    # acceleration; corner speed (mu g) barely depends on mass
    car, segs, grid = setup
    light = run_lap(dataclasses.replace(car, mass=car.mass - 250), grid)
    stock = run_lap(car, grid)
    bd = breakdown(segs, light, stock)
    assert bd["gap"] == pytest.approx(stock.lap_time - light.lap_time, abs=1e-3)
    assert bd["gap"] > 0 and bd["verdict"] == "accel"
    assert bd["launch"] == 0.0


def test_real_race_bookkeeping(setup):
    car, segs, grid = setup
    me = run_lap(car, grid, driver=Driver(push="hard"), seed=11)
    them = run_lap(car, grid, driver=Driver(push="safe"), seed=12)
    bd = breakdown(segs, me, them)
    assert bd["gap"] == pytest.approx(them.lap_time - me.lap_time, abs=1e-3)
    assert total(bd) == pytest.approx(bd["gap"], abs=0.01)        # 3-decimal rounding of 6 buckets
    assert bd["launch"] == pytest.approx(draw_timing(12).reaction - draw_timing(11).reaction, abs=1e-3)
    assert set(bd["totals"]) == set(CAUSES)
    # Section totals run along with the gap and end on it
    assert bd["sections"][-1]["total"] == pytest.approx(bd["gap"], abs=1e-3)
    assert sum(sec["gain"] for sec in bd["sections"]) + bd["launch"] == pytest.approx(bd["gap"], abs=0.01)


def test_a_crash_cuts_it_short(setup):
    # Flat out, seed 2 crashes at R7 (same seed as tests/test_bridge.py)
    car, segs, grid = setup
    me = run_lap(car, grid, driver=Driver(push="flat_out"), seed=2)
    them = run_lap(car, grid, driver=Driver(push="normal"), seed=5)
    assert me.dnf
    bd = breakdown(segs, me, them)
    assert bd["verdict"] == "crash" and not bd["complete"]
    assert bd["until_s"] == pytest.approx(me.telemetry.s[-1], abs=0.1)
