# MataroDrive Public Godot Toolchain

## Project boundary

- Engine: Godot `4.7.1.stable.official.a13da4feb`.
- Project root: `sp/`.
- Required main scene: `res://main.tscn`.
- Viewport: `1280x720`.
- Renderer: Mobile.
- Public runtime materials: no upstream bitmap, logo, font, scene, or audio is distributed; implement the required roles with runtime drawing or independently cleared material inside `sp/`.
- Network, runtime downloads, accounts, external paths, and engine migration are unavailable.

Only the copied `sp/` project is writable implementation scope. The public task documents, manifest, naming table, catalog, and license records are protected.

## Player input

| Action | Default input |
|---|---|
| `move_left` | A or Left Arrow |
| `move_right` | D or Right Arrow |
| `jump` | Space or Up Arrow |
| `pause` | Escape |

Menus, level select, reward/result controls, Garage, Settings, and Trophies must be reachable with ordinary visible mouse input.

## Profile save

- Save path: `user://mataro_profile.cfg`.
- The save contains only the profile state listed in GDD `PROGRESS-05`.
- A new process must load that profile before showing the Main Menu.
- Retry/restart must not delete profile progress. Only explicit gameplay actions change it.

## Read-only dashboard

- Implementation skeleton: `res://benchmark/dashboard.gd`.
- Self-check: `res://benchmark/dashboard_self_check.gd`.
- Naming table: `res://benchmark/naming-tables.json`.
- Snapshot: `user://benchmark_dashboard.json`.
- Contract: `game-state-dashboard/v2-godot`.

The dashboard has no drive, jump, purchase, save-reset, or result-forcing API.

## Materials

- `Assets/material-index.json` records all required visual roles as procedural.
- `Assets/asset-coverage.json` records no missing required source role.
- `Assets/asset-contact-sheet.png` shows the permitted procedural role language.
- 

Use runtime-drawn shapes, gradients, particles, and text to keep the car, terrain, collectibles, hazards, power-ups, goal, and UI visually distinct. Do not fetch or reconstruct the unavailable upstream logo or audio.

## Verification

Optional development feedback includes clean import, public smoke, dashboard self-check and ordinary play through the public requirements. No particular self-test sequence or report is required.

Store logs, screenshots, and runtime snapshots outside the submitted project. Remove `.godot/`, logs, screenshots, temporary scripts, and runtime state before delivery. Public smoke and dashboard self-check are optional aids and do not prove gameplay completion.

## Reproducibility

Accept optional `--seed=<integer>` after Godot's `--` separator, default 0. Randomized content repeats for the same seed and player input sequence. Fixed authored layouts do not change. Deterministic implementations may ignore this value.

## Starter observation state

The unfinished starter reports `not_ready`, numeric zero for unavailable slots, and empty entities/targets. In the implemented game report real values and only present, visible objects; menus have no invented player entity. Every snapshot adds `process_id` for process identity. Optional `--dashboard-output=<path>` redirects observation output only.
