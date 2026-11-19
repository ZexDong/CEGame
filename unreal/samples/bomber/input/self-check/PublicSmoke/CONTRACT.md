# Bomber Local Duel Public Smoke

This smoke is a public engineering-health check. It proves that a release input is internally consistent, the source target builds, the documented project entry starts a real client frame, the engine-health and task-state transports have healthy identities, a true Reopen produces a new process, and final cleanup succeeds.

It does not execute, accept, reject, or score any `GDD.md` gameplay requirement. The unmodified starter is expected to publish `provider_ready=false` and `game_state=null`. A completed candidate is expected to publish `provider_ready=true`; the smoke accepts either valid bridge state because its only concern is transport health.

## Command

Use a new or empty run directory outside the public input:

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 `
  -InputRoot <input> `
  -EngineRoot <engine-root> `
  -BenchmarkToolsRoot <benchmark-tools-root> `
  -RunRoot <run-root>
```

The launcher must provide:

- Unreal Engine 5.7.4 at `<engine-root>`;
- the repository public Unreal capability contract, validation summary, executor, executor native interop source, observer, operation-result schema, and state-snapshot schema under `<benchmark-tools-root>/engine/unreal-5.7.4/`, with SHA-256 identities matching `BENCHMARK_MANIFEST.json`;
- a Windows interactive desktop suitable for a 1280 x 720 game client; and
- a fresh run root that can contain logs, state, receipts, and captures.

## Assertions

| Check | Assertion |
|---|---|
| `package_identity` | The benchmark/file manifests, hashes, JSON, English-only gate, assets, paths, release boundary, and all seven declared public-tool identities are consistent. |
| `source_build` | `BomberStarterEditor Win64 Development` builds with exit code `0`. |
| `initial_start` | The public executor starts a bound independent game window and receives the first engine-health frame. |
| `initial_engine_state` | A fresh engine-health snapshot matches the process identity. |
| `initial_task_state` | The task-state envelope is fresh, read-only in shape, and matches the process identity. |
| `initial_capture` | A new client-only PNG is captured at 1280 x 720. |
| `reopen_identity` | Reopen closes the old process and creates a different process ID and token. |
| `reopen_state` | Both transports publish fresh state for the new process. |
| `reopen_capture` | A second client-only PNG is captured from the reopened process. |
| `final_cleanup` | Controlled input is released, the process tree is empty, and the input lease is released. |

## Result and exit codes

The script writes `public-smoke-result.json` using `schemas/public-smoke-result.schema.json` and keeps all referenced evidence run-relative.

| Exit code | Meaning |
|---:|---|
| `0` | Every public health assertion passed. |
| `1` | A release/project assertion failed with otherwise healthy smoke infrastructure. |
| `2` | Parameters, engine/tool availability, executor/desktop state, or cleanup prevented a valid health verdict. |

A failed or blocked smoke is not a gameplay score. Preserve the run directory for diagnosis and use a fresh run root for the next attempt.


