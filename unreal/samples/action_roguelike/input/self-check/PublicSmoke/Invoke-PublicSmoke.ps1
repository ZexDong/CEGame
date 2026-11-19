[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputRoot,
    [string]$EngineRoot,
    [Parameter(Mandatory)][string]$BenchmarkToolsRoot,
    [Parameter(Mandatory)][string]$RunRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing.Common

$input = (Resolve-Path -LiteralPath $InputRoot).Path
if ([string]::IsNullOrWhiteSpace($EngineRoot)) {
    $resolver = Join-Path $input 'tools/Resolve-Unreal56.ps1'
    $resolved = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $resolver | ConvertFrom-Json
    $EngineRoot = [string]$resolved.engine_root
}

function Save-JsonArtifact {
    param([Parameter(Mandatory)][object]$Value, [Parameter(Mandatory)][string]$Path)
    $json = $Value | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, ($json.Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}

function Add-Check {
    param([string]$Id, [ValidateSet('passed','failed','blocked')][string]$Status, [string]$Detail, [string[]]$Evidence = @())
    [void]$script:Checks.Add([ordered]@{ id = $Id; status = $Status; detail = $Detail; evidence = @($Evidence) })
}

function Add-Fault {
    param([ValidateSet('release','starter-project','executor','environment','cleanup')][string]$Domain, [string]$Code)
    $normalized = $Code.ToLowerInvariant() -replace '[^a-z0-9_]', '_'
    if ($normalized -notmatch '^[a-z]') { $normalized = "fault_$normalized" }
    [void]$script:Faults.Add([ordered]@{ domain = $Domain; code = $normalized })
}

function Test-Property {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-OperationFaultCode {
    param([AllowNull()][object]$Operation)
    if ($null -ne $Operation -and $null -ne $Operation.fault -and (Test-Property $Operation.fault 'code')) {
        return [string]$Operation.fault.code
    }
    return 'operation_failed_without_code'
}

function Resolve-PublicToolPath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$RelativePath)
    if ([IO.Path]::IsPathRooted($RelativePath) -or ($RelativePath -split '/') -contains '..' -or $RelativePath -ne $RelativePath.Replace('\', '/')) {
        throw "invalid_public_tool_path_$RelativePath"
    }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "public_tool_unavailable_$RelativePath"
    }
    return $full
}

function Test-NonBlackCapture {
    param([Parameter(Mandatory)][string]$Path)
    $bitmap = [Drawing.Bitmap]::new($Path)
    try {
        $stepX = [Math]::Max(1, [int][Math]::Floor($bitmap.Width / 32))
        $stepY = [Math]::Max(1, [int][Math]::Floor($bitmap.Height / 18))
        $brightSamples = 0
        $minimumLuma = 255.0
        $maximumLuma = 0.0
        for ($y = [int][Math]::Floor($stepY / 2); $y -lt $bitmap.Height; $y += $stepY) {
            for ($x = [int][Math]::Floor($stepX / 2); $x -lt $bitmap.Width; $x += $stepX) {
                $pixel = $bitmap.GetPixel($x, $y)
                $luma = (0.2126 * $pixel.R) + (0.7152 * $pixel.G) + (0.0722 * $pixel.B)
                if ($luma -gt 12.0) { $brightSamples++ }
                $minimumLuma = [Math]::Min($minimumLuma, $luma)
                $maximumLuma = [Math]::Max($maximumLuma, $luma)
            }
        }
        return $brightSamples -ge 3 -and ($maximumLuma - $minimumLuma) -ge 8.0
    }
    finally { $bitmap.Dispose() }
}

function Wait-HealthyClientCapture {
    param(
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$Prefix,
        [int]$TimeoutMs = 30000
    )
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $attempt = 0
    $lastCapture = $null
    $lastReceipt = $null
    while ($timer.ElapsedMilliseconds -lt $TimeoutMs) {
        $attempt++
        $suffix = $attempt.ToString('00')
        $captureRelative = "captures/$Prefix-$suffix.png"
        $receiptRelative = "receipts/capture-$Prefix-$suffix.json"
        $capture = Save-UnrealClientCapture -Session $Session -OutputPath (Join-Path $RunRoot $captureRelative) -ArtifactId "public-smoke-$Prefix-$suffix"
        Save-JsonArtifact $capture (Join-Path $RunRoot $receiptRelative)
        $lastCapture = $capture
        $lastReceipt = $receiptRelative
        $capturePath = Join-Path $RunRoot $captureRelative
        if ($capture.status -eq 'ok' -and [int]$capture.result.width -ge 320 -and [int]$capture.result.height -ge 240 -and (Test-NonBlackCapture -Path $capturePath)) {
            return [pscustomobject]@{ accepted = $true; capture = $capture; receipt = $receiptRelative; image = $captureRelative }
        }
        Start-Sleep -Milliseconds 1000
    }
    return [pscustomobject]@{ accepted = $false; capture = $lastCapture; receipt = $lastReceipt; image = $null }
}

$started = [DateTime]::UtcNow
$inputFull = [IO.Path]::GetFullPath($InputRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$engineFull = [IO.Path]::GetFullPath($EngineRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$toolsFull = [IO.Path]::GetFullPath($BenchmarkToolsRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$runFull = [IO.Path]::GetFullPath($RunRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$checks = [Collections.Generic.List[object]]::new()
$faults = [Collections.Generic.List[object]]::new()
$status = 'blocked'
$exitCode = 2
$session = $null
$sessionActive = $false
$cleanup = [ordered]@{ attempted = $false; status = 'not_acquired'; process_tree_clean = $null; controlled_input_released = $null }
$resultPath = Join-Path $runFull 'public-smoke-result.json'

try {
    if (-not (Test-Path -LiteralPath $inputFull -PathType Container) -or -not (Test-Path -LiteralPath $engineFull -PathType Container) -or -not (Test-Path -LiteralPath $toolsFull -PathType Container)) {
        throw 'invalid_root_parameter'
    }
    $inputPrefix = $inputFull + [IO.Path]::DirectorySeparatorChar
    if ($runFull.StartsWith($inputPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'run_root_inside_input' }
    if (Test-Path -LiteralPath $runFull) {
        if (@(Get-ChildItem -LiteralPath $runFull -Force).Count -gt 0) { throw 'run_root_not_empty' }
    } else { [void](New-Item -ItemType Directory -Path $runFull) }
    foreach ($dir in @('logs','receipts','state','captures')) { [void](New-Item -ItemType Directory -Path (Join-Path $runFull $dir)) }

    $staticOutput = & pwsh -NoProfile -File (Join-Path $inputFull 'tools/Test-PublicInput.ps1') -InputRoot $inputFull 2>&1
    $staticExit = $LASTEXITCODE
    [IO.File]::WriteAllLines((Join-Path $runFull 'logs/package-validation.txt'), [string[]]@($staticOutput), [Text.UTF8Encoding]::new($false))
    if ($staticExit -ne 0) { Add-Check 'package_identity' 'failed' 'The public package consistency gate failed.' @('logs/package-validation.txt'); Add-Fault 'release' 'package_identity_failed'; throw 'release_assertion_failed' }
    Add-Check 'package_identity' 'passed' 'The public package consistency gate passed.' @('logs/package-validation.txt')

    $benchmark = Get-Content -LiteralPath (Join-Path $inputFull 'BENCHMARK_MANIFEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    $resolvedTools = @{}
    foreach ($identityProperty in $benchmark.tooling.identities.PSObject.Properties) {
        $identity = $identityProperty.Value
        $identityPath = Resolve-PublicToolPath -Root $toolsFull -RelativePath ([string]$identity.path)
        $identityHash = (Get-FileHash -LiteralPath $identityPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($identityHash -cne [string]$identity.sha256) { throw "public_tool_hash_mismatch_$($identityProperty.Name)" }
        $resolvedTools[$identityProperty.Name] = $identityPath
    }
    Add-Check 'tool_identity' 'passed' 'All declared public benchmark tool identities matched their SHA-256 values.' @('logs/package-validation.txt')
    [void](Get-Content -LiteralPath (Join-Path $inputFull 'contracts/actionroguelike-probe-snapshot.schema.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100)
    [void](Get-Content -LiteralPath (Join-Path $inputFull 'contracts/actionroguelike-probe-events.schema.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100)
    Add-Check 'contract_schema' 'passed' 'The public read-only snapshot and event schemas parsed successfully.'
    $projectCopyRoot = Join-Path $runFull 'project-copy'
    Copy-Item -LiteralPath (Join-Path $inputFull 'starter-project') -Destination $projectCopyRoot -Recurse
    $projectPath = Join-Path $projectCopyRoot 'ArenaSlice.uproject'
    if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) { Add-Fault 'release' 'project_copy_failed'; throw 'release_assertion_failed' }
    $gameUserSettings = @'
[/Script/Engine.GameUserSettings]
bUseDesktopResolutionForFullscreen=False
bUseDynamicResolution=False
ResolutionSizeX=1280
ResolutionSizeY=720
LastUserConfirmedResolutionSizeX=1280
LastUserConfirmedResolutionSizeY=720
WindowPosX=100
WindowPosY=100
FullscreenMode=2
LastConfirmedFullscreenMode=2
PreferredFullscreenMode=2
Version=5
'@
    [IO.File]::WriteAllText((Join-Path $projectCopyRoot 'Config/DefaultGameUserSettings.ini'), ($gameUserSettings.Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    foreach ($settingsPlatform in @('WindowsEditor','Windows','WindowsNoEditor')) {
        $settingsDirectory = Join-Path $projectCopyRoot "Saved/Config/$settingsPlatform"
        [void](New-Item -ItemType Directory -Path $settingsDirectory -Force)
        [IO.File]::WriteAllText((Join-Path $settingsDirectory 'GameUserSettings.ini'), ($gameUserSettings.Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    }
    Add-Check 'project_copy' 'passed' 'A disposable exact project copy was created inside the external run root.'
    $dataValidation = Join-Path $engineFull 'Engine/Binaries/Win64/UnrealEditor-Cmd.exe'
    if (-not (Test-Path -LiteralPath $dataValidation -PathType Leaf)) { Add-Fault 'environment' 'data_validation_entry_unavailable'; throw 'environment_blocked' }
    $validationLog = Join-Path $runFull 'logs/data-validation.txt'
    $validationOutput = & $dataValidation $projectPath '-run=DataValidation' '-ProjectOnly' '-unattended' '-nop4' '-nosplash' '-stdout' '-FullStdOutLogOutput' 2>&1
    $validationExit = $LASTEXITCODE
    [IO.File]::WriteAllLines($validationLog, [string[]]@($validationOutput), [Text.UTF8Encoding]::new($false))
    if ($validationExit -ne 0) { Add-Check 'data_validation' 'failed' 'Unreal Data Validation returned a nonzero exit code.' @('logs/data-validation.txt'); Add-Fault 'starter-project' 'data_validation_failed'; throw 'project_assertion_failed' }
    Add-Check 'data_validation' 'passed' 'Unreal Data Validation returned exit code zero.' @('logs/data-validation.txt')

    Import-Module $resolvedTools.executor_module -Force
    Import-Module $resolvedTools.observer_module -Force
    $engineStatePath = Join-Path $runFull 'state/engine-health.json'
    $start = Start-UnrealEvaluationSession -ProjectPath $projectPath -RunRoot $runFull -StatePath $engineStatePath `
        -EngineRoot $engineFull -WindowWidth 1280 -WindowHeight 720 -TimeoutMs 60000 -FocusTimeoutMs 1500 `
        -ObserverDisabledControl -AdditionalArguments @('-WINDOWED','-ResX=1280','-ResY=720','-ForceRes','-ExecCmds=r.SetRes 1280x720w')
    Save-JsonArtifact $start (Join-Path $runFull 'receipts/start.json')
    if ($start.status -ne 'ok') { Add-Check 'initial_start' 'blocked' 'The public executor could not establish a healthy initial session.' @('receipts/start.json'); Add-Fault $(if ($start.environment_fault) {'environment'} else {'executor'}) (Get-OperationFaultCode $start); throw 'environment_blocked' }
    $session = $start.result.session
    $sessionActive = $true
    Add-Check 'initial_start' 'passed' 'The public executor established a bound independent game session.' @('receipts/start.json')

    $initialProbe = Wait-HealthyClientCapture -Session $session -RunRoot $runFull -Prefix 'initial'
    $initialCapture = $initialProbe.capture
    if ($null -eq $initialCapture -or $initialCapture.status -ne 'ok') { Add-Check 'initial_capture' 'blocked' 'The initial client capture was unavailable.' @($initialProbe.receipt); Add-Fault 'environment' (Get-OperationFaultCode $initialCapture); throw 'environment_blocked' }
    if (-not $initialProbe.accepted) { Add-Check 'initial_capture' 'blocked' 'No non-black client frame appeared within the bounded startup window.' @($initialProbe.receipt); Add-Fault 'environment' 'stable_client_frame_timeout'; throw 'environment_blocked' }
    Add-Check 'initial_capture' 'passed' 'A non-black client-only frame was captured; the receipt records its actual client size.' @($initialProbe.image,$initialProbe.receipt)

    $oldProcessId = [int]$start.result.process_id
    $oldProcessToken = [string]$start.result.process_token
    $reopen = Reopen-UnrealEvaluationSession -Session $session -GraceTimeoutMs 10000 -StartTimeoutMs 60000
    Save-JsonArtifact $reopen (Join-Path $runFull 'receipts/reopen.json')
    if ($reopen.status -ne 'ok') {
        if (Test-Property $reopen.result 'session') { $session = $reopen.result.session }
        Add-Check 'reopen_identity' 'blocked' 'Reopen did not establish a healthy new process.' @('receipts/reopen.json')
        Add-Fault $(if ($reopen.environment_fault) {'environment'} else {'executor'}) (Get-OperationFaultCode $reopen)
        throw 'environment_blocked'
    }
    $session = $reopen.result.session
    $newProcessId = [int]$reopen.result.process_id
    $newProcessToken = [string]$reopen.result.process_token
    if ($newProcessId -eq $oldProcessId -or $newProcessToken -ceq $oldProcessToken) { Add-Fault 'executor' 'reopen_identity_not_renewed'; throw 'environment_blocked' }
    Add-Check 'reopen_identity' 'passed' 'Reopen closed the old process and renewed the process ID and token.' @('receipts/reopen.json')

    $reopenProbe = Wait-HealthyClientCapture -Session $session -RunRoot $runFull -Prefix 'reopen'
    $reopenCapture = $reopenProbe.capture
    if ($null -eq $reopenCapture -or $reopenCapture.status -ne 'ok') { Add-Check 'reopen_capture' 'blocked' 'The reopened client capture was unavailable.' @($reopenProbe.receipt); Add-Fault 'environment' (Get-OperationFaultCode $reopenCapture); throw 'environment_blocked' }
    if (-not $reopenProbe.accepted) { Add-Check 'reopen_capture' 'blocked' 'No non-black client frame appeared within the bounded Reopen window.' @($reopenProbe.receipt); Add-Fault 'environment' 'stable_reopen_frame_timeout'; throw 'environment_blocked' }
    Add-Check 'reopen_capture' 'passed' 'A non-black client-only frame was captured from the reopened process; the receipt records its actual client size.' @($reopenProbe.image,$reopenProbe.receipt)

    $cleanup.attempted = $true
    $stop = Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 10000
    Save-JsonArtifact $stop (Join-Path $runFull 'receipts/stop.json')
    $sessionActive = $false
    $cleanupHealthy = $stop.status -eq 'ok' -and $stop.result.process_exited -eq $true -and [int]$stop.result.job_active_process_count_after_wait -eq 0 -and $stop.result.input_lease_released -eq $true -and $stop.result.input_cleanup.all_released -eq $true
    $cleanup.status = if ($cleanupHealthy) {'verified'} else {'failed'}
    $cleanup.process_tree_clean = [bool]($stop.result.process_exited -eq $true -and [int]$stop.result.job_active_process_count_after_wait -eq 0)
    $cleanup.controlled_input_released = [bool]($stop.result.input_lease_released -eq $true -and $stop.result.input_cleanup.all_released -eq $true)
    if (-not $cleanupHealthy) { Add-Check 'final_cleanup' 'blocked' 'Final process-tree or input cleanup was not verified.' @('receipts/stop.json'); Add-Fault 'cleanup' (Get-OperationFaultCode $stop); throw 'environment_blocked' }
    Add-Check 'final_cleanup' 'passed' 'Final process-tree and controlled-input cleanup were verified.' @('receipts/stop.json')
    $status = 'passed'; $exitCode = 0
}
catch {
    if ($_.Exception.Message -eq 'release_assertion_failed') { $status = 'failed'; $exitCode = 1 }
    elseif ($_.Exception.Message -eq 'project_assertion_failed') { $status = 'failed'; $exitCode = 1 }
    else { $status = 'blocked'; $exitCode = 2; if (@($faults).Count -eq 0) { Add-Fault 'environment' $_.Exception.Message } }
}
finally {
    if ($sessionActive -and $null -ne $session) {
        $cleanup.attempted = $true
        try {
            $emergencyStop = Stop-UnrealEvaluationSession -Session $session -GraceTimeoutMs 10000
            Save-JsonArtifact $emergencyStop (Join-Path $runFull 'receipts/emergency-stop.json')
            $emergencyHealthy = $emergencyStop.status -eq 'ok' -and $emergencyStop.result.process_exited -eq $true -and [int]$emergencyStop.result.job_active_process_count_after_wait -eq 0 -and $emergencyStop.result.input_lease_released -eq $true -and $emergencyStop.result.input_cleanup.all_released -eq $true
            $cleanup.status = if ($emergencyHealthy) {'verified'} else {'failed'}
            $cleanup.process_tree_clean = [bool]($emergencyStop.result.process_exited -eq $true -and [int]$emergencyStop.result.job_active_process_count_after_wait -eq 0)
            $cleanup.controlled_input_released = [bool]($emergencyStop.result.input_lease_released -eq $true -and $emergencyStop.result.input_cleanup.all_released -eq $true)
            if (-not $emergencyHealthy) { Add-Fault 'cleanup' 'emergency_cleanup_failed'; $status = 'blocked'; $exitCode = 2 }
        } catch { $cleanup.status = 'failed'; $cleanup.process_tree_clean = $false; $cleanup.controlled_input_released = $false; Add-Fault 'cleanup' 'emergency_cleanup_exception'; $status = 'blocked'; $exitCode = 2 }
    }
}

$benchmarkHash = (Get-FileHash -LiteralPath (Join-Path $inputFull 'BENCHMARK_MANIFEST.json') -Algorithm SHA256).Hash.ToLowerInvariant()

$result = [ordered]@{
    schema_version = '1.0.0'
    smoke_id = 'public-smoke-{0}-{1}' -f $started.ToString('yyyyMMddTHHmmssfffZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    started_utc = $started.ToString('o')
    ended_utc = [DateTime]::UtcNow.ToString('o')
    status = $status
    exit_code = $exitCode
    gameplay_requirements_evaluated = $false
    project = [ordered]@{ project_file = 'starter-project/ArenaSlice.uproject'; validation_entry = 'UnrealEditor-Cmd DataValidation' }
    engine = [ordered]@{ name = 'Unreal Engine'; version = '5.6.1'; changelist = 44394996; platform = 'Windows x64'; mode = 'editor_game' }
    input_identity = [ordered]@{ benchmark_manifest_sha256 = $benchmarkHash }
    checks = @($checks)
    faults = @($faults)
    cleanup = $cleanup
}
Save-JsonArtifact -Value $result -Path $resultPath
Write-Output ("PUBLIC_SMOKE_{0} result=public-smoke-result.json" -f $status.ToUpperInvariant())
exit $exitCode
