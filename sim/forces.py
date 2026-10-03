"""Resistive forces and the traction limit.

See docs/PHYSICS.md sections 3.3, 4.2, 4.3.
"""
from .units import G, RHO_AIR


def drag(car, v):
    """Aerodynamic drag [N] at speed v [m/s]: 1/2 * rho * Cd * A * v^2."""
    return 0.5 * RHO_AIR * car.cd * car.frontal_area * v * v


def rolling_resistance(car):
    """Rolling resistance [N]: Crr * m * g. Constant with speed in this model."""
    return car.crr * car.mass * G


def static_mu(car):
    """Tire mu at the static per-tire load (PHYSICS.md 3.3).

    Milestone A uses this as a constant. Milestone C makes mu respond to
    load transfer and downforce.
    """
    fz_kn = car.mass * G / 4 / 1000
    return car.mu_0 - car.load_k * fz_kn


def traction_limit_fwd(car, mu):
    """Max drive force [N] a FWD car can put down, with rearward load transfer.

    F_max = mu * m * g * (b/L) / (1 + mu * h/L)        (PHYSICS.md 4.3)

    b/L is the static front weight fraction. Assumes acceleration ~ F/m
    (drag neglected inside the load transfer term).
    """
    b_over_l = car.weight_front
    h_over_l = car.cg_height / car.wheelbase
    return mu * car.mass * G * b_over_l / (1 + mu * h_over_l)
