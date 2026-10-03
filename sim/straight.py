"""Straight-line acceleration solver, integrated over distance.

Each step advances the car a fixed distance ds using constant-acceleration
kinematics:

    v_new^2 = v^2 + 2 * a * ds        (no division by v, so it works from rest)
    dt      = 2 * ds / (v + v_new)    (exact for constant acceleration)

Drive force each step = min(engine wheel force, traction limit), or zero
while a shift is in progress. See docs/PHYSICS.md section 4.
"""
from dataclasses import dataclass, field

from .forces import drag, rolling_resistance, static_mu, traction_limit_fwd
from .powertrain import engine_rpm, rpm_from_speed, wheel_force


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
    shifts: list = field(default_factory=list)


def should_upshift(car, v, gear):
    """Shift when the next gear makes more wheel force, or at the fuel cut."""
    if gear >= len(car.gear_ratios):
        return False
    if rpm_from_speed(car, v, gear) >= car.fuel_cut:
        return True
    return wheel_force(car, v, gear + 1) > wheel_force(car, v, gear)


def run_straight(car, distance, ds=0.1):
    """Full-throttle run from a standstill over `distance` meters."""
    mu = static_mu(car)
    f_traction = traction_limit_fwd(car, mu)
    f_roll = rolling_resistance(car)

    s = t = v = 0.0
    gear = 1
    shift_left = 0.0          # seconds remaining in the current shift
    tel = Telemetry()

    def record(a):
        tel.s.append(s)
        tel.t.append(t)
        tel.v.append(v)
        tel.gear.append(0 if shift_left > 0 else gear)
        tel.rpm.append(engine_rpm(car, v, gear))
        tel.accel.append(a)

    while s < distance:
        # Start a shift? Drive force drops to zero for shift_time seconds.
        if shift_left <= 0 and should_upshift(car, v, gear):
            tel.shifts.append(ShiftEvent(gear, s, v, rpm_from_speed(car, v, gear)))
            gear += 1
            shift_left = car.shift_time

        if shift_left > 0:
            f_drive = 0.0
        else:
            f_drive = min(wheel_force(car, v, gear), f_traction)

        a = (f_drive - drag(car, v) - f_roll) / car.mass
        record(a)

        v2 = v * v + 2 * a * ds
        if v2 <= 0:
            break                 # car stopped; can't happen under power on flat ground
        v_new = v2 ** 0.5
        dt = 2 * ds / (v + v_new)

        s += ds
        t += dt
        v = v_new
        if shift_left > 0:
            shift_left -= dt

    record(0.0)
    return tel
