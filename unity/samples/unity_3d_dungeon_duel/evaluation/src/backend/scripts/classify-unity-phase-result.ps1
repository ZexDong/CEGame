[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$ExitCode,

    [Parameter(Mandatory = $true)]
    [string]$LogPath,

    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [ValidateSet("", "Static", "Dynamic", "Fresh", "BaselineCompile")]
    [string]$Phase = "",

    [string]$ResultPath = "",

    [string]$RulesPath = "",

    [switch]$TimedOut
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath($ProjectPath)
$assetsRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "Assets"))
$assetsPrefix = $assetsRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar) +
    [System.IO.Path]::DirectorySeparatorChar

$logText = if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
    Get-Content -Raw -Encoding UTF8 -LiteralPath $LogPath
} else {
    ""
}
$resultXmlReadable = $false
$resultTestCaseCount = 0
if (-not [string]::IsNullOrWhiteSpace($ResultPath) -and
    (Test-Path -LiteralPath $ResultPath -PathType Leaf)) {
    try {
        [xml]$resultDocument = Get-Content -Raw -Encoding UTF8 -LiteralPath $ResultPath
        $resultTestCaseCount = @($resultDocument.SelectNodes("//test-case")).Count
        $resultXmlReadable = $resultTestCaseCount -gt 0
    }
    catch {
        $resultXmlReadable = $false
        $resultTestCaseCount = 0
    }
}

$hasLicenseOrEntitlementFailure = (
    $logText -match '(?im)^LICENSE SYSTEM: No valid Unity Editor license found\.' -or
    $logText -match '(?im)^\[Package Manager\] The following packages were not registered because your license doesn''t allow it\.' -or
    (
        $logText -match '(?im)^\[Package Manager\] Unknown entitlement status \[0\] for package ' -and
        $logText -match '(?im)^\[Package Manager\] Registered 0 packages:'
    )
)
$hasPackageManagerInfrastructureFailure = (
    $logText -match '(?im)^\[Package Manager\].*\b(?:error|failed|unable)\b' -or
    $logText -match '(?im)^(?:An error occurred while resolving packages|Error while resolving packages|Failed to resolve packages)'
)

if ([string]::IsNullOrWhiteSpace($RulesPath)) {
    $RulesPath = Join-Path (Split-Path -Parent $PSScriptRoot) "rules.json"
}

$evaluatorHealthFailure = $false
$evaluatorHealthReason = ""
if (($Phase -eq "Dynamic" -or $Phase -eq "Fresh") -and
    (Test-Path -LiteralPath $RulesPath -PathType Leaf)) {
    try {
        $rules = Get-Content -Raw -Encoding UTF8 -LiteralPath $RulesPath |
            ConvertFrom-Json
        $phaseKey = $Phase.ToLowerInvariant()
        $healthRule = $rules.health_prerequisites.PSObject.Properties[$phaseKey].Value
        $requiredHealthTests = @($healthRule.required_tests | ForEach-Object { [string]$_ })
        if ($requiredHealthTests.Count -eq 0) {
            $evaluatorHealthFailure = $true
            $evaluatorHealthReason = "$Phase has no declared evaluator-health prerequisites."
        } elseif (-not (Test-Path -LiteralPath $ResultPath -PathType Leaf)) {
            $evaluatorHealthFailure = $true
            $evaluatorHealthReason = "$Phase produced no NUnit XML for evaluator-health verification."
        } else {
            [xml]$healthDocument = Get-Content -Raw -Encoding UTF8 -LiteralPath $ResultPath
            $healthCases = @($healthDocument.SelectNodes("//test-case"))
            $healthProblems = [System.Collections.Generic.List[string]]::new()
            foreach ($testName in $requiredHealthTests) {
                $matches = @($healthCases | Where-Object {
                    ([string]$_.methodname -eq $testName) -or
                    ([string]$_.name -eq $testName)
                })
                if ($matches.Count -ne 1) {
                    $healthProblems.Add("$testName count=$($matches.Count)")
                } elseif ([string]$matches[0].result -ne "Passed") {
                    $healthProblems.Add("$testName result=$([string]$matches[0].result)")
                }
            }
            if ($healthProblems.Count -gt 0) {
                $evaluatorHealthFailure = $true
                $evaluatorHealthReason = "$Phase evaluator-health prerequisite failure: " +
                    ($healthProblems -join "; ")
            }
        }
    }
    catch {
        $evaluatorHealthFailure = $true
        $evaluatorHealthReason = "$Phase evaluator-health verification threw: " +
            $_.Exception.Message
    }
}

function Get-CandidateCompilerErrors {
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        return @()
    }

    $errors = [System.Collections.Generic.List[object]]::new()
    $pattern = '^(?<path>.*?\.cs)\((?<line>\d+),(?<column>\d+)\):\s*error\s+(?<code>CS\d+)\s*:\s*(?<message>.*)$'
    foreach ($logLine in @(Get-Content -Encoding UTF8 -LiteralPath $LogPath)) {
        if ($logLine -notmatch $pattern) {
            continue
        }

        $reportedPath = ([string]$Matches.path).Trim().Trim('"')
        $normalizedPath = $reportedPath.Replace(
            [System.IO.Path]::AltDirectorySeparatorChar,
            [System.IO.Path]::DirectorySeparatorChar)
        while ($normalizedPath.StartsWith("." + [System.IO.Path]::DirectorySeparatorChar)) {
            $normalizedPath = $normalizedPath.Substring(2)
        }

        try {
            $absolutePath = if ([System.IO.Path]::IsPathRooted($normalizedPath)) {
                [System.IO.Path]::GetFullPath($normalizedPath)
            } else {
                [System.IO.Path]::GetFullPath((Join-Path $projectRoot $normalizedPath))
            }
        }
        catch {
            continue
        }

        if (-not $absolutePath.StartsWith(
                $assetsPrefix,
                [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $errors.Add([pscustomobject]@{
            path = $reportedPath
            line = [int]$Matches.line
            column = [int]$Matches.column
            code = [string]$Matches.code
            message = ([string]$Matches.message).Trim()
        })
    }
    return @($errors)
}

$compilerErrors = @(Get-CandidateCompilerErrors)
$knownInputSystemMismatch = $false
$inputMismatchEvidence = @()
if ($logText -match '(?is)InvalidOperationException.*UnityEngine\.Input|You are trying to read Input using the UnityEngine\.Input class') {
    $settingsPath = Join-Path $projectRoot 'ProjectSettings\ProjectSettings.asset'
    $handlerNewOnly = $false
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $settingsText = Get-Content -Raw -Encoding UTF8 -LiteralPath $settingsPath
        $handlerNewOnly = $settingsText -match '(?m)^\s*activeInputHandler:\s*1\s*$'
    }
    $candidateSourceRoot = Join-Path $assetsRoot 'DungeonDuelBenchmark'
    $legacyApiFiles = @()
    if (Test-Path -LiteralPath $candidateSourceRoot -PathType Container) {
        # The legacy class is often referenced through `using UnityEngine;` and
        # therefore appears as `Input.GetKeyDown(...)`, not as the fully
        # qualified `UnityEngine.Input.GetKeyDown(...)`.  Match both spellings,
        # while excluding identifiers such as InputAction/InputSystem.  This is
        # source corroboration only; the log diagnostic and activeInputHandler
        # setting are still required before this becomes a candidate failure.
        $legacyApiPattern = '(?<![A-Za-z0-9_\.])(?:UnityEngine\.)?Input\s*\.\s*(?:GetKey|GetKeyDown|GetKeyUp|GetMouseButton|GetMouseButtonDown|GetMouseButtonUp|mousePosition|mouseScrollDelta|touchCount|GetTouch|GetAxis|GetAxisRaw|GetButton|GetButtonDown|GetButtonUp|anyKey|anyKeyDown)\b'
        $legacyApiFiles = @(Get-ChildItem -LiteralPath $candidateSourceRoot -Recurse -File -Filter '*.cs' |
            Select-String -Pattern $legacyApiPattern |
            Select-Object -ExpandProperty Path -Unique)
    }
    if ($handlerNewOnly -and $legacyApiFiles.Count -gt 0) {
        $knownInputSystemMismatch = $true
        $inputMismatchEvidence = [pscustomobject]@{
            active_input_handler = 1
            legacy_api_files = @($legacyApiFiles)
            rule = 'candidate Assets/DungeonDuelBenchmark uses legacy UnityEngine.Input while activeInputHandler=1'
        }
    }
}
$executionStatus = if ($hasLicenseOrEntitlementFailure) {
    "infrastructure_error"
} elseif ($hasPackageManagerInfrastructureFailure) {
    "infrastructure_error"
} elseif ($TimedOut) {
    "infrastructure_error"
} elseif ($compilerErrors.Count -gt 0) {
    "candidate_failed"
} elseif ($evaluatorHealthFailure) {
    "infrastructure_error"
} elseif ($knownInputSystemMismatch) {
    "candidate_failed"
} elseif ($ExitCode -eq 0) {
    "passed"
} elseif ($resultXmlReadable -or $ExitCode -eq 2) {
    "candidate_failed"
} else {
    "infrastructure_error"
}
$failureKind = if ($hasLicenseOrEntitlementFailure) {
    "unity_license_or_entitlement_error"
} elseif ($hasPackageManagerInfrastructureFailure) {
    "unity_package_manager_error"
} elseif ($TimedOut) {
    "unity_process_timeout"
} elseif ($compilerErrors.Count -gt 0) {
    "candidate_compilation_error"
} elseif ($evaluatorHealthFailure) {
    "evaluator_health_failure"
} elseif ($knownInputSystemMismatch) {
    "candidate_input_api_mismatch"
} elseif ($ExitCode -eq 0) {
    "none"
} elseif ($resultXmlReadable -or $ExitCode -eq 2) {
    "test_failure"
} else {
    "unity_process_error"
}
$failureReason = if ($failureKind -eq "candidate_input_api_mismatch") {
    "Candidate uses legacy UnityEngine.Input polling while activeInputHandler=1 (Input System only); this is a candidate-owned compatibility failure."
} elseif ($failureKind -eq "unity_license_or_entitlement_error") {
    "Unity licensing or package entitlement failed before the candidate could be evaluated reliably."
} elseif ($failureKind -eq "unity_package_manager_error") {
    "Unity Package Manager failed before protected project dependencies could be evaluated reliably."
} elseif ($failureKind -eq "unity_process_timeout") {
    "Unity exceeded the bounded runner timeout without a reliable candidate attribution."
} elseif ($failureKind -eq "candidate_compilation_error") {
    "Candidate-owned C# compiler errors were found under the project Assets directory."
} elseif ($failureKind -eq "evaluator_health_failure") {
    $evaluatorHealthReason
} elseif ($failureKind -eq "test_failure") {
    "Unity completed the test run and reported candidate test failures."
} elseif ($failureKind -eq "unity_process_error") {
    "Unity exited abnormally without an attributable compiler error under candidate Assets."
} else {
    ""
}
$reportedCompilerErrors = if ($executionStatus -eq "infrastructure_error") {
    @()
} else {
    @($compilerErrors)
}

[pscustomobject]@{
    exit_code = $ExitCode
    execution_status = $executionStatus
    failure_kind = $failureKind
    failure_reason = $failureReason
    timed_out = [bool]$TimedOut
    phase = $Phase
    evaluator_health_checked = $Phase -eq "Dynamic" -or $Phase -eq "Fresh"
    evaluator_health_failure = $evaluatorHealthFailure
    result_xml_readable = $resultXmlReadable
    result_test_case_count = $resultTestCaseCount
    compiler_errors = @($reportedCompilerErrors)
    input_system_mismatch_evidence = $inputMismatchEvidence
    suppressed_downstream_assets_error_count = if (
        $executionStatus -eq "infrastructure_error") {
        $compilerErrors.Count
    } else {
        0
    }
} | ConvertTo-Json -Depth 6

