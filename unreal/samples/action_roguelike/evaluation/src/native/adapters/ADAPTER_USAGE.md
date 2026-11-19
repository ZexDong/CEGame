# Candidate state adapters

The game always requests semantic preconditions such as `health=50`,
`credits=50`, `teleport_acquired=true`. Only this layer maps them onto candidate
storage. Current profiles cover the reference and five existing native layouts.
Profiles are selected by source evidence, never by model directory name.

`analyze_fixture_adapter.py` checks native classes, scalar declarations and unique
damage-guard anchors against actual candidate sources. A matching reviewed hash
is recorded as `audited_source_hash`; structural matches with changed bytes are
recorded as `source_structure`. Zero or multiple matching profiles stop staging
with `FIXTURE_BINDING_UNAVAILABLE`. Structural selection does **not** establish
semantic correctness. The instrumented build, native readback and fresh independent
observer confirmation are mandatory before a gameplay trigger.

`stage_fixture.py` emits `ARCandidateAdapter.cpp` and `FixtureAdapterAnalysis.json`
only in a fresh private project. The analysis includes source evidence, actual
byte hashes and a profile-plus-source adapter identity. Runtime replies carry that
identity, before-state, readback and verification for each requested field. The
runner rejects foreign adapters and uncorroborated writes as evaluator faults.

For a new implementation, inspect its authoritative state and extend this small
private profile file (or pass a reviewed alternate file with `--bindings`):

- `PLAYER` / `GAMEMODE` specify the typed views inside the adapter only.
- `*_WRITE` set preconditions; `*_READ` independently read current storage.
  `CLOCK_READ` returns remaining seconds, regardless of internal timer direction.
- `CONTEXT` can resolve and null-check a health component or ability system.
  Component/attribute headers belong in `headers`; their unique source evidence
  belongs in `source_anchors`. `additional_modules` can declare GameplayAbilities
  or other required plugin modules. These extension points have no live component
  or GAS candidate validation in the current set.
- `required_members` describes audited scalar owners. Do not guess health storage
  from a similarly named member; corroborate it through the read-only observer.
- `damage_guards` protect setup against unrelated damage. They must be narrowly
  scoped to player damage, never healing, scoring, pickups or outcome functions.

Unknown semantics, ambiguous source, failed compilation, missing components,
readback mismatch or observation mismatch are `run_invalid`. Do not deduct points
for an unavailable mapping. New implementations require this small reviewed mapping;
the analyzer is not a general C++ semantic inference engine.

After staging and building, `Invoke-ActionRoguelikeFixtureHealth.ps1` accepts a JSON
array of `{ "name": "candidate-key", "project": "absolute-staged-uproject" }` and
checks two distinct health values, credits, teleport state, timer, placement,
orientation, input, capture and cleanup. It emits authoring evidence, never scores.
`-NativeOnly` verifies storage writes/readbacks when diagnosing a candidate with
an unavailable public observer; its `native_only_passed` result does not authorize
gameplay assertions or bypass the canonical observation contract.
