"""Driver meeting: run every push level many times and show the odds.

    python tools/driver_study.py                          (test track, 200 runs each)
    python tools/driver_study.py --rival 49.55            (win odds vs a rival time)
    python tools/driver_study.py --track data/tracks/switchbacks.txt --runs 100

Monte Carlo uses a coarser step (0.5 m) for speed: it shifts every time by
about the same small amount, so comparisons between push levels still hold.
Saves runs/latest/driver_study.png.
"""
import argparse
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

from common import CAR_FILE, DEFAULT_TRACK, ROOT, latest_path   # noqa: E402
from sim.car import load_car                                    # noqa: E402
from sim.driver import PUSH_LEVELS, Driver                      # noqa: E402
from sim.montecarlo import run_many                             # noqa: E402
from sim.track import discretize, load_track                    # noqa: E402

MC_DS = 0.5
COLORS = {"safe": "#74C365", "normal": "#4C9BE8", "hard": "#F2A541", "flat_out": "#ED2C3C"}


def study(car, track_file, runs, rival=None, out_path=None):
    grid = discretize(load_track(track_file), MC_DS)
    dists = [run_many(car, grid, Driver(push=p), runs) for p in PUSH_LEVELS]

    lines = [f"{runs} runs per push level on {Path(track_file).name} "
             f"(driver sigma {Driver().sigma}, step {MC_DS} m)", "",
             f"{'Push':<10}{'f':>7}{'Mean':>9}{'Spread':>8}{'Best':>9}{'Worst':>9}"
             f"{'Mistake runs':>14}" + (f"{'Win vs ' + format(rival, '.2f'):>14}" if rival else ""),
             "-" * (66 + (14 if rival else 0))]
    for d in dists:
        row = (f"{d.push:<10}{PUSH_LEVELS[d.push]:>7.3f}{d.mean:>9.2f}{d.stdev:>8.2f}"
               f"{min(d.times):>9.2f}{max(d.times):>9.2f}{d.mistake_rate * 100:>13.0f}%")
        if rival:
            row += f"{d.win_probability(rival) * 100:>13.0f}%"
        lines.append(row)
    if rival:
        best = max(dists, key=lambda d: d.win_probability(rival))
        lines += ["", f"Best odds vs {rival:.2f} s: {best.push} "
                      f"({best.win_probability(rival) * 100:.0f}%)"]

    if out_path:
        fig, ax = plt.subplots(figsize=(10, 5.5), layout="constrained")
        lo = min(min(d.times) for d in dists)
        hi = max(max(d.times) for d in dists)
        bins = [lo + (hi - lo) * i / 40 for i in range(41)]
        for d in dists:
            ax.hist(d.times, bins=bins, alpha=0.55, color=COLORS[d.push],
                    label=f"{d.push}: mean {d.mean:.2f} s, mistakes {d.mistake_rate * 100:.0f}%")
        if rival:
            ax.axvline(rival, color="black", linestyle="--", label=f"Rival {rival:.2f} s")
        ax.set_xlabel("Run time (s)")
        ax.set_ylabel("Runs")
        ax.set_title(f"{car.name}: push level vs run time ({Path(track_file).name})")
        ax.legend(fontsize=8)
        fig.savefig(out_path, dpi=120)
        plt.close(fig)
    return lines


def main():
    ap = argparse.ArgumentParser(description="Push level odds (Monte Carlo).")
    ap.add_argument("--track", default=str(DEFAULT_TRACK))
    ap.add_argument("--runs", type=int, default=200)
    ap.add_argument("--rival", type=float, default=None, help="rival time to beat (s)")
    args = ap.parse_args()
    out = latest_path("driver_study.png")
    print("\n" + "\n".join(study(load_car(CAR_FILE), args.track, args.runs, args.rival, out)))
    print(f"\nSaved {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
