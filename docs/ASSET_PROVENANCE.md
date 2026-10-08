# Asset provenance: Garage 1 (warehouse), props, cars

Downloaded 3D models used by the HOME scene. Author, license and source are copied from the
metadata Sketchfab embeds in each `.glb` (`asset.extras`); nothing here is inferred.

**Verification status.** The license field comes from the downloaded file. It has **not** been checked
against the live Sketchfab page, which is the authority. Until someone checks, every row is
**unverified**. Do not assume a license that is not listed here.

**Attribution status.** No credit screen exists in the game yet, so attribution for every CC-BY
asset below is **owed and not yet shown**. CC-BY 4.0 requires: title, author, source link, license
link, and a note that the model was modified. All of these models were modified (see "Changes").

## In use on HOME

| Role | Title | Author | License (per file) | Source | Prepared file |
|---|---|---|---|---|---|
| Garage 1 structure | Warehouse FBX Model Free | Nicholas-3D | CC-BY-4.0 | https://sketchfab.com/3d-models/warehouse-fbx-model-free-daa7fd3ff88945298d00045ca40a4c03 | `warehouse1_game.glb` |
| Player car (CHASSIS_0001) | Honda Civic EG6 (Low Poly) | RedUnLuckyBlockOSC | CC-BY-4.0 | https://sketchfab.com/3d-models/honda-civic-eg6-low-poly-67f1ae85642b46e5b54d123108975b5f | `eg6_game.glb` |
| Light switch | Simple Light Switch | BillieBones | CC-BY-4.0 | https://sketchfab.com/3d-models/simple-light-switch-32d02fa06d474f4db5a433aa134be612 | `warehouse_props_game.glb` |
| Ceiling fixtures | Fluorecent lights | Sean Thomas | CC-BY-4.0 | https://sketchfab.com/3d-models/fluorecent-lights-bca96f873b0743f88d61cd12b0750507 | `warehouse_props_game.glb` (4 ft strip, doubled, on two rods) |
| Hanging shop light | Low Poly hanging Light | Avadhoot | CC-BY-4.0 | https://sketchfab.com/3d-models/low-poly-hanging-light-b70dcbb9568846feb4758edcbefbe2c5 | `props/garage1/hanging_light.glb` |
| Locker | LowPoly Locker | anaamxria | **SKETCHFAB Standard** | https://sketchfab.com/3d-models/lowpoly-locker-4ffb1719b73c47dd9e2e731c0e5795a0 | `warehouse_props_game.glb` |
| Desk | PSX Table | Arimantos | CC-BY-4.0 | https://sketchfab.com/3d-models/psx-table-37c19b570ae74fea96cce7b39de52538 | `props/garage1/desk_table.glb` |
| Workstation PC (monitor, tower, keyboard, mouse) | Low Poly Retro PC | NobleCrow | CC-BY-4.0 | https://sketchfab.com/3d-models/low-poly-retro-pc-7d8881260cce4de39fc8fbc01ab47929 | `props/garage1/crt_monitor.glb`, `pc_tower.glb`, `pc_keyboard.glb`, `pc_mouse.glb` |
| Chair | Metal Folding Chair | Chen CheHsuan | CC-BY-4.0 | https://sketchfab.com/3d-models/metal-folding-chair-7a99fce4bdbd40e1b2949cdeb39a8fba | `props/garage1/folding_chair.glb` |
| Radio | PSX Style Satellite Radio | wooolvie | CC-BY-4.0 | https://sketchfab.com/3d-models/psx-style-satellite-radio-55f11b2c15ee4079a083858cf258a3c4 | `props/garage1/radio_base.glb` |
| Toolbox | Jagged Toolbox \| Game Ready | Skipperino | CC-BY-4.0 | https://sketchfab.com/3d-models/jagged-toolbox-game-ready-5aa1cd4642ce40728d0aae733ec7d765 | `props/garage1/toolbox_steel.glb` |
| Floor jack | Car jack | Jinhong Jeong | **CC-BY-NC-4.0 (NonCommercial)** | https://sketchfab.com/3d-models/car-jack-b07e82ed61d145d5a3294d74f6183368 | `props/garage1/floor_jack.glb` |
| Wall tools | tools pack, Tools pack 2 | Homie | CC-BY-4.0 | https://sketchfab.com/3d-models/tools-pack-59c5e176b95b4a0c9e0d9bd0f577a837 , https://sketchfab.com/3d-models/tools-pack-2-8c28443ed04c4564b570f3acc529102c | `props/garage1/hand_tools_a.glb`, `hand_tools_b.glb` |
| Shelving | Low-Poly Metal Shelf | Ronstu | CC-BY-4.0 | https://sketchfab.com/3d-models/low-poly-metal-shelf-d9f0169a2a254d5a8668d4cf598c743e | `props/garage1/metal_shelf.glb` |
| Cardboard boxes | Trash can | Broom | Broom PSX | Bonvikt | CC-BY-4.0 | https://sketchfab.com/3d-models/broom-psx-954fb26e27b04a09874da2e5795cc1fa | `props/garage1/broom.glb` |
| Shop rag | Dirty Rag | bimadwiananto | CC-BY-4.0 | https://sketchfab.com/3d-models/dirty-rag-0aeaa109e7bd49e19a6bd4963cd08aad | `props/garage1/shop_rag.glb` |

The `props/garage1/` files are under `godot/assets/models/props/garage1/` and are placed by `godot/home/garage1_props.tscn`.
Rebuilt from the raw sources by `art/blender/prep_garage1_props.py`.

**Open issue: the floor jack is CC-BY-NC-4.0.** NonCommercial: it cannot ship in a commercial release. It is
one node (`ToolArea/FloorJack` in `garage1_props.tscn`); replace or remove it before any commercial build.

Authors' profile links as embedded: sketchfab.com/Nicholas01, /RedLuckyBlockOSC, /BillieBones,
/Metallerz, /anaamxria. License text: CC-BY-4.0 = https://creativecommons.org/licenses/by/4.0/ ;
Sketchfab licenses = https://sketchfab.com/licenses

**Open issue: the two "SKETCHFAB Standard" props** (fixtures, locker) are not CC-BY. Their terms
differ (this record does not say how). Before shipping, someone must read the license page for
each and confirm (a) use inside a distributed game is allowed and (b) keeping the raw `.glb` in the
repository is allowed (matters if the repo ever goes public). If either fails, replace the model.

## Not model downloads (made by us)

Floor tiles, end walls, the painted-line/blot effects, the hardboard tool board behind the wall tools
(`ToolBoard`, a plain box in `garage1_props.tscn`) and the 32 px cardboard swatch on the boxes: generated by
`art/blender/prep_home.py`, `art/blender/prep_garage1_props.py` / `godot/home/`. The old primitive placeholder
boxes and bin are no longer exported (`PLACEHOLDER_PROPS = False` in `prep_home.py`). No attribution needed for these.

## Downloaded, not used by the current HOME scene (kept, nothing deleted)

| Title | Author | License (per file) | Source | Why unused |
|---|---|---|---|---|
| Honda Civic EG9 Sedan (Low Poly) | RedUnLuckyBlockOSC | CC-BY-4.0 | https://sketchfab.com/3d-models/honda-civic-eg9-sedan-low-poly-8f727e25234841c28bdd2eafe439de9e | **In use in replays** as Rafa's TEMPORARY VISUAL PROXY (not on HOME); prepared as `godot/assets/models/cars/eg9_game.glb`. Needs an in-game credit like the other CC-BY assets. |
| parking garage | SPLEEN VISION | CC-BY-4.0 | https://sketchfab.com/3d-models/parking-garage-98f7bc75350f4fb7ad36830f58fc99be | Retired HOME environment (replaced by the warehouse). Prepared output `garage1_game.glb` kept, unused. |
| Ceiling lowpoly fluorescent lamps with diffuser | Metallerz | **SKETCHFAB Standard** | https://sketchfab.com/3d-models/ceiling-lowpoly-fluorescent-lamps-with-diffuser-95cdcff49c484b66a966269d84143615 | Replaced by the strip fixtures (the big square diffuser panels were removed). Raw file kept. |
| Roll of paper towel | TobiG | **CC-BY-NC-SA-4.0** | https://sketchfab.com/3d-models/roll-of-paper-towel-24e92a25b0aa49c688d477ed58c7ff9e | Skipped: NonCommercial + ShareAlike, a 107,802-triangle photoscan that does not match the look. |
| PSX Handheld Camcorder VHS Horror Camera | ZwiebelGames | CC-BY-4.0 | https://sketchfab.com/3d-models/psx-handheld-camcorder-vhs-horror-camera-eb4582db00b34bca8fb4382edaae10d8 | Not part of the Garage 1 props milestone (HOME's camcorder is the overlay, not a model). |

Raw sources: `art/models/scenes/`, `art/models/cars/`, `art/models/warehouse props/` (never edited).

## Changes made to the models (required to disclose under CC-BY)

- Warehouse: cropped to a ~19 m section, rotated/moved to the game frame, textures removed and
  replaced by flat per-face colors, the floor replaced by a generated one, end walls added.
- EG6: sticker meshes removed, scaled and re-oriented, wheels separated, materials renamed and
  re-tuned (roughness, lamp emission), textures removed.
- Switch and fixtures: textures removed, scaled; the pack's OFF fixture was dropped.
- Locker: texture reduced to flat per-face colors.
- Garage 1 props (`props/garage1/*.glb`): scaled to real-world sizes, re-oriented (front = +Z), origins moved to the floor, textures downsized (128 to 512 px), desaturated and dusted, normal / ORM / emissive maps dropped, nearest-neighbour filtering, flat shading; the floor jack, wall tools were reduced in triangle count (12,916 to 2,800; 1,524 to 900; 3,534 to 1,700). The retro PC is split into monitor / tower / keyboard / mouse. The cardboard boxes keep only their geometry (straightened, scaled x1.4, UVs regenerated) and use a generated swatch instead of the pack's texture, which is printed with a modern-looking "MoveOn" logo.
- EG9 (replay proxy): scaled to 4.38 m, re-oriented, wheels separated, materials renamed and re-tuned, textures removed, repainted Frost white (the source is red).

## Checklist before any public build

1. Verify each license against its live Sketchfab page; update this file.
2. Resolve the two Sketchfab Standard props (confirm terms or replace).
3. Add an in-game credits screen listing every in-use CC-BY asset (title, author, link, license,
   "modified").
