"""Read performance numbers out of telemetry, with linear interpolation
between steps so results don't depend on landing exactly on a step."""


def _interp(x0, x1, y0, y1, x):
    return y0 + (y1 - y0) * (x - x0) / (x1 - x0)


def time_to_speed(tel, v_target):
    """Time [s] when speed first reaches v_target [m/s], or None."""
    for i in range(1, len(tel.v)):
        if tel.v[i] >= v_target:
            return _interp(tel.v[i - 1], tel.v[i], tel.t[i - 1], tel.t[i], v_target)
    return None


def time_at_distance(tel, s_target):
    """Time [s] when the car reaches distance s_target [m], or None."""
    for i in range(1, len(tel.s)):
        if tel.s[i] >= s_target:
            return _interp(tel.s[i - 1], tel.s[i], tel.t[i - 1], tel.t[i], s_target)
    return None


def speed_at_distance(tel, s_target):
    """Speed [m/s] at distance s_target [m], or None."""
    for i in range(1, len(tel.s)):
        if tel.s[i] >= s_target:
            return _interp(tel.s[i - 1], tel.s[i], tel.v[i - 1], tel.v[i], s_target)
    return None


def top_speed(tel):
    return max(tel.v)
