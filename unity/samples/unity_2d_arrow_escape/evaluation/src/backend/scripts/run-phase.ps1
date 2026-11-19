[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [ValidateSet("Static", "Dynamic", "Fresh")]
    [string]$Phase = "Static",

    [string]$UnityEditorPath=$env:UNITY_EDITOR,

    [string]$UnityCliPath=$env:UNITY_CLI,

    [string]$OutputDirectory = "",

    [ValidateRange(0, 3600)]
    [int]$TimeoutSeconds = 0,

    [string]$FreshSeedPath = "",

    [string]$FreshOutputDirectory = "",

    [switch]$NoExitOnCompletion
)

$ErrorActionPreference = "Stop"
$evaluationRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $evaluationRoot '..\..\..'))
$packagePath = Join-Path $evaluationRoot "package"
$classifierPath = Join-Path $PSScriptRoot "classify-unity-phase-result.ps1"
$processHelperPath = Join-Path $PSScriptRoot "invoke-bounded-cli-process.ps1"
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$UnityEditorPath = (Resolve-Path -LiteralPath $UnityEditorPath).Path
$UnityCliPath = (Resolve-Path -LiteralPath $UnityCliPath).Path
$packagePath = (Resolve-Path -LiteralPath $packagePath).Path
$classifierPath = (Resolve-Path -LiteralPath $classifierPath).Path
$processHelperPath = (Resolve-Path -LiteralPath $processHelperPath).Path
. $processHelperPath

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
        if ($null -ne $lockStream) {
            $lockStream.Dispose()
        }
    }
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $evaluationRoot "..\..\.."))
    $OutputDirectory = Join-Path $repositoryRoot "tmp\arrow-evaluator-manual"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

$manifestPath = Join-Path $ProjectPath "Packages\manifest.json"
$lockPath = Join-Path $ProjectPath "Packages\packages-lock.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Candidate project is missing Packages/manifest.json: $ProjectPath"
}
$manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
$hadLock = Test-Path -LiteralPath $lockPath -PathType Leaf
$lockBytes = if ($hadLock) {
    [System.IO.File]::ReadAllBytes($lockPath)
} else { $null }

$runId = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss-fff")
$startedUtc = [DateTime]::UtcNow.ToString("o")
$phaseLower = $Phase.ToLowerInvariant()
$resultPath = Join-Path $OutputDirectory "$runId-$phaseLower.xml"
$logPath = Join-Path $OutputDirectory "$runId-$phaseLower.log"
$editorLogPath = Join-Path $OutputDirectory "$runId-$phaseLower.editor.tmp.log"
$evidencePath = if ($Phase -eq "Static") {
    Join-Path $OutputDirectory "$runId-static-evidence"
} elseif ($Phase -eq "Dynamic") {
    Join-Path $OutputDirectory "$runId-dynamic-evidence"
} elseif ($Phase -eq "Fresh") {
    if ([string]::IsNullOrWhiteSpace($FreshOutputDirectory)) {
        Join-Path $OutputDirectory "$runId-fresh-evidence"
    } else {
        [System.IO.Path]::GetFullPath($FreshOutputDirectory)
    }
} else { "" }
$assembly = switch ($Phase) {
    "Static" { "OmniGame.Benchmark.ArrowEscape.Trajectory.Static" }
    "Dynamic" { "OmniGame.Benchmark.ArrowEscape.Trajectory.Dynamic" }
    "Fresh" { "OmniGame.Benchmark.ArrowEscape.Trajectory.Fresh" }
}
$effectiveTimeoutSeconds = if ($TimeoutSeconds -gt 0) {
    $TimeoutSeconds
} elseif ($Phase -in @("Static", "Fresh")) {
    300
} else {
    900
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
    [void]$builder.AppendLine("Arrow Escape evaluator $Phase phase diagnostic")
    [void]$builder.AppendLine("generated_utc=$([DateTime]::UtcNow.ToString('o'))")
    [void]$builder.AppendLine("project=$ProjectPath")
    [void]$builder.AppendLine("unity_cli=$UnityCliPath")
    [void]$builder.AppendLine("unity_editor=$UnityEditorPath")
    [void]$builder.AppendLine("assembly=$assembly")
    [void]$builder.AppendLine("result=$resultPath")
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

    try {
        if (Test-Path -LiteralPath $editorLogPath -PathType Leaf) {
            Remove-Item -LiteralPath $editorLogPath -Force -ErrorAction Stop
        }
    }
    catch {}
}

$processResult = $null
$arguments = @()
try {
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
    $packageUri = "file:" + ($packagePath -replace "\\", "/")
    $dependencyName = "com.omnigame.benchmark.arrow-escape.trajectory-evaluator"
    $dependency = $manifest.dependencies.PSObject.Properties[$dependencyName]
    if ($null -eq $dependency) {
        $manifest.dependencies | Add-Member -MemberType NoteProperty -Name $dependencyName -Value $packageUri
    } else {
        $dependency.Value = $packageUri
    }

    $testables = @()
    if ($null -ne $manifest.PSObject.Properties["testables"]) {
        $testables = @($manifest.testables | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        })
    }
    foreach ($testable in @($dependencyName, "com.unity.inputsystem")) {
        if ($testables -notcontains $testable) {
            $testables += $testable
        }
    }
    if ($null -eq $manifest.PSObject.Properties["testables"]) {
        $manifest | Add-Member -MemberType NoteProperty -Name "testables" -Value $testables
    } else {
        $manifest.testables = $testables
    }

    [System.IO.File]::WriteAllText(
        $manifestPath,
        ($manifest | ConvertTo-Json -Depth 100),
        [System.Text.UTF8Encoding]::new($false))

    $arguments = @(
        "--json",
        "--non-interactive",
        "test",
        $ProjectPath,
        "--mode", "PlayMode",
        "--output", $resultPath,
        "--editor-path", $UnityEditorPath,
        "--timeout", $effectiveTimeoutSeconds.ToString(),
        "--",
        "-screen-width", "1280",
        "-screen-height", "720",
        "-assemblyNames", $assembly,
        "-logFile", $editorLogPath
    )
    if ($Phase -eq "Static") {
        New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
        $arguments += @(
            "-omnigameStaticOutput", $evidencePath
        )
    } elseif ($Phase -eq "Dynamic") {
        $arguments += @(
            "-omnigameTrajectoryOutput", $evidencePath
        )
    } elseif ($Phase -eq "Fresh") {
        if ([string]::IsNullOrWhiteSpace($FreshSeedPath) -or
            -not (Test-Path -LiteralPath $FreshSeedPath -PathType Leaf)) {
            throw "Fresh phase requires the Dynamic fresh-process seed file: $FreshSeedPath"
        }
        $FreshSeedPath = (Resolve-Path -LiteralPath $FreshSeedPath).Path
        New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
        $arguments += @(
            "-omnigameFreshSeed", $FreshSeedPath,
            "-omnigameFreshOutput", $evidencePath
        )
    }
    $graceSeconds = if ($effectiveTimeoutSeconds -le 5) { 2 } else { 45 }
    $processResult = Invoke-BoundedCliProcess `
        -FilePath $UnityCliPath `
        -Arguments $arguments `
        -WorkingDirectory $ProjectPath `
        -TimeoutSeconds $effectiveTimeoutSeconds `
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
    throw "Unity CLI process helper returned no result for phase $Phase."
}
$exitCode = [int]$processResult.exit_code
$timedOut = [bool]$processResult.timed_out

$requiredHealthTests = @(switch ($Phase) {
    "Static" { "EVALUATOR_HEALTH_StaticResolution1280x720" }
    "Dynamic" { "EVALUATOR_HEALTH_DynamicInputProbeAndEvidenceWriter" }
    "Fresh" { "EVALUATOR_HEALTH_FreshProcessProtocol" }
    default { }
})
$expectedHealthCount = 1
if ($requiredHealthTests.Count -ne $expectedHealthCount) {
    throw "Internal phase-health mapping error for ${Phase}: expected " +
        "$expectedHealthCount prerequisite(s), got $($requiredHealthTests.Count)."
}
$classificationRaw = & $classifierPath `
    -ExitCode $exitCode `
    -LogPath $logPath `
    -ProjectPath $ProjectPath `
    -ResultPath $resultPath `
    -RequiredHealthTests $requiredHealthTests `
    -TimedOut:$timedOut
$classification = (($classificationRaw -join [Environment]::NewLine) |
    ConvertFrom-Json)

$unityProcessId = $null
$processEvidence = $null
$processEvidencePath = ""
if ($Phase -eq "Static") {
    $processEvidencePath = Join-Path $evidencePath "evaluator-health-static.json"
    if (Test-Path -LiteralPath $processEvidencePath -PathType Leaf) {
        try {
            $processEvidence = Get-Content -Raw -Encoding UTF8 `
                -LiteralPath $processEvidencePath | ConvertFrom-Json
            if ([int]$processEvidence.process_id -gt 0) {
                $unityProcessId = [int]$processEvidence.process_id
            }
        }
        catch { $unityProcessId = $null }
    }
} elseif ($Phase -eq "Dynamic") {
    $processEvidencePath = Join-Path $evidencePath "evaluator-health-dynamic.json"
    if (Test-Path -LiteralPath $processEvidencePath -PathType Leaf) {
        try {
            $processEvidence = Get-Content -Raw -Encoding UTF8 `
                -LiteralPath $processEvidencePath | ConvertFrom-Json
            if ([int]$processEvidence.process_id -gt 0) {
                $unityProcessId = [int]$processEvidence.process_id
            }
        }
        catch { $unityProcessId = $null }
    }
} elseif ($Phase -eq "Fresh") {
    $processEvidencePath = Join-Path $evidencePath "evaluator-health-fresh.json"
    if (Test-Path -LiteralPath $processEvidencePath -PathType Leaf) {
        try {
            $processEvidence = Get-Content -Raw -Encoding UTF8 `
                -LiteralPath $processEvidencePath | ConvertFrom-Json
            if ([int]$processEvidence.fresh_process_id -gt 0) {
                $unityProcessId = [int]$processEvidence.fresh_process_id
            }
        }
        catch { $unityProcessId = $null }
    }
}

if ([bool]$classification.health_prerequisites_passed) {
    $resolutionFailure = ""
    if ([string]::IsNullOrWhiteSpace($processEvidencePath) -or
        -not (Test-Path -LiteralPath $processEvidencePath -PathType Leaf)) {
        $resolutionFailure = "Required $Phase evaluator-health evidence is missing: " +
            $processEvidencePath
    } elseif ($null -eq $processEvidence) {
        $resolutionFailure = "Required $Phase evaluator-health evidence is unreadable: " +
            $processEvidencePath
    } elseif ([int]$processEvidence.screen_width -ne 1280 -or
              [int]$processEvidence.screen_height -ne 720 -or
              [int]$processEvidence.required_width -ne 1280 -or
              [int]$processEvidence.required_height -ne 720 -or
              -not [bool]$processEvidence.resolution_exact) {
        $resolutionFailure = "Required $Phase evaluator display was not proven at exact " +
            "1280x720. observed=$([int]$processEvidence.screen_width)x" +
            "$([int]$processEvidence.screen_height); required=" +
            "$([int]$processEvidence.required_width)x" +
            "$([int]$processEvidence.required_height); exact=" +
            "$([bool]$processEvidence.resolution_exact)."
    }
    if (-not [string]::IsNullOrWhiteSpace($resolutionFailure)) {
        $classification.execution_status = "infrastructure_error"
        $classification.failure_kind = "evaluator_health_failure"
        $classification.failure_reason = $resolutionFailure
        $classification.health_prerequisites_passed = $false
        $classification.health_validation_reasons = @(
            @($classification.health_validation_reasons) + $resolutionFailure)
        $classification.result_validation_reasons = @(
            @($classification.result_validation_reasons) + $resolutionFailure)
    }
}

$result = [pscustomobject]@{
    phase = $Phase
    phase_run_id = $runId
    started_utc = $startedUtc
    completed_utc = $completedUtc
    executor = "unity_cli_test"
    assembly = $assembly
    unity_process_id = $unityProcessId
    cli_process_id = [int]$processResult.process_id
    process_evidence = if ([string]::IsNullOrWhiteSpace($processEvidencePath)) {
        $null
    } else { $processEvidencePath }
    argument_transport = [string]$processResult.argument_transport
    exit_code = $exitCode
    timed_out = $timedOut
    timeout_seconds = $effectiveTimeoutSeconds
    execution_status = [string]$classification.execution_status
    failure_kind = [string]$classification.failure_kind
    failure_reason = [string]$classification.failure_reason
    compiler_errors = @($classification.compiler_errors)
    health_prerequisites = @($classification.health_prerequisites)
    health_prerequisites_passed = [bool]$classification.health_prerequisites_passed
    health_validation_reasons = @($classification.health_validation_reasons)
    result_xml_readable = [bool]$classification.result_xml_readable
    leaf_test_count = [int]$classification.leaf_test_count
    attributable_candidate_failures = @($classification.attributable_candidate_failures)
    unattributable_leaf_failures = @($classification.unattributable_leaf_failures)
    result_validation_reasons = @($classification.result_validation_reasons)
    result = $resultPath
    log = $logPath
    combined_cli_editor_log = $logPath
    evidence = $evidencePath
}

$result | ConvertTo-Json -Depth 4

if (-not $NoExitOnCompletion) {
    exit $exitCode
}
