# RougelikeTD Public Godot Toolchain

## Project boundary

- Engine: Godot `Godot`.
- Project root: `sp/`.
- Required main scene: `res://main.tscn`.
- Viewport: `960x540`.
- Renderer: Forward+.

- Network, runtime downloads, accounts, external paths, and engine migration are unavailable.

Only the copied `sp/` project is writable implementation scope. The public task documents, manifests, naming table, and license records are protected.

## Player input

All required gameplay is reachable through ordinary visible mouse input. Escape may optionally pause or return from a result, but it is not a required action and a mouse-only implementation remains conforming.

Controls:

| Action | Default |
|---|---|
| Select card / place hero / choose reward / activate result control | Left mouse click |
| Optional pause or cancel | Escape |

Do not require hidden keys, internal method calls, debug menus, command files, sockets, or HTTP.

## Read-only dashboard

- Implementation skeleton: `res://benchmark/dashboard.gd`.
- Self-check: `res://benchmark/dashboard_self_check.gd`.
- Naming table: `res://benchmark/naming-tables.json`.
- Snapshot: `user://benchmark_dashboard.json`.
- Contract: `game-state-dashboard/v2-godot`.

The dashboard reports only the player-observable names in GDD Section 12 and has no action or state-write API. It must not reveal upcoming random rewards or hidden enemy data.

## Materials

- Runtime assets are under `sp/assets/`.
- `Assets/material-index.json` records roles, dimensions, and import facts.
- `Assets/asset-coverage.json` records supplied, procedural, and missing roles.
- `Assets/asset-contact-sheet.png` previews the supplied visual files.
- 

The French upstream balance/style documents are private authoring references and are not part of the English Input.

## Verification

Optional development feedback includes clean import, public smoke, dashboard self-check and ordinary play through the public requirements. No particular self-test sequence or report is required.

Store logs, screenshots, and runtime snapshots outside the submitted project. Remove `.godot/`, logs, screenshots, temporary scripts, and runtime state before delivery. Public smoke and dashboard self-check are optional aids and do not prove gameplay completion.

## Reproducibility

Accept optional `--seed=<integer>` after Godot's `--` separator, default 0. Randomized content repeats for the same seed and player input sequence. Fixed authored layouts do not change. Deterministic implementations may ignore this value.

## Starter observation state

The unfinished starter reports `not_ready`, numeric zero for unavailable slots, and empty entities/targets. In the implemented game report real values and only present, visible objects; menus have no invented player entity. Every snapshot adds `process_id` for process identity. Optional `--dashboard-output=<path>` redirects observation output only.
