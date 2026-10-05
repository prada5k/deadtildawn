# Rarity glows (behind a part on the pull reveal and the swap card)

One picture per rarity. A file here replaces the glow drawn in code
(`widgets/part_art.gd draw_glow`); the reveal turns it slowly and makes it
breathe. Missing files use the code glow, so you can do them one at a time.

| File | Rarity |
|---|---|
| `common.png` | common (gray) |
| `rare.png` | rare |
| `epic.png` | epic |
| `legendary.png` | legendary |

- Square, 1024 x 1024, PNG with a **transparent** background
- The glow centered, fading out to fully transparent well before the edges
  (it's drawn a bit bigger than the part and spins: no hard edges or corners)
- Nothing in the middle that would fight the part drawn on top
- One prompt for all four, changing only the color, so they're a set:

> Halftone print glow, a radial burst of dots, large dots in the center
> shrinking to nothing at the edges, [COLOR], 1990s Japanese print style,
> centered, transparent background, no text, nothing in the center

Colors (the game's, `game.gd RARITY_COLORS`): common silver-gray #BFC2CC,
rare blue #5999FF, epic purple #B86BFF, legendary gold #FFC740.
