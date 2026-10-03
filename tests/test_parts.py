"""Tests for the parts system (sim/parts.py, data/parts/catalog.json)."""
from pathlib import Path

import pytest

from sim.car import load_car
from sim.forces import G, static_mu
from sim.lap import run_lap
from sim.parts import apply_parts, load_catalog, parts_by_ids, shape_factor
from sim.track import discretize, load_track, parse_pace_notes

ROOT = Path(__file__).parent.parent
CAR_FILE = ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json"


@pytest.fixture(scope="module")
def car():
    return load_car(CAR_FILE)


@pytest.fixture(scope="module")
def catalog():
    return load_catalog()


def test_catalog_is_valid(catalog):
    slots, parts = catalog
    assert len(parts) >= 20
    assert all(p["slot"] in slots for p in parts.values())
    assert {p["rarity"] for p in parts.values()} <= {"common", "rare", "epic", "legendary"}


def test_no_parts_is_stock(car):
    assert apply_parts(car, []) == car


def test_stock_car_never_modified(car, catalog):
    _, parts = catalog
    before = car.mass
    apply_parts(car, [parts["interior_strip"]])
    assert car.mass == before                       # frozen dataclass, new copy returned


def test_masses_add_up(car, catalog):
    mod = apply_parts(car, parts_by_ids(["interior_strip", "hood_carbon", "seats_buckets"]))
    assert mod.mass == pytest.approx(car.mass - 40 - 8 - 14)


def test_torque_shape_endpoints():
    shape = {"low": -0.13, "high": 0.16}
    assert shape_factor(shape, 1000) == pytest.approx(0.87)
    assert shape_factor(shape, 6800) == pytest.approx(1.16)
    assert shape_factor(shape, 3900) == pytest.approx(1.0 + (-0.13 + 0.16) / 2)


def test_grip_scales_at_every_load(car, catalog):
    # mu_scale must scale mu = mu0 - k*Fz at ANY load, so both terms scale
    _, parts = catalog
    mod = apply_parts(car, [parts["tires_300tw"]])
    for fz in (1.0, 3.0, 5.0):
        assert (mod.mu_0 - mod.load_k * fz) == pytest.approx((car.mu_0 - car.load_k * fz) * 1.05)


def test_one_part_per_slot(catalog):
    _, parts = catalog
    with pytest.raises(ValueError):
        apply_parts(load_car(CAR_FILE), [parts["shifter_short"], parts["shifter_race"]])


def test_unknown_part_rejected():
    with pytest.raises(ValueError):
        parts_by_ids(["warp_drive"])


def test_every_part_helps_on_the_test_track(car, catalog):
    _, parts = catalog
    grid = discretize(load_track(ROOT / "data" / "tracks" / "test_track.txt"), 0.5)
    base = run_lap(car, grid).lap_time
    for pid, p in parts.items():
        assert run_lap(apply_parts(car, [p]), grid).lap_time < base, pid


def test_short_final_drive_is_a_specialization(car, catalog):
    # Rarity is specialization: the 4.9 final drive helps on the test track but
    # HURTS on a tight hairpin road (more limiter hits and shifts at low speed)
    _, parts = catalog
    test = discretize(load_track(ROOT / "data" / "tracks" / "test_track.txt"), 0.5)
    tight = discretize(parse_pace_notes(
        "S 60, L1 180, S 60, R1 180, S 60, L2 150, S 60, R1 180, S 60"), 0.5)
    fd49 = apply_parts(car, [parts["fd_49"]])
    assert run_lap(fd49, test).lap_time < run_lap(car, test).lap_time
    assert run_lap(fd49, tight).lap_time > run_lap(car, tight).lap_time


def test_too_much_rear_bar_is_worse(car, catalog):
    # The 24 mm bar overshoots the roll-balance optimum (oversteer)
    from sim.forces import max_lateral_accel
    _, parts = catalog
    a19 = max_lateral_accel(apply_parts(car, [parts["rsb_19"]]))
    a24 = max_lateral_accel(apply_parts(car, [parts["rsb_24"]]))
    assert a19 > a24 > max_lateral_accel(car) * 0.99
