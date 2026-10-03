"""Parts: data-driven modifications to the car (data/parts/catalog.json).

apply_parts(car, parts) returns a NEW Car with the parts' effects applied;
the stock car is never modified. Every effect is a change to a real sim
input, so the physics decides what a part is worth on each road.
"""
import json
from dataclasses import replace
from pathlib import Path

CATALOG_FILE = Path(__file__).parent.parent / "data" / "parts" / "catalog.json"
RPM_LO, RPM_HI = 1000.0, 6800.0          # torque_shape endpoints

KNOWN_EFFECTS = {"torque_scale", "torque_shape", "mass_kg", "engine_inertia_scale",
                 "wheel_inertia_scale", "shift_time_s", "final_drive", "mu_scale",
                 "load_k_scale", "crr_scale", "roll_front", "cg_height_m"}


def load_catalog(path=CATALOG_FILE):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    parts = {p["id"]: p for p in data["parts"]}
    _check(data, parts)
    return data["slots"], parts


def _check(data, parts):
    """Fail fast on a bad catalog (typos would otherwise silently do nothing)."""
    if len(parts) != len(data["parts"]):
        raise ValueError("duplicate part ids in catalog")
    for p in parts.values():
        if p["slot"] not in data["slots"]:
            raise ValueError(f"{p['id']}: unknown slot {p['slot']!r}")
        unknown = set(p["effects"]) - KNOWN_EFFECTS
        if unknown:
            raise ValueError(f"{p['id']}: unknown effects {sorted(unknown)}")
        if p["price"] <= 0:
            raise ValueError(f"{p['id']}: price must be positive")


def shape_factor(shape, rpm):
    """Torque multiplier at rpm for a torque_shape effect (linear low -> high)."""
    x = min(max((rpm - RPM_LO) / (RPM_HI - RPM_LO), 0.0), 1.0)
    return 1.0 + shape["low"] + (shape["high"] - shape["low"]) * x


def apply_parts(car, part_list):
    """New Car with every part in part_list applied. One part per slot."""
    slots = [p["slot"] for p in part_list]
    if len(slots) != len(set(slots)):
        raise ValueError("two parts in the same slot")

    torque = list(car.torque_nm)
    mass = car.mass
    changes = {}
    for p in sorted(part_list, key=lambda p: p["id"]):      # deterministic order
        e = p["effects"]
        if "torque_scale" in e:
            torque = [t * e["torque_scale"] for t in torque]
        if "torque_shape" in e:
            torque = [t * shape_factor(e["torque_shape"], r) for t, r in zip(torque, car.torque_rpm)]
        mass += e.get("mass_kg", 0.0)
        if "engine_inertia_scale" in e:
            changes["engine_inertia"] = changes.get("engine_inertia", car.engine_inertia) * e["engine_inertia_scale"]
        if "wheel_inertia_scale" in e:
            changes["wheel_inertia"] = changes.get("wheel_inertia", car.wheel_inertia) * e["wheel_inertia_scale"]
        if "shift_time_s" in e:
            changes["shift_time"] = max(changes.get("shift_time", car.shift_time) + e["shift_time_s"], 0.05)
        if "final_drive" in e:
            changes["final_drive"] = e["final_drive"]
        if "mu_scale" in e:
            changes["mu_0"] = changes.get("mu_0", car.mu_0) * e["mu_scale"]
            # Scaling grip at EVERY load means scaling both terms of mu = mu0 - k*Fz
            changes["load_k"] = changes.get("load_k", car.load_k) * e["mu_scale"]
        if "load_k_scale" in e:
            changes["load_k"] = changes.get("load_k", car.load_k) * e["load_k_scale"]
        if "crr_scale" in e:
            changes["crr"] = changes.get("crr", car.crr) * e["crr_scale"]
        if "roll_front" in e:
            changes["roll_front"] = e["roll_front"]
        if "cg_height_m" in e:
            changes["cg_height"] = changes.get("cg_height", car.cg_height) + e["cg_height_m"]
    return replace(car, torque_nm=tuple(torque), mass=mass, **changes)


def parts_by_ids(ids, catalog=None):
    _, parts = catalog or load_catalog()
    missing = [i for i in ids if i not in parts]
    if missing:
        raise ValueError(f"unknown parts: {missing}")
    return [parts[i] for i in ids]
