# Art to redo with an image generator

Most of the UI art was generated in code (Pillow) as rough stand-ins. These
are the ones worth redoing, best payoff first. To swap one in: **save over the
file with the same name, at the same pixel size**, then F5. Git keeps the old
one, so a bad swap is one `git checkout <file>` away.

## Why the size and the border matter

Most of these are **9-slice** images: the game stretches the middle to fit
any button or panel and keeps the outer border as-is (the torn tape ends, a
frame). The border widths below are in pixels of the image. Keep everything
that shouldn't stretch (torn ends, frame, corners) INSIDE that border, and
keep the middle plain and even (it gets stretched). Same pixel size, or the
borders land in the wrong place.

**Tile** images repeat across a surface: they must be seamless (the left
edge continues into the right, the top into the bottom).

## The list (all in `godot/textures/`)

| # | File | Size (px) | Kind | Border (L/T/R/B) | What it is / what to ask for |
|---|---|---|---|---|---|
| 1 | `drawer.png` | 128 x 96 | 9-slice | 8 / 8 / 8 / 8 | Nav bar drawer face: red tool-chest steel, worn paint, a bevel. Transparent outside the drawer. |
| 1 | `drawer_hover.png` | 128 x 96 | 9-slice | 8 / 8 / 8 / 8 | Same drawer, a bit lighter (hovered). Same layout exactly. |
| 1 | `drawer_open.png` | 128 x 96 | 9-slice | 8 / 8 / 8 / 8 | Same drawer, pulled open (its tab). Same layout exactly. |
| 2 | `gaff.png` | 256 x 84 | 9-slice | 18 / 10 / 18 / 10 | Orange gaffer tape strip (the main buttons): cloth weave, torn ends only in the outer 18 px, transparent around it. |
| 3 | `tape.png` | 160 x 48 | 9-slice | 14 / 6 / 14 / 6 | Beige masking tape strip (labels, small buttons): torn ends in the outer 14 px, transparent around. |
| 4 | `receipt.png` | 200 x 120 | 9-slice | 8 / 8 / 8 / 10 | Thermal receipt paper (cash/rep in the corner): zig-zag torn bottom edge inside the bottom 10 px, plain middle. |
| 5 | `pegboard.png` | 256 x 256 | tile | none | Brown hardboard pegboard, round holes on a grid that tiles (8 holes across = 32 px apart). Seamless. |
| 6 | `whiteboard.png` | 256 x 256 | 9-slice | 18 / 18 / 18 / 22 | Whiteboard (the calendar): aluminum frame in the border (a marker tray along the bottom 22 px), clean white middle with faint ghosting. |
| 7 | `corkboard.png` | 512 x 512 | 9-slice | 18 / 18 / 18 / 18 | Corkboard (flyers, team board): wood frame in the outer 18 px, cork in the middle. |
| 8 | `pin.png` | 40 x 40 | sticker | - | A red pushpin seen from above, transparent background. |
| 8 | `clip.png` | 220 x 70 | sticker | - | A clipboard's metal clip, front on, transparent background. |
| 9 | `glow/<rarity>.png` | 1024 x 1024 | sticker | - | The rarity glows: see `glow/README.md`. |
| 10 | `parts/<part id>.png` | 512 x 512 | sticker | - | The part pictures: see `docs/PART_IMAGES.md`. |

Keep as they are: `paper.jpg`, `cork.jpg`, `cardboard.jpg`, `concrete.jpg`,
`bench.jpg`, `hardboard.jpg` (real CC0 photo textures, already good),
`dotmatrix.png` (the dyno printout's paper; it's matched to the font),
`handle.png`.

> **Oct 2026: low-poly kanjo.** The ready-to-paste prompts (with this table
> built in, plus new kanjo pieces) are in `docs/PROMPTS.md` section 2. The
> style line below is the old one.

## One style prompt for the set (old)

Start every request with the same line so the set matches (the halftone look):

> 1990s Japanese tuning-magazine print style, flat colors with a light
> halftone dot texture, slightly worn, garage-at-night palette, no text,
> no logos. [the thing], exactly [W] x [H] pixels, [transparent background /
> seamless tile].

If the generator won't hit the exact size, make it bigger at the same
proportions and resize it in Photopea (Image > Image Size), or hand it to
Claude to cut and resize.
