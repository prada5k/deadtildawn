"""Rolled parts and in-world pulls.

A catalog part is a TEMPLATE. A pull produces an INSTANCE: the template plus a
hidden quality roll q in [0, 1]. The instance's real effects scale with q:
benefits scale up and drawbacks scale down, so a good roll is better in every
way. q = 0.5 reproduces the catalog's nominal numbers exactly. Parts with a
fixed spec (a 4.4 final drive, a 19 mm sway bar) don't roll.

Pulls (data/parts/pulls.json) pick a rarity by weight, then a part of that
rarity, then a quality from the source's range. A pity counter per source
guarantees a minimum rarity within N pulls, so bad luck can slow progression
but never stall it.
"""
import json
from pathlib import Path

PULLS_FILE = Path(__file__).parent.parent / "data" / "parts" / "pulls.json"
RARITY_ORDER = ["common", "rare", "epic", "legendary"]
SPREAD = 0.35                 # q = 0 / 1 gives -35% / +35% of the nominal benefit
FIXED_SPEC = {"final_drive", "roll_front"}

# For each effect: does a LARGER value help (+1) or hurt (-1)?
DIRECTION = {
    "torque_scale": +1, "engine_inertia_scale": -1, "wheel_inertia_scale": -1,
    "mu_scale": +1, "load_k_scale": -1, "crr_scale": -1,
    "mass_kg": -1, "shift_time_s": -1, "cg_height_m": -1,
}
NEUTRAL = {"torque_scale": 1.0, "engine_inertia_scale": 1.0, "wheel_inertia_scale": 1.0,
           "mu_scale": 1.0, "load_k_scale": 1.0, "crr_scale": 1.0,
           "mass_kg": 0.0, "shift_time_s": 0.0, "cg_height_m": 0.0}


def load_pulls(path=PULLS_FILE):
    return json.loads(Path(path).read_text(encoding="utf-8"))["sources"]


def _scaled(delta, helps, q):
    """Scale a change from neutral: benefits grow with q, drawbacks shrink."""
    k = SPREAD * (2 * q - 1)
    return delta * (1 + k) if helps else delta * (1 - k)


def rolled_effects(template, q):
    """The template's effects at quality q."""
    out = {}
    for name, value in template["effects"].items():
        if name in FIXED_SPEC:
            out[name] = value
        elif name == "torque_shape":
            out[name] = {end: _scaled(v, v > 0, q) for end, v in value.items()}
        else:
            delta = value - NEUTRAL[name]
            helps = (delta > 0) == (DIRECTION[name] > 0)
            out[name] = NEUTRAL[name] + _scaled(delta, helps, q)
    return out


def instance_part(template, q):
    """A part dict usable by sim.parts.apply_parts, at quality q."""
    return {**template, "effects": rolled_effects(template, q), "quality": q}


def rolls(template):
    """Does this part's quality change anything?"""
    return any(name not in FIXED_SPEC for name in template["effects"])


def rarity_at_least(rarity, floor):
    return RARITY_ORDER.index(rarity) >= RARITY_ORDER.index(floor)


def pull(source_id, sources, parts, pity, rng):
    """One pull. Returns (template_id, quality, new_pity).

    pity: {source_id: pulls since the last pity-rarity-or-better hit}
    rng: random.Random (seeded by the caller for reproducibility)
    """
    src = sources[source_id]
    weights = dict(src["rarity_weights"])
    floor = src["pity"]["rarity"]
    since = pity.get(source_id, 0)
    if since + 1 >= src["pity"]["within"]:
        # Pity: this pull is guaranteed floor rarity or better
        weights = {r: (w if rarity_at_least(r, floor) else 0) for r, w in weights.items()}
        if sum(weights.values()) == 0:
            weights = {floor: 1}
    by_rarity = {r: [p for p in parts.values() if p["rarity"] == r] for r in RARITY_ORDER}
    weights = {r: w for r, w in weights.items() if w > 0 and by_rarity[r]}
    rarity = rng.choices(list(weights), weights=list(weights.values()))[0]
    template = rng.choice(sorted(by_rarity[rarity], key=lambda p: p["id"]))
    lo, hi = src["quality"]
    q = rng.uniform(lo, hi) if rolls(template) else 0.5
    new_pity = dict(pity)
    new_pity[source_id] = 0 if rarity_at_least(rarity, floor) else since + 1
    return template["id"], round(q, 4), new_pity
