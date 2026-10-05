# Art direction (decided with Spire, Oct 2026)

Features and the gameplay loop stay as they are; this is the look.

## UPDATE (Oct 2026): LOW-POLY KANJO, everything

Spire: "low poly kanjo for the rest of the project, including revamping what
we have already done." This overrides the photo-texture / garage-grit parts
below where they clash; the garage workbench menus, the night broadcast and
the kanjo layer (crew sticker, hanko, banner) stay, redrawn in the new style.

- **3D:** low-poly, flat-shaded (visible facets), small flat-color materials or
  tiny textures; chunky, readable silhouettes at phone size. Cars are Spire's
  low-poly models (`art/models/`, prepped by `art/blender/prep_cars.py`);
  props and scenery to match (no photo textures on 3D surfaces).
- **Kanjo:** Osaka loop culture brought to a SoCal canyon crew: 90s Hondas,
  Championship White, crew windshield banners, kanji / crew stickers, battle
  tape, red hanko seals, sodium-orange and moon-blue night light.
- **Real branding is IN** (Spire): real part and wheel brands on part
  pictures and stickers (Spoon, Mugen, Toda, Skunk2, Hondata, Bride, Konig,
  Buddy Club...). It's a game for Spire and friends, not a store release.
- **2D (menus, icons, glows):** flat vector shapes with faceted shading (the
  2D version of low poly), thick dark outlines, limited palette, light
  halftone dots. One style prompt for everything: `docs/PROMPTS.md`.
- **Revamp list (existing code-built art -> low poly):** scenery (rocks,
  chaparral, oaks, pines, cliffs: faceted meshes instead of boxes/billboards),
  the road edge props (posts, chevrons, Armco), spotters/flagger (low-poly
  people), the turnout + PCH overlook + lift bay props, then the UI
  textures (`docs/ART_REDO.md`) and part pictures (`docs/PART_IMAGES.md`).

## Vision

A SoCal touge game: mountain passes, canyons, roads over the ocean. Kanjo Civic
"piss missile" culture, late-90s / early-2000s tuner scene. Mobile-game polish
(Clash Royale, Big Win, Brawl Stars) dressed in garage grit. NOT arcade-retro.

## Menus: the garage workbench

Menus are objects in the warehouse (mockup A on the canvas
"deadtildawn menu directions").

- Pegboard wall background; masking tape, Dymo label-maker strips, receipts,
  Polaroids, shop paperwork. CC0 photo textures (ambientCG / Poly Haven) +
  code-drawn props.
- Bottom nav = a red tool chest; each tab is a drawer with a masking-tape label
  in Sharpie: `$$$` (parts), `car`, `home`, `cal`, `team`. Changing tabs slides
  drawers.
- HOME hero: a 3D overlook, the DX parked at a canyon turnout at dusk (ocean,
  sky, headlights), shown as a taped Polaroid. Updates as the car is built.
- CAR: the DX up on a two-post lift in a dim bay, still camera (drag to look,
  no auto-spin), installed parts visible on the model.
- `$$$` (parts): flyers pinned on a corkboard (pick-n-pull, swap meet, sealed
  crate); the counter is a parts-store receipt pad.
- Pull reveal: unbox on the bench (rarity), then "dyno it" prints a dot-matrix
  sheet (quality, exact numbers).
- CAL: a dry-erase whiteboard, race nights circled in marker. (A parts-store
  promo calendar comes later as a sponsor gift.)
- TEAM (replaces XTR): Polaroid board of Faba + the builder, their relationship
  and stats. Layout later; not coded yet.
- Race night (briefing, meeting, results): at a night canyon turnout, both cars
  parked with headlights on; stat card = clipboard tech sheet; push talk as
  Faba's dialog; wager as cash in hand.
- Motion: physical and quick (drawers slide, papers drop and settle, tape
  wobbles, stamps thunk), all under ~0.3 s.

## Type

- Racing Sans One: big headers, buttons, numbers that shout (kept).
- Barlow Condensed: body, stats, labels (replaces Rajdhani everywhere).
- Permanent Marker: Sharpie on tape, handwritten notes.
- Doto (dot-matrix): the dyno printout only.

Main actions in the hub are Sharpie on orange gaffer tape (GaffButton), not
slick buttons. Race-night buttons (SEND IT) keep the slanted orange style.

## Color: SoCal canyon dusk

Burnt orange #E8743B, sunset pink #E98A7A, Pacific blue #22334F, dusk purple
#3B2C4E, sage #8A9A7B, asphalt #1A1622. Paper #F1E9D8, tape #E9DFC6, ink
#1A1416, tool-chest red #A6262B. Keep #D64045 for danger/loss.

## Voice

Notes and captions are the BUILDER's handwriting (the player = Spire's voice).
All of them live in `godot/voice.gd`, written by Spire (Oct 2026): "straight
shitbox", "still pretty rough bud", "been locked in", "focus tf up pa come on",
"you fucked it pa"... Short, lowercase, texted. New notes: ask Spire for the
line, don't invent one. Whiteboard doodles are drawn (middle finger for the
rival, sad face after a loss), not written. Faba's lines (race night) are in
the same file, also in Spire's words: speech bubbles, never handwriting.

## The car

Faba's DX: Frost White, mechanically bone stock (physics unchanged), cosmetically
rough on day one: sun-faded clearcoat on roof and hood, one primer fender, a
missing hubcap, crusty steelies. It cleans up and gets kanjo'd as parts go on.
3D model: code-built EJ coupe for now (swappable parts), a real .glb later.

## Replay

Night lighting stays. Each road is a SoCal place: coast (PCH cliffs, ocean,
Armco), canyon (Malibu / Latigo rock-cut walls, chaparral, oaks), mountain
(Angeles Crest pines, higher). City lights below from high roads. Rival home
roads have a fixed place; open roads rotate. Gauges: Type R cluster (done).

## Build order

1. Foundation + home (fonts, theme, textures, drawer nav, home screen) - DONE
2. CAR lift, `$$$` corkboard + reveal, CAL whiteboard - DONE (rough pass, Oct 2026)
3. Race night at the turnout - DONE (rough pass: meeting + results; opponents built from their
   real proportions, widgets/car_model.gd)
4. Replay locations - DONE (rough pass: coast / canyon / mountain scenery, Best Motoring / VHS
   broadcast, roll-up + flagger intro, gap bar, slow-mo finish)
5. TEAM board - DONE (rough pass: Polaroids, driver / builder / record cards, memories)
6. Story - DONE (rough pass: VHS tape of the $50k night vs the 370Z, then Faba's texts; Claude's
   draft lines in voice.gd, Spire rewrites)

Rules from Overhaul 2: money is ALWAYS green, rep is ALWAYS orange.
