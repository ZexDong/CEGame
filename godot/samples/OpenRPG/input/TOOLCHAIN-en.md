# OpenRPG public toolchain and observation contract

Contract revision: `dashboard-contract-20261022-r2`

## Project and engine

- Open `sp/project.godot`. Godot: `Godot`, GL Compatibility.
- The required final entry is `res://src/main.tscn`; `application/run/main_scene` already points there. Keep this path as the final entry; its internal structure may change.
- Logical viewport: 1920 x 1080, initial client window: 960 x 540, canvas-items stretch. Rectangles in snapshots use logical viewport pixels, not physical desktop coordinates.
- The starting forest includes static building facades. Usable house doors, interiors, chests, NPCs, quests, and combat are still implementation work.
- The starting forest uses cell coordinates x=-12..36 and y=-8..24, including surrounding tree borders. Preserve these cells rather than rearranging them. Gobot starts at world position (24, 200). A static tree patch is placed at (48, 64). Camera2D zoom is 5x with limits (0, 0, 960, 560); starter movement bounds are (0, 0, 592, 400), expandable with new regions.
- Initial forest tiles are 16 x 16 pixels. Gobot's starting art uses region `(1, 1, 16, 16)` of `res://assets/characters/gobot_field.png`. Keep pixel art crisp with nearest filtering; avoid stretching individual sprites into arbitrary proportions. Resource facts are in the asset catalog.
- Existing `ui_left/right/up/down` actions support arrows and WASD. `ui_accept` supports Enter/Space and `interact` supports E/Space. `ui_cancel` uses Escape. Preserve those defaults; additional actions may be added. Mouse actions use normal left-button input. World movement is continuous; no drag or multi-key chord is required by the task.
- The opening's five lines are in `res://maps/opening_cutscene.dtl` as plain text. The starter reads them directly. The bundled Dialogic addon is optional and disabled; no external install is required.
- Use only the provided package and local engine. No external packages, network access, engine migration, or absolute source-resource paths are needed.

## Editing boundary

`BENCHMARK_MANIFEST.json` declares the protected public contract, source assets, public smoke, and self-check. Implement within writable `sp/**` paths while preserving protected matches. You may change the main scene and replace the starter gameplay/reporting scripts. New scripts, scenes, UI, and gameplay resources may be added. Do not rewrite the GDD, naming tables, global contracts, license text, or source assets to claim completion.

The `Assets/` directory contains `material-index.json` and `asset-contact-sheet.png`. Canonical source assets are under `sp/assets/` and `sp/battlers/`; no duplicate source mirror or second project is needed. Resources using `res://` resolve from `sp/`. Read MaterialMapping-en.md before using passive animation scenes or binary AtlasTextures.

## Saves

Store game progress in `user://openrpg_save.json`; its data schema is your choice. This location supports SAVE-02–07 and is separate from the dashboard. On Windows with the supplied project name it resolves below `%APPDATA%/Godot/app_userdata/OpenRPG/`. Godot's `OS.get_user_data_dir()` reports the actual directory. Only a deliberate New Game/Restart replaces valid progress; missing/corrupt files follow the GDD recovery rule.

## Read-only dashboard

- Skeleton and starter adapter: `res://benchmark/dashboard.gd`, already connected to the starter main scene. It reports actual opening/movement state and zero progression for the absent systems. Integrate or replace this read-only mapping as you implement the game.
- Global shape: `DASHBOARD_SPEC.md`. Machine-readable names: `res://benchmark/naming-tables.json`, the single machine-readable table matching GDD section 12. `res://benchmark/dashboard-snapshot.schema.json` describes the existing public snapshot shape; the public self-check additionally checks live PID, viewport bounds, identity, and HP relationships.
- Transport: latest UTF-8 JSON object at `user://benchmark_dashboard.json`. An optional `--dashboard-output=<path>` after `--` overrides only the report destination for isolated checks; it never changes gameplay. Partial file reads should be retried.
- The top-level object includes `revision`, `phase`, `slots`, `entities`, `targets`, and `process_id`. `process_id` is the actual process PID, preventing stale reports from another launch. Revision increases when the report body changes, including rectangles/selection; it is local to the process.
- Allowed phases are exactly the six global values. Exploration, dialogue, ordinary battle, and a battle-victory overlay use `playing`; only the final ending uses `won`; party defeat uses `lost`; pause uses `paused`. `battle_stage` and other slots distinguish intermediate states.
- There is no fixed public navigation grid for the reconstructed areas. Entities report a viewport `rect` instead of `cell`, as permitted by the global contract. Project visible world objects through the active camera and clip to the main viewport. Omit off-screen entities. Progress slots are still present when an object is in another area.
- Entity `id` is a stable public instance identifier, independent of node path; it distinguishes multiple enemies. NPC indices remain bound across reopening. Battle entities also report `hp`, `max_hp`, `selected`, and `acting` as described by the naming table. Target IDs distinguish repeated choices and match combatant IDs where applicable.
- Report each required control when its UI exists. `visible` and `interactable` reflect real rendering, disabled state, and modal coverage. A zero-count Bomb control remains visible and non-interactable. Rectangles describe actual clickable surfaces, not artificial invisible buttons.
- The observer only reports. Do not add an action, reset, inventory mutation, input injection, score, or result-forcing API. Normal keyboard/mouse input performs all gameplay.
- If you choose randomized layout/spawns, accept `--seed=<integer>` after `--` via `OS.get_cmdline_user_args()` and reproduce layout/spawns for the same seed. Randomness is optional.

## Optional local tools

Examples use `<Godot console>` for the executable listed in the shared guide. These tools are available feedback, not a mandatory implementation checklist.

```text
<Godot console> --headless --editor --import --path <copy>/sp
<Godot console> --headless --path <copy>/sp --script res://benchmark/public_smoke.gd
<Godot console> --path <copy>/sp --script res://benchmark/public_smoke.gd
<Godot console> --headless --path <copy>/sp --script res://benchmark/dashboard_self_check.gd
<Godot console> --path <copy>/sp
```

Public smoke loads the configured final entry, waits for it to settle, and checks package/resource and reporting format health; it does not test combat, puzzle solutions, or journey completion. The same script works with the unfinished starter and the final entry. Self-check validates the public naming/format only. Exit 0 indicates a pass, exit 1 a failed check. Full-game correctness comes from the GDD and COMMON_BASELINE, independently of tool choice.

Run tools in a cold copy if you want to keep the source package free from `.godot/`, logs, screenshots, and runtime files. No output from a check belongs in the public starter.

## Canonical document names

The shared guides use generic names such as `TOOLCHAIN.md` and `MaterialMapping.md`. In this package, the manifest resolves these to `TOOLCHAIN-en.md` and `MaterialMapping-en.md`. Read `README-en.md` for starter scope and `sp/benchmark/naming-tables.json` for the public vocabulary. No alias copies are maintained.

## Reproducibility

Accept optional `--seed=<integer>` after Godot's `--` separator, default 0. Randomized content repeats for the same seed and player input sequence. Fixed authored layouts do not change. Deterministic implementations may ignore this value.
