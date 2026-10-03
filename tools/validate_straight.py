"""Validation report: sim vs measured targets (acceleration + braking).

Standalone:  python tools/validate_straight.py
Used by run_all.py for the combined report. Track-independent: these are
straight-line tests of the car.
"""
import json

from common import CAR_FILE                                   # noqa: F401  (sets sys.path)
from sim.braking import stopping_distance
from sim.car import load_car
from sim.forces import limiting_axle, max_lateral_accel
from sim.units import G
from sim.metrics import (speed_at_distance, time_at_distance, time_to_speed,
                         top_speed)
from sim.straight import run_straight
from sim.units import FT_TO_M, MPH_TO_MS

QUARTER_MILE = 402.336

# Acceptance criteria (set before tuning; see docs/VALIDATION_LOG.md)
TOL_QUARTER = 0.015   # +/-1.5% outside the measured range
TOL_ZERO_60 = 0.05    # +/-5%
TOL_BRAKE = 0.015     # +/-1.5% outside the measured range


def _row(name, sim, lo, hi, unit, tol):
    """Error is measured from the nearest edge of the target range."""
    target = f"{lo}" if lo == hi else f"{lo}-{hi}"
    err = 0.0 if lo <= sim <= hi else (sim - (lo if sim < lo else hi)) / (lo if sim < lo else hi) * 100
    verdict = "PASS" if abs(err) <= tol * 100 else "FAIL"
    line = (f"{name:<22}{sim:>8.2f} {unit:<4}{target:>12} {unit:<4}"
            f"{err:>+7.1f}%  {verdict} (tol +/-{tol * 100:.1f}%)")
    return line, verdict == "PASS"


def validation_lines(car, car_file=CAR_FILE, convergence=False):
    """Validation table as text lines, plus whether everything graded passed."""
    targets = json.loads(car_file.read_text(encoding="utf-8"))["validation_targets"]
    q = run_straight(car, QUARTER_MILE, ds=0.1)
    long = run_straight(car, 8000, ds=0.5)

    lines = [f"{'Test':<22}{'Sim':>8}      {'Target':>12}      {'Error':>7}", "-" * 66]
    results = []
    z60 = targets["zero_to_60_mph"]["value"]
    results.append(_row("0-60 mph", time_to_speed(q, 60 * MPH_TO_MS), z60, z60, "s", TOL_ZERO_60))
    qt = targets["quarter_mile_time"]
    results.append(_row("Quarter mile time", time_at_distance(q, QUARTER_MILE),
                        qt["min"], qt["max"], "s", TOL_QUARTER))
    tr = targets["quarter_mile_trap"]
    results.append(_row("Quarter mile trap", speed_at_distance(q, QUARTER_MILE) / MPH_TO_MS,
                        tr["min"], tr["max"], "mph", TOL_QUARTER))
    br = targets["sixty_to_zero"]
    results.append(_row("60-0 mph braking", stopping_distance(car, 60 * MPH_TO_MS) / FT_TO_M,
                        br["min"], br["max"], "ft", TOL_BRAKE))
    lines += [line for line, _ in results]
    ts = targets["top_speed"]["value"]
    lines.append(f"{'Top speed (report)':<22}{top_speed(long) / MPH_TO_MS:>8.2f} mph"
                 f"{ts:>12} mph   low-confidence target, not graded")
    sk = targets["skidpad_g"]
    axle = limiting_axle(car)
    band = f"{sk['min']}-{sk['max']}"
    lines.append(f"{'Skidpad (report)':<22}{max_lateral_accel(car) / G:>8.3f} g   "
                 f"{band:>11} g    plausibility band, not graded; "
                 f"{axle}-limited ({'understeer' if axle == 'front' else 'oversteer'})")

    lines.append("")
    lines.append("Shift points (straight line):")
    for e in long.shifts:
        lines.append(f"  {e.from_gear}->{e.to_gear} at {e.rpm:.0f} rpm, {e.v / MPH_TO_MS:.1f} mph")

    if convergence:
        lines.append("")
        lines.append("Convergence (0-60 time vs step size):")
        for ds in (1.0, 0.5, 0.1, 0.05):
            r = run_straight(car, QUARTER_MILE, ds=ds)
            lines.append(f"  ds = {ds:<5} m -> {time_to_speed(r, 60 * MPH_TO_MS):.3f} s")

    return lines, all(ok for _, ok in results)


def main():
    car = load_car(CAR_FILE)
    lines, _ = validation_lines(car, convergence=True)
    print(f"\n{car.name}  (sim mass {car.mass:.0f} kg)\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
