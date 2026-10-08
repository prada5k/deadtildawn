# Phase 7D.1 — LOCAL CURVES multi-entrant event

`data/rivals/local_curves_roster_v1.json` defines the fixed five-entrant field for
`C96_TA_LOCAL_CURVES_001`: permanent player chassis `CHASSIS_0001`, established
rival Rafa Morales, and three fictional 1996 Ventura County Honda enthusiasts.
This is authored event data, not a procedural NPC or vehicle system.

The bridge runs every entrant independently through `local_curves_result()` on
the same LOCAL CURVES file, geometry hash, dry surface, 30 C ambient condition,
standing start, and 0.5 m integration step. The player's run keeps the established
reference-driver setup and seed 9605. Rafa keeps his existing EJ6 definition,
driver profile, seed, and temporary EG9 replay proxy. The other entrants reuse the
validated EG6 definition and only use existing parts whose catalog metadata
explicitly allows `eg6_sir_ii_1995`. They remain NPC fixtures and never enter player
inventory or vehicle ownership.

Every entrant stores a stable event entrant ID, stable vehicle ID, identity,
definition ID/path/hash, complete resulting physical `Car` configuration,
installed definition IDs, driver parameters, simulation seed, course snapshot,
event conditions, measured time/telemetry summary, and replay reference. The
additional EG6 replay files use the existing replay viewer's matching EG6 model
fallback; Rafa alone uses the EG9 proxy. The EG9 does not represent the EG6 or any
other entrant.

Standings sort by measured elapsed seconds, then stable entrant ID for an exact
tie. Gaps are measured from the event leader and stored in seconds to 0.001 s.
The game independently validates the five entrant identities, common course and
conditions, replay files, and standings before saving. The legacy `player`,
`rival`, `competition`, delta, and outcome fields remain for the existing event
detail flow; `entrants`, `standings`, `entrant_count`, and `player_position`
preserve the complete field without introducing a leaderboard UI.

Save version 14 adds fields only to newly completed multi-entrant results. The
v14 migration updates the version and leaves prior solo and player-versus-Rafa
result snapshots untouched; it never reruns historical events.

This fixture deliberately uses five total entrants. There are only two validated
car definitions in scope, so the fictional field reuses EG6 physical definitions
with explicit catalog-part setups and supported driver parameters. No new vehicle
physics data or simulation behavior was added.
