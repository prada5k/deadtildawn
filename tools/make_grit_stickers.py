"""Worn vinyl sticker textures for the menus (Spire: the clean buttons "dont
fit with the dark gritty parking backdrop"). Each is a 9-slice image: a
faded color, grime and scuffs, scratches, a chipped dirty-white die-cut
border, one corner peeling, a baked shadow. theme.tres uses them
(StyleBoxTexture, margin = MARGIN).

    python tools/make_grit_stickers.py      -> godot/textures/vinyl/*.png
"""
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "godot" / "textures" / "vinyl"
MARGIN = 22            # px of border the 9-slice keeps (corners, the die-cut edge)

STICKERS = {
    # name: (size, fill rgb, seed)
    "label": ((200, 72), (222, 216, 200), 3),        # tags and small buttons: dirty white
    "label_small": ((160, 60), (222, 216, 200), 4),
    "orange": ((300, 100), (214, 104, 34), 5),       # main buttons: faded orange
    "orange_small": ((220, 76), (214, 104, 34), 6),
    "red": ((300, 100), (196, 40, 34), 7),           # SEND IT
    # panels (cards, sheets, flyers): bigger, same wear
    "panel": ((420, 320), (226, 220, 204), 11),
    "panel_yellow": ((420, 320), (228, 196, 82), 12),
    "panel_pink": ((420, 320), (226, 168, 178), 13),
    "panel_blue": ((420, 320), (164, 192, 222), 14),
    "panel_cardboard": ((420, 320), (160, 122, 80), 15),
}


def noise(w, h, scale, rng):
    """Smooth value noise in 0..1."""
    small = rng.random((max(2, h // scale), max(2, w // scale)))
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img).astype(np.float32) / 255.0


def make(size, fill, seed):
    rng = np.random.default_rng(seed)
    random.seed(seed)
    w, h = size
    pad = 8                                             # room for the shadow
    iw, ih = w - pad * 2, h - pad * 2
    r = 16
    # The sticker's shape: a rounded rect with one corner peeled (cut on a diagonal)
    shape = Image.new("L", (iw, ih), 0)
    d = ImageDraw.Draw(shape)
    d.rounded_rectangle((0, 0, iw - 1, ih - 1), r, fill=255)
    peel = random.choice(["tr", "bl"])
    cut = 13
    if peel == "tr":
        d.polygon([(iw - cut - 1, 0), (iw, 0), (iw, cut + 1)], fill=0)
    else:
        d.polygon([(0, ih - cut - 1), (0, ih), (cut + 1, ih)], fill=0)
    # Chipped edge: nibble the alpha along the border
    a = np.asarray(shape).astype(np.float32) / 255.0
    chips = noise(iw, ih, 3, rng)
    edge = np.asarray(shape.filter(ImageFilter.MinFilter(3))).astype(np.float32) / 255.0
    rim = (a > 0) & (edge == 0)
    a[rim & (chips < 0.22)] = 0.0
    # The die-cut border (dirty white) and the face (faded, grimy)
    bw = 6                                              # the white die-cut border (px)
    face_img = Image.new("L", (iw, ih), 0)
    ImageDraw.Draw(face_img).rounded_rectangle((bw, bw, iw - 1 - bw, ih - 1 - bw), r - bw, fill=255)
    inner = np.asarray(face_img).astype(np.float32) / 255.0 * (a > 0)
    rgb = np.zeros((ih, iw, 3), np.float32)
    border = np.array([226, 222, 210], np.float32) / 255.0
    face = np.array(fill, np.float32) / 255.0
    rgb[:] = border
    face_mask = inner > 0
    rgb[face_mask] = face
    # Fade + grime: big soft blotches, darker toward the bottom (road dirt)
    blot = noise(iw, ih, 18, rng)
    fine = noise(iw, ih, 2, rng)
    big = w > 350                                       # panels carry small text: lighter wear
    grime = (0.9 + 0.1 * blot) if big else (0.78 + 0.22 * blot)
    grime *= 0.93 + 0.07 * fine
    ramp = np.linspace(1.0, 0.9 if big else 0.82, ih)[:, None]
    rgb *= (grime * ramp)[..., None]
    # Sun fade: wash the face toward grey in patches
    fade = np.clip(noise(iw, ih, 26, rng) - 0.55, 0, 1)[..., None] * (0.45 if big else 0.9)
    rgb = rgb * (1 - fade) + np.array([0.62, 0.6, 0.56]) * fade
    # Scratches: thin light lines across the face
    sc = Image.new("L", (iw, ih), 0)
    sd = ImageDraw.Draw(sc)
    for _ in range(int(iw * ih / 1400)):
        x0, y0 = random.uniform(0, iw), random.uniform(0, ih)
        ang = random.uniform(-0.6, 0.6)
        ln = random.uniform(8, 40)
        sd.line((x0, y0, x0 + ln, y0 + ln * ang), fill=random.randint(60, 140), width=1)
    s = np.asarray(sc).astype(np.float32)[..., None] / 255.0
    rgb = rgb * (1 - s * 0.5) + s * 0.5
    # A few dark scuffs
    for _ in range(4):
        cx, cy = random.uniform(0, iw), random.uniform(0, ih)
        rr = random.uniform(4, 12)
        yy, xx = np.ogrid[:ih, :iw]
        m = np.clip(1 - np.hypot(xx - cx, yy - cy) / rr, 0, 1)[..., None] * 0.35
        rgb *= 1 - m
    sticker = np.dstack([np.clip(rgb, 0, 1), a])
    sticker_img = Image.fromarray((sticker * 255).astype(np.uint8), "RGBA")
    # The baked shadow under it
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh_a = Image.new("L", (iw, ih), 0)
    sh_a.paste(Image.fromarray((a * 150).astype(np.uint8)), (0, 0))
    sh.paste((0, 0, 0, 255), (pad, pad + 4), sh_a)
    sh = sh.filter(ImageFilter.GaussianBlur(3))
    out.alpha_composite(sh)
    out.alpha_composite(sticker_img, (pad, pad))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (size, fill, seed) in STICKERS.items():
        make(size, fill, seed).save(OUT / f"{name}.png")
        print("wrote", name)


if __name__ == "__main__":
    main()
