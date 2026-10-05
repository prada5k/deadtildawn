# Part pictures (your images, cartoonized)

Every part has a picture in the game: the reveal, the swap card, the build
sheet, the $$$ rows. Right now they're drawn in code
(`godot/widgets/part_art.gd`). Drop a PNG named after the part's id into
`godot/textures/parts/` and the game uses yours instead, everywhere, with no
code change. Parts without an image keep the drawing, so you can do them a
few at a time.

## The file

- **Name:** `<part id>.png` exactly (list below), e.g. `header_421.png`
- **Size:** square, 512 x 512
- **Background:** transparent (the rarity glow and the paper show through)
- **Framing:** the part centered, filling ~80% of the square, a little room around it

## Keeping 24 images in one style

The trick with an AI image generator is to use the SAME prompt every time,
changing only the part. Paste a real photo of the part along with:

> Cartoon sticker illustration of this car part: [PART], 3/4 view, centered,
> bold black ink outline, flat cel-shaded colors with one highlight, slightly
> worn, 1990s Japanese parts catalog style, transparent background, no text,
> no logos, no shadow on the ground

Then:
1. Generate a few, pick the best, and save it as the part's id.
2. If the background isn't transparent, remove it (most generators have a
   "remove background" button; remove.bg or Photopea work too).
3. Resize to 512 x 512 (Photopea: Image > Image Size).
4. Drop it in `godot/textures/parts/`, press F5.

Do one first (say the 4-2-1 header) and check it in the game before doing
all 24: it's cheaper to fix the prompt than to redo two dozen images.

## The 24 part ids

| File | Part |
|---|---|
| `intake_short_ram.png` | Short ram intake |
| `intake_cold_air.png` | Cold air intake |
| `header_421.png` | 4-2-1 header |
| `header_41_race.png` | 4-1 race header |
| `cams_street.png` | Street cams |
| `cams_race.png` | High-rpm race cams |
| `ecu_street_tune.png` | Street tune ECU |
| `flywheel_light.png` | Lightweight flywheel |
| `shifter_short.png` | Short shifter |
| `shifter_race.png` | Race shifter + bushings |
| `fd_44.png` | 4.4 final drive |
| `fd_49.png` | 4.9 final drive |
| `tires_300tw.png` | Performance street tires (300TW) |
| `tires_200tw.png` | Extreme summer tires (200TW) |
| `tires_r_comp.png` | R-compound (100TW) |
| `wheels_light.png` | Lightweight 15s |
| `wheels_forged.png` | Forged 15s |
| `rsb_19.png` | Rear sway bar 19 mm |
| `rsb_24.png` | Rear sway bar 24 mm |
| `springs_lowering.png` | Lowering springs |
| `coilovers_street.png` | Street coilovers |
| `interior_strip.png` | Strip the interior |
| `hood_carbon.png` | Carbon hood |
| `seats_buckets.png` | Fixed-back buckets |

These images are for you and your friends. Brand logos in the source photos
are fine for that; the prompt asks for no logos anyway, so the set stays
clean if you ever change your mind.
