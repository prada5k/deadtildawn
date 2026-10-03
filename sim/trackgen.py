"""Procedural touge generator.

generate(seed, style) -> GeneratedTrack with pace notes, e.g.
    "S 180, R3 85, S 60, L1 170, S 140, R6 40, ..."

Same seed + style = same road, every time. Layouts are built segment by
segment and REJECTED (then retried with the next attempt) unless the road is
buildable on flat ground:
  - it never crosses itself (sim.track.find_crossings)
  - stretches of road far apart along the track are never closer than
    MIN_CLEARANCE_M in space (two roads can't overlap without a bridge)
  - its length is inside the style's range

Styles shape the road's character with a few knobs (severity mix, corner
angles, straight lengths, how often the road turns back on itself). See
docs for the design; tune the STYLES table, not the code.
"""
import math
import random
from dataclasses import dataclass

from .track import find_crossings, parse_pace_notes, track_xy

MIN_CLEARANCE_M = 22.0     # two 8 m roads plus a gap
CLEARANCE_SKIP_M = 70.0    # ignore points this close ALONG the track (neighbors)
MAX_ATTEMPTS = 400

# Corner angle ranges (degrees) by severity band
ANGLES = {
    "hairpin": (120, 180),    # severity 1-2
    "mid": (45, 120),         # severity 3-6
    "fast": (15, 70),         # severity 7-10
}

STYLES = {
    # weights for severity 1..10; straights (min, max) m; length (min, max) m
    "technical": {
        "severity": [10, 9, 9, 8, 6, 4, 2, 1, 0, 0],
        "straight": (15, 70), "length": (900, 1500),
        "same_dir": 0.30,      # chance the next corner turns the same way as the last
        "linked": 0.45,        # chance two corners come back to back (no straight)
    },
    "balanced": {
        "severity": [4, 5, 7, 8, 8, 7, 5, 3, 1, 0],
        "straight": (30, 140), "length": (1100, 1900),
        "same_dir": 0.35, "linked": 0.30,
    },
    "flowing": {
        "severity": [1, 1, 2, 4, 6, 8, 9, 8, 5, 2],
        "straight": (50, 220), "length": (1400, 2400),
        "same_dir": 0.40, "linked": 0.25,
    },
}


@dataclass
class GeneratedTrack:
    seed: int
    style: str
    notes: str           # pace notes, ready for parse_pace_notes
    length: float        # m
    corners: int
    attempts: int        # layouts tried before one passed the checks


def angle_for(severity, rng):
    band = "hairpin" if severity <= 2 else ("mid" if severity <= 6 else "fast")
    lo, hi = ANGLES[band]
    return int(round(rng.uniform(lo, hi) / 5) * 5)


def _draft(rng, style):
    """One candidate layout as a list of pace-note tokens."""
    s = STYLES[style]
    target = rng.uniform(*s["length"])
    tokens = [f"S {rng.randint(120, 260)}"]            # starting straight
    length = 0.0
    direction = rng.choice("LR")
    from .track import severity_radius
    while length < target:
        sev = rng.choices(range(1, 11), weights=s["severity"])[0]
        ang = angle_for(sev, rng)
        if rng.random() > s["same_dir"]:
            direction = "R" if direction == "L" else "L"
        tokens.append(f"{direction}{sev} {ang}")
        length += severity_radius(sev) * math.radians(ang)
        if rng.random() > s["linked"]:
            st = rng.randint(*s["straight"])
            tokens.append(f"S {st}")
            length += st
    run = rng.randint(60, 160)                           # run to the finish line
    if tokens[-1].startswith("S "):                      # never two straights in a row
        tokens[-1] = f"S {int(tokens[-1][2:]) + run}"
    else:
        tokens.append(f"S {run}")
    return tokens


def min_clearance(segments, step=2.0, skip=CLEARANCE_SKIP_M):
    """Closest approach (m) between points more than `skip` m apart along the
    road. Uses a coarse grid so it stays fast on long tracks."""
    length = sum(seg.length for seg in segments)
    s = [i * step for i in range(int(length / step) + 1)]
    xs, ys, _ = track_xy(segments, s)
    cell = MIN_CLEARANCE_M * 2
    grid = {}
    best = math.inf
    for i, (x, y) in enumerate(zip(xs, ys)):
        cx, cy = int(x // cell), int(y // cell)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for j in grid.get((cx + dx, cy + dy), ()):
                    if s[i] - s[j] > skip:
                        best = min(best, math.hypot(x - xs[j], y - ys[j]))
        grid.setdefault((cx, cy), []).append(i)
    return best


def check(segments, style):
    """Why a layout is unbuildable, or "" if it's fine."""
    length = sum(seg.length for seg in segments)
    lo, hi = STYLES[style]["length"]
    if not lo <= length <= hi * 1.15:
        return f"length {length:.0f} m"
    if find_crossings(segments, step=2.0):
        return "crosses itself"
    if min_clearance(segments) < MIN_CLEARANCE_M:
        return "road passes too close to itself"
    return ""


def generate(seed, style="balanced"):
    if style not in STYLES:
        raise ValueError(f"unknown style {style!r}; choose from {sorted(STYLES)}")
    rng = random.Random(f"{style}:{seed}")
    for attempt in range(1, MAX_ATTEMPTS + 1):
        notes = ", ".join(_draft(rng, style))
        segments = parse_pace_notes(notes)
        if check(segments, style) == "":
            return GeneratedTrack(seed, style, notes, sum(sg.length for sg in segments),
                                  sum(sg.is_corner for sg in segments), attempt)
    raise RuntimeError(f"no buildable {style} track for seed {seed} in {MAX_ATTEMPTS} attempts")
