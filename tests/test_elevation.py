"""Analytic road-grade checks and elevated-course compatibility contracts."""
from dataclasses import replace
import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path

import pytest

from sim.car import load_car
from sim.dynamics import DriveState, advance, brake_forces, car_constants, drive_accel
from sim.elevation import ElevationProfile, RoadPoint
from sim.forces import drag, max_lateral_accel, road_normal_force, road_rolling_resistance
from sim.lap import corner_speed, elevated_corner_speed, run_lap
from sim.powertrain import effective_mass
from sim.track import discretize, load_elevated_course, load_track, parse_pace_notes, track_xy
from sim.units import G

ROOT = Path(__file__).parent.parent
COURSE_FILE = ROOT / "data/tracks/local_curves_elevated_v2.json"
FLAT_FILE = ROOT / "data/tracks/local_curves.txt"
CAR_FILE = ROOT / "data/cars/eg6_sir_ii_1995.json"
BRIDGE = ROOT / "tools/game_bridge.py"


def bridge_run(tmp_path, command, name):
    out = tmp_path / name
    proc = subprocess.run([sys.executable, str(BRIDGE), command, "--car", "game",
                           "--out", str(out)], cwd=ROOT, capture_output=True, text=True, check=True)
    return json.loads(proc.stdout), json.loads(out.read_text(encoding="utf-8"))


def test_constant_slope_has_exact_height_grade_arc_length_and_contact_force():
    q = 0.1
    profile = ElevationProfile([(0, 0), (100, 10)], q, q)
    car = load_car(CAR_FILE)
    for s in (0, 1, 47, 100):
        point = profile.point(s)
        assert point.z == pytest.approx(q * s, abs=1e-12)
        assert point.grade == pytest.approx(q, abs=1e-12)
        assert point.grade_change == pytest.approx(0, abs=1e-12)
        assert road_normal_force(car, point, 30) == pytest.approx(car.mass * G / math.sqrt(1 + q*q))
        assert road_rolling_resistance(car, point, 30) == pytest.approx(car.crr * car.mass * G / math.sqrt(1 + q*q))
    assert profile.path_length(0, 100) == pytest.approx(100 * math.sqrt(1 + q*q), abs=1e-10)


def test_gravity_energy_on_a_constant_slope_has_no_double_count():
    car = replace(load_car(CAR_FILE), cd=0.0, crr=0.0)
    k = car_constants(car)
    moving_mass = effective_mass(car, 1, engine_coupled=False)
    for grade, speed in ((0.05, 20.0), (-0.05, 0.0)):
        point = ElevationProfile([(0, 0), (100, grade * 100)], grade, grade).point(50)
        expected_a = -car.mass * G * grade / math.sqrt(1 + grade*grade) / moving_mass
        a, limit = drive_accel(car, k, speed, 1, True, point)
        assert limit == "shift" and a == pytest.approx(expected_a, abs=1e-12)
        traveled = 20.0
        state, dt, _, _ = advance(car, k, DriveState(speed, 1, 1000), traveled, road=point)
        assert state.v ** 2 == pytest.approx(speed ** 2 + 2 * expected_a * traveled, abs=1e-9)
        assert dt == pytest.approx(2 * traveled / (speed + state.v), abs=1e-10)
        # Path rise is sin(theta) * path length, so effective-mass kinetic
        # energy changes by exactly the car's gravitational potential energy.
        assert 0.5 * moving_mass * (state.v**2 - speed**2) == pytest.approx(
            -car.mass * G * point.sin_angle * traveled, abs=1e-8)


def test_braking_force_balance_includes_grade_once_and_drag_is_tangential():
    car = load_car(CAR_FILE)
    k = car_constants(car)
    speed = 25.0
    points = [RoadPoint(0, q, 0) for q in (0.05, 0.0, -0.05)]
    decels = []
    for point in points:
        decel, front, rear = brake_forces(car, k, speed, road=point)
        expected = (front + rear + drag(car, speed)
                    + road_rolling_resistance(car, point, speed)
                    + car.mass * G * point.sin_angle) / k.m_brake
        assert decel == pytest.approx(expected, abs=1e-9)
        decels.append(decel)
    assert decels[0] > decels[1] > decels[2]


def test_spline_is_c2_at_authored_knots_and_keeps_plausible_contact():
    profile = load_elevated_course(COURSE_FILE).elevation
    for s, z in profile.samples:
        assert profile.point(s).z == pytest.approx(z, abs=1e-10)
    for s, _ in profile.samples[1:-1]:
        left, right = profile.point(s - 1e-6), profile.point(s + 1e-6)
        assert left.z == pytest.approx(right.z, abs=2e-7)
        assert left.grade == pytest.approx(right.grade, abs=2e-8)
        assert left.grade_change == pytest.approx(right.grade_change, abs=2e-8)
    points = [profile.point(i * profile.length / 1000) for i in range(1001)]
    assert max(abs(p.grade) for p in points) < 0.07
    assert min(p.normal_accel(60) for p in points) > 7.0
    assert profile.point(0).z == pytest.approx(0, abs=1e-12)
    assert profile.point(profile.length).z == pytest.approx(0, abs=1e-12)
    assert max(p.z for p in points) > 14
    assert profile.path_length(0, profile.length) > profile.length


@pytest.mark.parametrize("samples,start,end", [
    ([(1, 0), (100, 0)], 0, 0),
    ([(0, 0), (0, 1)], 0, 0),
    ([(0, 0), (100, float("nan"))], 0, 0),
    ([(0, 0), (100, 30)], 0, 0),
    ([(0, 0), (100, 0)], float("inf"), 0),
])
def test_malformed_profiles_are_rejected(samples, start, end):
    with pytest.raises(ValueError):
        ElevationProfile(samples, start, end)


def test_course_hash_includes_profile_and_checks_legacy_base(tmp_path):
    course = load_elevated_course(COURSE_FILE)
    assert course.snapshot() == {
        "road_id": "LOCAL_CURVES_ELEVATED_V2", "geometry_version": 2,
        "geometry_sha256": "dccad8c917d9de73082079e3fe67f26a827f986c5d12375f9965b71eb4217246",
    }
    data = json.loads(COURSE_FILE.read_text(encoding="utf-8"))
    (tmp_path / "local_curves.txt").write_bytes(FLAT_FILE.read_bytes())
    data["elevation_samples"][2][1] += 1
    changed = tmp_path / "changed.json"
    changed.write_text(json.dumps(data), encoding="utf-8")
    assert load_elevated_course(changed).geometry_sha256 != course.geometry_sha256
    data["base_track_sha256"] = "0" * 64
    changed.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(ValueError, match="base track hash"):
        load_elevated_course(changed)


def test_horizontal_geometry_and_path_distance_are_distinct():
    course = load_elevated_course(COURSE_FILE)
    elevated = discretize(course.segments, 0.5, course.elevation)
    flat = discretize(load_track(FLAT_FILE), 0.5)
    assert elevated.s == flat.s and elevated.curvature == flat.curvature
    assert elevated.path_s[-1] == pytest.approx(871.2308212099324, abs=1e-7)
    assert elevated.path_s[-1] > elevated.s[-1]
    assert track_xy(course.segments, elevated.s) == track_xy(load_track(FLAT_FILE), flat.s)


def test_explicit_zero_elevation_matches_legacy_flat_solver():
    segments = load_track(FLAT_FILE)
    length = sum(seg.length for seg in segments)
    car = load_car(CAR_FILE)
    old = run_lap(car, discretize(segments, 0.5)).lap_time
    zero = run_lap(car, discretize(segments, 0.5,
                                   ElevationProfile([(0, 0), (length, 0)]))).lap_time
    assert zero == pytest.approx(old, abs=1e-9)


def test_crest_reduces_and_compression_increases_lateral_limit():
    car = load_car(CAR_FILE)
    curvature = 1 / 80
    flat = corner_speed(car_constants(car), curvature)
    crest = elevated_corner_speed(car, curvature, RoadPoint(0, 0, -0.0005))
    compression = elevated_corner_speed(car, curvature, RoadPoint(0, 0, 0.0005))
    assert crest < flat < compression
    assert max_lateral_accel(car, normal_accel=G) == pytest.approx(car_constants(car).a_lat)


def test_grade_changes_measured_acceleration_direction_on_a_straight():
    car = load_car(CAR_FILE)
    segments = parse_pace_notes("S 402.336")
    flat = run_lap(car, discretize(segments, 0.5)).lap_time
    up = ElevationProfile([(0, 0), (402.336, 20.1168)], 0.05, 0.05)
    down = ElevationProfile([(0, 0), (402.336, -20.1168)], -0.05, -0.05)
    uphill = run_lap(car, discretize(segments, 0.5, up)).lap_time
    downhill = run_lap(car, discretize(segments, 0.5, down)).lap_time
    assert uphill > flat > downhill


def test_elevated_lap_repeatability_convergence_and_telemetry():
    course = load_elevated_course(COURSE_FILE)
    car = load_car(CAR_FILE)
    grid = discretize(course.segments, 0.5, course.elevation)
    first = run_lap(car, grid)
    second = run_lap(car, grid)
    finer = run_lap(car, discretize(course.segments, 0.25, course.elevation))
    flat = run_lap(car, discretize(course.segments, 0.5))
    flat_finer = run_lap(car, discretize(course.segments, 0.25))
    assert first.lap_time == second.lap_time
    assert abs(first.lap_time - finer.lap_time) < 0.03
    # The inherited corner-grid boundary effect shifts both absolute times;
    # the hill's measured difference must converge independently of it.
    assert abs((first.lap_time - flat.lap_time)
               - (finer.lap_time - flat_finer.lap_time)) < 0.001
    assert len(first.telemetry.s) == len(first.telemetry.z) == len(first.telemetry.grade)
    for s, z, grade in zip(first.telemetry.s, first.telemetry.z, first.telemetry.grade):
        point = course.elevation.point(s)
        assert z == pytest.approx(point.z, abs=1e-9)
        assert grade == pytest.approx(point.grade, abs=1e-9)
    assert all(a < b for a, b in zip(first.telemetry.t, first.telemetry.t[1:]))


def test_old_flat_replay_and_course_snapshot_are_unchanged(tmp_path):
    reply, replay = bridge_run(tmp_path, "local_curves", "flat.json")
    assert reply["measurements"]["total_time_s"] == 43.369
    assert reply["road"] == {"road_id": "LOCAL_CURVES", "geometry_version": 1,
                             "geometry_sha256": hashlib.sha256(FLAT_FILE.read_bytes()).hexdigest()}
    assert replay["version"] == 1
    assert "centerline_z" not in replay["track"] and "z" not in replay["samples"]


def test_elevated_replay_v2_contains_consistent_vertical_geometry(tmp_path):
    first, replay = bridge_run(tmp_path, "local_curves_elevated", "first.json")
    second, replay_again = bridge_run(tmp_path, "local_curves_elevated", "second.json")
    assert first["road"] == second["road"]
    assert first["measurements"] == second["measurements"]
    assert replay == replay_again
    assert replay["version"] == 2 and replay["track"]["distance_axis"] == "horizontal_centerline_m"
    assert len(replay["track"]["centerline"]) == len(replay["track"]["centerline_z"])
    samples = replay["samples"]
    assert all(len(samples[key]) == len(samples["t"]) for key in ("s", "path_s", "z", "grade", "v"))
    assert samples["path_s"][-1] == pytest.approx(replay["track"]["path_length"], abs=0.001)
    profile = load_elevated_course(COURSE_FILE).elevation
    for s, z, grade in zip(samples["s"], samples["z"], samples["grade"]):
        point = profile.point(s)
        assert z == pytest.approx(point.z, abs=0.001)
        assert grade == pytest.approx(point.grade, abs=1e-6)
