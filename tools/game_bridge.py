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
  rival     --rival FILE --seed N         rival card + tonight's posted time
  street    --week W --seed N             this week's open road (generated) + a random
                                          street racer and their posted time
  practice  --track FILE [--parts a,b]    practice runs per push level (time + mistake flag)
  odds      --track FILE --posted T       win odds for every push level (dev tools only:
                                          the game shows practice runs, not odds)
  race      --track FILE --push P --seed N --out FILE.json [--parts a,b]
                                           run the race, write the replay
  local_straight --out FILE.json [--parts a,b]
                                           run the fixed controlled test, write the replay
  local_curves --out FILE.json [--parts a,b]
                                           run the fixed handling test, write the replay

Odds and races use the SAME solver settings (GAME_DS), so the odds are honest.
Rival times are anchored to the STOCK car: upgrades make the player faster,
they never make the rival faster.
Time distributions are cached per car + track + settings (runs/cache/).
"""
import argparse
from dataclasses import asdict
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
REFERENCE_CAR = ROOT / "data" / "cars" / "ej6_dx_coupe_1996.json"
GAME_CAR = ROOT / "data" / "cars" / "eg6_sir_ii_1995.json"
ACTIVE_CAR_FILE = REFERENCE_CAR  # CLI default preserves the engineering-tool contract
MARKET_FILE = ROOT / "data" / "parts" / "market_v01.json"
LOCAL_STRAIGHT_FILE = ROOT / "data" / "tracks" / "local_straight.txt"
LOCAL_STRAIGHT_ID = "LOCAL_STRAIGHT"
QUARTER_MILE_M = 402.336
LOCAL_CURVES_FILE = ROOT / "data" / "tracks" / "local_curves.txt"
LOCAL_CURVES_ID = "LOCAL_CURVES"
LOCAL_CURVES_SEED = 9605
LOCAL_RIVAL_FILE = ROOT / "data" / "rivals" / "oxnard_eg6_time_attack.json"


def player_car(part_ids):
    """The selected car with these parts installed (stock if none). Entries are part ids,
    optionally with a quality roll: "cams_race@0.83" (default 0.5 = catalog)."""
    from sim.car import load_car
    from sim.parts import apply_parts, parts_by_ids
    car = load_car(ACTIVE_CAR_FILE)
    if not part_ids:
        return car
    ids, qualities = [], []
    for entry in part_ids:
        pid, _, q = entry.partition("@")
        ids.append(pid)
        qualities.append(float(q) if q else None)
    selected = parts_by_ids(ids)
    if any(q is not None for q in qualities):
        from sim.gacha import instance_part  # legacy CLI compatibility only
        selected = [instance_part(t, q) if q is not None else t
                    for t, q in zip(selected, qualities)]
    return apply_parts(car, selected)


def parse_parts(text):
    return sorted(p for p in (text or "").split(",") if p)


def physical_vehicle_state(car):
    """Small physical snapshot shared by controlled tests."""
    return {
        "car_id": car.id,
        "mass_kg": round(car.mass, 3),
        "final_drive": round(car.final_drive, 4),
        "shift_time_s": round(car.shift_time, 4),
        "engine_inertia_kgm2": round(car.engine_inertia, 4),
        "wheel_inertia_kgm2": round(car.wheel_inertia, 4),
        "cg_height_m": round(car.cg_height, 4),
        "front_roll_stiffness_fraction": round(car.roll_front, 4),
    }


def road_snapshot(path, road_id):
    """Stable identity for a controlled road's exact authored geometry."""
    return {
        "road_id": road_id,
        "geometry_version": 1,
        "geometry_sha256": hashlib.sha256(Path(path).read_bytes()).hexdigest(),
    }


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


def local_straight(out_file, part_ids=()):
    """Deterministic quarter-mile test for the current player-car configuration.

    Acceleration and braking use the existing validated solvers.  The replay is
    the acceleration run; the 60-0 figure is a separate existing measurement.
    """
    from types import SimpleNamespace

    from export_replay import build_replay
    from sim.braking import stopping_distance
    from sim.metrics import speed_at_distance, time_at_distance, time_to_speed
    from sim.straight import run_straight
    from sim.track import load_track
    from sim.units import AMBIENT_C, FT_TO_M, MPH_TO_MS

    segments = load_track(LOCAL_STRAIGHT_FILE)
    distance = sum(segment.length for segment in segments)
    if abs(distance - QUARTER_MILE_M) > 1e-6:
        raise ValueError(f"{LOCAL_STRAIGHT_ID} must be {QUARTER_MILE_M} m, got {distance}")

    car = player_car(part_ids)
    telemetry = run_straight(car, distance, ds=0.1)
    lap = SimpleNamespace(telemetry=telemetry, lap_time=telemetry.t[-1],
                          driver=None, seed=None, corner_log=[])
    replay_data = build_replay(car, segments, lap, LOCAL_STRAIGHT_ID)
    out = Path(out_file)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(replay_data, separators=(",", ":")), encoding="utf-8")

    zero_60 = time_to_speed(telemetry, 60 * MPH_TO_MS)
    quarter = time_at_distance(telemetry, QUARTER_MILE_M)
    trap = speed_at_distance(telemetry, QUARTER_MILE_M)
    reply(
        road_id=LOCAL_STRAIGHT_ID,
        road=road_snapshot(LOCAL_STRAIGHT_FILE, LOCAL_STRAIGHT_ID),
        measurement_scope={
            "run": "standing-start 402.336 m acceleration",
            "braking": "separate existing 60-0 braking calculation",
        },
        conditions={
            "surface": "baseline dry",
            "ambient_c": AMBIENT_C,
            "start": "standing",
            "reference_driver": "deterministic full throttle",
            "integration_step_m": 0.1,
        },
        installed_definition_ids=list(part_ids),
        vehicle_state=physical_vehicle_state(car),
        measurements={
            "zero_60_s": round(zero_60, 3),
            "quarter_mile_s": round(quarter, 3),
            "quarter_mile_trap_mph": round(trap / MPH_TO_MS, 1),
            "sixty_zero_ft": round(stopping_distance(car, 60 * MPH_TO_MS) / FT_TO_M, 1),
        },
        replay=str(out),
    )


def local_curves_result(out_file, part_ids=(), car=None, driver_name="Reference",
                        driver_push="normal", driver_sigma=0.0, driver_seed=LOCAL_CURVES_SEED,
                        definition_path=None, vehicle_visual=None):
    """Run fixed LOCAL CURVES and return its complete physical/result snapshot."""
    from export_replay import build_replay
    from sim.driver import Driver
    from sim.lap import run_lap
    from sim.metrics import speed_at_distance, time_at_distance
    from sim.track import discretize, load_track
    from sim.units import AMBIENT_C, MPH_TO_MS
    from sim.car import load_car

    segments = load_track(LOCAL_CURVES_FILE)
    car = car if car is not None else player_car(part_ids)
    driver = Driver(name=driver_name, push=driver_push, sigma=driver_sigma)
    lap = run_lap(car, discretize(segments, GAME_DS), driver=driver,
                  seed=driver_seed)
    telemetry = lap.telemetry
    replay_data = build_replay(car, segments, lap, LOCAL_CURVES_ID)
    if vehicle_visual:
        replay_data["vehicle_visual"] = dict(vehicle_visual)
    out = Path(out_file)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(replay_data, separators=(",", ":")), encoding="utf-8")

    corners = []
    start = 0.0
    for segment in segments:
        end = start + segment.length
        if segment.is_corner:
            entry = speed_at_distance(telemetry, start)
            exit_speed = speed_at_distance(telemetry, end)
            samples = [entry, exit_speed] + [
                v for s, v in zip(telemetry.s, telemetry.v) if start < s < end
            ]
            corners.append({
                "index": len(corners) + 1,
                "pace_note": segment.text,
                "direction": segment.direction,
                "severity": segment.severity,
                "start_m": round(start, 1),
                "end_m": round(end, 1),
                "time_s": round(time_at_distance(telemetry, end)
                                - time_at_distance(telemetry, start), 3),
                "entry_mph": round(entry / MPH_TO_MS, 1),
                "minimum_mph": round(min(samples) / MPH_TO_MS, 1),
                "exit_mph": round(exit_speed / MPH_TO_MS, 1),
            })
        start = end

    braking_distance = sum(
        telemetry.s[i + 1] - telemetry.s[i]
        for i in range(len(telemetry.s) - 1) if telemetry.brake[i] > 0
    )
    braking_time = sum(
        telemetry.t[i + 1] - telemetry.t[i]
        for i in range(len(telemetry.t) - 1) if telemetry.brake[i] > 0
    )
    braking_zones = sum(
        1 for i, brake in enumerate(telemetry.brake[:-1])
        if brake > 0 and (i == 0 or telemetry.brake[i - 1] == 0)
    )
    source_path = Path(definition_path) if definition_path else ACTIVE_CAR_FILE
    configuration = asdict(car)
    configuration["torque_rpm"] = list(configuration["torque_rpm"])
    configuration["torque_nm"] = list(configuration["torque_nm"])
    configuration["gear_ratios"] = list(configuration["gear_ratios"])
    configuration["definition_id"] = car.id
    configuration["definition_path"] = str(source_path.relative_to(ROOT).as_posix())
    configuration["definition_sha256"] = hashlib.sha256(source_path.read_bytes()).hexdigest()
    configuration["installed_definition_ids"] = list(part_ids)
    return dict(
        road_id=LOCAL_CURVES_ID,
        road=road_snapshot(LOCAL_CURVES_FILE, LOCAL_CURVES_ID),
        measurement_scope={
            "corners": "geometric corner arcs; approach and braking sectors excluded",
        },
        conditions={
            "surface": "baseline dry",
            "ambient_c": AMBIENT_C,
            "start": "standing",
            "reference_driver": "fixed normal profile",
            "driver_sigma": 0.0,
            "driver_seed": driver_seed,
            "integration_step_m": GAME_DS,
        },
        driver_configuration={"name": driver.name, "push": driver.push,
            "fraction": driver.f, "sigma": driver.sigma, "seed": driver_seed},
        installed_definition_ids=list(part_ids),
        vehicle_state=physical_vehicle_state(car),
        vehicle_configuration=configuration,
        measurements={
            "total_time_s": round(lap.lap_time, 3),
            "peak_speed_mph": round(max(telemetry.v) / MPH_TO_MS, 1),
            "braking_zones": braking_zones,
            "braking_distance_m": round(braking_distance, 1),
            "braking_time_s": round(braking_time, 3),
            "peak_brake": round(max(telemetry.brake), 3),
            "corners": corners,
        },
        replay=str(out),
    )


def local_curves(out_file, part_ids=()):
    """Fixed handling route with a deterministic, non-random reference driver."""
    reply(**local_curves_result(out_file, part_ids))


def time_attack(player_out, rival_out, part_ids=(), rival_file=LOCAL_RIVAL_FILE):
    """Run the EG6 and one authored rival on identical fixed road conditions."""
    profile = json.loads(Path(rival_file).read_text(encoding="utf-8"))
    rival_path = (ROOT / profile["vehicle"]["definition_path"]).resolve()
    if not rival_path.is_file():
        raise FileNotFoundError(f"Rival vehicle definition not found: {rival_path}")
    from sim.car import load_car
    driver = profile["driver"]
    player = local_curves_result(player_out, part_ids)
    rival = local_curves_result(rival_out, (), car=load_car(rival_path),
        driver_name=str(driver["name"]), driver_push=str(driver["push"]),
        driver_sigma=float(driver["sigma"]), driver_seed=int(driver["seed"]),
        definition_path=rival_path, vehicle_visual=profile.get("vehicle_visual", {}))
    if player["road"] != rival["road"]:
        raise ValueError("Player and rival road snapshots differ")
    conditions_match = {k: v for k, v in player["conditions"].items() if k != "reference_driver"}
    rival_conditions_match = {k: v for k, v in rival["conditions"].items() if k != "reference_driver"}
    if conditions_match != rival_conditions_match:
        raise ValueError("Player and rival conditions differ")
    reply(event_id="C96_TA_LOCAL_CURVES_001", rival_id=profile["rival_id"],
          rival_identity={k: profile[k] for k in ("name", "home", "bio")},
          player=player, rival=rival)


def part_effects(car, part):
    """Exact effects of one part on the stock car, as display strings."""
    from sim.parts import apply_parts
    from sim.powertrain import torque_at
    from sim.units import HP_TO_W, LBFT_TO_NM, RPM_TO_RADS

    mod = apply_parts(car, [part])

    def peak_hp(c):
        return max(torque_at(c, r) * r * RPM_TO_RADS for r in range(1000, int(c.fuel_cut), 25)) / HP_TO_W
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
    car = load_car(ACTIVE_CAR_FILE)
    from sim.gacha import load_pulls
    sources = {k: {kk: v for kk, v in s.items() if kk in ("name", "price", "blurb", "rep_required", "pity")}
               for k, s in load_pulls().items() if not s.get("hidden")}
    reply(slots=slots, sources=sources,
          parts=[{**p, "effects_text": part_effects(car, p)} for p in parts.values()])


def shop_catalog():
    """Fixed-spec EG6 definitions and curated offers; no pull-data dependency."""
    from sim.car import load_car
    from sim.parts import load_catalog

    slots, parts = load_catalog()
    market = json.loads(MARKET_FILE.read_text(encoding="utf-8"))
    car = load_car(GAME_CAR)
    eligible = {pid: p for pid, p in parts.items()
                if car.id in p.get("compatible_base_car_ids", [])}
    retail = market["retail_ids"]
    used = market["initial_used"]
    if len(retail) != len(set(retail)) or any(pid not in eligible for pid in retail):
        raise ValueError("retail contains duplicate or EG6-incompatible definitions")
    listing_ids = [listing["listing_id"] for listing in used]
    if len(listing_ids) != len(set(listing_ids)):
        raise ValueError("duplicate used listing IDs")
    if any(listing["part"] not in eligible or listing["price"] <= 0 for listing in used):
        raise ValueError("used listing has incompatible part or invalid price")
    work_days = market["work_days_by_slot"]
    if any(p["slot"] not in work_days or any(
        type(work_days[p["slot"]].get(op)) is not int or work_days[p["slot"]][op] < 1
        for op in ("install", "remove")) for p in eligible.values()):
        raise ValueError("every EG6-compatible slot needs positive whole-day work durations")
    refresh = market["used_refresh"]
    fixtures = refresh["fixture_listing_ids"]
    fixture_ids = {listing["listing_id"] for listing in used}
    if any(listing_id not in fixture_ids for listing_id in fixtures):
        raise ValueError("used refresh fixture references an unknown initial listing")
    if type(market["retail_delivery_days"]) is not int or market["retail_delivery_days"] < 1:
        raise ValueError("retail delivery duration must be a positive whole number of days")
    if type(market["used_pickup_days"]) is not int or market["used_pickup_days"] < 0:
        raise ValueError("used pickup duration must be a non-negative whole number of days")
    if type(refresh["calendar_weeks"]) is not int or refresh["calendar_weeks"] < 1:
        raise ValueError("market refresh cadence must be a positive number of calendar weeks")
    if type(refresh["max_available_listings"]) is not int or refresh["max_available_listings"] < 1:
        raise ValueError("market availability cap must be positive")
    if type(refresh["listings_per_refresh"]) is not int or not 1 <= refresh["listings_per_refresh"] <= refresh["max_available_listings"]:
        raise ValueError("market refresh batch must fit the available listing cap")
    reply(slots=slots, retail_ids=retail, initial_used=used,
          work_days_by_slot=work_days, work_notes=market["work_notes"],
          retail_delivery_days=market["retail_delivery_days"],
          used_pickup_days=market["used_pickup_days"],
          retail_fulfillment_notes=market["retail_fulfillment_notes"],
          used_fulfillment_notes=market["used_fulfillment_notes"],
          used_refresh=refresh,
          parts=[{**{k: v for k, v in p.items() if k != "rarity"},
                  "effects_text": part_effects(car, p)} for p in eligible.values()])


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
    car = load_car(ACTIVE_CAR_FILE)
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
    key = hashlib.sha256((ACTIVE_CAR_FILE.read_text(encoding="utf-8") + track_path.read_text(encoding="utf-8")
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
    spec = json.loads(resolve(rival_file).read_text(encoding="utf-8"))
    data, cached = distributions(spec["track"])          # STOCK car: rivals don't track upgrades
    # Base time: where the player's BEST odds (over all push levels) equal the
    # target. Each push level reaches the target at its own quantile; the best
    # odds first reach it at the earliest (smallest) of those times.
    base = min(quantile(d["times"], spec["best_push_odds"]) for d in data.values())
    posted = base + random.Random(seed).gauss(0.0, spec["nightly_spread_s"])
    reply(id=spec["id"], name=spec["name"], car=spec["car"], club=spec["club"],
          track=spec["track"], payout=spec["payout"], base_time=round(base, 3),
          posted_time=round(posted, 3), seed=seed, cached=cached)


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
    """A random street racer on this week's open road. Like the rival, the
    posted time is anchored to the STOCK car on this road."""
    import random
    track, style = open_road(week)
    spec = json.loads((ROOT / "data" / "street_racers.json").read_text(encoding="utf-8"))
    rng = random.Random(seed)
    racer = rng.choice(spec["racers"])
    target = rng.uniform(*spec["best_push_odds"])        # some nights are easier than others
    data, cached = distributions(track)
    base = min(quantile(d["times"], target) for d in data.values())
    posted = base + rng.gauss(0.0, spec["nightly_spread_s"])
    reply(id="street", name=racer["name"], car=racer["car"], club=f"Open road, {style}",
          track=track, payout="even", base_time=round(base, 3), posted_time=round(posted, 3),
          seed=seed, week=week, style=style, cached=cached)


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


def race(track_file, push, seed, out_file, part_ids=()):
    from export_replay import build_replay
    from sim.car import load_car
    from sim.driver import Driver
    from sim.lap import run_lap
    from sim.track import discretize, load_track

    track_path = resolve(track_file)
    car = player_car(part_ids)
    segments = load_track(track_path)
    lap = run_lap(car, discretize(segments, GAME_DS), driver=Driver(push=push), seed=seed)
    replay_data = build_replay(car, segments, lap, track_path.name)
    out = Path(out_file)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(replay_data, separators=(",", ":")), encoding="utf-8")
    reply(lap_time=round(lap.lap_time, 3), push=push, seed=seed, replay=str(out),
          mistakes=[c.text for c in lap.corner_log if c.mistake])


def main():
    global ACTIVE_CAR_FILE
    ap = argparse.ArgumentParser(description="deadtildawn game bridge")
    ap.add_argument("command", choices=["parts", "shop_catalog", "pull", "car_stats", "track", "rival", "street",
                                        "practice", "odds", "race", "local_straight", "local_curves", "time_attack"])
    ap.add_argument("--car", choices=["reference", "game"], default="reference",
                    help="reference EJ6 for engineering tools (default), game EG6 for Godot")
    ap.add_argument("--week", type=int)
    ap.add_argument("--source")
    ap.add_argument("--pity", default="{}")
    ap.add_argument("--parts", default="", help="installed part ids, comma-separated")
    ap.add_argument("--track")
    ap.add_argument("--rival")
    ap.add_argument("--posted", type=float)
    ap.add_argument("--push")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--out")
    ap.add_argument("--player-out")
    ap.add_argument("--rival-out")
    ap.add_argument("--rival-profile", default=str(LOCAL_RIVAL_FILE))
    a = ap.parse_args()
    ACTIVE_CAR_FILE = GAME_CAR if a.car == "game" else REFERENCE_CAR
    try:
        part_ids = parse_parts(a.parts)
        if a.command == "parts":
            parts_catalog()
        elif a.command == "shop_catalog":
            shop_catalog()
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
            race(a.track, a.push, a.seed, a.out, part_ids)
        elif a.command == "local_straight":
            local_straight(a.out, part_ids)
        elif a.command == "local_curves":
            local_curves(a.out, part_ids)
        elif a.command == "time_attack":
            if not a.player_out or not a.rival_out:
                raise ValueError("time_attack requires --player-out and --rival-out")
            time_attack(a.player_out, a.rival_out, part_ids, resolve(a.rival_profile))
    except Exception as e:                         # report, don't crash the game
        fail(f"{type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
