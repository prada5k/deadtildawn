# Phase 7B rival replay visual proxy

Rafa's simulated and saved vehicle remains the stock `ej6_dx_coupe_1996`
definition. The simulation bridge loads that EJ6 definition, and race results
continue to snapshot its EJ6 vehicle ID and resolved physical parameters.

The supplied `art/models/cars/eg9.glb` is selected only as a **TEMPORARY VISUAL
PROXY** for Rafa's replay. It depicts a Honda Civic EG9 Ferio sedan. It is not
an EJ6, is not a visually accurate representation of Rafa's simulated EJ6 DX
coupe, and must not be relabeled as one. Its visual identity and disclaimer
are recorded in `data/rivals/oxnard_eg6_time_attack.json` and copied into that
rival replay's non-physical `vehicle_visual` metadata.

The replay viewer selects a model through replay metadata (`vehicle_visual.visual_id`
and `asset_path`). To replace this proxy while keeping existing replays current,
replace the GLB at the selected path and retain the stable visual ID. A different
path can be selected in the rival profile for future runs without changing the
simulation or game saves. Do not change the rival's `vehicle` definition to
replace its appearance. The viewer reads the raw GLB at runtime;
it does not convert or edit the source asset. If the path is missing or the
model cannot load, the generic replay marker remains available and the replay
shows a proxy/load notice.

## Asset attribution

- Title: Honda Civic EG9 Sedan (Low Poly)
- Creator: RedUnLuckyBlockOSC ([Sketchfab profile](https://sketchfab.com/RedLuckyBlockOSC))
- Source: [Sketchfab model page](https://sketchfab.com/3d-models/honda-civic-eg9-sedan-low-poly-8f727e25234841c28bdd2eafe439de9e)
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- Changes: the source GLB is kept byte-for-byte; the replay viewer scales and positions it at runtime for framing.

The GLB's embedded glTF `asset.extras` contains the same title, creator, source,
and `CC-BY-4.0` license metadata. CC BY 4.0 permits commercial sharing and
adaptation when its attribution terms are met. That license does not itself
grant trademark or other third-party rights; this record documents the model
author's stated asset license, not separate Honda brand permissions.

This selection is replay-only presentation data. It does not change physics,
the save schema, the permanent player Civic, the rival vehicle ID, or historical
race configuration snapshots.

## Update: prepared model and the 3D rear camera

The replay's REAR camera (`godot/widgets/replay_chase.gd`) draws the proxy as a prepared, game-ready model,
`godot/assets/models/cars/eg9_game.glb` (made from the unchanged raw `art/models/cars/eg9.glb` by
`art/blender/prep_home.py`, stage `eg9`: scaled to the real 4.38 m, nose +X, tires on the ground, wheels
separate, Frost-white paint so it reads apart from the red EG6). It is selected by the stable
`vehicle_visual.visual_id` (`eg9_ferio_temp_proxy`), so already-saved rival replays and the rival profile
(`asset_path`) are unchanged; the 2D views still use the raw path above. If the prepared file is missing, the
3D view shows the generic low-poly marker. The top bar still prints the proxy disclosure
(`TEMPORARY VISUAL PROXY / ... / SIM / 1996 Honda Civic DX Coupe`). The rival's gauges use his own recorded
redline (6500) and fuel cut (6800).
