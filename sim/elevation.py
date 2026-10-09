"""C2 road elevation over horizontal (map) distance.

The clamped cubic spline has authored endpoint grades.  Its coordinate is the
same horizontal centerline distance used by pace notes and track_xy; vehicle
speed and acceleration are instead measured along the resulting 3D path.
"""
from bisect import bisect_right
from dataclasses import dataclass
import math

from .units import G


@dataclass(frozen=True)
class RoadPoint:
    z: float                  # elevation, m
    grade: float              # dz / d(horizontal distance)
    grade_change: float       # d²z / d(horizontal distance)², 1/m

    @property
    def cos_angle(self):
        return 1.0 / math.sqrt(1.0 + self.grade * self.grade)

    @property
    def sin_angle(self):
        return self.grade * self.cos_angle

    @property
    def vertical_curvature(self):
        # d(theta) / d(3D arc length); negative at a crest.
        return self.grade_change * self.cos_angle ** 3

    def normal_accel(self, speed):
        """Road-normal acceleration N/m, including crest/compression loading."""
        return G * self.cos_angle + speed * speed * self.vertical_curvature


class ElevationProfile:
    """Clamped cubic spline through (horizontal distance, elevation) samples."""

    # Fifth-order Gauss-Legendre integration on each spline interval.
    _NODES = (0.0, -0.5384693101056831, 0.5384693101056831,
              -0.9061798459386640, 0.9061798459386640)
    _WEIGHTS = (0.5688888888888889, 0.4786286704993665, 0.4786286704993665,
                0.2369268850561891, 0.2369268850561891)

    def __init__(self, samples, start_grade=0.0, end_grade=0.0, max_grade=0.12):
        if not isinstance(samples, (list, tuple)) or len(samples) < 2:
            raise ValueError("elevation requires at least two samples")
        self.samples = tuple((float(s), float(z)) for s, z in samples)
        if any(not math.isfinite(v) for pair in self.samples for v in pair):
            raise ValueError("elevation samples must be finite")
        if self.samples[0][0] != 0 or any(b[0] <= a[0] for a, b in zip(self.samples, self.samples[1:])):
            raise ValueError("elevation distances must start at zero and increase strictly")
        if not all(math.isfinite(v) for v in (start_grade, end_grade, max_grade)) or max_grade <= 0:
            raise ValueError("endpoint grades and grade limit must be finite")
        self.start_grade, self.end_grade = float(start_grade), float(end_grade)
        self.length = self.samples[-1][0]
        xs = [p[0] for p in self.samples]
        ys = [p[1] for p in self.samples]
        h = [b - a for a, b in zip(xs, xs[1:])]
        delta = [(b - a) / width for a, b, width in zip(ys, ys[1:], h)]
        n = len(xs)
        lower, diagonal, upper, rhs = [0.0] * n, [0.0] * n, [0.0] * n, [0.0] * n
        diagonal[0], upper[0], rhs[0] = 2 * h[0], h[0], 6 * (delta[0] - self.start_grade)
        for i in range(1, n - 1):
            lower[i], diagonal[i], upper[i] = h[i - 1], 2 * (h[i - 1] + h[i]), h[i]
            rhs[i] = 6 * (delta[i] - delta[i - 1])
        lower[-1], diagonal[-1], rhs[-1] = h[-1], 2 * h[-1], 6 * (self.end_grade - delta[-1])
        for i in range(1, n):
            factor = lower[i] / diagonal[i - 1]
            diagonal[i] -= factor * upper[i - 1]
            rhs[i] -= factor * rhs[i - 1]
        second = [0.0] * n
        second[-1] = rhs[-1] / diagonal[-1]
        for i in range(n - 2, -1, -1):
            second[i] = (rhs[i] - upper[i] * second[i + 1]) / diagonal[i]
        self._x = tuple(xs)
        self._coeff = tuple((ys[i], delta[i] - h[i] * (2 * second[i] + second[i + 1]) / 6,
                             second[i] / 2, (second[i + 1] - second[i]) / (6 * h[i]))
                            for i in range(n - 1))
        for i, width in enumerate(h):
            _, b, c, d = self._coeff[i]
            positions = [0.0, width]
            if d != 0 and 0 < -c / (3 * d) < width:
                positions.append(-c / (3 * d))
            if max(abs(b + 2 * c * t + 3 * d * t * t) for t in positions) > max_grade + 1e-12:
                raise ValueError(f"elevation interval {i + 1} exceeds grade limit {max_grade}")

    def point(self, s):
        if not math.isfinite(s) or s < -1e-9 or s > self.length + 1e-9:
            raise ValueError(f"elevation distance {s} outside [0, {self.length}]")
        s = min(max(s, 0.0), self.length)
        i = min(bisect_right(self._x, s) - 1, len(self._coeff) - 1)
        t = s - self._x[i]
        a, b, c, d = self._coeff[i]
        return RoadPoint(a + t * (b + t * (c + t * d)),
                         b + t * (2 * c + 3 * d * t), 2 * c + 6 * d * t)

    def path_length(self, start, end):
        """3D traveled length over a horizontal-distance interval."""
        if start < 0 or end > self.length + 1e-9 or end < start:
            raise ValueError("invalid elevation path-length interval")
        total = 0.0
        while start < end - 1e-12:
            i = min(bisect_right(self._x, start) - 1, len(self._coeff) - 1)
            stop = min(end, self._x[i + 1])
            mid, half = (start + stop) / 2, (stop - start) / 2
            total += half * sum(w * math.hypot(1.0, self.point(mid + half * x).grade)
                                for x, w in zip(self._NODES, self._WEIGHTS))
            start = stop
        return total

    def horizontal_at_path_offset(self, start, end, offset):
        """Map a shift's path-distance offset back to the replay/map coordinate."""
        lo, hi = start, end
        for _ in range(36):
            mid = (lo + hi) / 2
            if self.path_length(start, mid) < offset:
                lo = mid
            else:
                hi = mid
        return (lo + hi) / 2
