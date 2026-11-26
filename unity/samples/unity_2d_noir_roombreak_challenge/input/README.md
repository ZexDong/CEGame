# Noir Roombreak Challenge Public Project

This directory is the public starting Unity project for
`unity.noir_roombreak_challenge.v1`. Complete the player-facing game described
by `GDD.md` in this project.

Public Input revision: `v1.11-tool-guide-v5-20260825`  
GDD revision: `v1.7-player-goals-only-20260825`  
Public contract revision: `2026.08.24-v1`  
Common Unity tool guide: `unity-common-tool-guide-v5-20260825`

## Read first

Read these public files before editing:

1. `INITIAL_AGENT_PROMPT.md`
2. `GDD.md`
3. `TOOLCHAIN.md`
4. `UNITY_BENCHMARK_TOOL_GUIDE.md`
5. `BENCHMARK_MANIFEST.json`
6. `ASSET_MANIFEST.json`
7. `ASSET_CATALOG.md` and `ASSET_CATALOG.json`
8. `ASSET_CONTACT_SHEET.png`
9. `Packages/com.gamecreate.benchmark.noir-roombreak.contracts/Runtime/README.md`

The current directory is already the writable project copy. Do not create a
nested Unity project or import the canonical source directory in place.

## Required project entry

- Starter Scene: `Assets/NoirStarter/Scenes/NoirStarter.unity`
- Required final Scene: `Assets/NoirChallenge/Scenes/NoirRoombreak.unity`
- Required first enabled Build Settings Scene:
  `Assets/NoirChallenge/Scenes/NoirRoombreak.unity`
- Target Game view: `1280x720`
- Writable implementation root: `Assets/NoirChallenge/**`

The final Scene must contain an active component implementing the public
read-only contract:

`GameCreate.Benchmark.NoirRoombreak.INoirRoombreakProbe`

The Probe reports normally reached live state. It must not move the player,
change gameplay, defeat enemies, force results, reset state, or load Scenes.

## Pinned tools

```text
Unity Editor  $env:UNITY_EDITOR
Unity CLI     $env:UNITY_CLI
Input System  1.19.0
URP           17.0.4
uGUI          2.0.0
Cinemachine   3.1.5
```

Use the installed versions. Do not install, upgrade, or downgrade the Editor or
packages. Use `UnityEngine.InputSystem`, not legacy `UnityEngine.Input`.

## Supplied asset context

The supplied media root is exactly `Assets/TaskAssets/NoirSource/`.
`ASSET_CONTACT_SHEET.png` is the initial visual inventory. The two catalogs give
the exact paths, semantic roles, source dimensions, visible-content bounds,
importer and slice facts, prefab dependencies, and intentionally omitted
upstream script references.

Important source facts:

- the Player, Anda, and Obser silhouettes occupy only a small part of their
  padded 128x128 textures;
- some protected importers expose the full padded texture instead of a tight
  visible region;
- Vulto JPG frames are opaque character references on black, not room
  backgrounds;
- source prefabs with omitted upstream gameplay scripts are media and
  composition references, not complete gameplay objects.

Keep protected sources and importers unchanged. Put project-owned scripts,
derived sprites, materials, animations, prefabs, tests, and the final Scene
under `Assets/NoirChallenge/**`.

## Project-local Unity feedback

Follow `UNITY_BENCHMARK_TOOL_GUIDE.md` for CLI argument placement, project-local
logs, Input System behavior, UI setup, real Play frames, and exact-project PID
handling. Resolve the current project and pinned tools with:

```powershell
$Project = (Get-Location).Path
$Cli = $env:UNITY_CLI
$Editor = $env:UNITY_EDITOR
```

Every Unity command must use a new file under this project's `Logs/**` tree.
For an import and compile check:

```powershell
$Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$CheckDir = "$Project\Logs\ToolChecks\$Stamp-compile"
$HostTemp = "$CheckDir\host-temp"
$EditorLog = "$CheckDir\editor.log"
New-Item -ItemType Directory -Force -Path $CheckDir,$HostTemp | Out-Null
$OldTemp=$env:TEMP; $OldTmp=$env:TMP
try {
  $env:TEMP=$HostTemp; $env:TMP=$HostTemp
  & $Cli --json --non-interactive --proxy-disable run $Project `
    --editor-path $Editor --timeout 600 -- -logFile $EditorLog
  if ($LASTEXITCODE -ne 0) { throw "Unity import/compile failed: $LASTEXITCODE" }
} finally {
  $env:TEMP=$OldTemp; $env:TMP=$OldTmp
}
Get-Content -LiteralPath $EditorLog -Tail 200
```

A zero exit code does not replace reading the new log for compiler errors,
package failures, missing references, and first-frame exceptions.

## Public smoke filters

The exact public filters are:

```text
GameCreate.Benchmark.NoirRoombreak.PublicSmoke.EditMode
GameCreate.Benchmark.NoirRoombreak.PublicSmoke.PlayMode
```

Run them sequentially with new project-local XML and log files:

```powershell
$Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$CheckDir = "$Project\Logs\ToolChecks\$Stamp-tests"
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
    --filter 'GameCreate.Benchmark.NoirRoombreak.PublicSmoke.EditMode' `
    --output $EditXml --editor-path $Editor --timeout 600 -- -logFile $EditLog
  if ($LASTEXITCODE -ne 0) { throw "Public EditMode smoke failed: $LASTEXITCODE" }

  & $Cli --json --non-interactive --proxy-disable test $Project --mode PlayMode `
    --filter 'GameCreate.Benchmark.NoirRoombreak.PublicSmoke.PlayMode' `
    --output $PlayXml --editor-path $Editor --timeout 900 -- -logFile $PlayLog
  if ($LASTEXITCODE -ne 0) { throw "Public PlayMode smoke failed: $LASTEXITCODE" }
} finally {
  $env:TEMP=$OldTemp; $env:TMP=$OldTmp
}
```

Read each new NUnit XML and matching log. The public tests check the declared
public workspace route; they do not prove every player-facing behavior in `GDD.md`.

## Protected boundaries

Writable and protected paths are declared in `BENCHMARK_MANIFEST.json`. Do not
overwrite protected starter media, public smoke tests, package locks, contracts,
manifests, catalogs, contact sheet, or task documents. Work only in this current
project and keep all generated logs and XML under its `Logs/**` path.

