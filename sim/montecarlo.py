"""Monte Carlo: many runs of the same car, track and driver with different
random seeds, to get the distribution of times and the odds against a rival.
See docs/PHYSICS.md section 6."""
import statistics
from dataclasses import dataclass

import math

from .lap import finish_time, run_lap


@dataclass
class Distribution:
    push: str
    times: list           # s, one per run
    mistakes: list        # bool per run: at least one mistake in that run

    @property
    def finished(self):
        return [t for t in self.times if not math.isinf(t)]

    @property
    def dnf_rate(self):
        return 1 - len(self.finished) / len(self.times)

    @property
    def mean(self):
        """Mean of FINISHED runs (a DNF has no time)."""
        return statistics.mean(self.finished)

    @property
    def stdev(self):
        f = self.finished
        return statistics.stdev(f) if len(f) > 1 else 0.0

    @property
    def mistake_runs(self):
        return sum(self.mistakes)

    @property
    def mistake_rate(self):
        return self.mistake_runs / len(self.times)

    def win_probability(self, rival_time):
        """Fraction of runs faster than the rival's time."""
        return sum(t < rival_time for t in self.times) / len(self.times)


def run_many(car, grid, driver, n, seed0=0, temp_start=None):
    """n runs with seeds seed0 .. seed0 + n - 1 (reproducible)."""
    kwargs = {} if temp_start is None else {"temp_start": temp_start}
    times, mistakes = [], []
    for seed in range(seed0, seed0 + n):
        lap = run_lap(car, grid, driver=driver, seed=seed, **kwargs)
        times.append(finish_time(lap))           # inf for a DNF
        mistakes.append(any(c.mistake for c in lap.corner_log))
    return Distribution(driver.push, times, mistakes)
