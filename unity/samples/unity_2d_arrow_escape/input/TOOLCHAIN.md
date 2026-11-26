# Arrow Escape v2 Unity task contract

Player-facing acceptance is defined only by numbered requirements in `GDD.md` Section 6.
This file defines only the Arrow-specific Unity execution and observation boundary. Shared
Unity and CLI facts are in `UNITY_BENCHMARK_TOOL_GUIDE.md`.

## Fixed environment and paths

```text
Unity Editor: Unity
Unity CLI: 1.0.0-beta.3
Input System: 1.19.0
Test Framework: 1.6.0
Viewport: 1280 x 720
Main scene: Assets/ArrowEscapeBenchmark/Scenes/ArrowEscape.unity
Writable root: Assets/ArrowEscapeBenchmark/**
Additional writable file: ProjectSettings/EditorBuildSettings.asset
```

Use only the installed packages and supplied assets. Runtime code must not depend on
`UnityEditor`. Save the main scene, levels, prefabs, references, and Build Settings before
Play. The delivered game must not require an Editor startup callback to assemble itself.

## Supplied asset context

`BENCHMARK_MANIFEST.json` declares `ASSET_CONTACT_SHEET.png` as the one startup inventory image. Exact source paths, hashes, dimensions, alpha bounds, importer facts, semantic roles, and coverage are in `ASSET_CATALOG.json`, `ASSET_CATALOG.md`, and `ASSET_COVERAGE.json`. The contact sheet is not a finished board or target composition. Protected Texture Type Default imports may be copied into `Assets/ArrowEscapeBenchmark/**` and configured there; do not edit their protected importers.

## Public validation commands

Run from the current project while no Editor owns it. Use fresh project-local output paths
and read both the CLI exit code and new NUnit XML.

```powershell
$Project = (Get-Location).Path
$Cli = $env:UNITY_CLI
$Editor = $env:UNITY_EDITOR
$Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$CheckDir = "$Project\Logs\ToolChecks\$Stamp-arrow"
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
    --filter 'OmniGame.Benchmark.ArrowEscape.PublicSmoke' --output $EditXml `
    --editor-path $Editor --timeout 600 -- -logFile $EditLog
  if ($LASTEXITCODE -ne 0) { throw "EditMode smoke failed: $LASTEXITCODE" }

  & $Cli --json --non-interactive --proxy-disable test $Project --mode PlayMode `
    --filter 'OmniGame.Benchmark.ArrowEscape.PublicSmoke' --output $PlayXml `
    --editor-path $Editor --timeout 900 -- -logFile $PlayLog
  if ($LASTEXITCODE -ne 0) { throw "PlayMode smoke failed: $LASTEXITCODE" }
} finally {
  $env:TEMP=$OldTemp; $env:TMP=$OldTmp
}
```

EditMode must report `4/4 Passed`; PlayMode must report `1/1 Passed`. Missing, stale, or
zero-test XML is not a pass. The PlayMode smoke loads the saved scene, advances real
player-loop frames, and checks the public observation surface. It does not complete the
three levels or certify the numbered GDD flow.

## Normal input boundary

Player actions use Unity Input System `Mouse` state. Supported implementation routes
include `Mouse.current` polling, enabled `InputAction` or `PlayerInput`, and an Input-System-
compatible EventSystem. An ordinary left-click on one visible target commits at most one
matching intent. Press-only, cross-target, blank, moving-target, removed-target, and
post-terminal interactions must not commit an unintended action. Required controls and
world targets need real visible geometry reachable through the player-facing input route.
Pure IMGUI, UI Toolkit, or a reported rectangle without matching runtime geometry cannot
be the only required player route.

## Read-only Probe

The saved main scene contains exactly one active `IArrowEscapeReadOnlyProbe` reporting
contract `3.0`. `CaptureBenchmarkSnapshot()` may only describe the current player-visible
state. It must not perform player actions, mutate state, load fixtures, restart, or force a
result.

`VisibleTargets` is a complete current registry:

- one `Kind = Arrow` entry for every non-exited arrow, using the same arrow ID;
- one visible entry each for Hint, Restart, and Next Level;
- unique `Kind + Id` pairs and non-empty `VisualState` values;
- finite bottom-left-origin Unity screen rectangles, at least `2 x 2` pixels, intersecting
  the `1280 x 720` viewport;
- `Interactable = true` only when a complete normal click may currently reach the target.

During `Playing`, active non-moving arrows remain interactable even when blocked or locked,
because those clicks are player attempts. Moving arrows are not interactable; exited arrows
have no arrow entry; arrow targets after win/loss are not interactable. Registry entries
must correspond to real visible Renderer/Collider2D or runtime uGUI targets.

## Runtime checks

The public smokes and fresh local logs are available after meaningful changes to expose
compiler, import, serialization, font, camera, collider, raycast, UI, or first-frame
exceptions. They do not replace the numbered GDD outcomes. A delivered distinct-process
reopen must start a clean tutorial session as specified by the GDD.
