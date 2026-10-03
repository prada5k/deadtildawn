"""Straight-line acceleration solver, integrated over distance.

Each step advances the car a fixed distance ds using constant-acceleration
kinematics:

    v_new^2 = v^2 + 2 * a * ds        (no division by v, so it works from rest)
    dt      = 2 * ds / (v + v_new)    (exact for constant acceleration)

Acceleration each step comes from one of three cases (PHYSICS.md 4.5):
  - shifting:  no drive force, engine decoupled
  - grip OK:   a = (F_engine - resistance) / m_eff
  - wheelspin: tires at the traction limit, engine and driven wheels decoupled
"""
from dataclasses import dataclass, field

from .forces import drag, rolling_resistance, static_mu, traction_limit_fwd
from .powertrain import (effective_mass, engine_rpm, is_clutch_slipping,
                         overall_ratio, rpm_from_speed, speed_from_rpm,
                         wheel_force)

RPM_EPS = 1e-6   # tolerance for "at the fuel cut" after an exact event step


@dataclass
class ShiftEvent:
    from_gear: int
    s: float     # m, where the shift started
    v: float     # m/s
    rpm: float   # engine rpm when the shift started


@dataclass
class Telemetry:
    s: list = field(default_factory=list)      # m
    t: list = field(default_factory=list)      # s
    v: list = field(default_factory=list)      # m/s
    gear: list = field(default_factory=list)   # 0 = mid-shift
    rpm: list = field(default_factory=list)
    accel: list = field(default_factory=list)  # m/s^2
    limit: list = field(default_factory=list)  # "power", "traction", or "shift"
    shifts: list = field(default_factory=list)


def should_upshift(car, v, gear):
    """Shift when the next gear makes more wheel force, or at the fuel cut."""
    if gear >= len(car.gear_ratios):
        return False
    if rpm_from_speed(car, v, gear) >= car.fuel_cut - RPM_EPS:
        return True
    return wheel_force(car, v, gear + 1) > wheel_force(car, v, gear)


def spin_absorption(car, gear, engine_coupled):
    """Equivalent mass [kg] of the parts spun up by the driven wheels:
    the two driven wheels, plus the engine if the clutch is locked.
    Force absorbed = this x a, so the tires transmit F_engine - this x a."""
    r2 = car.wheel_radius ** 2
    m = 2 * car.wheel_inertia / r2
    if engine_coupled:
        m += car.engine_inertia * overall_ratio(car, gear) ** 2 / r2
    return m


def run_straight(car, distance, ds=0.1):
    """Full-throttle run from a standstill over `distance` meters."""
    mu = static_mu(car)
    f_traction = traction_limit_fwd(car, mu)
    f_roll = rolling_resistance(car)
    # Mass the car has when the driven side is decoupled: body + 2 free-rolling wheels
    m_free = car.mass + 2 * car.wheel_inertia / car.wheel_radius ** 2

    s = t = v = 0.0
    gear = 1
    shift_left = 0.0          # seconds remaining in the current shift
    tel = Telemetry()

    def record(a, limit):
        tel.s.append(s)
        tel.t.append(t)
        tel.v.append(v)
        tel.gear.append(0 if shift_left > 0 else gear)
        tel.rpm.append(engine_rpm(car, v, gear))
        tel.accel.append(a)
        tel.limit.append(limit)

    while s < distance:
        # Start a shift? Drive force drops to zero for shift_time seconds.
        if shift_left <= 0 and should_upshift(car, v, gear):
            tel.shifts.append(ShiftEvent(gear, s, v, rpm_from_speed(car, v, gear)))
            gear += 1
            shift_left = car.shift_time

        resist = drag(car, v) + f_roll

        if shift_left > 0:
            a = -resist / effective_mass(car, gear, engine_coupled=False)
            limit = "shift"
        else:
            coupled = not is_clutch_slipping(car, v, gear)
            f_engine = wheel_force(car, v, gear)
            a = (f_engine - resist) / effective_mass(car, gear, engine_coupled=coupled)
            f_tire = f_engine - spin_absorption(car, gear, coupled) * a
            if f_tire > f_traction:
                a = (f_traction - resist) / m_free
                limit = "traction"
            else:
                limit = "power"

        record(a, limit)

        step = ds
        v2 = v * v + 2 * a * step
        if v2 <= 0:
            break                 # car stopped; can't happen under power on flat ground

        # Event detection: if this step would carry the engine past the fuel
        # cut, shorten it to land exactly on the cut (constant-accel kinematics:
        # step = (v_cut^2 - v^2) / 2a). The shift then starts next iteration.
        if shift_left <= 0 and a > 0:
            v_cut = speed_from_rpm(car, car.fuel_cut, gear)
            if v < v_cut < v2 ** 0.5:
                step = (v_cut * v_cut - v * v) / (2 * a)
                v2 = v_cut * v_cut

        v_new = v2 ** 0.5
        dt = 2 * step / (v + v_new)

        s += step
        t += dt
        v = v_new
        if shift_left > 0:
            shift_left -= dt

    record(0.0, "end")
    return tel