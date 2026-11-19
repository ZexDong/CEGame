# Defold toolchain notes for Timelooper v2

## Project and normal player input

- Open `starter_project/game.project` in Defold 1.13.0 or use the Bob command documented in
  `DEFOLD_ENGINE_INTERFACE_GUIDE.md`.
- Bootstrap collection: `/main/main.collection`.
- Target game view: 960 × 540.
- Existing bindings provide A/D and Left/Right for continuous horizontal movement; W, Up, Space,
  and X for jump; Enter for confirmation; R for restart; and Escape for pause/back.
- Gameplay is operated exclusively through these normal keyboard bindings. The Dashboard never
  accepts, synthesizes, or forwards actions.

## Dashboard wiring

- Shared transport module: `starter_project/main/dashboard.lua`.
- Task vocabulary: schema-version-2 `naming-tables.json`, validated by
  `naming-tables.schema.json`; an identical convenience copy is at
  `starter_project/benchmark/naming-tables.json`.
- Supply a read-only capture function to `dashboard.init(...)`, call `dashboard.update(dt)` from
  the normal update loop, and call `dashboard.final()` at shutdown.
- The trace is `dashboard.jsonl` in the process launch working directory. Launching the executable
  with `starter_project/` as its working directory writes the file there.
- Each line is one complete snapshot. The file is truncated once at process start and a line is
  appended only when the reported payload changes.
- Entity `position` is the real center and `size` is the full extent in the 960 × 540 bottom-left
  world coordinate system. This task has no mouse targets, so `targets` is empty.

Run the public format checker from this input directory:

```bash
python3 tools/dashboard_self_check.py \
  starter_project/dashboard.jsonl \
  naming-tables.json
```

The checker proves format conformance only. It does not prove gameplay correctness or agreement
between the report, collisions, and rendered scene.

## Determinism

The required level, gem placement, hazards, mechanisms, and ten-second echo schedule are fixed.
No seed entry point is required.
