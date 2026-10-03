"""Run everything for one track and save a combined report.

    python tools/run_all.py                                  (default test track)
    python tools/run_all.py --track data/tracks/my_track.txt
    python tools/run_all.py --mass -100                      (adds a comparison)
    python tools/run_all.py --runs 5                         (back-to-back runs, brakes stay hot)

Creates runs/<track name>/<date_time>/ containing:
    summary.txt         everything printed below, plus the inputs used
    track_layout.png    the road and corner severities (no car)
    lap_telemetry.png   speed, rpm/gear, pedals, g vs distance
    speed_map.png       speed heatmap + driver inputs on the track shape
    fade_test.png       ten 60-0 stops back to back (car only)
    replay.json         for the Godot viewer (also copied to godot/replays/latest.json)
    compare.png         only with --mass
"""
import argparse
from datetime import datetime
from pathlib import Path

from common import (CAR_FILE, DEFAULT_TRACK, DS, ROOT, RUNS_DIR, load_run,  # noqa: E402
                    segment_lines, shift_lines)
from compare import compare                                                  # noqa: E402
from export_replay import write_replay                                       # noqa: E402
from fade_test import fade_test                                              # noqa: E402
from plot_lap import draw_lap                                                # noqa: E402
from plot_speed_map import draw_speed_map                                    # noqa: E402
from plot_track import crossing_lines, draw_layout                           # noqa: E402
from validate_straight import validation_lines                               # noqa: E402


def section(title):
    return ["", f"== {title} " + "=" * max(0, 60 - len(title)), ""]


def back_to_back_lines(car, grid, n):
    """n runs in a row with no cool-down: rotors start each run as hot as the
    last one ended."""
    from sim.lap import run_lap
    from sim.units import AMBIENT_C
    lines = [f"{n} runs in a row, no cool-down between runs", "",
             f"{'Run':<5}{'Lap s':>9}{'Rotor start C':>15}{'Peak C':>9}{'End C':>9}", "-" * 47]
    temp = AMBIENT_C
    for i in range(1, n + 1):
        lap = run_lap(car, grid, temp_start=temp)
        lines.append(f"{i:<5}{lap.lap_time:>9.2f}{temp:>15.0f}"
                     f"{max(lap.telemetry.brake_temp):>9.0f}{lap.temp_end:>9.0f}")
        temp = lap.temp_end
    return lines


def run_all(track_file, mass_delta=None, runs_dir=RUNS_DIR, stamp=None, runs=1,
            copy_to_godot=True):
    """Run every tool on one track. Returns (output_dir, summary_lines)."""
    track_file = Path(track_file)
    stamp = stamp or datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    out_dir = Path(runs_dir) / track_file.stem / stamp
    out_dir.mkdir(parents=True, exist_ok=True)

    car, segments, grid, lap = load_run(track_file)
    length = sum(seg.length for seg in segments)
    n_corners = sum(seg.is_corner for seg in segments)
    notes = ", ".join(seg.text for seg in segments)

    crossings = draw_layout(segments, track_file.name, out_dir / "track_layout.png")
    draw_lap(car, segments, lap, out_dir / "lap_telemetry.png")
    draw_speed_map(car, segments, lap, track_file.name, out_dir / "speed_map.png")

    def rel(p):
        p = Path(p).resolve()
        return p.relative_to(ROOT) if p.is_relative_to(ROOT) else p

    lines = [
        "deadtildawn run summary",
        f"Run:     {stamp}",
        f"Car:     {car.name}, {car.mass:.0f} kg  [{rel(CAR_FILE)}]",
        f"Track:   {track_file.name}, {length:.0f} m, {n_corners} corners, standing start"
        f"  [{rel(track_file)}]",
        f"Notes:   {notes}",
        f"Solver:  QSS point mass, ds = {DS} m",
    ]
    lines += crossing_lines(crossings) or ["Layout:  no crossings"]

    lines += section("Lap")
    lines.append(f"Lap time: {lap.lap_time:.2f} s  "
                 f"(average {length / lap.lap_time * 3.6:.1f} km/h)")
    lines.append("")
    lines += segment_lines(segments, lap.telemetry)
    lines += ["", "Shifts:"] + ["  " + ln for ln in shift_lines(lap.telemetry)]
    lines += ["", f"Front rotor: start {lap.telemetry.brake_temp[0]:.0f} C, "
                  f"peak {max(lap.telemetry.brake_temp):.0f} C, end {lap.temp_end:.0f} C "
                  f"(fade onset {car.pad_fade_temp:.0f} C); "
                  f"converged in {lap.iterations} passes"]
    if runs > 1:
        lines += section("Back-to-back runs")
        lines += back_to_back_lines(car, grid, runs)

    lines += section("Validation (car only, track-independent)")
    val_lines, all_pass = validation_lines(car)
    lines += val_lines
    lines += ["", f"All graded targets: {'PASS' if all_pass else 'FAIL'}"]

    lines += section("Brake fade test (car only, track-independent)")
    lines += fade_test(car, out_dir / "fade_test.png")

    copied = write_replay(car, segments, lap, track_file.name, out_dir / "replay.json",
                          copy_to_godot=copy_to_godot)
    files = ["track_layout.png", "lap_telemetry.png", "speed_map.png", "fade_test.png",
             "replay.json" + ("  (copied to godot/replays/latest.json)" if copied else "")]
    if mass_delta is not None:
        lines += section(f"Comparison ({mass_delta:+.0f} kg)")
        lines += compare(car, lap, segments, grid, mass_delta, out_dir / "compare.png")
        files.append("compare.png")

    lines += section("Files")
    lines += [f"  {f}" for f in files + ["summary.txt"]]
    lines.append(f"Saved in: {rel(out_dir)}")

    (out_dir / "summary.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out_dir, lines


def main():
    ap = argparse.ArgumentParser(description="Run everything for one track.")
    ap.add_argument("--track", default=str(DEFAULT_TRACK), help="pace-note track file")
    ap.add_argument("--mass", type=float, default=None,
                    help="also compare against a car with this mass change (kg)")
    ap.add_argument("--runs", type=int, default=1,
                    help="also run this many back-to-back runs (brakes stay hot)")
    args = ap.parse_args()
    track = Path(args.track)
    if not track.exists():
        available = sorted(p.name for p in (ROOT / "data" / "tracks").glob("*.txt"))
        print(f"Track file not found: {track}")
        print("Available tracks: " + ", ".join(available))
        return
    _, lines = run_all(track, args.mass, runs=args.runs)
    print("\n".join(lines))


if __name__ == "__main__":
    main()
