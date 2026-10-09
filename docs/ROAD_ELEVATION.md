# Phase 8A.1 — road elevation contract

The existing pace notes, `track_xy`, `TrackGrid.s`, corner boundaries, and
replay `samples.s` measure **horizontal plan-view centerline distance** `s` in
meters. A corner's published radius and `TrackGrid.curvature` are plan-view
geometry: `k_xy = d(heading)/ds`. They do not become 3D arc lengths when a
profile is attached. This preserves the coordinates and hashes of every
existing flat road.

An elevated road specifies `z(s)` in meters. The new fixture uses a clamped
cubic spline through authored `(s,z)` points. Endpoint grades are explicit;
height, grade `q=dz/ds`, and `dq/ds` are continuous at every join. The loader
requires finite, strictly increasing samples from zero to the base road's
horizontal length and rejects grades above 12%. These are fixture validity
checks, not claims that real roads cannot be steeper.

The car's velocity `v` is **3D path speed**. For each horizontal grid interval,
the solver integrates traveled distance

`dℓ = sqrt(1 + q²) ds`, `θ = atan(q)`, `sinθ = q/sqrt(1+q²)`.

The distance-step formulas `v₂²=v₁²+2aΔℓ` and
`Δt=2Δℓ/(v₁+v₂)` use `Δℓ`, including in the backward braking envelope.
Shift positions are mapped back to horizontal `s` for telemetry and replay.
The original 0.5 m discretization remains **horizontal**; the elevated path
step is slightly longer. Forces are sampled at each step's start, as with the
existing flat solver. Convergence against a 0.25 m grid is required.

## Force model

- Gravity along the tangent is `-m g sinθ`. It enters longitudinal resistance
  once, under power, during shifts, and during braking.
- The road-normal acceleration is `g cosθ + v² κ_v`, where
  `κ_v=dθ/dℓ=(d²z/ds²)/(1+q²)^(3/2)`. The corresponding contact normal
  `N=m(g cosθ+v²κ_v)` sets rolling resistance `Crr N`, axle loads, tire
  load sensitivity, FWD traction, and the lateral limit. Crests reduce N;
  compressions increase it. A run that loses contact is rejected because
  airborne motion is outside this solver.
- Aerodynamic drag remains `½ρCdAv²`, opposing the 3D tangent velocity.
  Atmospheric density is held constant; the small test hill does not model
  altitude-dependent air density.
- On a slope, front/rear pitch transfer uses the acceleration attributable to
  longitudinal contact force, approximated by `a_t + g sinθ`. Gravity's
  free-rolling acceleration therefore does not create fictitious pitch
  transfer. The existing flat drag/rolling transfer approximation remains.
- The plan-view yaw curvature produces lateral acceleration
  `a_y=v² k_xy cos²θ`. The elevated corner speed solves this demand against
  the speed-dependent load-sensitive tire limit. Driver corner positions and
  authored radii stay in horizontal `s`; no arbitrary hill speed multiplier
  is applied.

The solver remains quasi-steady and unbanked. It does not model suspension
travel, pitch inertia, wheel lift in the longitudinal direction, airborne
flight, banking, or a 3D racing line. Those limits matter when a later phase
builds 3D replay geometry; visible road pitch must follow the saved profile,
and any jump/compression animation must not change recorded measurements.

## Identity and compatibility

`LOCAL_STRAIGHT` and `LOCAL_CURVES` still use their original files,
`geometry_version: 1`, hashes, and flat solver path. The separate
`LOCAL_CURVES_ELEVATED_V2` fixture refers to the unchanged LOCAL CURVES
pace notes and declares their SHA-256. Its geometry hash covers both the
base pace-note bytes and the elevation manifest bytes. It is available only
through the development bridge command `local_curves_elevated`; the scheduled
competitive event still uses flat LOCAL CURVES.

Flat replays remain `deadtildawn-replay` version 1 with their original
structure. Elevated replays use version 2: the same 2D `centerline`, plus
`centerline_z`, spline control samples/endpoint grades, and per-sample `z`,
`grade`, and 3D `path_s`. The Godot 3D rear view evaluates the same clamped
profile at horizontal `s` for the road mesh, subject, and virtual camera car;
the four 2D cameras intentionally remain plan-view projections. Road grade
rotates the car's wheels and body as a single parent, while recorded-input
body motion remains on its separate child. On this unbanked road the lateral
lane offset has the centerline height. The road is sampled at approximately
1 m horizontal intervals for the mesh, so curvature between mesh vertices is
a visual polygonal approximation of the continuous spline. There is no
terrain deformation, airborne animation, or physical bank in this milestone.
The elevated rear camera uses a wider fixed field of view for 390×844 portrait
framing; v1 camera parameters stay unchanged. Save version 14 is unchanged.
Saved historical event/results and replay files are read as recorded and are
never resimulated by this feature.
