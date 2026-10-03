"""Speed map: how a car drove the track, drawn on the track's shape.

Left map:  speed heatmap (0 km/h red -> top speed green), corners labeled
           with the car's minimum speed
Right map: driver inputs (full throttle, partial throttle, brake, shifting)

Standalone:  python tools/plot_speed_map.py [track_file]  -> runs/latest/speed_map.png
Used by run_all.py for the combined report.
"""
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt                    # noqa: E402
from matplotlib.collections import LineCollection  # noqa: E402
from matplotlib.lines import Line2D                # noqa: E402

from common import DEFAULT_TRACK, latest_path, load_run            # noqa: E402
from map_helpers import (SPEED_CMAP, draw_crossings, draw_markers,  # noqa: E402
                         frame, label_corners, segments_of)
from sim.track import find_crossings, track_xy                     # noqa: E402

INPUT_COLORS = {
    "full": "#2ca02c",      # full throttle
    "partial": "#e6b800",   # holding corner speed
    "brake": "#d62728",
    "shift": "#7f7f7f",
}


def input_state(throttle, brake, limit):
    if brake > 0:
        return "brake"
    if limit == "shift":
        return "shift"
    if throttle >= 0.999:
        return "full"
    return "partial"


def draw_speed_map(car, segments, lap, title, out_path):
    tel = lap.telemetry
    xs, ys, hs = track_xy(segments, tel.s)
    lines = segments_of(xs, ys)
    road_x, road_y = xs[::20], ys[::20]      # every ~2 m is plenty for label clearance
    crossings = find_crossings(segments)

    def min_speed_text(seg, start, end):
        v = min(vi for si, vi in zip(tel.s, tel.v) if start <= si <= end) * 3.6
        return f"{seg.text}\n{v:.0f} km/h"

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8), layout="constrained")

    speeds = [v * 3.6 for v in tel.v[:-1]]
    lc = LineCollection(lines, cmap=SPEED_CMAP, linewidths=6, capstyle="round")
    lc.set_array(speeds)
    lc.set_clim(0, max(speeds))
    ax1.add_collection(lc)
    fig.colorbar(lc, ax=ax1, shrink=0.75, label="Speed (km/h)")
    label_corners(ax1, segments, lambda sl: track_xy(segments, sl), road_x, road_y,
                  text_for=min_speed_text, style_for=lambda seg: ("white", "black"))
    draw_markers(ax1, xs, ys, hs)
    draw_crossings(ax1, crossings)
    ax1.set_title(f"Speed: {car.name}, {lap.lap_time:.2f} s")

    states = [input_state(th, br, lim)
              for th, br, lim in zip(tel.throttle, tel.brake, tel.limit)][:-1]
    ax2.add_collection(LineCollection(lines, colors=[INPUT_COLORS[st] for st in states],
                                      linewidths=6, capstyle="round"))
    draw_markers(ax2, xs, ys, hs)
    draw_crossings(ax2, crossings)
    ax2.legend(handles=[Line2D([0], [0], color=c, lw=5, label=lbl) for lbl, c in [
        ("Full throttle", INPUT_COLORS["full"]),
        ("Partial throttle (holding corner speed)", INPUT_COLORS["partial"]),
        ("Brake", INPUT_COLORS["brake"]),
        ("Shifting", INPUT_COLORS["shift"])]],
        loc="best", fontsize=8)
    ax2.set_title("Driver inputs")

    for ax in (ax1, ax2):
        frame(ax, xs, ys)
    fig.suptitle(f"{title}  ({sum(s.length for s in segments):.0f} m, standing start)",
                 fontsize=11)
    fig.savefig(out_path, dpi=120)
    plt.close(fig)


def main():
    track_file = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_TRACK
    car, segments, _, lap = load_run(track_file)
    out = latest_path("speed_map.png")
    draw_speed_map(car, segments, lap, track_file.name, out)
    print(f"Saved {out.relative_to(out.parents[2])}")


if __name__ == "__main__":
    main()
