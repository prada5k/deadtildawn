"""Engine and drivetrain: torque curve, RPM <-> speed, wheel force.

See docs/PHYSICS.md section 4.1.
"""
from .units import RPM_TO_RADS


def torque_at(car, rpm):
    """Engine torque [N*m] at a given rpm.

    - At or above fuel cut: 0 (ECU cuts fuel)
    - Below the first curve point: hold the first value
    - Between points: linear interpolation
    - Past the last point, up to fuel cut: extend the last segment's slope
      (extrapolation; the dyno chart ends before the fuel cut)
    """
    if rpm >= car.fuel_cut:
        return 0.0
    xs, ys = car.torque_rpm, car.torque_nm
    if rpm <= xs[0]:
        return ys[0]
    for i in range(1, len(xs)):
        if rpm <= xs[i]:
            t = (rpm - xs[i - 1]) / (xs[i] - xs[i - 1])
            return ys[i - 1] + t * (ys[i] - ys[i - 1])
    slope = (ys[-1] - ys[-2]) / (xs[-1] - xs[-2])
    return ys[-1] + slope * (rpm - xs[-1])


def overall_ratio(car, gear):
    """Gear ratio x final drive. Gear is 1-indexed, like a real shifter."""
    return car.gear_ratios[gear - 1] * car.final_drive


def rpm_from_speed(car, v, gear):
    """Engine rpm if the clutch is fully engaged. v in m/s."""
    return v / car.wheel_radius * overall_ratio(car, gear) / RPM_TO_RADS


def speed_from_rpm(car, rpm, gear):
    """Road speed [m/s] at a given engine rpm and gear."""
    return rpm * RPM_TO_RADS * car.wheel_radius / overall_ratio(car, gear)


def engine_rpm(car, v, gear):
    """Actual engine rpm, including clutch slip at launch.

    In 1st gear the driver holds launch rpm and slips the clutch until road
    speed catches up; after that the clutch is locked.
    """
    rpm = rpm_from_speed(car, v, gear)
    if gear == 1:
        return max(rpm, car.launch_rpm)
    return rpm


def wheel_force(car, v, gear):
    """Engine drive force at the contact patch [N].

    Does NOT include the traction limit; that is a separate cap.
    """
    rpm = engine_rpm(car, v, gear)
    return (torque_at(car, rpm) * overall_ratio(car, gear)
            * car.drivetrain_eff / car.wheel_radius)
