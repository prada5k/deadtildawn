# Visual Overhaul Specification: deadtildawn (v1.1)

This spec defines the structural arrangement and component skinning required to revamp the interface into a high-density, text-padded automotive management engine.

## 1. Top Core Dashboard & Stencil Header
- **Top Profile Banner (`PanelContainer`):** Stacks components vertically via an internal `VBoxContainer` named `BannerColumn`. 
- **Upper Row (`HBoxContainer`):** Places our game title logo `DEADTILDAWN` (Russo One font, skewed `0.15` italic slant in Milano Red) on the left margin, aligned flush with the unique `%Header` instance node on the right rail.
- **The Stencil Location Bar:** A solid Milano Red (`#D64045`) panel block with 0px corners sitting beneath the stats. Contains a single label displaying `THE WAREHOUSE // DATA_TERMINAL_01` in solid Greasy Charcoal text (`#0F0E10`). 
- **The User Context Row:** Displays a square, high-contrast B&W pixel portrait slot of the User player, flanked by the left-aligned `Subtitle` description string.

## 2. Central Garage Lift Hero Area
- **Sizing Policy:** The central `HeroPedestal` (`Control` node) uses Size Flags Vertical -> `Expand` and `Fill` to maximize its screen grid usage.
- **The Lift Asset:** Holds a static, industrial **raw metal garage car lift** graphic blueprint element. Your FWD Civic Si coupe asset rests securely on top of the lift arms. 
- **Blueprint Mesh backdrop:** Behind the lift, a tiled, transparent `16x16px` texture maps fine grid lines of Raw Machined Silver (`#C0C5C1` at 0.05 opacity) to make the space look like automotive engineering graph paper.

## 3. Persistent Icon Tray Sizing
- **The Base Bar:** Pinned to the absolute bottom via a solid Greasy Charcoal background tray with internal `Content Margin` settings set to `Top: 16`, `Bottom: 24`, `Left: 12`, and `Right: 12`.
- **Icon Formatting:** Buttons use vector textures or clean font codes for icons instead of alpha text words. The horizontal rows stretch out flush to fill the phone boundaries.

## 4. Live Simulation Replay HUD (`main.gd`)
- **Analog Cockpit Instrumentation:** Playback overlays use crisp, **90s JDM white-face analog gauges** (Defi/GReddy style) with sharp black numbers and sweeping neon-orange needles for the Tachometer and Speedometer widgets.
