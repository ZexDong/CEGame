# Defold toolchain notes for this task

## Project and normal player input

- Open `starter_project/game.project` in Defold 1.13.0, or use the Bob command documented in
  `DEFOLD_ENGINE_INTERFACE_GUIDE.md`.
- Bootstrap collection: `/main/main.collection`.
- Logical game view: 1280 × 720.
- The existing input binding maps the left mouse button to the Defold action `click`.
- Start Shift, generator, upgrade, pause, resume, restart, and exit controls are operated with normal
  pointer clicks. A complete click is a press and release over the same visible control.
- The dashboard is observation-only. It must not receive, synthesize, or route pointer actions.

## Dashboard wiring for this task

- Canonical transport module: `starter_project/main/dashboard.lua`.
- Machine-readable task names: `starter_project/benchmark/naming-tables.json`.
- Your game supplies a read-only capture function to `dashboard.init(...)`, calls
  `dashboard.update(dt)` from the normal update loop, and calls `dashboard.final()` on shutdown.
- The transport file is `dashboard.jsonl` in the process launch working directory. Launch the
  executable with `starter_project/` as its working directory when you want the trace there.
- Each line is one complete JSON snapshot. The file is truncated when the process starts and gains a
  new line only when the reported state changes.
- Every reported entity has a stable `id`, and each Station entity kind uses the `rect` geometry
  declared in `naming-tables.json`. Entity and target rectangles are
  `[left, bottom, width, height]` in the 1280 × 720 logical game view. They are not desktop
  coordinates and do not include the operating-system title bar.
- Run the public format checker from this input directory:

```bash
python3 tools/dashboard_self_check.py \
  starter_project/dashboard.jsonl \
  naming-tables.json
```

The checker validates format and published names. It does not judge whether the game is complete or
whether the reported facts agree with the visible game; those facts must still be truthful.

## Randomness

This task does not require random layout, prices, upgrade order, or timing. There is no seed entry
point.
