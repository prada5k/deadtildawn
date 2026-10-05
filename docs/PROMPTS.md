# ChatGPT prompts (low-poly kanjo)

Copy-paste prompts for the art, all in one style so everything matches. Use
**one ChatGPT thread per set** (parts in one thread, menus in another):
ChatGPT keeps a style steadier when the earlier images are in the same chat.

ChatGPT makes PICTURES, not 3D files. The 3D models come from Sketchfab
(prepped by `art/blender/prep_cars.py`) or from a picture through an
image-to-3D tool; prompt 3 makes pictures for that.

---

## 0. The style line (start EVERY prompt with this)

> Low-poly kanjo style: flat-shaded faceted shapes like a low-poly 3D game
> asset, visible polygon facets, crisp edges, a limited palette, soft studio
> light from the upper left, a thin dark outline. 1990s Osaka-loop kanjo
> crew culture, Honda tuner scene. Real brand logos and lettering are fine
> and should be accurate.

---

## 1. Part pictures (the 24 parts; `docs/PART_IMAGES.md` has the ids)

Paste a real photo of the part along with:

> [STYLE LINE]
> Turn this photo into a game icon of the part: [PART, with its real brand],
> 3/4 view from slightly above, centered, filling about 80% of the frame,
> keeping its real shape, colors and brand markings. Transparent background,
> no ground shadow, no extra text. Square, 1024 x 1024.

Save as `godot/textures/parts/<part id>.png` (any square size; the game
scales it). Brand ideas, if you want real ones (your call):

| Part id | Idea |
|---|---|
| intake_short_ram | AEM short ram |
| intake_cold_air | AEM cold air intake |
| header_421 | DC Sports 4-2-1 |
| header_41_race | Toda / Skunk2 4-1 race header |
| cams_street | Skunk2 Pro stage 1 cams |
| cams_race | Toda / Jun high-lift cams |
| ecu_street_tune | Hondata-chipped P28 ECU |
| flywheel_light | Toda chromoly flywheel |
| shifter_short | Hybrid Racing short shifter |
| shifter_race | Spoon shifter + Innovative mounts |
| fd_44 / fd_49 | ring and pinion gear set (MFactory) |
| tires_300tw | Falken Azenis |
| tires_200tw | Bridgestone Potenza RE-71R |
| tires_r_comp | Toyo Proxes R888R |
| wheels_light | Konig Countergram (chrome) |
| wheels_forged | Buddy Club P1 (white) |
| rsb_19 / rsb_24 | Progress rear sway bar |
| springs_lowering | Eibach Pro-Kit |
| coilovers_street | Tein Flex Z |
| interior_strip | a bare shell: seats and carpet out, no brand |
| hood_carbon | Seibon carbon hood |
| seats_buckets | Bride Zeta bucket seat |

---

## 2. Menu pieces (redo of the UI art; sizes in `docs/ART_REDO.md`)

> [STYLE LINE]
> A game UI piece for a kanjo street racing game set in a night-time SoCal
> garage: [THE PIECE, from the list below]. Flat front view, no perspective,
> exactly [W] x [H] pixels, [transparent background / seamless tile]. Keep
> the [BORDER] px border for edges and torn ends, and the middle plain and
> even (it gets stretched). No text.

| File (`godot/textures/`) | W x H | Background | Border | THE PIECE |
|---|---|---|---|---|
| `drawer.png` | 128 x 96 | transparent | 8 | the face of a red steel tool-chest drawer, faceted bevel, a little worn |
| `drawer_hover.png` | 128 x 96 | transparent | 8 | the same drawer face, a bit lighter |
| `drawer_open.png` | 128 x 96 | transparent | 8 | the same drawer pulled open, its top edge showing |
| `gaff.png` | 256 x 84 | transparent | 18 | a strip of orange gaffer tape, torn ends |
| `tape.png` | 160 x 48 | transparent | 14 | a strip of beige masking tape, torn ends |
| `receipt.png` | 200 x 120 | transparent | 8 (bottom 10) | thermal receipt paper, zig-zag torn bottom edge |
| `pegboard.png` | 256 x 256 | seamless tile | none | brown pegboard, round holes on a grid 32 px apart |
| `whiteboard.png` | 256 x 256 | transparent | 18 (bottom 22) | a whiteboard: aluminum frame, marker tray along the bottom, white middle |
| `corkboard.png` | 512 x 512 | transparent | 18 | a corkboard with a wood frame |
| `pin.png` | 40 x 40 | transparent | - | a red pushpin seen from above |
| `clip.png` | 220 x 70 | transparent | - | a clipboard's steel clip, front view |

New kanjo pieces (no slot in the game yet: make them and I'll wire them in):

| File | Size | THE PIECE |
|---|---|---|
| `godot/textures/kanjo/banner.png` | 1024 x 192 | a windshield banner strip: white vinyl lettering "DEADTILDAWN" on black, kanjo crew style (the text IS wanted here) |
| `godot/textures/kanjo/sticker_sheet.png` | 1024 x 1024 | a sheet of 9 die-cut kanjo crew / JDM parts stickers on transparent, real brands welcome |
| `godot/textures/kanjo/hanko.png` | 512 x 512 | a red ink hanko seal stamp, square, rough ink edges, transparent (no characters; the game writes them) |

---

## 3. Pictures for 3D (props and parts to turn into models)

For an image-to-3D tool (Tripo, Hunyuan3D, Rodin) or for Claude to model
from. One object per picture:

> [STYLE LINE]
> A single low-poly 3D game asset: [OBJECT]. 3/4 view from slightly above,
> the whole object in frame, plain white background, even lighting, no
> shadow, no other objects. Under 2,000 polygons look.

Useful objects for the game, most useful first: a California highway
reflector post, a yellow curve-warning sign on a post, a steel Armco
guardrail section, a chaparral bush, a coast live oak, a boulder, a
pine tree, a street-racing spotter in a hi-vis vest holding a flashlight,
a parked pickup truck, a two-post car lift, a red rolling tool chest, a
tire rack, an engine hoist.

---

## 4. Rarity glows (`godot/textures/glow/README.md` has sizes and colors)

> [STYLE LINE]
> A glow burst for a game loot reveal: faceted triangular rays and shards
> radiating from the center, [COLOR], fading to fully transparent well before
> the edges, nothing in the center. Transparent background, 1024 x 1024.

Colors: common #BFC2CC, rare #5999FF, epic #B86BFF, legendary #FFC740.
