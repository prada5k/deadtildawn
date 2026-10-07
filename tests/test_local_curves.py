"""Permanent LOCAL_CURVES controlled handling-test contract."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest

from sim.track import find_crossings, load_track


ROOT = Path(__file__).parent.parent
BRIDGE = ROOT / "tools/game_bridge.py"
ROAD = ROOT / "data/tracks/local_curves.txt"


def run_test(out, command="local_curves", *args):
    result = subprocess.run(
        [sys.executable, str(BRIDGE), command, "--car", "game",
         "--out", str(out), *args],
        cwd=ROOT, capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def test_local_curves_authored_geometry_and_identity_are_stable():
    assert hashlib.sha256(ROAD.read_bytes()).hexdigest() == (
        "6ef6f0d8c13c0a470005c4ec58758b4048c74a630b53712345f1e6dea20ccef4"
    )
    segments = load_track(ROAD)
    assert [segment.text for segment in segments] == [
        "S 140", "L3 90", "S 55", "R5 75", "S 70", "R2 120",
        "S 45", "L6 70", "S 65", "R4 90", "S 100",
    ]
    assert sum(segment.length for segment in segments) == pytest.approx(870.4305117)
    assert find_crossings(segments) == []


def test_local_curves_is_repeatable_and_uses_fixed_reference_driver(tmp_path):
    first = run_test(tmp_path / "first.json")
    second = run_test(tmp_path / "second.json")

    assert first["road_id"] == second["road_id"] == "LOCAL_CURVES"
    assert first["conditions"] == second["conditions"]
    assert first["vehicle_state"] == second["vehicle_state"]
    assert first["measurements"] == second["measurements"]
    assert len(first["measurements"]["corners"]) == 5

    replay = json.loads((tmp_path / "first.json").read_text(encoding="utf-8"))
    assert replay["format"] == "deadtildawn-replay"
    assert replay["track"]["name"] == "LOCAL_CURVES"
    assert replay["driver"]["name"] == "Reference"
    assert replay["driver"]["sigma"] == 0.0
    assert replay["driver"]["seed"] == 9605
    assert not any(corner["mistake"] for corner in replay["driver"]["corners"])
    assert max(replay["samples"]["brake"]) > 0


def test_rear_sway_physical_change_reaches_curves_without_assuming_direction(tmp_path):
    stock = run_test(tmp_path / "stock.json")
    modified = run_test(tmp_path / "rsb.json", "local_curves", "--parts", "rsb_19")

    assert stock["vehicle_state"]["front_roll_stiffness_fraction"] == 0.60
    assert modified["vehicle_state"]["front_roll_stiffness_fraction"] == 0.48
    assert modified["installed_definition_ids"] == ["rsb_19"]
    assert modified["measurements"] != stock["measurements"]


def test_lowering_springs_change_physical_cg_before_curves_simulation(tmp_path):
    stock = run_test(tmp_path / "stock.json")
    modified = run_test(tmp_path / "springs.json", "local_curves",
                        "--parts", "springs_lowering")

    assert stock["vehicle_state"]["cg_height_m"] == 0.500
    assert modified["vehicle_state"]["cg_height_m"] == 0.475
    assert modified["installed_definition_ids"] == ["springs_lowering"]
    assert modified["measurements"] != stock["measurements"]


def test_controlled_tests_stay_separate_and_return_no_rewards(tmp_path):
    straight = run_test(tmp_path / "straight.json", "local_straight")
    curves = run_test(tmp_path / "curves.json")

    assert straight["road_id"] == "LOCAL_STRAIGHT"
    assert straight["measurements"] == {
        "zero_60_s": 8.173,
        "quarter_mile_s": 16.561,
        "quarter_mile_trap_mph": 90.2,
        "sixty_zero_ft": 138.8,
    }
    assert curves["road_id"] == "LOCAL_CURVES"
    for reply in (straight, curves):
        for forbidden in ("reward", "cash", "followers", "rep", "xp", "won", "loot", "wager"):
            assert forbidden not in reply
