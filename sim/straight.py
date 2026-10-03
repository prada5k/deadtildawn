"""Straight-line acceleration solver, integrated over distance.

Each grid step advances the car ds meters with constant-acceleration
kinematics (v_new^2 = v^2 + 2 a ds), split exactly at shift events.
The physics lives in dynamics.py; this module just runs it from a standstill.
See docs/PHYSICS.md section 4.
"""
from .dynamics import DriveState, advance, car_constants
from .powertrain import engine_rpm
from .telemetry import Telemetry
from .units import AMBIENT_C


def run_straight(car, distance, ds=0.1):
    """Full-throttle run from a standstill over `distance` meters."""
    k = car_constants(car)
    st = DriveState()
    s = t = 0.0
    tel = Telemetry()

    while s < distance - 1e-9:
        step = min(ds, distance - s)
        new, dt, limit, a = advance(car, k, st, step, s0=s, events=tel.shifts)
        _record(tel, car, s, t, st, a, limit, 0.0 if limit == "shift" else 1.0)
        st, s, t = new, s + step, t + dt

    _record(tel, car, s, t, st, 0.0, "end", 1.0)
    return tel


def _record(tel, car, s, t, st, a, limit, throttle):
    tel.s.append(s)
    tel.t.append(t)
    tel.v.append(st.v)
    tel.gear.append(0 if st.shift_left > 0 else st.gear)
    tel.rpm.append(engine_rpm(car, st.v, st.gear))
    tel.accel.append(a)
    tel.limit.append(limit)
    tel.throttle.append(throttle)
    tel.brake.append(0.0)
    tel.brake_temp.append(AMBIENT_C)   # straight-line runs don't track brake heat
