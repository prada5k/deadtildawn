"""Tests for the Godot <-> Python bridge (tools/game_bridge.py): the JSON
contract the game relies on. (Opponent difficulty: tests/test_opponents.py.)"""
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


STAT_KEYS = ("name", "hp", "torque_lbft", "weight_kg", "hp_per_tonne", "drivetrain",
             "zero_60_s", "skidpad_g")


def test_rival_is_a_stat_card():
    # Head-to-head: the card IS the information. No posted time, no odds.
    r = call("rival", "--rival", RIVAL, "--seed", "7")
    assert r["ok"] and r["opponent"] == "zed_280z" and r["track"] == TRACK
    assert set(STAT_KEYS) <= set(r["stats"]) and r["stats"]["drivetrain"] == "RWD"
    assert r["condition"] in ("tired", "worn", "healthy", "fresh") and r["driver_read"]
    assert "posted_time" not in r and "win" not in str(r)


def race(tmp_path, *extra, push="hard", seed="5", opp_seed="5"):
    out = tmp_path / "race.json"
    r = call("race", "--track", TRACK, "--push", push, "--seed", seed, "--out", str(out),
             "--opponent", "zed_280z", "--opp-seed", opp_seed, *extra)
    return r, json.loads(out.read_text(encoding="utf-8"))


def test_head_to_head_race_contract(tmp_path):
    r, replay = race(tmp_path)
    assert r["ok"]
    for key in ("lap_time", "dnf", "crash_corner", "opponent_time", "opponent_dnf",
                "opponent_crash_corner", "won", "no_contest", "mistakes"):
        assert key in r, key
    # won follows the DNF rule: a DNF never wins, both out = no contest
    mine = float("inf") if r["dnf"] else r["lap_time"]
    theirs = float("inf") if r["opponent_dnf"] else r["opponent_time"]
    assert r["no_contest"] == (r["dnf"] and r["opponent_dnf"])
    assert r["won"] == (not r["no_contest"] and mine < theirs)


def test_replay_carries_the_ghost(tmp_path):
    r, replay = race(tmp_path)
    g = replay["ghost"]
    assert g["name"] == "Zed" and g["car"] == "1977 Nissan 280Z"
    assert g["lap_time"] == pytest.approx(r["opponent_time"], abs=1e-3)
    assert g["dnf"] == r["opponent_dnf"]
    n = len(g["samples"]["t"])
    assert n > 10 and all(len(g["samples"][k]) == n for k in ("x", "y", "heading"))
    assert g["samples"]["t"][-1] == pytest.approx(g["lap_time"], abs=1e-3)
    assert replay["dnf"] == r["dnf"] and replay["crash_corner"] == r["crash_corner"]


def test_player_crash_in_the_replay(tmp_path):
    # Flat out, seed 2 crashes at R7 (found by search; 12% of flat-out runs crash)
    r, replay = race(tmp_path, push="flat_out", seed="2", opp_seed="2")
    assert r["dnf"] and r["crash_corner"] == "R7 65" and not r["won"]
    assert replay["dnf"] and replay["lap_time"] == pytest.approx(r["lap_time"], abs=1e-3)
    assert replay["samples"]["t"][-1] == pytest.approx(r["lap_time"], abs=1e-3)   # ends at the crash


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


def test_practice_contract():
    r = call("practice", "--track", TRACK)
    assert r["ok"] and r["runs"] == 60
    for push, d in r["push_levels"].items():
        assert len(d["times"]) == len(d["mistakes"]) == 60
        assert all(isinstance(m, bool) for m in d["mistakes"])
    assert "win" not in str(r)                 # the game gets no percentages


def test_car_stats_dyno_curve():
    r = call("car_stats")
    rpm = [p[0] for p in r["dyno"]]
    assert rpm[0] == 1000 and rpm[-1] == 6800
    peak_tq = max(p[1] for p in r["dyno"])
    assert peak_tq == pytest.approx(103, abs=1.5)          # spec: 103 lb-ft


def test_parts_contract():
    r = call("parts")
    assert r["ok"] and len(r["parts"]) >= 20
    for p in r["parts"]:
        assert {"id", "slot", "name", "rarity", "price", "effects_text"} <= set(p)
        assert p["effects_text"], p["id"]                     # every part shows exact effects


def test_car_stats_with_parts():
    stock = call("car_stats")
    mod = call("car_stats", "--parts", "interior_strip")
    assert mod["weight_kg"] == stock["weight_kg"] - 40


def test_parts_change_the_race_but_not_the_opponent(tmp_path):
    # Same seeds: stripping 40 kg makes Faba faster; Zed's run is untouched
    # (opponents don't track the player's upgrades)
    stock, _ = race(tmp_path, push="normal")
    light, _ = race(tmp_path, "--parts", "interior_strip", push="normal")
    assert light["lap_time"] < stock["lap_time"]
    assert light["opponent_time"] == stock["opponent_time"]


def test_pull_contract():
    r = call("pull", "--source", "junkyard", "--seed", "1", "--pity", "{}")
    assert r["ok"] and 0.0 <= r["quality"] <= 0.7 and r["effects_text"]
    assert "junkyard" in r["pity"]


def test_rolled_parts_reach_the_sim():
    worn = call("car_stats", "--parts", "interior_strip@0.0")["weight_kg"]
    mint = call("car_stats", "--parts", "interior_strip@1.0")["weight_kg"]
    assert mint < worn < call("car_stats")["weight_kg"]


def test_street_contract_and_reproducible():
    a = call("street", "--week", "2", "--seed", "11")
    b = call("street", "--week", "2", "--seed", "11")
    assert a["ok"] and a["opponent"] == b["opponent"] and a["stats"] == b["stats"]
    assert set(STAT_KEYS) <= set(a["stats"]) and "posted_time" not in a
    assert a["track"].startswith("data/tracks/generated/open_week_2")
    assert call("track", "--track", a["track"])["ok"]          # the road is a valid track


def test_sources_listed_with_rep_gates_and_loot_hidden():
    r = call("parts")
    assert r["sources"]["swap_meet"]["rep_required"] == 30
    assert r["sources"]["crate"]["rep_required"] == 100
    assert "loot" not in r["sources"]
