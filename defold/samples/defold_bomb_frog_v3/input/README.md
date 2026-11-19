# Bomb Frog v3 — Frozen Public Input

Build the game described by `GDD.md` inside `starter_project/`.

The complete published acceptance boundary is:

- `GDD.md` — game-specific requirements;
- `COMMON_BASELINE.md` — shared expectations for any playable game;
- `DASHBOARD_SPEC.md`, `naming-tables.schema.json`, and `naming-tables.json` — the required
  read-only state report and the schema for its task vocabulary;
- `TOOLCHAIN.md` and `DEFOLD_ENGINE_INTERFACE_GUIDE.md` — verified Defold build and API notes;
- `reference_images/` and `legal/` — visual references and their license.

This v3 task requires two sequential fixed chambers and a two-hit armored enemy; `GDD.md` is the
authoritative frozen public boundary. The starter is intentionally minimal and contains no target
gameplay. The shared Dashboard transport is provided as infrastructure, but the game must
truthfully map its own authoritative live state into it.

Implement only in `starter_project/`. Do not expect access to a reference implementation, private
checkpoint script, evaluator, score, hidden treasure positions, or precomputed solution.
