"""Tests for the car loader and powertrain.

Every expected value here comes from a hand calculation in docs/PHYSICS.md
or from the car's spec sheet. If a test fails, either the code or the hand
calculation is wrong; find out which.
"""
from pathlib import Path

import pytest

from sim.car import load_car
from sim.powertrain import (engine_rpm, rpm_from_speed, speed_from_rpm,
                            torque_at, wheel_force)
from sim.units import HP_TO_W, MPH_TO_MS, RPM_TO_RADS

CAR_FILE = Path(__file__).parent.parent / "data" / "cars" / "ej6_dx_coupe_1996.json"


@pytest.fixture
def car():
    return load_car(CAR_FILE)


# ---------- car data ----------

def test_sim_mass_is_curb_plus_driver_plus_fuel(car):
    assert car.mass == pytest.approx(1026 + 70 + 16)


def test_has_five_gears(car):
    assert len(car.gear_ratios) == 5


# ---------- rpm <-> speed (hand calcs) ----------

def test_speed_at_3000rpm_in_first(car):
    # Hand calc: 3000 rpm in 1st -> 25.6 km/h (clutch engagement speed)
    assert speed_from_rpm(car, 3000, 1) * 3.6 == pytest.approx(25.56, abs=0.05)


def test_rpm_at_60mph_in_second(car):
    # Hand calc: 60 mph in 2nd -> ~6216 rpm
    assert rpm_from_speed(car, 60 * MPH_TO_MS, 2) == pytest.approx(6216, abs=3)


def test_first_gear_top_speed_at_fuel_cut(car):
    # Hand calc: 1st gear at 6800 rpm -> ~58 km/h
    assert speed_from_rpm(car, 6800, 1) * 3.6 == pytest.approx(57.9, abs=0.2)


def test_rpm_speed_round_trip(car):
    # Converting speed -> rpm -> speed must return the original speed
    v = 20.0
    for gear in range(1, 6):
        assert speed_from_rpm(car, rpm_from_speed(car, v, gear), gear) == pytest.approx(v)


# ---------- torque curve ----------

def test_torque_on_curve_point(car):
    assert torque_at(car, 4500) == pytest.approx(140)


def test_torque_interpolates_between_points(car):
    # Halfway between 4500 (140) and 5000 (138)
    assert torque_at(car, 4750) == pytest.approx(139)


def test_power_at_6200_matches_spec(car):
    # Cross-check: digitized curve should reproduce the 106 hp spec within 3%
    power = torque_at(car, 6200) * 6200 * RPM_TO_RADS
    assert power == pytest.approx(106 * HP_TO_W, rel=0.03)


def test_torque_extrapolates_past_curve(car):
    # Last segment slope: (101 - 114) / 200 = -0.065 N*m/rpm
    assert torque_at(car, 6750) == pytest.approx(101 - 0.065 * 50)


def test_fuel_cut_kills_torque(car):
    assert torque_at(car, 6800) == 0.0
    assert torque_at(car, 7000) == 0.0


# ---------- launch and wheel force ----------

def test_launch_holds_rpm_during_clutch_slip(car):
    assert engine_rpm(car, 0.0, 1) == car.launch_rpm
    assert engine_rpm(car, 3.0, 1) == car.launch_rpm   # ~11 km/h, still slipping


def test_clutch_locks_above_engagement_speed(car):
    v = 10.0   # 36 km/h, above the 25.6 km/h engagement speed
    assert engine_rpm(car, v, 1) == pytest.approx(rpm_from_speed(car, v, 1))


def test_no_launch_slip_outside_first_gear(car):
    assert engine_rpm(car, 1.0, 2) == pytest.approx(rpm_from_speed(car, 1.0, 2))


def test_wheel_force_first_gear_at_peak_torque(car):
    # Hand calc: 139.6 N*m x 13.19 x 0.88 / 0.298 m = ~5437 N
    v = speed_from_rpm(car, 4600, 1)
    assert wheel_force(car, v, 1) == pytest.approx(5437, rel=0.002)


def test_first_gear_exceeds_fwd_traction_limit(car):
    # PHYSICS.md 4.3: FWD traction limit is ~5111 N, so 1st gear at peak
    # torque should overpower the tires (wheelspin)
    v = speed_from_rpm(car, 4600, 1)
    assert wheel_force(car, v, 1) > 5111
