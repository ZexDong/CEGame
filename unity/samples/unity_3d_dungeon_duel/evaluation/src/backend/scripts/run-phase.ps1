[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$ProjectPath,
    [ValidateSet('Static','Dynamic','Fresh')] [string]$Phase = 'Static',
    [string]$UnityEditorPath=$env:UNITY_EDITOR,
    [string]$UnityCliPath=$env:UNITY_CLI,
    [string]$OutputDirectory = '',
    [ValidateRange(0,3600)] [int]$TimeoutSeconds = 0,
    [string]$TestFilter = '',
    [ValidateRange(0,2147483647)] [int]$PriorProcessId = 0,
    [switch]$NoExitOnCompletion
)

$ErrorActionPreference = 'Stop'
$evaluationRoot = Split-Path -Parent $PSScriptRoot
$packagePath = (Resolve-Path -LiteralPath (Join-Path $evaluationRoot 'package')).Path
$classifierPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'classify-unity-phase-result.ps1')).Path
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$UnityEditorPath = (Resolve-Path -LiteralPath $UnityEditorPath).Path
$UnityCliPath = (Resolve-Path -LiteralPath $UnityCliPath).Path

$manifestPath = Join-Path $ProjectPath 'Packages\manifest.json'
$lockPath = Join-Path $ProjectPath 'Packages\packages-lock.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Candidate Unity project is missing Packages/manifest.json: $ProjectPath"
}
$unityLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
if (Test-Path -LiteralPath $unityLockPath -PathType Leaf) {
    throw "Candidate project is open. Close its Editor before evaluation: $ProjectPath"
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    throw 'OutputDirectory is required and must be repository-local.'
}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

$runId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$phaseLower = $Phase.ToLowerInvariant()
$resultPath = Join-Path $OutputDirectory "$runId-$phaseLower.xml"
$logPath = Join-Path $OutputDirectory "$runId-$phaseLower.log"
$cliStdout = Join-Path $OutputDirectory "$runId-$phaseLower-cli.stdout.log"
$cliStderr = Join-Path $OutputDirectory "$runId-$phaseLower-cli.stderr.log"
$evidencePath = if ($Phase -in @('Dynamic','Fresh')) {
    Join-Path $OutputDirectory "$runId-$phaseLower-evidence"
} else { '' }
if ($evidencePath) { New-Item -ItemType Directory -Path $evidencePath | Out-Null }

$effectiveTimeoutSeconds = if ($TimeoutSeconds -gt 0) { $TimeoutSeconds }
    elseif ($Phase -eq 'Static') { 300 }
    elseif ($Phase -eq 'Fresh') { 420 }
    else { 900 }
$filter = if (-not [string]::IsNullOrWhiteSpace($TestFilter)) { $TestFilter }
    elseif ($Phase -eq 'Static') { 'StaticGateTests' }
    elseif ($Phase -eq 'Fresh') { 'Fresh' }
    else { 'Dynamic' }
$assembly = if ($Phase -eq 'Static') {
    'OmniGame.Benchmark.DungeonDuel.Trajectory.Static'
} elseif ($Phase -eq 'Fresh') {
    'OmniGame.Benchmark.DungeonDuel.Trajectory.Fresh'
} else {
    'OmniGame.Benchmark.DungeonDuel.Trajectory.Dynamic'
}

function Quote([string]$Value) { '"' + ($Value -replace '"','\"') + '"' }

$backupRoot = Join-Path $OutputDirectory ('_manifest-backup-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backupRoot | Out-Null
$manifestBackup = Join-Path $backupRoot 'manifest.json'
$lockBackup = Join-Path $backupRoot 'packages-lock.json'
Copy-Item -LiteralPath $manifestPath -Destination $manifestBackup
$hadLock = Test-Path -LiteralPath $lockPath -PathType Leaf
if ($hadLock) { Copy-Item -LiteralPath $lockPath -Destination $lockBackup }

$exitCode = -1
$timedOut = $false
$cliProcessId = 0
$unityProcessId = 0
try {
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
    if ($null -eq $manifest.PSObject.Properties['dependencies']) {
        throw 'Candidate Packages/manifest.json has no dependencies object.'
    }
    $dependencyName = 'com.omnigame.benchmark.dungeon-duel.trajectory-evaluator'
    $packageUri = 'file:' + ($packagePath -replace '\\','/')
    $dependency = $manifest.dependencies.PSObject.Properties[$dependencyName]
    if ($null -eq $dependency) {
        $manifest.dependencies | Add-Member NoteProperty $dependencyName $packageUri
    } else { $dependency.Value = $packageUri }
    $testables = @()
    if ($null -ne $manifest.PSObject.Properties['testables']) {
        $testables = @($manifest.testables | Where-Object { $_ })
    }
    foreach ($name in @($dependencyName,'com.unity.inputsystem')) {
        if ($testables -notcontains $name) { $testables += $name }
    }
    if ($null -eq $manifest.PSObject.Properties['testables']) {
        $manifest | Add-Member NoteProperty testables $testables
    } else { $manifest.testables = $testables }
    [IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))

    $args = @(
        '--json','--non-interactive','test',(Quote $ProjectPath),
        '--mode','PlayMode','--filter',(Quote $filter),
        '--output',(Quote $resultPath),'--editor-path',(Quote $UnityEditorPath),
        '--timeout',$effectiveTimeoutSeconds.ToString(),
        '--','-logFile',(Quote $logPath)
    )
    if ($evidencePath) {
        $args += @(
            '-omnigameTrajectoryOutput',(Quote $evidencePath),
            '-omnigameDungeonDuelTrajectoryOutput',(Quote $evidencePath),
            '-omnigameEvaluatorPhase',$Phase
        )
    }
    if ($Phase -eq 'Fresh') {
        $args += @('-omnigamePriorProcessId',$PriorProcessId.ToString())
    }

    $process = Start-Process -FilePath $UnityCliPath -ArgumentList $args `
        -WorkingDirectory $ProjectPath -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $cliStdout -RedirectStandardError $cliStderr
    $cliProcessId = [int]$process.Id
    $graceSeconds = if ($effectiveTimeoutSeconds -le 5) { 2 } else { 45 }
    if (-not $process.WaitForExit(($effectiveTimeoutSeconds + $graceSeconds) * 1000)) {
        $timedOut = $true
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(10000) | Out-Null
        $exitCode = 124
    } else {
        $process.WaitForExit()
        $exitCode = [int]$process.ExitCode
    }

    if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
        $parts = @()
        if (Test-Path -LiteralPath $cliStdout) { $parts += Get-Content -LiteralPath $cliStdout -Raw }
        if (Test-Path -LiteralPath $cliStderr) { $parts += Get-Content -LiteralPath $cliStderr -Raw }
        [IO.File]::WriteAllText($logPath,($parts -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    }

    if ($evidencePath) {
        $healthPath = Join-Path $evidencePath "evaluator-health-$phaseLower.json"
        if (Test-Path -LiteralPath $healthPath -PathType Leaf) {
            try { $unityProcessId = [int]((Get-Content $healthPath -Raw | ConvertFrom-Json).process_id) }
            catch { $unityProcessId = 0 }
        }
    }
}
finally {
    Copy-Item -LiteralPath $manifestBackup -Destination $manifestPath -Force
    if ($hadLock) { Copy-Item -LiteralPath $lockBackup -Destination $lockPath -Force }
    elseif (Test-Path -LiteralPath $lockPath) { [IO.File]::Delete($lockPath) }
    if (Test-Path -LiteralPath $backupRoot) { [IO.Directory]::Delete((Resolve-Path $backupRoot).Path,$true) }
}

$classificationRaw = & $classifierPath -ExitCode $exitCode -LogPath $logPath `
    -ProjectPath $ProjectPath -Phase $Phase -ResultPath $resultPath -TimedOut:$timedOut
$classification = (($classificationRaw -join [Environment]::NewLine) | ConvertFrom-Json)
$result = [pscustomobject]@{
    phase = $Phase
    process_id = $unityProcessId
    cli_process_id = $cliProcessId
    executor = 'unity-cli-test'
    assembly = $assembly
    test_filter = $filter
    test_platform = 'PlayMode'
    exit_code = $exitCode
    timed_out = $timedOut
    timeout_seconds = $effectiveTimeoutSeconds
    execution_status = [string]$classification.execution_status
    failure_kind = [string]$classification.failure_kind
    failure_reason = [string]$classification.failure_reason
    compiler_errors = @($classification.compiler_errors)
    input_system_mismatch_evidence = if (
        $null -ne $classification.PSObject.Properties['input_system_mismatch_evidence']
    ) {
        $classification.input_system_mismatch_evidence
    } else {
        $null
    }
    result = $resultPath
    log = $logPath
    cli_stdout = $cliStdout
    cli_stderr = $cliStderr
    evidence = $evidencePath
}
$result | ConvertTo-Json -Depth 6
if (-not $NoExitOnCompletion) { exit $exitCode }
