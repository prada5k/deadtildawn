"""Bridge between the Godot game and the Python sim.

Godot runs:   python tools/game_bridge.py <command> [options]
and reads ONE JSON object from stdout. Every reply has "bridge_version" and
"ok"; failures come back as {"ok": false, "error": "..."} instead of crashing.

Commands:
  car_stats                               stat sheet for the garage
  track     --track FILE                  layout for the briefing (no car)
  rival     --rival FILE --seed N         rival card + tonight's posted time
  practice  --track FILE                  practice runs per push level (time + mistake flag)
  odds      --track FILE --posted T       win odds for every push level (dev tools only:
                                          the game shows practice runs, not odds)
  race      --track FILE --push P --seed N --out FILE.json
                                          run the race, write the replay

Odds and races use the SAME solver settings (GAME_DS), so the odds are honest.
Time distributions are cached per car + track + settings (runs/cache/).
"""
import argparse
import hashlib
import json
import random
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).parent))

BRIDGE_VERSION = 1
CACHE_FORMAT = 2       # bump when the cached JSON layout changes (sim changes are hashed)
GAME_DS = 0.5          # m; odds and races must match
ODDS_RUNS = 60         # Monte Carlo runs per push level
CACHE_DIR = ROOT / "runs" / "cache"
CAR_FILE = ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json"


def reply(**data):
    print(json.dumps({"bridge_version": BRIDGE_VERSION, "ok": True, **data},
                     separators=(",", ":")))


def fail(message):
    print(json.dumps({"bridge_version": BRIDGE_VERSION, "ok": False, "error": message}))
    sys.exit(1)


def resolve(path):
    p = Path(path)
    return p if p.is_absolute() else ROOT / p


# ------------------------------------------------------------------ commands

def car_stats():
    from sim.braking import stopping_distance
    from sim.car import load_car
    from sim.forces import limiting_axle, max_lateral_accel
    from sim.metrics import time_at_distance, time_to_speed, top_speed
    from sim.straight import run_straight
    from sim.units import FT_TO_M, G, HP_TO_W, LBFT_TO_NM, MPH_TO_MS, RPM_TO_RADS

    car = load_car(CAR_FILE)
    power = max(t * r * RPM_TO_RADS for r, t in zip(car.torque_rpm, car.torque_nm))
    peak_rpm = max(zip(car.torque_rpm, car.torque_nm), key=lambda p: p[0] * p[1])[0]
    tq, tq_rpm = max(zip(car.torque_nm, car.torque_rpm))
    q = run_straight(car, 402.336, ds=0.1)
    long = run_straight(car, 8000, ds=0.5)
    hp = power / HP_TO_W
    from sim.powertrain import torque_at
    dyno = []
    for rpm in range(1000, int(car.fuel_cut) + 1, 200):
        t = torque_at(car, rpm - 1e-6 if rpm == car.fuel_cut else rpm)
        dyno.append([rpm, round(t / LBFT_TO_NM, 1), round(t * rpm * RPM_TO_RADS / HP_TO_W, 1)])
    reply(dyno=dyno, name=car.name, hp=round(hp), hp_rpm=peak_rpm,
          torque_lbft=round(tq / LBFT_TO_NM), torque_rpm=tq_rpm,
          weight_kg=round(car.mass), hp_per_tonne=round(hp / (car.mass / 1000)),
          zero_60_s=round(time_to_speed(q, 60 * MPH_TO_MS), 2),
          quarter_s=round(time_at_distance(q, 402.336), 2),
          top_speed_mph=round(top_speed(long) / MPH_TO_MS),
          skidpad_g=round(max_lateral_accel(car) / G, 3),
          balance="understeer" if limiting_axle(car) == "front" else "oversteer",
          sixty_zero_ft=round(stopping_distance(car, 60 * MPH_TO_MS) / FT_TO_M),
          redline=car.redline, drivetrain="FWD")


def track(track_file):
    from export_replay import TRACK_POINT_STEP, _r
    from sim.track import find_crossings, load_track, track_xy
    import math

    segments = load_track(resolve(track_file))
    length = sum(seg.length for seg in segments)
    s = [i * TRACK_POINT_STEP for i in range(int(length / TRACK_POINT_STEP) + 1)] + [length]
    xs, ys, _ = track_xy(segments, s)
    corners, start = [], 0.0
    for seg in segments:
        end = start + seg.length
        if seg.is_corner:
            (mx,), (my,), (mh,) = track_xy(segments, [(start + end) / 2])
            out = 1 if seg.direction == "L" else -1
            corners.append({"text": seg.text, "severity": seg.severity,
                            "radius": _r(seg.radius, 1), "s_start": _r(start, 1),
                            "s_end": _r(end, 1), "mid": [_r(mx, 2), _r(my, 2)],
                            "outward": [_r(math.sin(mh) * out, 4), _r(-math.cos(mh) * out, 4)]})
        start = end
    reply(name=resolve(track_file).name, length=_r(length, 1),
          notes=", ".join(seg.text for seg in segments),
          centerline=[[_r(x, 2), _r(y, 2)] for x, y in zip(xs, ys)],
          corners=corners, crossings=len(find_crossings(segments)))


def distributions(track_file):
    """Lap-time samples per push level, cached by car + track + settings."""
    from sim.car import load_car
    from sim.driver import PUSH_LEVELS, Driver
    from sim.montecarlo import run_many
    from sim.track import discretize, load_track

    # The cache key must cover EVERYTHING that changes the results: car data,
    # track, settings, and the sim's own code. Hashing the sim source means any
    # physics or driver-model change invalidates old odds automatically (a
    # hand-bumped version number only works if someone remembers to bump it).
    track_path = resolve(track_file)
    sim_code = "".join(p.read_text(encoding="utf-8") for p in sorted((ROOT / "sim").glob("*.py")))
    key = hashlib.sha256((CAR_FILE.read_text(encoding="utf-8") + track_path.read_text(encoding="utf-8")
                          + sim_code + f"{GAME_DS}|{ODDS_RUNS}|{Driver().sigma}|fmt{CACHE_FORMAT}").encode()).hexdigest()[:16]
    cache = CACHE_DIR / f"{track_path.stem}_{key}.json"
    if cache.exists():
        return json.loads(cache.read_text(encoding="utf-8")), True

    car = load_car(CAR_FILE)
    grid = discretize(load_track(track_path), GAME_DS)
    data = {}
    for push in PUSH_LEVELS:
        d = run_many(car, grid, Driver(push=push), ODDS_RUNS, seed0=1000)
        data[push] = {"times": d.times, "mistakes": d.mistakes, "mistake_rate": d.mistake_rate}
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(data), encoding="utf-8")
    return data, False


def quantile(xs, q):
    xs = sorted(xs)
    i = q * (len(xs) - 1)
    lo = int(i)
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (i - lo)


def rival(rival_file, seed):
    spec = json.loads(resolve(rival_file).read_text(encoding="utf-8"))
    data, cached = distributions(spec["track"])
    # Base time: where the player's BEST odds (over all push levels) equal the
    # target. Each push level reaches the target at its own quantile; the best
    # odds first reach it at the earliest (smallest) of those times.
    base = min(quantile(d["times"], spec["best_push_odds"]) for d in data.values())
    posted = base + random.Random(seed).gauss(0.0, spec["nightly_spread_s"])
    reply(id=spec["id"], name=spec["name"], car=spec["car"], club=spec["club"],
          track=spec["track"], payout=spec["payout"], base_time=round(base, 3),
          posted_time=round(posted, 3), seed=seed, cached=cached)


def odds(track_file, posted):
    data, cached = distributions(track_file)
    out = {}
    for push, d in data.items():
        t = d["times"]
        out[push] = {"win": round(sum(x < posted for x in t) / len(t), 3),
                     "mean": round(statistics.mean(t), 3),
                     "spread": round(statistics.stdev(t), 3),
                     "best": round(min(t), 3), "worst": round(max(t), 3),
                     "mistake_rate": round(d["mistake_rate"], 3)}
    reply(posted=posted, runs=len(next(iter(data.values()))["times"]), cached=cached,
          push_levels=out)


def practice(track_file):
    """Every practice run per push level: the game draws these as dots and
    leaves the judging to the player (no percentages)."""
    data, cached = distributions(track_file)
    reply(runs=len(next(iter(data.values()))["times"]), cached=cached,
          push_levels={p: {"times": [round(t, 3) for t in d["times"]],
                           "mistakes": d["mistakes"]} for p, d in data.items()})


def race(track_file, push, seed, out_file):
    from export_replay import build_replay
    from sim.car import load_car
    from sim.driver import Driver
    from sim.lap import run_lap
    from sim.track import discretize, load_track

    track_path = resolve(track_file)
    car = load_car(CAR_FILE)
    segments = load_track(track_path)
    lap = run_lap(car, discretize(segments, GAME_DS), driver=Driver(push=push), seed=seed)
    replay_data = build_replay(car, segments, lap, track_path.name)
    out = Path(out_file)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(replay_data, separators=(",", ":")), encoding="utf-8")
    reply(lap_time=round(lap.lap_time, 3), push=push, seed=seed, replay=str(out),
          mistakes=[c.text for c in lap.corner_log if c.mistake])


def main():
    ap = argparse.ArgumentParser(description="deadtildawn game bridge")
    ap.add_argument("command", choices=["car_stats", "track", "rival", "practice", "odds", "race"])
    ap.add_argument("--track")
    ap.add_argument("--rival")
    ap.add_argument("--posted", type=float)
    ap.add_argument("--push")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--out")
    a = ap.parse_args()
    try:
        if a.command == "car_stats":
            car_stats()
        elif a.command == "track":
            track(a.track)
        elif a.command == "rival":
            rival(a.rival, a.seed)
        elif a.command == "practice":
            practice(a.track)
        elif a.command == "odds":
            odds(a.track, a.posted)
        elif a.command == "race":
            race(a.track, a.push, a.seed, a.out)
    except Exception as e:                         # report, don't crash the game
        fail(f"{type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
