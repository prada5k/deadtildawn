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


def road_normal_force(car, road, speed):
    """Contact normal force on an unbanked 3D centerline [N]."""
    normal = car.mass * road.normal_accel(speed)
    if normal <= 0:
        raise RuntimeError("road contact lost; airborne motion is not modeled")
    return normal


def road_rolling_resistance(car, road, speed):
    return car.crr * road_normal_force(car, road, speed)


def road_axle_loads(car, a_long, road, speed):
    """Axle normals with slope gravity removed from longitudinal load transfer.

    Contact force, not the car's gravity acceleration, creates pitch transfer.
    Retaining the legacy drag/rolling approximation makes this exactly match
    axle_loads on a flat road.
    """
    normal = road_normal_force(car, road, speed)
    transfer = car.mass * (a_long + G * road.sin_angle) * car.cg_height / car.wheelbase
    return max(normal * car.weight_front - transfer, 0.0), max(normal * (1 - car.weight_front) + transfer, 0.0)


def road_traction_limit_fwd(car, road, speed, tol=1e-9):
    """FWD contact-force limit including road normal and rearward pitch transfer."""
    normal = road_normal_force(car, road, speed)
    force = axle_grip(car, normal * car.weight_front)
    for _ in range(200):
        front = max(normal * car.weight_front - force * car.cg_height / car.wheelbase, 0.0)
        new = axle_grip(car, front)
        if abs(new - force) < tol:
            return new
        force = new
    raise RuntimeError("road traction limit did not converge")


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


def lateral_tire_loads(car, a_y, normal_accel=G):
    """Normal loads [N] on (front outer, front inner, rear outer, rear inner)
    while cornering at lateral acceleration a_y [m/s^2] (PHYSICS.md 3.4).

    Total lateral transfer moment = m * a_y * h. The front axle takes its
    roll-stiffness share of it across the front track, the rear the rest.

    Wheel lift: an axle can transfer at most its whole inside-tire load. Once
    its inside wheel lifts, any extra roll moment goes to the other axle, so
    the four loads add up to the supplied road normal force.
    """
    w = car.mass * normal_accel
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


def lateral_grip(car, a_y, normal_accel=G):
    """Total lateral friction force [N] from four load-sensitive tires."""
    return sum(tire_mu(car, fz) * fz for fz in lateral_tire_loads(car, a_y, normal_accel))


def axle_lateral_caps(car, a_y, normal_accel=G):
    """Lateral acceleration [m/s^2] each axle could support at a_y.

    In steady cornering each axle must provide lateral force in proportion to
    the mass it carries (front: m * a_y * b/L). So an axle's cap is its grip
    divided by its share of the mass. Returns (front_cap, rear_cap).
    """
    fo, fi, ro, ri = lateral_tire_loads(car, a_y, normal_accel)
    grip_f = tire_mu(car, fo) * fo + tire_mu(car, fi) * fi
    grip_r = tire_mu(car, ro) * ro + tire_mu(car, ri) * ri
    return (grip_f / (car.mass * car.weight_front),
            grip_r / (car.mass * (1 - car.weight_front)))


def max_lateral_accel(car, tol=1e-10, normal_accel=G):
    """Steady-state cornering limit [m/s^2] with no aero: the skidpad number
    (PHYSICS.md 3.4).

    The car is limited by whichever axle saturates first: front first =
    understeer, rear first = oversteer. Grip depends on load transfer, which
    depends on a_y, so solve a_y = min(front_cap(a_y), rear_cap(a_y)) by
    fixed-point iteration.
    """
    if normal_accel <= 0:
        return 0.0
    a = static_mu(car) * normal_accel
    for _ in range(300):
        a_new = min(axle_lateral_caps(car, a, normal_accel))
        if abs(a_new - a) < tol:
            return a_new
        a = a_new
    raise RuntimeError("max_lateral_accel did not converge")


def limiting_axle(car):
    """'front' (understeer) or 'rear' (oversteer) at the cornering limit."""
    front_cap, rear_cap = axle_lateral_caps(car, max_lateral_accel(car))
    return "front" if front_cap <= rear_cap else "rear"


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
