"""Tests for the procedural track generator (sim/trackgen.py)."""
import statistics

import pytest

from sim.track import find_crossings, parse_pace_notes
from sim.trackgen import MIN_CLEARANCE_M, STYLES, generate, min_clearance

SEEDS = range(6)


@pytest.mark.parametrize("style", list(STYLES))
def test_generated_tracks_are_buildable(style):
    for seed in SEEDS:
        g = generate(seed, style)
        segs = parse_pace_notes(g.notes)                 # strict parser accepts it
        assert find_crossings(segs, step=2.0) == []
        assert min_clearance(segs) >= MIN_CLEARANCE_M
        lo, hi = STYLES[style]["length"]
        assert lo <= g.length <= hi * 1.15


def test_same_seed_same_track():
    assert generate(42, "technical").notes == generate(42, "technical").notes


def test_different_seeds_differ():
    assert len({generate(s, "balanced").notes for s in SEEDS}) == len(SEEDS)


def test_styles_have_different_character():
    def mean_severity(style):
        sev = []
        for seed in SEEDS:
            sev += [sg.severity for sg in parse_pace_notes(generate(seed, style).notes) if sg.is_corner]
        return statistics.mean(sev)
    assert mean_severity("technical") < mean_severity("balanced") < mean_severity("flowing")


def test_never_two_straights_in_a_row():
    for style in STYLES:
        for seed in SEEDS:
            tokens = [t.strip() for t in generate(seed, style).notes.split(",")]
            for a, b in zip(tokens, tokens[1:]):
                assert not (a.startswith("S ") and b.startswith("S ")), (style, seed)


def test_clearance_allows_a_normal_hairpin():
    # A 180-degree hairpin (R 15 m) leaves the straights 30 m apart center to
    # center: a 22 m gap between two 8 m roads. Buildable.
    segs = parse_pace_notes("S 200, L1 180, S 200")
    assert min_clearance(segs) == pytest.approx(30.0, abs=0.5)
    assert min_clearance(segs) >= MIN_CLEARANCE_M


def test_clearance_catches_a_near_miss():
    # Overturning the hairpin (190 degrees) angles the return road back toward
    # the first straight: it never crosses, but comes within ~9 m. Not buildable.
    segs = parse_pace_notes("S 200, L1 190, S 120")
    assert find_crossings(segs, step=2.0) == []
    assert min_clearance(segs) < MIN_CLEARANCE_M


def test_unknown_style_rejected():
    with pytest.raises(ValueError):
        generate(1, "rally")
