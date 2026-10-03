"""Brake heat: pad friction vs temperature and rotor heating/cooling.

See docs/PHYSICS.md sections 5.2-5.4.
"""
import math


def pad_mu(car, temp):
    """Pad friction at rotor temperature `temp` [C]: flat up to fade onset,
    then falling linearly, never below the floor."""
    if temp <= car.pad_fade_temp:
        return car.pad_mu
    return max(car.pad_mu - car.pad_fade_rate * (temp - car.pad_fade_temp), car.pad_mu_min)


def cooling_ha(car, v):
    """Convective cooling h*A [W/K] for one rotor at speed v [m/s].
    More airflow at speed carries heat away faster (Newton's law of cooling)."""
    return car.cool_h0 + car.cool_h1 * v


def time_constant(car, v):
    """Cooling time constant tau = m*c / (h*A) [s]: time to shed ~63% of the
    rotor's excess heat with no braking."""
    return car.rotor_mass * car.rotor_c / cooling_ha(car, v)


def rotor_temp_after(car, temp, power, v, dt, ambient, cooling=True):
    """Rotor temperature after dt seconds of heating power [W] at speed v.

        m*c*dT/dt = P - hA*(T - T_amb)

    For constant P and v over the step, the exact solution is an exponential
    approach to T_inf = T_amb + P/hA. With cooling=False (hand-calc checks),
    all heat stays in the rotor: T += P*dt / (m*c).
    """
    if not cooling:
        return temp + power * dt / (car.rotor_mass * car.rotor_c)
    ha = cooling_ha(car, v)
    t_inf = ambient + power / ha
    return t_inf + (temp - t_inf) * math.exp(-dt / time_constant(car, v))
