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


def axle_loads(car, a_long):
    """Front and rear axle normal loads [N] with longitudinal load transfer.

    a_long > 0 accelerating (load moves rearward), < 0 braking (forward).
    Transfer = m * a * h / L  (PHYSICS.md 4.3, 5.1). Loads never go below 0.
    """
    w = car.mass * G
    transfer = car.mass * a_long * car.cg_height / car.wheelbase
    front = w * car.weight_front - transfer
    rear = w * (1 - car.weight_front) + transfer
    return max(front, 0.0), max(rear, 0.0)


def tire_mu(car, fz):
    """Load-sensitive friction for one tire carrying fz [N] (PHYSICS.md 3.3)."""
    return car.mu_0 - car.load_k * fz / 1000


def axle_grip(car, axle_load):
    """Max friction force [N] from one axle's two tires, load split evenly."""
    fz = axle_load / 2
    return 2 * tire_mu(car, fz) * fz


def lateral_tire_loads(car, a_y):
    """Normal loads [N] on (front outer, front inner, rear outer, rear inner)
    while cornering at lateral acceleration a_y [m/s^2] (PHYSICS.md 3.4).

    Total lateral transfer moment = m * a_y * h. The front axle takes its
    roll-stiffness share of it across the front track, the rear the rest.

    Wheel lift: an axle can transfer at most its whole inside-tire load. Once
    its inside wheel lifts, any extra roll moment goes to the other axle, so
    the four loads always add up to the car's weight.
    """
    w = car.mass * G
    front, rear = w * car.weight_front, w * (1 - car.weight_front)
    moment = car.mass * a_y * car.cg_height
    dwf = car.roll_front * moment / car.track_front
    dwr = (1 - car.roll_front) * moment / car.track_rear
    if dwr > rear / 2:                                   # rear inside wheel lifts
        dwf += (dwr - rear / 2) * car.track_rear / car.track_front
        dwr = rear / 2
    if dwf > front / 2:                                  # front inside wheel lifts
        dwr = min(dwr + (dwf - front / 2) * car.track_front / car.track_rear, rear / 2)
        dwf = front / 2
    return (front / 2 + dwf, front / 2 - dwf, rear / 2 + dwr, rear / 2 - dwr)


def lateral_grip(car, a_y):
    """Total lateral friction force [N] from four load-sensitive tires."""
    return sum(tire_mu(car, fz) * fz for fz in lateral_tire_loads(car, a_y))


def axle_lateral_caps(car, a_y):
    """Lateral acceleration [m/s^2] each axle could support at a_y.

    In steady cornering each axle must provide lateral force in proportion to
    the mass it carries (front: m * a_y * b/L). So an axle's cap is its grip
    divided by its share of the mass. Returns (front_cap, rear_cap).
    """
    fo, fi, ro, ri = lateral_tire_loads(car, a_y)
    grip_f = tire_mu(car, fo) * fo + tire_mu(car, fi) * fi
    grip_r = tire_mu(car, ro) * ro + tire_mu(car, ri) * ri
    return (grip_f / (car.mass * car.weight_front),
            grip_r / (car.mass * (1 - car.weight_front)))


def max_lateral_accel(car, tol=1e-10):
    """Steady-state cornering limit [m/s^2] with no aero: the skidpad number
    (PHYSICS.md 3.4).

    The car is limited by whichever axle saturates first: front first =
    understeer, rear first = oversteer. Grip depends on load transfer, which
    depends on a_y, so solve a_y = min(front_cap(a_y), rear_cap(a_y)) by
    fixed-point iteration.
    """
    a = static_mu(car) * G
    for _ in range(300):
        a_new = min(axle_lateral_caps(car, a))
        if abs(a_new - a) < tol:
            return a_new
        a = a_new
    raise RuntimeError("max_lateral_accel did not converge")


def limiting_axle(car):
    """'front' (understeer) or 'rear' (oversteer) at the cornering limit."""
    front_cap, rear_cap = axle_lateral_caps(car, max_lateral_accel(car))
    return "front" if front_cap <= rear_cap else "rear"


def traction_limit_rwd_ls(car, tol=1e-9):
    """RWD traction limit [N]: the driven REAR axle GAINS load as the car
    accelerates (PHYSICS.md 4.3: F = mu m g (a/L) / (1 - mu h / L) with
    constant mu). With load-sensitive tires, solve F = axle_grip(rear load at
    a = F/m) by fixed-point iteration."""
    f = static_mu(car) * car.mass * G * (1 - car.weight_front)
    for _ in range(200):
        _, rear = axle_loads(car, f / car.mass)
        f_new = axle_grip(car, rear)
        if abs(f_new - f) < tol:
            return f_new
        f = f_new
    raise RuntimeError("traction_limit_rwd_ls did not converge")


def traction_limit(car):
    """Traction limit of the driven axle [N] for this car's drivetrain."""
    return traction_limit_rwd_ls(car) if car.drivetrain == "RWD" else traction_limit_fwd_ls(car)


def traction_limit_fwd_ls(car, tol=1e-9):
    """FWD traction limit [N] with rearward load transfer AND per-tire load
    sensitivity on the front axle (PHYSICS.md 4.3, 3.3).

    Front axle load = m*g*(b/L) - m*a*h/L with a ~ F/m, so solve
    F = axle_grip(front_load(F)) by fixed-point iteration.
    """
    f = traction_limit_fwd(car, static_mu(car))
    for _ in range(200):
        front, _ = axle_loads(car, f / car.mass)
        f_new = axle_grip(car, front)
        if abs(f_new - f) < tol:
            return f_new
        f = f_new
    raise RuntimeError("traction_limit_fwd_ls did not converge")
