# Public Smoke Test

`Invoke-PublicSmoke.ps1` is the repeatable health check for this public starting package. It validates package and tool identities, parses the public task-state schemas, creates a disposable exact project copy under the external run root, runs Unreal Data Validation, starts the copied default entry in the executor's observer-disabled stable-window mode, obtains a bounded non-black client capture, performs a true process Reopen, obtains another non-black client capture, and verifies final input and process cleanup. Each capture receipt records the actual host client size; exact candidate-evaluation viewport enforcement is outside this common-start smoke.

It does **not** evaluate any gameplay requirement in `GDD.md`. The answer-free Content-only common start intentionally has no gameplay provider, so its smoke validates the contract files and real window lifecycle without claiming candidate task-state publication.

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 `
  -InputRoot <input> `
  [-EngineRoot <engine-root>] `
  -BenchmarkToolsRoot <benchmark-tools-root> `
  -RunRoot <new-empty-run-root>
```

The run root must be outside the public input and must be new or empty.

When `-EngineRoot` is omitted, the smoke invokes `tools/Resolve-Unreal56.ps1` and validates UE 5.6.1 (CL 44394996) automatically.

| Exit code | Meaning |
|---:|---|
| `0` | All public health assertions passed. |
| `1` | A release or project assertion failed. |
| `2` | Parameters, tools, environment, evidence, or cleanup prevented a valid verdict. |

The machine result is `<run-root>/public-smoke-result.json` and follows `schemas/public-smoke-result.schema.json`. Logs, captures, state, and receipts remain inside the external run root and must not be copied into the public input.
