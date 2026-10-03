"""Generate procedural touge roads and draw a contact sheet.

    python tools/gen_tracks.py                         (4 of each style)
    python tools/gen_tracks.py --style technical --count 9 --seed 100

Saves each road's pace notes to data/tracks/generated/<style>_<seed>.txt
(usable anywhere a track file is: run_all, the viewer, the game) and a sheet
to runs/latest/generated_tracks.png.
"""
import argparse

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt                    # noqa: E402
from matplotlib.collections import LineCollection  # noqa: E402

from common import CAR_FILE, ROOT, latest_path      # noqa: E402
from map_helpers import segments_of, severity_color  # noqa: E402
from sim.car import load_car                        # noqa: E402
from sim.lap import run_lap                         # noqa: E402
from sim.track import discretize, parse_pace_notes, track_xy  # noqa: E402
from sim.trackgen import STYLES, generate           # noqa: E402

OUT_DIR = ROOT / "data" / "tracks" / "generated"


def draw(ax, segments, title):
    length = sum(sg.length for sg in segments)
    s = [i * 1.0 for i in range(int(length) + 1)]
    xs, ys, _ = track_xy(segments, s)
    colors, idx, end = [], 0, segments[0].length
    for si in s[:-1]:
        while si >= end and idx < len(segments) - 1:
            idx += 1
            end += segments[idx].length
        sg = segments[idx]
        colors.append(severity_color(sg.severity) if sg.is_corner else "0.45")
    ax.add_collection(LineCollection(segments_of(xs, ys), colors=colors, linewidths=3.5,
                                     capstyle="round"))
    ax.plot(xs[0], ys[0], "o", color="black", markersize=5)
    ax.plot(xs[-1], ys[-1], "s", color="black", markersize=5)
    pad = 40
    ax.set_xlim(min(xs) - pad, max(xs) + pad)
    ax.set_ylim(min(ys) - pad, max(ys) + pad)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_title(title, fontsize=9)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--style", choices=list(STYLES), default=None, help="default: every style")
    ap.add_argument("--count", type=int, default=4)
    ap.add_argument("--seed", type=int, default=0, help="first seed")
    args = ap.parse_args()
    styles = [args.style] if args.style else list(STYLES)

    car = load_car(CAR_FILE)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    fig, axes = plt.subplots(len(styles), args.count, figsize=(3.2 * args.count, 3.4 * len(styles)),
                             layout="constrained", squeeze=False)
    for r, style in enumerate(styles):
        for c in range(args.count):
            seed = args.seed + c
            g = generate(seed, style)
            (OUT_DIR / f"{style}_{seed}.txt").write_text(
                f"# Generated: style {style}, seed {seed} (sim/trackgen.py)\n{g.notes}\n", encoding="utf-8")
            segs = parse_pace_notes(g.notes)
            lap = run_lap(car, discretize(segs, 0.5)).lap_time
            draw(axes[r][c], segs, f"{style} #{seed}\n{g.length:.0f} m, {g.corners} corners, "
                                   f"stock {lap:.1f} s ({g.length / lap * 3.6:.0f} km/h)")
            print(f"{style:<10}#{seed:<4}{g.length:>6.0f} m  {g.corners:>2} corners  "
                  f"stock lap {lap:6.2f} s  tries {g.attempts}")
    out = latest_path("generated_tracks.png")
    fig.savefig(out, dpi=110)
    print(f"\nSaved {out.relative_to(ROOT)} and pace notes in {OUT_DIR.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
