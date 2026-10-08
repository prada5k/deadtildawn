"""CONTRABAND96 Garage 1 floor overlays: small RGBA swatches laid over the concrete as a few transparent quads
(godot/home/garage1_props.tscn -> FloorDetail). Generated, not downloaded. Deterministic (fixed seeds).

    python art/blender/gen_floor_overlays.py        (needs numpy + Pillow)

Outputs godot/assets/textures/floor/: floor_oil.png (old oil blots), floor_grime.png (soft dark grime),
floor_scuffs.png (dark and chalky scuff streaks), floor_fade.png (faded, bleached discoloration).
Low resolution on purpose (PSX): the quads use nearest filtering.
"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets", "textures", "floor")


def noise(n, rng, octaves=((4, 1.0), (8, 0.5), (16, 0.25), (32, 0.12))):
    """Smooth value noise in [0, 1] at n x n (bilinear-upsampled random grids, summed)."""
    out = np.zeros((n, n))
    tot = 0.0
    for g, w in octaves:
        grid = rng.random((g + 1, g + 1))
        im = Image.fromarray((grid * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
        out += np.asarray(im, dtype=float) / 255.0 * w
        tot += w
    out /= tot
    return (out - out.min()) / (out.max() - out.min() + 1e-9)


def save(name, rgb, alpha):
    img = np.zeros(alpha.shape + (4,), dtype=np.uint8)
    img[..., :3] = np.clip(np.array(rgb) * 255, 0, 255)
    img[..., 3] = np.clip(alpha * 255, 0, 255)
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, name))
    print("wrote", name, img.shape[:2], "max alpha", round(float(alpha.max()), 2))


def radial(n, soft=0.35):
    y, x = np.mgrid[0:n, 0:n]
    r = np.hypot((x - n / 2) / (n / 2), (y - n / 2) / (n / 2))
    return np.clip(1 - r, 0, 1) ** soft            # 1 in the middle, 0 at the border (no visible quad edge)


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(1996)

    # oil: a few irregular dark blots with a faint ring where it dried, brown-black
    n = 128
    f = noise(n, rng)
    rad = radial(n, 0.6)
    blot = np.clip((f * 0.8 + rad * 0.9 - 0.62) * 3.2, 0, 1) * (rad > 0.05)
    ring = np.clip(1 - np.abs(blot - 0.35) * 6, 0, 1) * 0.15
    save("floor_oil.png", (0.035, 0.028, 0.02), np.clip(blot * 1.0 + ring, 0, 0.95) * np.clip(rad * 3, 0, 1))

    # grime: broad soft darkening, patchy
    n = 128
    f = noise(n, rng, ((3, 1.0), (6, 0.6), (12, 0.3)))
    save("floor_grime.png", (0.03, 0.026, 0.022), np.clip(f * 0.55, 0, 0.5) * np.clip(radial(n, 0.5) * 2.2, 0, 1))

    # scuffs: short thin streaks, mostly one direction (x), dark rubber marks plus a few chalky ones
    n = 256
    a = np.zeros((n, n))
    col = np.zeros((n, n, 3))
    img = Image.new("L", (n, n), 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    for _ in range(46):
        x, y = rng.integers(10, n - 10), rng.integers(10, n - 10)
        ln = rng.integers(8, 34)
        ang = rng.normal(0.0, 0.28)
        d.line([(x, y), (x + ln * np.cos(ang), y + ln * np.sin(ang))], fill=int(rng.integers(70, 170)), width=int(rng.integers(1, 3)))
    streak = np.asarray(img, dtype=float) / 255.0
    streak *= np.clip(radial(n, 0.4) * 2.5, 0, 1)
    save("floor_scuffs.png", (0.025, 0.022, 0.02), np.clip(streak * 1.15, 0, 0.8))

    # fade: a bleached, faded patch (sun and mopping), pale warm grey, very low alpha
    n = 128
    f = noise(n, rng, ((3, 1.0), (7, 0.5), (14, 0.2)))
    save("floor_fade.png", (0.62, 0.56, 0.46), np.clip((f - 0.35) * 0.6, 0, 0.3) * np.clip(radial(n, 0.5) * 2.5, 0, 1))


main()
