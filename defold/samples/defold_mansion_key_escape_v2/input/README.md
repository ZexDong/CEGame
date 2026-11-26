# Fog Mansion: Key Escape — public input

This directory is the complete public starting point for the task. Develop only inside
`starter_project/`; it is intentionally buildable but contains no target exploration gameplay.

Read:

1. `GDD.md` — the task-specific player requirements and published Dashboard names;
2. `COMMON_BASELINE.md` — the game-independent quality requirements;
3. `DASHBOARD_SPEC.md` — the shared read-only state format;
4. `naming-tables.json` — the exact Mansion slot, entity, and control names;
5. `dashboard-snapshot.schema.json` and `naming-tables.schema.json` — the two public JSON schemas;
6. `DEFOLD_ENGINE_INTERFACE_GUIDE.md` — verified Defold engineering interfaces;
7. `TOOLCHAIN.md` — this task's project entry, normal keyboard input, coordinate space, and
   Dashboard transport;
8. `assets/ASSET_MANIFEST.md`, `reference/README.md`, and `legal/UPSTREAM_MIT_LICENSE.txt` —
   permitted assets, visual references, and provenance.

The GDD and Common Baseline define what to build. The remaining documents define tools and a
read-only observation interface. The Dashboard has no input, query command, coordinate mutation,
inventory mutation, door control, teleport, restart, or result-forcing operation.

Reference screenshots constrain the requested composition and information hierarchy; they are not
pre-rendered game backgrounds. This input contains no Gold source, private checkpoint script,
score weights, answer path, evaluator, or historical result.
