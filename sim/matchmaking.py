"""Matchmaking: pick tonight's opponent for the player's car and tune him.

Game design (Spire, Oct 2026): a well-played night should be about a coin
flip. Street racers are MATCHED to the player's car (closest power-to-weight)
and TUNED each night: the opponent's engine condition is set so the player's
best push level has `target` odds. Rivals use the same tuning, but only after
the player beats them (sim stays pure: the game decides when).

Tuning, step by step:
  1. Run the player's car at every push level (fixed seeds).
  2. Run the opponent at a COARSE ladder of engine conditions (0.35-2.2).
  3. odds(c) = the player's BEST push level vs the opponent at condition c
     (head_to_head compares every pair of runs). A stronger engine (higher c)
     means a faster opponent, so odds fall as c rises.
  4. Find the two rungs that bracket the target, then run a FINE ladder
     between them and interpolate linearly there. Why two passes: run-to-run
     spreads are only ~0.1 s while the engine moves the opponent ~1.3 s per
     0.1 of condition, so the odds fall from ~1 to ~0 over a condition window
     only ~0.04 wide (the "odds cliff"). A coarse rung spacing alone lands
     anywhere on that cliff.

Steps 1-2 and the fine ladder are independent runs, so they go to one process
pool in parallel (each job is one run_many call). Same seeds -> same answer on
every machine.
"""
import os
from concurrent.futures import ProcessPoolExecutor

from .driver import PUSH_LEVELS, Driver
from .montecarlo import run_many
from .opponents import head_to_head, opponent_car, opponent_driver
from .powertrain import torque_at
from .units import RPM_TO_RADS

TUNE_RUNS = 40                     # Monte Carlo runs per job
COARSE = [0.35 * (2.2 / 0.35) ** (i / 11) for i in range(12)]   # 0.35 .. 2.2, log spaced
FINE_RUNGS = 12
PLAYER_SEED = 5000
OPPONENT_SEED = 7000
MATCH_CHOICES = 3                  # pick among this many closest opponents


def peak_power_w(car):
    """Peak engine power (W), sampled every 25 rpm up to the fuel cut."""
    return max(torque_at(car, r) * r * RPM_TO_RADS for r in range(1000, int(car.fuel_cut), 25))


def power_to_weight(car):
    return peak_power_w(car) / car.mass


def match_opponent(player, base, specs, rng, choices=MATCH_CHOICES):
    """Opponent id whose car (as authored, condition 1) is closest to the
    player's power-to-weight; random among the `choices` closest.
    specs: {id: spec}."""
    target = power_to_weight(player)
    ranked = sorted(specs, key=lambda oid: abs(
        power_to_weight(opponent_car(base, dict(specs[oid], condition=1.0))) - target))
    return rng.choice(ranked[:choices])


def _times(job):
    """One Monte Carlo job (module level so the process pool can pickle it)."""
    car, grid, driver, n, seed0 = job
    return run_many(car, grid, driver, n, seed0=seed0).times


class _Runner:
    """Runs jobs in a shared process pool (or inline when parallel=False)."""

    def __init__(self, parallel):
        self.pool = ProcessPoolExecutor(max_workers=os.cpu_count() or 1) if parallel else None

    def run(self, jobs):
        return list(self.pool.map(_times, jobs)) if self.pool else [_times(j) for j in jobs]

    def close(self):
        if self.pool:
            self.pool.shutdown()


def _curve(runner, player_times, base, spec, grid, runs, ladder):
    jobs = [(opponent_car(base, dict(spec, condition=c)), grid, opponent_driver(spec), runs, OPPONENT_SEED)
            for c in ladder]
    return [(c, max(head_to_head(pt, opp) for pt in player_times))
            for c, opp in zip(ladder, runner.run(jobs))]


def condition_for_odds(curve, target):
    """Engine condition where the odds curve crosses `target` (linear
    interpolation between rungs). Clamped to the ladder's ends."""
    if curve[0][1] <= target:
        return curve[0][0]                 # even the weakest engine is too strong for us
    for (c0, o0), (c1, o1) in zip(curve, curve[1:]):
        if o0 > target >= o1:
            return c0 + (c1 - c0) * (o0 - target) / (o0 - o1)
    return curve[-1][0]                    # even the strongest engine can't stop us


def bracket(curve, target):
    """The two rungs around the first crossing of `target` (or the end rungs)."""
    for (c0, o0), (c1, o1) in zip(curve, curve[1:]):
        if o0 > target >= o1:
            return c0, c1
    return (curve[0][0], curve[0][0]) if curve[0][1] <= target else (curve[-1][0], curve[-1][0])


def tune(player, base, spec, grid, target, runs=TUNE_RUNS, parallel=True):
    """(condition, fine curve) so the player's best push wins with ~target odds."""
    runner = _Runner(parallel)
    try:
        player_times = runner.run([(player, grid, Driver(push=p), runs, PLAYER_SEED) for p in PUSH_LEVELS])
        coarse = _curve(runner, player_times, base, spec, grid, runs, COARSE)
        lo, hi = bracket(coarse, target)
        if lo == hi:
            return round(lo, 4), coarse
        fine = [lo + (hi - lo) * i / (FINE_RUNGS - 1) for i in range(FINE_RUNGS)]
        curve = _curve(runner, player_times, base, spec, grid, runs, fine)
        return round(condition_for_odds(curve, target), 4), curve
    finally:
        runner.close()


def measure_odds(player, base, spec, grid, runs=200, seed0=100000, batches=8, parallel=True):
    """Best-push odds for the player vs this opponent, from a big FRESH sample
    (runs per side, split into batches so it runs in parallel). For checking a
    tuning or a calibration, never for setting one: 40-run estimates near the
    odds cliff wander by +-0.1 or more."""
    n = runs // batches
    runner = _Runner(parallel)
    try:
        jobs = [(player, grid, Driver(push=p), n, seed0 + 1000 * b) for p in PUSH_LEVELS for b in range(batches)]
        jobs += [(opponent_car(base, spec), grid, opponent_driver(spec), n, seed0 + 500000 + 1000 * b)
                 for b in range(batches)]
        res = runner.run(jobs)
    finally:
        runner.close()
    k = len(PUSH_LEVELS) * batches
    opp = [t for r in res[k:] for t in r]
    return max(head_to_head([t for r in res[i * batches:(i + 1) * batches] for t in r], opp)
               for i in range(len(PUSH_LEVELS)))

