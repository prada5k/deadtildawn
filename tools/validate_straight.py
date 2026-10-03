"""Straight-line validation report: sim vs measured targets.

Run from the repo root:  python tools/validate_straight.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))

from sim.car import load_car                                  # noqa: E402
from sim.metrics import (speed_at_distance, time_at_distance,  # noqa: E402
                         time_to_speed, top_speed)
from sim.straight import run_straight                          # noqa: E402
from sim.units import MPH_TO_MS                                # noqa: E402

CAR_FILE = ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json"
QUARTER_MILE = 402.336


def row(name, sim, lo, hi, unit):
    target = f"{lo}" if lo == hi else f"{lo}-{hi}"
    if lo <= sim <= hi:
        err, verdict = 0.0, "PASS"
    else:
        ref = lo if sim < lo else hi
        err = (sim - ref) / ref * 100
        verdict = "FAIL"
    print(f"{name:<22}{sim:>8.2f} {unit:<4}{target:>12} {unit:<4}{err:>+7.1f}%  {verdict}")


def main():
    car = load_car(CAR_FILE)
    targets = json.loads(CAR_FILE.read_text(encoding="utf-8"))["validation_targets"]

    q = run_straight(car, QUARTER_MILE, ds=0.1)
    long = run_straight(car, 8000, ds=0.5)

    print(f"\n{car.name}  (sim mass {car.mass:.0f} kg)\n")
    print(f"{'Test':<22}{'Sim':>8}      {'Target':>12}      {'Error':>7}")
    print("-" * 66)
    z60 = targets["zero_to_60_mph"]["value"]
    row("0-60 mph", time_to_speed(q, 60 * MPH_TO_MS), z60, z60, "s")
    qt = targets["quarter_mile_time"]
    row("Quarter mile time", time_at_distance(q, QUARTER_MILE), qt["min"], qt["max"], "s")
    tr = targets["quarter_mile_trap"]
    row("Quarter mile trap", speed_at_distance(q, QUARTER_MILE) / MPH_TO_MS,
        tr["min"], tr["max"], "mph")
    ts = targets["top_speed"]["value"]
    print(f"{'Top speed (report)':<22}{top_speed(long) / MPH_TO_MS:>8.2f} mph"
          f"{ts:>12} mph   low-confidence target, not graded")

    print("\nShift points:")
    for e in long.shifts:
        print(f"  {e.from_gear}->{e.from_gear + 1} at {e.rpm:.0f} rpm, "
              f"{e.v / MPH_TO_MS:.1f} mph")

    print("\nConvergence (0-60 time vs step size):")
    for ds in (1.0, 0.5, 0.1, 0.05):
        r = run_straight(car, QUARTER_MILE, ds=ds)
        print(f"  ds = {ds:<5} m -> {time_to_speed(r, 60 * MPH_TO_MS):.3f} s")


if __name__ == "__main__":
    main()
