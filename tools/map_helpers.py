"""Drawing helpers shared by the map tools (plot_track.py, plot_speed_map.py)."""
import colorsys
import math

import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap

SEVERITY_CMAP = plt.get_cmap("RdYlGn")


def hsl(h, s, l):
    """CSS hsl(h, s%, l%) -> matplotlib RGB tuple."""
    return colorsys.hls_to_rgb(h / 360, l / 100, s / 100)


# Speed gradient (CSS: linear-gradient(90deg, hsla(355,84%,55%) 0%,
#                  hsla(47,90%,73%) 50%, hsla(110,44%,58%) 100%))
SPEED_CMAP = LinearSegmentedColormap.from_list("speed", [
    (0.0, hsl(355, 84, 55)),   # red    #ED2C3C
    (0.5, hsl(47, 90, 73)),    # yellow #F8DE7E
    (1.0, hsl(110, 44, 58)),   # green  #74C365
])
LABEL_HALF_W, LABEL_HALF_H = 34.0, 15.0   # m, approximate label box size on the map
CLEARANCE = 8.0                           # m, gap between a label and the road
MAP_PAD = 70                              # m, room around the road for labels


def severity_color(sev):
    """Severity 1 (hairpin) = bright red ... 10 (kink) = green."""
    return SEVERITY_CMAP((sev - 1) / 9)


def segments_of(xs, ys):
    """Consecutive point pairs, for a LineCollection."""
    return [[(xs[i], ys[i]), (xs[i + 1], ys[i + 1])] for i in range(len(xs) - 1)]


def corner_spans(segments):
    """(start_m, end_m, segment) for every corner."""
    spans, start = [], 0.0
    for seg in segments:
        end = start + seg.length
        if seg.is_corner:
            spans.append((start, end, seg))
        start = end
    return spans


def _box_clear(cx, cy, road_x, road_y, placed):
    """True if a label centered at (cx, cy) touches neither the road nor another label."""
    hw, hh = LABEL_HALF_W + CLEARANCE, LABEL_HALF_H + CLEARANCE
    for x, y in zip(road_x, road_y):
        if abs(x - cx) < hw and abs(y - cy) < hh:
            return False
    for px, py in placed:
        if abs(px - cx) < 2 * LABEL_HALF_W + 4 and abs(py - cy) < 2 * LABEL_HALF_H + 4:
            return False
    return True


def place_label(x, y, outward_angle, road_x, road_y, placed):
    """Search outward from a corner for a spot clear of the road and other
    labels: try the outside of the turn first, then swing around."""
    for dist in (45, 60, 80, 100, 125, 150):
        for swing in (0, 25, -25, 50, -50, 75, -75, 100, -100, 130, -130, 180):
            ang = outward_angle + math.radians(swing)
            cx, cy = x + dist * math.cos(ang), y + dist * math.sin(ang)
            if _box_clear(cx, cy, road_x, road_y, placed):
                return cx, cy
    return x + 60 * math.cos(outward_angle), y + 60 * math.sin(outward_angle)


def label_corners(ax, segments, xy_at, road_x, road_y, text_for, style_for):
    """Label every corner with a leader line, avoiding the road and each other.

    xy_at(s_list) -> (xs, ys, headings); text_for(seg, start, end) -> str;
    style_for(seg) -> (box_face_color, text_color).
    """
    placed = []
    for start, end, seg in corner_spans(segments):
        (x,), (y,), (h,) = xy_at([(start + end) / 2])
        outward = 1 if seg.direction == "L" else -1   # outside of the turn
        out_ang = math.atan2(-math.cos(h) * outward, math.sin(h) * outward)
        cx, cy = place_label(x, y, out_ang, road_x, road_y, placed)
        placed.append((cx, cy))
        face, text_color = style_for(seg)
        ax.annotate(text_for(seg, start, end), (x, y), xytext=(cx, cy),
                    fontsize=8, ha="center", va="center", color=text_color,
                    fontweight="bold",
                    bbox=dict(boxstyle="round,pad=0.3", fc=face, ec="0.3", lw=0.6),
                    arrowprops=dict(arrowstyle="-", color="0.3", lw=0.8,
                                    shrinkA=0, shrinkB=4))


def draw_markers(ax, xs, ys, hs):
    ax.plot(xs[0], ys[0], "o", color="black", markersize=9, zorder=5)
    ax.annotate("START", (xs[0], ys[0]), textcoords="offset points",
                xytext=(-10, 10), fontsize=8, fontweight="bold")
    ax.plot(xs[-1], ys[-1], "s", color="black", markersize=9, zorder=5)
    ax.annotate("FINISH", (xs[-1], ys[-1]), textcoords="offset points",
                xytext=(6, -14), fontsize=8, fontweight="bold")
    i = min(300, len(xs) - 2)
    ax.annotate("", xy=(xs[i] + 15 * math.cos(hs[i]), ys[i] + 15 * math.sin(hs[i])),
                xytext=(xs[i], ys[i]),
                arrowprops=dict(arrowstyle="->", lw=1.5, color="black"))


def draw_crossings(ax, crossings):
    for x, y, _, _ in crossings:
        ax.plot(x, y, "x", color="magenta", markersize=16, mew=3, zorder=6)
        ax.annotate("crossing", (x, y), textcoords="offset points", xytext=(10, -4),
                    color="magenta", fontsize=8, fontweight="bold")


def frame(ax, xs, ys):
    ax.set_xlim(min(xs) - MAP_PAD, max(xs) + MAP_PAD)
    ax.set_ylim(min(ys) - MAP_PAD, max(ys) + MAP_PAD)
    ax.set_aspect("equal")
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.grid(True, color="0.92")
