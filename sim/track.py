"""Tracks: strict pace-note parser, severity scale, and discretization.

Format (PHYSICS.md 2):  "S 200, R7 65, S 40, L6 25"
  S <length_m>                  straight
  <L|R><severity 1-10> <deg>    corner

Strict on purpose: a typo like "R13" or "S20" raises an error naming the
segment, instead of being silently misread.
"""
import math
import re
from dataclasses import dataclass
from pathlib import Path

R_MIN = 15.0    # m, severity 1
R_MAX = 500.0   # m, severity 10

_STRAIGHT = re.compile(r"S (\d+(?:\.\d+)?)")
_CORNER = re.compile(r"([LR])(10|[1-9]) (\d+(?:\.\d+)?)")
_FORMAT_HELP = ("Expected 'S <length_m>' (e.g. 'S 200') or "
                "'<L|R><severity 1-10> <angle_deg>' (e.g. 'R3 90').")


def severity_radius(n):
    """Geometric scale: R_n = 15 * (500/15)^((n-1)/9)."""
    if not 1 <= n <= 10:
        raise ValueError(f"severity must be 1-10, got {n}")
    return R_MIN * (R_MAX / R_MIN) ** ((n - 1) / 9)


@dataclass(frozen=True)
class Segment:
    text: str
    length: float                 # m
    radius: float | None = None   # m, None for straights
    severity: int | None = None
    angle_deg: float | None = None
    direction: str | None = None  # "L" or "R"

    @property
    def is_corner(self):
        return self.radius is not None


def parse_pace_notes(text):
    """Parse a pace-note string into a list of Segments (strict)."""
    tokens = [tok.strip() for tok in text.split(",")]
    segments = []
    for i, tok in enumerate(tokens, start=1):
        if not tok:
            raise ValueError(f"Segment {i} is empty (stray comma?). {_FORMAT_HELP}")

        m = _STRAIGHT.fullmatch(tok)
        if m:
            length = float(m.group(1))
            if length <= 0:
                raise ValueError(f"Segment {i} '{tok}': length must be > 0")
            segments.append(Segment(tok, length))
            continue

        m = _CORNER.fullmatch(tok)
        if m:
            direction, sev, angle = m.group(1), int(m.group(2)), float(m.group(3))
            if not 0 < angle <= 360:
                raise ValueError(f"Segment {i} '{tok}': angle must be in (0, 360]")
            radius = severity_radius(sev)
            segments.append(Segment(tok, radius * math.radians(angle), radius,
                                    sev, angle, direction))
            continue

        raise ValueError(f"Segment {i} '{tok}' is not valid. {_FORMAT_HELP}")
    return segments


def load_track(path):
    """Read a track file. Lines starting with # are comments; pace notes may
    span several lines (end each line with a comma)."""
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    text = " ".join(ln.strip() for ln in lines
                    if ln.strip() and not ln.strip().startswith("#"))
    return parse_pace_notes(text)


@dataclass(frozen=True)
class TrackGrid:
    s: tuple            # m, node positions (uniform except possibly the last step)
    curvature: tuple    # 1/m at each node, 0 on straights
    length: float       # m


def discretize(segments, ds):
    """Nodes every ds meters. A node on a straight/corner boundary takes the
    corner's curvature (conservative: the car must already be at corner speed)."""
    length = sum(seg.length for seg in segments)
    n = math.ceil(length / ds - 1e-9)
    s = [min(i * ds, length) for i in range(n + 1)]
    curv = [0.0] * len(s)

    start = 0.0
    for seg in segments:
        end = start + seg.length
        if seg.is_corner:
            k = 1.0 / seg.radius
            for i, si in enumerate(s):
                if start - 1e-9 <= si <= end + 1e-9:
                    curv[i] = max(curv[i], k)
        start = end
    return TrackGrid(tuple(s), tuple(curv), length)


def track_xy(segments, s_values):
    """2D coordinates [m] of points at distances s_values along the track.

    Starts at the origin heading east (+x). A left turn rotates the heading
    counter-clockwise. Inside a corner of radius R, heading changes at rate
    kappa = +/-1/R per meter, and the position follows the exact arc:

        x = x0 + (sin(h0 + kappa*d) - sin(h0)) / kappa
        y = y0 - (cos(h0 + kappa*d) - cos(h0)) / kappa

    Returns (xs, ys, headings_rad). Used for track maps now, Godot later.
    """
    # Position and heading at the start of every segment
    starts = []
    x = y = h = 0.0
    s0 = 0.0
    for seg in segments:
        starts.append((s0, x, y, h))
        x, y, h = _point_in_segment(seg, x, y, h, seg.length)
        s0 += seg.length

    xs, ys, hs = [], [], []
    idx = 0
    for s in s_values:
        while idx < len(segments) - 1 and s > starts[idx][0] + segments[idx].length:
            idx += 1
        seg_s0, x0, y0, h0 = starts[idx]
        d = min(max(s - seg_s0, 0.0), segments[idx].length)
        px, py, ph = _point_in_segment(segments[idx], x0, y0, h0, d)
        xs.append(px)
        ys.append(py)
        hs.append(ph)
    return xs, ys, hs


def _point_in_segment(seg, x0, y0, h0, d):
    """Point a distance d into a segment that starts at (x0, y0) heading h0."""
    if not seg.is_corner:
        return x0 + d * math.cos(h0), y0 + d * math.sin(h0), h0
    kappa = (1.0 if seg.direction == "L" else -1.0) / seg.radius
    h = h0 + kappa * d
    return (x0 + (math.sin(h) - math.sin(h0)) / kappa,
            y0 - (math.cos(h) - math.cos(h0)) / kappa,
            h)


def find_crossings(segments, step=1.0, gap=30.0):
    """Points where the road crosses itself, as [(x, y, s_a, s_b), ...].

    Samples the centerline every `step` meters and tests every pair of short
    chords for intersection. Chords closer than `gap` meters apart along the
    track are skipped (neighbors always touch). Not every valid pace-note
    string is a buildable flat road; a crossing needs a bridge.
    """
    length = sum(seg.length for seg in segments)
    n = int(length / step)
    s = [i * step for i in range(n + 1)] + ([length] if n * step < length else [])
    xs, ys, _ = track_xy(segments, s)

    found = []
    for i in range(len(s) - 1):
        for j in range(i + 1, len(s) - 1):
            if s[j] - s[i] < gap:
                continue
            hit = _chord_intersection(xs[i], ys[i], xs[i + 1], ys[i + 1],
                                      xs[j], ys[j], xs[j + 1], ys[j + 1])
            if hit:
                if not found or math.hypot(hit[0] - found[-1][0], hit[1] - found[-1][1]) > step:
                    found.append((hit[0], hit[1], s[i], s[j]))
    return found


def _chord_intersection(x1, y1, x2, y2, x3, y3, x4, y4):
    """Intersection point of segments (1-2) and (3-4), or None."""
    den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if abs(den) < 1e-12:
        return None
    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
    u = ((x1 - x3) * (y1 - y2) - (y1 - y3) * (x1 - x2)) / den
    if 0 <= t <= 1 and 0 <= u <= 1:
        return x1 + t * (x2 - x1), y1 + t * (y2 - y1)
    return None
