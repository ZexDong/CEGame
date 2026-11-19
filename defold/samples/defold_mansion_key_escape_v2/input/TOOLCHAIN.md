# Defold toolchain notes for this task

## Project and normal player input

- Open `starter_project/game.project` in Defold 1.13.0, or use the Bob command documented in
  `DEFOLD_ENGINE_INTERFACE_GUIDE.md`.
- Bootstrap collection: `/main/main.collection`.
- Logical game view: 960 × 540.
- W/A/S/D and the arrow keys are continuous held movement. Enter or Space confirms and interacts;
  Escape returns from a page or closes the current modal as described by the GDD.
- A direction is held from its Defold `pressed` event until the matching `released` event. Normal
  movement must not depend on operating-system key repeat.
- The Dashboard is observation-only. It must not receive, synthesize, or route keyboard actions.

## Dashboard wiring for this task

- Canonical transport module: `starter_project/main/dashboard.lua`.
- Machine-readable task names: `starter_project/benchmark/naming-tables.json`.
- Your game supplies a read-only capture function to `dashboard.init(...)`, calls
  `dashboard.update(dt)` from the normal update loop, calls `dashboard.publish_now()` after real
  state transitions that need immediate observation, and calls `dashboard.final()` on shutdown.
- The transport file is `dashboard.jsonl` in the process launch working directory. Launch the
  executable with `starter_project/` as its working directory when you want the trace there.
- Each line is one complete JSON snapshot. The file is truncated when the process starts and gains
  a new line only when the reported payload changes.
- All Mansion entities use the `position` geometry declared in `naming-tables.json` and also report
  `size`. Coordinates are room-local 960 × 540 game-view pixels with bottom-left origin. Combine a
  position with numeric slot `room_index` (`0` foyer, `1` study, `2` courtyard) before comparing or
  navigating across rooms.
- This keyboard-only task has no pointer targets, so every snapshot reports `targets: []`.
- Run the public format checker from this input directory:

```bash
python3 tools/dashboard_self_check.py \
  starter_project/dashboard.jsonl \
  naming-tables.json
```

The checker validates format and published names. It does not judge whether gameplay is complete
or whether a reported fact agrees with the rendered game; the mapping must still be truthful.

## Randomness

The required room layout, puzzle order, and threat setup may be deterministic. This task has no
required seed entry point.
