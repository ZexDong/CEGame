[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputRoot,
    [Parameter(Mandatory)][string]$BenchmarkToolsRoot,
    [Parameter(Mandatory)][string]$RunRoot,
    [string]$EngineRoot
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$packageRoot = (Resolve-Path -LiteralPath $InputRoot).Path
$run = [IO.Path]::GetFullPath($RunRoot)
if ($run.StartsWith($packageRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must be outside the input.' }
if (Test-Path -LiteralPath $run) { throw 'RunRoot must be new.' }
New-Item -ItemType Directory -Path $run,(Join-Path $run 'captures'),(Join-Path $run 'receipts') | Out-Null
$resolveArgs = @{}
if ($EngineRoot) { $resolveArgs.EngineRoot = $EngineRoot }
$engineInfo = & (Join-Path $packageRoot 'tools/Resolve-Unreal57.ps1') @resolveArgs | ConvertFrom-Json
$engine = $engineInfo.engine_root
$env:UE_5_7_ROOT = $engine
function Receipt([string]$Name, $Value) {
    $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $run "receipts/$Name.json") -Encoding utf8
}
& (Join-Path $packageRoot 'tools/Test-PublicInput.ps1') -InputRoot $packageRoot -VerifySnapshot | Set-Content (Join-Path $run 'static-check.json')
$project = Join-Path $packageRoot 'starter-project/ChompStarter.uproject'
& (Join-Path $engine 'Engine/Build/BatchFiles/Build.bat') ChompStarterEditor Win64 Development "-Project=$project" -WaitMutex -NoHotReloadFromIDE *> (Join-Path $run 'build.log')
if ($LASTEXITCODE -ne 0) { throw 'Blank starter build failed; see build.log.' }
Import-Module (Join-Path $BenchmarkToolsRoot 'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1') -Force
Add-Type -AssemblyName System.Drawing
$statePath = Join-Path $run 'game-state.json'
function Read-ReadyState([int]$ExpectedPid) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        if (Test-Path -LiteralPath $statePath) {
            try {
                $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -Depth 50
                if ($state.process_id -eq $ExpectedPid -and $state.first_frame -and $state.bridge_ready) {
                    & (Join-Path $packageRoot 'tools/Test-Observation.ps1') -Path $statePath | Out-Null
                    if ($state.provider_ready -or $null -ne $state.game_state) { throw 'Untouched starter contains gameplay observations.' }
                    return $state
                }
            } catch { if ($_.Exception.Message -like '*contains gameplay*') { throw } }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'No fresh first-frame starter observation.'
}
function Capture-Visible($Session, [string]$Name) {
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    $attempt=0
    do {
        $attempt++
        $path=Join-Path $run "captures/$Name-$attempt.png"
        $result=Save-UnrealClientCapture -Session $Session -OutputPath $path -ArtifactId "$Name-$attempt"
        Receipt "$Name-$attempt" $result
        if ($result.status -eq 'ok') {
            $bitmap=[Drawing.Bitmap]::new($path)
            try {
                $maximum=0; $minimum=255
                for ($y=1;$y -lt 30;$y++) {
                    for ($x=1;$x -lt 50;$x++) {
                        $pixel=$bitmap.GetPixel([int]($bitmap.Width*$x/50),[int]($bitmap.Height*$y/30))
                        $luma=($pixel.R+$pixel.G+$pixel.B)/3
                        $maximum=[Math]::Max($maximum,$luma);$minimum=[Math]::Min($minimum,$luma)
                    }
                }
                if ($maximum -gt 80 -and ($maximum-$minimum) -gt 40 -and $bitmap.Width -eq 1280 -and $bitmap.Height -eq 720) { return $path }
            } finally { $bitmap.Dispose() }
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'No rendered non-black 1280x720 client frame.'
}
$session=$null
$resultSummary=[ordered]@{schema_version='1.0.0';status='failed';gameplay_requirements_evaluated=$false;checks=[ordered]@{}}
try {
    $start=Start-UnrealEvaluationSession -ProjectPath $project -RunRoot $run -StatePath (Join-Path $run 'unused-engine-fixture.json') -EngineRoot $engine -ObserverDisabledControl -WindowWidth 1280 -WindowHeight 720 -TimeoutMs 180000 -AdditionalArguments @("-ChompStatePath=$statePath",'-NoSplash','-NoP4','-NoLiveCoding','-ForceRes','-culture=en')
    Receipt 'start' $start
    if ($start.status -ne 'ok') { throw "Start failed: $($start.fault.code)" }
    $session=$start.result.session
    $resultSummary.checks.window_dpi=$start.result.window_dpi
    $first=Read-ReadyState $start.result.process_id
    Receipt 'initial-state' $first
    $resultSummary.checks.initial_capture=Split-Path (Capture-Visible $session 'initial') -Leaf
    $resultSummary.checks.stable_capture=Split-Path (Capture-Visible $session 'stable') -Leaf
    $reopen=Reopen-UnrealEvaluationSession -Session $session -GraceTimeoutMs 15000 -StartTimeoutMs 180000
    Receipt 'reopen' $reopen
    if ($reopen.status -ne 'ok') { throw "Reopen failed: $($reopen.fault.code)" }
    $session=$reopen.result.session
    $second=Read-ReadyState $reopen.result.process_id
    Receipt 'reopened-state' $second
    if ($first.process_id -eq $second.process_id -or $first.process_token -eq $second.process_token) { throw 'Reopen did not create a new process identity.' }
    $resultSummary.checks.reopened_capture=Split-Path (Capture-Visible $session 'reopened') -Leaf
    $stop=Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 15000
    Receipt 'stop' $stop
    if ($stop.status -ne 'ok') { throw "Stop failed: $($stop.fault.code)" }
    $session=$null
    $resultSummary.status='passed'
    $resultSummary.checks.build='passed'
    $resultSummary.checks.observation_schema='passed'
    $resultSummary.checks.unavailable_gameplay='passed'
    $resultSummary.checks.new_process_reopen='passed'
    $resultSummary.checks.cleanup='passed'
} catch {
    $resultSummary.error=$_.Exception.Message
    throw
} finally {
    if ($session) { Receipt 'finally-stop' (Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 15000) }
    $resultSummary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $run 'public-smoke-result.json') -Encoding utf8
}
$resultSummary | ConvertTo-Json -Depth 20
