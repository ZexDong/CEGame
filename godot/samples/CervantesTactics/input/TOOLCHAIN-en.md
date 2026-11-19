# CervantesTactics Public Godot Toolchain

This document defines the public technical boundary for the canonical Input. Player-visible requirements and exact game rules remain exclusively in `GDD-en.md`.

## Project boundary

- Engine: Godot `4.7.1.stable.official.a13da4feb`.
- Project root: `sp/`.
- Main scene: `res://Main.tscn`.
- Renderer: GL Compatibility.
- Logical viewport: `1280 × 720`.
- Source assets: `Asserts/`, governed by `MaterialMapping-en.md` and `legal/`.
- Network, runtime downloads, accounts, and paths outside the copied Input workspace are unavailable.

Only the copied `sp/` project is writable implementation scope. The public task documents, material manifest, and license records are protected task inputs and must not be rewritten to weaken requirements.

## Player input

All required behavior must be reachable through the visible game window with ordinary keyboard and mouse input. The implementation may use normal Godot `InputMap`, GUI callbacks, `_input`, `_shortcut_input`, or `_unhandled_input`. It must not require calls to internal gameplay functions, hidden shortcuts, debug menus, task-specific node names, command files, sockets, or HTTP.

The required player actions, including menu navigation, camera pan/zoom/rotation, tactical selection, movement, attacks, abilities, cancel, pause, result handling, Restart/Main Menu, settings, and save-slot flows, are defined by `GDD-en.md`.

## Read-only dashboard

- Implementation skeleton: `res://benchmark/dashboard.gd`.
- Self-check: `res://benchmark/dashboard_self_check.gd`.
- Naming table: `res://benchmark/naming-tables.json`.
- Snapshot: `user://benchmark_dashboard.json`.
- Contract: `game-state-dashboard/v2-godot`, as defined by `DASHBOARD_SPEC.md`.

The dashboard may report only public, player-observable semantics. It must not expose private implementation structure or accept commands, and changing a snapshot outside the process must never change gameplay.

## Verification

Use the designated Godot 4.7.1 console executable for a clean headless import and `res://benchmark/public_smoke.gd` for the public launch smoke. Then start the normal GUI project and exercise the complete public flow with real visible input. Check success, both failure outcomes, rejection feedback, Retry/Main Menu, save/load, settings persistence, and a fully closed different-process reopen.

Store logs, screenshots, and runtime snapshots outside the submitted Input while testing. Before handoff, remove `.godot/`, logs, screenshots, temporary scripts, runtime state, and local evidence from the project tree. Report any unexecuted or failed check honestly.
