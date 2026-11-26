# TowerDefense Public Godot Toolchain

This document defines the public technical boundary for the canonical Input. Player-visible requirements and exact game rules remain exclusively in `GDD-en.md`.

## Project boundary

- Engine: Godot `Godot`.
- Project root: `sp/`.
- Main scene: `res://Starter/Main.tscn`.
- Renderer: GL Compatibility.
- Logical viewport: `1152 × 648`.
- Source assets: `Asserts/`, governed by `Asserts/MANIFEST.json`, `MaterialMapping-en.md`, and `legal/`.
- Network, runtime downloads, accounts, and paths outside the copied Input workspace are unavailable.

Only the copied `sp/` project is writable implementation scope. The public task documents, material manifest, and license records are protected task inputs and must not be rewritten to weaken requirements.

## Player input

All required behavior must be reachable through the visible game window with ordinary mouse input. A click is a pointer move, left-button press, and release over a visible control or tower. A tower placement is a real drag sequence: move to a visible tower card, press, move through visible intermediate positions while held, and release over the battlefield.

The implementation may use GUI callbacks, native drag-and-drop, `_input`, `_shortcut_input`, or `_unhandled_input`. It must not require calls to internal gameplay functions, hidden shortcuts, debug menus, task-specific node names, command files, sockets, or HTTP. Drag continuation and release should be handled from the actual input events rather than relying only on global singleton polling.

## Read-only dashboard

- Implementation skeleton: `res://benchmark/dashboard.gd`.
- Self-check: `res://benchmark/dashboard_self_check.gd`.
- Naming table: `res://benchmark/naming-tables.json`.
- Snapshot: `user://benchmark_dashboard.json`.
- Contract: `game-state-dashboard/v2-godot`, as defined by `DASHBOARD_SPEC.md`.

The dashboard reports only public, player-observable semantics. It must not expose node paths, scripts, resources, private implementation structure, or accept commands. Changing a snapshot outside the process must never change gameplay. Debug labels, route markers, test overlays, answer buttons, and hidden result shortcuts must not appear during play.

## Artwork and coordinates

The game uses logical viewport coordinates, not desktop cursor coordinates. The Grassland artwork keeps a uniform, non-mirrored relationship with the playfield. The painted stone road, enemy travel, road rejection, and continuous clear-grass placement describe the same battlefield.

Copying or importing an asset is insufficient by itself: the menu, map, tower, and dinosaur images must be visibly bound to the corresponding player-facing roles defined by `GDD-en.md`. Allowed presentation choices include proportional scaling, cropping that preserves required map relationships, atlas regions, sprite frames, animation, tint, rotation, flipping, and supporting effects.

## Verification

Use the designated Godot console executable for a clean headless import and `res://benchmark/public_smoke.gd` for the public launch smoke. Then start the normal GUI project and exercise the complete tower-defense journey with real visible input: build/reject drags, combat, repair/upgrade/sell, Game Over, Restart, the winning campaign, Main Menu, close, and a fully closed different-process reopen.

Store logs, screenshots, and runtime snapshots outside the submitted Input while testing. Before handoff, remove `.godot/`, logs, screenshots, temporary scripts, runtime state, and local evidence from the project tree. Report any unexecuted or failed check honestly.
