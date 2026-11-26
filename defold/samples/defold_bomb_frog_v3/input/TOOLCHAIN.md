# Defold toolchain notes for Bomb Frog v3

## Project and normal player input

- Open `starter_project/game.project` in Defold or use the Bob command documented in
  `DEFOLD_ENGINE_INTERFACE_GUIDE.md`.
- Bootstrap collection: `/main/main.collection`.
- Target game view: 1280 × 720.
- Existing bindings provide arrow keys and WASD, Space, Enter, Escape, R, Q, and left mouse click.
- Gameplay is operated exclusively through those normal keyboard and mouse bindings. The
  Dashboard must not accept or synthesize actions.

## Dashboard wiring

- Shared transport module: `starter_project/main/dashboard.lua`.
- Machine-readable task names: schema-version-2 `naming-tables.json`, validated by
  `naming-tables.schema.json`; an identical convenience copy is available at
  `starter_project/benchmark/naming-tables.json`.
- The gameplay script supplies a read-only capture function to `dashboard.init(...)`, calls
  `dashboard.update(dt)` from its normal update loop, and calls `dashboard.final()` at shutdown.
- The trace is `dashboard.jsonl` in the process launch working directory. Launching the executable
  with `starter_project/` as its working directory writes the file there.
- Each line is one complete snapshot. The file is truncated once at process start and a new line is
  appended only when the reported payload changes.
- Target rectangles use 1280 × 720 game-view pixels with origin at the bottom-left. They must be
  derived from the same rectangles used by the real mouse hit test.

Run the public format checker from this input directory:

```bash
python3 tools/dashboard_self_check.py \
  starter_project/dashboard.jsonl \
  naming-tables.json
```

The checker proves format conformance only. It does not prove that gameplay is correct or that a
reported fact matches the rendered game.

## Deterministic chambers

Both chamber layouts and hidden-treasure assignments are fixed. No seed entry point is required.
The public coordinate space is 9 × 7; chamber 1 uses its declared 7 × 5 active rectangle and
chamber 2 uses the full grid.
