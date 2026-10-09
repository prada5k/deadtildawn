"""Full-lap quasi-steady-state (QSS) solver.

1. Corner limits:   flat v_max = sqrt(a_lat * R); elevated roads solve
                    speed-dependent normal load and 3D path curvature
2. Backward pass:   braking envelope; the fastest speed at each node from which
                    the car can still brake down to every limit ahead of it
3. Forward pass:    full-throttle driving (dynamics.advance), capped by the
                    envelope. Where capped, the car is braking (brake pedal) or
                    holding the corner limit (partial throttle). Downshifts are
                    sequential, made while braking, never mid-corner. Front
                    rotor temperature is tracked along the way.
4. Iterate:         braking capacity depends on rotor temperature, which depends
                    on the braking before it, so passes 2-3 repeat with the last
                    temperature profile until the lap time stops changing
                    (fixed-point iteration, PHYSICS.md 5.4).

See docs/PHYSICS.md sections 2-5.
"""
import math
import random
from dataclasses import dataclass, field

from .brakes import rotor_temp_after
from .driver import apply_plan, plan_corners
from .dynamics import (DriveState, advance, brake_decel, brake_forces,
                       car_constants, road_resistance, should_downshift)
from .forces import max_lateral_accel
from .powertrain import effective_mass, engine_rpm, rpm_from_speed, wheel_force
from .telemetry import ShiftEvent, Telemetry
from .units import AMBIENT_C, G


@dataclass
class LapResult:
    telemetry: Telemetry
    lap_time: float      # s
    v_limit: list        # m/s, corner limit at each node (inf on straights)
    v_envelope: list     # m/s, corner limits + braking
    iterations: int = 1  # fixed-point passes until the lap time converged
    temp_end: float = AMBIENT_C   # C, front rotor at the finish
    driver: object = None         # Driver, or None for the theoretical limit
    seed: object = None           # random seed of this run (reproducible)
    corner_log: list = field(default_factory=list)   # CornerAttempt per corner


def corner_speed(k, curvature):
    """v_max = sqrt(a_lat * R) (PHYSICS.md 3.4): a_lat is the car's lateral
    limit with load transfer and load sensitivity. No limit on straights."""
    if curvature <= 0:
        return math.inf
    return math.sqrt(k.a_lat / curvature)


def elevated_corner_speed(car, curvature, road):
    """Solve lateral demand v²*k_xy*cos²(theta) against speed-dependent normal grip."""
    if curvature <= 0:
        return math.inf
    demand_coefficient = curvature * road.cos_angle ** 2

    def margin(speed):
        available = max_lateral_accel(car, normal_accel=max(0.0, road.normal_accel(speed)))
        return available - speed * speed * demand_coefficient

    lo, hi = 0.0, 10.0
    while margin(hi) > 0 and hi < 200.0:
        hi *= 2
    if margin(hi) > 0:
        return math.inf
    for _ in range(44):
        mid = (lo + hi) / 2
        if margin(mid) > 0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def braking_envelope(car, k, s, v_limit, temps, brake_scale=1.0, road_points=None):
    """Backward pass: walk from the end of the track toward the start.
    v_i^2 = v_(i+1)^2 + 2 * a_brake * d_path  (deceleration evaluated at v_(i+1),
    with the front rotors at the temperature expected at that node).
    brake_scale < 1: a driver braking at a fraction of the car's maximum."""
    env = list(v_limit)
    for i in range(len(s) - 2, -1, -1):
        v_next = env[i + 1]
        if math.isinf(v_next):
            continue
        road = None if road_points is None else road_points[i + 1]
        a = brake_decel(car, k, v_next, temps[i + 1], road=road) * brake_scale
        env[i] = min(env[i], math.sqrt(v_next ** 2 + 2 * a * (s[i + 1] - s[i])))
    return env


def run_lap(car, grid, temp_start=AMBIENT_C, ambient=AMBIENT_C, tol=1e-6, max_iter=20,
            driver=None, seed=None, plan=None):
    """Standing-start run over a discretized track, starting with the front
    rotors at temp_start (carry temperatures over for back-to-back runs).

    driver=None: the theoretical limit (validation runs). With a Driver, each
    corner gets a random attempt (reproducible from `seed`), or pass a fixed
    `plan` (list of CornerAttempt) to script one.
    """
    k = car_constants(car)
    road_points = (None if grid.elevation is None else
                   [grid.elevation.point(s) for s in grid.s])
    v_limit = ([corner_speed(k, c) for c in grid.curvature] if road_points is None else
               [elevated_corner_speed(car, c, road) for c, road in zip(grid.curvature, road_points)])
    brake_scale = 1.0
    if driver is not None:
        if plan is None:
            plan = plan_corners(driver, grid.corners, random.Random(seed))
        v_limit = apply_plan(grid, v_limit, plan)
        brake_scale = min(driver.f, 1.0)
    temps = [temp_start] * len(grid.s)       # first guess: rotors never heat up
    prev_time = None
    for it in range(1, max_iter + 1):
        distance_nodes = grid.s if road_points is None else grid.path_s
        env = braking_envelope(car, k, distance_nodes, v_limit, temps, brake_scale, road_points)
        result = _forward_pass(car, k, grid, v_limit, env, temp_start, ambient, road_points)
        result.iterations = it
        result.driver, result.seed, result.corner_log = driver, seed, plan or []
        if prev_time is not None and abs(result.lap_time - prev_time) < tol:
            return result
        prev_time, temps = result.lap_time, result.telemetry.brake_temp
    raise RuntimeError("run_lap: brake temperature iteration did not converge")


def _forward_pass(car, k, grid, v_limit, env, temp_start, ambient, road_points=None):
    s = grid.s
    distance_nodes = s if road_points is None else grid.path_s
    tel = Telemetry()
    st = DriveState()
    t = 0.0
    temp = temp_start

    for i in range(len(s) - 1):
        step = distance_nodes[i + 1] - distance_nodes[i]
        road = None if road_points is None else road_points[i]
        events = []
        new, dt, limit, a = advance(car, k, st, step, s0=distance_nodes[i],
                                    events=events, road=road)
        heat = 0.0   # W into one front rotor during this step

        if new.v > env[i + 1]:
            # Capped: braking for a corner ahead, or holding the corner limit
            v_next = env[i + 1]
            a = (v_next ** 2 - st.v ** 2) / (2 * step)
            dt = 2 * step / (st.v + v_next)
            gear, shift_left = st.gear, max(st.shift_left - dt, 0.0)
            resist = road_resistance(car, k, st.v, road)

            coast = resist / k.m_brake           # decel from drag + rolling alone
            if v_next < st.v - 1e-9 and -a > coast:
                # Slowing faster than coasting: brakes
                limit, throttle = "brake", 0.0
                a_max, f_front, f_rear = brake_forces(car, k, st.v, temp, road=road)
                # Fraction of max braking: (needed - coasting) / (max - coasting)
                brake = min(max((-a - coast) / (a_max - coast), 0.0), 1.0)
                # Brake force actually used, split front/rear like at the limit
                f_used = max(k.m_brake * -a - resist, 0.0)
                heat = f_used * f_front / (f_front + f_rear) * (st.v + v_next) / 2 / 2
                # Sequential downshift while braking (no mid-corner shifts)
                if shift_left <= 0 and should_downshift(car, v_next, gear):
                    tel.shifts.append(ShiftEvent(gear, gear - 1, s[i + 1], v_next,
                                                 rpm_from_speed(car, v_next, gear)))
                    gear, shift_left = gear - 1, car.shift_time
            else:
                # Holding or gently changing speed: partial throttle (feathering).
                # Gentle slowing (less than coasting) still needs SOME throttle.
                limit, brake = "corner", 0.0
                f_needed = effective_mass(car, gear) * a + resist
                f_avail = 0.0 if shift_left > 0 else wheel_force(car, st.v, gear)
                throttle = min(max(f_needed / f_avail, 0.0), 1.0) if f_avail > 0 else 0.0

            new = DriveState(v_next, gear, shift_left)
        else:
            if road_points is not None:
                for event in events:
                    event.s = grid.elevation.horizontal_at_path_offset(
                        s[i], s[i + 1], event.s - distance_nodes[i])
            tel.shifts.extend(events)   # only keep shifts that actually happened
            throttle, brake = (0.0 if limit == "shift" else 1.0), 0.0

        _record(tel, car, s[i], t, st, a, limit, throttle, brake, temp, road)
        temp = rotor_temp_after(car, temp, heat, (st.v + new.v) / 2, dt, ambient)
        st, t = new, t + dt

    _record(tel, car, s[-1], t, st, 0.0, "end", tel.throttle[-1], tel.brake[-1],
            temp, None if road_points is None else road_points[-1])
    return LapResult(tel, t, v_limit, env, temp_end=temp)


def _record(tel, car, s, t, st, a, limit, throttle, brake, temp, road=None):
    tel.s.append(s)
    if road is not None:
        tel.z.append(road.z)
        tel.grade.append(road.grade)
    tel.t.append(t)
    tel.v.append(st.v)
    tel.gear.append(0 if st.shift_left > 0 else st.gear)
    tel.rpm.append(engine_rpm(car, st.v, st.gear))
    tel.accel.append(a)
    tel.limit.append(limit)
    tel.throttle.append(throttle)
    tel.brake.append(brake)
    tel.brake_temp.append(temp)
