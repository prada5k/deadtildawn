"""Shared setup for the tools: paths, loading a run, and summary text."""
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sim.car import load_car                      # noqa: E402
from sim.lap import run_lap                       # noqa: E402
from sim.track import discretize, load_track      # noqa: E402

CAR_FILE = ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json"
DEFAULT_TRACK = ROOT / "data" / "tracks" / "test_track.txt"
RUNS_DIR = ROOT / "runs"
LATEST_DIR = RUNS_DIR / "latest"   # standalone tools save here
DS = 0.1                           # m, lap solver step


def load_run(track_file, car=None):
    """Load the car and track and run one lap. Returns (car, segments, grid, lap)."""
    car = car or load_car(CAR_FILE)
    segments = load_track(track_file)
    grid = discretize(segments, DS)
    return car, segments, grid, run_lap(car, grid)


def latest_path(filename):
    LATEST_DIR.mkdir(parents=True, exist_ok=True)
    return LATEST_DIR / filename


def segment_lines(segments, tel):
    """Per-segment speed table as text lines."""
    lines = [f"{'Segment':<9}{'From':>7}{'To':>7}{'Entry':>8}{'Min':>8}{'Max':>8}  km/h"]
    start = 0.0
    for seg in segments:
        end = start + seg.length
        v = [vi * 3.6 for si, vi in zip(tel.s, tel.v) if start <= si <= end]
        lines.append(f"{seg.text:<9}{start:>7.0f}{end:>7.0f}{v[0]:>8.1f}"
                     f"{min(v):>8.1f}{max(v):>8.1f}")
        start = end
    return lines


def shift_lines(tel):
    lines = []
    for e in tel.shifts:
        kind = "up  " if e.to_gear > e.from_gear else "down"
        lines.append(f"{kind} {e.from_gear}->{e.to_gear} at {e.s:6.1f} m, "
                     f"{e.v * 3.6:5.1f} km/h, {e.rpm:5.0f} rpm")
    return lines
