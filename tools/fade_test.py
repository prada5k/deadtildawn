"""Brake fade test: ten 60-0 stops back to back (car only, track-independent).

Two versions:
  - with cooling: accelerate straight back to 60 between stops (like a
    magazine fade test)
  - no cooling:   worst case, all heat stays in the rotors

Standalone:  python tools/fade_test.py  -> runs/latest/fade_test.png
Used by run_all.py for the combined report.
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

from common import CAR_FILE, latest_path                 # noqa: E402
from sim.braking import repeated_stops                   # noqa: E402
from sim.car import load_car                             # noqa: E402
from sim.units import FT_TO_M, MPH_TO_MS                 # noqa: E402

N_STOPS = 10


def fade_test(car, out_path, n=N_STOPS):
    """Run both versions, draw the plot, return a text table as lines."""
    v0 = 60 * MPH_TO_MS
    cooled = repeated_stops(car, n, v0, cooling=True)
    hot = repeated_stops(car, n, v0, cooling=False)
    base = cooled[0].distance

    lines = [f"Ten 60-0 stops back to back. Pads: fade onset {car.pad_fade_temp:.0f} C,"
             f" capacity ratio {car.brake_capacity}",
             "",
             f"{'':<6}{'--- with cooling ---':^30}{'---- no cooling ----':^30}",
             f"{'Stop':<6}{'Start C':>9}{'End C':>9}{'Dist ft':>12}"
             f"{'Start C':>9}{'End C':>9}{'Dist ft':>12}",
             "-" * 66]
    for i, (c, h) in enumerate(zip(cooled, hot), 1):
        lines.append(f"{i:<6}{c.temp_start:>9.0f}{c.temp_end:>9.0f}{c.distance / FT_TO_M:>12.1f}"
                     f"{h.temp_start:>9.0f}{h.temp_end:>9.0f}{h.distance / FT_TO_M:>12.1f}")

    def first_fade(stops):
        for i, st in enumerate(stops, 1):
            if st.distance > base * 1.01:
                return f"stop {i} (+{(st.distance / base - 1) * 100:.0f}%)"
        return f"none in {n} stops"

    lines += ["", f"First stop >1% longer: with cooling {first_fade(cooled)}, "
                  f"no cooling {first_fade(hot)}"]

    stops = range(1, n + 1)
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True, layout="constrained")
    ax1.plot(stops, [c.temp_end for c in cooled], "o-", color="tab:blue",
             label="With cooling (end of stop)")
    ax1.plot(stops, [h.temp_end for h in hot], "o-", color="tab:red",
             label="No cooling (end of stop)")
    ax1.axhline(car.pad_fade_temp, color="0.4", linestyle="--", linewidth=1,
                label=f"Fade onset ({car.pad_fade_temp:.0f} C)")
    bite = car.pad_fade_temp + (car.pad_mu - car.pad_mu / car.brake_capacity) / car.pad_fade_rate
    ax1.axhline(bite, color="0.1", linestyle=":", linewidth=1,
                label=f"Fade costs distance (~{bite:.0f} C)")
    ax1.set_ylabel("Front rotor temp (C)")
    ax1.set_title(f"{car.name}: brake fade test, {n} x 60-0 mph")
    ax1.legend(loc="upper left", fontsize=8)

    w = 0.38
    ax2.bar([i - w / 2 for i in stops], [c.distance / FT_TO_M for c in cooled], w,
            color="tab:blue", label="With cooling")
    ax2.bar([i + w / 2 for i in stops], [h.distance / FT_TO_M for h in hot], w,
            color="tab:red", label="No cooling")
    ax2.axhline(base / FT_TO_M, color="black", linewidth=0.8)
    ax2.set_ylim(base / FT_TO_M * 0.9, None)
    ax2.set_ylabel("Stopping distance (ft)")
    ax2.set_xlabel("Stop number")
    ax2.set_xticks(list(stops))
    ax2.legend(loc="upper left", fontsize=8)

    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    return lines


def main():
    car = load_car(CAR_FILE)
    out = latest_path("fade_test.png")
    print("\n" + "\n".join(fade_test(car, out)))
    print(f"\nSaved {out.relative_to(out.parents[2])}")


if __name__ == "__main__":
    main()
