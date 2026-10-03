"""Sensitivity study: change one input at a time by 10% and measure lap time.

Every input gets a "better" change (e.g. +10% power, -10% mass) and the
reverse. If both directions give roughly equal and opposite effects, the
response is close to linear. The result is a tornado chart: inputs ranked by
how much 10% of each is worth, per track.

Standalone:  python tools/sensitivity.py [track_file ...]
             (default: test_track + switchbacks) -> runs/latest/sensitivity.png
"""
import sys
from dataclasses import replace
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

from common import CAR_FILE, DS, ROOT, latest_path   # noqa: E402
from sim.car import load_car                         # noqa: E402
from sim.lap import run_lap                          # noqa: E402
from sim.track import discretize, load_track         # noqa: E402

STEP = 0.10

# name -> (function(car, factor) -> car, factor for the "better" direction)
INPUTS = {
    "Power (torque curve)": (lambda c, f: replace(c, torque_nm=tuple(t * f for t in c.torque_nm)), 1 + STEP),
    "Mass": (lambda c, f: replace(c, mass=c.mass * f), 1 - STEP),
    "Tire grip (mu)": (lambda c, f: replace(c, mu_0=c.mu_0 * f, load_k=c.load_k * f), 1 + STEP),
    "Drag (Cd)": (lambda c, f: replace(c, cd=c.cd * f), 1 - STEP),
    "Brake capacity": (lambda c, f: replace(c, brake_capacity=c.brake_capacity * f), 1 + STEP),
    "Shift time": (lambda c, f: replace(c, shift_time=c.shift_time * f), 1 - STEP),
    "Rotating inertia": (lambda c, f: replace(c, engine_inertia=c.engine_inertia * f,
                                             wheel_inertia=c.wheel_inertia * f), 1 - STEP),
    "Front roll stiffness share": (lambda c, f: replace(c, roll_front=c.roll_front * f), 1 - STEP),
    "Pad fade temperature": (lambda c, f: replace(c, pad_fade_temp=c.pad_fade_temp * f), 1 + STEP),
}


def study(car, track_file):
    """Returns (baseline lap time, {input: (delta_better, delta_worse)})."""
    grid = discretize(load_track(track_file), DS)
    base = run_lap(car, grid).lap_time
    results = {}
    for name, (apply, better) in INPUTS.items():
        worse = 2 - better                       # 1.1 <-> 0.9
        d_better = run_lap(apply(car, better), grid).lap_time - base
        d_worse = run_lap(apply(car, worse), grid).lap_time - base
        results[name] = (d_better, d_worse)
    return base, results


def table_lines(track_name, base, results):
    ranked = sorted(results.items(), key=lambda kv: kv[1][0])
    lines = [f"{track_name}: baseline {base:.2f} s", "",
             f"{'Rank':<5}{'Input (10% better)':<29}{'Better':>9}{'Worse':>9}{'% of lap':>10}",
             "-" * 62]
    for i, (name, (db, dw)) in enumerate(ranked, 1):
        lines.append(f"{i:<5}{name:<29}{db:>+9.3f}{dw:>+9.3f}{db / base * 100:>+9.2f}%")
    return lines


def draw(studies, out_path):
    fig, axes = plt.subplots(1, len(studies), figsize=(7.5 * len(studies), 6),
                             layout="constrained", squeeze=False)
    for ax, (track_name, base, results) in zip(axes[0], studies):
        ranked = sorted(results.items(), key=lambda kv: -abs(kv[1][0]))[::-1]
        names = [n for n, _ in ranked]
        better = [r[0] for _, r in ranked]
        worse = [r[1] for _, r in ranked]
        y = range(len(names))
        ax.barh(y, worse, color="#ED2C3C", alpha=0.45, label="10% worse")
        ax.barh(y, better, color="#74C365", label="10% better")
        ax.axvline(0, color="black", linewidth=0.8)
        ax.set_yticks(list(y))
        ax.set_yticklabels(names)
        ax.set_xlabel("Lap time change (s)   <- faster | slower ->")
        ax.set_title(f"{track_name}: baseline {base:.2f} s")
        ax.legend(loc="lower right", fontsize=8)
        ax.grid(axis="x", color="0.9")
    fig.suptitle("Sensitivity: what 10% of each input is worth", fontsize=12)
    fig.savefig(out_path, dpi=120)
    plt.close(fig)


def main():
    tracks = [Path(a) for a in sys.argv[1:]] or [
        ROOT / "data" / "tracks" / "test_track.txt",
        ROOT / "data" / "tracks" / "switchbacks.txt"]
    car = load_car(CAR_FILE)
    studies = []
    for tf in tracks:
        base, results = study(car, tf)
        studies.append((tf.name, base, results))
        print("\n" + "\n".join(table_lines(tf.name, base, results)))
    out = latest_path("sensitivity.png")
    draw(studies, out)
    print(f"\nSaved {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
