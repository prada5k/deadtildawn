"""Permanent LOCAL_STRAIGHT controlled-test contract."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).parent.parent
BRIDGE = ROOT / "tools/game_bridge.py"
ROAD = ROOT / "data/tracks/local_straight.txt"


def run_test(out, *args):
    result = subprocess.run(
        [sys.executable, str(BRIDGE), "local_straight", "--car", "game",
         "--out", str(out), *args],
        cwd=ROOT, capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def test_local_straight_is_permanent_quarter_mile():
    from sim.track import load_track

    segments = load_track(ROAD)
    assert sum(segment.length for segment in segments) == pytest.approx(402.336)
    assert all(not segment.is_corner for segment in segments)


def test_local_straight_is_repeatable_and_writes_existing_replay_contract(tmp_path):
    first = run_test(tmp_path / "first.json")
    second = run_test(tmp_path / "second.json")

    assert first["ok"] and second["ok"]
    assert first["road_id"] == second["road_id"] == "LOCAL_STRAIGHT"
    assert first["road"] == second["road"] == {
        "road_id": "LOCAL_STRAIGHT",
        "geometry_version": 1,
        "geometry_sha256": hashlib.sha256(ROAD.read_bytes()).hexdigest(),
    }
    assert first["measurement_scope"] == {
        "run": "standing-start 402.336 m acceleration",
        "braking": "separate existing 60-0 braking calculation",
    }
    assert first["conditions"] == second["conditions"]
    assert first["measurements"] == second["measurements"]
    assert first["vehicle_state"] == second["vehicle_state"]

    replay = json.loads((tmp_path / "first.json").read_text(encoding="utf-8"))
    assert replay["format"] == "deadtildawn-replay"
    assert replay["track"]["name"] == "LOCAL_STRAIGHT"
    assert replay["driver"] is None
    assert replay["samples"]["brake"] == [0.0] * len(replay["samples"]["brake"])
    assert {"t", "s", "v", "rpm", "gear", "throttle", "brake"} <= set(replay["samples"])


def test_physical_part_definition_reaches_local_straight_without_rpg_modifier(tmp_path):
    stock = run_test(tmp_path / "stock.json")
    modified = run_test(tmp_path / "modified.json", "--parts", "flywheel_light")

    assert stock["vehicle_state"]["car_id"] == modified["vehicle_state"]["car_id"] == "eg6_sir_ii_1995"
    assert modified["installed_definition_ids"] == ["flywheel_light"]
    assert modified["vehicle_state"]["mass_kg"] == pytest.approx(
        stock["vehicle_state"]["mass_kg"] - 3
    )
    assert modified["vehicle_state"]["engine_inertia_kgm2"] == pytest.approx(
        stock["vehicle_state"]["engine_inertia_kgm2"] * 0.65
    )
    for forbidden in ("reward", "cash", "followers", "rep", "xp", "won", "loot"):
        assert forbidden not in modified
