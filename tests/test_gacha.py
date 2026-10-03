"""Tests for rolled parts and pulls (sim/gacha.py, data/parts/pulls.json)."""
import random
from collections import Counter
from pathlib import Path

import pytest

from sim.car import load_car
from sim.gacha import (RARITY_ORDER, instance_part, load_pulls, pull, rarity_at_least,
                       rolled_effects, rolls)
from sim.lap import run_lap
from sim.parts import apply_parts, load_catalog
from sim.track import discretize, load_track

ROOT = Path(__file__).parent.parent


@pytest.fixture(scope="module")
def parts():
    return load_catalog()[1]


@pytest.fixture(scope="module")
def sources():
    return load_pulls()


# ---------- rolled quality ----------

def test_half_quality_is_the_catalog_part(parts):
    for p in parts.values():
        for name, v in rolled_effects(p, 0.5).items():
            assert v == pytest.approx(p["effects"][name]) if not isinstance(v, dict) \
                else all(v[k] == pytest.approx(p["effects"][name][k]) for k in v)


def test_good_roll_improves_benefits_and_shrinks_drawbacks(parts):
    r = parts["tires_r_comp"]                         # grip up, rolling drag up (a drawback)
    lo, hi = rolled_effects(r, 0.0), rolled_effects(r, 1.0)
    assert hi["mu_scale"] > lo["mu_scale"]           # more grip
    assert hi["crr_scale"] < lo["crr_scale"]         # LESS rolling drag
    cams = parts["cams_race"]                         # low end down (drawback), top end up
    lo, hi = rolled_effects(cams, 0.0)["torque_shape"], rolled_effects(cams, 1.0)["torque_shape"]
    assert hi["high"] > lo["high"] and hi["low"] > lo["low"]   # less low-end loss


def test_fixed_spec_parts_dont_roll(parts):
    assert not rolls(parts["fd_44"]) and not rolls(parts["rsb_19"])
    assert rolled_effects(parts["fd_44"], 0.0) == parts["fd_44"]["effects"]


def test_better_roll_is_faster(parts):
    car = load_car(ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json")
    grid = discretize(load_track(ROOT / "data" / "tracks" / "test_track.txt"), 0.5)
    worn = run_lap(apply_parts(car, [instance_part(parts["interior_strip"], 0.0)]), grid).lap_time
    mint = run_lap(apply_parts(car, [instance_part(parts["interior_strip"], 1.0)]), grid).lap_time
    assert mint < worn


# ---------- pulls ----------

def test_pull_is_reproducible(sources, parts):
    a = [pull("swap_meet", sources, parts, {}, random.Random(7))[:2] for _ in range(1)]
    b = [pull("swap_meet", sources, parts, {}, random.Random(7))[:2] for _ in range(1)]
    assert a == b


def test_quality_stays_in_source_range(sources, parts):
    rng = random.Random(1)
    pity = {}
    for _ in range(400):
        pid, q, pity = pull("junkyard", sources, parts, pity, rng)
        if rolls(parts[pid]):
            assert 0.0 <= q <= 0.7


def test_junkyard_never_legendary_crate_never_common(sources, parts):
    rng = random.Random(2)
    pity = {}
    for _ in range(600):
        pid, _, pity = pull("junkyard", sources, parts, pity, rng)
        assert parts[pid]["rarity"] != "legendary"
        pid, _, pity = pull("crate", sources, parts, pity, rng)
        assert parts[pid]["rarity"] != "common"


@pytest.mark.parametrize("source", ["junkyard", "swap_meet", "crate"])
def test_pity_guarantee(sources, parts, source):
    # The longest run of pulls without the pity rarity (or better) is < `within`
    rng = random.Random(3)
    pity, gap, worst = {}, 0, 0
    floor, within = sources[source]["pity"]["rarity"], sources[source]["pity"]["within"]
    for _ in range(3000):
        pid, _, pity = pull(source, sources, parts, pity, rng)
        gap = 0 if rarity_at_least(parts[pid]["rarity"], floor) else gap + 1
        worst = max(worst, gap)
    assert worst < within


def test_rarity_rates_roughly_match_weights(sources, parts):
    # Swap meet, many pulls: commons ~50%, rares ~38% (pity nudges rates up a bit)
    rng = random.Random(4)
    pity, counts = {}, Counter()
    n = 6000
    for _ in range(n):
        pid, _, pity = pull("swap_meet", sources, parts, pity, rng)
        counts[parts[pid]["rarity"]] += 1
    assert counts["common"] / n == pytest.approx(0.50, abs=0.04)
    assert counts["rare"] / n == pytest.approx(0.38, abs=0.04)
    assert counts["legendary"] / n < 0.05
