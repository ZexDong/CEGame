[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputRoot,
    [string]$EngineRoot,
    [Parameter(Mandatory)][string]$BenchmarkToolsRoot,
    [Parameter(Mandatory)][string]$RunRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$input = (Resolve-Path -LiteralPath $InputRoot).Path
$resolver = Join-Path $input 'tools/Resolve-Unreal57.ps1'
if ([string]::IsNullOrWhiteSpace($EngineRoot)) {
    $resolved = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $resolver | ConvertFrom-Json
    $EngineRoot = [string]$resolved.engine_root
}

function Add-SmokeCheck {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('passed', 'failed', 'blocked')][string]$Status,
        [Parameter(Mandatory)][string]$Detail,
        [string[]]$Evidence = @()
    )
    $script:Checks.Add([ordered]@{
            id = $Id
            status = $Status
            detail = $Detail
            evidence = @($Evidence)
        })
}

function Add-SmokeFault {
    param(
        [Parameter(Mandatory)][ValidateSet('release', 'starter-project', 'executor', 'environment', 'cleanup')][string]$Domain,
        [Parameter(Mandatory)][string]$Code
    )
    $normalized = $Code.ToLowerInvariant() -replace '[^a-z0-9_]', '_'
    if ($normalized -notmatch '^[a-z]') {
        $normalized = 'fault_' + $normalized
    }
    $script:Faults.Add([ordered]@{ domain = $Domain; code = $normalized })
}

function Save-JsonArtifact {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$Path
    )
    $json = $Value | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, ($json.Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}

function ConvertTo-PublicSmokeSanitizedText {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)

    $knownRoots = @(
        @($script:InputFull, '<input>'),
        @($script:EngineFull, '<engine-root>'),
        @($script:ToolsFull, '<benchmark-tools-root>'),
        @($script:RunFull, '<run-root>')
    )
    $hostUser = [Environment]::UserName
    $hostDevice = [Environment]::MachineName
    return @($Lines | ForEach-Object {
            $value = [string]$_
            foreach ($entry in $knownRoots) {
                $value = $value.Replace([string]$entry[0], [string]$entry[1], [StringComparison]::OrdinalIgnoreCase)
            }
            if ($hostUser) { $value = $value.Replace($hostUser, '<host-user>', [StringComparison]::OrdinalIgnoreCase) }
            if ($hostDevice) { $value = $value.Replace($hostDevice, '<host-device>', [StringComparison]::OrdinalIgnoreCase) }
            $value -replace '(?i)\b[A-Z]:\\[^\r\n]*', '<host-path>'
        })
}

function Test-ObjectProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Resolve-PublicToolIdentityPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        $RelativePath -ne $RelativePath.Replace('\', '/') -or
        [IO.Path]::IsPathRooted($RelativePath) -or
        ($RelativePath -split '/') -contains '..' -or
        $RelativePath -match '[\x00-\x1f]') {
        throw "Public tool identity path is not a normalized relative path: $RelativePath"
    }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $prefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Public tool identity path escaped the benchmark tools root: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Declared public tool identity is unavailable: $RelativePath"
    }
    $current = Get-Item -LiteralPath $full -Force
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Public tool identity has a reparse-point ancestor: $RelativePath"
        }
        if ($current.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar) -ieq $rootFull) {
            break
        }
        $current = if ($current -is [IO.DirectoryInfo]) { $current.Parent } else { $current.Directory }
    }
    return $full
}

function Wait-TaskState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedToken,
        [Parameter(Mandatory)][int]$ExpectedProcessId,
        [int]$TimeoutMs = 10000
    )
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    while ($deadline.ElapsedMilliseconds -lt $TimeoutMs) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            try {
                $state = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
                if ([string]$state.process_token -ceq $ExpectedToken -and
                    [int]$state.process_id -eq $ExpectedProcessId) {
                    return $state
                }
            }
            catch {
                # Atomic replacement can briefly race with directory metadata; retry within the bound.
            }
        }
        Start-Sleep -Milliseconds 100
    }
    return $null
}

function Test-TaskStateShape {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$ExpectedToken,
        [Parameter(Mandatory)][int]$ExpectedProcessId
    )
    $rootFields = @(
        'schema_version', 'process_token', 'process_id', 'snapshot_id', 'round_id',
        'round_index', 'restart_count', 'monotonic_ms', 'bridge_ready',
        'provider_ready', 'game_state'
    )
    foreach ($field in $rootFields) {
        if (-not (Test-ObjectProperty -Object $State -Name $field)) { return $false }
    }
    if ([string]$State.schema_version -cne '2.0.0' -or
        [string]$State.process_token -cne $ExpectedToken -or
        [int]$State.process_id -ne $ExpectedProcessId -or
        [int64]$State.snapshot_id -lt 0 -or
        [double]$State.monotonic_ms -lt 0 -or
        $State.bridge_ready -ne $true) {
        return $false
    }
    try {
        $json = $State | ConvertTo-Json -Depth 100
        return Test-Json -Json $json -SchemaFile (Join-Path $script:InputFull 'contracts/game-state.schema.json') -ErrorAction Stop
    }
    catch { return $false }

}

function Get-OperationFaultCode {
    param([AllowNull()][object]$Operation)
    if ($null -ne $Operation -and $null -ne $Operation.fault -and
        (Test-ObjectProperty -Object $Operation.fault -Name 'code')) {
        return [string]$Operation.fault.code
    }
    return 'operation_failed_without_code'
}

$Checks = [Collections.Generic.List[object]]::new()
$Faults = [Collections.Generic.List[object]]::new()
$StartedUtc = [DateTime]::UtcNow
$SmokeId = 'public-smoke-{0}-{1}' -f $StartedUtc.ToString('yyyyMMddTHHmmssfffZ'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$Status = 'blocked'
$ExitCode = 2
$Session = $null
$SessionActive = $false
$Cleanup = [ordered]@{
    attempted = $false
    status = 'not_acquired'
    process_tree_clean = $null
    controlled_input_released = $null
}

$inputItem = Get-Item -LiteralPath $InputRoot -Force
$engineItem = Get-Item -LiteralPath $EngineRoot -Force
$toolsItem = Get-Item -LiteralPath $BenchmarkToolsRoot -Force
if (-not $inputItem.PSIsContainer -or -not $engineItem.PSIsContainer -or -not $toolsItem.PSIsContainer) {
    [Console]::Error.WriteLine('PUBLIC_SMOKE_BLOCKED: invalid_root_parameter')
    exit 2
}
$InputFull = $inputItem.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar)
$EngineFull = $engineItem.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar)
$ToolsFull = $toolsItem.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar)
$RunFull = [IO.Path]::GetFullPath($RunRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$inputPrefix = $InputFull + [IO.Path]::DirectorySeparatorChar
if ($RunFull.StartsWith($inputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine('PUBLIC_SMOKE_BLOCKED: run_root_inside_input')
    exit 2
}
if (Test-Path -LiteralPath $RunFull) {
    $runItem = Get-Item -LiteralPath $RunFull -Force
    if (-not $runItem.PSIsContainer -or @(Get-ChildItem -LiteralPath $RunFull -Force).Count -gt 0) {
        [Console]::Error.WriteLine('PUBLIC_SMOKE_BLOCKED: run_root_not_empty')
        exit 2
    }
}
else {
    [void](New-Item -ItemType Directory -Path $RunFull)
}
foreach ($relativeDirectory in @('logs', 'receipts', 'state', 'captures')) {
    [void](New-Item -ItemType Directory -Path (Join-Path $RunFull $relativeDirectory))
}

$BenchmarkHash = (Get-FileHash -LiteralPath (Join-Path $InputFull 'BENCHMARK_MANIFEST.json') -Algorithm SHA256).Hash.ToLowerInvariant()

$ResultPath = Join-Path $RunFull 'public-smoke-result.json'
$BuildLogPath = Join-Path $RunFull 'logs/build.txt'
$StaticLogPath = Join-Path $RunFull 'logs/package-validation.txt'
$ProjectPath = Join-Path $InputFull 'starter-project/Captain2DScaffold.uproject'
$EngineStatePath = Join-Path $RunFull 'state/engine-health.json'
$GameStatePath = Join-Path $RunFull 'state/game-state.json'

try {
    $currentShell = (Get-Process -Id $PID).Path
    $staticOutput = & $currentShell -NoProfile -File (Join-Path $InputFull 'tools/Test-PublicInput.ps1') -InputRoot $InputFull 2>&1
    $staticExit = $LASTEXITCODE
    [IO.File]::WriteAllLines(
        $StaticLogPath,
        (ConvertTo-PublicSmokeSanitizedText -Lines ([string[]]@($staticOutput))),
        [Text.UTF8Encoding]::new($false))
    if ($staticExit -ne 0) {
        Add-SmokeCheck -Id 'package_identity' -Status 'failed' -Detail 'The public package consistency gate failed.' -Evidence @('logs/package-validation.txt')
        Add-SmokeFault -Domain 'release' -Code 'package_identity_failed'
        $Status = 'failed'
        $ExitCode = 1
        throw 'controlled_public_smoke_failure'
    }
    try {
        $benchmark = Get-Content -LiteralPath (Join-Path $InputFull 'BENCHMARK_MANIFEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
        $toolIdentities = @(
            [pscustomobject]@{ path = [string]$benchmark.engine.executor_module; sha256 = [string]$benchmark.tooling.executor_sha256 },
            [pscustomobject]@{ path = [string]$benchmark.engine.executor_native_interop; sha256 = [string]$benchmark.tooling.executor_native_interop_sha256 },
            [pscustomobject]@{ path = [string]$benchmark.engine.observer_module; sha256 = [string]$benchmark.tooling.observer_sha256 },
            [pscustomobject]@{ path = [string]$benchmark.engine.operation_result_schema; sha256 = [string]$benchmark.tooling.operation_result_schema_sha256 },
            [pscustomobject]@{ path = [string]$benchmark.observation.engine_state_schema; sha256 = [string]$benchmark.tooling.state_snapshot_schema_sha256 },
            [pscustomobject]@{ path = [string]$benchmark.tooling.capabilities_contract; sha256 = [string]$benchmark.tooling.capabilities_contract_sha256 }
        )
        foreach ($identity in $toolIdentities) {
            if ($identity.sha256 -cnotmatch '^[a-f0-9]{64}$') {
                throw "Declared public tool SHA-256 is invalid: $($identity.path)"
            }
            $identityPath = Resolve-PublicToolIdentityPath -Root $ToolsFull -RelativePath $identity.path
            $actualIdentity = (Get-FileHash -LiteralPath $identityPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualIdentity -cne $identity.sha256) {
                throw "Declared public tool SHA-256 does not match: $($identity.path)"
            }
        }
        [IO.File]::AppendAllLines(
            $StaticLogPath,
            [string[]]@("PUBLIC_TOOL_IDENTITY_OK files=$($toolIdentities.Count)"),
            [Text.UTF8Encoding]::new($false)
        )
    }
    catch {
        Add-SmokeCheck -Id 'package_identity' -Status 'failed' -Detail 'The public package or declared tool identity gate failed.' -Evidence @('logs/package-validation.txt')
        Add-SmokeFault -Domain 'release' -Code 'public_tool_identity_failed'
        $Status = 'failed'
        $ExitCode = 1
        throw 'controlled_public_smoke_failure'
    }
    Add-SmokeCheck -Id 'package_identity' -Status 'passed' -Detail 'The public package and declared tool identities passed.' -Evidence @('logs/package-validation.txt')

    $buildEntry = Join-Path $EngineFull 'Engine/Build/BatchFiles/Build.bat'
    if (-not (Test-Path -LiteralPath $buildEntry -PathType Leaf)) {
        Add-SmokeCheck -Id 'source_build' -Status 'blocked' -Detail 'The Unreal build entry was unavailable.'
        Add-SmokeFault -Domain 'environment' -Code 'build_entry_unavailable'
        throw 'controlled_public_smoke_block'
    }
    $buildOutput = & $buildEntry Captain2DScaffoldEditor Win64 Development $ProjectPath '-CompilerVersion=14.44.35207' -WaitMutex -NoHotReloadFromIDE 2>&1
    $buildExit = $LASTEXITCODE
    [IO.File]::WriteAllLines(
        $BuildLogPath,
        (ConvertTo-PublicSmokeSanitizedText -Lines ([string[]]@($buildOutput))),
        [Text.UTF8Encoding]::new($false))
    if ($buildExit -ne 0) {
        Add-SmokeCheck -Id 'source_build' -Status 'failed' -Detail 'The documented source target returned a nonzero exit code.' -Evidence @('logs/build.txt')
        Add-SmokeFault -Domain 'starter-project' -Code 'source_build_failed'
        $Status = 'failed'
        $ExitCode = 1
        throw 'controlled_public_smoke_failure'
    }
    Add-SmokeCheck -Id 'source_build' -Status 'passed' -Detail 'The documented source target built with exit code zero.' -Evidence @('logs/build.txt')

    $executorPath = Join-Path $ToolsFull 'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1'
    $observerPath = Join-Path $ToolsFull 'engine/unreal-5.7.4/observer/UnrealEvaluationObserver.psm1'
    if (-not (Test-Path -LiteralPath $executorPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $observerPath -PathType Leaf)) {
        Add-SmokeFault -Domain 'environment' -Code 'public_module_unavailable'
        throw 'controlled_public_smoke_block'
    }
    Import-Module $executorPath -Force
    Import-Module $observerPath -Force

    $start = Start-UnrealEvaluationSession -ProjectPath $ProjectPath -RunRoot $RunFull `
        -StatePath $EngineStatePath -EngineRoot $EngineFull -WindowWidth 1280 -WindowHeight 720 `
        -TimeoutMs 60000 -FocusTimeoutMs 1500 `
        -AdditionalArguments @("-EvalGameStatePath=$GameStatePath", '-ForceRes')
    Save-JsonArtifact -Value $start -Path (Join-Path $RunFull 'receipts/start.json')
    if ($start.status -ne 'ok') {
        Add-SmokeCheck -Id 'initial_start' -Status 'blocked' -Detail 'The public executor could not establish a healthy initial session.' -Evidence @('receipts/start.json')
        Add-SmokeFault -Domain $(if ($start.environment_fault) { 'environment' } else { 'executor' }) -Code (Get-OperationFaultCode -Operation $start)
        throw 'controlled_public_smoke_block'
    }
    $Session = $start.result.session
    $SessionActive = $true
    Add-SmokeCheck -Id 'initial_start' -Status 'passed' -Detail 'The public executor established a bound independent game session.' -Evidence @('receipts/start.json')

    $initialRead = Read-UnrealEvaluationState -StatePath $EngineStatePath `
        -ExpectedProcessToken ([string]$start.result.process_token) `
        -ExpectedProcessId ([int]$start.result.process_id) -MaxAgeMs 2000
    Save-JsonArtifact -Value $initialRead -Path (Join-Path $RunFull 'receipts/read-initial-engine-state.json')
    if ($initialRead.status -ne 'ok') {
        Add-SmokeCheck -Id 'initial_engine_state' -Status 'blocked' -Detail 'The initial engine-health snapshot was not fresh and identity-matched.' -Evidence @('receipts/read-initial-engine-state.json')
        Add-SmokeFault -Domain 'executor' -Code (Get-OperationFaultCode -Operation $initialRead)
        throw 'controlled_public_smoke_block'
    }
    Add-SmokeCheck -Id 'initial_engine_state' -Status 'passed' -Detail 'The initial engine-health snapshot was fresh and identity-matched.' -Evidence @('state/engine-health.json', 'receipts/read-initial-engine-state.json')

    $initialTaskState = Wait-TaskState -Path $GameStatePath `
        -ExpectedToken ([string]$start.result.process_token) -ExpectedProcessId ([int]$start.result.process_id)
    if ($null -eq $initialTaskState -or
        -not (Test-TaskStateShape -State $initialTaskState `
            -ExpectedToken ([string]$start.result.process_token) -ExpectedProcessId ([int]$start.result.process_id))) {
        Add-SmokeCheck -Id 'initial_task_state' -Status 'blocked' -Detail 'The initial task-state envelope was missing, stale, or structurally invalid.' -Evidence @('state/game-state.json')
        Add-SmokeFault -Domain 'executor' -Code 'initial_task_state_invalid'
        throw 'controlled_public_smoke_block'
    }
    Add-SmokeCheck -Id 'initial_task_state' -Status 'passed' -Detail 'The initial task-state envelope was fresh, identity-matched, and structurally valid.' -Evidence @('state/game-state.json')

    $initialCapture = Save-UnrealClientCapture -Session $Session `
        -OutputPath (Join-Path $RunFull 'captures/initial-frame.png') -ArtifactId 'public-smoke-initial-frame'
    Save-JsonArtifact -Value $initialCapture -Path (Join-Path $RunFull 'receipts/capture-initial.json')
    if ($initialCapture.status -ne 'ok' -or [int]$initialCapture.result.width -ne 1280 -or [int]$initialCapture.result.height -ne 720) {
        Add-SmokeCheck -Id 'initial_capture' -Status 'blocked' -Detail 'The initial capture did not match the required 1280 x 720 client contract.' -Evidence @('receipts/capture-initial.json')
        Add-SmokeFault -Domain 'environment' -Code (Get-OperationFaultCode -Operation $initialCapture)
        throw 'controlled_public_smoke_block'
    }
    Add-SmokeCheck -Id 'initial_capture' -Status 'passed' -Detail 'A 1280 x 720 client-only frame was captured.' -Evidence @('captures/initial-frame.png', 'receipts/capture-initial.json')

    $oldProcessId = [int]$start.result.process_id
    $oldProcessToken = [string]$start.result.process_token
    $SessionActive = $false
    $reopen = Reopen-UnrealEvaluationSession -Session $Session -GraceTimeoutMs 10000 -StartTimeoutMs 60000
    Save-JsonArtifact -Value $reopen -Path (Join-Path $RunFull 'receipts/reopen.json')
    if ($reopen.status -ne 'ok') {
        if (Test-ObjectProperty -Object $reopen.result -Name 'session') {
            $Session = $reopen.result.session
            $SessionActive = $true
        }
        Add-SmokeCheck -Id 'reopen_identity' -Status 'blocked' -Detail 'Reopen did not produce a healthy new process.' -Evidence @('receipts/reopen.json')
        Add-SmokeFault -Domain $(if ($reopen.environment_fault) { 'environment' } else { 'executor' }) -Code (Get-OperationFaultCode -Operation $reopen)
        throw 'controlled_public_smoke_block'
    }
    $Session = $reopen.result.session
    $SessionActive = $true
    $newProcessId = [int]$reopen.result.process_id
    $newProcessToken = [string]$reopen.result.process_token
    if ($newProcessId -eq $oldProcessId -or $newProcessToken -ceq $oldProcessToken) {
        Add-SmokeCheck -Id 'reopen_identity' -Status 'blocked' -Detail 'Reopen did not renew both process identities.' -Evidence @('receipts/reopen.json')
        Add-SmokeFault -Domain 'executor' -Code 'reopen_identity_not_renewed'
        throw 'controlled_public_smoke_block'
    }
    Add-SmokeCheck -Id 'reopen_identity' -Status 'passed' -Detail 'Reopen closed the old process and renewed both process identities.' -Evidence @('receipts/reopen.json')

    $reopenRead = Read-UnrealEvaluationState -StatePath $EngineStatePath `
        -ExpectedProcessToken $newProcessToken -ExpectedProcessId $newProcessId -MaxAgeMs 2000
    Save-JsonArtifact -Value $reopenRead -Path (Join-Path $RunFull 'receipts/read-reopen-engine-state.json')
    $reopenTaskState = Wait-TaskState -Path $GameStatePath -ExpectedToken $newProcessToken -ExpectedProcessId $newProcessId
    if ($reopenRead.status -ne 'ok' -or $null -eq $reopenTaskState -or
        -not (Test-TaskStateShape -State $reopenTaskState -ExpectedToken $newProcessToken -ExpectedProcessId $newProcessId)) {
        Add-SmokeCheck -Id 'reopen_state' -Status 'blocked' -Detail 'The reopened process did not publish two fresh identity-matched transports.' -Evidence @('state/engine-health.json', 'state/game-state.json', 'receipts/read-reopen-engine-state.json')
        Add-SmokeFault -Domain 'executor' -Code 'reopen_state_invalid'
        throw 'controlled_public_smoke_block'
    }
    Add-SmokeCheck -Id 'reopen_state' -Status 'passed' -Detail 'The reopened process published two fresh identity-matched transports.' -Evidence @('state/engine-health.json', 'state/game-state.json', 'receipts/read-reopen-engine-state.json')

    $reopenCapture = Save-UnrealClientCapture -Session $Session `
        -OutputPath (Join-Path $RunFull 'captures/reopen-frame.png') -ArtifactId 'public-smoke-reopen-frame'
    Save-JsonArtifact -Value $reopenCapture -Path (Join-Path $RunFull 'receipts/capture-reopen.json')
    if ($reopenCapture.status -ne 'ok' -or [int]$reopenCapture.result.width -ne 1280 -or [int]$reopenCapture.result.height -ne 720) {
        Add-SmokeCheck -Id 'reopen_capture' -Status 'blocked' -Detail 'The reopened 1280 x 720 client capture was unavailable.' -Evidence @('receipts/capture-reopen.json')
        Add-SmokeFault -Domain 'environment' -Code (Get-OperationFaultCode -Operation $reopenCapture)
        throw 'controlled_public_smoke_block'
    }
    Add-SmokeCheck -Id 'reopen_capture' -Status 'passed' -Detail 'A second 1280 x 720 client-only frame was captured from the reopened process.' -Evidence @('captures/reopen-frame.png', 'receipts/capture-reopen.json')

    $Cleanup.attempted = $true
    $stop = Stop-UnrealEvaluationSession -Session $Session -GraceTimeoutMs 10000
    Save-JsonArtifact -Value $stop -Path (Join-Path $RunFull 'receipts/stop.json')
    $SessionActive = $false
    $cleanupHealthy = $stop.status -eq 'ok' -and $stop.result.process_exited -eq $true -and
        [int]$stop.result.job_active_process_count_after_wait -eq 0 -and
        $stop.result.input_lease_released -eq $true -and $stop.result.input_cleanup.all_released -eq $true
    $Cleanup.status = if ($cleanupHealthy) { 'verified' } else { 'failed' }
    $Cleanup.process_tree_clean = [bool]($stop.result.process_exited -eq $true -and [int]$stop.result.job_active_process_count_after_wait -eq 0)
    $Cleanup.controlled_input_released = [bool]($stop.result.input_lease_released -eq $true -and $stop.result.input_cleanup.all_released -eq $true)
    if (-not $cleanupHealthy) {
        Add-SmokeCheck -Id 'final_cleanup' -Status 'blocked' -Detail 'Final input or process-tree cleanup was not verified.' -Evidence @('receipts/stop.json')
        Add-SmokeFault -Domain 'cleanup' -Code (Get-OperationFaultCode -Operation $stop)
        throw 'controlled_public_smoke_block'
    }
    Add-SmokeCheck -Id 'final_cleanup' -Status 'passed' -Detail 'Final controlled input, process-tree, and lease cleanup was verified.' -Evidence @('receipts/stop.json')
    $Status = 'passed'
    $ExitCode = 0
}
catch {
    if ($_.Exception.Message -notin @('controlled_public_smoke_failure', 'controlled_public_smoke_block')) {
        Add-SmokeFault -Domain 'environment' -Code 'unexpected_smoke_exception'
    }
}
finally {
    if ($SessionActive -and $null -ne $Session) {
        $Cleanup.attempted = $true
        try {
            $emergencyStop = Stop-UnrealEvaluationSession -Session $Session -GraceTimeoutMs 10000
            Save-JsonArtifact -Value $emergencyStop -Path (Join-Path $RunFull 'receipts/emergency-stop.json')
            $emergencyHealthy = $emergencyStop.status -eq 'ok' -and $emergencyStop.result.process_exited -eq $true -and
                [int]$emergencyStop.result.job_active_process_count_after_wait -eq 0 -and
                $emergencyStop.result.input_lease_released -eq $true -and $emergencyStop.result.input_cleanup.all_released -eq $true
            $Cleanup.status = if ($emergencyHealthy) { 'verified' } else { 'failed' }
            $Cleanup.process_tree_clean = [bool]($emergencyStop.result.process_exited -eq $true -and [int]$emergencyStop.result.job_active_process_count_after_wait -eq 0)
            $Cleanup.controlled_input_released = [bool]($emergencyStop.result.input_lease_released -eq $true -and $emergencyStop.result.input_cleanup.all_released -eq $true)
            if (-not $emergencyHealthy) {
                Add-SmokeFault -Domain 'cleanup' -Code 'emergency_cleanup_failed'
                $Status = 'blocked'
                $ExitCode = 2
            }
        }
        catch {
            $Cleanup.status = 'failed'
            $Cleanup.process_tree_clean = $false
            $Cleanup.controlled_input_released = $false
            Add-SmokeFault -Domain 'cleanup' -Code 'emergency_cleanup_exception'
            $Status = 'blocked'
            $ExitCode = 2
        }
    }
}

$result = [ordered]@{
    schema_version = '1.0.0'
    smoke_id = $SmokeId
    started_utc = $StartedUtc.ToString('o')
    ended_utc = [DateTime]::UtcNow.ToString('o')
    status = $Status
    exit_code = $ExitCode
    gameplay_requirements_evaluated = $false
    project = [ordered]@{
        project_file = 'starter-project/Captain2DScaffold.uproject'
        target = 'Captain2DScaffoldEditor Win64 Development'
    }
    engine = [ordered]@{
        name = 'Unreal Engine'
        version = '5.7.4'
        platform = 'Windows x64'
        mode = 'editor_game'
    }
    input_identity = [ordered]@{
        benchmark_manifest_sha256 = $BenchmarkHash

    }
    checks = @($Checks)
    faults = @($Faults)
    cleanup = $Cleanup
}
Save-JsonArtifact -Value $result -Path $ResultPath
Write-Output ("PUBLIC_SMOKE_{0} result=public-smoke-result.json" -f $Status.ToUpperInvariant())
exit $ExitCode
