# Dungeon Duel v2 Unity task contract

Player-facing acceptance is defined only by numbered requirements in `GDD.md` Section 6.
This file defines Dungeon-specific Unity paths, public tests, normal-input surfaces, and
the public read-only Probe. Shared engine facts are in `UNITY_BENCHMARK_TOOL_GUIDE.md`.

## Fixed environment and paths

```text
Unity Editor: Unity
Unity CLI: 1.0.0-beta.3
Input System: 1.19.0
AI Navigation: 2.0.13
URP: 17.0.4
Test Framework: 1.6.0
uGUI: 2.0.0
Main scene: Assets/DungeonDuelBenchmark/Scenes/DungeonDuel.unity
Writable root: Assets/DungeonDuelBenchmark/**
Additional writable file: ProjectSettings/EditorBuildSettings.asset
```

Use only installed packages and supplied assets. Runtime assemblies must not reference
`UnityEditor`. Save the main scene, components, UI, materials, references, and Build
Settings before Play. The delivered game must not require an Editor startup callback to
assemble the runtime scene.


## Supplied asset context

`BENCHMARK_MANIFEST.json` declares `ASSET_CONTACT_SHEET.png` as the startup inventory image.
Exact source paths, hashes, Unity GUIDs, semantic roles and handling notes are in
`ASSET_CATALOG.json`, `ASSET_CATALOG.md`, and `ASSET_COVERAGE.json`. The contact sheet is
rendered only from the public starter Scene and source Prefabs; it is not a final encounter
layout or evaluation Reference. The presentation Prefabs do not contain the required
gameplay. Preserve protected sources and author all final gameplay and derived content
under `Assets/DungeonDuelBenchmark/**`.

## Normal input and visible surfaces

The project uses Input System Package (New) only. Supported implementation routes are
`Keyboard.current` and `Mouse.current`, enabled `InputAction`, or `PlayerInput`. The player
left-clicks reachable floor to move, right-clicks a living enemy to attack, points at floor
and presses `2` to Dash, presses `R` to Restart, or left-clicks the visible runtime Restart
control. One player action creates at most one matching intent, and UI input must not fall
through to the world. Player, both Imps, Boss, gate, and floor use real visible Renderer
and Collider geometry reachable from the active gameplay Camera. Runtime HUD and Restart
use visible uGUI or TMP surfaces with a GraphicRaycaster, EventSystem, and an Input-System-
compatible UI module. IMGUI, UI Toolkit, editor controls, or reported data without matching
runtime geometry cannot be the only required player-facing route.

If `NavMeshAgent` is used, place it on a baked reachable NavMesh before calling
`SetDestination`. Equivalent custom movement is allowed. Preserve supplied URP,
materials, VFX, and audio references; check a material property with `HasProperty` before
writing it.

## Public read-only Probe

The saved main scene contains exactly one active `MonoBehaviour` implementing:

```text
OmniGame.Benchmark.DungeonDuel.V2.IDungeonDuelBenchmarkProbe
```

It reports contract `2.0`, a truthful current Player/Imp/Boss/gate/Dash/audio/phase
snapshot, real visible actor and gate target GameObjects, and three finite reachable world
positions. It has no action or state-mutation method. Reported values and targets must
match the same runtime state and surfaces used by the player.

## Public validation commands

Run from the current project while no Editor owns it. Use new project-local paths for every
log and NUnit XML.

```powershell
$Project = (Get-Location).Path
$Cli = $env:UNITY_CLI
$Editor = $env:UNITY_EDITOR
$Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$CheckDir = "$Project\Logs\ToolChecks\$Stamp-dungeon"
$HostTemp = "$CheckDir\host-temp"
$EditXml = "$CheckDir\editmode.xml"
$PlayXml = "$CheckDir\playmode.xml"
$EditLog = "$CheckDir\editmode.log"
$PlayLog = "$CheckDir\playmode.log"
New-Item -ItemType Directory -Force -Path $CheckDir,$HostTemp | Out-Null
$OldTemp=$env:TEMP; $OldTmp=$env:TMP
try {
  $env:TEMP=$HostTemp; $env:TMP=$HostTemp
  & $Cli --json --non-interactive --proxy-disable test $Project --mode EditMode `
    --filter 'OmniGame.Benchmark.DungeonDuel.PublicSmoke' --output $EditXml `
    --editor-path $Editor --timeout 600 -- -logFile $EditLog
  if ($LASTEXITCODE -ne 0) { throw "EditMode smoke failed: $LASTEXITCODE" }

  & $Cli --json --non-interactive --proxy-disable test $Project --mode PlayMode `
    --filter 'OmniGame.Benchmark.DungeonDuel.PublicRuntimeSmoke' --output $PlayXml `
    --editor-path $Editor --timeout 900 -- -logFile $PlayLog
  if ($LASTEXITCODE -ne 0) { throw "PlayMode smoke failed: $LASTEXITCODE" }
} finally {
  $env:TEMP=$OldTemp; $env:TMP=$OldTmp
}
```

EditMode must report `6/6 Passed`; PlayMode must report `1/1 Passed`. Missing, stale, or
zero-test XML is not a pass. The PlayMode smoke loads the saved scene and advances real
frames to expose startup failures; it does not execute movement, combat, Dash, terminal,
Restart, or reopen flows.

## Open and distinct-process reopen

```powershell
& $Cli --json --non-interactive --proxy-disable open $Project --editor-path $Editor
```

Use `open` only when a controllable Game view exists; a shell-only process must not claim
that it operated the Game view.

A genuine reopen closes the Editor that owns this exact project and opens the same project
in a new PID. For automated ownership, snapshot exact-project Unity PIDs before `open`,
then match `Win32_Process.CommandLine` against the exact normalized project path and bind
exactly one new PID. Close only that PID. Stop nothing when matching is missing or
ambiguous; never terminate Unity processes by image name.

Restart and reopen both reconstruct a clean encounter. No health, death, gate, Dash,
position, or terminal progress persists through PlayerPrefs or files.
