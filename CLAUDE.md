# CONTRABAND96

> **THIS IS MY CIVIC.**

CONTRABAND96 is a portrait-mobile car-building / vehicle-setup simulation built around one 1996 Honda Civic EG6 hatch, one home garage, and a living late-1990s / early-2000s Southern California car scene.

The player **never drives the car**.

The player:

**BUILDS → SETS UP → COMMITS → WATCHES → ANALYZES → LEARNS**

Racing is the experiment that tests the player's engineering decisions. The physics decides what is fast.

This document is the project constitution, design bible, technical direction, migration guide, and operating manual for Claude Code. When an older implementation conflicts with this document, do not silently rewrite it. Preserve working code, identify the conflict, and migrate deliberately.

---

# 1. NON-NEGOTIABLE DESIGN RULES

## 1.1 This is my Civic

The 1996 EG6 hatch is the protagonist. The player does not progress by discarding it for faster cars.

The same chassis persists for the entire save. Its mileage/use, parts, panels, paint, stickers, damage, repairs, setup history, race history and visual identity accumulate over time.

The early-game and late-game car may look almost unrelated, but they are the same chassis.

There is no Civic → Integra → S2000 → NSX ladder.

Progression means:

> **I know this car better now.**

The game must support radical reinvention: clean NA street car, stripped battle car, turbo build, stance/show build, serious time-attack setup, or something strange. There is no final or universally correct build.

## 1.2 One car. One garage.

The player keeps the same home garage for the entire save.

The garage does not become a mansion or glossy showroom. It accumulates tools, removed parts, wheel boxes, damaged panels, memorabilia, sponsor objects, photographs, clutter and history.

The emotional constants are:

> **THE CIVIC — what you built.**  
> **THE GARAGE — what you accumulated.**  
> **THE TAPES — what happened.**

## 1.3 The player never drives

Never implement steering, accelerator, brake, clutch, shifting or other player-driving controls.

The race is a simulation the player watches.

The signature race presentation is the existing **low rear chase view**, with restrained live telemetry such as speed/RPM, gear, throttle, brake and timer/delta where appropriate.

Optional cameras may later include higher chase, bumper, roadside/TV or MiniDV spectator views, but the low rear camera remains the signature view.

The player's reference driver must be consistent enough for engineering comparisons. The same car/setup/road/conditions should produce very similar results. Do not secretly level up the reference driver and contaminate A/B testing.

Rivals may have distinct driving tendencies.

## 1.4 Racing is the focus, but racing is not every day

> **Racing is the focus of CONTRABAND96, but racing is not the majority of the player's clicks. Everything between races exists to make the next race matter.**

Serious races should feel like the payoff to days of finding parts, testing, tuning, repairing, watching weather, hearing rumors and deciding whether the Civic is ready.

Do not schedule competitive races every in-game day. Quieter periods of garage work, testing, shopping, pickups, deliveries, meets and planning create anticipation.

A social/competitive event happens once. Roads may return later. Avoid grindable repeated race payouts.

## 1.5 No presets

This is a hard rule.

No:
- build presets
- style presets
- “Kanjo build”
- “track build”
- “stance build”
- recommended packages
- one-click physical configurations
- magic loadouts that install parts

The player finds parts, buys/orders them, physically installs them, removes them, damages them, repairs them, replaces them and tunes them.

A setup notebook may remember adjustment values. It must never magically install physical components.

Core ownership loop:

**FIND → BUILD → TEST → RACE → BREAK → FIX → LEARN → FIND**

## 1.6 The physics decides what is fast

There are no arbitrary RPG performance bonuses.

Never implement:
- +12 handling
- +8 speed
- PERFORMANCE 87
- hidden “player level” grip
- rarity-based stat superiority
- invisible skill-tree vehicle bonuses
- event-specific fake handling modifiers

Every meaningful performance modification changes physical properties. Those properties interact with road, weather, surface, driver, condition and setup.

Expose physical values where useful:
- mass
- torque/power curve
- gearing/final drive
- wheel/tire dimensions and mass
- tire grip/compound/condition
- spring/damping/ride height
- alignment
- brake capability/temperature
- drag/downforce
- damage/condition

Human-readable observations may interpret measured behavior. They must not prescribe an optimal solution.

## 1.7 No aesthetic score

There is no correct-looking Civic.

No:
- style score
- build rating
- “perfect fitment”
- cleanliness bonus
- battle-style bonus
- forced symmetry

Clean builds, stance/show builds, sparse builds, battle cars and sticker-covered cars are all valid.

Physics may create consequences for extreme fitment or unsuitable hardware. The game does not moralize about taste.

---

# 2. CORE GAME LOOP

North star:

> **CONTRABAND96 is a car-building RPG/sim where the road is the puzzle and the Civic is your solution.**

Mechanical loop:

**BUILD → SET UP → COMMIT → WATCH → ANALYZE → LEARN**

World loop:

**SCOUT → THINK → BUILD → TUNE → TEST → RACE → ANALYZE → LIVE WITH IT → PROGRESS**

A typical week can include:

1. Garage/world updates.
2. Classifieds rotate, deliveries arrive, forum posts and rumors appear.
3. Player checks CALENDAR and opportunities.
4. Player investigates road/conditions.
5. Player buys, installs, removes or repairs parts.
6. Player tunes only what installed hardware + knowledge + access allow.
7. Player optionally tests on permanent local roads.
8. Player commits to a time attack.
9. Simulation resolves the actual physical consequences.
10. Player watches the Civic run.
11. Results explain **what happened**, not what to buy.
12. Wear, damage, money, followers, relationships, rivals and world state update.
13. Important runs may become tapes.
14. Time advances and the world continues.

No XP is required to make this loop work.

---

# 3. RACING AND TIME ATTACK

Time attack is the primary competitive structure.

Most serious events do not require wheel-to-wheel racing. Prefer separate/equivalent-condition runs and target times. This avoids unnecessary overtaking/collision AI and keeps the focus on engineering.

A rival may establish a time, or both cars may make separate simulated runs.

The emotional question is:

> **Can my Civic beat that number?**

Losing is not “FAILED EVENT.” A 0.41 s loss can be more interesting than a five-second win because it creates an engineering question.

Major events become important through context, not labels such as BRONZE / GOLD / LEGENDARY.

Importance can emerge from:
- people talking about the event
- preparation time
- invitation
- familiar rivals
- money/history
- weather uncertainty
- road reputation

Do not create procedural difficulty escalation. Roads do not level up. Challenge comes from target times, competitors, conditions, consequences and player ambition.

---

# 4. TESTING: THE PLAYER'S LABORATORY

Testing is not filler and is not limited to a straight road.

Permanent local test roads never regenerate.

At minimum, support:

## LOCAL STRAIGHT
Used for:
- 0–30
- 0–60
- 0–100 later
- 30–60 / 40–80
- 60–0
- launch behavior
- wheelspin
- shift points
- RPM/speed/throttle traces

## LOCAL CURVES / LOOP
Used for:
- total time
- corner minimum speeds
- braking points
- exit speeds
- lateral acceleration
- rough-section behavior
- bottoming
- tire behavior
- setup comparison

Geometry stays fixed so A/B testing remains meaningful. Conditions may vary.

The TEST LOG should support a long history of runs.

Testing may eventually consume tire/brake/component wear and time. Early implementations may use time alone.

Example tuning behavior: if ECU/hardware + knowledge allow launch RPM adjustment, the player changes RPM, runs tests and observes bog/wheelspin. The game never states the optimal launch RPM.

---

# 5. ROAD AND ENVIRONMENT MODEL

The world is finite and recognizable. Roads provide variation.

> **Persistent content with changing context, not infinite forgettable content.**

Persistent low-poly SoCal environment families include:
- Oxnard / Ventura: home territory, industrial streets, agricultural edges, coastal influence
- Coast / PCH: ocean, cliffs, sweepers, marine layer
- Malibu / Santa Monica Mountains: tighter canyon environments
- Los Angeles: parking structures, industrial districts, concrete/freeway infrastructure
- Angeles Crest / mountains: elevation, rocks, guardrails, long mountain roads

Locations may be fictionalized from real geography rather than 1:1 recreations.

## Road layers

**GEOMETRY**
- curvature/radius
- straights
- width
- direction
- entry/exit geometry
- racing line

**VERTICAL PROFILE**
- elevation
- grade
- crests
- compressions

**SURFACE**
- grip
- roughness
- patches/local differences

**CONDITIONS**
- temperature
- wetness
- rain
- fog/visibility

**ENVIRONMENT**
- low-poly SoCal visual wrapper

Grip and roughness are different variables.

Elevation must be physical:
- uphill affects gravity, power-to-weight and gearing
- downhill affects gravity, braking and brake temperature/fade

The same road may support uphill and downhill events without arbitrary modifiers.

## Authored vs procedural roads

Keep authored:
- HOME test straight
- HOME curvy test road
- several signature/landmark roads

Use procedural + persistent generation for many discovered competitive roads.

Procedural generation happens behind the social world. Never expose a “GENERATE TRACK” button.

Once discovered, a road receives a persistent identity. Save its seed/geometry/history. The same hairpin, rough patch or compression remains when revisited.

Road generation must satisfy engineering constraints such as curvature continuity, reasonable radii, width, elevation gradients, no impossible overlaps, useful braking opportunities and valid start/finish.

Long roads may later expose LOWER / FULL / UPPER sections.

Surface can occasionally evolve through repaving/patching, but rarely enough that history remains useful.

Old roads never become obsolete.

---

# 6. ROAD INTELLIGENCE

Separate instrumented facts from human information.

Objective measurements may include:
- length
- elevation gain/loss
- major corners
- tightest radius
- longest straight
- full-throttle percentage
- surface measurements
- temperature/weather

Human/forum/crew intel can be imperfect:
- “surface gets rough near the top”
- “water sits in turn 6”
- “brakes cooked last time”
- “heard they repaved part of it”

Information can be uncertain/outdated/wrong, but not unfairly so.

Never turn road intelligence into recommended setup instructions.

---

# 7. RESULTS, TELEMETRY AND ANALYSIS

Core principle:

> **Results answer “what happened?”, never “what should I buy?”**

## Layer 1: result

Immediate emotional result:
- finish/freeze-frame
- time
- target/rival
- gap
- WIN/LOSS where relevant
- cash
- followers
- no XP

Physics-derived breakdown may include:
- braking
- corners
- exits
- high speed
- tire fade
- mistakes

Comparison options can include:
- rival
- previous run
- personal best

## Layer 2: sector analysis

Route/elevation trace with sector deltas and measured observations.

Examples:
- lowest exit RPM
- full-throttle %
- exit acceleration relative to comparison
- significant tire slip
- bottoming events

Do not say “final drive too long” or “buy softer springs.”

## Layer 3: telemetry

Plot versus distance/time:
- speed
- RPM
- gear
- throttle
- brake

Later:
- longitudinal/lateral acceleration
- tire slip
- brake temperature
- tire temperature/condition
- suspension travel
- bottoming

Overlay current run against PB/rival/previous.

A telemetry point should eventually be able to jump replay to the same moment/location.

Every run should snapshot exact car configuration + conditions.

“CHANGES SINCE LAST RUN” should compare physical changes. If the player changed multiple variables, do not infer causality.

---

# 8. RUN LOG AND TAPE ARCHIVE

These are different systems.

**RUN LOG** = every simulation/test result.

**TAPE ARCHIVE** = player-preserved runs + major events automatically preserved.

A tape can store:
- date
- location
- direction/section
- result
- time
- exact car configuration
- conditions
- memorable low-poly freeze-frame
- handwritten player note
- replay reference

The archive should become a visual biography of the Civic.

Old tapes must preserve the car appearance/state from that moment.

---

# 9. VEHICLE PHYSICS DOMAINS

The long-term model may include:

## Engine/powertrain
- torque/power curve
- engine mass
- response
- gearing
- final drive
- differential
- transmission ratios
- drivetrain loss
- eventual swaps

## Mass/chassis
- total mass
- weight distribution
- interior removal
- seats/battery/body components
- reinforcement
- possible CoG effects

## Wheels/tires
- compound
- width
- diameter
- sidewall
- wheel mass
- wear
- temperature
- wet grip
- pressure later

## Suspension/geometry
- spring stiffness
- damping
- ride height
- available travel
- camber
- toe
- anti-roll stiffness
- rough-road compliance

## Brakes
- force/capacity
- thermal capacity
- fade
- pads/rotors
- wear

## Aero
- drag
- frontal effects
- lift/downforce balance
- speed-dependent consequences

## Environment
- grade/elevation
- surface
- bumps
- temperature
- wetness/rain

## Condition
- tire/brake wear
- component damage
- alignment
- worn parts

Suspension may be a credible abstraction rather than full multibody dynamics. Physical readability matters: stiff/low cars should visibly respond differently to rough pavement; bottoming should have consequences.

Weather changes physical conditions. Never implement “RAIN: -20% HANDLING.”

Aero must be physical: drag/downforce scale with speed.

---

# 10. PARTS AND OWNERSHIP

No part levels.

OEM may outperform cheap aftermarket hardware in some properties. Expensive parts are not automatically superior in every context.

Useful categories include:
- engine
- drivetrain
- wheels
- tires
- suspension
- brakes
- chassis
- weight/interior
- aero/body
- exterior/interior accessories

## Definitions vs instances

A **part definition** describes what a product/component is.

An **owned item instance** describes the player's specific physical object.

Meaningful owned instances should have stable IDs and may eventually store:
- definition ID
- source/seller
- acquisition week/date
- acquisition price
- condition
- wear
- damage
- installed state/position
- repair history
- provenance/history

Do not destroy the existing inventory UID concept. Evolve it.

A sold part may eventually appear on an NPC car.

---

# 11. ECONOMY AND PARTS ECOSYSTEM

Core feeling:

> **You build the Civic you can build, not necessarily the Civic you planned.**

Progression:
- early = resourceful
- mid = connected
- late = intentional

Acquisition channels:

## USED
Forum classifieds, local sellers, swap meets, junkyards. Cheap, rotating, unpredictable, variable condition.

## RETAIL
Reliable common/new consumables and components. Predictable, more expensive. Basic necessities remain available so RNG cannot cripple a save.

## IMPORT
Expensive, slow, specialized/period Japanese parts. Orders can take weeks and arrive with packaging/docs/stickers.

## CONNECTIONS
Private/off-market access through shops, crews, rivals, sponsors and sellers.

Prices do **not** scale with player level/week.

No rarity colors, rarity tiers, pity system or gacha.

Condition/specification/provenance/availability replace rarity.

Classified listings should exist independently of the player: persist, sell to NPCs, change price, receive comments, disappear.

Negotiation can stay simple: BUY / OFFER / counter.

Selling should be asynchronous: player posts an owned part with an asking price and waits for interest. Avoid an instant universal sell-to-void button.

Racing is an important economic engine, but not every race needs a large payout. Some events primarily provide history, visibility, relationships or invitations.

Custom wheel ordering can eventually expose model, diameter, width, offset, finish and quantity, with a real multi-week wait. Custom does not mean stat superiority.

Shops are relationships, not “Shop Level 4” catalogs.

---

# 12. KNOWLEDGE, HARDWARE AND ACCESS

Mechanical progression uses three questions:

> **KNOWLEDGE — do I understand it?**  
> **HARDWARE — does the car support the adjustment?**  
> **ACCESS — do I have the tools/facility/person required?**

Example: the player may understand rear camber, but stock hardware is fixed. Adjustable arms provide hardware. Measurement/alignment capability still requires access.

The starting player is already an enthusiast and can handle basic maintenance, wheels/tires, bolt-ons, interior removal, simple suspension replacement and basic body work.

Advanced capability develops through:
- working on systems
- TECH forum material
- testing
- shops
- mentors/relationships
- racing observations

No generic skill points or XP grind.

Knowledge never creates invisible performance bonuses. It improves observation, adjustment, diagnosis and work capability.

Progression can branch through chassis, engine, drivetrain, brakes/tires, aero/body and electronics/data.

Shops fill knowledge/access gaps. The player can pay for work they cannot perform.

Tools become physical HOME progression without becoming a tool-shopping simulator.

Information precision should improve with knowledge/access.

Major capabilities should unlock slowly; small progress should occur frequently enough to avoid stagnation.

---

# 13. CUSTOMIZATION AND VISUAL IDENTITY

The starting EG6 should be relatively ordinary so visual history can accumulate.

Body parts are physical possessions. Removed stock parts remain in inventory. Damage belongs to the installed part. Junkyard replacement panels keep their actual color/condition unless painted.

Mismatched panels are supported.

Paint can be simple:
- color
- finish
- condition

Wheels deserve physical depth:
- design/model
- diameter
- width
- offset
- mass
- finish
- condition

Tires are separate:
- width
- aspect ratio
- compound/model
- condition

Front/rear mismatch is allowed where physically plausible.

Extreme fitment is not blocked for aesthetics. Physical consequences handle rubbing/contact/travel.

Interior should visibly evolve. Meaningful removals affect mass.

Stickers are inventory possessions obtained through parts, events, crews, sponsors, shops, imports, forum/community and personal sources.

Sticker editor:
- move
- scale
- rotate
- flip
- remove
- body/windows
- no forced symmetry
- no mandatory snapping
- banners as a larger special type

No build/style presets.

---

# 14. DAMAGE, WEAR AND REPAIR

> **Wear is predictable. Damage is consequential. Failure is explainable.**

> **CONTRABAND96 does not punish the player for using the car. It records the consequences of how the car was built, maintained and raced.**

Tires are the most important consumable. Model gradual tread/heat-cycle/wear behavior rather than a 100→0 health cliff.

Brakes separate wear from temperature/fade.

Normal engine use should be forgiving. Risk increases through aggressive tuning/boost, heat, insufficient supporting hardware, poor used parts and repeated abuse. Warning signs should usually exist.

Suspension wear is slow; crashes accelerate it.

Individual wheels may bend and retain damage.

Crashes emerge from physical conditions, not random post-race crash rolls:
- excessive speed
- insufficient grip
- instability
- wet surface
- bottoming
- brake fade
- component failure

Severity can range from cosmetic to major mechanical damage.

Cosmetic and mechanical condition remain separate. No universal “CAR CONDITION 68%.”

No one-click REPAIR ALL. Diagnose specific issues and decide what to repair, replace, straighten or leave.

Major repairs consume calendar time and produce visible WIP states.

The Civic cannot be permanently deleted from the save. Severe consequences may force cheaper repairs, stock components, selling parts, waiting or entering smaller events, but the same chassis comes home.

---

# 15. CALENDAR AND TIME

> **Time exists to make the car scene feel alive. The calendar creates choices and consequences, but never asks the player to optimize their daily life.**

Primary unit: **day**, not hour-by-hour life simulation.

Instant/menu actions generally do not advance time:
- browsing forum/classifieds
- inventory
- saved setup values
- tapes
- planning
- cosmetic sticker placement

Activities/work can consume meaningful time:
- testing
- meet
- race
- distant pickup
- shop visit
- installation
- repair
- engine work

Avoid rigid “one action per day.”

## WIP states

Major jobs should physically affect HOME.

If the Civic is on jack stands with suspension apart, the calendar can show IN GARAGE and the player may miss an event.

Deliveries/custom orders use calendar time and uncertainty.

The player should sometimes miss opportunities. The world continues without them. Missing one event must not permanently lock core progression.

No end-of-week score, XP or rank.

Calendar = life history.  
Tape Archive = racing history.  
Garage = physical history.

---

# 16. FORUM AND SOCIAL WORLD

SHOP is integrated into a fictional early-web enthusiast forum inspired by old Honda/import forums.

Possible sections:
- GENERAL
- TECH
- FOR SALE
- SPOTTED
- RUNS

Use usernames, timestamps, replies, local rumors, classifieds and consequences.

The forum is the social nervous system.

Update it with a handful of meaningful daily changes, not hundreds.

Forum information may be wrong/outdated. Instrumented facts remain distinct from people talking.

Prefer 15–30 memorable recurring people over hundreds of shallow NPCs.

---

# 17. RIVALS, CREWS AND THE LIVING SCENE

> **NPCs exist in the same car culture as the player; they do not merely wait to race the player.**

Important NPCs can have simplified persistent state:
- resources
- preferences
- driving style
- car/build
- owned notable parts
- relationships
- goals

They do not require full offscreen life simulation.

Rivals have persistent cars that physically evolve. Never scale them with arbitrary +difficulty stats.

NPCs can make bad/non-optimal engineering choices.

Rivalries emerge from repeated history. Do not display “RIVAL UNLOCKED.”

NPCs can disappear, sell cars, damage engines, change crews, return with different builds or stop racing.

Crews are social clusters, not stat factions. Independent play remains fully viable.

TEAM should evolve from sparse contacts into a network of people, crews, shops, sponsors, importers, mechanics and rivals. Avoid friendship meters where natural history/notes can communicate the relationship.

---

# 18. FOLLOWERS AND SPONSORS

REP is legacy. The intended social visibility metric is **followers**.

Followers represent attention, not skill.

They may influence:
- invitations
- sponsor interest
- private listings
- forum visibility/sections
- seller/rival/crew opportunities

Followers never alter vehicle physics.

Sponsors create tradeoffs and obligations, not free stat bonuses. A supplied tire may be physically wrong for the next road. Sponsor decals/banner/meet appearances can matter.

---

# 19. LONG-TERM PROGRESSION

Late game does not mean graduating from street-level car culture.

It means becoming deeply embedded in it.

Early:
- sparse calendar
- few contacts
- public classifieds
- ordinary customer treatment
- local events
- nearly ordinary Civic

Recognition accumulates through repeated presence, not one giant unlock.

Late:
- more opportunities than the player necessarily wants to pursue
- established rival histories
- specialist relationships
- private sellers
- advanced tools/knowledge
- meaningful custom/import orders
- a garage full of history
- a Civic with a visible biography

Major progression is deliberately slow and memorable. Small progress happens often enough to avoid stagnation.

There is no final car and no universal final opponent.

An eventual story may have a climax, but the mechanical world can remain open afterward.

Late-game nostalgia is a feature: Week 3 tape versus Week 100 tape should communicate progression better than a LEVEL 73 badge.

---

# 20. VISUAL AND AUDIO CONSTITUTION

## ALWAYS LOW POLY

Every 3D world element must visibly read as stylized low-poly:
- cars
- parts
- wheels
- garage props
- environments
- roads
- shops
- people if present
- 3D imagery inside UI

Use faceted geometry, simplified materials, flat/limited shading, intentional polygon reduction and recognizable but non-photorealistic forms.

Do not drift toward photorealism.

## Graphic identity

Locked direction:
- portrait mobile
- late-1990s / early-2000s Southern California street-racing culture
- MiniDV/VHS camcorder aesthetic
- photocopied tuner zine / garage notebook / early-web language
- dirty black/charcoal
- off-white typography
- restrained red accents
- scratched/distressed borders
- tape/paper/handwriting/halftone/grain/scanlines
- physical/analog rather than futuristic

No:
- glassmorphism
- glossy modern cards
- neon cyberpunk
- rarity colors
- generic mobile-game polish

Target cultural balance: roughly **65% SoCal / 35% Kanjo influence**.

California is the world. Kanjo contributes Honda/build/crew/raw-functional influence.

Do not add Japanese environmental/location text merely for flavor. Imported Japanese products/stickers may legitimately contain Japanese branding.

Use US dollars.

## HOME layout language

Current approved direction:
- upper ~55–58%: camcorder view of actual Civic in Garage 1 (the Oxnard warehouse, section 21)
- lower ~42–45%: grimy/zine-like UI
- camcorder REC/date/time/SP/battery language
- SETTINGS as distressed tape label
- location metadata such as GARAGE 1 / OXNARD, CA
- top-right cash + followers
- contraband96 / SOCAL branding
- main nav order: **CAR / CALENDAR / HOME / TEAM / SHOP**
- text-only nav
- restrained rough red active marker
- STROBE bottom-right
- no separate LIGHT control
- environmental collage/scraps allowed

HOME camera can idle subtly. Use fluorescent flicker, VHS tracking, autofocus/exposure pulse, distant traffic, radio/fan/CRT ambience, weather and post-run cooling sounds.

Race sound is crucial because the player watches. RPM, shifts, throttle modulation, tire scrub, scraping/bottoming, impacts, turbo sounds and stripped-interior rawness can communicate physics.

---

# 21. GARAGE / HOME IMPLEMENTATION PHILOSOPHY

HOME is an anchor, not a point-and-click adventure.

## Garage 1: the Oxnard warehouse

**Garage 1 is a permanent low-poly industrial warehouse bay in Oxnard, California.** It is the player's one garage for the entire save (section 1.2). It replaces the earlier parking-structure garage, which is retired as a HOME environment (the old prepared file `godot/assets/models/scenes/garage1_game.glb` and the raw scan `art/models/scenes/parking_garage.glb` are kept, unused).

- Look: 1996 SoCal industrial. An arched steel hall with ribs, side-wall panels and a clerestory strip, matte faceted concrete floor, muted putty-gray palette, fluorescent fixtures. Aged, not abandoned; a modest personal work bay, never a showroom. No Japanese environmental text.
- The Civic parks beside the long side wall, nose toward the camera (+x is the nose). The prepared models share one origin: where the Civic parks, floor at y = 0, the side wall 2.6 m behind it (z = -2.6). The visible space is a cropped ~19 m section of the source hall, closed by plain end walls.
- Files: `godot/home/home_garage.tscn` / `.gd` (hooks: `CivicAnchor`, `VehicleVisual`, `GarageVisual`, `GarageCamera`, lights under `Lighting`), `godot/assets/models/scenes/warehouse1_game.glb` (structure, floor, end walls, window glow), `warehouse_props_game.glb` (fixtures, locker, light switch, boxes, bin), `godot/assets/models/cars/eg6_game.glb`. Everything is rebuilt from the raw sources in `art/models/` by `art/blender/prep_home.py` (stages `car`, `warehouse`, `props`; `garage` is the retired parking structure). Raw sources are never edited.
- Camera (Spire's final, set by hand in the editor): stationary, tight front three-quarter, at (7.6, 2.2, 4.3) with fov 27 looking down ~11 degrees at `CAMERA_TARGET` (-0.15, 0.35, -0.4). The car fills the frame width; at 390x844 the mirrors and bumper corners crop slightly (intentional). Camera position and fov live on `GarageCamera` in `home_garage.tscn`; the aim point is the `CAMERA_TARGET` constant in `home_garage.gd` (it re-aims the camera on every start, so the camera's rotation in the Inspector is overwritten). HOME's 3D region is ~58% of the screen (`warehouse.tscn` GarageHero).
- Rendering: `gl_compatibility`, mobile-first. Walls and floor are flat per-face colors (vertex colors, no textures); three omni lights (one shadow-casting tube over the car) with low specular; a gradient blot under the car grounds the tires; soft paint/glass specular on the Civic. Paint and Glass materials are softened in code by name.
- Placeholders: the cardboard boxes and the bin on HOME are still simple primitives. Real models (`set_of_cardboard_boxes.glb`, `trashcan.glb`) are in `art/models/warehouse props/` but not yet integrated into `prep_home.py`. The bin sits where the camera cannot see it.
- Provenance: every downloaded asset's source, author, license and attribution status is in `docs/ASSET_PROVENANCE.md`. CC-BY assets need an in-game credit that does not exist yet; two props are under the Sketchfab Standard license, unverified.

## Anchors

Use one persistent garage scene with state-driven display anchors/zones:
- car
- wheel wall
- parts shelf
- workbench
- wall/history
- floor
- package/WIP areas

Do not render every inventory object. Prioritize recent, removed, sentimental/history-linked, WIP and player-pinned objects.

The Civic in HOME always reflects actual state:
- wheels
- ride height/camber
- tires
- panels
- paint
- lights
- hood/wing/exhaust
- decals/banner
- interior
- damage
- dirt/wear

Functional inventory stays under CAR. HOME visualizes history/state.

Limited interactions are enough:
- tap car → CAR
- package → delivery
- wall/history → memorabilia/archive
- workbench → notebook where appropriate

No free walking, first-person mode or arbitrary object physics.

---

# 22. TECHNICAL ARCHITECTURE

## 22.1 Current repository is valuable

Do not treat this repo as a clean-slate rewrite.

Working code has value.

> **Do not replace a functioning implementation merely because another implementation appears cleaner.**

Inspect before editing. Reuse before replacing. Refactor only for a concrete reason.

## 22.2 Python is the reference physics implementation

`sim/` remains the physics oracle and Physics 3 engineering reference.

Preserve:
- SI units internally
- traceable input data
- frozen `Car` dataclass / explicit variants
- hand-calculation unit tests
- measured validation targets
- acceptance criteria set before tuning
- no knob-turning to match data
- physically justified model changes
- `docs/VALIDATION_LOG.md`
- step-size convergence
- seeded/reproducible tests where appropriate

Current validated model includes QSS distance-based integration, torque curve/gearing, rotational inertia, drag/rolling resistance, FWD traction/load transfer, load-sensitive tires, lateral load transfer, axle-limited cornering, brake thermal/fade behavior, sequential shifting and driver modeling.

Do not casually alter validated behavior for game balance.

## 22.3 Preserve the academic validation car

The current validated **1996 Civic DX coupe (EJ6 / D16Y7 / S40)** is part of the Physics 3 reference work.

Do not mutate that dataset into an EG6.

Create a separate game vehicle definition for the CONTRABAND96 **1996 EG6 hatch**.

Reference/validation car and game chassis may coexist.

## 22.4 Godot is the shipping game

Godot owns:
- game state
- presentation
- UI
- garage
- calendar
- economy
- world/NPC state
- replay
- audio
- save/load
- final runtime simulation after port
- iOS build

The current Python bridge is useful for desktop development and must not be ripped out prematurely.

Final iPhone runtime must not depend on an external Python environment.

Long-term:
1. Python remains oracle.
2. Establish known validation/regression cases.
3. Port required runtime physics to Godot/GDScript.
4. Compare Godot outputs against Python.
5. Keep both implementations regression-tested.

Do not start a wholesale physics port without an explicit milestone/task.

## 22.5 Physics and game logic remain separate

Physics input conceptually consists of:

**VEHICLE STATE**
- physical configuration
- setup
- condition/damage

**ROAD STATE**
- geometry
- elevation
- surface
- conditions

**DRIVER PROFILE**
- repeatable behavior/tendencies

Physics returns a **RUN RESULT**:
- time
- trajectory
- speed
- RPM
- gear
- throttle
- brake
- physics state/events
- damage/failure events when implemented

Physics must not care about followers, week number, sponsor status, part price or narrative importance.

## 22.6 Simulation and playback are separate

The existing replay approach is strategically important.

Preferred architecture:
1. simulate run
2. record trajectory/telemetry/events
3. play the recorded run
4. use the same run record for replay, results and telemetry

This supports deterministic comparison, Tape Archive, synchronized graphs, multiple cameras and mobile efficiency.

Do not build replay and telemetry as unrelated systems.

## 22.7 Protect the low rear camera

The existing viewer/camera code is working infrastructure.

Do not replace the camera system as incidental cleanup.

The eventual 3D low-rear chase camera is a first-class identity feature.

## 22.8 Save architecture

Design new persistent state with a `save_version` from the start and explicit migrations.

Long-term domains:
- PLAYER: cash, followers, knowledge, relationships
- CIVIC: permanent chassis ID, installed parts, setup, appearance, damage
- INVENTORY: meaningful owned instances
- GARAGE: equipment, memorabilia, displayed objects
- WORLD: date/week, known people, shops, crews, known roads, history
- MARKET: listings, player sales, orders, deliveries
- RACING: run log, PBs, event/rival history
- ARCHIVE: tapes

Use stable IDs for chassis, items, NPCs, roads, shops, events and tapes.

Never silently change save schema.

## 22.9 Calendar/world scheduler

Use day-level world ticks for relevant systems:
- listings
- deliveries
- NPC changes
- shop opportunities
- weather
- events
- forum updates
- repair/work completion
- orders

Do not simulate every NPC minute-by-minute.

## 22.10 Deterministic procedural generation

Road generation and other important procedural systems should accept reproducible seeds for debugging.

A persistent road saves its identity/recipe rather than requiring a huge duplicated scene.

---

# 23. ASSET PIPELINE

Preferred flow:

**downloaded/free low-poly asset → Blender/MCP prep → GLB → Godot**

Use Blender/MCP for:
- inspection
- simplification
- scaling
- orientation
- mesh separation
- pivot fixes
- material naming/recoloring
- export

Do not procedurally reinvent detailed props that already exist as suitable low-poly assets.

Use procedural/code generation where it adds real value:
- roads
- terrain
- track infrastructure/layout
- telemetry/data visualization
- state-driven placement

Build a normalized reusable low-poly asset library for vegetation, rocks, barriers, guardrails, poles, warehouses, lights, signs, garage props, boxes, tools, wheels and car components.

Keep scale, pivots, naming, material philosophy and polygon density consistent.

Every downloaded asset gets an entry in `docs/ASSET_PROVENANCE.md` (source, author, license, attribution status) when it enters `art/`. Never state a license that the file or its source page does not show; mark it unverified.

---

# 24. MOBILE / iPHONE CONSTRAINT

Target device: **iPhone 14**.

Mobile performance is a design constraint from the beginning.

Favor:
- low-poly geometry
- reusable assets
- instancing
- controlled texture sizes
- simple materials
- limited expensive dynamic lighting
- efficient procedural reconstruction
- precomputed run playback where appropriate

The VHS/MiniDV aesthetic can intentionally complement simplified rendering.

Get a playable build onto the iPhone early. Do not wait until the end of development to discover iOS problems.

---

# 25. CURRENT REPO: KEEP / MODIFY / RETIRE / ADD

## KEEP

Preserve and build around:
- `sim/` reference physics architecture
- validation philosophy and logs
- SI-unit conventions
- telemetry
- replay format/concept
- Python bridge during desktop development
- existing Godot vertical slice where useful
- gauges / throttle / brake / gear presentation
- scene-routing/hub concepts
- editor-authored screens and shared theme approach
- inventory UID concept
- save migration discipline
- seeded driver/procedural behavior
- `sim/trackgen.py` as a foundation
- working code unless a feature gives a reason to change it

## MODIFY

Deliberately evolve:
- project identity deadtildawn → CONTRABAND96
- game car DX coupe → separate EG6 game chassis while preserving validated EJ6 reference
- 2D/broadcast viewer → eventual low-poly 3D signature race presentation
- frequent race calendar → meaningful sparse event cadence
- posted-time/simple rival structure → persistent simulated rivals
- current shop → forum/classifieds/retail/import/connection ecosystem
- current part instances → physical provenance/condition/damage/history
- current procedural tracks → persistent discovered roads with richer geometry/environment
- REP UI/state → followers + relationships/history
- current hub visuals → locked CONTRABAND96 low-poly/VHS/zine design
- Python desktop runtime → validated GDScript runtime for iOS later

## RETIRE / DO NOT EXPAND

Legacy concepts incompatible with the new game:
- old Faba/crash story as authoritative design
- police events
- gacha
- rarity weights/colors
- pity
- sealed-crate progression
- hidden quality as loot rarity
- 5% loot-per-win system
- REP gates
- blueprint/build levels
- arbitrary progression buffs
- mandatory wager-centered loop
- race-every-Friday/Saturday assumption
- “easy to wipe progress” as a design goal
- presets
- player driving controls

Do not delete legacy code merely to make the repo look clean. Remove it when the replacement is ready or when it actively blocks current work.

## ADD

Build gradually:
- permanent game chassis identity
- EG6 game definition/model
- richer item instances
- persistent world/calendar scheduler
- WIP work orders
- local permanent test roads
- road persistence/history
- elevation/surface/roughness/weather
- continuous racing line
- suspension interaction
- damage/wear/repair
- forum/classifieds
- relationships/shops/sellers
- evolving rivals
- followers/sponsors
- run log + Tape Archive
- garage history/memorabilia
- iOS-compatible validated physics runtime

---

# 26. DEVELOPMENT ROADMAP

Build vertical slices. Every major stage should leave a playable CONTRABAND96.

## v0.1 — THE GAME EXISTS

Goal: one complete loop.

Include roughly:
- one EG6
- one garage
- one permanent test road
- one competitive road
- one rival
- small parts catalog (about 10–20 meaningful parts)
- basic classifieds/retail access
- calendar
- build/install
- test
- time attack
- results/telemetry
- save
- iPhone build as early as practical

Loop:

**find → buy → install → test → race → analyze**

Do not attempt the entire dream before this works.

## v0.2 — THIS IS MY CIVIC

Focus on ownership:
- richer item instances
- deeper inventory
- wheels/fitment
- body/interior changes
- stickers
- persistent appearance
- garage packages/objects
- WIP states

Two saves should naturally produce different Civics.

## v0.3 — THE ROAD IS THE PUZZLE

Deepen engineering:
- elevation/grade
- improved road geometry
- continuous racing line
- surface grip
- roughness
- suspension interaction
- weather

## v0.4 — THE CAR REMEMBERS

Add consequences:
- tire wear
- brake wear/thermal behavior
- damage
- alignment/component condition
- repairs
- garage persistence
- deeper telemetry/run comparison

## v0.5 — THE WORLD KNOWS YOU

Add social persistence:
- richer NPC state
- relationships
- evolving rivals
- crews
- shops
- private sellers
- followers
- forum
- sponsors
- road discovery

## v0.6 — A LIFE WITH THE CIVIC

Deepen long-term identity:
- Tape Archive
- photographs/memorabilia
- imports/custom orders
- advanced knowledge/tools
- serious engine builds
- advanced chassis setup
- long-term world evolution

Scope may change. The vertical principle does not.

---

# 27. PHYSICS DEVELOPMENT ORDER

Add physical complexity in validated layers rather than one giant rewrite.

Suggested sequence:
1. current road physics + existing vehicle model
2. elevation/grade
3. continuous racing line
4. roughness + suspension interaction
5. wetness + temperature
6. brake/tire thermal/wear expansion
7. aero

For each major layer:

**define physics → implement/reference in Python → hand-calc/validate where possible → test → port/use in Godot when appropriate → visually inspect the EG6 behavior → compare → commit**

Do not add a physical system only because it sounds sophisticated. It should create meaningful observable decisions.

---

# 28. CLAUDE CODE OPERATING RULES

These rules are mandatory unless the user explicitly overrides them.

## Before editing

1. Inspect the existing implementation.
2. Identify which current files/systems own the behavior.
3. State the smallest coherent change.
4. Preserve validated/reference behavior unless changing it is the task.
5. Check whether the task affects save/replay/data contracts.

## While editing

- Make small, testable changes.
- Reuse existing architecture before creating parallel systems.
- Do not rewrite working systems for cleanliness.
- Do not silently change data formats.
- Do not add dependencies without justification.
- Keep node names/contracts stable unless migration is part of the task.
- Keep mobile/iPhone constraints in mind.
- Keep low-poly visual rule in mind.
- Never add player driving controls.
- Never add presets.
- Never add arbitrary RPG performance stats.
- Never prescribe optimal setup to the player.
- Never make followers/relationships alter physics.
- Never convert physical parts into rarity-tier loot.
- Never mutate the validated EJ6 dataset to represent the EG6.
- Do not start the full Python→GDScript port without an explicit milestone.
- Do not delete legacy systems before their replacement is working merely to “clean up.”

## Physics changes

For any physics change:
- explain the physical assumption
- identify equations/inputs affected
- establish expected behavior before tuning
- add/update tests
- compare with hand calculation or external measured target when available
- update relevant physics documentation/validation log
- verify step-size/numerical behavior where relevant
- preserve SI internally

If the result only matches a target after arbitrary parameter tuning, stop and explain the problem.

## Game-system changes

For new game systems:
- keep physics and game logic separated
- use stable IDs for persistent objects
- consider save migration
- consider deterministic seeds where useful
- prefer data-driven definitions over one-off hard-coded branches
- preserve physical ownership/history

## UI changes

- preserve the locked CONTRABAND96 visual language
- 3D imagery is always visibly low-poly
- portrait mobile first
- use existing theme/shared components where practical
- do not introduce modern glass/neon/gacha aesthetics
- do not use rarity colors
- avoid clutter that hides the car/road
- keep race HUD restrained

## Git discipline

Before a major feature, start from a known clean commit.

Prefer one coherent feature/fix per commit.

After implementation:
1. run relevant tests
2. run Godot headless/self-tests where applicable
3. manually inspect important visual behavior
4. commit if good
5. revert/fix if broken

Do not combine unrelated physics, save, UI and road-generator rewrites into one giant change.

---

# 29. CURRENT DEVELOPMENT COMMANDS / LEGACY REFERENCE

These commands describe the current desktop/reference project and may evolve. Verify before changing them.

```
.venv\Scripts\activate
python -m pytest -v
python tools/run_all.py [--track FILE] [--mass -100] [--runs 4]
python tools/validate_straight.py
python tools/export_replay.py [track]
python tools/driver_study.py --rival 49.55
python tools/sensitivity.py
```

Current Godot desktop development uses the repository Python bridge. Final iOS runtime must not.

Preserve useful existing tests such as bridge/replay contract tests and add regression coverage rather than replacing them casually.

---

# 30. HOW TO WORK WITH THE USER

The user is a mechanical engineering student and project integrator, not a professional game developer.

The user makes major decisions about scope, design and architecture direction.

When a real architectural choice exists:
- explain the reason
- give concise options/tradeoffs
- recommend one
- do not hide important decisions inside code changes

For physics, the user often wants to derive/predict behavior before running code. Preserve that engineering workflow.

Be direct about:
- scope creep
- weak physical assumptions
- fragile architecture
- mobile-performance risk
- validation problems

Work iteratively.

Do not jump several milestones ahead merely because they are described in this bible.

When adding files, make their role and location clear.

---

# 31. DESIGN TESTS

When uncertain whether a feature belongs, ask:

### Does this make the player more attached to **their specific Civic**?
If yes, strong signal.

### Does this create an engineering decision or make a consequence observable?
If yes, strong signal.

### Does this make the next race matter more?
If yes, strong signal.

### Does this replace physical behavior with an arbitrary game stat?
If yes, reject/rethink it.

### Does this give the player the answer instead of evidence?
If yes, reject/rethink it.

### Does this turn the game into a driving game?
If yes, reject it.

### Does this create disposable cars, disposable roads or disposable NPCs?
Usually rethink it.

### Does this make racing frequent but meaningless?
Rethink it.

### Does this look like generic modern mobile-game UI?
Reject it.

### Does this violate low-poly presentation?
Reject it.

### Is this a preset disguised as convenience?
Reject it.

---

# 32. FINAL NORTH STAR

CONTRABAND96 begins with a nearly ordinary Civic, a sparse calendar, one garage and a handful of people.

The player finds parts, makes compromises, tests ideas, changes setup, loses races, wins races, breaks things, fixes things, learns the roads, meets people and slowly gains the ability to understand and control more of the car.

The culture opens around them without promoting them out of it.

The garage fills.

The tapes accumulate.

The Civic changes.

Years of game history should be visible without a level number.

At any point, the strongest possible summary of the save should remain:

> **THIS IS MY CIVIC.**

And the strongest possible summary of the game should remain:

> **One car. One garage. No presets. The player never drives. The road is the puzzle. The Civic is the solution. The physics decides what is fast.**
