"""Straight-line braking tests: single stops and the repeated-stop fade test.

See docs/PHYSICS.md sections 5.1-5.4.
"""
import math
from dataclasses import dataclass

from .brakes import rotor_temp_after
from .dynamics import brake_forces, car_constants
from .metrics import time_to_speed
from .straight import run_straight
from .units import AMBIENT_C


@dataclass
class StopResult:
    distance: float    # m
    time: float        # s
    temp_start: float  # C, front rotor
    temp_end: float    # C, front rotor


def brake_stop(car, v0, temp=AMBIENT_C, ds=0.01, ambient=AMBIENT_C, cooling=True):
    """Max braking from v0 [m/s] to rest, tracking front rotor temperature.

    Each step: braking forces at the current speed and rotor temperature, then
    heat into one front rotor = front brake force x speed / 2, over the step's
    time. The final step is solved exactly (s = v^2 / 2a).
    """
    k = car_constants(car)
    v, s, t, temp0 = v0, 0.0, 0.0, temp
    while v > 0:
        a, f_front, _ = brake_forces(car, k, v, temp)
        step = ds
        v2 = v * v - 2 * a * step
        if v2 <= 0:
            step, v2 = v * v / (2 * a), 0.0
        v_new = math.sqrt(v2)
        dt = 2 * step / (v + v_new)
        power = f_front * (v + v_new) / 2 / 2          # one of two front rotors
        temp = rotor_temp_after(car, temp, power, (v + v_new) / 2, dt, ambient, cooling)
        v, s, t = v_new, s + step, t + dt
    return StopResult(s, t, temp0, temp)


def stopping_distance(car, v0, ds=0.01, temp=AMBIENT_C):
    """Distance [m] to stop from v0 [m/s] with rotors starting at `temp`."""
    return brake_stop(car, v0, temp=temp, ds=ds).distance


def cool_while_accelerating(car, temp, v0, ambient=AMBIENT_C):
    """Accelerate from rest back to v0 at full throttle; return the rotor
    temperature at the end (airflow cools the rotors, no braking heat)."""
    tel = run_straight(car, 2000, ds=0.5)
    t_end = time_to_speed(tel, v0)
    for i in range(1, len(tel.t)):
        if tel.t[i - 1] >= t_end:
            break
        dt = min(tel.t[i], t_end) - tel.t[i - 1]
        temp = rotor_temp_after(car, temp, 0.0, (tel.v[i - 1] + tel.v[i]) / 2, dt, ambient)
    return temp, t_end


def repeated_stops(car, n, v0, cooling=True, ambient=AMBIENT_C):
    """Fade test: n max-braking stops from v0, back to back.

    cooling=True:  like a magazine test; after each stop, accelerate straight
                   back to v0 (airflow cools the rotors on the way)
    cooling=False: worst case; all heat stays in the rotors (hand-calc check)
    """
    temp, stops = ambient, []
    for _ in range(n):
        stop = brake_stop(car, v0, temp=temp, ambient=ambient, cooling=cooling)
        stops.append(stop)
        temp = stop.temp_end
        if cooling:
            temp, _ = cool_while_accelerating(car, temp, v0, ambient)
    return stops
