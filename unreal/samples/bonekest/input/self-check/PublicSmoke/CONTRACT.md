# Public smoke

Run with PowerShell 7:

```powershell
pwsh -NoProfile -File self-check/PublicSmoke/Invoke-PublicSmoke.ps1 -InputRoot <input> -RunRoot <empty-output> -EngineRoot <installed-ue-5.7.4>
```

RunRoot must be a new/empty directory outside InputRoot. The script copies the project
without generated directories, builds its editor target, loads project assets in the
editor, opens the normal independent game view, checks fresh read-only state, captures
a nonblack client frame, and checks the starter's Space probe when phase is not_ready.
It then closes/reopens into a new process and verifies a fresh session before cleanup.
If the game has been implemented, it checks the same public observation format but
does not demand the unfinished health probe or award gameplay credit.

The snapshot is one complete UTF-8 JSON document. Compact and indented formatting,
LF/CRLF line endings, a final newline, and an optional UTF-8 BOM are accepted. The
reader checks the whole document, process/session identity, a file age of at most
1 second, and an advancing snapshot sequence on initial start and Reopen. A valid
stationary game state still publishes increasing snapshot IDs. A stopped writer,
an old process's document, a partial document, and JSON Lines are not readiness.

The script writes result.json, receipts, build/asset logs, snapshots and client PNGs to
RunRoot. Exit 0 means all health checks passed; exit 1 means a check failed. The result
schema is result.schema.json. A failed run preserves the failure and cleanup receipts.
Desktop capture and input require an unlocked, unobstructed interactive Windows desktop.
The public executor serializes input ownership; an existing lease produces a reported
environment failure. Do not treat process launch alone as a rendered-frame assertion.

Assertions cover build, asset loads/dependencies, fresh process-bound snapshot format,
nonblack 16:9 client frame, optional starter input, fresh Reopen and release of all owned
processes/inputs. No maze, damage, economy, visual-fidelity or requirement correctness
assertion is included. Public package integrity and project health are distinct checks.
