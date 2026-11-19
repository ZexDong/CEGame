[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][int]$ExitCode,
    [Parameter(Mandatory = $true)][string]$LogPath,
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [ValidateSet("Baseline", "Test")][string]$InvocationKind = "Test",
    [string]$ResultPath = "",
    [string[]]$EvaluatorHealthTestIds = @(),
    [switch]$TimedOut
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath($ProjectPath)
$assetsRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "Assets"))
$assetsPrefix = $assetsRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$logText = if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
    Get-Content -Raw -Encoding UTF8 -LiteralPath $LogPath
} else { "" }

$licenseFailure = $logText -match '(?im)No valid Unity Editor license|LICENSE SYSTEM.*(?:error|failed)' 
$packageInfrastructureFailure = $logText -match '(?im)(?:Unable to connect to package manager|Failed to connect to Unity Package Manager|upm.*timed out)'
$healthFailures = [System.Collections.Generic.List[string]]::new()
$observationUnsupported = [System.Collections.Generic.List[string]]::new()
$evaluatorInfrastructureFailures = [System.Collections.Generic.List[string]]::new()
$candidateVerdicts = [System.Collections.Generic.List[string]]::new()
$candidateFeatureMissingCount = 0
$candidateBlockedCount = 0
$ordinaryFailedTestCount = 0
if ($InvocationKind -eq "Test" -and $EvaluatorHealthTestIds.Count -gt 0 -and
    -not [string]::IsNullOrWhiteSpace($ResultPath) -and
    (Test-Path -LiteralPath $ResultPath -PathType Leaf)) {
    try {
        [xml]$healthXml = Get-Content -Raw -Encoding UTF8 -LiteralPath $ResultPath
        $healthCases = @($healthXml.SelectNodes("//test-case"))
        foreach ($healthId in $EvaluatorHealthTestIds) {
            $matches = @($healthCases | Where-Object {
                [string]$_.methodname -eq $healthId -or [string]$_.name -eq $healthId
            })
            if ($matches.Count -ne 1) {
                $healthFailures.Add("$healthId expected once, found $($matches.Count)")
            } elseif ([string]$matches[0].result -ne "Passed") {
                $healthFailures.Add("$healthId returned $([string]$matches[0].result)")
            }
        }
    } catch {
        $healthFailures.Add("health NUnit XML unreadable: $($_.Exception.Message)")
    }
}
if ($InvocationKind -eq "Test" -and
    -not [string]::IsNullOrWhiteSpace($ResultPath) -and
    (Test-Path -LiteralPath $ResultPath -PathType Leaf)) {
    try {
        [xml]$resultXml = Get-Content -Raw -Encoding UTF8 -LiteralPath $ResultPath
        foreach ($case in @($resultXml.SelectNodes("//test-case"))) {
            $result = [string]$case.result
            $messageNode = $case.SelectSingleNode("failure/message")
            if ($null -eq $messageNode) { $messageNode = $case.SelectSingleNode("reason/message") }
            $message = if ($null -eq $messageNode) { "" } else { ([string]$messageNode.InnerText).Trim() }
            $stackNode = $case.SelectSingleNode("failure/stack-trace")
            $stackTrace = if ($null -eq $stackNode) { "" } else {
                ([string]$stackNode.InnerText).Trim()
            }
            $label = [string]$case.label
            $id = if (-not [string]::IsNullOrWhiteSpace([string]$case.methodname)) {
                [string]$case.methodname
            } else { [string]$case.name }
            $candidateFeatureMissing =
                $message.Contains("[OMNIGAME_CANDIDATE_FEATURE_MISSING]") -or
                $label.Contains("OMNIGAME_CANDIDATE_FEATURE_MISSING")
            $candidateBlocked =
                $message.Contains("[OMNIGAME_CANDIDATE_BLOCKED]") -or
                $label.Contains("OMNIGAME_CANDIDATE_BLOCKED")
            $evaluatorObservationFault =
                $message.Contains("[OMNIGAME_EVALUATOR_UNOBSERVABLE]") -or
                $label.Contains("OMNIGAME_EVALUATOR_UNOBSERVABLE")
            $markedEvaluatorInfrastructure =
                ($message.Contains("[OMNIGAME_EVALUATOR_INFRASTRUCTURE]") -or
                 $label.Contains("OMNIGAME_EVALUATOR_INFRASTRUCTURE")) -and
                ($stackTrace -match '(?i)(OmniGame\.Benchmark\.SignCircuit\.Evaluator|_private-evaluator-package)')
            $inputSystemDeviceAssertion =
                $message -match "(?i)^Unhandled log message:\s*'\[Assert\]\s*(?:Action|Map|Binding|Composite) count in old and new state must be the same" -and
                $stackTrace -match '(?i)UnityEngine\.InputSystem\.InputSystem:(?:AddDevice|RemoveDevice|EnableDevice|DisableDevice)' -and
                $stackTrace -match '(?i)OmniGame\.Benchmark\.SignCircuit\.Evaluator\.NativeInputDriver[/\\.<].*(?:Initialize|Dispose)' -and
                $stackTrace -match '(?i)_private-evaluator-package[\\/]+Tests[\\/]+Dynamic[\\/]+NativeInputDriver\.cs'
            if (($result -in @("Failed", "Inconclusive", "Skipped")) -and
                ($markedEvaluatorInfrastructure -or $inputSystemDeviceAssertion)) {
                $kind = if ($inputSystemDeviceAssertion) {
                    "input_system_internal_device_assertion"
                } else { "marked_evaluator_runtime_failure" }
                $evaluatorInfrastructureFailures.Add("$($id): ${kind}: $message")
                continue
            }
            if (($result -in @("Failed", "Inconclusive", "Skipped")) -and
                $evaluatorObservationFault -and
                ($candidateFeatureMissing -or $candidateBlocked)) {
                $observationUnsupported.Add(
                    "$($id): conflicting candidate and evaluator-fault markers: $message")
                continue
            }
            if (($result -in @("Failed", "Inconclusive", "Skipped")) -and
                ($candidateFeatureMissing -or $candidateBlocked)) {
                $kind = if ($candidateFeatureMissing) {
                    $candidateFeatureMissingCount++
                    "candidate_feature_missing"
                } else {
                    $candidateBlockedCount++
                    "candidate_blocked"
                }
                $candidateVerdicts.Add("$($id): ${kind}: $message")
                continue
            }
            if (($result -in @("Inconclusive", "Skipped")) -and
                $evaluatorObservationFault) {
                $observationUnsupported.Add("$($id): $message")
                continue
            }
            if ($result -eq "Failed") {
                # The Unity CLI exit code is a transport detail and has varied
                # across wrapper versions. A readable non-health Failed leaf is
                # passed to the scorer, which owns the final candidate-vs-fixture
                # decision from NUnit site/label/markers and evidence.
                $ordinaryFailedTestCount++
            }
        }
    } catch {
        # The scorer and health gates separately reject unreadable NUnit XML.
    }
}
$compilerErrors = [System.Collections.Generic.List[object]]::new()
$pattern = '^(?<path>.*?\.cs)\((?<line>\d+),(?<column>\d+)\):\s*error\s+(?<code>CS\d+)\s*:\s*(?<message>.*)$'
if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
    foreach ($line in @(Get-Content -Encoding UTF8 -LiteralPath $LogPath)) {
        if ($line -notmatch $pattern) { continue }
        $reported = ([string]$Matches.path).Trim().Trim('"')
        try {
            $absolute = if ([System.IO.Path]::IsPathRooted($reported)) {
                [System.IO.Path]::GetFullPath($reported)
            } else {
                [System.IO.Path]::GetFullPath((Join-Path $projectRoot $reported))
            }
        } catch { continue }
        if (-not $absolute.StartsWith($assetsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $compilerErrors.Add([pscustomobject]@{
            path = $reported
            line = [int]$Matches.line
            column = [int]$Matches.column
            code = [string]$Matches.code
            message = ([string]$Matches.message).Trim()
        })
    }
}

$status = if ($licenseFailure -or $packageInfrastructureFailure -or $TimedOut -or
    $observationUnsupported.Count -gt 0 -or
    $evaluatorInfrastructureFailures.Count -gt 0 -or
    $healthFailures.Count -gt 0) {
    "infrastructure_error"
} elseif ($compilerErrors.Count -gt 0 -or
    $candidateVerdicts.Count -gt 0 -or
    $ordinaryFailedTestCount -gt 0 -or
    ($InvocationKind -eq "Test" -and $ExitCode -eq 2)) {
    "candidate_failed"
} elseif ($ExitCode -eq 0) {
    "passed"
} else {
    "infrastructure_error"
}
$kind = if ($licenseFailure) {
    "unity_license_error"
} elseif ($packageInfrastructureFailure) {
    "unity_package_manager_error"
} elseif ($TimedOut) {
    "unity_process_timeout"
} elseif ($observationUnsupported.Count -gt 0) {
    "evaluator_observation_unsupported"
} elseif ($evaluatorInfrastructureFailures.Count -gt 0) {
    "evaluator_runtime_failure"
} elseif ($healthFailures.Count -gt 0) {
    "evaluator_health_failure"
} elseif ($compilerErrors.Count -gt 0) {
    "candidate_compilation_error"
} elseif ($candidateFeatureMissingCount -gt 0) {
    "candidate_feature_missing"
} elseif ($candidateBlockedCount -gt 0) {
    "candidate_blocked"
} elseif ($InvocationKind -eq "Test" -and $ExitCode -eq 2) {
    "test_failure"
} elseif ($ExitCode -eq 0) {
    "none"
} else {
    "unity_process_error"
}

[pscustomobject]@{
    exit_code = $ExitCode
    execution_status = $status
    failure_kind = $kind
    timed_out = [bool]$TimedOut
    compiler_errors = @($compilerErrors)
    evaluator_health_failures = @($healthFailures)
    evaluator_observation_unsupported = @($observationUnsupported)
    evaluator_infrastructure_failures = @($evaluatorInfrastructureFailures)
    candidate_verdicts = @($candidateVerdicts)
    ordinary_failed_test_count = $ordinaryFailedTestCount
} | ConvertTo-Json -Depth 6
