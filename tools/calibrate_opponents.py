"""Calibrate each opponent's engine CONDITION so a STOCK DX at its best push
level has the opponent's target odds against them (data/opponents.json).
Condition scales engine output (a tired street engine); the stat card shows
the resulting horsepower truthfully. Drivers stay as authored.

    python tools/calibrate_opponents.py                 (all opponents)
    python tools/calibrate_opponents.py --only zed_280z

Writes the calibrated condition back into data/opponents.json. Uses the game's
own solver settings (GAME_DS) so the calibration matches real races.
Each opponent takes ~20-40 s.
"""
import argparse
import json

from common import CAR_FILE, ROOT                       # noqa: E402
from game_bridge import GAME_DS                         # noqa: E402
from sim.car import load_car                            # noqa: E402
from sim.driver import PUSH_LEVELS, Driver              # noqa: E402
from sim.montecarlo import run_many                     # noqa: E402
from sim.opponents import (OPPONENTS_FILE, head_to_head, load_opponents,  # noqa: E402
                           opponent_car, opponent_driver)
from sim.track import discretize, load_track, parse_pace_notes             # noqa: E402
from sim.trackgen import generate                       # noqa: E402

RUNS = 40
ITERATIONS = 7
CONDITION_RANGE = (0.3, 1.6)


def reference_grid(data, spec):
    if "calibrate_on" in spec:
        return discretize(load_track(ROOT / spec["calibrate_on"]), GAME_DS)
    ref = data["street_reference_track"]
    return discretize(parse_pace_notes(generate(ref["seed"], ref["style"]).notes), GAME_DS)


def best_odds(player, opp_times):
    return max(head_to_head(player[p], opp_times) for p in player)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    args = ap.parse_args()
    base = load_car(CAR_FILE)
    data = load_opponents()
    player_cache = {}
    for oid, spec in data["opponents"].items():
        if args.only and oid not in args.only:
            continue
        grid = reference_grid(data, spec)
        key = spec.get("calibrate_on", "street")
        if key not in player_cache:
            player_cache[key] = {p: run_many(base, grid, Driver(push=p), RUNS, seed0=5000).times
                                 for p in PUSH_LEVELS}
        player = player_cache[key]
        lo, hi = CONDITION_RANGE
        for _ in range(ITERATIONS):              # bisection: stronger engine -> lower odds
            spec["condition"] = (lo + hi) / 2
            opp = run_many(opponent_car(base, spec), grid, opponent_driver(spec), RUNS, seed0=7000).times
            if best_odds(player, opp) > spec["target_odds"]:
                lo = spec["condition"]
            else:
                hi = spec["condition"]
        spec["condition"] = round((lo + hi) / 2, 4)
        car = opponent_car(base, spec)
        opp = run_many(car, grid, opponent_driver(spec), RUNS, seed0=7000).times
        from sim.powertrain import torque_at
        from sim.units import HP_TO_W, RPM_TO_RADS
        hp = max(torque_at(car, r) * r * RPM_TO_RADS for r in range(1000, 6800, 50)) / HP_TO_W
        print(f"{spec['name']:<8} {spec['car']:<32} condition {spec['condition']:.3f} ({hp:.0f} hp)  "
              f"best odds {best_odds(player, opp):.2f} (target {spec['target_odds']})", flush=True)
        OPPONENTS_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")
    OPPONENTS_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
