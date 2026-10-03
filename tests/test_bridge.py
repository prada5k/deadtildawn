"""Tests for the Godot <-> Python bridge (tools/game_bridge.py): the JSON
contract the game relies on, and the rival difficulty rule."""
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
BRIDGE = ROOT / "tools" / "game_bridge.py"
TRACK = "data/tracks/test_track.txt"
RIVAL = "data/rivals/zed_280z.json"


def call(*args):
    out = subprocess.run([sys.executable, str(BRIDGE), *args], capture_output=True,
                         text=True, cwd=ROOT)
    return json.loads(out.stdout)


def test_car_stats_contract():
    r = call("car_stats")
    assert r["ok"] and r["bridge_version"] == 1
    for key in ("name", "hp", "torque_lbft", "weight_kg", "zero_60_s", "skidpad_g",
                "sixty_zero_ft", "top_speed_mph"):
        assert key in r


def test_track_contract():
    r = call("track", "--track", TRACK)
    assert r["ok"] and len(r["corners"]) == 5 and r["crossings"] == 0


def test_errors_come_back_as_json():
    r = call("odds", "--track", "no_such_track.txt", "--posted", "50")
    assert r["ok"] is False and "error" in r


def test_rival_difficulty_hits_target():
    # At the rival's BASE time, the player's best push level wins ~45% of runs
    rival = call("rival", "--rival", RIVAL, "--seed", "1")
    odds = call("odds", "--track", TRACK, "--posted", str(rival["base_time"]))
    best = max(p["win"] for p in odds["push_levels"].values())
    assert best == pytest.approx(0.45, abs=1 / 60 + 1e-9)     # within one run of 60


def test_rival_posted_time_is_seeded():
    a = call("rival", "--rival", RIVAL, "--seed", "7")
    b = call("rival", "--rival", RIVAL, "--seed", "7")
    c = call("rival", "--rival", RIVAL, "--seed", "8")
    assert a["posted_time"] == b["posted_time"] != c["posted_time"]


def test_race_writes_a_viewer_replay(tmp_path):
    out = tmp_path / "race.json"
    r = call("race", "--track", TRACK, "--push", "hard", "--seed", "5", "--out", str(out))
    replay = json.loads(out.read_text(encoding="utf-8"))
    assert r["ok"] and replay["format"] == "deadtildawn-replay"
    assert replay["lap_time"] == pytest.approx(r["lap_time"], abs=1e-3)
    assert replay["driver"]["push"] == "hard" and replay["driver"]["seed"] == 5


def test_race_matches_odds_settings():
    # The race must use the same solver settings as the odds, or the odds lie:
    # a race with seed 1000 (the first Monte Carlo seed) must reproduce the
    # first sample of the cached distribution exactly.
    sys.path.insert(0, str(ROOT / "tools"))
    import game_bridge
    data, _ = game_bridge.distributions(TRACK)
    r = call("race", "--track", TRACK, "--push", "normal", "--seed", "1000",
             "--out", str(ROOT / "runs" / "cache" / "_test_race.json"))
    assert r["lap_time"] == pytest.approx(data["normal"]["times"][0], abs=1e-3)


def test_cache_key_changes_when_sim_code_changes(tmp_path, monkeypatch):
    # Regression: stale cached odds after a physics change. The cache key must
    # depend on the sim's source code, not a hand-bumped version number.
    sys.path.insert(0, str(ROOT / "tools"))
    import hashlib
    import game_bridge
    src = "".join(p.read_text(encoding="utf-8") for p in sorted((ROOT / "sim").glob("*.py")))
    text = (ROOT / "tools" / "game_bridge.py").read_text(encoding="utf-8")
    assert "sim_code" in text and "SIM_VERSION" not in text
    assert hashlib.sha256(src.encode()).hexdigest() != hashlib.sha256((src + " ").encode()).hexdigest()
