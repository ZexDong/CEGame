# Timelooper v2 — Public Input

Build the game described by `GDD.md` inside `starter_project/`.

The complete published task boundary is:

- `GDD.md` — game-specific requirements;
- `COMMON_BASELINE.md` — shared expectations for a playable game;
- `DASHBOARD_SPEC.md`, `naming-tables.schema.json`, and `naming-tables.json` — the required
  read-only state report and its task vocabulary;
- `TOOLCHAIN.md` and `DEFOLD_ENGINE_INTERFACE_GUIDE.md` — verified Defold build and API notes;
- `assets/`, `reference_images/`, and `legal/` — allowed assets, visual references, and licensing.

The starter is intentionally minimal and contains no target gameplay. The supplied Dashboard
module is read-only transport infrastructure; the implementation must map its own authoritative
live state into the public vocabulary.

Implement only in `starter_project/`. The public package contains no reference implementation,
private checkpoint script, evaluator, score, fixed solution route, or virtual gameplay input.
Copy only the asset files needed by the implementation from `assets/` into `starter_project/`
before referencing them from Defold resources.
