[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [string]$UnityEditorPath=$env:UNITY_EDITOR,

    [string]$UnityCliPath=$env:UNITY_CLI,

    [string]$OutputDirectory = "",

    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 600,

    [switch]$NoExitOnCompletion
)

$ErrorActionPreference = "Stop"
$evaluationRoot = Split-Path -Parent $PSScriptRoot
$classifierPath = (Resolve-Path -LiteralPath (
    Join-Path $PSScriptRoot "classify-unity-phase-result.ps1")).Path
$processHelperPath = (Resolve-Path -LiteralPath (
    Join-Path $PSScriptRoot "invoke-bounded-cli-process.ps1")).Path
. $processHelperPath

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$UnityEditorPath = (Resolve-Path -LiteralPath $UnityEditorPath).Path
$UnityCliPath = (Resolve-Path -LiteralPath $UnityCliPath).Path

$unityLockPath = Join-Path $ProjectPath "Temp\UnityLockfile"
if (Test-Path -LiteralPath $unityLockPath -PathType Leaf) {
    $lockStream = $null
    try {
        $lockStream = [System.IO.File]::Open(
            $unityLockPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None)
    }
    catch {
        throw "Unity project is already open or otherwise locked: $ProjectPath. " +
            "Close the Editor instance for this candidate project before running evaluation."
    }
    finally {
        if ($null -ne $lockStream) { $lockStream.Dispose() }
    }
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $evaluationRoot "..\..\.."))
    $OutputDirectory = Join-Path $repositoryRoot "tmp\arrow-evaluator-manual-baseline"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

$runId = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss-fff")
$logPath = Join-Path $OutputDirectory "$runId-candidate-compile.log"
$editorLogPath = Join-Path $OutputDirectory "$runId-candidate-compile.editor.tmp.log"
$manifestPath = Join-Path $ProjectPath "Packages\manifest.json"
$lockPath = Join-Path $ProjectPath "Packages\packages-lock.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Candidate project is missing Packages/manifest.json: $ProjectPath"
}
$manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
$hadLock = Test-Path -LiteralPath $lockPath -PathType Leaf
$lockBytes = if ($hadLock) {
    [System.IO.File]::ReadAllBytes($lockPath)
} else {
    $null
}

function Read-EditorDiagnostic([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return "<not created>"
    }
    try { return [System.IO.File]::ReadAllText($Path) }
    catch { return "<could not read '$Path': $($_.Exception.Message)>" }
}

function Write-CombinedDiagnosticLog(
    [string[]]$InvocationArguments,
    $ProcessResult
) {
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine("Arrow Escape evaluator candidate baseline diagnostic")
    [void]$builder.AppendLine("generated_utc=$([DateTime]::UtcNow.ToString('o'))")
    [void]$builder.AppendLine("project=$ProjectPath")
    [void]$builder.AppendLine("unity_cli=$UnityCliPath")
    [void]$builder.AppendLine("unity_editor=$UnityEditorPath")
    [void]$builder.AppendLine("process_id=$([int]$ProcessResult.process_id)")
    [void]$builder.AppendLine("exit_code=$([int]$ProcessResult.exit_code)")
    [void]$builder.AppendLine("timed_out=$([bool]$ProcessResult.timed_out)")
    [void]$builder.AppendLine("argument_transport=$($ProcessResult.argument_transport)")
    [void]$builder.AppendLine("invocation=" + (@($InvocationArguments) -join " "))
    if (-not [string]::IsNullOrWhiteSpace([string]$ProcessResult.launch_error)) {
        [void]$builder.AppendLine("launch_error=$($ProcessResult.launch_error)")
    }
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("===== UNITY CLI STDOUT =====")
    [void]$builder.AppendLine([string]$ProcessResult.stdout)
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("===== UNITY CLI STDERR =====")
    [void]$builder.AppendLine([string]$ProcessResult.stderr)
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("===== UNITY EDITOR LOG =====")
    [void]$builder.AppendLine((Read-EditorDiagnostic $editorLogPath))
    [System.IO.File]::WriteAllText(
        $logPath,
        $builder.ToString(),
        [System.Text.UTF8Encoding]::new($false))

    # Process and redirected streams have already been disposed by the helper.
    # Keep just one combined author diagnostic unless the editor file is still
    # externally locked, in which case preserving it is safer than data loss.
    try {
        if (Test-Path -LiteralPath $editorLogPath -PathType Leaf) {
            Remove-Item -LiteralPath $editorLogPath -Force -ErrorAction Stop
        }
    }
    catch {}
}

function New-UnityCliRunArguments(
    [string]$CandidateProjectPath,
    [string]$EditorPath,
    [int]$CliTimeoutSeconds,
    [string]$EditorLogPath
) {
    # Unity CLI owns the reserved batch/quit/project switches.  Only the
    # Editor log path is forwarded after `--`.
    return @(
        "--non-interactive",
        "--no-banner",
        "--verbose",
        "run",
        "--editor-path", $EditorPath,
        "--timeout", $CliTimeoutSeconds.ToString(),
        $CandidateProjectPath,
        "--",
        "-logFile", $EditorLogPath
    )
}

# Unity CLI `run` owns its reserved batch/quit flags. In particular, forwarding
# `-quit` after `--` makes CLI 1.0.0-beta.3 fail before Editor startup with exit
# code 6. Only non-reserved Editor arguments are forwarded here.
$arguments = @(New-UnityCliRunArguments `
    $ProjectPath $UnityEditorPath $TimeoutSeconds $editorLogPath)
$graceSeconds = if ($TimeoutSeconds -le 5) { 2 } else { 45 }
$processResult = $null
$startedUtc = [DateTime]::UtcNow.ToString("o")
try {
    $processResult = Invoke-BoundedCliProcess `
        -FilePath $UnityCliPath `
        -Arguments $arguments `
        -WorkingDirectory $ProjectPath `
        -TimeoutSeconds $TimeoutSeconds `
        -GraceSeconds $graceSeconds
}
finally {
    [System.IO.File]::WriteAllBytes($manifestPath, $manifestBytes)
    if ($hadLock) {
        [System.IO.File]::WriteAllBytes($lockPath, $lockBytes)
    } elseif (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        Remove-Item -LiteralPath $lockPath -Force
    }
    if ($null -ne $processResult) {
        Write-CombinedDiagnosticLog $arguments $processResult
    }
}
$completedUtc = [DateTime]::UtcNow.ToString("o")

if ($null -eq $processResult) {
    throw "Unity CLI process helper returned no result."
}
$exitCode = [int]$processResult.exit_code
$timedOut = [bool]$processResult.timed_out
$classificationRaw = & $classifierPath `
    -ExitCode $exitCode `
    -LogPath $logPath `
    -ProjectPath $ProjectPath `
    -TimedOut:$timedOut
$classification = (($classificationRaw -join [Environment]::NewLine) |
    ConvertFrom-Json)

$result = [pscustomobject]@{
    phase = "BaselineCompile"
    phase_run_id = $runId
    started_utc = $startedUtc
    completed_utc = $completedUtc
    executor = "unity_cli_run"
    # `unity run` does not expose its child Editor PID to this wrapper.  Keep
    # that fact explicit instead of mislabelling the outer CLI PID as Unity.
    unity_process_id = $null
    cli_process_id = [int]$processResult.process_id
    argument_transport = [string]$processResult.argument_transport
    exit_code = $exitCode
    timed_out = $timedOut
    timeout_seconds = $TimeoutSeconds
    execution_status = [string]$classification.execution_status
    failure_kind = [string]$classification.failure_kind
    failure_reason = [string]$classification.failure_reason
    compiler_errors = @($classification.compiler_errors)
    log = $logPath
    combined_cli_editor_log = $logPath
}

$result | ConvertTo-Json -Depth 6
if (-not $NoExitOnCompletion) { exit $exitCode }
