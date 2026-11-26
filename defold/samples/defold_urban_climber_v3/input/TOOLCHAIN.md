# Defold toolchain — Urban Climber v3

## Entry and build

Open [starter_project/game.project](starter_project/game.project) in Defold.
The bootstrap is `/main/main.collection` and the game view is 960 × 540.
The starter has no external library dependency and intentionally opens an empty window.

The verified Bob/JDK paths, build commands, executable discovery, and exact-process shutdown
are in [DEFOLD_ENGINE_INTERFACE_GUIDE.md](DEFOLD_ENGINE_INTERFACE_GUIDE.md). For example, from
`starter_project/` on the supplied native desktop environment:

```bash
DEFOLD_JAR="${DEFOLD_BOB_JAR:?Set DEFOLD_BOB_JAR to the installed Bob JAR}"
: "${DEFOLD_JAVA:?Set DEFOLD_JAVA to the installed Java executable}"
"$DEFOLD_JAVA" -cp "$DEFOLD_JAR" com.dynamo.bob.Bob \
  --root . --platform arm64-macos --variant debug --archive \
  resolve distclean build bundle
```

Bundled executables appear below `starter_project/build/default/`. Launch from the project root
to keep `dashboard.jsonl`, `log.txt`, and any redirected runtime output there.
Build output does not prove Lua initialization or gameplay correctness.

## Supplied normal-input bindings

Bindings are in `starter_project/main/game.input_binding`. The action ID is the string hashed by
Defold for `on_input`; it is not necessarily the physical key name.

| Physical input | Action ID | Task use |
|---|---|---|
| W / Up | `up` | One climbing point up; previous UI choice |
| S / Down | `down` | One climbing point down; next UI choice |
| A / Left | `left` | One point/cell left |
| D / Right | `right` | One point/cell right |
| Enter / Space | `confirm` | Confirm selected UI; activate adjacent beacon during climbing |
| Escape | `pause` | Pause/resume |
| R | `restart` | Retry current level from pause/results |
| Q | `quit` | Menu from pause/results; quit from title menu |

The starter acquires input focus but its `on_input` has no gameplay behavior.
Movement is discrete per press.
Gameplay is driven by the normal bound keyboard events, never by writing
Dashboard state. Context-dependent rules and rejected actions are defined in GDD Section 6.

## Read-only observation and debugging

The supplied `starter_project/main/dashboard.lua` is the shared transport, not game logic.

- Provide a read-only capture function returning `phase`, numeric `slots`, `entities`, and
  `targets` to `dashboard.init(capture)`. The module supplies `revision`.
- Call `dashboard.update(dt)` in the regular update callback and `dashboard.final()` on shutdown.
  `dashboard.publish_now()` can publish important state changes immediately; unchanged payloads
  do not create extra revisions. The regular polling interval is 0.20 seconds.
- The file is `dashboard.jsonl` in the process launch working directory, truncated once on launch
  and appended only when the reported payload changes.
- Use the real current variables that drive gameplay/rendering. Capture has no side effects;
  observing is not an action. Current movement edges and window/closure warnings describe only present facts.
- The public task table is [naming-tables.json](naming-tables.json), with an identical project copy
  at `starter_project/benchmark/naming-tables.json`. Both use shared schema version 2.
- All required slot names are listed in GDD Section 12. Boolean-like slots use documented 0/1
  values; states such as `locked` belong in entities, not numeric slots.
- The blank starter reports all slots as 0 and both arrays empty, with `phase=not_ready`.
  That proves only infrastructure startup, not the required game menu or any feature.
- `print()` and Lua errors are visible in runtime stdout/stderr and `log.txt`.
  Dashboard format checking alone does not prove visible or causal correctness.

From this input directory, check a trace produced by a launch whose working directory was
`starter_project/`:

```bash
python3 tools/dashboard_self_check.py \
  starter_project/dashboard.jsonl \
  naming-tables.json
```

This standard-library-only checker validates snapshots and names, not gameplay quality.
No network service, debug socket, state setter, or extra input bridge is supplied or needed.

## Content and determinism

See [assets/ASSET_MANIFEST.md](assets/ASSET_MANIFEST.md) for required sprite sheets, dimensions, optional backgrounds, and license. Copy used assets into the project; Defold resource paths are rooted there.
Both levels, starting contents, and event schedules are fixed. There is no seed parameter or
randomization requirement. Any gameplay implementation remains inside `starter_project/`.
