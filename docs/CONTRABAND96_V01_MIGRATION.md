# CONTRABAND96 — v0.1 MIGRATION PLAN

This is the ordered implementation checklist for transforming the current `deadtildawn` vertical slice into the first playable CONTRABAND96 vertical slice.

Read `CLAUDE.md` first. It is authoritative.

The purpose of this plan is **not** to implement the whole game. It is to move the current project toward the new design while protecting working physics, replay, save and UI infrastructure.

## Definition of v0.1 success

A player can:

**HOME → inspect Civic → acquire a physical part → install it → run a repeatable local test → inspect the result → prepare for one meaningful time attack → watch the simulated run → analyze the result → return HOME with persistent state**

The game still has one Civic, one garage and a small world. That is enough.

Do not add advanced damage, sponsors, crews, imports, full forum simulation, advanced suspension, elevation, weather or the full GDScript physics port until this loop is stable.

---

# Guardrails before migration

- Do not mutate the validated EJ6 reference dataset.
- Do not rewrite the Python physics.
- Do not rewrite `game.gd` merely because it is large.
- Do not delete gacha/REP/old-story code until replacement systems are working.
- Do not attempt a complete visual overhaul and game-system rewrite in one commit.
- Preserve replay/telemetry contracts unless a task explicitly migrates them.
- Preserve save migration support.
- Run tests after each coherent migration step.
- Commit each step separately.

---

# PHASE 0 — BASELINE AND SAFETY

## 0.1 Establish the post-bible baseline

Before gameplay changes:

- run the full Python test suite
- run Godot headless game test
- run replay viewer self-test
- record failures that already exist before migration
- verify the current vertical slice launches
- verify a current race can still produce/play a replay

Do not “fix” unrelated failures while establishing the baseline.

### Exit condition
We know exactly what passes before CONTRABAND96 migration begins.

---

# PHASE 1 — IDENTITY WITHOUT PHYSICS RISK

This is the safest first visible transformation.

## 1.1 Rename presentation-level identity

Change user-facing branding from deadtildawn to CONTRABAND96 where it does not affect file/data contracts.

Examples:
- project/window title
- hub/logo text
- screen copy
- stale deadtildawn-facing labels

Do **not** rename replay format IDs, directories, scripts or internal contracts solely for cosmetic cleanliness. Internal legacy names can remain until there is a functional reason to migrate them.

## 1.2 Remove old story from the active startup flow

The Faba/crash story is legacy and should no longer define a new save.

Do not spend time writing the replacement story yet.

Preferred v0.1 behavior:
- new game enters the CONTRABAND96 HOME/garage experience directly, or
- uses a minimal temporary title/introduction consistent with the new bible

Keep old intro code/assets in the repo until removal is safe.

## 1.3 Establish new navigation vocabulary

Target main navigation:

**CAR / CALENDAR / HOME / TEAM / SHOP**

Current shell is useful and should be evolved, not replaced.

For v0.1:
- HOME replaces WAREHOUSE as the player's conceptual anchor
- CAR remains
- CALENDAR remains
- SHOP remains
- TEAM may initially be a simple placeholder/limited contacts screen

Do not invent functionality merely to fill TEAM.

## 1.4 REP → followers migration boundary

Do not perform a giant social-system rewrite yet.

First:
- introduce a `followers` save field
- migrate old `rep` values safely if needed for existing development saves
- display followers in the shell
- stop using REP as the visible progression identity

Any old REP-gated legacy system can temporarily remain internally until its replacement phase, but no new feature may depend on REP.

### Exit condition
The current game visibly identifies as CONTRABAND96, starts without relying on the old story, and uses the new hub vocabulary without changing validated physics.

---

# PHASE 2 — PROTECT REFERENCE CAR, ADD GAME CHASSIS

## 2.1 Freeze the EJ6 as reference data

Current:
`data/cars/ej6_dx_coupe_1996.json`

Keep it intact as the Physics 3 validation/reference car.

Tests and validation tools that currently depend on it should continue to do so unless explicitly testing the game car.

## 2.2 Add a separate EG6 game definition

Create a new data file for the 1996 EG6 hatch.

Important:
- do not fabricate high-confidence engineering values
- use sources/confidence metadata consistent with existing car data
- mark uncertain values honestly
- do not tune EG6 numbers to achieve desired gameplay

The first EG6 definition can be incomplete/temporary if the current `Car` schema requires values not yet researched, but uncertainty must be explicit.

## 2.3 Separate “reference car” from “game car” selection

The bridge currently hardcodes the EJ6 as `CAR_FILE`.

Refactor only enough to allow:
- validation/reference tools → EJ6
- game bridge/game → EG6

Do not duplicate physics functions.

## 2.4 Permanent chassis identity

Introduce a stable game chassis ID in save state, e.g. a semantic ID rather than a level-based car identifier.

The chassis persists for the entire save.

Do not build multi-car garage architecture.

### Exit condition
Physics validation still uses the untouched EJ6. The game can identify/load the EG6 independently, and the save contains one persistent game chassis identity.

---

# PHASE 3 — REMOVE GACHA FROM THE PLAYER LOOP

This is the largest incompatible current system and should be replaced early.

## 3.1 Preserve useful parts architecture

Keep:
- data-driven physical effects
- one part per compatible slot
- `apply_parts`
- physical changes to real simulation inputs
- inventory UIDs
- installed UID references

These align strongly with CONTRABAND96.

## 3.2 Stop exposing gacha mechanics

Remove from active UI/loop:
- PULLS
- rarity colors
- pity
- unopened/dyno reveal
- hidden quality-as-loot progression
- loot-per-win
- REP gates
- crate progression

Do not immediately delete `sim/gacha.py` or its tests. First remove dependencies from the active game loop.

## 3.3 Introduce simple v0.1 acquisition channels

Do not build the full living marketplace yet.

For v0.1 implement two clear channels:

**RETAIL**
- small set of common/new parts
- fixed known specification
- predictable price

**USED / CLASSIFIEDS**
- small rotating set of specific item instances
- seller/source identity
- price
- condition descriptor
- enough persistence that a listing does not reroll every time the screen opens

No rarity tiers.

## 3.4 Evolve inventory instance schema

Current instances already have UIDs. Preserve them.

Move toward fields such as:
- uid
- part definition ID
- source
- seller where applicable
- acquired day/week
- acquisition price
- condition
- installed state/position
- history metadata

For v0.1, only implement fields the current loop needs, but choose a schema that can expand.

Do not make “quality” a hidden rarity roll. If a used item's physical condition affects performance, represent that explicitly and explainably.

## 3.5 Replace instant scrap sale

The current SELL FOR fixed scrap behavior is legacy.

For v0.1 it is acceptable to:
- disable selling temporarily, or
- create a very small classifieds selling flow

Do not spend weeks building the final NPC marketplace before the core loop works.

### Exit condition
The player can acquire and install physical parts without gacha, rarity, pity or REP.

---

# PHASE 4 — HOME AS THE ANCHOR

## 4.1 Evolve warehouse into HOME

Reuse the working hub/scene architecture.

HOME should no longer primarily be a “next race / minimum buy-in / record” screen.

v0.1 HOME responsibilities:
- show the actual current Civic
- show cash/followers
- provide navigation
- show concise current calendar/world information
- surface deliveries/WIP later
- retain the approved VHS/garage atmosphere

Do not build a point-and-click garage.

## 4.2 Preserve current 3D/visual work where useful

The current pedestal/placeholder architecture may remain while the real low-poly EG6 pipeline is integrated.

Never replace working visual infrastructure merely because final art is not present.

## 4.3 Low-poly benchmark

Any new 3D asset or scene added from this point must visibly follow the locked low-poly style.

Do not use photoreal placeholder assets that accidentally become permanent.

### Exit condition
HOME feels like the persistent base of the new game rather than a race lobby.

---

# PHASE 5 — PERMANENT LOCAL TESTING

Testing is required before the new race loop because it establishes the game's engineering identity.

## 5.1 Add LOCAL STRAIGHT

Create one permanent repeatable test route.

Initial useful outputs:
- 0–60
- acceleration trace
- RPM
- gear
- throttle
- braking metric if supported

Use the same road geometry/conditions for controlled comparisons unless the player deliberately changes conditions later.

## 5.2 Add LOCAL CURVES

Create one permanent repeatable curvy route using current road capabilities.

It does not need elevation/suspension roughness yet.

Initial outputs:
- total time
- speed trace
- corner behavior available from current telemetry
- comparison to previous/PB

The road geometry must remain stable.

## 5.3 Test log v0.1

Persist test results with at least:
- run ID
- route ID
- date/week
- time/metrics
- installed-part snapshot or configuration reference

Do not build the full Tape Archive yet.

## 5.4 Stable reference driver

Testing must use a sufficiently repeatable driver mode for meaningful A/B comparison.

Do not use large random performance swings in controlled testing.

### Exit condition
The player can change a physical part, run the same test again, and meaningfully compare what happened.

---

# PHASE 6 — CALENDAR: FROM RACE SCHEDULE TO LIFE SCHEDULE

## 6.1 Remove fixed Friday/Saturday race assumption

The current calendar is structurally useful but its event philosophy is legacy.

Replace fixed weekly race cadence with a small v0.1 schedule containing a mix such as:
- classifieds refresh
- local testing availability
- part pickup/delivery
- quiet/open day
- one meaningful competitive time attack

Do not force one action per day.

## 6.2 Day-level world state

Introduce/clarify a single day-level advancement mechanism.

It should eventually own:
- listings
- deliveries
- work completion
- events
- forum/world updates

For v0.1 only wire the systems that exist.

Do not simulate NPC lives minute-by-minute.

## 6.3 WIP architecture hook

The full repair/install-time system can wait, but design the save/calendar so a future work order can contain:
- work type
- start day
- completion day
- status

Avoid implementing a dead-end calendar schema that assumes all installs are instant forever.

### Exit condition
The calendar creates anticipation around one race rather than functioning as a race conveyor belt.

---

# PHASE 7 — ONE MEANINGFUL TIME ATTACK

## 7.1 Replace wager-centered pre-race framing

The current minimum-buy-in/wager logic should stop being the core gate.

For v0.1, a race can have a fixed/simple purse or entry condition.

Do not make every event economically identical.

## 7.2 One persistent rival

Use one rival for the vertical slice.

The rival should have:
- stable NPC ID
- name
- persistent car definition/configuration
- driver profile
- relationship/history fields sufficient for future expansion

Do not implement a full rival ladder.

## 7.3 Simulated opponent

Move away from “posted time anchored to stock player car” as the long-term model.

The rival should eventually produce their time from:
- their own car
- their own driver
- the same road/conditions

For v0.1, implement the smallest reliable version of this without rewriting the solver.

## 7.4 Race presentation

Preserve the existing replay/telemetry infrastructure.

Target presentation direction:
- low rear signature view when 3D race presentation is ready
- speed/RPM
- gear
- throttle
- brake
- timer/delta where useful

Do not implement player controls.

### Exit condition
The player prepares for and watches one meaningful time attack against a persistent rival.

---

# PHASE 8 — RESULTS THAT TEACH WITHOUT ANSWERING

## 8.1 Remove XP/REP-style result framing

Result should emphasize:
- time
- rival/target
- gap
- win/loss
- cash where relevant
- followers where relevant

## 8.2 Use existing breakdown work

The existing time-gap/breakdown infrastructure is valuable.

Expose measured categories where defensible, e.g.:
- braking
- corners
- exits
- acceleration/high speed
- mistakes/fade where supported

Make gain/loss sign conventions unambiguous.

## 8.3 Comparison

v0.1 should support at least one useful comparison:
- previous run
- personal best
- rival

## 8.4 No prescriptions

Allowed:
- “exit RPM lower than comparison”
- “lost 0.31 s in braking”
- “front brake temperature exceeded X”

Not allowed:
- “install shorter gearing”
- “buy better brakes”
- “raise ride height”

### Exit condition
After a loss, the player has evidence to investigate rather than a shopping recommendation.

---

# PHASE 9 — SAVE MODEL HARDENING

Do this after the new v0.1 loop is concrete enough that the schema is not purely speculative.

## 9.1 Increment save version

Migrate existing development saves where practical.

## 9.2 Establish domains

v0.1 does not need every future field, but clearly separate:
- player
- chassis
- inventory
- installed configuration
- world/calendar
- market/listings
- tests/runs
- rival/history

## 9.3 Stable IDs

Use stable IDs for:
- chassis
- owned item
- road
- NPC
- run
- listing where persistent

## 9.4 Snapshot run configuration

Each important run/test should be able to identify the exact installed configuration used.

### Exit condition
The v0.1 loop survives save/reload without losing identity/history.

---

# PHASE 10 — iPHONE CHECKPOINT

Do not wait for advanced physics or final art.

Once the new v0.1 loop is coherent:

- create/test the iOS export path
- verify portrait layout on iPhone 14
- verify touch navigation
- profile obvious rendering/performance problems
- document blockers from the Python bridge

The desktop bridge may still be required at this stage; that is acceptable for development. The purpose is to expose iOS/presentation issues early and define the runtime-port requirements.

Do not start a rushed full physics port merely to claim the checkpoint is complete.

---

# WHAT NOT TO BUILD DURING THIS MIGRATION

Unless required by a preceding step, defer:

- full story rewrite
- full forum simulation
- crews
- sponsors
- imports
- custom wheel manufacturing
- full sticker editor
- advanced livery editor
- advanced damage
- engine failures
- full repair ecosystem
- deep mechanic knowledge tree
- corner weighting
- advanced ECU tuning
- elevation
- full suspension dynamics
- wetness/temperature system
- aero expansion
- full persistent procedural-road discovery
- large NPC population
- final Tape Archive presentation
- full Python→GDScript port
- arbitrary garage object placement
- free-walk garage
- multiple player cars

These are not rejected features. They are protected from being implemented too early.

---

# RECOMMENDED COMMIT ORDER

Use approximately this order. Each line should be a coherent, testable commit or small group of commits.

1. **Baseline tests documented**
2. **CONTRABAND96 presentation identity**
3. **Old intro removed from active new-game path**
4. **HOME navigation vocabulary + followers field**
5. **Separate EG6 game-car data path from EJ6 reference**
6. **Permanent chassis ID**
7. **Inventory schema migration away from rolled rarity quality**
8. **Retail acquisition**
9. **Persistent used classifieds**
10. **Gacha UI removed from active loop**
11. **HOME race-lobby assumptions removed**
12. **Permanent LOCAL STRAIGHT**
13. **Permanent LOCAL CURVES**
14. **Test log + configuration snapshot**
15. **Calendar event cadence migration**
16. **One persistent rival**
17. **Simulated-rival time attack**
18. **Results/comparison pass**
19. **Save schema hardening**
20. **v0.1 full-loop regression test**
21. **iPhone checkpoint**

If a step reveals that the existing architecture already solves the problem cleanly, reuse it and make a smaller commit.

---

# v0.1 ACCEPTANCE TEST

A clean new save should be able to demonstrate this story without debug intervention:

1. Open CONTRABAND96.
2. Arrive at HOME with one 1996 EG6 hatch.
3. Inspect the Civic.
4. Browse a small believable set of retail/used parts.
5. Buy one physical part.
6. Install it.
7. Run LOCAL STRAIGHT or LOCAL CURVES.
8. Inspect the measured result.
9. Make a setup/build decision.
10. Advance through a sparse calendar toward one time attack.
11. See the rival/road information without being told the optimal setup.
12. Commit to the run.
13. Watch the Civic race without controlling it.
14. See time, gap and useful physics-derived observations.
15. Return HOME.
16. Save/reload.
17. The same chassis, installed part, cash, followers, test history and race history remain.

If this works, CONTRABAND96 exists.

Everything after that deepens **this same game**.
