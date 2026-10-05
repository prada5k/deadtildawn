# Real car models (replacing the code-built shells)

The cars are built in code from boxes and extruded side profiles
(`godot/widgets/dx_model.gd`, `car_model.gd`). That's fast to change, but it
always looks blocky. The big jump in looks is a real 3D model. The game is
ready for one: drop a glTF file at `godot/models/dx.glb` and the DX uses it
everywhere (the lift, home, the turnout, the replay). Without the file, the
code-built shell is used, so nothing breaks while you work on it.

## What the model is, and what the code still does

The model is the **shell only**: body, glass, bumpers, lights, mirrors. The
code keeps building, on top of it:

- the **wheels** (they change with parts: steelies, lightweight 7-spokes,
  forged mesh, R-compound letters, camber, ride height),
- the **interior** (stock seats, buckets, the rear seat that goes away),
- the **exhaust tip** (stock, header, race canister: the flames come out here),
- the **body shop add-ons** (banner, stripes, stickers, lip, wings, tow hooks).

So leave the wheels and the interior OUT of the model (empty wheel arches,
nothing inside the glass).

## The DX we have (Oct 2026): built by a script

`art/blender/build_dx.py` builds the shell from numbers (a loft of
cross-sections, like a hull in CAD: the bottom line, the beltline and the
half width along the car, plus the roof line) and exports `dx.glb`. To change
the car, change the numbers and run it again:

1. Open `art/blender/dx.blend` in Blender.
2. Scripting tab > Open > `art/blender/build_dx.py` > Run Script (the play
   button). It rebuilds the car, exports `godot/models/dx.glb`, and saves
   `dx.blend`.
3. In Godot, F5. (The editor re-imports the .glb by itself when it gets
   focus.)

You can also sculpt `dx.blend` by hand and export it yourself (File > Export
> glTF 2.0, "glTF Binary", +Y Up, to `godot/models/dx.glb`), but running the
script again would overwrite your hand edits. Pick one way per change. To go
back to the old code-built car, delete `godot/models/dx.glb` (and its `.import`).

The materials the game swaps by name: **Paint** (respray color), **Roof**
and **Hood** (sun-faded on Faba's car; Hood turns carbon with the carbon
hood), **Fender** (the front right fender: primer until a respray),
**Glass** (tint), **Headlight / Taillight / Amber** (glow when the lights
are on). Trim and Plate stay as modeled.

## Wheels and body shop looks (models too)

- **Wheels:** `art/blender/build_wheels.py` builds `godot/models/wheels/`
  `wheels_stock` (14" steelie + an object named `Hubcap`, hidden on the
  front right of Faba's car), `wheels_light` (7 spokes), `wheels_forged` (10
  spokes). One RIGHT-side wheel per file, centered on the axle, its face
  toward Blender -Y; the game turns it around for the left side. Material
  `Rim` takes the wheel's color (or the body shop's rims), `Hubcap` the cap's.
  Mostly lathes (a profile spun around the axle) + one spoke copied around.
- **Looks:** `godot/models/looks/<body shop item id>.glb`, in the CAR's frame,
  replaces that item's code-built version (`dx_model.gd look_model`, for the
  stripes, lip and wing slots). `build_dx.py` builds `stripes_side`,
  `stripes_twin`, `wing_duck` and `lip` on the body's real surface; `Paint`
  takes the car's color, `Contrast` the stripe color. The GT wing comes from a
  picture (`art/looks/README.md`).

## The rules (so it lines up with everything else)

| What | Rule |
|---|---|
| Units | meters (Blender's default) |
| Size | the real EJ6: 4.45 m long, 1.70 m wide, roof at 1.34 m |
| Origin | on the ground, at the middle of the car (between the axles, halfway across) |
| Forward | Godot +X = Blender +X (the car's right side is Blender -Y) |
| Up | +Y in Godot (Blender's +Z; the glTF exporter converts it) |
| Right side of the car | Godot +Z |
| Axles | front at x = +1.275 m, rear at x = -1.345 m, track 1.47 m |
| Materials | at least **`Paint`** (body) and **`Glass`** (windows); the full list the game swaps is above. Anything else (trim, rubber) stays as you made it. |
| Size budget | keep it under ~20k triangles (two of these render at once on a phone, in split screen) |

## Making it in Blender (a rough path)

1. Find side, front, top and rear blueprints of a 1992-95 Civic coupe (EG/EJ) and
   set them up as reference images, scaled so the car is 4.45 m long.
2. Block out the body from a cube (subdivide, extrude along the profile),
   then refine. Keep it low-poly: a phone renders this at night, so big
   shapes matter more than detail. The silhouette is what reads.
3. Split the windows into their own material named `Glass`; give the body
   `Paint`.
4. Put the origin on the ground at the game's x = 0 (front axle 1.275 m ahead
   of it), the nose pointing along Blender's +X.
5. Apply scale and rotation (Ctrl+A > All Transforms).
6. File > Export > glTF 2.0, format "glTF Binary (.glb)", with +Y Up checked.
   Save as `godot/models/dx.glb`.
7. Open the game (F5): the DX on the lift is your model. Drag around it on
   the lift to check the wheels sit in the arches.

This is real CAD-adjacent skill (reference scaling, coordinate frames,
origins, low-poly modeling): the same frame conventions you'll meet in
SolidWorks or any simulation package.

## Faster but generic: free model kits

Kenney's free "Car Kit" (kenney.nl, public domain / CC0) has dozens of
low-poly cars that look good together. They're generic, though: no '96
Civic or 280Z, so the cars would lose their identity. It's a good stand-in
for background traffic or spectator cars later.

## Opponents

`car_model.gd` builds every opponent from its proportions. The same hook can
come later (`models/<car>.glb` by keyword) once there's a model to test with.
