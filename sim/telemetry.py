"""Telemetry containers shared by all solvers."""
from dataclasses import dataclass, field


@dataclass
class ShiftEvent:
    from_gear: int
    to_gear: int
    s: float     # m, where the shift started
    v: float     # m/s
    rpm: float   # engine rpm when the shift started


@dataclass
class Telemetry:
    s: list = field(default_factory=list)      # m
    t: list = field(default_factory=list)      # s
    v: list = field(default_factory=list)      # m/s
    gear: list = field(default_factory=list)   # 0 = mid-shift
    rpm: list = field(default_factory=list)
    accel: list = field(default_factory=list)  # m/s^2
    limit: list = field(default_factory=list)  # power/traction/shift/brake/corner
    throttle: list = field(default_factory=list)  # 0-1
    brake: list = field(default_factory=list)     # 0-1, fraction of max braking
    brake_temp: list = field(default_factory=list)  # C, front rotor
    shifts: list = field(default_factory=list)
