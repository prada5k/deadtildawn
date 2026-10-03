"""Compare the stock car against a modified version, on the track and in the
straight-line tests.

Standalone:  python tools/compare.py --mass -100 [--track FILE]
             -> runs/latest/compare.png
Used by run_all.py when --mass is given.

Assumption: mass changes keep the weight distribution and CG height the same
(i.e. weight is removed evenly).
"""
import argparse
from dataclasses import replace
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

from common import DEFAULT_TRACK, latest_path, load_run            # noqa: E402
from sim.braking import stopping_distance                          # noqa: E402
from sim.lap import run_lap                                        # noqa: E402
from sim.metrics import (speed_at_distance, time_at_distance,      # noqa: E402
                         time_to_speed)
from sim.straight import run_straight                              # noqa: E402
from sim.units import FT_TO_M, MPH_TO_MS                           # noqa: E402

QUARTER_MILE = 402.336


def make_variant(car, mass_delta):
    label = f"{mass_delta:+.0f} kg"
    return replace(car, mass=car.mass + mass_delta, name=f"{car.name} ({label})"), label


def _metrics(car, lap, segments):
    q = run_straight(car, QUARTER_MILE, ds=0.1)
    out = {
        "Lap time (s)": lap.lap_time,
        "0-60 mph (s)": time_to_speed(q, 60 * MPH_TO_MS),
        "Quarter mile (s)": time_at_distance(q, QUARTER_MILE),
        "Trap speed (mph)": speed_at_distance(q, QUARTER_MILE) / MPH_TO_MS,
        "60-0 mph (ft)": stopping_distance(car, 60 * MPH_TO_MS) / FT_TO_M,
    }
    start = 0.0
    for seg in segments:
        end = start + seg.length
        if seg.is_corner:
            v = min(vi for si, vi in zip(lap.telemetry.s, lap.telemetry.v) if start <= si <= end)
            out[f"{seg.text} min speed (km/h)"] = v * 3.6
        start = end
    return out


def compare(stock, lap_stock, segments, grid, mass_delta, out_path):
    """Run the modified car, draw the comparison plot, return the table as lines."""
    mod, label = make_variant(stock, mass_delta)
    lap_mod = run_lap(mod, grid)
    res_a, res_b = _metrics(stock, lap_stock, segments), _metrics(mod, lap_mod, segments)

    lines = [f"Stock: {stock.mass:.0f} kg   Modified: {mod.mass:.0f} kg ({label})",
             "Assumption: weight distribution and CG height unchanged", "",
             f"{'Metric':<30}{'Stock':>10}{label:>10}{'Change':>10}", "-" * 60]
    for key in res_a:
        a, b = res_a[key], res_b[key]
        lines.append(f"{key:<30}{a:>10.2f}{b:>10.2f}{b - a:>+10.2f}")

    ta, tb = lap_stock.telemetry, lap_mod.telemetry
    s = ta.s
    delta = [b - a for a, b in zip(ta.t, tb.t)]   # same grid, so direct subtraction
    dv = [(b - a) * 3.6 for a, b in zip(ta.v, tb.v)]

    fig, (ax1, ax2, ax3) = plt.subplots(
        3, 1, figsize=(11, 9), sharex=True,
        gridspec_kw={"height_ratios": [3, 1.5, 1.5]}, layout="constrained")
    start = 0.0
    for seg in segments:
        end = start + seg.length
        if seg.is_corner:
            for ax in (ax1, ax2, ax3):
                ax.axvspan(start, end, color="0.92", zorder=0)
            ax1.text((start + end) / 2, 3, seg.text, ha="center", fontsize=8)
        start = end
    ax1.plot(s, [v * 3.6 for v in ta.v], color="0.35",
             label=f"Stock ({lap_stock.lap_time:.2f} s)")
    ax1.plot(s, [v * 3.6 for v in tb.v], color="tab:green",
             label=f"{label} ({lap_mod.lap_time:.2f} s)")
    ax1.set_ylabel("Speed (km/h)")
    ax1.set_title(f"Stock vs {label}: {lap_mod.lap_time - lap_stock.lap_time:+.2f} s per run")
    ax1.legend(loc="upper right")
    ax2.plot(s, delta, color="tab:green")
    ax2.fill_between(s, delta, 0, color="tab:green", alpha=0.25)
    ax2.axhline(0, color="black", linewidth=0.5)
    ax2.set_ylabel("Time delta (s)\n(below 0 = ahead)")
    ax3.plot(s, dv, color="tab:blue")
    ax3.axhline(0, color="black", linewidth=0.5)
    ax3.set_ylabel("Speed gain (km/h)")
    ax3.set_xlabel("Distance (m)")
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--mass", type=float, default=-100, help="mass change in kg")
    ap.add_argument("--track", default=str(DEFAULT_TRACK))
    args = ap.parse_args()
    stock, segments, grid, lap = load_run(Path(args.track))
    out = latest_path("compare.png")
    print("\n" + "\n".join(compare(stock, lap, segments, grid, args.mass, out)))
    print(f"\nSaved {out.relative_to(out.parents[2])}")


if __name__ == "__main__":
    main()
