[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputRoot,
    [string]$EngineRoot,
    [Parameter(Mandatory)][string]$BenchmarkToolsRoot,
    [Parameter(Mandatory)][string]$RunRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$input = (Resolve-Path -LiteralPath $InputRoot).Path
$resolver = Join-Path $input 'tools/Resolve-Unreal57.ps1'
if ([string]::IsNullOrWhiteSpace($EngineRoot)) {
    $resolved = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $resolver | ConvertFrom-Json
    $EngineRoot = [string]$resolved.engine_root
}
$engine = (Resolve-Path -LiteralPath $EngineRoot).Path
$toolsRoot = (Resolve-Path -LiteralPath $BenchmarkToolsRoot).Path
$run = [IO.Path]::GetFullPath($RunRoot)
if (Test-Path -LiteralPath $run) {
    if (@(Get-ChildItem -LiteralPath $run -Force).Count -ne 0) { throw 'RunRoot must be empty.' }
} else {
    New-Item -ItemType Directory -Path $run -Force | Out-Null
}
foreach ($name in @('state','task-state','captures','receipts','logs')) {
    New-Item -ItemType Directory -Path (Join-Path $run $name) -Force | Out-Null
}

Add-Type -AssemblyName System.Drawing
function Assert-VisibleCapture([string]$Path) {
    $bitmap = [Drawing.Bitmap]::new($Path)
    try {
        $values = [Collections.Generic.List[double]]::new()
        for ($row = 1; $row -le 8; $row++) {
            for ($column = 1; $column -le 12; $column++) {
                $x = [Math]::Min($bitmap.Width - 2, [Math]::Max(1, [int](($column / 13.0) * $bitmap.Width)))
                $y = [Math]::Min($bitmap.Height - 2, [Math]::Max(1, [int](($row / 9.0) * $bitmap.Height)))
                $pixel = $bitmap.GetPixel($x, $y)
                $values.Add(($pixel.R + $pixel.G + $pixel.B) / 3.0)
            }
        }
        $average = ($values | Measure-Object -Average).Average
        $maximum = ($values | Measure-Object -Maximum).Maximum
        if ($average -lt 8.0 -or $maximum -lt 40.0) { throw 'A public smoke capture is effectively black.' }
    }
    finally {
        $bitmap.Dispose()
    }
}

function Save-StableVisibleCapture([object]$Session, [string]$Name, [int]$TimeoutSeconds = 60) {
    $captures = Join-Path $run 'captures'
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $attempt = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        $attempt++
        $attemptPath = Join-Path $captures ("{0}-attempt-{1}.png" -f $Name, $attempt)
        $capture = Save-UnrealClientCapture -Session $Session -OutputPath $attemptPath -ArtifactId ("{0}-attempt-{1}" -f $Name, $attempt)
        if ($capture.status -eq 'ok') {
            try {
                Assert-VisibleCapture $attemptPath
                $finalPath = Join-Path $captures ("{0}.png" -f $Name)
                Copy-Item -LiteralPath $attemptPath -Destination $finalPath
                return $finalPath
            } catch {
                # The first post-launch frames can be black while UE 5.7 shaders warm.
            }
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Timed out waiting for a stable non-black capture: $Name"
}

& (Join-Path $input 'tools/Test-PublicInput.ps1') -InputRoot $input | Out-Null

$buildVersion = Get-Content -LiteralPath (Join-Path $engine 'Engine/Build/Build.version') -Raw -Encoding UTF8 | ConvertFrom-Json
$version = '{0}.{1}.{2}' -f $buildVersion.MajorVersion,$buildVersion.MinorVersion,$buildVersion.PatchVersion
if ($version -cne '5.7.4' -or [int64]$buildVersion.Changelist -ne 51494982) { throw 'Engine identity mismatch.' }

$project = Join-Path $input 'starter-project/RollBallStarter.uproject'
$buildLog = Join-Path $run 'logs/build.log'
& (Join-Path $engine 'Engine/Build/BatchFiles/Build.bat') `
    RollBallStarterEditor Win64 Development $project -WaitMutex -NoHotReloadFromIDE *> $buildLog
if ($LASTEXITCODE -ne 0) { throw 'The public starter build failed.' }

Import-Module (Join-Path $toolsRoot 'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1') -Force

$engineState = Join-Path $run 'state/engine-health.json'
$gameState = Join-Path $run 'task-state/game-state.json'
$session = $null
$reopened = $null
$checks = [ordered]@{}
try {
    $start = Start-UnrealEvaluationSession `
        -ProjectPath $project -RunRoot $run -StatePath $engineState `
        -EngineRoot $engine -WindowWidth 1280 -WindowHeight 720 `
        -TimeoutMs 180000 -ObserverDisabledControl `
        -AdditionalArguments @("-RollBallStatePath=$gameState", '-NoSplash', '-NoSound')
    if ($start.status -ne 'ok') { throw "Starter Start failed: $($start.fault.code)" }
    $session = $start.result.session
    $checks.start = 'passed'

    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    $first = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $gameState -PathType Leaf) {
            try {
                $candidate = Get-Content -LiteralPath $gameState -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 32
                if ($candidate.bridge_ready -eq $true -and $candidate.first_frame -eq $true) { $first = $candidate; break }
            } catch {}
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $first) { throw 'The starter bridge did not publish a first-frame snapshot.' }
    if ($first.provider_ready -ne $false -or $null -ne $first.game_state) { throw 'The starter bridge contains gameplay state.' }
    if ([string]$first.layout_id -cne 'rollball-fixed-maze-10x10-v2') { throw 'The starter bridge layout identity is invalid.' }
    $firstProcessId = [int]$first.process_id
    $checks.answer_free_bridge = 'passed'

    [void](Save-StableVisibleCapture -Session $session -Name 'starter-initial')
    [void](Save-StableVisibleCapture -Session $session -Name 'starter-stable')
    $checks.initial_capture = 'passed'

    $reopen = Reopen-UnrealEvaluationSession -Session $session -GraceTimeoutMs 15000 -StartTimeoutMs 180000
    if ($reopen.status -ne 'ok') { throw "Reopen failed: $($reopen.fault.code)" }
    $session = $null
    $reopened = $reopen.result.session

    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    $second = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $gameState -PathType Leaf) {
            try {
                $candidate = Get-Content -LiteralPath $gameState -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 32
                if ($candidate.bridge_ready -eq $true -and $candidate.first_frame -eq $true -and [int]$candidate.process_id -ne $firstProcessId) { $second = $candidate; break }
            } catch {}
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $second) { throw 'The reopened starter did not publish a new-process snapshot.' }
    if ($second.provider_ready -ne $false -or $null -ne $second.game_state) { throw 'The reopened starter bridge contains gameplay state.' }
    $checks.reopen = 'passed'

    [void](Save-StableVisibleCapture -Session $reopened -Name 'starter-reopen')
    $checks.reopen_capture = 'passed'

    $stop = Stop-UnrealEvaluationSession -Session $reopened -GraceTimeoutMs 15000
    if ($stop.status -ne 'ok') { throw "Final Stop failed: $($stop.fault.code)" }
    $reopened = $null
    $checks.cleanup = 'passed'

    $result = [ordered]@{
        schema_version = '1.0.0'
        status = 'passed'
        gameplay_requirements_evaluated = $false
        engine = @{ version = '5.7.4'; changelist = 51494982 }
        layout_id = 'rollball-fixed-maze-10x10-v2'
        checks = $checks
    }
    $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $run 'public-smoke-result.json') -Encoding utf8
    $result | ConvertTo-Json -Depth 16
}
finally {
    if ($reopened) { Stop-UnrealEvaluationSession -Session $reopened -GraceTimeoutMs 15000 | Out-Null }
    if ($session) { Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 15000 | Out-Null }
}
