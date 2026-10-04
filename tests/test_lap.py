"""Tests for the track parser, lap solver, and braking test."""
import math
from pathlib import Path

import pytest

from sim.braking import stopping_distance
from sim.car import load_car
from sim.dynamics import brake_decel, car_constants
from sim.forces import axle_grip, axle_loads, drag, static_mu
from sim.driver import CornerAttempt, Driver
from sim.lap import finish_time, run_lap
from sim.track import (discretize, load_track, parse_pace_notes, severity_radius,
                       track_xy, find_crossings)
from sim.units import FT_TO_M, MPH_TO_MS

ROOT = Path(__file__).parent.parent
CAR_FILE = ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json"
TRACK_FILE = ROOT / "data" / "tracks" / "test_track.txt"


@pytest.fixture(scope="module")
def car():
    return load_car(CAR_FILE)


@pytest.fixture(scope="module")
def segments():
    return load_track(TRACK_FILE)


@pytest.fixture(scope="module")
def lap(car, segments):
    return run_lap(car, discretize(segments, 0.1))


def speeds_in(lap, segments, text):
    """Speeds [m/s] at nodes inside the segment with the given pace-note text."""
    start = 0.0
    for seg in segments:
        end = start + seg.length
        if seg.text == text:
            return [v for s, v in zip(lap.telemetry.s, lap.telemetry.v)
                    if start + 0.5 <= s <= end - 0.5]
        start = end
    raise KeyError(text)


# ---------- severity scale (PHYSICS.md 2) ----------

def test_severity_endpoints():
    assert severity_radius(1) == pytest.approx(15.0)
    assert severity_radius(10) == pytest.approx(500.0)


def test_severity_5():
    # 15 * (500/15)^(4/9) = ~71.3 m
    assert severity_radius(5) == pytest.approx(71.3, abs=0.1)


# ---------- strict parser ----------

def test_parses_test_track(segments):
    assert len(segments) == 11
    assert segments[1].severity == 7 and segments[1].direction == "R"


def test_track_length(segments):
    # Straights 730 m + corner arcs (R x theta) = ~1066.6 m
    assert sum(seg.length for seg in segments) == pytest.approx(1066.6, abs=0.1)


@pytest.mark.parametrize("bad", ["S20", "R13 90", "R3", "X 10", "R0 90",
                                 "S 200,", "r3 90", "R3 0"])
def test_parser_rejects_typos(bad):
    with pytest.raises(ValueError):
        parse_pace_notes(bad)


def test_parser_error_names_the_segment():
    with pytest.raises(ValueError, match="Segment 2 'S20'"):
        parse_pace_notes("S 100, S20")


# ---------- lap solver ----------

def test_standing_start(lap):
    assert lap.telemetry.v[0] == 0.0


def test_hairpin_at_corner_limit(lap, segments):
    # Hand calc: lateral limit 0.832 g (axle-limited, PHYSICS.md 3.4):
    #   sqrt(8.163 * 15) = 11.07 m/s = 39.8 km/h
    v = speeds_in(lap, segments, "L1 180")
    assert min(v) * 3.6 == pytest.approx(39.8, abs=0.1)


def test_r3_at_corner_limit(lap, segments):
    # Hand calc: sqrt(8.163 * 32.7) = 16.34 m/s = 58.8 km/h
    v = speeds_in(lap, segments, "R3 90")
    assert min(v) * 3.6 == pytest.approx(58.8, abs=0.1)


def test_r7_taken_flat(lap, segments):
    # Spire's prediction: ~105 km/h at 200 m is below the R7 limit (~133 km/h),
    # so there is no braking before or through the R7
    r7_end = sum(seg.length for seg in segments[:2])
    limits = [lim for s, lim in zip(lap.telemetry.s, lap.telemetry.limit) if s < r7_end]
    assert "brake" not in limits


def test_never_exceeds_corner_limit(lap):
    for v, vmax in zip(lap.telemetry.v, lap.v_limit):
        assert v <= vmax + 1e-9


def test_time_increases(lap):
    t = lap.telemetry.t
    assert all(b > a for a, b in zip(t, t[1:]))


def test_lap_converged_in_step_size(car, segments):
    a = run_lap(car, discretize(segments, 0.1)).lap_time
    b = run_lap(car, discretize(segments, 0.05)).lap_time
    assert a == pytest.approx(b, abs=0.02)


# ---------- braking (PHYSICS.md 5.1) ----------

def test_stopping_distance_between_analytic_bounds(car):
    # Deceleration grows with speed (drag), so the true distance lies between
    # v0^2 / (2 a(v0)) and v0^2 / (2 a(0))
    k = car_constants(car)
    v0 = 60 * MPH_TO_MS
    lo = v0 ** 2 / (2 * brake_decel(car, k, v0))
    hi = v0 ** 2 / (2 * brake_decel(car, k, 0.0))
    assert lo < stopping_distance(car, v0) < hi


def test_axle_loads_under_braking(car):
    # Hand calc at 8.9 m/s^2 braking: transfer = 1112 * 8.9 * 0.5 / 2.621 = 1888 N
    #   front axle = 10909 * 0.61 + 1888 = 8542 N  (4271 N per tire)
    #   rear axle  = 10909 * 0.39 - 1888 = 2366 N  (1183 N per tire)
    front, rear = axle_loads(car, -8.9)
    assert front / 2 == pytest.approx(4271, abs=1)
    assert rear / 2 == pytest.approx(1183, abs=1)


def test_load_transfer_costs_braking_grip(car):
    # Hand calc: per-tire mu = 1.05 - 0.05 * Fz(kN)
    #   front 0.836 * 4271 * 2 + rear 0.991 * 1183 * 2 = ~9490 N
    #   vs static (4 equal tires) 0.914 * 10909 = ~9967 N  -> ~4.8% less
    front, rear = axle_loads(car, -8.9)
    grip = axle_grip(car, front) + axle_grip(car, rear)
    assert grip == pytest.approx(9490, rel=0.001)
    assert grip / (static_mu(car) * car.mass * 9.81) == pytest.approx(0.952, abs=0.001)


def test_brake_decel_is_self_consistent(car):
    # Fixed point: the converged deceleration must reproduce itself
    k = car_constants(car)
    v = 60 * MPH_TO_MS
    a = brake_decel(car, k, v)
    front, rear = axle_loads(car, -a)
    a_check = (axle_grip(car, front) + axle_grip(car, rear)
               + drag(car, v) + k.f_roll) / k.m_brake
    assert a == pytest.approx(a_check, abs=1e-8)


def test_stopping_distance_converged(car):
    v0 = 60 * MPH_TO_MS
    assert stopping_distance(car, v0, ds=0.01) == pytest.approx(
        stopping_distance(car, v0, ds=0.001), abs=0.005)


# ---------- shifting rules ----------

def test_shifts_are_sequential(lap):
    for e in lap.telemetry.shifts:
        assert abs(e.to_gear - e.from_gear) == 1


def test_no_money_shifts(lap, car):
    # After every downshift the engine must be at or below redline
    from sim.powertrain import rpm_from_speed
    for e in lap.telemetry.shifts:
        if e.to_gear < e.from_gear:
            assert rpm_from_speed(car, e.v, e.to_gear) <= car.redline + 1e-6


def test_exits_hairpin_in_first(lap, segments):
    r1_end = sum(seg.length for seg in segments[:8])
    gears = [g for s, g in zip(lap.telemetry.s, lap.telemetry.gear)
             if r1_end - 5 <= s <= r1_end and g != 0]
    assert gears and all(g == 1 for g in gears)


# ---------- driver inputs ----------

def test_inputs_in_range(lap):
    tel = lap.telemetry
    assert all(0.0 <= x <= 1.0 for x in tel.throttle)
    assert all(0.0 <= x <= 1.0 for x in tel.brake)


def test_never_throttle_and_brake_together(lap):
    tel = lap.telemetry
    assert not any(th > 0 and br > 0 for th, br in zip(tel.throttle, tel.brake))


def test_full_brake_in_braking_zones(lap):
    # QSS braking runs at the limit: pedal ~100% through braking zones
    braking = [b for b, lim in zip(lap.telemetry.brake, lap.telemetry.limit) if lim == "brake"]
    assert braking and sum(b > 0.99 for b in braking) / len(braking) > 0.95


def test_partial_throttle_holding_hairpin(lap, segments):
    # Holding 41.7 km/h only needs enough force to beat drag + rolling resistance
    start = sum(seg.length for seg in segments[:7])
    th = [x for s, x, lim in zip(lap.telemetry.s, lap.telemetry.throttle, lap.telemetry.limit)
          if start + 5 <= s <= start + 40 and lim == "corner"]
    assert th and all(x < 0.2 for x in th)


# ---------- track geometry ----------

def test_straight_goes_east():
    xs, ys, _ = track_xy(parse_pace_notes("S 100"), [0.0, 100.0])
    assert xs[-1] == pytest.approx(100.0) and ys[-1] == pytest.approx(0.0)


def test_right_90_ends_one_radius_over_and_down():
    # Heading east, a right 90 of radius R ends at (R, -R), heading south
    segs = parse_pace_notes("R1 90")
    xs, ys, hs = track_xy(segs, [segs[0].length])
    assert xs[0] == pytest.approx(15.0) and ys[0] == pytest.approx(-15.0)
    assert hs[0] == pytest.approx(-math.pi / 2)


def test_left_360_returns_to_start():
    segs = parse_pace_notes("L4 360")
    xs, ys, _ = track_xy(segs, [segs[0].length])
    assert xs[0] == pytest.approx(0.0, abs=1e-9) and ys[0] == pytest.approx(0.0, abs=1e-9)


def test_hairpin_reverses_heading(segments):
    # Heading change across L1 180 is exactly +pi (left = counter-clockwise)
    start = sum(seg.length for seg in segments[:7])
    end = start + segments[7].length
    _, _, hs = track_xy(segments, [start, end])
    assert hs[1] - hs[0] == pytest.approx(math.pi)


def test_points_spaced_by_arc_length(segments):
    # Consecutive points 0.1 m apart along the track are ~0.1 m apart in space
    s = [i * 0.1 for i in range(10000)]
    xs, ys, _ = track_xy(segments, s)
    gaps = [math.hypot(xs[i + 1] - xs[i], ys[i + 1] - ys[i]) for i in range(len(s) - 1)]
    assert max(gaps) == pytest.approx(0.1, abs=1e-6)


def test_no_crossing_on_simple_track():
    assert find_crossings(parse_pace_notes("S 100, R5 90, S 100, L5 90, S 100")) == []


def test_figure_eight_crosses_once():
    # Two opposite 270-degree loops joined by straights form a figure-8
    segs = parse_pace_notes("S 100, L4 270, S 100, R4 270, S 100")
    assert len(find_crossings(segs)) >= 1


def test_old_test_track_crossed_itself():
    # v1 of the track (R1 hairpin): the S 200 after the hairpin crossed the
    # road right at the R3 entry (R3 starts at ~582 m)
    segs = parse_pace_notes("S 200, R7 65, S 40, L6 25, S 120, R3 90, S 90, "
                            "R1 180, S 200, L5 45, S 40")
    hits = find_crossings(segs)
    assert len(hits) == 1
    x, y, s_a, s_b = hits[0]
    assert 582 < s_a < 600      # just inside the R3
    assert 771 < s_b < 971      # on the S 200 after the hairpin


def test_test_track_has_no_crossings(segments):
    # v2 (L1 hairpin) is a buildable flat road
    assert find_crossings(segments) == []


# ---------- crashes (DNF) ----------

@pytest.fixture(scope="module")
def crashed(car, segments):
    # Scripted: clean through the first corner, crash in the second
    grid = discretize(segments, 0.1)
    plan = [CornerAttempt(text, 1.04 if i == 1 else 0.95, i == 1, s0, s1, crash=i == 1)
            for i, (text, s0, s1) in enumerate(grid.corners)]
    return run_lap(car, grid, driver=Driver(), plan=plan), grid


def test_crash_ends_the_run_at_the_apex(crashed):
    lap, grid = crashed
    text, s0, s1 = grid.corners[1]
    assert lap.dnf and lap.crash_corner == text
    assert lap.telemetry.s[-1] == pytest.approx((s0 + s1) / 2, abs=0.1)   # one step of ds
    assert lap.lap_time == lap.telemetry.t[-1]                            # time of the crash
    assert len(lap.telemetry.t) == len(lap.telemetry.v) == len(lap.telemetry.brake_temp)


def test_dnf_never_beats_a_finished_run(crashed, lap):
    # The crashed run's clock stopped early, so its raw lap_time is SHORTER
    # than a full lap: compare with finish_time(), never lap_time
    dnf, _ = crashed
    assert dnf.lap_time < lap.lap_time
    assert finish_time(dnf) == math.inf and finish_time(lap) == lap.lap_time
    assert finish_time(lap) < finish_time(dnf)
