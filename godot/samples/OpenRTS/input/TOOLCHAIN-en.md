# Open RTS public toolchain

Godot; project `sp/`; required main scene `res://main.tscn`; GL Compatibility; 1280x720. Implement in `sp/**`, preserving protected paths in the manifest. Internal organization is free.

## InputMap

| Action | Default |
|---|---|
| `camera_left`, `camera_right`, `camera_up`, `camera_down` | A, D, W, S |
| `select`, `command` | Left/right mouse |
| `selection_modifier` | Shift |
| `rotate_blueprint` | R |
| `zoom_in`, `zoom_out` | Wheel up/down |
| `focus_base`, `idle_worker`, `help`, `pause` | Home, I, F1, Escape |
| `group_1` through `group_9` | 1–9; Ctrl stores, unmodified recalls |

The starter declares actions; the implementation supplies gameplay behavior. Drag and modifier state may use normal input events.

## Observations

`res://benchmark/dashboard.gd` publishes `user://benchmark_dashboard.json`; `capture()` returns the DASHBOARD_SPEC.md read-only format. Vocabulary: `res://benchmark/naming-tables.json`. Additional `process_id` identifies the process. Absent-context numeric slots are zero. The unfinished starter is `not_ready` with no invented gameplay entities.

Optional user argument `--dashboard-output=<path>` redirects only observation output; it cannot control gameplay. Self-check and smoke are optional health checks, not proof of completion. Keep generated output outside the delivered package.

## Reproducibility and materials

Accept `--seed=<integer>` after Godot's `--` separator, default 0. Randomized decisions repeat for the same seed and input sequence; fixed map remains unchanged. No gameplay save.

Source models at `sp/assets/models/` import as PackedScenes with embedded materials. Catalog lists bounds and dependencies. Preserve proportions. The contact sheet previews source models, not a required composition. No upstream scenes, scripts, logos, translations or voice tracks are supplied.

## Starter observation state

The unfinished starter reports `not_ready`, numeric zero for unavailable slots, and empty entities/targets. In the implemented game report real values and only present, visible objects; menus have no invented player entity. Every snapshot adds `process_id` for process identity. Optional `--dashboard-output=<path>` redirects observation output only.
