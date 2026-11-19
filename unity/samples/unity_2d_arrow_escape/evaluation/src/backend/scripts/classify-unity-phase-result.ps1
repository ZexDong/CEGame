[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$ExitCode,

    [Parameter(Mandatory = $true)]
    [string]$LogPath,

    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [string]$ResultPath = "",

    [string[]]$RequiredHealthTests = @(),

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

# A failed licensing/entitlement check can cause Unity Package Manager to
# register none of the project's packages.  Unity then reports hundreds of
# perfectly real CS0246/CS0234 diagnostics under Assets because Input System,
# uGUI, NUnit and the public contract assembly have all disappeared from the
# compilation graph.  Those Assets diagnostics are consequences, not the root
# cause, so infrastructure markers must take precedence over path attribution.
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
$healthValidationReasons = [System.Collections.Generic.List[string]]::new()
$resultValidationReasons = [System.Collections.Generic.List[string]]::new()
$requiredHealthTests = @($RequiredHealthTests | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_)
})
$resultDocument = $null
$leafCases = @()
$resultXmlRequested = -not [string]::IsNullOrWhiteSpace($ResultPath)
$resultXmlReadable = $false

function Get-NUnitCaseMessage($Case) {
    if ($null -eq $Case) { return "" }
    foreach ($path in @("failure/message", "reason/message", "output")) {
        $node = $Case.SelectSingleNode($path)
        if ($null -ne $node -and
            -not [string]::IsNullOrWhiteSpace([string]$node.InnerText)) {
            return ([string]$node.InnerText).Trim()
        }
    }
    return ""
}

function Get-NUnitCaseDiagnosticText($Case) {
    if ($null -eq $Case) { return "" }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @(
        "failure/message",
        "failure/stack-trace",
        "reason/message",
        "output")) {
        $node = $Case.SelectSingleNode($path)
        if ($null -ne $node -and
            -not [string]::IsNullOrWhiteSpace([string]$node.InnerText)) {
            $parts.Add(([string]$node.InnerText).Trim())
        }
    }
    return ($parts -join "`n")
}

function Get-CandidateRuntimeFrame($Case) {
    if ($null -eq $Case -or
        (Get-XmlAttributeValue $Case "result") -ne "Failed") {
        return ""
    }
    $method = Get-XmlAttributeValue $Case "methodname"
    if ([string]::IsNullOrWhiteSpace($method)) {
        $method = Get-XmlAttributeValue $Case "name"
    }
    # Only formal candidate-facing leaves may use this attribution. Evaluator
    # health/regression failures remain infrastructure-invalid even if a
    # candidate frame appears deeper in their stack.
    if ($method -notmatch '^(?:STATIC\d+|TRAJ\d+|FRESH\d+)') {
        return ""
    }
    $site = Get-XmlAttributeValue $Case "site"
    $label = Get-XmlAttributeValue $Case "label"
    if ($site -match '^(?i:SetUp|TearDown)$' -or
        $label -match '^(?i:Error|Cancelled)$') {
        return ""
    }

    $diagnostic = Get-NUnitCaseDiagnosticText $Case
    foreach ($pattern in @(
        '(?im)\(at\s+(?<frame>Assets[\\/][^)\r\n]+\.cs:\d+)\)',
        '(?im)\bin\s+(?<frame>[A-Za-z]:[\\/][^\r\n]*[\\/]Assets[\\/][^:\r\n]+\.cs:\d+)')) {
        $match = [regex]::Match($diagnostic, $pattern)
        if ($match.Success) {
            return [string]$match.Groups["frame"].Value
        }
    }
    return ""
}

function Get-XmlAttributeValue($Node, [string]$Name) {
    if ($null -eq $Node -or [string]::IsNullOrWhiteSpace($Name)) { return "" }
    if ($Node -is [System.Xml.XmlElement]) {
        return [string]$Node.GetAttribute($Name)
    }
    try {
        $attribute = $Node.Attributes.GetNamedItem($Name)
        return if ($null -eq $attribute) { "" } else { [string]$attribute.Value }
    }
    catch { return "" }
}

if ($resultXmlRequested) {
    if (-not (Test-Path -LiteralPath $ResultPath -PathType Leaf)) {
        $resultValidationReasons.Add("NUnit result XML is missing: $ResultPath")
    } else {
        try {
            [xml]$resultDocument = Get-Content -Raw -Encoding UTF8 `
                -LiteralPath $ResultPath
            # Only leaf cases determine attribution. NUnit parent suites can be
            # Failed with label=Child merely because one child failed; counting
            # both would duplicate one candidate assertion and can obscure a
            # genuine SetUp/TearDown evaluator error.
            $leafCases = @($resultDocument.SelectNodes(
                "//test-case[not(descendant::test-case)]"))
            if ($leafCases.Count -eq 0) {
                $resultValidationReasons.Add(
                    "NUnit result XML contains no leaf test cases.")
            } else {
                $resultXmlReadable = $true
            }
        }
        catch {
            $resultValidationReasons.Add(
                "NUnit result XML is unreadable: $($_.Exception.Message)")
        }
    }
}

if ($requiredHealthTests.Count -gt 0) {
    if (-not $resultXmlReadable) {
        $healthValidationReasons.Add(
            "Required evaluator-health result XML is unavailable: $ResultPath")
    } else {
        foreach ($healthTest in $requiredHealthTests) {
            $matches = @($leafCases | Where-Object {
                (Get-XmlAttributeValue $_ "methodname") -eq $healthTest -or
                (Get-XmlAttributeValue $_ "name") -eq $healthTest
            })
            if ($matches.Count -ne 1) {
                $healthValidationReasons.Add(
                    "Expected exactly one evaluator-health test $healthTest, " +
                    "found $($matches.Count).")
            } elseif ((Get-XmlAttributeValue $matches[0] "result") -ne "Passed") {
                $healthValidationReasons.Add(
                    "Evaluator-health test $healthTest returned " +
                    "'$(Get-XmlAttributeValue $matches[0] 'result')': " +
                    (Get-NUnitCaseMessage $matches[0]))
            }
        }
    }
}

$allowedCandidateMarkers = @(
    "[OMNIGAME_CANDIDATE_STATIC]",
    "[OMNIGAME_CANDIDATE_DYNAMIC]",
    "[OMNIGAME_CANDIDATE_FRESH]",
    "[OMNIGAME_EVALUATOR_UNSUPPORTED]"
)
$failedLeafCases = @($leafCases | Where-Object {
    (Get-XmlAttributeValue $_ "result") -eq "Failed"
})
$attributableCandidateFailures = [System.Collections.Generic.List[object]]::new()
$unattributableLeafFailures = [System.Collections.Generic.List[object]]::new()
foreach ($case in $failedLeafCases) {
    $message = Get-NUnitCaseMessage $case
    $site = Get-XmlAttributeValue $case "site"
    $label = Get-XmlAttributeValue $case "label"
    $marked = @($allowedCandidateMarkers | Where-Object {
        $message.Contains($_)
    }).Count -gt 0
    $setupOrEvaluatorError = $site -match '^(?i:SetUp|TearDown)$' -or
        $label -match '^(?i:Error|Cancelled)$'
    $candidateRuntimeFrame = if ($setupOrEvaluatorError) { "" } else {
        Get-CandidateRuntimeFrame $case
    }
    $candidateRuntimeFailure =
        -not [string]::IsNullOrWhiteSpace($candidateRuntimeFrame)
    $record = [pscustomobject]@{
        id = if (-not [string]::IsNullOrWhiteSpace(
                (Get-XmlAttributeValue $case "methodname"))) {
            Get-XmlAttributeValue $case "methodname"
        } else { Get-XmlAttributeValue $case "name" }
        site = $site
        label = $label
        message = $message
        attribution = if ($marked) {
            "candidate_marker"
        } elseif ($candidateRuntimeFailure) {
            "candidate_runtime_exception_assets_stack"
        } else { $null }
        candidate_runtime_frame = if ($candidateRuntimeFailure) {
            $candidateRuntimeFrame
        } else { $null }
    }
    if (($marked -or $candidateRuntimeFailure) -and
        -not $setupOrEvaluatorError) {
        $attributableCandidateFailures.Add($record)
    } else {
        $unattributableLeafFailures.Add($record)
    }
}
foreach ($case in @($leafCases | Where-Object {
    (Get-XmlAttributeValue $_ "result") -notin @("Passed", "Failed")
})) {
    $unattributableLeafFailures.Add([pscustomobject]@{
        id = if (-not [string]::IsNullOrWhiteSpace(
                (Get-XmlAttributeValue $case "methodname"))) {
            Get-XmlAttributeValue $case "methodname"
        } else { Get-XmlAttributeValue $case "name" }
        site = Get-XmlAttributeValue $case "site"
        label = Get-XmlAttributeValue $case "label"
        message = "Unsupported NUnit result '$(Get-XmlAttributeValue $case 'result')': " +
            (Get-NUnitCaseMessage $case)
    })
}
if ($resultXmlReadable -and $unattributableLeafFailures.Count -gt 0) {
    foreach ($failure in $unattributableLeafFailures) {
        $resultValidationReasons.Add(
            "Unattributable NUnit leaf failure $($failure.id) " +
            "(site=$($failure.site), label=$($failure.label)): $($failure.message)")
    }
}

$evaluatorHealthFailure = $healthValidationReasons.Count -gt 0
$resultInfrastructureFailure = $resultXmlRequested -and
    ($resultValidationReasons.Count -gt 0)
$candidateTestFailure = $resultXmlReadable -and
    $attributableCandidateFailures.Count -gt 0 -and
    $unattributableLeafFailures.Count -eq 0
$executionStatus = if ($hasLicenseOrEntitlementFailure) {
    "infrastructure_error"
} elseif ($hasPackageManagerInfrastructureFailure) {
    "infrastructure_error"
} elseif ($TimedOut) {
    "infrastructure_error"
} elseif ($evaluatorHealthFailure) {
    "infrastructure_error"
} elseif ($compilerErrors.Count -gt 0) {
    "candidate_failed"
} elseif ($resultInfrastructureFailure) {
    "infrastructure_error"
} elseif ($candidateTestFailure -and $ExitCode -in @(0, 2, 6)) {
    "candidate_failed"
} elseif ($ExitCode -eq 0) {
    "passed"
} else {
    "infrastructure_error"
}
$failureKind = if ($hasLicenseOrEntitlementFailure) {
    "unity_license_or_entitlement_error"
} elseif ($hasPackageManagerInfrastructureFailure) {
    "unity_package_manager_error"
} elseif ($TimedOut) {
    "unity_process_timeout"
} elseif ($evaluatorHealthFailure) {
    "evaluator_health_failure"
} elseif ($compilerErrors.Count -gt 0) {
    "candidate_compilation_error"
} elseif ($resultInfrastructureFailure) {
    "nunit_result_infrastructure_failure"
} elseif ($candidateTestFailure -and $ExitCode -in @(0, 2, 6)) {
    "test_failure"
} elseif ($ExitCode -eq 0) {
    "none"
} else {
    "unity_process_error"
}
$failureReason = if ($failureKind -eq "unity_license_or_entitlement_error") {
    "Unity licensing or package entitlement failed before the candidate could be evaluated reliably."
} elseif ($failureKind -eq "unity_package_manager_error") {
    "Unity Package Manager failed before protected project dependencies could be evaluated reliably."
} elseif ($failureKind -eq "unity_process_timeout") {
    "Unity exceeded the bounded runner timeout without a reliable candidate attribution."
} elseif ($failureKind -eq "evaluator_health_failure") {
    "Evaluator health prerequisites failed; this run is invalid and cannot reduce candidate score. " +
    ($healthValidationReasons -join " | ")
} elseif ($failureKind -eq "nunit_result_infrastructure_failure") {
    "NUnit completed without a safely attributable candidate result. " +
    ($resultValidationReasons -join " | ")
} elseif ($failureKind -eq "candidate_compilation_error") {
    "Candidate-owned C# compiler errors were found under the project Assets directory."
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
    health_prerequisites = @($requiredHealthTests)
    health_prerequisites_passed = -not $evaluatorHealthFailure
    health_validation_reasons = @($healthValidationReasons)
    result_xml_requested = $resultXmlRequested
    result_xml_readable = $resultXmlReadable
    result_validation_reasons = @($resultValidationReasons)
    leaf_test_count = $leafCases.Count
    failed_leaf_test_count = $failedLeafCases.Count
    attributable_candidate_failures = @($attributableCandidateFailures)
    unattributable_leaf_failures = @($unattributableLeafFailures)
    compiler_errors = @($reportedCompilerErrors)
    suppressed_downstream_assets_error_count = if (
        $executionStatus -eq "infrastructure_error") {
        $compilerErrors.Count
    } else {
        0
    }
} | ConvertTo-Json -Depth 6
