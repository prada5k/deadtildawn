"""Physics-backed deterministic multi-entrant event contract."""
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).parent.parent
BRIDGE = ROOT / "tools" / "game_bridge.py"
ROSTER = ROOT / "data" / "rivals" / "local_curves_roster_v1.json"


def call(*args):
    completed = subprocess.run([sys.executable, str(BRIDGE), *args], cwd=ROOT,
        capture_output=True, text=True, check=True)
    return json.loads(completed.stdout)


def run_event(tmp_path, suffix):
    out = tmp_path / suffix
    response = call("time_attack", "--car", "game",
        "--player-out", str(out / "player.json"),
        "--rival-out", str(out / "rafa.json"),
        "--entrant-out-dir", str(out / "entrants"),
        "--roster-profile", str(ROSTER))
    return response, out


def test_five_entrant_roster_and_runs_are_deterministic_and_independent(tmp_path):
    first, first_out = run_event(tmp_path, "first")
    second, _ = run_event(tmp_path, "second")

    assert first["roster_id"] == "LOCAL_CURVES_OXNARD_1996_V1"
    assert first["roster_version"] == 1 and first["event_seed"] == 9605
    assert len(first["entrants"]) == 5
    ids = [entrant["entrant_id"] for entrant in first["entrants"]]
    assert ids == ["PLAYER_CHASSIS_0001", "RIVAL_OXNARD_001", "RIVAL_VENTURA_002",
                   "RIVAL_OXNARD_003", "RIVAL_CAMARILLO_004"]
    assert len(set(ids)) == len(ids)

    player = first["player_entrant"]
    assert player["entrant_type"] == "PLAYER"
    assert player["vehicle_id"] == "CHASSIS_0001"
    assert player["vehicle_configuration"]["definition_id"] == "eg6_sir_ii_1995"
    assert first["rival"]["vehicle_configuration"]["definition_id"] == "ej6_dx_coupe_1996"

    entrants_by_id = {entry["entrant_id"]: entry for entry in first["entrants"]}
    configs = [entrants_by_id[entrant_id]["vehicle_configuration"] for entrant_id in ids]
    assert len({json.dumps(config, sort_keys=True) for config in configs}) == 5
    assert [e["simulation_seed"] for e in first["entrants"]] == [9605, 9605, 9606, 9607, 9608]
    for entrant in first["entrants"]:
        assert entrant["road"] == first["player"]["road"]
        assert entrant["event_conditions"] == player["event_conditions"]
        assert entrant["measurements"]["total_time_s"] > 0
        assert Path(entrant["replay"]).is_file()
        assert entrant["driver"]["seed"] == entrant["simulation_seed"]
        assert entrant["vehicle_configuration"]["definition_sha256"]

    assert first["rival"]["measurements"]["total_time_s"] == 44.426
    assert first["player"]["measurements"]["total_time_s"] == 43.369
    assert first["standings"][3]["entrant_id"] == "PLAYER_CHASSIS_0001"
    assert first["standings"][3]["position"] == 4
    assert first["player"]["measurements"] == second["player"]["measurements"]
    assert first["rival"]["measurements"] == second["rival"]["measurements"]
    assert [e["measurements"] for e in first["entrants"]] == [e["measurements"] for e in second["entrants"]]
    assert first["standings"] == second["standings"]

    # Established replay paths remain supported; EG9 is assigned only to Rafa,
    # while other EG6 runs rely on the replay viewer's matching EG6 model.
    rafa_replay = json.loads((first_out / "rafa.json").read_text(encoding="utf-8"))
    assert rafa_replay["vehicle_visual"]["visual_id"] == "eg9_ferio_temp_proxy"
    assert (ROOT / "godot/assets/models/cars/eg6_game.glb").is_file()
    for entrant in first["entrants"][2:]:
        replay = json.loads(Path(entrant["replay"]).read_text(encoding="utf-8"))
        assert replay["car"]["name"].find("EG6") >= 0
        assert "vehicle_visual" not in replay


def test_standings_use_measured_times_and_stable_tie_breaks():
    from tools.game_bridge import _event_standings

    entries = [
        {"entrant_id": "B", "measurements": {"total_time_s": 43.1}},
        {"entrant_id": "C", "measurements": {"total_time_s": 43.2}},
        {"entrant_id": "A", "measurements": {"total_time_s": 43.1}},
    ]
    assert _event_standings(entries) == [
        {"position": 1, "entrant_id": "A", "time_s": 43.1, "gap_to_leader_s": 0.0},
        {"position": 2, "entrant_id": "B", "time_s": 43.1, "gap_to_leader_s": 0.0},
        {"position": 3, "entrant_id": "C", "time_s": 43.2, "gap_to_leader_s": 0.1},
    ]


def test_multi_entrant_player_measurement_matches_controlled_local_curves(tmp_path):
    event, _ = run_event(tmp_path, "baseline")
    local_path = tmp_path / "controlled.json"
    local = call("local_curves", "--car", "game", "--out", str(local_path))
    assert event["player"]["measurements"] == local["measurements"]
    assert event["player"]["road"] == local["road"]
