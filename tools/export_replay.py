"""Export a lap as replay.json for the Godot viewer.

The JSON file is the contract between the Python sim and the Godot viewer.
Bump REPLAY_VERSION whenever the format changes, so the viewer can refuse
files it doesn't understand instead of misreading them.

Standalone:  python tools/export_replay.py [track_file]
             -> godot/replays/latest.json (open the godot/ project to watch)
Used by run_all.py (also saved in each run folder).

Adding optional fields (like "driver") keeps older viewers working, so it
doesn't need a version bump; removing or renaming fields does.

Coordinates are the sim's: meters, x east, y north, heading in radians
counter-clockwise from east. Godot's 2D y axis points down; the viewer flips it.
"""
import json
import math
import sys
from pathlib import Path

from common import DEFAULT_TRACK, ROOT, load_run   # noqa: E402
from sim.track import track_xy                     # noqa: E402

REPLAY_FORMAT = "deadtildawn-replay"
REPLAY_VERSION = 1
SAMPLE_STEP = 0.5        # m between telemetry samples (Godot interpolates between them)
TRACK_POINT_STEP = 1.0   # m between road outline points
GODOT_REPLAY = ROOT / "godot" / "replays" / "latest.json"


def _r(x, nd=3):
    return round(x, nd)


def _pose_samples(segments, lap):
    """Downsampled (t, s, x, y, heading) for a ghost car (s: distance along the
    road, for the viewer's gap tower)."""
    tel = lap.telemetry
    every = max(1, round(SAMPLE_STEP / (tel.s[1] - tel.s[0])))
    idx = list(range(0, len(tel.s), every))
    if idx[-1] != len(tel.s) - 1:
        idx.append(len(tel.s) - 1)
    xs, ys, hs = track_xy(segments, [tel.s[i] for i in idx])
    return {"t": [_r(tel.t[i]) for i in idx], "s": [_r(tel.s[i], 2) for i in idx],
            "x": [_r(x, 2) for x in xs],
            "y": [_r(y, 2) for y in ys], "heading": [_r(h, 4) for h in hs]}


def build_replay(car, segments, lap, track_name, ghost=None, location=None):
    """ghost (optional): {"name", "car", "lap"}: the opponent, drawn as a ghost
    car. location (optional): "coast" | "canyon" | "mountain", the place the
    viewer dresses the road as. Optional fields (ghost, dnf, location) keep
    older viewers working."""
    tel = lap.telemetry
    length = sum(seg.length for seg in segments)

    # Road centerline
    s_road = [i * TRACK_POINT_STEP for i in range(int(length / TRACK_POINT_STEP) + 1)] + [length]
    rx, ry, _ = track_xy(segments, s_road)

    # Corners (for labels and trackside cameras)
    corners, start = [], 0.0
    for seg in segments:
        end = start + seg.length
        if seg.is_corner:
            (mx,), (my,), (mh,) = track_xy(segments, [(start + end) / 2])
            out = 1 if seg.direction == "L" else -1          # outside of the turn
            corners.append({
                "text": seg.text, "severity": seg.severity, "direction": seg.direction,
                "radius": _r(seg.radius, 1), "angle_deg": seg.angle_deg,
                "s_start": _r(start, 1), "s_end": _r(end, 1),
                "mid": [_r(mx, 2), _r(my, 2)],
                "outward": [_r(math.sin(mh) * out, 4), _r(-math.cos(mh) * out, 4)],
            })
        start = end

    # Telemetry, downsampled (keep the final sample)
    every = max(1, round(SAMPLE_STEP / (tel.s[1] - tel.s[0])))
    idx = list(range(0, len(tel.s), every))
    if idx[-1] != len(tel.s) - 1:
        idx.append(len(tel.s) - 1)
    xs, ys, hs = track_xy(segments, [tel.s[i] for i in idx])

    samples = {
        "t": [_r(tel.t[i]) for i in idx],
        "s": [_r(tel.s[i], 2) for i in idx],
        "x": [_r(x, 2) for x in xs],
        "y": [_r(y, 2) for y in ys],
        "heading": [_r(h, 4) for h in hs],
        "v": [_r(tel.v[i]) for i in idx],
        "gear": [tel.gear[i] for i in idx],
        "rpm": [round(tel.rpm[i]) for i in idx],
        "throttle": [_r(tel.throttle[i]) for i in idx],
        "brake": [_r(tel.brake[i]) for i in idx],
        "brake_temp": [_r(tel.brake_temp[i], 1) for i in idx],
    }

    return {
        "format": REPLAY_FORMAT,
        "version": REPLAY_VERSION,
        "units": {"distance": "m", "speed": "m/s", "time": "s", "angle": "rad",
                  "temperature": "C"},
        "car": {"name": car.name, "mass": car.mass, "redline": car.redline,
                "fuel_cut": car.fuel_cut, "pad_fade_temp": car.pad_fade_temp},
        "track": {"name": track_name, "length": _r(length, 1),
                  "notes": ", ".join(seg.text for seg in segments),
                  "centerline": [[_r(x, 2), _r(y, 2)] for x, y in zip(rx, ry)],
                  "corners": corners},
        "lap_time": _r(lap.lap_time),
        "dnf": getattr(lap, "dnf", False),
        "crash_corner": getattr(lap, "crash_corner", ""),
        "location": location,
        "ghost": None if ghost is None else {
            "name": ghost["name"], "car": ghost["car"], "lap_time": _r(ghost["lap"].lap_time),
            "dnf": ghost["lap"].dnf, "crash_corner": ghost["lap"].crash_corner,
            "samples": _pose_samples(segments, ghost["lap"])},
        "driver": None if lap.driver is None else {
            "name": lap.driver.name, "push": lap.driver.push, "sigma": lap.driver.sigma,
            "f": _r(lap.driver.f, 4), "seed": lap.seed,
            "corners": [{"text": c.text, "attempt": _r(c.attempt, 4), "mistake": c.mistake,
                         "crash": getattr(c, "crash", False),
                         "s_start": _r(c.s_start, 1), "s_end": _r(c.s_end, 1)}
                        for c in lap.corner_log]},
        "samples": samples,
    }


def write_replay(car, segments, lap, track_name, out_path, copy_to_godot=True):
    """Write replay.json; also copy it to the Godot project if it exists."""
    text = json.dumps(build_replay(car, segments, lap, track_name), separators=(",", ":"))
    Path(out_path).write_text(text, encoding="utf-8")
    if copy_to_godot and GODOT_REPLAY.parent.parent.exists():
        GODOT_REPLAY.parent.mkdir(exist_ok=True)
        GODOT_REPLAY.write_text(text, encoding="utf-8")
        return True
    return False


def main():
    track_file = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_TRACK
    car, segments, _, lap = load_run(track_file)
    GODOT_REPLAY.parent.mkdir(parents=True, exist_ok=True)
    write_replay(car, segments, lap, track_file.name, GODOT_REPLAY, copy_to_godot=False)
    print(f"Saved {GODOT_REPLAY.relative_to(ROOT)} ({GODOT_REPLAY.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
