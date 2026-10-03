"""Lap telemetry plots vs distance: speed, gear/rpm, driver inputs, rotor
temperature, longitudinal g.

Standalone:  python tools/plot_lap.py [track_file]  -> runs/latest/lap_telemetry.png
Used by run_all.py for the combined report.
"""
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

from common import DEFAULT_TRACK, latest_path, load_run, segment_lines, shift_lines  # noqa: E402
from sim.units import G  # noqa: E402


def draw_lap(car, segments, lap, out_path):
    tel = lap.telemetry
    fig, (ax1, ax2, ax4, ax5, ax3) = plt.subplots(
        5, 1, figsize=(11, 13), sharex=True,
        gridspec_kw={"height_ratios": [3, 2, 1.5, 1.5, 1.5]}, layout="constrained")

    start = 0.0
    for seg in segments:
        end = start + seg.length
        if seg.is_corner:
            for ax in (ax1, ax2, ax3, ax4, ax5):
                ax.axvspan(start, end, color="0.9", zorder=0)
            ax1.text((start + end) / 2, 2, seg.text, ha="center", fontsize=8)
        start = end

    ax1.plot(tel.s, [v * 3.6 for v in tel.v], label="Speed")
    lim = [v * 3.6 if v != float("inf") else None for v in lap.v_limit]
    ax1.plot(tel.s, lim, "--", color="red", linewidth=1, label="Corner limit")
    ax1.set_ylabel("Speed (km/h)")
    ax1.set_title(f"{car.name}: {lap.lap_time:.2f} s")
    ax1.legend(loc="upper right")

    ax2.plot(tel.s, tel.rpm, color="tab:orange", label="RPM")
    ax2.set_ylabel("RPM")
    ax2b = ax2.twinx()
    ax2b.step(tel.s, tel.gear, where="post", color="tab:green", label="Gear (0 = shifting)")
    ax2b.set_ylabel("Gear")
    ax2b.set_ylim(-0.5, 5.5)
    ax2b.legend(loc="lower right")

    ax4.fill_between(tel.s, [x * 100 for x in tel.throttle], step="post",
                     color="tab:green", alpha=0.6, label="Throttle")
    ax4.fill_between(tel.s, [x * 100 for x in tel.brake], step="post",
                     color="tab:red", alpha=0.6, label="Brake")
    ax4.set_ylabel("Pedal (%)")
    ax4.set_ylim(0, 105)
    ax4.legend(loc="upper right", ncol=2)

    ax5.plot(tel.s, tel.brake_temp, color="tab:red")
    ax5.axhline(car.pad_fade_temp, color="tab:red", linestyle="--", linewidth=1,
                label=f"Fade onset ({car.pad_fade_temp:.0f} C)")
    ax5.set_ylabel("Front rotor (C)")
    ax5.set_ylim(0, max(max(tel.brake_temp), car.pad_fade_temp) * 1.1)
    ax5.legend(loc="upper left")

    ax3.plot(tel.s, [a / G for a in tel.accel], color="tab:purple")
    ax3.axhline(0, color="black", linewidth=0.5)
    ax3.set_ylabel("Long. accel (g)")
    ax3.set_xlabel("Distance (m)")

    fig.savefig(out_path, dpi=120)
    plt.close(fig)


def main():
    track_file = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_TRACK
    car, segments, _, lap = load_run(track_file)
    out = latest_path("lap_telemetry.png")
    draw_lap(car, segments, lap, out)
    print(f"\n{car.name} on {track_file.name}: lap time {lap.lap_time:.2f} s\n")
    print("\n".join(segment_lines(segments, lap.telemetry)))
    print("\nShifts:\n  " + "\n  ".join(shift_lines(lap.telemetry)))
    print(f"\nSaved {out.relative_to(out.parents[2])}")


if __name__ == "__main__":
    main()
