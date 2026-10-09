"""Shared longitudinal dynamics for every solver.

- drive_accel:  acceleration under power (shift / power-limited / wheelspin)
- brake_decel:  grip-limited braking deceleration
- advance:      move the car a distance under power, splitting the step
                exactly at events (fuel cut, end of a shift)

See docs/PHYSICS.md sections 4 and 5.
"""
from dataclasses import dataclass

from .forces import (axle_grip, axle_loads, drag, max_lateral_accel,
                     road_axle_loads, road_rolling_resistance, road_traction_limit_fwd,
                     rolling_resistance, static_mu, traction_limit_fwd_ls)
from .powertrain import (effective_mass, is_clutch_slipping, overall_ratio,
                         rpm_from_speed, speed_from_rpm, wheel_force)
from .brakes import pad_mu
from .telemetry import ShiftEvent
from .units import AMBIENT_C, G

RPM_EPS = 1e-6       # tolerance for "at the fuel cut" after an exact event step
MIN_SUBSTEP = 1e-9   # m, guards against zero-length steps


@dataclass(frozen=True)
class CarConstants:
    """Per-car values that don't change during a run (computed once)."""
    mu: float          # tire friction at static load (starting guesses only)
    a_lat: float       # m/s^2, max steady cornering acceleration (skidpad)
    f_traction: float  # N, FWD traction limit (load-sensitive front tires)
    f_roll: float      # N, rolling resistance
    m_free: float      # kg, body + 2 free wheels (driven side decoupled)
    m_brake: float     # kg, body + 4 wheels (clutch in while braking)
    f_brake_cap: float  # N, cold front brake capacity (hardware limit)


def car_constants(car):
    mu = static_mu(car)
    r2 = car.wheel_radius ** 2
    f_roll = rolling_resistance(car)
    m_brake = effective_mass(car, 1, engine_coupled=False)

    # Brake capacity: capacity_ratio x the front grip at cold max braking from
    # rest (fixed point without any capacity limit).
    a = mu * G
    for _ in range(100):
        front, rear = axle_loads(car, -a)
        a_new = (axle_grip(car, front) + axle_grip(car, rear) + f_roll) / m_brake
        if abs(a_new - a) < 1e-12:
            break
        a = a_new
    front_grip_ref = axle_grip(car, axle_loads(car, -a_new)[0])

    return CarConstants(
        mu=mu,
        a_lat=max_lateral_accel(car),
        f_traction=traction_limit_fwd_ls(car),
        f_roll=f_roll,
        m_free=car.mass + 2 * car.wheel_inertia / r2,
        m_brake=m_brake,
        f_brake_cap=car.brake_capacity * front_grip_ref,
    )


@dataclass
class DriveState:
    v: float = 0.0          # m/s
    gear: int = 1
    shift_left: float = 0.0  # s remaining in the current shift


# ---------------------------------------------------------------- decisions

def should_upshift(car, v, gear):
    """Shift when the next gear makes more wheel force, or at the fuel cut."""
    if gear >= len(car.gear_ratios):
        return False
    if rpm_from_speed(car, v, gear) >= car.fuel_cut - RPM_EPS:
        return True
    return wheel_force(car, v, gear + 1) > wheel_force(car, v, gear)


def should_downshift(car, v, gear):
    """Sequential downshift: one gear at a time, only if the lower gear makes
    more wheel force AND the engine lands at or below redline in it.
    Landing above redline is a "money shift": the wheels over-rev the engine
    and the fuel cut can't stop it."""
    if gear <= 1:
        return False
    if rpm_from_speed(car, v, gear - 1) > car.redline:
        return False
    return wheel_force(car, v, gear - 1) > wheel_force(car, v, gear)


# ---------------------------------------------------------------- physics

def spin_absorption(car, gear, engine_coupled):
    """Equivalent mass [kg] spun up by the driven wheels: the two driven
    wheels, plus the engine if the clutch is locked (PHYSICS.md 4.5)."""
    r2 = car.wheel_radius ** 2
    m = 2 * car.wheel_inertia / r2
    if engine_coupled:
        m += car.engine_inertia * overall_ratio(car, gear) ** 2 / r2
    return m


def road_resistance(car, k, v, road=None):
    """Tangential drag, tire rolling loss, and gravity (once each)."""
    if road is None:
        return drag(car, v) + k.f_roll
    return drag(car, v) + road_rolling_resistance(car, road, v) + car.mass * G * road.sin_angle


def drive_accel(car, k, v, gear, shifting, road=None):
    """Acceleration [m/s^2] under full throttle, and what limits it."""
    resist = road_resistance(car, k, v, road)
    if shifting:
        return -resist / effective_mass(car, gear, engine_coupled=False), "shift"

    coupled = not is_clutch_slipping(car, v, gear)
    f_engine = wheel_force(car, v, gear)
    a = (f_engine - resist) / effective_mass(car, gear, engine_coupled=coupled)
    f_tire = f_engine - spin_absorption(car, gear, coupled) * a
    traction = k.f_traction if road is None else road_traction_limit_fwd(car, road, v)
    if f_tire > traction:
        return (traction - resist) / k.m_free, "traction"
    return a, "power"


def front_brake_capacity(car, k, temp):
    """Max force [N] the front brakes can make at rotor temperature `temp`:
    cold capacity scaled by pad friction (PHYSICS.md 5.2, 5.3)."""
    return k.f_brake_cap * pad_mu(car, temp) / car.pad_mu


def brake_forces(car, k, v, temp=AMBIENT_C, tol=1e-10, road=None):
    """Max braking at speed v with front rotors at `temp` [C] (PHYSICS.md 5.1-5.3).

    Returns (decel, front_force, rear_force), decel positive [m/s^2].
    Each axle at its own grip limit (ideal bias) with forward load transfer and
    tire load sensitivity. The front is also capped by brake capacity, which
    drops as the pads fade. Drag and rolling resistance help slow the car.

    Deceleration sets the load transfer, which sets the grip, which sets the
    deceleration, so it is solved by fixed-point iteration from the static guess.
    """
    resist = road_resistance(car, k, v, road)
    cap = front_brake_capacity(car, k, temp)
    a = (k.mu * car.mass * G + resist) / k.m_brake
    for _ in range(100):
        front, rear = (axle_loads(car, -a) if road is None else
                       road_axle_loads(car, -a, road, v))
        f_front = min(axle_grip(car, front), cap)
        f_rear = axle_grip(car, rear)
        a_new = (f_front + f_rear + resist) / k.m_brake
        if abs(a_new - a) < tol:
            return a_new, f_front, f_rear
        a = a_new
    raise RuntimeError("brake_forces did not converge")


def brake_decel(car, k, v, temp=AMBIENT_C, road=None):
    """Max braking deceleration [m/s^2, positive]. See brake_forces."""
    return brake_forces(car, k, v, temp, road=road)[0]


# ---------------------------------------------------------------- stepping

def advance(car, k, st, dist, s0=0.0, events=None, road=None):
    """Advance the car `dist` meters at full throttle, starting at position s0.

    Splits the step exactly at events so results don't depend on step size:
      - reaching the fuel cut (then an upshift starts)
      - the end of a shift (then drive force resumes)

    Shift starts are appended to `events` (a list) if given.
    Returns (new_state, elapsed_time, limit_at_start, accel_at_start).
    """
    v, gear, shift_left = st.v, st.gear, st.shift_left
    remaining, elapsed, first_limit, first_a = dist, 0.0, None, 0.0

    for _ in range(10_000):
        if remaining <= MIN_SUBSTEP:
            break
        if shift_left <= 0:
            if should_upshift(car, v, gear):
                new_gear = gear + 1
            elif should_downshift(car, v, gear):      # kickdown under power
                new_gear = gear - 1
            else:
                new_gear = gear
            if new_gear != gear:
                if events is not None:
                    events.append(ShiftEvent(gear, new_gear, s0 + dist - remaining,
                                             v, rpm_from_speed(car, v, gear)))
                gear = new_gear
                shift_left = car.shift_time

        shifting = shift_left > 0
        a, limit = drive_accel(car, k, v, gear, shifting, road)
        if first_limit is None:
            first_limit, first_a = limit, a

        step = remaining
        v2 = v * v + 2 * a * step
        if v2 <= 0:
            raise RuntimeError("car stopped under power; check inputs")

        # Event: fuel cut reached inside this step
        if not shifting and a > 0:
            v_cut = speed_from_rpm(car, car.fuel_cut, gear)
            if v < v_cut < v2 ** 0.5:
                step = max((v_cut * v_cut - v * v) / (2 * a), MIN_SUBSTEP)
                v2 = v_cut * v_cut

        # Event: shift ends inside this step (constant accel: s = v t + a t^2 / 2)
        if shifting:
            s_end = v * shift_left + 0.5 * a * shift_left ** 2
            if MIN_SUBSTEP < s_end < step:
                step = s_end
                v2 = v * v + 2 * a * step

        v_new = v2 ** 0.5
        dt = 2 * step / (v + v_new)
        if shifting:
            shift_left = max(shift_left - dt, 0.0)
            if shift_left < 1e-12:
                shift_left = 0.0

        v = v_new
        elapsed += dt
        remaining -= step
    else:
        raise RuntimeError("advance() did not converge; too many sub-steps")

    return DriveState(v, gear, shift_left), elapsed, first_limit, first_a
