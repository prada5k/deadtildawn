"""Opponents: game-tuned cars and drivers (data/opponents.json).

An opponent's car is the base car with CHANGES applied (the same effects
parts use, plus drivetrain and weight split), so every opponent runs through
exactly the same physics as the player. Their driver has a push level,
consistency (sigma) and skill, all authored. Difficulty is tuned by the
engine's `condition` (calibrated by tools/calibrate_opponents.py); the stat
card shows the resulting horsepower, so the card never lies about the car.
"""
import json
from dataclasses import replace
from pathlib import Path

from .driver import Driver
from .parts import apply_parts

OPPONENTS_FILE = Path(__file__).parent.parent / "data" / "opponents.json"


def load_opponents(path=OPPONENTS_FILE):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def opponent_car(base, spec):
    effects = dict(spec["effects"])
    # condition scales the engine (tired street engine < 1 < fresh)
    effects["torque_scale"] = effects.get("torque_scale", 1.0) * spec.get("condition", 1.0)
    car = apply_parts(base, [{"id": "spec", "slot": "spec", "effects": effects}])
    return replace(car, name=spec["car"], drivetrain=spec["drivetrain"],
                   weight_front=spec["weight_front"])


def opponent_driver(spec):
    d = spec["driver"]
    return Driver(name=spec["name"], sigma=d["sigma"], push=d["push"], skill=d["skill"])


def condition_label(spec):
    c = spec.get("condition", 1.0)
    return "tired" if c < 0.8 else ("worn" if c < 0.95 else ("healthy" if c <= 1.05 else "fresh"))


def driver_read(spec):
    """One line for the stat card: what you'd hear about this driver."""
    d = spec["driver"]
    skill, push = d["skill"], d["push"]
    level = "sharp" if skill >= 0.99 else ("solid" if skill >= 0.96 else
             ("average" if skill >= 0.93 else "sloppy"))
    style = {"safe": "drives within himself", "normal": "drives a steady pace",
             "hard": "pushes hard", "flat_out": "drives on the ragged edge"}[push]
    consistency = "rarely makes mistakes" if d["sigma"] <= 0.022 else (
        "loose in the corners" if d["sigma"] >= 0.03 else "fairly consistent")
    return f"{level.capitalize()}, {style}, {consistency}."


def head_to_head(player_times, opponent_times):
    """P(player beats opponent), comparing every pair of sampled runs.
    DNF times are inf: a DNF never beats a finished run, and if both crash
    nobody wins (counted as a loss here: you didn't beat him)."""
    wins = sum(1 for p in player_times for o in opponent_times if p < o)
    return wins / (len(player_times) * len(opponent_times))
