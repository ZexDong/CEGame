# Brick'n'Balls Challenge Input

Public Input revision: `v1.4-tool-guide-v5-20260825`  
GDD revision: `v1.1-player-goals-only-20260825`  
Common Unity tool guide: `unity-common-tool-guide-v5-20260825`

This is the public starting workspace. Work in the current isolated project copy and do not create a nested Unity project.

## Required reading

1. `INITIAL_AGENT_PROMPT.md`
2. `GDD.md`
3. `TOOLCHAIN.md`
4. `UNITY_BENCHMARK_TOOL_GUIDE.md`
5. `ASSET_MANIFEST.json`

## Entry Scene

`Assets/Scenes/BrickChallenge.unity`

The Scene contains only the starting camera. Supplied media is under `Assets/TaskAssets`. The target gameplay is intentionally absent.

## Cold compile and timestamped evidence

```powershell
$Cli = $env:UNITY_CLI
$Editor = $env:UNITY_EDITOR
$Project = '<repository-local-project-copy>'
$Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$Evidence = "$Project\Logs\PublicSmoke\$Stamp"
New-Item -ItemType Directory -Force -Path $Evidence,"$Evidence\HostTemp" | Out-Null
$env:TEMP = "$Evidence\HostTemp"
$env:TMP = $env:TEMP
& $Cli --json --non-interactive --proxy-disable run $Project `
  --editor-path $Editor --timeout 600 -- -logFile "$Evidence\cold-import.log"
```

Read the newly written log. A zero exit code alone does not prove gameplay correctness.

## Public smoke tests

Close the Editor for this exact project before each command. Run the two modes sequentially, never concurrently.

```powershell
$EditXml = "$Evidence\public-editmode-$Stamp.xml"
$PlayXml = "$Evidence\public-playmode-$Stamp.xml"
$EditLog = "$Evidence\public-editmode-$Stamp.log"
$PlayLog = "$Evidence\public-playmode-$Stamp.log"
& $Cli --json --non-interactive --proxy-disable test $Project --mode EditMode `
  --filter 'OmniGame.Benchmark.BrickChallenge.PublicSmoke.EditMode' `
  --output $EditXml --editor-path $Editor --timeout 600 -- -logFile $EditLog
& $Cli --json --non-interactive --proxy-disable test $Project --mode PlayMode `
  --filter 'OmniGame.Benchmark.BrickChallenge.PublicSmoke.PlayMode' `
  --output $PlayXml --editor-path $Editor --timeout 900 -- -logFile $PlayLog
```

The newly written EditMode XML must report exactly `1/1 Passed`; the PlayMode XML must report exactly `1/1 Passed`. Missing, stale, unreadable, or zero-test XML is not a pass. Public smoke proves only workspace health, not scored gameplay.
