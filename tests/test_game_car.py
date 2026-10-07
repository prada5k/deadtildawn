"""The EJ6 engineering reference and the 1995 EG6 player Civic are separate."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest

from sim.car import load_car


ROOT = Path(__file__).parent.parent
REFERENCE = ROOT / "data/cars/ej6_dx_coupe_1996.json"
GAME = ROOT / "data/cars/eg6_sir_ii_1995.json"
BRIDGE = ROOT / "tools/game_bridge.py"


def test_reference_car_is_unchanged_and_loadable():
    assert hashlib.sha256(REFERENCE.read_bytes()).hexdigest() == (
        "066cee567c1434000c26dde2d3a3eb8fc21461188b908c139d2b2fa49322d60e"
    )
    car = load_car(REFERENCE)
    assert car.id == "ej6_dx_coupe_1996"


def test_game_car_loads_with_sourced_factory_and_assumption_metadata():
    data = json.loads(GAME.read_text(encoding="utf-8"))
    car = load_car(GAME)
    assert (data["model_year"], data["chassis"], data["trim"]) == (1995, "E-EG6", "SiR-II")
    assert car.id == "eg6_sir_ii_1995"
    assert car.mass == pytest.approx(1050 + 70 + 16.65)
    assert car.wheelbase == pytest.approx(2.570)
    assert car.torque_rpm[-1] > 7800
    assert data["engine"]["torque_curve"]["confidence"] == "model-assumption"

    honda_spec = data["source_urls"]["Honda 1995 SiR-II archive"]
    assert honda_spec in data["engine"]["code_source"]
    assert honda_spec in data["tires"]["size_source"]
    assert honda_spec in data["drivetrain_source"]

    def check_values(node):
        if isinstance(node, dict):
            if "value" in node:
                assert node.get("source") and node.get("confidence")
                assert node["confidence"] in {"factory", "factory-converted", "derived", "model-assumption"}
                if node["confidence"] in {"factory", "factory-converted"}:
                    assert honda_spec in node["source"]
            for value in node.values():
                check_values(value)
        elif isinstance(node, list):
            for value in node:
                check_values(value)

    check_values(data)


def test_bridge_car_selection_preserves_reference_default():
    def stats(*args):
        run = subprocess.run([sys.executable, str(BRIDGE), "car_stats", *args],
                             cwd=ROOT, capture_output=True, text=True, check=True)
        return json.loads(run.stdout)

    reference = stats()
    game = stats("--car", "game")
    assert reference["ok"] and "DX Coupe" in reference["name"]
    assert reference["dyno"][-1][0] == 6800
    assert game["ok"] and "SiR-II" in game["name"]
    assert game["dyno"][-1][0] > reference["dyno"][-1][0]
