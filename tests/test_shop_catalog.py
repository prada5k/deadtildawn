"""Active EG6 shop content is physical, fixed-spec, and separate from pulls."""
import json
import subprocess
import sys
from pathlib import Path

from sim.car import load_car
from sim.parts import apply_parts, load_catalog


ROOT = Path(__file__).parent.parent
BRIDGE = ROOT / "tools/game_bridge.py"
GAME = ROOT / "data/cars/eg6_sir_ii_1995.json"


def shop_reply():
    result = subprocess.run([sys.executable, str(BRIDGE), "shop_catalog", "--car", "game"],
                            cwd=ROOT, capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def test_active_shop_has_only_eg6_compatible_fixed_spec_definitions():
    reply = shop_reply()
    assert reply["ok"]
    assert "sources" not in reply and "pity" not in reply
    offered = {p["id"]: p for p in reply["parts"]}
    assert offered and "fd_44" not in offered
    assert all("eg6_sir_ii_1995" in p["compatible_base_car_ids"] for p in offered.values())
    assert all("rarity" not in p and "quality" not in p for p in offered.values())
    assert all(pid in offered for pid in reply["retail_ids"])
    assert all(listing["part"] in offered for listing in reply["initial_used"])
    assert len({listing["listing_id"] for listing in reply["initial_used"]}) == len(reply["initial_used"])


def test_acquisition_source_does_not_change_eg6_physical_effect():
    _, definitions = load_catalog()
    car = load_car(GAME)
    retail = {"uid": "p1", "part": "rsb_19", "source": "retail", "acquired_price": 320}
    used = {"uid": "p2", "part": "rsb_19", "source": "used", "acquired_price": 240,
            "seller_id": "SELLER_0003", "listing_id": "USED_0003"}
    retail_car = apply_parts(car, [definitions[retail["part"]]])
    used_car = apply_parts(car, [definitions[used["part"]]])
    assert retail_car == used_car
    assert retail_car.roll_front == 0.48 != car.roll_front
