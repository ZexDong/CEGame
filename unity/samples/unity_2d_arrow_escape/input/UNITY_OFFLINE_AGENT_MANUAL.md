# Arrow Escape v2 offline command reference

This file contains Arrow-specific paths, public filters, and expected counts. Reusable
Unity 6 and CLI behavior is documented in `UNITY_BENCHMARK_TOOL_GUIDE.md`.

## Fixed values

```powershell
$Project = (Get-Location).Path
$Cli = 'D:\game\engine\shared-tools\unity\cli\1.0.0-beta.3\unity.exe'
$Editor = 'D:\game\engine\unity\6000.0.80f1\Editor\Unity.exe'
$Scene = 'Assets/ArrowEscapeBenchmark/Scenes/ArrowEscape.unity'
```

Work in the current project. Keep new command logs and XML in a stable project-local
folder under `Logs/ToolChecks/`; Unity may recreate `Temp/`.

## Public tests

```powershell
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

Require a new readable EditMode XML with `4/4 Passed` and a new readable PlayMode XML
with `1/1 Passed`. The PlayMode smoke enters real frames but does not execute the full
puzzle.

## Open and normal input

```powershell
& $Cli --json --non-interactive --proxy-disable open $Project --editor-path $Editor
```

Use this only when a controllable Game view exists. A shell-only session must not claim
that it operated the Game view. Player controls must remain connected to the real visible
runtime targets; direct gameplay or result calls are not a player-input implementation.

## Reopen

Stop Play and close only the Editor that owns this exact project. Confirm that PID exits,
then open the same project again. For automation, snapshot matching PIDs before `open`,
match `Win32_Process.CommandLine` against the exact normalized project path, bind exactly
one new PID, and close only that PID. Stop nothing when the match is missing or ambiguous;
never terminate every `Unity.exe` process.

## Arrow-specific checks

- Save `Assets/ArrowEscapeBenchmark/Scenes/ArrowEscape.unity` and Build Settings.
- Use Unity Input System Mouse input, not a legacy-only or IMGUI-only player route.
- Keep visible arrow Renderer geometry and Collider2D aligned.
- Keep Hint, Restart, and Next Level as visible runtime controls.
- Publish one truthful contract `3.0` Probe and a complete visible-target registry.
- For world-space LineRenderer arrows, update stored positions during motion.
- When rebuilding after Restart, account for `Destroy` completing at frame end.
- A fresh process must begin with a clean tutorial session.
