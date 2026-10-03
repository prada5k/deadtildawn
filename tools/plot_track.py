"""Track map: the road itself, from its pace notes. No car involved.

Corners are colored by severity (1 = bright red hairpin ... 10 = green kink),
straights are gray. Labels show each corner's pace note and radius.

Standalone:  python tools/plot_track.py [track_file]  -> runs/latest/track_layout.png
Used by run_all.py for the combined report.
"""
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt                    # noqa: E402
from matplotlib.cm import ScalarMappable           # noqa: E402
from matplotlib.collections import LineCollection  # noqa: E402
from matplotlib.colors import BoundaryNorm         # noqa: E402

from common import DEFAULT_TRACK, latest_path                          # noqa: E402
from map_helpers import (SEVERITY_CMAP, draw_crossings, draw_markers,  # noqa: E402
                         frame, label_corners, segments_of, severity_color)
from sim.track import find_crossings, load_track, track_xy             # noqa: E402

STEP = 0.5            # m between drawn points
STRAIGHT_COLOR = "0.45"


def draw_layout(segments, title, out_path):
    """Draw the track layout. Returns the list of crossings found."""
    length = sum(seg.length for seg in segments)
    s = [i * STEP for i in range(int(length / STEP) + 1)] + [length]
    xs, ys, hs = track_xy(segments, s)

    colors, idx, seg_end = [], 0, segments[0].length
    for si in s[:-1]:
        while si >= seg_end and idx < len(segments) - 1:
            idx += 1
            seg_end += segments[idx].length
        seg = segments[idx]
        colors.append(severity_color(seg.severity) if seg.is_corner else STRAIGHT_COLOR)

    fig, ax = plt.subplots(figsize=(10, 8), layout="constrained")
    ax.add_collection(LineCollection(segments_of(xs, ys), colors=colors,
                                     linewidths=7, capstyle="round"))
    label_corners(
        ax, segments, lambda sl: track_xy(segments, sl), xs, ys,
        text_for=lambda seg, a, b: f"{seg.text}\nR = {seg.radius:.0f} m",
        style_for=lambda seg: (severity_color(seg.severity),
                               "white" if seg.severity <= 2 or seg.severity >= 9 else "black"))
    draw_markers(ax, xs, ys, hs)
    crossings = find_crossings(segments)
    draw_crossings(ax, crossings)

    norm = BoundaryNorm([i + 0.5 for i in range(0, 11)], SEVERITY_CMAP.N)
    cbar = fig.colorbar(ScalarMappable(norm=norm, cmap=SEVERITY_CMAP), ax=ax,
                        shrink=0.7, ticks=range(1, 11))
    cbar.set_label("Corner severity (1 = hairpin, 10 = kink)")

    n_corners = sum(seg.is_corner for seg in segments)
    ax.set_title(f"{title}: {length:.0f} m, {n_corners} corners")
    frame(ax, xs, ys)
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    return crossings


def crossing_lines(crossings):
    return [f"WARNING: road crosses itself at ({x:.0f}, {y:.0f}) m "
            f"(track positions {a:.0f} m and {b:.0f} m); needs a bridge"
            for x, y, a, b in crossings]


def main():
    track_file = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_TRACK
    out = latest_path("track_layout.png")
    crossings = draw_layout(load_track(track_file), track_file.name, out)
    for line in crossing_lines(crossings):
        print(line)
    print(f"Saved {out.relative_to(out.parents[2])}")


if __name__ == "__main__":
    main()
