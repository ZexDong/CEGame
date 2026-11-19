# Defold toolchain notes for this task

## Project and normal player input

- Open `starter_project/game.project` in Defold 1.13.0, or use the Bob command documented in
  `DEFOLD_ENGINE_INTERFACE_GUIDE.md`.
- Bootstrap collection: `/main/main.collection`.
- Logical game view: 1136 × 640.
- The supplied input binding maps W/Up, S/Down, A/Left, and D/Right to continuous movement; Enter
  and Space to `action`; Escape to `pause`; R to `restart`; and MouseButton1 to `click`.
- Continuous movement uses normal key press, hold, and release. Briefing, pause, and result controls
  may also be operated with normal left-mouse clicks.
- The Dashboard is observation-only. It must not receive, synthesize, or route player input.

## Dashboard wiring for this task

- Canonical transport module: `starter_project/main/dashboard.lua`.
- Machine-readable task names: `starter_project/benchmark/naming-tables.json`.
- Supply `dashboard.init(...)` with a capture function that reads the same authoritative player,
  cargo, delivery-zone, obstacle, timer, and UI state used by gameplay and rendering.
- Call `dashboard.update(dt)` from the normal update loop and `dashboard.final()` on shutdown.
- The transport writes `dashboard.jsonl` in the process launch working directory. Launch the
  executable with `starter_project/` as its working directory when you want the trace there.
- Each line is one complete snapshot. The file is truncated at process start and gains a revision
  only when the reported payload changes.
- Entity positions and full sizes use continuous `[x, y, z]` world coordinates with `y` up.
- GUI target rectangles use `[left, bottom, width, height]` in the 1136 × 640 game view. They are
  not host-desktop coordinates and do not include the operating-system title bar.
- Run the public checker from this input directory:

```bash
python3 tools/dashboard_self_check.py \
  starter_project/dashboard.jsonl \
  naming-tables.json
```

The checker validates the shared format and published names. It does not prove gameplay
correctness; reported facts must still agree with normal input, collision, the visible world, and
the HUD.

## Randomness

This task does not require a randomized layout, cargo placement, task size, or shift length. There
is no seed entry point.
