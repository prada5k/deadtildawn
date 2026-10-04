"""Tests for resistive forces, traction, and the straight-line solver."""
from dataclasses import replace
from pathlib import Path

import pytest

from sim.car import load_car
from sim.forces import drag, rolling_resistance, static_mu, traction_limit, traction_limit_fwd
from sim.metrics import time_at_distance, time_to_speed
from sim.straight import run_straight
from sim.units import MPH_TO_MS

CAR_FILE = Path(__file__).parent.parent / "data" / "cars" / "ej6_dx_coupe_1996.json"
QUARTER_MILE = 402.336  # m


@pytest.fixture(scope="module")
def car():
    return load_car(CAR_FILE)


@pytest.fixture(scope="module")
def quarter(car):
    return run_straight(car, QUARTER_MILE, ds=0.1)


@pytest.fixture(scope="module")
def long_run(car):
    return run_straight(car, 3000, ds=0.5)


# ---------- forces (hand calcs) ----------

def test_fwd_traction_limit(car):
    # PHYSICS.md 4.3: mu = 0.9 -> ~5111 N
    assert traction_limit_fwd(car, 0.9) == pytest.approx(5111, rel=0.001)


def test_rwd_traction_limit_hand_calc(car):
    # PHYSICS.md 4.3, RWD: the driven rear axle GAINS load as the car accelerates.
    # F = mu m g (a/L) / (1 - mu h/L); 50/50 DX, constant mu 0.9 (load_k = 0):
    # 0.9 * 1112 * 9.81 * 0.5 / (1 - 0.9 * 0.5 / 2.621) = 4908.8 / 0.8283 = 5926 N
    rwd = replace(car, drivetrain="RWD", weight_front=0.5, mu_0=0.9, load_k=0.0)
    assert traction_limit(rwd) == pytest.approx(5926, rel=0.001)


def test_rwd_load_sensitivity_costs_grip(car):
    # Load-sensitive tires: the loaded rear tires lose mu -> less than the 5926 N
    # constant-mu hand calc (sim: 5815 N, VALIDATION_LOG)
    rwd = replace(car, drivetrain="RWD", weight_front=0.5)
    assert traction_limit(rwd) == pytest.approx(5815, rel=0.001)


def test_rwd_beats_fwd_with_the_same_weight_split(car):
    # Same car, same 50/50 split: accelerating moves load onto a RWD car's
    # driven axle and OFF a FWD car's
    fwd = replace(car, drivetrain="FWD", weight_front=0.5)
    rwd = replace(car, drivetrain="RWD", weight_front=0.5)
    assert traction_limit(rwd) > traction_limit(fwd)


def test_drag_at_60mph(car):
    # 0.5 * 1.225 * 0.32 * 1.90 * 26.82^2 = ~268 N
    assert drag(car, 60 * MPH_TO_MS) == pytest.approx(268, rel=0.002)


def test_rolling_resistance(car):
    # 0.015 * 1112 * 9.81 = ~163.6 N
    assert rolling_resistance(car) == pytest.approx(163.6, rel=0.001)


def test_static_mu(car):
    # PHYSICS.md 3.3: 1.05 - 0.05 * 2.727 kN = ~0.914
    assert static_mu(car) == pytest.approx(0.914, abs=0.001)


# ---------- solver: shift points (hand calcs) ----------

def test_shift_1_to_2_at_limiter(quarter):
    # Event detection lands the shift exactly on the fuel cut
    first = quarter.shifts[0]
    assert first.from_gear == 1
    assert first.rpm == pytest.approx(6800, abs=0.01)


def test_shift_2_to_3_at_limiter(quarter):
    second = quarter.shifts[1]
    assert second.from_gear == 2
    assert second.rpm == pytest.approx(6800, abs=0.01)


def test_shift_3_to_4_below_limiter(long_run):
    # Hand calc: 3rd/4th wheel-force crossover at ~6620 rpm
    third = long_run.shifts[2]
    assert third.from_gear == 3
    assert third.rpm == pytest.approx(6620, abs=30)


def test_quarter_mile_uses_three_gears(quarter):
    # Trap speed ~80 mph is ~5400 rpm in 3rd; 4th is never reached
    assert len(quarter.shifts) == 2


# ---------- solver: sanity ----------

def test_time_and_distance_always_increase(quarter):
    assert all(b > a for a, b in zip(quarter.t, quarter.t[1:]))
    assert all(b > a for a, b in zip(quarter.s, quarter.s[1:]))


def test_car_decelerates_during_shifts(quarter):
    # Mid-shift (gear 0) there is no drive force, only drag and rolling resistance
    shifting = [a for g, a in zip(quarter.gear, quarter.accel) if g == 0]
    assert shifting and all(a < 0 for a in shifting)


def test_never_exceeds_fuel_cut(quarter, car):
    # Physically impossible to pass the fuel cut; must hold to float precision
    assert max(quarter.rpm) <= car.fuel_cut + 1e-6


def test_shift_points_independent_of_step_size(car):
    # With event detection, limiter shifts don't depend on ds
    for ds in (1.0, 0.5, 0.1):
        tel = run_straight(car, QUARTER_MILE, ds=ds)
        assert tel.shifts[0].rpm == pytest.approx(6800, abs=0.01)


# ---------- numerics ----------

def test_converged_in_step_size(car):
    # Halving ds must not change results meaningfully
    a = run_straight(car, QUARTER_MILE, ds=0.1)
    b = run_straight(car, QUARTER_MILE, ds=0.05)
    assert time_to_speed(a, 60 * MPH_TO_MS) == pytest.approx(
        time_to_speed(b, 60 * MPH_TO_MS), abs=0.01)
    assert time_at_distance(a, QUARTER_MILE) == pytest.approx(
        time_at_distance(b, QUARTER_MILE), abs=0.01)


# ---------- rotating inertia (PHYSICS.md 4.5) ----------

def test_tire_force_below_traction_with_inertia(car):
    # Hand calc, 1st gear at 4600 rpm (10.88 m/s):
    #   a = (5437 - 208) / 1383 = 3.78 m/s^2
    #   absorbed = (18.0 + 235.1 kg) * 3.78 = ~957 N
    #   tire force = 5437 - 957 = ~4480 N < 5177 N traction limit
    from sim.powertrain import speed_from_rpm, wheel_force
    from sim.dynamics import spin_absorption
    from sim.powertrain import effective_mass
    v = speed_from_rpm(car, 4600, 1)
    f_engine = wheel_force(car, v, 1)
    resist = drag(car, v) + rolling_resistance(car)
    a = (f_engine - resist) / effective_mass(car, 1)
    f_tire = f_engine - spin_absorption(car, 1, True) * a
    assert f_tire == pytest.approx(4480, rel=0.005)
    assert f_tire < traction_limit_fwd(car, static_mu(car))


def test_stock_car_never_traction_limited(quarter):
    # Regression check of a model finding (not a hand calc): the stock D16Y7
    # can't overpower its tires once inertia is included.
    assert "traction" not in quarter.limit
