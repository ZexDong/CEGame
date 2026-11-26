# Unity 6 offline command reference for Sign Circuit

This file is a concise command companion to `UNITY_BENCHMARK_TOOL_GUIDE.md` and
`TOOLCHAIN.md`. It does not add player-facing requirements. `GDD.md` Section 6
remains authoritative.

## 1. Fixed local tools

From the current project root:

```powershell
$Project = (Resolve-Path '.').Path
$Editor = $env:UNITY_EDITOR
$Cli = $env:UNITY_CLI
```

Expected versions:

```text
Unity Editor Unity (2dfd32957da2)
Unity CLI 1.0.0-beta.3
Input System 1.19.0
Test Framework 1.6.0
```

Use only installed packages and supplied assets. Runtime code under
`Assets/Benchmark/Runtime/**` cannot reference `UnityEditor`. Optional one-shot
Editor helpers belong under `Assets/Benchmark/Editor/**` and cannot be required
when the saved scene enters Play Mode.

## 2. Public test commands

Close the Editor that owns this exact project and wait for its process and lock to
exit. Create new timestamped paths and execute the two pinned commands:

```powershell
$Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$SmokeDir = Join-Path $Project 'Logs\PublicSmoke'
New-Item -ItemType Directory -Force -Path $SmokeDir | Out-Null
$EditXml = Join-Path $SmokeDir "public-editmode-$Stamp.xml"
$PlayXml = Join-Path $SmokeDir "public-playmode-$Stamp.xml"

& $Cli --json --non-interactive test $Project `
  --mode EditMode `
  --filter 'OmniGame.Benchmark.SignCircuit.PublicTests.SignCircuitPublicEditModeTests' `
  --output $EditXml --editor-path $Editor --timeout 600
$EditExit = $LASTEXITCODE
if ($EditExit -ne 0) { throw "EditMode CLI exit: $EditExit" }

& $Cli --json --non-interactive test $Project `
  --mode PlayMode `
  --filter 'OmniGame.Benchmark.SignCircuit.PublicTests.SignCircuitPublicPlayModeTests' `
  --output $PlayXml --editor-path $Editor --timeout 900
$PlayExit = $LASTEXITCODE
if ($PlayExit -ne 0) { throw "PlayMode CLI exit: $PlayExit" }
```

Parse each new XML rather than trusting only the process exit:

```powershell
[xml]$Edit = Get-Content -Raw -Encoding UTF8 -LiteralPath $EditXml
[xml]$Play = Get-Content -Raw -Encoding UTF8 -LiteralPath $PlayXml

$EditCases = @($Edit.SelectNodes('//test-case'))
$PlayCases = @($Play.SelectNodes('//test-case'))
if ($EditCases.Count -ne 2 -or @($EditCases | Where-Object result -ne 'Passed').Count -ne 0) {
  throw 'EditMode expected 2/2 Passed.'
}
if ($PlayCases.Count -ne 1 -or @($PlayCases | Where-Object result -ne 'Passed').Count -ne 0) {
  throw 'PlayMode expected 1/1 Passed.'
}
```

A new readable `2/2 Passed` EditMode XML and `1/1 Passed` PlayMode XML are
required. The PlayMode test advances real frames, checks the saved scene and camera, and
rejects blocking runtime errors, but it does not complete the route.

## 3. Open the current project

When a controllable Unity desktop is available:

```powershell
& $Cli --json --non-interactive open $Project --editor-path $Editor
if ($LASTEXITCODE -ne 0) { throw "Unity open exit: $LASTEXITCODE" }
```

Wait for import and compilation and inspect the new project-local log. A live
Editor command server is not required.

## 4. Runtime input implementation facts

Use `Keyboard.current`/`Mouse.current`, enabled Input Actions, or `PlayerInput` for the
player-facing keyboard and pointer controls documented by the GDD. Required pointer
controls need real uGUI Buttons under Canvas, GraphicRaycaster, EventSystem, and an Input-
System-compatible UI module. Required text and panels need real visible uGUI `Text` or
`TMP_Text`/Graphic surfaces. Do not call gameplay outcome methods to imitate input.

The protected read-only probe may expose current state and screen locations, but
it cannot perform an action or replace the runtime input implementation.

## 5. Exact-project PID safety

A scene reload or a new Play session is not a separate process. Match only the
Unity Editor whose command line contains the exact normalized project path:

```powershell
function Get-ExactProjectUnityProcess([string]$ProjectPath) {
  $Exact = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')
  $Token = [regex]::Escape($Exact)
  $Pattern = '(?i)(?:^|\s)-projectPath\s+(?:"' + $Token + '"|' + $Token + ')(?=\s|$)'
  @(Get-CimInstance Win32_Process -Filter "Name='Unity.exe'" | Where-Object {
      -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
      [string]$_.CommandLine -match $Pattern
    })
}
```

Close only an unambiguous exact-project process:

```powershell
$Owned = @(Get-ExactProjectUnityProcess $Project)
if ($Owned.Count -gt 1) { throw 'More than one Unity process owns this exact project.' }
$ClosedPid = $null
if ($Owned.Count -eq 1) {
  $ClosedPid = [int]$Owned[0].ProcessId
  Stop-Process -Id $ClosedPid
  Wait-Process -Id $ClosedPid -Timeout 60 -ErrorAction SilentlyContinue
}
if (@(Get-ExactProjectUnityProcess $Project).Count -ne 0) {
  throw 'The exact-project Unity process or lock is still active.'
}
```

When closing an interactively opened project, retain and stop only its exact-path
PID. Never use `taskkill /IM Unity.exe` or `Stop-Process -Name Unity`.

## 6. Protected probe quick reference

Keep `Assets/BenchmarkContract/**` unchanged. Publish through
`SignCircuitProbePublisher.Publish(...)` with schema version `2`.

Action IDs:

```text
menu.sign_circuit
menu.levels
menu.original_level
menu.continue
ui.restart
```

Observation IDs:

```text
ui.progress
ui.timer
ui.best
ui.status
panel.pause
panel.success
panel.failure
```

Use bottom-left-origin Game View pixel rectangles clipped to the real visible
viewport. IDs are unique case-insensitively. Action rectangles match the visible
uGUI control; observation rectangles overlap the corresponding visible uGUI/TMP
surface. Panel IDs locate the visible panel container, not only its title.
`TOOLCHAIN.md` lists every snapshot and target field.

## 7. Project-local diagnostics

- Public XML and related command output: `Logs/PublicSmoke/`
- Unity-generated project state: `Library/`, `Logs/`, `Temp/`, `UserSettings/`,
  `obj/`
- Unity command log: the explicit project-local `-logFile` path for that command

Use new timestamped project-local XML paths. Do not create root
`TestResults.xml` or `TestResults/`. Unity may create its own caches; do not treat
a cache file as a test result.

## 8. Common first checks

| Symptom | First check |
|---|---|
| package or import timeout | Exact-project Editor ownership, project lock, and the newest CLI/Editor log. |
| compiler error | First project-owned source location in the complete compiler output. |
| zero tests | Exact filter, compiled test asmdefs, new XML path, and discovered test-case count. |
| keyboard has no effect | Current Input System device, enabled action or `PlayerInput`, active Game view, and gameplay-state routing. |
| pointer does not activate | Visible clipped target, Canvas/GraphicRaycaster, EventSystem UI module, top raycast hit, and runtime click routing. |
| probe is missing or stale | Publication occurs in the active Menu, Circuit, or legacy scene on current frames. |
| screenshot is blank | Enabled camera, target display, culling mask, layers, and first runtime exception. |
| `Arial.ttf` exception | Use `LegacyRuntime.ttf` or an imported/serialized font. |
| runtime uses `UnityEditor` | Move one-shot code under the Editor root or remove the runtime dependency. |
| Restart duplicates state | Stale listeners, actions, coroutines, static state, spawned objects, or audio. |
| best time disappears | Durable save path, completed write, exact-project close, and distinct-PID reopen. |
| old level is broken | Protected scene unchanged and original Menu/Level1+2 controls still available. |
| world-space line ignores movement | Update world points or use consistently authored local-space points. |
| old and new objects overlap after Restart | Deactivate/unregister, cross a player-loop frame, then rebuild. |

State only commands and behavior that were actually observed.
