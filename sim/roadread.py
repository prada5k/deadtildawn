"""Reading a road before the race (the scout screen): the numbers, from the
pace notes and one theoretical-limit run of the player's car. No lap times
(the game never shows them) and no verdict (Spire: the player reads the
numbers and decides what the road rewards).

  straight_share    distance on straights / road length (pace notes only)
  full_throttle     share of the run's TIME at full throttle
  braking           share of the run's time on the brakes
  longest_straight  m
  tightest          the tightest corner (pace note + radius)
  hairpins          corners at radius <= HAIRPIN_M

Why time as well as distance: the car spends longer per meter in corners
(it's slower there), so a road that's 55% straight by distance can still be
under half full throttle by time. Time is what a part buys back. The open
roads 1-9 + the test track run 41-70% full throttle (flowing 66-70%, tight
41-44%, VALIDATION_LOG).
"""

HAIRPIN_M = 25.0       # severity 1-2 (15 m, 22 m)


def road_read(segments, lap):
    tel = lap.telemetry
    length = sum(seg.length for seg in segments)
    straights = [seg.length for seg in segments if not seg.is_corner]
    corners = [seg for seg in segments if seg.is_corner]
    total = tel.t[-1] - tel.t[0]
    full = brake = 0.0
    for i in range(len(tel.t) - 1):
        dt = tel.t[i + 1] - tel.t[i]
        if tel.throttle[i] >= 0.99:
            full += dt
        if tel.brake[i] > 0.0:
            brake += dt
    full_share = full / total if total > 0 else 0.0
    tight = min(corners, key=lambda c: c.radius) if corners else None
    return {
        "length": round(length, 1),
        "straight_share": round(sum(straights) / length, 3) if length else 0.0,
        "full_throttle": round(full_share, 3),
        "braking": round(brake / total, 3) if total > 0 else 0.0,
        "longest_straight": round(max(straights), 1) if straights else 0.0,
        "tightest": None if tight is None else {"text": tight.text, "radius": round(tight.radius, 1)},
        "corners": len(corners),
        "hairpins": sum(1 for c in corners if c.radius <= HAIRPIN_M),
    }
