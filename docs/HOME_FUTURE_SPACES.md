# HOME (Garage 1): floor and wall space kept clear for later

Nothing below is implemented. These are places left empty on purpose so that objects the save produces
(removed stock parts, empty parts boxes, spares, deliveries, used tools, memorabilia) can appear without
touching the Civic, the workstation or the camera's view of the car. Game frame: the Civic is at the origin, nose +x,
floor y = 0, side wall z = -2.56, end wall x = -7.5. The wall has columns (0.16 m proud) at x in [-2.4,-1.8],
[-6.6,-6.0] and [1.8,2.4]; stay out of them.

| Slot | Where (x, z) | Good for |
|---|---|---|
| Foreground floor | x 2.8 to 6.5, z -0.5 to 3.5 (nearest the camera) | the biggest open space: a delivered package, a pallet, a wheel set, a jack stand. Keep most of it empty. |
| Car's right-hand gap | x -2 to 2, z 1.0 to 2.4 | a removed bumper, a creeper, a parts tray beside the Civic |
| Wall bay, front half | x 1.0 to 1.75, z -2.5 to -1.8 (floor, against the wall) | stacked parts boxes, wheel boxes |
| End-wall corner | x -7.4 to -6.7, z 0.0 to 1.6 | deliveries / packages, larger crates |
| Wall above the desk | side wall, x -1.3 to 0.4, height 1.4 to 2.3 | photographs, tape labels, event flyers (WallMemorabilia) |

Existing empty `Zones` nodes in `home_garage.tscn` (`PartsStorage`, `WallMemorabilia`, `EntranceBackground`,
`WorkArea`, `Tools`) are the intended parents for these.
