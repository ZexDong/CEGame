[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputRoot,
    [Parameter(Mandatory)][string]$RunRoot,
    [string]$EngineRoot
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$inputRootPath = (Resolve-Path -LiteralPath $InputRoot).Path
$run = [IO.Path]::GetFullPath($RunRoot)
if ($run.StartsWith($inputRootPath.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $run -eq $inputRootPath) {
    throw 'RunRoot must be outside InputRoot.'
}
if ((Test-Path -LiteralPath $run) -and @(Get-ChildItem -LiteralPath $run -Force).Count) { throw 'RunRoot must be empty.' }
New-Item -ItemType Directory -Path $run -Force | Out-Null
$checks = [ordered]@{}
$failure = $null
$session = $null
function Save-Receipt([string]$Name, $Value) {
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $run "$Name.json") -Encoding utf8
}
function Copy-ProjectTree([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Project links are not supported by public smoke.' }
        if ($item.PSIsContainer) {
            if ($item.Name -notin @('Binaries','Intermediate','Saved','DerivedDataCache','.vs','.git')) {
                Copy-ProjectTree $item.FullName (Join-Path $Destination $item.Name)
            }
        } else { Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Destination $item.Name) }
    }
}
function Wait-Observation([string]$StateFile, [int]$ExpectedProcessId = 0,
    [string]$ExpectedSessionId = '', [long]$AfterSnapshotId = 0, [int]$TimeoutMs = 30000) {
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        if (Test-Path -LiteralPath $StateFile) {
            try {
                $state = Get-Content -LiteralPath $StateFile -Raw -Encoding utf8 | ConvertFrom-Json
                $age = ([DateTime]::UtcNow - (Get-Item -LiteralPath $StateFile).LastWriteTimeUtc).TotalSeconds
                if ($null -ne $state.snapshot_id -and $state.snapshot_id -gt $AfterSnapshotId -and $state.phase -and
                    $age -ge -1 -and $age -le 1 -and
                    ($ExpectedProcessId -eq 0 -or $state.process_id -eq $ExpectedProcessId) -and
                    (-not $ExpectedSessionId -or $state.session_id -eq $ExpectedSessionId)) { return $state }
            } catch {}
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'No settled runtime observation snapshot.'
}
function Capture-Visible([object]$ActiveSession, [string]$Name) {
    Add-Type -AssemblyName System.Drawing
    $deadline = [DateTime]::UtcNow.AddSeconds(40)
    $captureAttempt = 0
    do {
        $captureFile = Join-Path $run "$Name-probe-$captureAttempt.png"
        $captureAttempt++
        $receipt = Save-UnrealClientCapture -Session $ActiveSession -OutputPath $captureFile -ArtifactId $Name
        if ($receipt.status -eq 'ok') {
            $bitmap = [Drawing.Bitmap]::new($captureFile)
            try {
                $sum = 0.0; $bright = 0; $count = 0
                for ($y = 4; $y -lt $bitmap.Height; $y += 8) {
                    for ($x = 4; $x -lt $bitmap.Width; $x += 8) {
                        $pixel = $bitmap.GetPixel($x,$y)
                        $level = ($pixel.R + $pixel.G + $pixel.B) / 3.0
                        $sum += $level; $count++
                        if ($level -gt 70) { $bright++ }
                    }
                }
                if ((($bitmap.Width -eq 1280 -and $bitmap.Height -eq 720) -or ($bitmap.Width -eq 1920 -and $bitmap.Height -eq 1080)) -and $sum/$count -gt 8 -and $bright -gt 20) {
                    Copy-Item -LiteralPath $captureFile -Destination (Join-Path $run "$Name.png")
                    Save-Receipt $Name $receipt
                    return
                }
            } finally { $bitmap.Dispose() }
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "No valid non-black client frame: $Name"
}
try {
    & (Join-Path $inputRootPath 'tools/Test-PublicInput.ps1') -InputRoot $inputRootPath -AllowProjectChanges > (Join-Path $run 'static-gate.json')
    if ($LASTEXITCODE -ne 0) { throw 'Public input static gate failed.' }
    $checks.static_gate = $true
    $resolveArgs = @{}
    if ($EngineRoot) { $resolveArgs.EngineRoot = $EngineRoot }
    $engine = (& (Join-Path $inputRootPath 'tools/Resolve-Unreal57.ps1') @resolveArgs | ConvertFrom-Json).engine_root
    Copy-ProjectTree (Join-Path $inputRootPath 'starter-project') (Join-Path $run 'starter-project')
    $project = Join-Path $run 'starter-project/BoneMaze.uproject'
    & (Join-Path $engine 'Engine/Build/BatchFiles/Build.bat') BoneMazeEditor Win64 Development "-Project=$project" -WaitMutex -NoHotReloadFromIDE *> (Join-Path $run 'build.log')
    if ($LASTEXITCODE -ne 0) { throw 'Clean copied project build failed.' }
    $checks.build = $true
    & (Join-Path $engine 'Engine/Binaries/Win64/UnrealEditor-Cmd.exe') $project -run=pythonscript "-script=$(Join-Path $inputRootPath 'self-check/PublicSmoke/Validate-Assets.py')" -unattended -NoP4 -NoSplash -NullRHI "-abslog=$(Join-Path $run 'asset-validation.log')" *> (Join-Path $run 'asset-validation-console.log')
    if ($LASTEXITCODE -ne 0) { throw 'Editor asset validation failed.' }
    Copy-Item -LiteralPath (Join-Path $run 'starter-project/Saved/Benchmark/asset-validation.json') -Destination (Join-Path $run 'asset-validation.json')
    $checks.assets = $true
    Import-Module (Join-Path $inputRootPath 'tools/engine/executor/UnrealEvaluationExecutor.psm1') -Force
    $dashboard = Join-Path $run 'state.json'
    $start = Start-UnrealEvaluationSession -ProjectPath $project -RunRoot $run -StatePath (Join-Path $run 'engine-health.json') `
        -EngineRoot $engine -WindowWidth 1280 -WindowHeight 720 -TimeoutMs 120000 -ObserverDisabledControl `
        -AdditionalArguments @('-NoSplash','-ForceRes',"-ObservationPath=$dashboard", "-UserDir=$(Join-Path $run 'userdata')")
    Save-Receipt 'start' $start
    if ($start.status -ne 'ok') { throw "Start failed: $($start.fault.code)" }
    $session = $start.result.session
    $oldProcess = $start.result.process_id
    $checks.start = $true
    $first = Wait-Observation $dashboard $oldProcess
    & (Join-Path $engine 'Engine/Binaries/ThirdParty/Python3/Win64/python.exe') (Join-Path $inputRootPath 'tools/check_observation.py') $dashboard --max-age 1 > (Join-Path $run 'dashboard-check.json')
    if ($LASTEXITCODE -ne 0) { throw 'observation self-check failed.' }
    $checks.dashboard = $true
    if ($first.process_id -ne $oldProcess) { throw 'Snapshot process does not match the launched game.' }
    Save-Receipt 'initial-snapshot' $first
    $advancing = Wait-Observation $dashboard $oldProcess $first.session_id $first.snapshot_id
    Save-Receipt 'advancing-snapshot' $advancing
    $checks.observation_progress = $true
    Capture-Visible $session 'initial-frame'
    $checks.visible_frame = $true
    if ($first.phase -eq 'not_ready') {
        $beforePulses = $first.starter_health.input_pulses
        $press = Invoke-UnrealPressKey -Session $session -Key 'Space' -DurationMs 250
        Save-Receipt 'input-receipt' $press
        if ($press.status -ne 'ok') { throw 'Starter input dispatch failed.' }
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        do {
            $after = Wait-Observation $dashboard $oldProcess $first.session_id $first.snapshot_id
            if ($after.starter_health.input_pulses -gt $beforePulses) { break }
            Start-Sleep -Milliseconds 100
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($after.starter_health.input_pulses -ne $beforePulses + 1) { throw 'Starter did not observe exactly one Space edge.' }
        Save-Receipt 'after-input-snapshot' $after
        $checks.starter_input = $true
    }
    # Reopen readiness is bound to the new PID; never delete a live writer's snapshot.
    $reopen = Reopen-UnrealEvaluationSession -Session $session -GraceTimeoutMs 45000 -StartTimeoutMs 120000
    Save-Receipt 'reopen' $reopen
    if ($reopen.status -ne 'ok') { throw "Reopen failed: $($reopen.fault.code)" }
    $session = $reopen.result.session
    if ($reopen.result.process_id -eq $oldProcess) { throw 'Reopen did not create a new process.' }
    $second = Wait-Observation $dashboard $reopen.result.process_id
    if ($second.process_id -ne $reopen.result.process_id) { throw 'Reopened observation is from a different process.' }
    Save-Receipt 'reopened-snapshot' $second
    Capture-Visible $session 'reopened-frame'
    $reopenedAdvancing = Wait-Observation $dashboard $reopen.result.process_id $second.session_id $second.snapshot_id
    Save-Receipt 'reopened-advancing-snapshot' $reopenedAdvancing
    & (Join-Path $engine 'Engine/Binaries/ThirdParty/Python3/Win64/python.exe') (Join-Path $inputRootPath 'tools/check_observation.py') $dashboard --max-age 1 > (Join-Path $run 'reopened-dashboard-check.txt')
    if ($LASTEXITCODE -ne 0 -or $second.session_id -eq $first.session_id) { throw 'Reopened observation is not a fresh conformant trace.' }
    $checks.reopen = $true
    $stop = Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 45000
    Save-Receipt 'stop' $stop
    if ($stop.status -ne 'ok') { throw "Stop failed: $($stop.fault.code)" }
    $session = $null
    $checks.cleanup = $true
} catch {
    $failure = $_.Exception.Message
    Save-Receipt 'failure-detail' @{message=$failure;stack=$_.ScriptStackTrace;category=[string]$_.CategoryInfo}
} finally {
    if ($null -ne $session) {
        $cleanup = Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 45000
        Save-Receipt 'failure-cleanup' $cleanup
    }
}
$result = [ordered]@{status=$(if($failure){'failed'}else{'passed'});checks=$checks;engine='5.7.4-cl51494982';gameplay_verified=$false;error=$failure}
Save-Receipt 'result' $result
$result | ConvertTo-Json -Depth 10
if ($failure) { exit 1 }
exit 0
