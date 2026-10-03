"""Tests for brake heat and fade (PHYSICS.md 5.2-5.4)."""
import math
from dataclasses import replace
from pathlib import Path

import pytest

from sim.brakes import pad_mu, rotor_temp_after, time_constant
from sim.braking import brake_stop, repeated_stops
from sim.car import load_car
from sim.dynamics import car_constants, front_brake_capacity
from sim.forces import axle_grip, axle_loads
from sim.lap import run_lap
from sim.track import discretize, load_track
from sim.units import AMBIENT_C, MPH_TO_MS

ROOT = Path(__file__).parent.parent
CAR_FILE = ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json"
V60 = 60 * MPH_TO_MS


@pytest.fixture(scope="module")
def car():
    return load_car(CAR_FILE)


@pytest.fixture(scope="module")
def no_cooling_stops(car):
    return repeated_stops(car, 8, V60, cooling=False)


@pytest.fixture(scope="module")
def switchbacks():
    return discretize(load_track(ROOT / "data" / "tracks" / "switchbacks.txt"), 0.1)


# ---------- pad friction and cooling ----------

def test_pad_mu_flat_below_fade_onset(car):
    assert pad_mu(car, 30) == pad_mu(car, 350) == pytest.approx(0.40)


def test_pad_mu_fades_above_onset(car):
    # 0.40 - 0.001 * (450 - 350) = 0.30
    assert pad_mu(car, 450) == pytest.approx(0.30)


def test_pad_mu_has_a_floor(car):
    assert pad_mu(car, 2000) == pytest.approx(car.pad_mu_min)


def test_cooling_time_constant(car):
    # tau = m*c / hA: 2300 / (4 + 1.15*30) = ~59.7 s at 30 m/s; 2300 / 4 = 575 s parked
    assert time_constant(car, 30) == pytest.approx(59.7, abs=0.1)
    assert time_constant(car, 0) == pytest.approx(575, abs=0.5)


def test_cooling_is_exponential(car):
    # With no heat in, after one time constant the excess drops to 1/e
    tau = time_constant(car, 30)
    t = rotor_temp_after(car, 330.0, 0.0, 30, tau, ambient=30.0)
    assert t - 30 == pytest.approx(300 / math.e, rel=1e-9)


# ---------- brake capacity ----------

def test_cold_capacity_is_ratio_times_front_grip(car):
    k = car_constants(car)
    assert front_brake_capacity(car, k, AMBIENT_C) == pytest.approx(k.f_brake_cap)
    assert k.f_brake_cap > axle_grip(car, axle_loads(car, -8.0)[0])   # can lock the fronts


def test_fade_bites_near_440C(car):
    # Capacity drops below grip once pad_mu < 0.40 / 1.3 = 0.308 -> ~442 C
    k = car_constants(car)
    assert front_brake_capacity(car, k, 430) > k.f_brake_cap / car.brake_capacity
    assert front_brake_capacity(car, k, 455) < k.f_brake_cap / car.brake_capacity


# ---------- repeated-stop fade test (Spire's hand calcs) ----------

def test_one_stop_heats_rotor_65C(no_cooling_stops):
    # Hand calc: 403 kJ x 0.75 / 2 = 151 kJ -> 151000 / (5 x 460) = 65.7 C
    first = no_cooling_stops[0]
    assert first.temp_end - first.temp_start == pytest.approx(65.7, rel=0.015)


def test_fade_onset_during_stop_5(no_cooling_stops):
    # Hand calc: (350 - 30) / 65.7 = 4.87 stops
    assert no_cooling_stops[3].temp_end < 350 < no_cooling_stops[4].temp_end


def test_first_longer_stop_is_stop_7(no_cooling_stops):
    # Hand calc: (440 - 30) / 65.7 = 6.24 -> fade first costs distance on stop 7
    d = [st.distance for st in no_cooling_stops]
    assert all(x == pytest.approx(d[0], rel=1e-6) for x in d[:6])
    assert d[6] > d[0] * 1.01
    assert d[7] > d[6]          # and it keeps getting worse


def test_cooling_between_stops_delays_fade(car, no_cooling_stops):
    cooled = repeated_stops(car, 8, V60, cooling=True)
    for hot, cool in zip(no_cooling_stops[1:], cooled[1:]):
        assert cool.temp_start < hot.temp_start


# ---------- laps ----------

def test_test_track_reaches_equilibrium_below_fade(car):
    # Model finding: back-to-back runs on the short flat test track settle
    # below fade onset, so lap time never changes
    grid = discretize(load_track(ROOT / "data" / "tracks" / "test_track.txt"), 0.1)
    temp, times = AMBIENT_C, []
    for _ in range(6):
        lap = run_lap(car, grid, temp_start=temp)
        times.append(lap.lap_time)
        temp = lap.temp_end
    assert max(lap.telemetry.brake_temp) < car.pad_fade_temp
    assert max(times) - min(times) < 1e-6


def test_weak_pads_fade_on_switchbacks(car, switchbacks):
    weak = replace(car, pad_fade_temp=200)
    fade_proof = replace(car, pad_fade_temp=1e9)
    lap = run_lap(weak, switchbacks)
    assert lap.lap_time > run_lap(fade_proof, switchbacks).lap_time + 0.1
    assert lap.iterations >= 3          # temperature feedback needed several passes


def test_iteration_converged(car, switchbacks):
    weak = replace(car, pad_fade_temp=200)
    a = run_lap(weak, switchbacks, tol=1e-6).lap_time
    b = run_lap(weak, switchbacks, tol=1e-9).lap_time
    assert a == pytest.approx(b, abs=1e-5)


def test_rotor_heats_only_when_braking(car, switchbacks):
    tel = run_lap(car, switchbacks).telemetry
    for i in range(len(tel.s) - 1):
        if tel.limit[i] != "brake":
            assert tel.brake_temp[i + 1] <= tel.brake_temp[i] + 1e-9
