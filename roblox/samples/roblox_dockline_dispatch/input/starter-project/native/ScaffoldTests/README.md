# Public scaffold checks

Run from the `input/` directory:

```powershell
.\ScaffoldTests\Test-InputScaffold.ps1
```

The script checks Manifest parsing, the 3600-second limit, required public files, public/private directory isolation, relative Rojo paths, public Schema identity, RBXLX XML readability, and optional local `rojo`/`luau-compile` surfaces when tools can be found.

A PASS proves only that this public input and blank starter are usable. It does not prove that target gameplay exists, Roblox Studio Play succeeds, or any scored behavior is correct. A missing optional CLI is reported as NOT RUN rather than a gameplay failure.
