# Learning Godot on deadtildawn

A path from "never opened the editor" to restyling and building screens yourself, using this project as the playground. Do the exercises in order; each one builds on the last. Commit before each exercise so you can always get back.

## 1. Five ideas that explain most of Godot

**Nodes.** Everything is a node: a label, a button, a camera, a car. Each node type does one job.

**Scenes.** A scene is a saved tree of nodes (`.tscn`). `intro.tscn` is a scene; so is `game.tscn`. Scenes can contain other scenes.

**Containers lay things out for you.** A `VBoxContainer` stacks children top to bottom, an `HBoxContainer` left to right, a `MarginContainer` adds padding, a `GridContainer` makes a grid. Put nodes inside containers instead of positioning them by hand; that's how layouts survive different phone sizes.

**The Theme holds the look.** `theme.tres` defines every color, font, size, and button style. A **type variation** is a named style that builds on a base type: `TitleLabel` is a Label that's big, `DangerButton` is a red Button. A node picks one with its *Theme Type Variation* property. Change the variation once, and every node using it changes.

**Signals connect things.** A button emits `pressed`; code listens and reacts. The bridge emits `replied` when Python answers. That's how separate parts talk without knowing about each other.

## 2. How this project is organized

| File | What it is |
|---|---|
| `game.tscn` / `game.gd` | The game: state, save file, and every menu screen (built in code) |
| `intro.tscn` / `intro.gd` | The story intro, built in the **editor** (your first scene to explore) |
| `main.tscn` / `main.gd` | The race viewer (broadcast cameras, HUD) |
| `theme.tres` | The look of every menu: colors, fonts, buttons, panels |
| `ui.gd` | Helpers the menus use (`UI.label`, `UI.button`, ...) |
| `gauge.gd`, `track_map.gd` | Custom drawn widgets (they draw themselves in `_draw()`) |
| `bridge.gd` | Talks to the Python sim |

The menu screens are built in code so they stay small and testable, but their **look comes entirely from the theme**. So you can restyle the whole game in the editor without touching code.

## 3. Exercises

**Exercise 1: tour the editor (15 min).** Open the project. Find the four main areas: the **Scene** dock (node tree, top left), the **FileSystem** dock (files, bottom left), the **Inspector** (properties of the selected node, right), and the main view (center). Press F5 to run the game, F6 to run just the open scene.

**Exercise 2: restyle the game from the Theme (20 min).** Double-click `theme.tres`. The Theme editor opens at the bottom. Find `AccentButton` and change its `normal` style's background color. Run with F5: every orange button changed. Then change `TitleLabel`'s font size. Notice you never touched code.

**Exercise 3: edit a scene visually (30 min).** Open `intro.tscn`. Click `Skip` in the Scene dock and look at the Inspector. Move it with the **Layout** preset menu (anchor it to the bottom-right instead of the top-right). Click `Background` and change its color. Select `Body` and change its Theme Type Variation. Run with F6 to see just the intro.

**Exercise 4: change the story (10 min).** In `intro.gd`, the `SLIDES` list holds every slide. Add one, reword one, or add `"bg": "crash"` to a slide to give it the red background. The look stays in the scene; the words stay in the script. That's **separating content from presentation**.

**Exercise 5: make a new style (20 min).** In the Theme editor, add a type variation called `WarningLabel` (base type `Label`) with a yellow font color. In `game.gd`, find a label in `show_results` and give it `"WarningLabel"` instead of `"MutedLabel"`. Run it.

**Exercise 6: build a screen in the editor (1-2 h).** Create a new scene with a `Control` root. Add a `MarginContainer` set to Full Rect, a `VBoxContainer` inside, then Labels and a Button. Give them theme variations. Ideas: a "Faba" profile card, or a warehouse header with the crew's record. Save it as `crew.tscn`. Ask Claude to help wire it into the game: a screen that shows it and returns to the warehouse.

## 4. Habits worth building early

- **Containers over manual positions.** If you're typing pixel coordinates for menu items, there's usually a container that does it better.
- **Watch for the wrap trap.** A Label with autowrap inside an `HBoxContainer` collapses to one character per line, because nothing gives it a width. In a `VBoxContainer` it wraps to the column. (This bit us once already; `ui.gd` now handles it.)
- **Keep the main action on screen.** On mobile, the big button (SEND IT) belongs in a pinned area, not at the bottom of a scrolling list.
- **Run the headless tests after changes:** `godot --headless --path godot -- --gametest`. The editor won't always tell you a script broke until you reach that screen.
- **Read errors in the Output and Debugger panels** (bottom of the editor). The first error is usually the real one; the rest are fallout.

## 5. Reference

The official docs are excellent: https://docs.godotengine.org. Most useful pages for now: "Your first 2D game" (the whole node/scene/signal workflow), "Size and anchors," "Using Containers," and "Introduction to GUI skinning" (themes and type variations).
