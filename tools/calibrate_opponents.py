"""Calibrate each opponent's engine CONDITION so a STOCK DX at its best push
level has the opponent's target odds against them (data/opponents.json).
Condition scales engine output (a tired street engine); the stat card shows
the resulting horsepower truthfully. Drivers stay as authored.

    python tools/calibrate_opponents.py                 (all opponents)
    python tools/calibrate_opponents.py --only zed_280z

Writes the calibrated condition back into data/opponents.json. Uses the game's
own solver settings (GAME_DS) so the calibration matches real races.
Uses sim/matchmaking.tune (parallel): a few seconds per opponent.
"""
import argparse
import json

from common import CAR_FILE, ROOT                       # noqa: E402
from game_bridge import GAME_DS                         # noqa: E402
from sim.car import load_car                            # noqa: E402
from sim.matchmaking import power_to_weight, tune     # noqa: E402
from sim.opponents import OPPONENTS_FILE, load_opponents, opponent_car  # noqa: E402
from sim.track import discretize, load_track, parse_pace_notes             # noqa: E402
from sim.trackgen import generate                       # noqa: E402
from sim.units import HP_TO_W                           # noqa: E402

RUNS = 40


def reference_grid(data, spec):
    if "calibrate_on" in spec:
        return discretize(load_track(ROOT / spec["calibrate_on"]), GAME_DS)
    ref = data["street_reference_track"]
    return discretize(parse_pace_notes(generate(ref["seed"], ref["style"]).notes), GAME_DS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    args = ap.parse_args()
    base = load_car(CAR_FILE)
    data = load_opponents()
    for oid, spec in data["opponents"].items():
        if args.only and oid not in args.only:
            continue
        grid = reference_grid(data, spec)
        # Same tuner the game uses every night (sim/matchmaking.py), vs the STOCK DX
        spec["condition"], curve = tune(base, base, spec, grid, spec["target_odds"], runs=RUNS)
        print(f"{spec['name']:<8} {spec['car']:<32} condition {spec['condition']:.3f} "
              f"({power_to_weight(opponent_car(base, spec)) * 1000 / HP_TO_W:.0f} hp/t)  "
              f"target {spec['target_odds']}", flush=True)
        OPPONENTS_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
