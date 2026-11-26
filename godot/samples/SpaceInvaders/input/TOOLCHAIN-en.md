# SpaceInvaders Public Godot Toolchain

## Project boundary

- Engine: Godot `Godot`.
- Project root: `sp/`.
- Required main scene: `res://main.tscn`.
- Viewport: `1280x720`.
- Renderer: GL Compatibility.
- Target platform for this task: Windows desktop with a visible game window.

- Network, runtime downloads, accounts, external paths, and engine migration are unavailable.

Only the copied `sp/` project is writable implementation scope. Do not rewrite the public task documents, manifest, naming table, material catalog, or license records to weaken requirements.

## Player input

The project defines and consumes these Godot InputMap actions:

| Action | Default input | Semantics |
|---|---|---|
| `move_left` | A or Left Arrow | Move while held |
| `move_right` | D or Right Arrow | Move while held |
| `shoot` | W, Up Arrow, Space, or Enter | Fire once per press |
| `pause` | Escape | Pause or resume |

All gameplay must remain reachable through normal visible keyboard/mouse input. Do not require calls to internal gameplay methods, hidden shortcuts, debug menus, command files, sockets, or HTTP.

## Read-only dashboard

- Implementation skeleton: `res://benchmark/dashboard.gd`.
- Self-check: `res://benchmark/dashboard_self_check.gd`.
- Naming table: `res://benchmark/naming-tables.json`.
- Snapshot: `user://benchmark_dashboard.json`.
- Contract: `game-state-dashboard/v2-godot`, as defined by `DASHBOARD_SPEC.md`.

The dashboard must report only the public state named in GDD Section 12. It accepts no action command and cannot modify gameplay.

## Materials

- Runtime assets are under `sp/assets/`.
- `Assets/material-index.json` records file roles, dimensions, and import facts.
- `Assets/asset-coverage.json` records supplied, procedural, and missing roles.
- `Assets/asset-contact-sheet.png` previews the supplied visual source files and prescribes no scene layout.
- 

The upstream `PixeloidMono-d94EV.ttf` font is intentionally not published because its separate license has not been cleared. Use the engine default font or an independently cleared font.

## Verification

Optional development feedback includes clean import, public smoke, dashboard self-check and ordinary play through the public requirements. No particular self-test sequence or report is required.

Store logs, screenshots, and runtime snapshots outside the submitted project. Remove `.godot/`, logs, screenshots, temporary scripts, and runtime state before delivery. Public smoke and dashboard self-check are optional implementation aids and do not prove that gameplay is complete.

## Reproducibility

Accept optional `--seed=<integer>` after Godot's `--` separator, default 0. Randomized content repeats for the same seed and player input sequence. Fixed authored layouts do not change. Deterministic implementations may ignore this value.

## Starter observation state

The unfinished starter reports `not_ready`, numeric zero for unavailable slots, and empty entities/targets. In the implemented game report real values and only present, visible objects; menus have no invented player entity. Every snapshot adds `process_id` for process identity. Optional `--dashboard-output=<path>` redirects observation output only.
