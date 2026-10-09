"""Tracks: strict pace-note parser, severity scale, and discretization.

Format (PHYSICS.md 2):  "S 200, R7 65, S 40, L6 25"
  S <length_m>                  straight
  <L|R><severity 1-10> <deg>    corner

Strict on purpose: a typo like "R13" or "S20" raises an error naming the
segment, instead of being silently misread.
"""
import math
import re
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

from .elevation import ElevationProfile

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
class ElevatedCourse:
    road_id: str
    geometry_version: int
    segments: tuple
    elevation: ElevationProfile
    geometry_sha256: str

    def snapshot(self):
        return {"road_id": self.road_id, "geometry_version": self.geometry_version,
                "geometry_sha256": self.geometry_sha256}


def load_elevated_course(path):
    """Load a versioned elevation fixture without changing legacy pace-note files."""
    path = Path(path)
    raw = path.read_bytes()
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("elevated course must be a JSON object")
    if data.get("geometry_version") != 2 or not isinstance(data.get("road_id"), str) or not data["road_id"]:
        raise ValueError("elevated course needs a road ID and geometry_version 2")
    if data.get("distance_axis") != "horizontal_centerline_m" or data.get("interpolation") != "clamped_cubic_spline_c2":
        raise ValueError("unsupported elevated-course distance axis or interpolation")
    base_name = data.get("base_track")
    if not isinstance(base_name, str) or Path(base_name).name != base_name:
        raise ValueError("base_track must be a neighboring pace-note filename")
    base_path = path.parent / base_name
    base_bytes = base_path.read_bytes()
    if hashlib.sha256(base_bytes).hexdigest() != data.get("base_track_sha256"):
        raise ValueError("base track hash differs from elevated course declaration")
    segments = tuple(load_track(base_path))
    length = sum(seg.length for seg in segments)
    if "elevation_samples" not in data:
        raise ValueError("elevated course lacks elevation_samples")
    profile = ElevationProfile(data["elevation_samples"],
                               data.get("start_grade", 0.0), data.get("end_grade", 0.0))
    if not math.isclose(profile.length, length, abs_tol=1e-6, rel_tol=0):
        raise ValueError("elevation must end at the horizontal course length")
    digest = hashlib.sha256(base_bytes + b"\0" + raw).hexdigest()
    return ElevatedCourse(data["road_id"], 2, segments, profile, digest)


@dataclass(frozen=True)
class TrackGrid:
    s: tuple            # m, horizontal plan-view positions (uniform except last step)
    curvature: tuple    # horizontal yaw curvature, 1/m; 0 on straights
    length: float       # horizontal plan-view length, m
    corner_id: tuple = ()   # index into `corners` at each node, -1 on straights
    corners: tuple = ()     # (pace-note text, s_start, s_end) per corner
    path_s: tuple = ()      # 3D traveled distance at each horizontal-distance node
    elevation: ElevationProfile | None = None


def discretize(segments, ds, elevation=None):
    """Nodes every ds meters. A node on a straight/corner boundary takes the
    corner's curvature (conservative: the car must already be at corner speed)."""
    length = sum(seg.length for seg in segments)
    n = math.ceil(length / ds - 1e-9)
    s = [min(i * ds, length) for i in range(n + 1)]
    curv = [0.0] * len(s)
    cid = [-1] * len(s)
    corners = []

    start = 0.0
    for seg in segments:
        end = start + seg.length
        if seg.is_corner:
            k = 1.0 / seg.radius
            for i, si in enumerate(s):
                if start - 1e-9 <= si <= end + 1e-9:
                    if k >= curv[i]:
                        curv[i], cid[i] = k, len(corners)
            corners.append((seg.text, start, end))
        start = end
    if elevation is not None:
        if not math.isclose(elevation.length, length, abs_tol=1e-6, rel_tol=0):
            raise ValueError("elevation and horizontal track lengths differ")
        path_s = [0.0]
        for a, b in zip(s, s[1:]):
            path_s.append(path_s[-1] + elevation.path_length(a, b))
        return TrackGrid(tuple(s), tuple(curv), length, tuple(cid), tuple(corners),
                         tuple(path_s), elevation)
    return TrackGrid(tuple(s), tuple(curv), length, tuple(cid), tuple(corners))


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
