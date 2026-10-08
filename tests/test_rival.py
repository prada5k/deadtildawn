"""Physics-backed pair-run contract for the authored Phase 7B local rival."""
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).parent.parent
BRIDGE = ROOT / "tools" / "game_bridge.py"
PROFILE = "data/rivals/oxnard_eg6_time_attack.json"


def run_pair(tmp_path, suffix):
    player_replay = tmp_path / f"player_{suffix}.json"
    rival_replay = tmp_path / f"rival_{suffix}.json"
    completed = subprocess.run(
        [sys.executable, str(BRIDGE), "time_attack", "--car", "game",
         "--player-out", str(player_replay), "--rival-out", str(rival_replay),
         "--rival-profile", PROFILE], cwd=ROOT, capture_output=True, text=True,
         check=True,
    )
    return json.loads(completed.stdout), player_replay, rival_replay


def test_authored_rival_is_independent_deterministic_physics_run(tmp_path):
    first, player_replay, rival_replay = run_pair(tmp_path, "first")
    second, _, _ = run_pair(tmp_path, "second")

    assert first["event_id"] == "C96_TA_LOCAL_CURVES_001"
    assert first["rival_id"] == "RIVAL_OXNARD_001"
    assert first["player"]["vehicle_configuration"]["definition_id"] == "eg6_sir_ii_1995"
    assert first["rival"]["vehicle_configuration"]["definition_id"] == "ej6_dx_coupe_1996"
    assert first["player"]["vehicle_configuration"] != first["rival"]["vehicle_configuration"]
    assert first["player"]["road"] == first["rival"]["road"]
    assert first["player"]["conditions"] == first["rival"]["conditions"]
    assert first["player"]["measurements"]["total_time_s"] > 0
    assert first["rival"]["measurements"]["total_time_s"] > 0
    assert first["player"]["measurements"] == second["player"]["measurements"]
    assert first["rival"]["measurements"] == second["rival"]["measurements"]
    assert first["player"]["vehicle_configuration"]["definition_sha256"]
    assert first["rival"]["vehicle_configuration"]["definition_sha256"]
    assert json.loads(player_replay.read_text(encoding="utf-8"))["lap_time"] == first["player"]["measurements"]["total_time_s"]
    assert json.loads(rival_replay.read_text(encoding="utf-8"))["lap_time"] == first["rival"]["measurements"]["total_time_s"]


def test_rival_replay_selects_eg9_only_as_disclaimed_visual_proxy(tmp_path):
    result, _, rival_replay = run_pair(tmp_path, "visual")
    profile = json.loads((ROOT / PROFILE).read_text(encoding="utf-8"))
    visual = json.loads(rival_replay.read_text(encoding="utf-8"))["vehicle_visual"]

    assert profile["vehicle"]["definition_id"] == "ej6_dx_coupe_1996"
    assert visual["visual_id"] == "eg9_ferio_temp_proxy"
    assert visual["role"] == "temporary_visual_proxy"
    assert visual["accuracy"] == "not_visually_accurate"
    assert "Do not relabel this asset as an EJ6" in visual["notice"]
    assert visual["asset_path"] == "res://../art/models/cars/eg9.glb"
    assert result["rival"]["vehicle_configuration"]["definition_id"] == "ej6_dx_coupe_1996"
