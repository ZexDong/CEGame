[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [ValidateSet("Static", "Dynamic", "Fresh")][string]$Phase = "Static",
    [string]$UnityEditorPath=$env:UNITY_EDITOR,
    [string]$UnityCliPath=$env:UNITY_CLI,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$EvidenceDirectory = "",
    [string]$EvaluatorPackagePath = "",
    [string]$EvaluationSessionId = "",
    [string]$TestFilter = "",
    [ValidateRange(0, 3600)][int]$TimeoutSeconds = 0,
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
if ([string]::IsNullOrWhiteSpace($EvaluatorPackagePath)) {
    $EvaluatorPackagePath = Join-Path $evaluationRoot "package"
}
$packagePath = (Resolve-Path -LiteralPath $EvaluatorPackagePath).Path
$classifierPath = Join-Path $PSScriptRoot "classify-unity-phase-result.ps1"
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$UnityEditorPath = (Resolve-Path -LiteralPath $UnityEditorPath).Path
$UnityCliPath = (Resolve-Path -LiteralPath $UnityCliPath).Path
if (-not ((Test-PathUnderRoot $ProjectPath $repoTmpRoot) -or
          (Test-PathUnderRoot $ProjectPath $repoRunsRoot))) {
    throw "Private phase runner accepts only repository tmp/ or runs/ project copies: $ProjectPath"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-PathUnderRoot $OutputDirectory $repoTmpRoot)) {
    throw "Private phase output must stay under repository tmp/: $OutputDirectory"
}
if (-not (Test-PathUnderRoot $env:TEMP $repoTmpRoot) -or
    -not (Test-PathUnderRoot $env:TMP $repoTmpRoot)) {
    throw "Invoke phases through run-evaluation.ps1 so Unity/CLI TEMP and TMP stay repository-local."
}
$manifestPath = Join-Path $ProjectPath "Packages\manifest.json"
$lockPath = Join-Path $ProjectPath "Packages\packages-lock.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Candidate is missing Packages/manifest.json: $ProjectPath"
}
if (Test-Path -LiteralPath (Join-Path $ProjectPath "Temp\UnityLockfile") -PathType Leaf) {
    $lockStream = $null
    try {
        $lockStream = [System.IO.File]::Open(
            (Join-Path $ProjectPath "Temp\UnityLockfile"),
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
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path $OutputDirectory "evidence"
}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$EvidenceDirectory = (Resolve-Path -LiteralPath $EvidenceDirectory).Path

$manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
$hadLock = Test-Path -LiteralPath $lockPath -PathType Leaf
$lockBytes = if ($hadLock) { [System.IO.File]::ReadAllBytes($lockPath) } else { $null }
$runId = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss-fff")
$startedUtc = [DateTime]::UtcNow.ToString("o")
$phaseLower = $Phase.ToLowerInvariant()
$resultPath = Join-Path $OutputDirectory "$runId-$phaseLower.xml"
$logPath = Join-Path $OutputDirectory "$runId-$phaseLower.log"
$stderrPath = Join-Path $OutputDirectory "$runId-$phaseLower.stderr.log"
$assembly = switch ($Phase) {
    "Static" { "OmniGame.Benchmark.SignCircuit.Evaluator.Static" }
    "Dynamic" { "OmniGame.Benchmark.SignCircuit.Evaluator.Dynamic" }
    "Fresh" { "OmniGame.Benchmark.SignCircuit.Evaluator.Fresh" }
}
$effectiveTimeout = if ($TimeoutSeconds -gt 0) { $TimeoutSeconds } elseif ($Phase -eq "Dynamic") { 900 } else { 360 }

function Quote-Argument([string]$Value) { '"' + ($Value -replace '"', '\"') + '"' }
$exitCode = -1
$timedOut = $false
$processId = $null
try {
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath |
        ConvertFrom-Json
    if ($null -eq $manifest.PSObject.Properties["dependencies"]) {
        throw "Candidate Packages/manifest.json has no dependencies object."
    }
    $dependencyName = "com.omnigame.benchmark.sign-circuit.evaluator"
    $packageUri = "file:" + ($packagePath -replace '\\', '/')
    $existing = $manifest.dependencies.PSObject.Properties[$dependencyName]
    if ($null -eq $existing) {
        $manifest.dependencies | Add-Member -MemberType NoteProperty `
            -Name $dependencyName -Value $packageUri
    } else {
        $existing.Value = $packageUri
    }
    $testables = if ($null -ne $manifest.PSObject.Properties["testables"]) {
        @($manifest.testables)
    } else { @() }
    foreach ($name in @($dependencyName, "com.unity.inputsystem")) {
        if ($testables -notcontains $name) { $testables += $name }
    }
    if ($null -eq $manifest.PSObject.Properties["testables"]) {
        $manifest | Add-Member -MemberType NoteProperty -Name "testables" -Value $testables
    } else {
        $manifest.testables = $testables
    }
    [System.IO.File]::WriteAllText($manifestPath,
        ($manifest | ConvertTo-Json -Depth 100),
        [System.Text.UTF8Encoding]::new($false))

    # Unity CLI is the primary executor. Raw Editor arguments after `--` retain
    # a graphics device and pass the private assembly/evidence contract through
    # to the Unity Test Framework process.
    $arguments = @(
        "test", (Quote-Argument $ProjectPath),
        "-e", (Quote-Argument $UnityEditorPath),
        "--mode", "PlayMode",
        "--output", (Quote-Argument $resultPath),
        "--timeout", $effectiveTimeout
    )
    if (-not [string]::IsNullOrWhiteSpace($TestFilter)) {
        # Unity CLI owns test selection. The CLI-level --filter must precede
        # the raw Editor delimiter; -testFilter after -- is forbidden here.
        $arguments += @("--filter", (Quote-Argument $TestFilter))
    }
    $arguments += @(
        "--",
        "-noaudio",
        "-assemblyNames", $assembly,
        "-signCircuitEvidenceOutput", (Quote-Argument $EvidenceDirectory)
    )
    if (-not [string]::IsNullOrWhiteSpace($EvaluationSessionId)) {
        $arguments += @("-signCircuitEvaluationSession", (Quote-Argument $EvaluationSessionId))
    }
    $process = Start-Process -FilePath $UnityCliPath -ArgumentList $arguments `
        -WorkingDirectory $ProjectPath -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $logPath -RedirectStandardError $stderrPath
    $processId = $process.Id
    # The CLI owns the Unity watchdog. Give the wrapper cleanup/headroom so it
    # does not kill a CLI process exactly as Unity is writing XML and logs.
    if (-not $process.WaitForExit(($effectiveTimeout + 90) * 1000)) {
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

$healthTestIds = @(switch ($Phase) {
    "Dynamic" { "EVALUATOR_REGRESSION_DynamicRuntimeHealth" }
    "Fresh" { "EVALUATOR_REGRESSION_FreshProcessHealth" }
    default { }
})
$unityProcessId = $null
$healthEvidencePath = $null
if ($healthTestIds.Count -eq 1) {
    $healthEvidencePath = Join-Path $EvidenceDirectory ($healthTestIds[0] + ".json")
    if (Test-Path -LiteralPath $healthEvidencePath -PathType Leaf) {
        try {
            $healthEvidence = Get-Content -Raw -Encoding UTF8 `
                -LiteralPath $healthEvidencePath | ConvertFrom-Json
            if ([string]$healthEvidence.test_id -eq [string]$healthTestIds[0] -and
                [string]$healthEvidence.evaluation_session_id -eq $EvaluationSessionId -and
                [int]$healthEvidence.process_id -gt 0) {
                # This PID is written inside the private test assembly and is the
                # actual Unity Editor test process, not the outer Unity CLI PID.
                $unityProcessId = [int]$healthEvidence.process_id
            }
        } catch {
            $unityProcessId = $null
        }
    }
}
$classification = ((& $classifierPath -ExitCode $exitCode -LogPath $logPath `
    -ProjectPath $ProjectPath -InvocationKind Test -ResultPath $resultPath `
    -EvaluatorHealthTestIds $healthTestIds -TimedOut:$timedOut) `
    -join [Environment]::NewLine) |
    ConvertFrom-Json
$result = [pscustomobject]@{
    phase = $Phase
    evaluation_session_id = $EvaluationSessionId
    phase_run_id = $runId
    started_utc = $startedUtc
    completed_utc = $completedUtc
    unity_process_id = $unityProcessId
    cli_process_id = $processId
    process_evidence = $healthEvidencePath
    timeout_seconds = $effectiveTimeout
    executor = "unity_cli_test"
    assembly = $assembly
    test_filter = $TestFilter
    exit_code = $exitCode
    execution_status = [string]$classification.execution_status
    failure_kind = [string]$classification.failure_kind
    compiler_errors = @($classification.compiler_errors)
    evaluator_health_failures = @($classification.evaluator_health_failures)
    evaluator_observation_unsupported =
        @($classification.evaluator_observation_unsupported)
    evaluator_infrastructure_failures =
        @($classification.evaluator_infrastructure_failures)
    candidate_verdicts = @($classification.candidate_verdicts)
    result = $resultPath
    log = $logPath
    cli_stdout_log = $logPath
    stderr_log = $stderrPath
    evidence = $EvidenceDirectory
}
$result | ConvertTo-Json -Depth 6
if (-not $NoExitOnCompletion) { exit $exitCode }
