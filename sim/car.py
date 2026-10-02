"""Load a car definition (JSON) into a Car object with SI values.

The JSON stores every number as {"value": ..., "source": ..., "confidence": ...}
so it can be traced. The Car object keeps only the numbers the physics needs.
"""
import json
from dataclasses import dataclass


def _v(entry):
    """Pull the number out of a {"value": ..., "source": ...} entry."""
    return entry["value"]


@dataclass(frozen=True)
class Car:
    id: str
    name: str
    mass: float            # kg, curb + driver + fuel
    wheelbase: float       # m
    weight_front: float    # fraction of static weight on front axle
    cg_height: float       # m
    torque_rpm: tuple      # rpm points of the torque curve
    torque_nm: tuple       # torque (N*m) at those points
    redline: float         # rpm, where the driver shifts
    fuel_cut: float        # rpm, hard limit (ECU cuts fuel)
    launch_rpm: float      # rpm held during clutch slip at launch
    gear_ratios: tuple     # 1st..5th
    final_drive: float
    drivetrain_eff: float
    shift_time: float      # s of zero drive force per shift
    wheel_radius: float    # m
    mu_0: float            # tire grip at zero load
    load_k: float          # grip lost per kN of tire load
    crr: float             # rolling resistance coefficient
    cd: float              # drag coefficient
    frontal_area: float    # m^2
    cla: float             # downforce area, m^2


def load_car(path):
    with open(path, encoding="utf-8") as f:
        d = json.load(f)

    m, geo, eng = d["mass"], d["geometry"], d["engine"]
    tr, ti, aero = d["transmission"], d["tires"], d["aero"]
    rpm, tq = zip(*eng["torque_curve"]["points"])

    car = Car(
        id=d["id"],
        name=d["name"],
        mass=_v(m["curb"]) + _v(m["driver"]) + _v(m["fuel"]),
        wheelbase=_v(geo["wheelbase"]),
        weight_front=_v(geo["weight_front_fraction"]),
        cg_height=_v(geo["cg_height"]),
        torque_rpm=tuple(rpm),
        torque_nm=tuple(tq),
        redline=_v(eng["redline"]),
        fuel_cut=_v(eng["fuel_cut"]),
        launch_rpm=_v(tr["launch_rpm"]),
        gear_ratios=tuple(_v(tr["gear_ratios"])),
        final_drive=_v(tr["final_drive"]),
        drivetrain_eff=_v(tr["efficiency"]),
        shift_time=_v(tr["shift_time"]),
        wheel_radius=_v(ti["radius"]),
        mu_0=_v(ti["mu_0"]),
        load_k=_v(ti["load_sensitivity_k"]),
        crr=_v(ti["rolling_resistance"]),
        cd=_v(aero["cd"]),
        frontal_area=_v(aero["frontal_area"]),
        cla=_v(aero["cla"]),
    )
    _check(car)
    return car


def _check(car):
    """Fail fast on bad data instead of producing silently wrong physics."""
    if list(car.torque_rpm) != sorted(car.torque_rpm):
        raise ValueError("torque curve rpm points must be in increasing order")
    if car.fuel_cut < car.redline:
        raise ValueError("fuel cut must be at or above redline")
    if list(car.gear_ratios) != sorted(car.gear_ratios, reverse=True):
        raise ValueError("gear ratios must decrease from 1st to top gear")
    if not 0 < car.weight_front < 1:
        raise ValueError("weight_front must be a fraction between 0 and 1")
