"""Monte Carlo: many runs of the same car, track and driver with different
random seeds, to get the distribution of times and the odds against a rival.
See docs/PHYSICS.md section 6."""
import statistics
from dataclasses import dataclass

from .lap import run_lap


@dataclass
class Distribution:
    push: str
    times: list           # s, one per run
    mistakes: list        # bool per run: at least one mistake in that run

    @property
    def mean(self):
        return statistics.mean(self.times)

    @property
    def stdev(self):
        return statistics.stdev(self.times) if len(self.times) > 1 else 0.0

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
        times.append(lap.lap_time)
        mistakes.append(any(c.mistake for c in lap.corner_log))
    return Distribution(driver.push, times, mistakes)
