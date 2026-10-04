"""Bridge between the Godot game and the Python sim.

Godot runs:   python tools/game_bridge.py <command> [options]
and reads ONE JSON object from stdout. Every reply has "bridge_version" and
"ok"; failures come back as {"ok": false, "error": "..."} instead of crashing.

Commands:
  parts                                   the parts catalog, with each part's exact effects
  pull      --source S --pity JSON --seed N   one pull: part, quality roll, effects, new pity
                                          (--parts entries may carry a quality: cams_race@0.83)
  car_stats [--parts a,b]                 stat sheet + dyno for the car with these parts
  track     --track FILE                  layout for the briefing (no car)
  rival     --rival FILE                  rival's stat card (car + driver read) + home road
  street    --week W --seed N             this week's open road (generated) + a random
                                          street racer's stat card
  race      ... --opponent ID --opp-seed N   head-to-head: both cars run the road; the
                                          replay carries the opponent as a ghost
  practice  --track FILE [--parts a,b]    practice runs per push level (time + mistake flag)
  odds      --track FILE --posted T       win odds for every push level (dev tools only:
                                          the game shows practice runs, not odds)
  race      --track FILE --push P --seed N --out FILE.json [--parts a,b]
                                          run the race, write the replay

Odds and races use the SAME solver settings (GAME_DS), so the odds are honest.
Rival times are anchored to the STOCK car: upgrades make the player faster,
they never make the rival faster.
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


def player_car(part_ids):
    """The DX with these parts installed (stock if none). Entries are part ids,
    optionally with a quality roll: "cams_race@0.83" (default 0.5 = catalog)."""
    from sim.car import load_car
    from sim.gacha import instance_part
    from sim.parts import apply_parts, parts_by_ids
    car = load_car(CAR_FILE)
    if not part_ids:
        return car
    ids, qs = [], []
    for entry in part_ids:
        pid, _, q = entry.partition("@")
        ids.append(pid)
        qs.append(float(q) if q else 0.5)
    return apply_parts(car, [instance_part(t, q) for t, q in zip(parts_by_ids(ids), qs)])


def parse_parts(text):
    return sorted(p for p in (text or "").split(",") if p)


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

def stat_sheet(car):
    """Numbers for a stat card (the same sheet for the DX and opponents)."""
    from sim.braking import stopping_distance
    from sim.forces import limiting_axle, max_lateral_accel
    from sim.metrics import time_to_speed
    from sim.powertrain import torque_at
    from sim.straight import run_straight
    from sim.units import FT_TO_M, G, HP_TO_W, LBFT_TO_NM, MPH_TO_MS, RPM_TO_RADS
    hp = max(torque_at(car, r) * r * RPM_TO_RADS for r in range(1000, 6800, 25)) / HP_TO_W
    tq = max(torque_at(car, r) for r in range(1000, 6800, 25)) / LBFT_TO_NM
    q = run_straight(car, 402.336, ds=0.5)
    return {"name": car.name, "hp": round(hp), "torque_lbft": round(tq), "weight_kg": round(car.mass),
            "hp_per_tonne": round(hp / (car.mass / 1000)), "drivetrain": car.drivetrain,
            "zero_60_s": round(time_to_speed(q, 60 * MPH_TO_MS), 2),
            "skidpad_g": round(max_lateral_accel(car) / G, 3),
            "balance": "understeer" if limiting_axle(car) == "front" else "oversteer",
            "sixty_zero_ft": round(stopping_distance(car, 60 * MPH_TO_MS) / FT_TO_M)}


def opponent_card(oid):
    from sim.car import load_car
    from sim.opponents import (condition_label, driver_read, load_opponents, opponent_car)
    spec = load_opponents()["opponents"][oid]
    sheet = stat_sheet(opponent_car(load_car(CAR_FILE), spec))
    sheet["name"] = spec["car"]
    return {"opponent": oid, "name": spec["name"], "car": spec["car"], "stats": sheet,
            "condition": condition_label(spec), "driver_read": driver_read(spec)}


def car_stats(part_ids=()):
    from sim.braking import stopping_distance
    from sim.car import load_car
    from sim.forces import limiting_axle, max_lateral_accel
    from sim.metrics import time_at_distance, time_to_speed, top_speed
    from sim.straight import run_straight
    from sim.units import FT_TO_M, G, HP_TO_W, LBFT_TO_NM, MPH_TO_MS, RPM_TO_RADS

    car = player_car(part_ids)
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


def part_effects(car, part):
    """Exact effects of one part on the stock car, as display strings."""
    from sim.parts import apply_parts
    from sim.powertrain import torque_at
    from sim.units import HP_TO_W, LBFT_TO_NM, RPM_TO_RADS

    mod = apply_parts(car, [part])

    def peak_hp(c):
        return max(torque_at(c, r) * r * RPM_TO_RADS for r in range(1000, 6800, 25)) / HP_TO_W
    out = []
    e = part["effects"]
    if "torque_scale" in e or "torque_shape" in e:
        out.append(f"{peak_hp(mod) - peak_hp(car):+.1f} hp peak")
        d3 = (torque_at(mod, 3000) - torque_at(car, 3000)) / LBFT_TO_NM
        d6 = (torque_at(mod, 6000) - torque_at(car, 6000)) / LBFT_TO_NM
        out.append(f"{d3:+.1f} lb-ft @ 3000 rpm, {d6:+.1f} lb-ft @ 6000 rpm")
    if e.get("mass_kg"):
        out.append(f"{e['mass_kg']:+.0f} kg")
    if "engine_inertia_scale" in e:
        out.append(f"flywheel inertia {(e['engine_inertia_scale'] - 1) * 100:+.0f}%")
    if "wheel_inertia_scale" in e:
        out.append(f"wheel inertia {(e['wheel_inertia_scale'] - 1) * 100:+.0f}%")
    if "shift_time_s" in e:
        out.append(f"shift time {car.shift_time:.2f} s -> {mod.shift_time:.2f} s")
    if "final_drive" in e:
        out.append(f"final drive {car.final_drive:.3f} -> {mod.final_drive:.3f}")
    if "mu_scale" in e:
        out.append(f"grip {(e['mu_scale'] - 1) * 100:+.0f}%")
    if "load_k_scale" in e:
        out.append(f"load sensitivity {(e['load_k_scale'] - 1) * 100:+.0f}%")
    if "crr_scale" in e:
        out.append(f"rolling resistance {(e['crr_scale'] - 1) * 100:+.0f}%")
    if "roll_front" in e:
        out.append(f"front roll stiffness {car.roll_front * 100:.0f}% -> {mod.roll_front * 100:.0f}%")
    if "cg_height_m" in e:
        out.append(f"center of gravity {e['cg_height_m'] * 100:+.1f} cm")
    return out


def parts_catalog():
    from sim.car import load_car
    from sim.parts import load_catalog
    slots, parts = load_catalog()
    car = load_car(CAR_FILE)
    from sim.gacha import load_pulls
    sources = {k: {kk: v for kk, v in s.items() if kk in ("name", "price", "blurb", "rep_required", "pity")}
               for k, s in load_pulls().items() if not s.get("hidden")}
    reply(slots=slots, sources=sources,
          parts=[{**p, "effects_text": part_effects(car, p)} for p in parts.values()])


def do_pull(source, pity_json, seed):
    """One pull from an in-world source, with the effects of the rolled part."""
    import random
    from sim.car import load_car
    from sim.gacha import instance_part, load_pulls, pull
    from sim.parts import load_catalog
    sources = load_pulls()
    if source not in sources:
        raise ValueError(f"unknown source {source!r}")
    # (rep and cash gates are enforced by the game, which owns the save)
    _, parts = load_catalog()
    pity = json.loads(pity_json or "{}")
    pid, q, new_pity = pull(source, sources, parts, pity, random.Random(seed))
    car = load_car(CAR_FILE)
    reply(source=source, price=sources[source]["price"], part=pid, quality=q,
          rarity=parts[pid]["rarity"], name=parts[pid]["name"], slot=parts[pid]["slot"],
          effects_text=part_effects(car, instance_part(parts[pid], q)), pity=new_pity)


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


def distributions(track_file, part_ids=()):
    """Lap-time samples per push level, cached by car + parts + track + settings."""
    from sim.driver import PUSH_LEVELS, Driver
    from sim.parts import CATALOG_FILE
    from sim.montecarlo import run_many
    from sim.track import discretize, load_track

    # The cache key must cover EVERYTHING that changes the results: car data,
    # track, settings, and the sim's own code. Hashing the sim source means any
    # physics or driver-model change invalidates old odds automatically (a
    # hand-bumped version number only works if someone remembers to bump it).
    track_path = resolve(track_file)
    sim_code = "".join(p.read_text(encoding="utf-8") for p in sorted((ROOT / "sim").glob("*.py")))
    key = hashlib.sha256((CAR_FILE.read_text(encoding="utf-8") + track_path.read_text(encoding="utf-8")
                          + sim_code + CATALOG_FILE.read_text(encoding="utf-8") + ",".join(part_ids)
                          + f"{GAME_DS}|{ODDS_RUNS}|{Driver().sigma}|fmt{CACHE_FORMAT}").encode()).hexdigest()[:16]
    cache = CACHE_DIR / f"{track_path.stem}_{key}.json"
    if cache.exists():
        return json.loads(cache.read_text(encoding="utf-8")), True

    car = player_car(part_ids)
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
    """The rival's stat card on his home road. (No posted time: the race is
    head-to-head, so the card IS the information.)"""
    spec = json.loads(resolve(rival_file).read_text(encoding="utf-8"))
    reply(id=spec["id"], club=spec["club"], track=spec["track"], payout=spec["payout"],
          seed=seed, **opponent_card(spec["opponent"]))


OPEN_ROAD_STYLES = ["technical", "balanced", "flowing"]
OPEN_ROAD_DIR = ROOT / "data" / "tracks" / "generated"


def open_road(week):
    """This week's open road: generated from the week number (same week = same
    road), style rotating technical -> balanced -> flowing. Writes the pace
    notes to a track file once and returns its repo-relative path."""
    from sim.trackgen import generate
    style = OPEN_ROAD_STYLES[(week - 1) % len(OPEN_ROAD_STYLES)]
    path = OPEN_ROAD_DIR / f"open_week_{week}.txt"
    if not path.exists():
        g = generate(1000 + week, style)
        OPEN_ROAD_DIR.mkdir(parents=True, exist_ok=True)
        path.write_text(f"# Open road, week {week}: {style} (sim/trackgen.py seed {1000 + week})\n"
                        f"{g.notes}\n", encoding="utf-8")
    return path.relative_to(ROOT).as_posix(), style


def street(week, seed):
    """A random street racer's stat card on this week's open road."""
    import random
    from sim.opponents import load_opponents
    track, style = open_road(week)
    oid = random.Random(seed).choice(load_opponents()["street"])
    reply(id="street", club=f"Open road, {style}", track=track, payout="even",
          seed=seed, week=week, style=style, **opponent_card(oid))


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


def practice(track_file, part_ids=()):
    """Every practice run per push level: the game draws these as dots and
    leaves the judging to the player (no percentages)."""
    data, cached = distributions(track_file, part_ids)
    reply(runs=len(next(iter(data.values()))["times"]), cached=cached,
          push_levels={p: {"times": [round(t, 3) for t in d["times"]],
                           "mistakes": d["mistakes"]} for p, d in data.items()})


def race(track_file, push, seed, out_file, part_ids=(), opponent=None, opp_seed=None):
    from export_replay import build_replay
    from sim.car import load_car
    from sim.driver import Driver
    from sim.lap import run_lap
    from sim.track import discretize, load_track

    from sim.lap import finish_time
    from sim.opponents import load_opponents, opponent_car, opponent_driver

    track_path = resolve(track_file)
    car = player_car(part_ids)
    segments = load_track(track_path)
    grid = discretize(segments, GAME_DS)
    lap = run_lap(car, grid, driver=Driver(push=push), seed=seed)
    ghost, opp = None, None
    if opponent:
        spec = load_opponents()["opponents"][opponent]
        opp = run_lap(opponent_car(load_car(CAR_FILE), spec), grid,
                      driver=opponent_driver(spec), seed=opp_seed)
        ghost = {"name": spec["name"], "car": spec["car"], "lap": opp}
    replay_data = build_replay(car, segments, lap, track_path.name, ghost)
    out = Path(out_file)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(replay_data, separators=(",", ":")), encoding="utf-8")
    result = {}
    if opp is not None:
        # Head-to-head: a DNF never wins; if both crash, nobody wins
        both_out = lap.dnf and opp.dnf
        result = {"opponent_time": round(opp.lap_time, 3), "opponent_dnf": opp.dnf,
                  "opponent_crash_corner": opp.crash_corner,
                  "no_contest": both_out,
                  "won": (not both_out) and finish_time(lap) < finish_time(opp)}
    reply(lap_time=round(lap.lap_time, 3), dnf=lap.dnf, crash_corner=lap.crash_corner,
          push=push, seed=seed, replay=str(out),
          mistakes=[c.text for c in lap.corner_log if c.mistake], **result)


def main():
    ap = argparse.ArgumentParser(description="deadtildawn game bridge")
    ap.add_argument("command", choices=["parts", "pull", "car_stats", "track", "rival", "street",
                                        "practice", "odds", "race"])
    ap.add_argument("--week", type=int)
    ap.add_argument("--opponent")
    ap.add_argument("--opp-seed", type=int, default=0)
    ap.add_argument("--source")
    ap.add_argument("--pity", default="{}")
    ap.add_argument("--parts", default="", help="installed part ids, comma-separated")
    ap.add_argument("--track")
    ap.add_argument("--rival")
    ap.add_argument("--posted", type=float)
    ap.add_argument("--push")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--out")
    a = ap.parse_args()
    try:
        part_ids = parse_parts(a.parts)
        if a.command == "parts":
            parts_catalog()
        elif a.command == "pull":
            do_pull(a.source, a.pity, a.seed)
        elif a.command == "car_stats":
            car_stats(part_ids)
        elif a.command == "track":
            track(a.track)
        elif a.command == "rival":
            rival(a.rival, a.seed)
        elif a.command == "street":
            street(a.week, a.seed)
        elif a.command == "practice":
            practice(a.track, part_ids)
        elif a.command == "odds":
            odds(a.track, a.posted)
        elif a.command == "race":
            race(a.track, a.push, a.seed, a.out, part_ids, a.opponent, a.opp_seed)
    except Exception as e:                         # report, don't crash the game
        fail(f"{type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
