"""Smoke tests for the tools: the full report runs end to end and writes
every file. (Checks that nothing is broken, not that plots look right.)"""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from run_all import run_all  # noqa: E402

TRACK = ROOT / "data" / "tracks" / "test_track.txt"


def test_run_all_writes_every_file(tmp_path):
    out_dir, lines = run_all(TRACK, mass_delta=-100, runs_dir=tmp_path, stamp="test",
                             copy_to_godot=False)
    assert out_dir == tmp_path / "test_track" / "test"
    for name in ("summary.txt", "track_layout.png", "lap_telemetry.png",
                 "speed_map.png", "fade_test.png", "compare.png", "replay.json"):
        assert (out_dir / name).stat().st_size > 0, name


def test_summary_has_every_section(tmp_path):
    out_dir, _ = run_all(TRACK, mass_delta=-100, runs_dir=tmp_path, stamp="test",
                         copy_to_godot=False)
    text = (out_dir / "summary.txt").read_text(encoding="utf-8")
    for heading in ("== Lap", "== Validation", "== Brake fade test",
                    "== Comparison (-100 kg)", "== Files"):
        assert heading in text
    assert "Notes:   S 200, R7 65" in text          # inputs recorded
    assert "All graded targets: PASS" in text


def test_no_comparison_without_mass(tmp_path):
    out_dir, _ = run_all(TRACK, runs_dir=tmp_path, stamp="test", copy_to_godot=False)
    assert not (out_dir / "compare.png").exists()


# ---------- replay.json contract (what the Godot viewer expects) ----------

def test_replay_contract():
    import math
    from common import load_run
    from export_replay import REPLAY_VERSION, build_replay

    car, segments, _, lap = load_run(TRACK)
    r = build_replay(car, segments, lap, TRACK.name)

    assert r["format"] == "deadtildawn-replay" and r["version"] == REPLAY_VERSION
    for key in ("name", "mass", "redline", "fuel_cut", "pad_fade_temp"):
        assert key in r["car"]
    for key in ("name", "length", "notes", "centerline", "corners"):
        assert key in r["track"]

    channels = ("t", "s", "x", "y", "heading", "v", "gear", "rpm",
                "throttle", "brake", "brake_temp")
    n = len(r["samples"]["t"])
    assert n > 100
    for ch in channels:
        assert len(r["samples"][ch]) == n, ch            # every channel same length
    t = r["samples"]["t"]
    assert all(b > a for a, b in zip(t, t[1:]))          # viewer assumes increasing time
    assert t[-1] == r["lap_time"]                        # last sample is the finish

    for c in r["track"]["corners"]:
        for key in ("text", "severity", "radius", "s_start", "s_end", "mid", "outward"):
            assert key in c
        assert math.hypot(*c["outward"]) == pytest.approx(1.0, abs=1e-3)


def test_replay_outward_points_away_from_turn_center():
    # Regression test for a sign bug: labels/cameras go on the OUTSIDE of a turn.
    # Outside = farther from the corner's center of curvature than the road.
    import math
    from common import load_run
    from export_replay import build_replay
    from sim.track import track_xy

    car, segments, _, lap = load_run(TRACK)
    for c in build_replay(car, segments, lap, TRACK.name)["track"]["corners"]:
        (x,), (y,), (h,) = track_xy(segments, [(c["s_start"] + c["s_end"]) / 2])
        side = 1 if c["direction"] == "L" else -1           # center is to the left of L turns
        cx, cy = x - math.sin(h) * side * c["radius"], y + math.cos(h) * side * c["radius"]
        ox, oy = c["mid"][0] + c["outward"][0] * 10, c["mid"][1] + c["outward"][1] * 10
        assert math.hypot(ox - cx, oy - cy) > c["radius"]


# ---------- sensitivity sanity (physics directions) ----------

def test_better_inputs_never_slow_the_car():
    # Every "10% better" change must make the lap faster or leave it unchanged
    # (brakes don't matter on a flat track without fade). A flipped sign here
    # means a physics bug.
    from common import load_run
    from sensitivity import INPUTS
    from sim.lap import run_lap

    car, _, grid, lap = load_run(TRACK)
    for name in ("Mass", "Power (torque curve)", "Tire grip (mu)", "Drag (Cd)",
                 "Brake capacity"):
        apply, better = INPUTS[name]
        assert run_lap(apply(car, better), grid).lap_time <= lap.lap_time + 1e-9, name



def test_replay_driver_block():
    from common import load_run
    from export_replay import build_replay
    from sim.driver import Driver

    car, segments, _, lap = load_run(TRACK, driver=Driver(push="hard"), seed=3)
    d = build_replay(car, segments, lap, TRACK.name)["driver"]
    assert d["push"] == "hard" and d["seed"] == 3
    assert len(d["corners"]) == 5
    assert all({"text", "attempt", "mistake", "s_start", "s_end"} <= set(c) for c in d["corners"])
    # And the theoretical-limit run has no driver block
    car, segments, _, lap = load_run(TRACK)
    assert build_replay(car, segments, lap, TRACK.name)["driver"] is None


def test_run_all_with_driver_and_odds(tmp_path):
    out_dir, _ = run_all(TRACK, runs_dir=tmp_path, stamp="drv", copy_to_godot=False,
                         push="hard", seed=11, rival=49.6, odds_runs=10)
    text = (out_dir / "summary.txt").read_text(encoding="utf-8")
    assert "push hard" in text and "seed 11" in text
    assert "== Driver meeting" in text
    assert (out_dir / "driver_study.png").exists()
