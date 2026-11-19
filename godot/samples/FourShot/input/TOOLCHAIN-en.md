# FourShot Public Godot Toolchain

This document defines the public technical boundary for the canonical Input. Player-visible requirements and exact game rules remain exclusively in `GDD-en.md`.

## Project boundary

- Engine: Godot `4.7.1.stable.official.a13da4feb`.
- Project root: `sp/`.
- Main scene: `res://main.tscn`.
- Renderer: GL Compatibility.
- Logical viewport: `1280 × 720`.
- Source assets: `Asserts/`, governed by `MaterialMapping-en.md` and `legal/`.
- Network, runtime downloads, accounts, and paths outside the copied Input workspace are unavailable.

Only the copied `sp/` project is writable implementation scope. The public task documents, material manifest, and license records are protected task inputs and must not be rewritten to weaken requirements.

## Player input

All required behavior must be reachable through the visible game window with ordinary keyboard and mouse input. WASD controls movement and establishes the persistent shooting direction from the last nonzero eight-direction movement input; stopping preserves that direction. Left-button input triggers shooting along it. Holding left click fires HK-67 at its cadence, while each press fires at most one Glock-21 or special-sniper shot. Arrow keys and mouse position must not aim; the mouse remains available for visible UI controls and the no-movement dash direction defined by `RULE-04c`. Reload, weapon switching, dash, map, bomb placement, menu navigation, and visible buttons follow the controls stated in `GDD-en.md`.

The implementation may use normal Godot `InputMap`, GUI callbacks, `_input`, `_shortcut_input`, or `_unhandled_input`. It must not require calls to internal gameplay functions, hidden shortcuts, debug menus, task-specific node names, command files, sockets, or HTTP.

## Read-only dashboard

- Implementation skeleton: `res://benchmark/dashboard.gd`.
- Self-check: `res://benchmark/dashboard_self_check.gd`.
- Naming table: `res://benchmark/naming-tables.json`.
- Snapshot: `user://benchmark_dashboard.json`.
- Contract: `game-state-dashboard/v2-godot`, as defined by `DASHBOARD_SPEC.md`.

The dashboard reports only public, player-observable semantics. It must not expose private implementation structure or accept commands, and changing a snapshot outside the process must never change gameplay.

## Deterministic evaluation seed

The public seed entry is the Godot user argument `--benchmark-seed=<decimal>`, supplied after Godot's `--` separator and read from `OS.get_cmdline_user_args()`. If it is absent, the game uses `41041`. A fresh level and Retry reset the gameplay random source to that value. The dashboard publishes the effective value as numeric slot `rng_seed`; the snapshot remains read-only and cannot change it.

## Verification

Use the designated Godot 4.7.1 console executable for a clean headless import and `res://benchmark/public_smoke.gd` for the public launch smoke. Then start the normal GUI project with `-- --benchmark-seed=41041` and exercise the six level journeys with real visible input, including rejection feedback, Retry, level switching, close, and a fully closed different-process reopen.

Store logs, screenshots, and runtime snapshots outside the submitted Input while testing. Before handoff, remove `.godot/`, logs, screenshots, temporary scripts, runtime state, and local evidence from the project tree. Report any unexecuted or failed check honestly.
