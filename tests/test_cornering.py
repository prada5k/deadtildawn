"""Tests for cornering with lateral load transfer (PHYSICS.md 3.4)."""
from dataclasses import replace
from pathlib import Path

import pytest

from sim.car import load_car
from sim.forces import (axle_lateral_caps, lateral_tire_loads, limiting_axle,
                        max_lateral_accel, traction_limit_fwd_ls)
from sim.units import G

CAR_FILE = Path(__file__).parent.parent / "data" / "cars" / "ej6_dx_coupe_1996.json"


@pytest.fixture(scope="module")
def car():
    return load_car(CAR_FILE)


def test_lateral_tire_loads(car):
    # Hand calc at a_y = 8.163 m/s^2:
    #   moment = 1112 * 8.163 * 0.5 = 4539 N*m
    #   front transfer = 0.6 * 4539 / 1.47 = 1853 N; static per tire 3327 N
    #   rear transfer  = 0.4 * 4539 / 1.47 = 1235 N; static per tire 2127 N
    fo, fi, ro, ri = lateral_tire_loads(car, 8.163)
    assert fo == pytest.approx(3327 + 1853, abs=2)
    assert fi == pytest.approx(3327 - 1853, abs=2)
    assert ro == pytest.approx(2127 + 1235, abs=2)
    assert ri == pytest.approx(2127 - 1235, abs=2)


def test_loads_sum_to_weight(car):
    assert sum(lateral_tire_loads(car, 7.0)) == pytest.approx(car.mass * G)


def test_skidpad_in_plausible_band(car):
    # Report-only target: 0.75-0.85 g for economy cars of the era (not measured)
    assert 0.75 <= max_lateral_accel(car) / G <= 0.85


def test_lateral_limit_is_self_consistent(car):
    a = max_lateral_accel(car)
    assert min(axle_lateral_caps(car, a)) == pytest.approx(a, abs=1e-8)


def test_stock_civic_understeers(car):
    # 61% front weight + 60% front roll stiffness: the front saturates first
    assert limiting_axle(car) == "front"


def test_rear_roll_stiffness_has_an_optimum(car):
    # Shifting roll stiffness rearward (rear sway bar) helps until the axles
    # balance; past that the rear saturates first (oversteer) and grip drops
    a = {rf: max_lateral_accel(replace(car, roll_front=rf)) for rf in (0.6, 0.4, 0.2)}
    assert a[0.4] > a[0.6]
    assert a[0.4] > a[0.2]
    assert limiting_axle(replace(car, roll_front=0.2)) == "rear"


def test_load_transfer_costs_grip_vs_equal_tires(car):
    # Lateral transfer + load sensitivity: less than the static four-equal-tire grip
    from sim.forces import static_mu
    assert max_lateral_accel(car) < static_mu(car) * G


def test_fwd_traction_with_load_sensitive_front_tires(car):
    # Fixed point F = axle_grip(front load at a = F/m): ~5151 N
    # (vs 5177 N with one static mu for all tires)
    assert traction_limit_fwd_ls(car) == pytest.approx(5151, abs=1)


def test_wheel_lift_keeps_loads_summing_to_weight(car):
    # Regression: at a 20/80 roll split the rear inside wheel lifts; the extra
    # roll moment must move to the front axle, not disappear
    stiff_rear = replace(car, roll_front=0.2)
    loads = lateral_tire_loads(stiff_rear, 8.0)
    assert loads[3] == pytest.approx(0.0, abs=1e-9)          # rear inside lifted
    assert sum(loads) == pytest.approx(car.mass * G)
