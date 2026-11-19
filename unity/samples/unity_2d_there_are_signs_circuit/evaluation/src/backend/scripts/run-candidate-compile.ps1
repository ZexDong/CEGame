[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [string]$UnityEditorPath=$env:UNITY_EDITOR,
    [string]$UnityCliPath=$env:UNITY_CLI,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$EvaluationSessionId = "",
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 1200,
    [switch]$NoExitOnCompletion
)

$ErrorActionPreference = "Stop"
$evaluationRoot = Split-Path -Parent $PSScriptRoot
$demoRoot = Split-Path -Parent $evaluationRoot
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $demoRoot "..\..")).Path
$repoTmpRoot = (Join-Path $repoRoot "tmp").TrimEnd('\', '/')
$repoRunsRoot = (Join-Path $repoRoot "runs").TrimEnd('\', '/')
function Test-PathUnderRoot([string]$Path, [string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)
}
$classifierPath = Join-Path $PSScriptRoot "classify-unity-phase-result.ps1"
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$UnityEditorPath = (Resolve-Path -LiteralPath $UnityEditorPath).Path
$UnityCliPath = (Resolve-Path -LiteralPath $UnityCliPath).Path
if (-not ((Test-PathUnderRoot $ProjectPath $repoTmpRoot) -or
          (Test-PathUnderRoot $ProjectPath $repoRunsRoot))) {
    throw "Private compile runner accepts only repository tmp/ or runs/ project copies: $ProjectPath"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-PathUnderRoot $OutputDirectory $repoTmpRoot)) {
    throw "Private compile output must stay under repository tmp/: $OutputDirectory"
}
if (-not (Test-PathUnderRoot $env:TEMP $repoTmpRoot) -or
    -not (Test-PathUnderRoot $env:TMP $repoTmpRoot)) {
    throw "Invoke compile through run-evaluation.ps1 so Unity TEMP and TMP stay repository-local."
}

$unityLockPath = Join-Path $ProjectPath "Temp\UnityLockfile"
if (Test-Path -LiteralPath $unityLockPath -PathType Leaf) {
    $lockStream = $null
    try {
        $lockStream = [System.IO.File]::Open(
            $unityLockPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None)
    } catch {
        throw "Unity project is open or locked. Close it before evaluation: $ProjectPath"
    } finally {
        if ($null -ne $lockStream) { $lockStream.Dispose() }
    }
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

$manifestPath = Join-Path $ProjectPath "Packages\manifest.json"
$lockPath = Join-Path $ProjectPath "Packages\packages-lock.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Candidate is missing Packages/manifest.json: $ProjectPath"
}
$manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
$hadLock = Test-Path -LiteralPath $lockPath -PathType Leaf
$lockBytes = if ($hadLock) { [System.IO.File]::ReadAllBytes($lockPath) } else { $null }
$runId = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss-fff")
$startedUtc = [DateTime]::UtcNow.ToString("o")
$logPath = Join-Path $OutputDirectory "$runId-candidate-compile.log"
$stdoutPath = Join-Path $OutputDirectory "$runId-candidate-compile.cli.stdout.log"
$stderrPath = Join-Path $OutputDirectory "$runId-candidate-compile.cli.stderr.log"

function Quote-Argument([string]$Value) { '"' + ($Value -replace '"', '\"') + '"' }
function New-UnityCliRunArguments(
    [string]$CandidateProjectPath,
    [string]$EditorPath,
    [int]$CliTimeoutSeconds,
    [string]$UnityLogPath
) {
    # `unity run` owns batch/quit/project routing. Do not duplicate those raw
    # Editor switches after `--`; only the Unity log destination is forwarded.
    return @(
        "run",
        "--editor-path", (Quote-Argument $EditorPath),
        "--timeout", $CliTimeoutSeconds,
        (Quote-Argument $CandidateProjectPath),
        "--",
        "-logFile", (Quote-Argument $UnityLogPath)
    )
}
$exitCode = -1
$timedOut = $false
$cliProcessId = $null
try {
    $arguments = New-UnityCliRunArguments `
        $ProjectPath $UnityEditorPath $TimeoutSeconds $logPath
    $process = Start-Process -FilePath $UnityCliPath -ArgumentList $arguments `
        -WorkingDirectory $ProjectPath -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $cliProcessId = $process.Id
    # The pinned CLI owns the primary timeout and child-Editor cleanup. This
    # outer watchdog only provides bounded wrapper headroom for log flushing.
    if (-not $process.WaitForExit(($TimeoutSeconds + 90) * 1000)) {
        $timedOut = $true
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(10000) | Out-Null
        $exitCode = 124
    } else {
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    }
} finally {
    [System.IO.File]::WriteAllBytes($manifestPath, $manifestBytes)
    if ($hadLock) {
        [System.IO.File]::WriteAllBytes($lockPath, $lockBytes)
    } elseif (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        Remove-Item -LiteralPath $lockPath -Force
    }
}
$completedUtc = [DateTime]::UtcNow.ToString("o")

$classification = ((& $classifierPath -ExitCode $exitCode -LogPath $logPath `
    -ProjectPath $ProjectPath -InvocationKind Baseline -TimedOut:$timedOut) `
    -join [Environment]::NewLine) |
    ConvertFrom-Json
$result = [pscustomobject]@{
    phase = "BaselineCompile"
    evaluation_session_id = $EvaluationSessionId
    phase_run_id = $runId
    started_utc = $startedUtc
    completed_utc = $completedUtc
    # Baseline has no private in-process health record, so the child Unity PID
    # is intentionally unknown. The outer pinned CLI PID remains explicit.
    unity_process_id = $null
    cli_process_id = $cliProcessId
    timeout_seconds = $TimeoutSeconds
    executor = "unity_cli_run"
    exit_code = $exitCode
    execution_status = [string]$classification.execution_status
    failure_kind = [string]$classification.failure_kind
    compiler_errors = @($classification.compiler_errors)
    log = $logPath
    cli_stdout_log = $stdoutPath
    stderr_log = $stderrPath
}
$result | ConvertTo-Json -Depth 6
if (-not $NoExitOnCompletion) { exit $exitCode }
