[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StaticResultPath,
    [string]$DynamicResultPath = "",
    [string]$FreshResultPath = "",
    [string]$EvidenceDirectory = "",
    [string]$EvaluationSessionId = "",
    [int]$DynamicProcessId = 0,
    [int]$FreshProcessId = 0,
    [string]$DynamicStartedUtc = "",
    [string]$DynamicCompletedUtc = "",
    [string]$FreshStartedUtc = "",
    [string]$FreshCompletedUtc = "",
    [string]$VisualResultPath = "",
    [string]$VisualEvidenceDirectory = "",
    [string]$VisualRoot = "",
    [string]$ProjectPath = "",
    [string]$RulesPath = "",
    [string]$HashBindingPath = "",
    [string]$OutputPath = "",
    [switch]$NoExitOnInvalid
)

$ErrorActionPreference = "Stop"
$evaluationRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RulesPath)) {
    $RulesPath = Join-Path $evaluationRoot "rules.json"
}
$RulesPath = (Resolve-Path -LiteralPath $RulesPath).Path
$StaticResultPath = (Resolve-Path -LiteralPath $StaticResultPath).Path
$rules = Get-Content -Raw -Encoding UTF8 -LiteralPath $RulesPath | ConvertFrom-Json
$visualFileRoot = if ([string]::IsNullOrWhiteSpace($VisualRoot)) {
    $evaluationRoot
} else {
    (Resolve-Path -LiteralPath $VisualRoot).Path
}
$validation = [System.Collections.Generic.List[string]]::new()
$candidateStaticMarker = "[OMNIGAME_SIGN_CIRCUIT_CANDIDATE_STATIC]"
$candidateFeatureMissingMarker = "[OMNIGAME_CANDIDATE_FEATURE_MISSING]"
$candidateBlockedMarker = "[OMNIGAME_CANDIDATE_BLOCKED]"
$evaluatorObservationMarker = "[OMNIGAME_EVALUATOR_UNOBSERVABLE]"
$evaluatorInfrastructureMarker = "[OMNIGAME_EVALUATOR_INFRASTRUCTURE]"

function Add-Validation([string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Message) -and
        -not $validation.Contains($Message)) { $validation.Add($Message) }
}
function Get-DirectFailureMessage($Node) {
    if ($null -eq $Node) { return "" }
    $failure = $Node.SelectSingleNode("./failure")
    if ($null -eq $failure) { return "" }
    $messageNode = $failure.SelectSingleNode("message")
    if ($null -eq $messageNode) { return "<no message>" }
    return ([string]$messageNode.InnerText).Trim()
}
function Get-ParentNUnitResult($Node) {
    $raw = if ($null -eq $Node) { "" } else { [string]$Node.result }
    $match = [regex]::Match($raw,
        '^\s*Failed\s*\(\s*Child\s*\)\s*$',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return [pscustomobject]@{
        raw = $raw
        base_result = if ($match.Success) { "Failed" } else { $raw }
        child_aggregate = $match.Success
    }
}
function Test-IsChildAggregateFailure($Node, [string]$Message) {
    if ($null -eq $Node) { return $false }
    $site = [string]$Node.site
    if ($site -match '(?i)^child$') { return $true }
    return $Message -match
        '(?i)(?:one or more|some) child tests?.*(?:failed|errors?)|child tests?.*(?:failed|errors?)'
}
function Test-HasNUnitInfrastructureSite($Node, [string]$Message = "") {
    if ($null -eq $Node) { return $false }
    $site = [string]$Node.site
    # NUnit uses site=Child for an aggregate parent whose explicit child testcase
    # carries the real candidate verdict. It is not itself a fixture failure.
    if ($site -match '(?i)^child$') { return $false }
    if ($site -match '(?i)(setup|teardown|parent)') { return $true }
    $label = [string]$Node.label
    return $label -match '(?i)^(error|cancelled|invalid)$' -and
        -not (Test-IsChildAggregateFailure $Node $Message)
}
function Test-HasExplicitCandidateMarker([string]$Message) {
    if ([string]::IsNullOrWhiteSpace($Message) -or
        $Message.Contains($evaluatorObservationMarker)) {
        return $false
    }
    return $Message.Contains($candidateStaticMarker) -or
        $Message.Contains($candidateFeatureMissingMarker) -or
        $Message.Contains($candidateBlockedMarker)
}
function Get-StackTrace($Case) {
    if ($null -eq $Case) { return "" }
    $stack = $Case.SelectSingleNode("failure/stack-trace")
    if ($null -eq $stack) { return "" }
    return ([string]$stack.InnerText).Trim()
}
function Test-IsEvaluatorInfrastructureFailure($Case, [string]$Message) {
    if ($null -eq $Case) { return $false }
    $stackTrace = Get-StackTrace $Case
    $label = [string]$Case.label
    $marked = ($Message.Contains($evaluatorInfrastructureMarker) -or
        $label.Contains("OMNIGAME_EVALUATOR_INFRASTRUCTURE")) -and
        $stackTrace -match
            '(?i)(OmniGame\.Benchmark\.SignCircuit\.Evaluator|_private-evaluator-package)'
    $inputSystemDeviceAssertion =
        $Message -match "(?i)^Unhandled log message:\s*'\[Assert\]\s*(?:Action|Map|Binding|Composite) count in old and new state must be the same" -and
        $stackTrace -match '(?i)UnityEngine\.InputSystem\.InputSystem:(?:AddDevice|RemoveDevice|EnableDevice|DisableDevice)' -and
        $stackTrace -match '(?i)OmniGame\.Benchmark\.SignCircuit\.Evaluator\.NativeInputDriver[/\\.<].*(?:Initialize|Dispose)' -and
        $stackTrace -match '(?i)_private-evaluator-package[\\/]+Tests[\\/]+Dynamic[\\/]+NativeInputDriver\.cs'
    return $marked -or $inputSystemDeviceAssertion
}
function Read-Cases([string]$Path, [string]$Phase, [bool]$Required) {
    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($Required) { Add-Validation "$Phase NUnit XML is required but missing." }
        return @()
    }
    try {
        [xml]$xml = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
        $roots = @($xml.SelectNodes("/test-run"))
        if ($roots.Count -ne 1) {
            Add-Validation "$Phase NUnit XML must contain exactly one test-run root; found $($roots.Count)."
            return @()
        }
        $root = $roots[0]
        $rootResultInfo = Get-ParentNUnitResult $root
        $rootResult = [string]$rootResultInfo.base_result
        if ($rootResult -notin @("Passed", "Failed")) {
            Add-Validation "$Phase NUnit test-run has unsupported root result '$($rootResultInfo.raw)'."
        }
        $cases = @($xml.SelectNodes("//test-case"))
        $nonPassedCases = @($cases | Where-Object {
            [string]$_.result -ne "Passed"
        })
        $rootMessage = Get-DirectFailureMessage $root
        $rootAggregate = [bool]$rootResultInfo.child_aggregate -or
            (Test-IsChildAggregateFailure $root $rootMessage)
        $rootInfrastructureReason = ""
        $rootCandidateMarked = Test-HasExplicitCandidateMarker $rootMessage
        if ($rootResult -eq "Failed" -and
            (Test-HasNUnitInfrastructureSite $root $rootMessage) -and
            -not $rootCandidateMarked) {
            $rootInfrastructureReason = "$Phase NUnit test-run failed in host/fixture " +
                "infrastructure (site='$([string]$root.site)', " +
                "label='$([string]$root.label)'): $rootMessage"
        } elseif ($rootResult -eq "Failed" -and
            -not [string]::IsNullOrWhiteSpace($rootMessage) -and
            -not $rootAggregate) {
            $rootInfrastructureReason =
                "$Phase NUnit test-run has a direct non-child failure: $rootMessage"
        }
        $suiteInfrastructureFound = $false
        foreach ($suite in @($xml.SelectNodes("//test-suite"))) {
            $suiteResultInfo = Get-ParentNUnitResult $suite
            $suiteResult = [string]$suiteResultInfo.base_result
            if ($suiteResult -notin @("Passed", "Failed", "Skipped", "Inconclusive")) {
                Add-Validation "$Phase NUnit suite '$([string]$suite.name)' has unsupported result '$($suiteResultInfo.raw)'."
            }
            $message = Get-DirectFailureMessage $suite
            $hasDirectFailure = -not [string]::IsNullOrWhiteSpace($message)
            $candidateMarked = Test-HasExplicitCandidateMarker $message
            $suiteAggregate = [bool]$suiteResultInfo.child_aggregate -or
                (Test-IsChildAggregateFailure $suite $message)
            if ((Test-HasNUnitInfrastructureSite $suite $message) -and
                -not $candidateMarked) {
                $suiteInfrastructureFound = $true
                Add-Validation ("$Phase NUnit fixture/assembly failure is evaluator-invalid: " +
                    "$([string]$suite.name) " +
                    "(site='$([string]$suite.site)', label='$([string]$suite.label)'): $message")
            } elseif ($hasDirectFailure -and -not $suiteAggregate -and
                -not $candidateMarked) {
                $suiteInfrastructureFound = $true
                Add-Validation ("$Phase NUnit fixture/assembly direct failure is evaluator-invalid: " +
                    "$([string]$suite.name): $message")
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($rootInfrastructureReason) -and
            -not $suiteInfrastructureFound) {
            Add-Validation $rootInfrastructureReason
        }
        if ($rootResult -eq "Failed" -and $rootAggregate -and
            $nonPassedCases.Count -eq 0 -and -not $suiteInfrastructureFound) {
            Add-Validation "$Phase NUnit test-run is Failed(Child) without a non-Passed child testcase."
        }
        foreach ($case in $cases) {
            $result = [string]$case.result
            if ($result -notin @("Passed", "Failed", "Skipped", "Inconclusive")) {
                Add-Validation "$Phase NUnit testcase '$([string]$case.name)' has unsupported result '$result'."
            }
            $site = [string]$case.site
            $label = [string]$case.label
            $caseMessage = Get-Message $case
            $candidateMarked = Test-HasExplicitCandidateMarker $caseMessage
            if ($result -ne "Passed" -and
                (Test-IsEvaluatorInfrastructureFailure $case $caseMessage)) {
                Add-Validation ("$Phase NUnit testcase '$([string]$case.name)' " +
                    "failed inside evaluator/Input System infrastructure and cannot " +
                    "be scored as a candidate failure: $caseMessage")
                continue
            }
            if ((Test-HasNUnitInfrastructureSite $case $caseMessage) -and
                -not $suiteInfrastructureFound -and -not $candidateMarked) {
                Add-Validation ("$Phase NUnit testcase '$([string]$case.name)' failed in " +
                    "fixture/host infrastructure (site='$site', label='$label').")
            }
            if ($result -eq "Passed" -and $null -ne $case.SelectSingleNode("failure")) {
                Add-Validation "$Phase NUnit testcase '$([string]$case.name)' is Passed but contains failure data."
            }
        }
        return $cases
    } catch {
        Add-Validation "$Phase NUnit XML is unreadable: $($_.Exception.Message)"
        return @()
    }
}
function Find-Case($Cases, [string]$Id) {
    @($Cases | Where-Object {
        [string]$_.methodname -eq $Id -or [string]$_.name -eq $Id
    })
}
function Get-Message($Case) {
    if ($null -eq $Case) { return "missing" }
    $failure = $Case.SelectSingleNode("failure/message")
    if ($null -ne $failure) { return ([string]$failure.InnerText).Trim() }
    $reason = $Case.SelectSingleNode("reason/message")
    if ($null -ne $reason) { return ([string]$reason.InnerText).Trim() }
    return ""
}
function Get-TestVerdict([string]$Result, [string]$Message) {
    if ($Result -eq "Passed") { return "passed" }
    $candidateFeatureMissing = $Message.Contains($candidateFeatureMissingMarker)
    $candidateBlocked = $Message.Contains($candidateBlockedMarker)
    $evaluatorObservationFault = $Message.Contains($evaluatorObservationMarker)
    if ($evaluatorObservationFault -and
        ($candidateFeatureMissing -or $candidateBlocked)) {
        return "conflicting_markers"
    }
    if ($candidateFeatureMissing) {
        return "candidate_feature_missing"
    }
    if ($candidateBlocked) {
        return "candidate_blocked"
    }
    if (($Result -in @("Inconclusive", "Skipped")) -and
        $evaluatorObservationFault) {
        return "evaluator_observation_fault"
    }
    if ($Result -eq "Failed") { return "candidate_failed" }
    if ($Result -eq "Missing") { return "missing" }
    return "unsupported"
}
function Read-PhaseResults($DeclaredTests, $Cases, [string]$PhaseName,
    [int]$ExpectedCount, [bool]$ValidateStaticMarker) {
    if ($Cases.Count -ne $ExpectedCount) {
        Add-Validation "$PhaseName discovered $($Cases.Count) tests; expected $ExpectedCount."
    }
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($declared in @($DeclaredTests)) {
        $matches = @(Find-Case $Cases ([string]$declared.id))
        if ($matches.Count -ne 1) {
            Add-Validation "Expected exactly one $PhaseName test $($declared.id), found $($matches.Count)."
        }
        $case = if ($matches.Count -gt 0) { $matches[0] } else { $null }
        $result = if ($null -ne $case) { [string]$case.result } else { "Missing" }
        $message = Get-Message $case
        $markerText = $message + " " + $(if ($null -eq $case) { "" } else {
            [string]$case.label
        })
        $verdict = if (Test-IsEvaluatorInfrastructureFailure $case $message) {
            "evaluator_infrastructure_fault"
        } else { Get-TestVerdict $result $markerText }
        if ($verdict -eq "conflicting_markers") {
            Add-Validation "$PhaseName test $($declared.id) exposed conflicting candidate and evaluator-fault markers."
        } elseif ($result -notin @("Passed", "Failed")) {
            if ($verdict -in @("candidate_feature_missing", "candidate_blocked")) {
                # A missing candidate feature or unmet candidate prerequisite is a
                # supported zero-point verdict, not evaluator infrastructure failure.
            } elseif ($verdict -eq "evaluator_observation_fault") {
                Add-Validation ("$PhaseName test $($declared.id) could not be " +
                    "observed by the automated evaluator; candidate scoring is invalid, " +
                    "not zero: $message")
            } else {
                Add-Validation "$PhaseName test $($declared.id) returned unsupported result '$result'."
            }
        } elseif ($ValidateStaticMarker -and $result -eq "Failed" -and
            -not $message.Contains($candidateStaticMarker)) {
            Add-Validation "Static test $($declared.id) failed without the stable candidate marker."
        }
        $items.Add([pscustomobject]@{
            id = [string]$declared.id
            phase = $PhaseName.ToLowerInvariant()
            role = if ($null -ne $declared.PSObject.Properties["role"]) {
                [string]$declared.role
            } else { "scoring_or_support" }
            result = $result
            verdict = $verdict
            message = $message
            evidence_valid = $null
            evidence_status = "not_checked"
            checkpoint_mode = $null -ne $declared.PSObject.Properties['checkpoint_order'] -and
                @($declared.checkpoint_order).Count -gt 0
            checkpoint_order = if ($null -ne $declared.PSObject.Properties['checkpoint_order']) {
                @($declared.checkpoint_order | ForEach-Object { [string]$_ })
            } else { @() }
            checkpoint_results = @()
            checkpoint_evidence_complete = $null
        })
    }
    return @($items)
}
function Find-PhaseItem($Items, [string]$Id) {
    @($Items | Where-Object { [string]$_.id -eq $Id }) |
        Select-Object -First 1
}
function Test-ItemPassed($Items, [string]$Id) {
    $item = Find-PhaseItem $Items $Id
    if ($null -eq $item -or [string]$item.result -ne "Passed") { return $false }
    if ([string]$item.phase -in @("dynamic", "fresh")) {
        return [bool]$item.evidence_valid
    }
    return $true
}
function Round-One([double]$Value) {
    return [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero)
}
function Get-Sha256([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Test-Sha256Value([string]$Value) {
    return -not [string]::IsNullOrWhiteSpace($Value) -and
        $Value -match '^[0-9a-fA-F]{64}$'
}

# Validate the rule-set itself before interpreting candidate output.
$dimensionIds = @("D1", "D2", "D3", "D4", "D5", "D6")
$declaredTotal = 0.0
foreach ($dimensionId in $dimensionIds) {
    $maximum = [double]$rules.dimension_maxima.$dimensionId
    $declaredTotal += $maximum
    if ($dimensionId -ne "D6") {
        $dimensionChecks = @($rules.scoring_checks | Where-Object {
            [string]$_.dimension -eq $dimensionId
        })
        if ($dimensionChecks.Count -eq 0) {
            Add-Validation "$dimensionId has no formal checkpoints."
        }
    }
}
if ([string]$rules.official_scoring.formula -ne
    "dimension_maximum * passed_checkpoints / total_checkpoints" -or
    [bool]$rules.official_scoring.diagnostic_weights_affect_formal_score) {
    Add-Validation "rules.json does not declare the required equal-checkpoint formula."
}
$checkIds = @($rules.scoring_checks | ForEach-Object { [string]$_.id })
if (@($checkIds | Sort-Object -Unique).Count -ne $checkIds.Count) {
    Add-Validation "rules.json contains duplicate scoring checkpoint ids."
}
$allDeclaredRuleTests = @($rules.phases.static.tests) +
    @($rules.phases.dynamic.tests) + @($rules.phases.fresh.tests)
foreach ($check in @($rules.scoring_checks)) {
    $matches = @($allDeclaredRuleTests | Where-Object {
        [string]$_.id -eq [string]$check.source_test_id
    })
    if ($matches.Count -ne 1) {
        Add-Validation ("Checkpoint $($check.id) must map to exactly one declared NUnit " +
            "testcase; found $($matches.Count) for $($check.source_test_id).")
    }
    if ([string]$check.phase -notin @("static", "dynamic", "fresh")) {
        Add-Validation "Checkpoint $($check.id) has unsupported phase '$($check.phase)'."
    }
}
foreach ($declared in @($allDeclaredRuleTests)) {
    $checkpointOrder = if ($null -ne $declared.PSObject.Properties['checkpoint_order']) {
        @($declared.checkpoint_order | ForEach-Object { [string]$_ })
    } else { @() }
    if ($checkpointOrder.Count -eq 0) { continue }
    if (@($checkpointOrder | Sort-Object -Unique).Count -ne $checkpointOrder.Count) {
        Add-Validation "Composite testcase $($declared.id) contains duplicate checkpoint ids."
    }
    $mappedChecks = @($rules.scoring_checks | Where-Object {
        [string]$_.source_test_id -eq [string]$declared.id
    })
    $mappedIds = @($mappedChecks | ForEach-Object { [string]$_.id })
    $mappingDifference = @(Compare-Object -ReferenceObject $checkpointOrder `
        -DifferenceObject $mappedIds -CaseSensitive)
    if ($checkpointOrder.Count -ne $mappedIds.Count -or $mappingDifference.Count -gt 0) {
        Add-Validation ("Composite testcase $($declared.id) checkpoint_order must " +
            "contain every mapped scoring checkpoint exactly once.")
    }
    foreach ($mappedCheck in $mappedChecks) {
        if ($checkpointOrder -notcontains [string]$mappedCheck.id) {
            Add-Validation "Composite testcase $($declared.id) omits checkpoint $($mappedCheck.id)."
        }
        if ($null -eq $mappedCheck.PSObject.Properties['checkpoint_evidence_scene'] -or
            [string]::IsNullOrWhiteSpace([string]$mappedCheck.checkpoint_evidence_scene)) {
            Add-Validation "Composite checkpoint $($mappedCheck.id) has no checkpoint_evidence_scene."
        }
    }
}
if ($declaredTotal -ne [double]$rules.maximum_score) {
    Add-Validation "D1-D6 maxima do not sum to maximum_score."
}
if (([double]$rules.dimension_maxima.D1 + [double]$rules.dimension_maxima.D2 +
     [double]$rules.dimension_maxima.D3 + [double]$rules.dimension_maxima.D4 +
     [double]$rules.dimension_maxima.D5) -ne [double]$rules.automatic_maximum_score) {
    Add-Validation "D1-D5 maxima do not sum to automatic_maximum_score."
}

$staticCases = @(Read-Cases $StaticResultPath "Static" $true)
$staticResults = @(Read-PhaseResults $rules.phases.static.tests $staticCases "Static" `
    ([int]$rules.expected_test_counts.static) $true)
$staticFullPass = @($staticResults | Where-Object { $_.result -ne "Passed" }).Count -eq 0

$dynamicCases = @()
$freshCases = @()
$dynamicResults = @()
$freshResults = @()
if ($staticFullPass) {
    $dynamicCases = @(Read-Cases $DynamicResultPath "Dynamic" $true)
    $freshCases = @(Read-Cases $FreshResultPath "Fresh" $true)
    $dynamicResults = @(Read-PhaseResults $rules.phases.dynamic.tests $dynamicCases "Dynamic" `
        ([int]$rules.expected_test_counts.dynamic) $false)
    $freshResults = @(Read-PhaseResults $rules.phases.fresh.tests $freshCases "Fresh" `
        ([int]$rules.expected_test_counts.fresh) $false)
}

$allTestResults = @($staticResults) + @($dynamicResults) + @($freshResults)
$evidenceAudit = [System.Collections.Generic.List[object]]::new()
if ($staticFullPass) {
    if ([string]::IsNullOrWhiteSpace($EvidenceDirectory) -or
        -not (Test-Path -LiteralPath $EvidenceDirectory -PathType Container)) {
        Add-Validation "Dynamic/Fresh evidence directory is required but missing."
    }
    if ([string]::IsNullOrWhiteSpace($EvaluationSessionId)) {
        Add-Validation "EvaluationSessionId is required for Dynamic/Fresh evidence binding."
    }
    if ($DynamicProcessId -le 0 -or $FreshProcessId -le 0) {
        Add-Validation "Dynamic and Fresh Unity process ids must both be positive."
    } elseif ($DynamicProcessId -eq $FreshProcessId) {
        Add-Validation "Dynamic and Fresh must run in distinct Unity processes."
    }

    function Convert-PhaseUtc([string]$Value, [string]$Label) {
        try {
            return [DateTimeOffset]::Parse($Value,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal -bor
                [Globalization.DateTimeStyles]::AdjustToUniversal)
        } catch {
            Add-Validation "$Label is missing or not a valid UTC timestamp: '$Value'."
            return $null
        }
    }

    $dynamicStart = Convert-PhaseUtc $DynamicStartedUtc "DynamicStartedUtc"
    $dynamicEnd = Convert-PhaseUtc $DynamicCompletedUtc "DynamicCompletedUtc"
    $freshStart = Convert-PhaseUtc $FreshStartedUtc "FreshStartedUtc"
    $freshEnd = Convert-PhaseUtc $FreshCompletedUtc "FreshCompletedUtc"
    if ($null -ne $dynamicStart -and $null -ne $dynamicEnd -and
        $dynamicStart -gt $dynamicEnd) {
        Add-Validation "Dynamic phase window is reversed."
    }
    if ($null -ne $freshStart -and $null -ne $freshEnd -and
        $freshStart -gt $freshEnd) {
        Add-Validation "Fresh phase window is reversed."
    }

    $phaseMetadata = @{
        dynamic = [pscustomobject]@{
            process_id = $DynamicProcessId; started = $dynamicStart; completed = $dynamicEnd
        }
        fresh = [pscustomobject]@{
            process_id = $FreshProcessId; started = $freshStart; completed = $freshEnd
        }
    }
    $declaredEvidenceTests = @($rules.phases.dynamic.tests | ForEach-Object {
        [pscustomobject]@{ phase = "dynamic"; declaration = $_ }
    }) + @($rules.phases.fresh.tests | ForEach-Object {
        [pscustomobject]@{ phase = "fresh"; declaration = $_ }
    })
    $records = [System.Collections.Generic.List[object]]::new()
    if (Test-Path -LiteralPath $EvidenceDirectory -PathType Container) {
        $evidenceRoot = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
        $allowedAuxiliary = @($rules.evidence_contract.auxiliary_json_files |
            ForEach-Object { [string]$_ })
        foreach ($file in @(Get-ChildItem -LiteralPath $evidenceRoot -Recurse `
                -File -Filter '*.json')) {
            $relative = $file.FullName.Substring($evidenceRoot.Length).TrimStart('\','/') `
                -replace '\\','/'
            if ($allowedAuxiliary -contains $relative) { continue }
            try {
                $value = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName |
                    ConvertFrom-Json -DateKind String
            } catch {
                Add-Validation "Evidence JSON is unreadable: $relative ($($_.Exception.Message))"
                continue
            }
            if ($null -eq $value.PSObject.Properties['test_id'] -or
                [string]::IsNullOrWhiteSpace([string]$value.test_id)) {
                Add-Validation "Unexpected JSON without test_id in evidence directory: $relative"
                continue
            }
            $records.Add([pscustomobject]@{
                path = $file.FullName
                relative_path = $relative
                value = $value
            })
        }
    }

    $declaredIds = @($declaredEvidenceTests | ForEach-Object {
        [string]$_.declaration.id
    })
    foreach ($record in @($records)) {
        if ($declaredIds -notcontains [string]$record.value.test_id) {
            Add-Validation "Stale or unknown formal evidence record: $($record.relative_path) test_id=$($record.value.test_id)"
        }
    }

    foreach ($entry in $declaredEvidenceTests) {
        $phase = [string]$entry.phase
        $declared = $entry.declaration
        $id = [string]$declared.id
        $item = Find-PhaseItem $allTestResults $id
        $matches = @($records | Where-Object {
            [string]$_.value.test_id -ceq $id
        })
        $nunitPassed = $null -ne $item -and [string]$item.result -eq "Passed"
        $checkpointMode = $null -ne $declared.PSObject.Properties['checkpoint_order'] -and
            @($declared.checkpoint_order).Count -gt 0
        $recordValid = $true
        if ($nunitPassed -and $matches.Count -ne 1) {
            Add-Validation "Passed $phase testcase $id requires exactly one evidence JSON; found $($matches.Count)."
            $recordValid = $false
        } elseif (-not $nunitPassed -and $checkpointMode -and $matches.Count -gt 1) {
            Add-Validation "Non-Passed composite $phase testcase $id may publish at most one partial checkpoint record; found $($matches.Count)."
            $recordValid = $false
        } elseif (-not $nunitPassed -and -not $checkpointMode -and $matches.Count -ne 0) {
            Add-Validation "Non-Passed $phase testcase $id published stale/formal evidence; found $($matches.Count)."
            $recordValid = $false
        }

        if ($matches.Count -eq 1) {
            $record = $matches[0]
            $value = $record.value
            $expectedLeaf = $id + ".json"
            if ([IO.Path]::GetFileName([string]$record.path) -cne $expectedLeaf) {
                Add-Validation "Evidence for $id must use exact filename $expectedLeaf."
                $recordValid = $false
            }
            if ([string]$value.evaluation_session_id -cne $EvaluationSessionId) {
                Add-Validation "Evidence $id belongs to a different evaluation session."
                $recordValid = $false
            }
            try { $recordProcessId = [int]$value.process_id }
            catch { $recordProcessId = 0 }
            if ($recordProcessId -ne [int]$phaseMetadata[$phase].process_id) {
                Add-Validation "Evidence $id process_id=$recordProcessId does not match the $phase Unity PID $($phaseMetadata[$phase].process_id)."
                $recordValid = $false
            }
            try { $frame = [int]$value.frame } catch { $frame = 0 }
            if ($frame -le 0) {
                Add-Validation "Evidence $id must contain frame > 0."
                $recordValid = $false
            }
            $generated = Convert-PhaseUtc ([string]$value.generated_utc) `
                "Evidence $id generated_utc"
            if ($null -eq $generated -or
                $null -eq $phaseMetadata[$phase].started -or
                $null -eq $phaseMetadata[$phase].completed -or
                $generated -lt $phaseMetadata[$phase].started -or
                $generated -gt $phaseMetadata[$phase].completed) {
                Add-Validation ("Evidence $id generated_utc is outside the authoritative " +
                    "$phase phase window (generated=$generated; start=$($phaseMetadata[$phase].started); " +
                    "end=$($phaseMetadata[$phase].completed)).")
                $recordValid = $false
            }
            if ($checkpointMode) {
                if ([string]::IsNullOrWhiteSpace([string]$value.scene)) {
                    Add-Validation "Composite evidence $id must contain a non-empty current scene."
                    $recordValid = $false
                }
            } elseif ([string]$declared.role -ne "evaluator_health") {
                $expectedScene = [string]$declared.evidence_scene
                if ([string]::IsNullOrWhiteSpace($expectedScene) -or
                    -not [string]::Equals([string]$value.scene, $expectedScene,
                        [StringComparison]::Ordinal)) {
                    Add-Validation "Evidence $id scene '$($value.scene)' does not match '$expectedScene'."
                    $recordValid = $false
                }
            }

            if ($checkpointMode) {
                $partialValue = if ($null -eq
                    $value.PSObject.Properties['checkpoint_partial_credit']) {
                    $null
                } else { $value.checkpoint_partial_credit }
                $partialFlag = $partialValue -is [bool] -and [bool]$partialValue
                if (-not $partialFlag) {
                    Add-Validation "Composite evidence $id does not declare checkpoint_partial_credit=true."
                    $recordValid = $false
                }
                $expectedOrder = @($declared.checkpoint_order | ForEach-Object { [string]$_ })
                $checkpointEntries = if ($null -ne $value.PSObject.Properties['checkpoints']) {
                    @($value.checkpoints)
                } else { @() }
                if ($checkpointEntries.Count -ne $expectedOrder.Count) {
                    Add-Validation ("Composite evidence $id contains $($checkpointEntries.Count) " +
                        "checkpoint entries; expected $($expectedOrder.Count).")
                    $recordValid = $false
                }
                $checkpointAuditItems = [System.Collections.Generic.List[object]]::new()
                $allowedStatuses = @($rules.evidence_contract.checkpoint_statuses |
                    ForEach-Object { [string]$_ })
                $activeCount = 0
                $previousRank = -1
                $passedCheckpointCount = 0
                for ($checkpointIndex = 0;
                     $checkpointIndex -lt $checkpointEntries.Count;
                     $checkpointIndex++) {
                    $checkpointEntry = $checkpointEntries[$checkpointIndex]
                    if ($null -eq $checkpointEntry) {
                        Add-Validation "Composite evidence $id checkpoint index $checkpointIndex is null."
                        $recordValid = $false
                        continue
                    }
                    $checkpointId = [string]$checkpointEntry.check_id
                    $checkpointStatus = [string]$checkpointEntry.status
                    try { $checkpointFrame = [int]$checkpointEntry.frame }
                    catch { $checkpointFrame = 0 }
                    $checkpointGeneratedText = if ($null -eq
                        $checkpointEntry.PSObject.Properties['generated_utc']) {
                        ""
                    } else { [string]$checkpointEntry.generated_utc }
                    $actualCheckpointScene = if ($null -eq
                        $checkpointEntry.PSObject.Properties['scene']) {
                        ""
                    } else { [string]$checkpointEntry.scene }
                    $expectedCheckpointId = if ($checkpointIndex -lt $expectedOrder.Count) {
                        [string]$expectedOrder[$checkpointIndex]
                    } else { "<none>" }
                    if ($checkpointId -cne $expectedCheckpointId) {
                        Add-Validation ("Composite evidence $id checkpoint index " +
                            "$checkpointIndex is '$checkpointId'; expected '$expectedCheckpointId'.")
                        $recordValid = $false
                    }
                    if ([Array]::IndexOf($allowedStatuses, $checkpointStatus) -lt 0) {
                        Add-Validation "Composite evidence $id checkpoint $checkpointId has unsupported status '$checkpointStatus'."
                        $recordValid = $false
                    }
                    $rank = switch ($checkpointStatus) {
                        "passed" { 0 }
                        "active" { 1 }
                        "pending" { 2 }
                        default { 99 }
                    }
                    if ($rank -lt $previousRank) {
                        Add-Validation "Composite evidence $id checkpoint statuses are not a passed/active/pending prefix."
                        $recordValid = $false
                    }
                    $previousRank = [Math]::Max($previousRank, $rank)
                    if ($checkpointStatus -eq "active") { $activeCount++ }
                    if ($checkpointStatus -eq "passed") {
                        $passedCheckpointCount++
                        if ($checkpointFrame -le 0) {
                            Add-Validation "Passed checkpoint $checkpointId in $id must contain frame > 0."
                            $recordValid = $false
                        }
                        $checkpointGenerated = Convert-PhaseUtc `
                            $checkpointGeneratedText `
                            "Checkpoint $checkpointId generated_utc"
                        if ($null -eq $checkpointGenerated -or
                            $null -eq $phaseMetadata[$phase].started -or
                            $null -eq $phaseMetadata[$phase].completed -or
                            $checkpointGenerated -lt $phaseMetadata[$phase].started -or
                            $checkpointGenerated -gt $phaseMetadata[$phase].completed) {
                            Add-Validation ("Checkpoint $checkpointId generated_utc is " +
                                "outside the authoritative $phase phase window.")
                            $recordValid = $false
                        }
                        $checkpointRule = @($rules.scoring_checks | Where-Object {
                            [string]$_.id -ceq $checkpointId
                        }) | Select-Object -First 1
                        $expectedCheckpointScene = if ($null -eq $checkpointRule) { "" } else {
                            [string]$checkpointRule.checkpoint_evidence_scene
                        }
                        $checkpointSceneValid = if ($expectedCheckpointScene -ceq
                            "@non_menu_scene") {
                            -not [string]::IsNullOrWhiteSpace($actualCheckpointScene) -and
                            $actualCheckpointScene.StartsWith("Assets/",
                                [StringComparison]::Ordinal) -and
                            $actualCheckpointScene.EndsWith(".unity",
                                [StringComparison]::Ordinal) -and
                            -not [string]::Equals($actualCheckpointScene,
                                [string]$rules.scene_contract.menu_scene,
                                [StringComparison]::Ordinal)
                        } else {
                            -not [string]::IsNullOrWhiteSpace($expectedCheckpointScene) -and
                            [string]::Equals($actualCheckpointScene,
                                $expectedCheckpointScene, [StringComparison]::Ordinal)
                        }
                        if (-not $checkpointSceneValid) {
                            Add-Validation ("Passed checkpoint $checkpointId scene " +
                                "'$actualCheckpointScene' does not match " +
                                "'$expectedCheckpointScene'.")
                            $recordValid = $false
                        }
                    }
                    $checkpointAuditItems.Add([pscustomobject]@{
                        check_id = $checkpointId
                        status = $checkpointStatus
                        generated_utc = $checkpointGeneratedText
                        frame = $checkpointFrame
                        scene = $actualCheckpointScene
                    })
                }
                if ($activeCount -gt 1) {
                    Add-Validation "Composite evidence $id contains more than one active checkpoint."
                    $recordValid = $false
                }
                $testCompleteValue = if ($null -eq
                    $value.PSObject.Properties['test_complete']) {
                    $null
                } else { $value.test_complete }
                if ($testCompleteValue -isnot [bool]) {
                    Add-Validation "Composite evidence $id test_complete must be a JSON boolean."
                    $recordValid = $false
                }
                $testComplete = $testCompleteValue -is [bool] -and
                    [bool]$testCompleteValue
                if ($testComplete -and $passedCheckpointCount -ne $expectedOrder.Count) {
                    Add-Validation "Composite evidence $id is test_complete but not every checkpoint passed."
                    $recordValid = $false
                }
                if ($nunitPassed -and (-not $testComplete -or
                    $passedCheckpointCount -ne $expectedOrder.Count)) {
                    Add-Validation "Passed composite testcase $id lacks a complete all-passed checkpoint ledger."
                    $recordValid = $false
                }
                if ($null -ne $item) {
                    $item.checkpoint_results = @($checkpointAuditItems)
                    $item.checkpoint_evidence_complete = $testComplete
                }
            }
        }
        if ($null -ne $item) {
            $item.evidence_valid = if ($nunitPassed) {
                $recordValid -and $matches.Count -eq 1
            } elseif ($checkpointMode) {
                $recordValid -and $matches.Count -le 1
            } else {
                $matches.Count -eq 0
            }
            $item.evidence_status = if ($nunitPassed -and [bool]$item.evidence_valid) {
                if ($checkpointMode) { "valid_checkpoint_complete" } else { "valid" }
            } elseif (-not $nunitPassed -and $checkpointMode -and
                $matches.Count -eq 1 -and [bool]$item.evidence_valid) {
                "valid_partial_checkpoints"
            } elseif (-not $nunitPassed -and $matches.Count -eq 0) {
                "absent_for_nonpass"
            } else { "invalid" }
        }
        $evidenceAudit.Add([pscustomobject]@{
            test_id = $id
            phase = $phase
            nunit_result = if ($null -eq $item) { "Missing" } else { [string]$item.result }
            evidence_count = $matches.Count
            evidence_status = if ($null -eq $item) { "invalid" } else {
                [string]$item.evidence_status
            }
            checkpoint_mode = $checkpointMode
            passed_checkpoint_count = if ($null -eq $item) { 0 } else {
                @($item.checkpoint_results | Where-Object {
                    [string]$_.status -eq "passed"
                }).Count
            }
            checkpoint_count = if ($null -eq $item) { 0 } else {
                @($item.checkpoint_results).Count
            }
        })
    }

    $seedPath = if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) { "" } else {
        Join-Path $EvidenceDirectory "fresh-seed.json"
    }
    $freshFormal = Find-PhaseItem $allTestResults "FRESH01_BestTimeSurvivesFreshProcess"
    if ($null -ne $freshFormal -and [string]$freshFormal.result -eq "Passed") {
        if (-not (Test-Path -LiteralPath $seedPath -PathType Leaf)) {
            Add-Validation "Passed Fresh persistence testcase requires fresh-seed.json."
        } else {
            try {
                $seed = Get-Content -Raw -Encoding UTF8 -LiteralPath $seedPath |
                    ConvertFrom-Json -DateKind String
                if ([string]$seed.evaluation_session_id -cne $EvaluationSessionId -or
                    [int]$seed.source_process_id -ne $DynamicProcessId -or
                    [string]$seed.source_scene -cne [string]$rules.scene_contract.main_scene -or
                    $null -eq $seed.persisted_record -or
                    -not (Test-Sha256Value ([string]$seed.persisted_record.fingerprint_sha256))) {
                    Add-Validation "fresh-seed.json is not bound to this session, Dynamic PID, main scene, and durable fingerprint."
                }
            } catch {
                Add-Validation "fresh-seed.json is unreadable or malformed: $($_.Exception.Message)"
            }
        }
    }
}
$evaluatorHealthValid = $true
if ($staticFullPass) {
    foreach ($health in @($rules.health_prerequisites)) {
        $source = Find-PhaseItem $allTestResults ([string]$health.source_test_id)
        if ($null -eq $source -or [string]$source.result -ne "Passed" -or
            -not [bool]$source.evidence_valid) {
            $evaluatorHealthValid = $false
            $actual = if ($null -eq $source) { "Missing" } else {
                "$([string]$source.result)/evidence=$([string]$source.evidence_status)"
            }
            Add-Validation "Evaluator health prerequisite $($health.source_test_id) returned $actual; $($health.phase) scoring is invalid."
        }
    }
}
$checkResults = [System.Collections.Generic.List[object]]::new()
foreach ($check in @($rules.scoring_checks)) {
    $source = Find-PhaseItem $allTestResults ([string]$check.source_test_id)
    $nunitResult = if ($null -eq $source) { "NotRun" } else { [string]$source.result }
    $evidenceRequired = [string]$check.phase -in @("dynamic", "fresh")
    $evidenceValid = -not $evidenceRequired -or
        ($null -ne $source -and [bool]$source.evidence_valid)
    $checkpointMode = $null -ne $source -and [bool]$source.checkpoint_mode
    $checkpointEvidence = if ($checkpointMode) {
        @($source.checkpoint_results | Where-Object {
            [string]$_.check_id -ceq [string]$check.id
        }) | Select-Object -First 1
    } else { $null }
    $checkpointStatus = if ($null -eq $checkpointEvidence) { "" } else {
        [string]$checkpointEvidence.status
    }
    $passed = if ($checkpointMode) {
        $evidenceValid -and $checkpointStatus -eq "passed"
    } else {
        $nunitResult -eq "Passed" -and $evidenceValid
    }
    $result = if ($passed) {
        "Passed"
    } elseif (-not $evidenceValid) {
        "InvalidEvidence"
    } elseif ($checkpointMode -and $checkpointStatus -eq "active") {
        "Failed"
    } elseif ($checkpointMode -and $checkpointStatus -eq "pending") {
        "Blocked"
    } elseif ($checkpointMode -and [string]$source.verdict -in
        @("candidate_blocked", "candidate_feature_missing")) {
        "Blocked"
    } elseif ($nunitResult -eq "Passed") {
        "InvalidEvidence"
    } else { $nunitResult }
    $checkpointVerdict = if (-not $checkpointMode) {
        if ($null -eq $source) { "not_run" } else { [string]$source.verdict }
    } elseif ($passed) {
        "passed_checkpoint"
    } elseif ($checkpointStatus -eq "active") {
        "candidate_failed_checkpoint"
    } elseif ($checkpointStatus -eq "pending") {
        "candidate_blocked_checkpoint"
    } elseif ($null -eq $source) {
        "not_run"
    } else { [string]$source.verdict }
    $checkResults.Add([pscustomobject]@{
        id = [string]$check.id
        dimension = [string]$check.dimension
        phase = [string]$check.phase
        source_test_id = [string]$check.source_test_id
        gdd_ref = [string]$check.gdd_ref
        question = [string]$check.question
        result = $result
        nunit_result = $nunitResult
        checkpoint_status = if ($checkpointMode) { $checkpointStatus } else { $null }
        evidence_status = if ($checkpointMode -and $passed) {
            "checkpoint_passed"
        } elseif ($checkpointMode -and $checkpointStatus -eq "active") {
            "checkpoint_failed"
        } elseif ($checkpointMode -and $checkpointStatus -eq "pending") {
            "checkpoint_blocked"
        } elseif ($evidenceRequired -and $null -ne $source) {
            [string]$source.evidence_status
        } elseif ($evidenceRequired) { "missing" } else { "nunit_xml" }
        verdict = $checkpointVerdict
        passed = $passed
        diagnostic_weight = if ($null -ne $check.PSObject.Properties['diagnostic_weight']) {
            [double]$check.diagnostic_weight
        } else { $null }
        score = $null
        maximum_score = $null
        message = if ($checkpointMode -and $checkpointStatus -eq "pending") {
            "blocked after an earlier checkpoint in the same player journey did not complete"
        } elseif ($checkpointMode -and $checkpointStatus -eq "active" -and
            $null -ne $source) {
            [string]$source.message
        } elseif ($null -eq $source) { "not run because a prior static gate failed" } else {
            [string]$source.message
        }
    })
}

$dimensions = [ordered]@{}
foreach ($dimensionId in @("D1", "D2", "D3", "D4", "D5")) {
    $items = @($checkResults | Where-Object { $_.dimension -eq $dimensionId })
    $maximum = [double]$rules.dimension_maxima.$dimensionId
    $passedCount = @($items | Where-Object { [bool]$_.passed }).Count
    $scoreValue = if ($items.Count -eq 0) { 0.0 } else {
        $maximum * $passedCount / $items.Count
    }
    $equalShare = if ($items.Count -eq 0) { 0.0 } else { $maximum / $items.Count }
    foreach ($item in $items) {
        $item.maximum_score = $equalShare
        $item.score = if ([bool]$item.passed) { $equalShare } else { 0.0 }
    }
    $dimensions[$dimensionId] = [pscustomobject]@{
        name = switch ($dimensionId) {
            "D1" { "Engineering Validity & Engine Integration" }
            "D2" { "Specification Fulfillment & Content Completeness" }
            "D3" { "Gameplay Correctness & System Behavior" }
            "D4" { "End-to-End Flow & Lifecycle Integrity" }
            "D5" { "Interface Functionality & Player Feedback" }
        }
        score = Round-One ([double]$scoreValue)
        maximum_score = $maximum
        passed_checkpoints = $passedCount
        total_checkpoints = $items.Count
        formula = "maximum_score * passed_checkpoints / total_checkpoints"
        status = if ($dimensionId -eq "D1" -or $staticFullPass) { "evaluated" } else { "not_reached" }
        checks = @($items)
    }
}
if (-not $evaluatorHealthValid) {
    foreach ($dimensionId in @("D2", "D3", "D4", "D5")) {
        $dimensions[$dimensionId].score = $null
        $dimensions[$dimensionId].status = "invalid_evaluator_health"
    }
}

$visual = $null
# D6 is a separately bound three-round visual protocol. Candidate-origin
# missing, black/transparent, or broken images are valid zero-point states per
# the scoring guide. Reference, model, tool, prompt-context, parser, or capture
# infrastructure failures leave D6 invalid_visual and Overall null without
# erasing a trustworthy D1-D5 score.
$visualStatus = "pending"
$visualScore = $null
$visualValidation = [System.Collections.Generic.List[string]]::new()
function Add-VisualValidation([string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Message) -and
        -not $visualValidation.Contains($Message)) {
        $visualValidation.Add($Message)
    }
}
if (-not [string]::IsNullOrWhiteSpace($VisualResultPath)) {
    $visualStatus = "invalid_visual"
    if (-not (Test-Path -LiteralPath $VisualResultPath -PathType Leaf)) {
        Add-VisualValidation "Visual result path was supplied but does not exist: $VisualResultPath"
    } else {
        try {
            $visual = Get-Content -Raw -Encoding UTF8 -LiteralPath $VisualResultPath |
                ConvertFrom-Json
            $expectedModel = [string]$rules.phases.visual.model_id
            $expectedPromptHash = ([string]$rules.phases.visual.prompt_sha256).ToLowerInvariant()
            $expectedStatesHash = ([string]$rules.phases.visual.states_manifest_sha256).ToLowerInvariant()
            $expectedPromptRelative = [string]$rules.phases.visual.prompt
            $expectedStatesRelative = [string]$rules.phases.visual.states_manifest
            if (-not [string]::IsNullOrWhiteSpace($VisualRoot)) {
                $expectedPromptRelative = Split-Path -Leaf $expectedPromptRelative
                $expectedStatesRelative = Split-Path -Leaf $expectedStatesRelative
            }
            $expectedPromptPath = Join-Path $visualFileRoot $expectedPromptRelative
            $expectedStatesPath = Join-Path $visualFileRoot $expectedStatesRelative
            $frozenVisualPrompt = Get-Content -Raw -Encoding UTF8 -LiteralPath $expectedPromptPath
            $visualStatePlaceholder = [regex]::Match($frozenVisualPrompt, '<[^<>]+>').Value
            $seenResponseIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $actualPromptHash = Get-Sha256 $expectedPromptPath
            $actualStatesHash = Get-Sha256 $expectedStatesPath

            if ([int]$visual.schema_version -ne [int]$rules.phases.visual.result_schema_version) {
                Add-VisualValidation "Visual result schema_version does not match rules.json."
            }
            if (-not [bool]$visual.valid -or [string]$visual.status -ne "evaluated") {
                Add-VisualValidation "Visual scoring result is not a completed evaluated result."
                foreach ($reason in @($visual.errors)) {
                    Add-VisualValidation ([string]$reason)
                }
            }
            if (-not [bool]$visual.formal_score_complete) {
                Add-VisualValidation "Visual result did not assert formal_score_complete=true."
            }
            if ([bool]$visual.dry_run) {
                Add-VisualValidation "A visual dry-run cannot provide D6."
            }
            if (-not [string]::Equals([string]$visual.model_id, $expectedModel,
                    [StringComparison]::Ordinal)) {
                Add-VisualValidation "Visual result model_id does not match the frozen model_id."
            }
            if (-not (Test-Sha256Value $expectedPromptHash) -or
                -not [string]::Equals($actualPromptHash, $expectedPromptHash,
                    [StringComparison]::OrdinalIgnoreCase)) {
                Add-VisualValidation "The evaluator's visual prompt no longer matches its frozen SHA256."
            }
            if (-not [bool]$visual.prompt.verified -or
                -not [string]::Equals([string]$visual.prompt.sha256,
                    $expectedPromptHash, [StringComparison]::OrdinalIgnoreCase) -or
                -not [string]::Equals([string]$visual.prompt.expected_sha256,
                    $expectedPromptHash, [StringComparison]::OrdinalIgnoreCase)) {
                Add-VisualValidation "Visual result prompt SHA256 binding is missing or mismatched."
            }
            if (-not (Test-Sha256Value $expectedStatesHash) -or
                -not [string]::Equals($actualStatesHash, $expectedStatesHash,
                    [StringComparison]::OrdinalIgnoreCase) -or
                -not [bool]$visual.states_manifest.verified -or
                -not [string]::Equals([string]$visual.states_manifest.sha256,
                    $expectedStatesHash, [StringComparison]::OrdinalIgnoreCase)) {
                Add-VisualValidation "Visual states manifest SHA256 binding is missing or mismatched."
            }
            if (-not [bool]$rules.phases.visual.formal_reference_ready -or
                -not [bool]$visual.reference_preflight.formal_reference_ready) {
                Add-VisualValidation "The frozen same-state Original reference set is not formally ready."
            }
            $expectedRounds = [int]$rules.phases.visual.rounds
            $rounds = @($visual.rounds)
            if ([int]$visual.rounds_required -ne $expectedRounds -or
                [int]$visual.rounds_completed -ne $expectedRounds -or
                $rounds.Count -ne $expectedRounds) {
                Add-VisualValidation "Visual scoring must contain exactly $expectedRounds completed rounds."
            }

            $evidenceRoot = $null
            if (-not [string]::IsNullOrWhiteSpace($VisualEvidenceDirectory)) {
                if (Test-Path -LiteralPath $VisualEvidenceDirectory -PathType Container) {
                    $evidenceRoot = (Resolve-Path -LiteralPath $VisualEvidenceDirectory).Path
                } else {
                    Add-VisualValidation "Visual evidence directory does not exist: $VisualEvidenceDirectory"
                }
            } else {
                $derived = Join-Path (Split-Path -Parent $VisualResultPath) "evidence"
                if (Test-Path -LiteralPath $derived -PathType Container) {
                    $evidenceRoot = (Resolve-Path -LiteralPath $derived).Path
                }
            }

            $topStates = @($visual.states)
            if ($topStates.Count -ne @($rules.visual_states).Count) {
                Add-VisualValidation "Visual scoring state count does not match rules.json."
            }
            foreach ($expectedState in @($rules.visual_states)) {
                $matches = @($topStates | Where-Object {
                    [string]$_.id -eq [string]$expectedState.id
                })
                if ($matches.Count -ne 1) {
                    Add-VisualValidation "Expected one visual state $($expectedState.id), found $($matches.Count)."
                    continue
                }
                $state = $matches[0]
                if (-not [bool]$state.reference_present -or
                    -not (Test-Sha256Value ([string]$state.reference_sha256))) {
                    Add-VisualValidation "Visual state $($expectedState.id) has no valid Original reference binding."
                    continue
                }
                $candidateFailureZero = [bool]$state.candidate_failure_zero
                if (-not $candidateFailureZero -and
                    (-not [bool]$state.candidate_present -or
                     -not (Test-Sha256Value ([string]$state.candidate_sha256)))) {
                    Add-VisualValidation "Visual state $($expectedState.id) has no valid candidate image binding and was not classified as a guide zero."
                    continue
                }
                if ($candidateFailureZero -and
                    [string]$state.candidate_image_status -notin @("missing","black_or_transparent","broken")) {
                    Add-VisualValidation "Visual state $($expectedState.id) used an unsupported candidate-failure zero classification."
                }
                $expectedReferenceRelative = [string]$expectedState.reference
                if (-not [string]::IsNullOrWhiteSpace($VisualRoot)) {
                    $expectedReferenceRelative = $expectedReferenceRelative -replace '^visual[\\/]', ''
                }
                $expectedReference = [IO.Path]::GetFullPath(
                    (Join-Path $visualFileRoot $expectedReferenceRelative))
                if (-not (Test-Path -LiteralPath $expectedReference -PathType Leaf) -or
                    -not [string]::Equals((Get-Sha256 $expectedReference),
                        [string]$state.reference_sha256,
                        [StringComparison]::OrdinalIgnoreCase)) {
                    Add-VisualValidation "Visual state $($expectedState.id) reference image hash does not match the frozen reference."
                }
                $recordedReference = [IO.Path]::GetFullPath([string]$state.reference_path)
                if (-not [string]::Equals($recordedReference, $expectedReference,
                        [StringComparison]::OrdinalIgnoreCase)) {
                    Add-VisualValidation "Visual state $($expectedState.id) reference path is not the frozen reference path."
                }
                $recordedCandidate = [IO.Path]::GetFullPath([string]$state.candidate_path)
                if (-not $candidateFailureZero -and
                    (-not (Test-Path -LiteralPath $recordedCandidate -PathType Leaf) -or
                     -not [string]::Equals((Get-Sha256 $recordedCandidate),
                         [string]$state.candidate_sha256,
                         [StringComparison]::OrdinalIgnoreCase))) {
                    Add-VisualValidation "Visual state $($expectedState.id) candidate image hash no longer matches the scored file."
                }
                if ($null -ne $evidenceRoot) {
                    $expectedCandidate = [IO.Path]::GetFullPath(
                        (Join-Path $evidenceRoot ([string]$expectedState.candidate_evidence)))
                    if (-not [string]::Equals($recordedCandidate, $expectedCandidate,
                            [StringComparison]::OrdinalIgnoreCase)) {
                        Add-VisualValidation "Visual state $($expectedState.id) candidate path is not the evaluator evidence file."
                    }
                }
            }

            $usableStateCount = @($topStates | Where-Object { -not [bool]$_.candidate_failure_zero }).Count
            $promptPreflights = @($visual.prompt_input_preflights)
            if ($promptPreflights.Count -ne $usableStateCount -or
                @($promptPreflights | Where-Object { -not [bool]$_.verified }).Count -ne 0) {
                Add-VisualValidation "Every VLM-scored state must have one passing model-visible prompt-input preflight."
            }
            foreach ($preflight in $promptPreflights) {
                if ([int]$preflight.message_count -ne 1 -or
                    [int]$preflight.developer_message_count -ne 0 -or
                    [int]$preflight.environment_context_count -ne 0 -or
                    -not [bool]$preflight.exact_user_prompt -or
                    [int]$preflight.image_count -ne 2 -or
                    -not (Test-Sha256Value ([string]$preflight.raw_sha256)) -or
                    -not (Test-Path -LiteralPath ([string]$preflight.raw_path) -PathType Leaf) -or
                    -not [string]::Equals((Get-Sha256 ([string]$preflight.raw_path)),
                        [string]$preflight.raw_sha256,[StringComparison]::OrdinalIgnoreCase)) {
                    Add-VisualValidation "A prompt-input preflight count/content/raw-hash binding is missing or changed."
                }
            }

            $allowedScores = @(0.0, 0.5, 1.0, 1.5, 2.0)
            $criterionNames = @(
                "scene_assembly", "composition_layout", "scale_layer_clarity",
                "style_color", "overall_finish")
            $observedRoundScores = [System.Collections.Generic.List[double]]::new()
            for ($roundNumber = 1; $roundNumber -le $expectedRounds; $roundNumber++) {
                $roundMatches = @($rounds | Where-Object { [int]$_.round -eq $roundNumber })
                if ($roundMatches.Count -ne 1) {
                    Add-VisualValidation "Expected one visual round $roundNumber, found $($roundMatches.Count)."
                    continue
                }
                $round = $roundMatches[0]
                if (-not [string]::Equals([string]$round.model_id, $expectedModel,
                        [StringComparison]::Ordinal) -or
                    -not [string]::Equals([string]$round.prompt_sha256,
                        $expectedPromptHash, [StringComparison]::OrdinalIgnoreCase)) {
                    Add-VisualValidation "Visual round $roundNumber used a different model_id or prompt SHA256."
                }
                $roundStates = @($round.states)
                if ($roundStates.Count -ne @($rules.visual_states).Count) {
                    Add-VisualValidation "Visual round $roundNumber has the wrong state count."
                    continue
                }
                $observedStateScores = [System.Collections.Generic.List[double]]::new()
                foreach ($expectedState in @($rules.visual_states)) {
                    $stateMatches = @($roundStates | Where-Object {
                        [string]$_.state_id -eq [string]$expectedState.id
                    })
                    if ($stateMatches.Count -ne 1) {
                        Add-VisualValidation "Visual round $roundNumber expected state $($expectedState.id) once."
                        continue
                    }
                    $stateResult = $stateMatches[0]
                    $topState = @($topStates | Where-Object {
                        [string]$_.id -eq [string]$expectedState.id
                    }) | Select-Object -First 1
                    if (-not [string]::Equals([string]$stateResult.model_id,
                            $expectedModel, [StringComparison]::Ordinal) -or
                        -not [string]::Equals([string]$stateResult.prompt_sha256,
                            $expectedPromptHash, [StringComparison]::OrdinalIgnoreCase) -or
                        $null -eq $topState -or
                        -not [string]::Equals([string]$stateResult.reference_sha256,
                            [string]$topState.reference_sha256,
                            [StringComparison]::OrdinalIgnoreCase) -or
                        -not [string]::Equals([string]$stateResult.candidate_sha256,
                            [string]$topState.candidate_sha256,
                            [StringComparison]::OrdinalIgnoreCase)) {
                        Add-VisualValidation "Visual round $roundNumber state $($expectedState.id) has inconsistent model/prompt/image bindings."
                    }
                    if ([bool]$stateResult.candidate_failure_zero) {
                        if (-not [bool]$topState.candidate_failure_zero -or
                            [string]$stateResult.scoring_method -ne "guide_zero_without_vlm_call" -or
                            [double]$stateResult.score -ne 0.0 -or
                            $null -ne $stateResult.raw_response_path -or
                            $null -ne $stateResult.event_log_path -or
                            $null -ne $stateResult.invocation_path) {
                            Add-VisualValidation "Visual round $roundNumber state $($expectedState.id) candidate-failure zero record is inconsistent."
                        }
                    } else {
                        if ([bool]$topState.candidate_failure_zero -or
                            [string]$stateResult.scoring_method -ne "fixed_vlm_prompt") {
                            Add-VisualValidation "Visual round $roundNumber state $($expectedState.id) unexpectedly used a VLM/non-VLM route."
                        }
                        foreach ($artifact in @(
                            @([string]$stateResult.raw_response_path,[string]$stateResult.raw_response_sha256,"raw response"),
                            @([string]$stateResult.event_log_path,[string]$stateResult.event_log_sha256,"event log"),
                            @([string]$stateResult.invocation_path,[string]$stateResult.invocation_sha256,"invocation"))) {
                            $artifactPath=[string]$artifact[0]; $artifactHash=[string]$artifact[1]
                            if (-not (Test-Sha256Value $artifactHash) -or
                                -not (Test-Path -LiteralPath $artifactPath -PathType Leaf) -or
                                -not [string]::Equals((Get-Sha256 $artifactPath),$artifactHash,
                                    [StringComparison]::OrdinalIgnoreCase)) {
                                Add-VisualValidation "Visual round $roundNumber state $($expectedState.id) $($artifact[2]) file/hash is missing or changed."
                            }
                        }
                        try {
                            $invocation = Get-Content -Raw -Encoding UTF8 -LiteralPath `
                                ([string]$stateResult.invocation_path) | ConvertFrom-Json
                            $matchingPreflight = @($promptPreflights | Where-Object {
                                [string]$_.state_id -eq [string]$expectedState.id
                            }) | Select-Object -First 1
                            $messages = @($invocation.input)
                            if ([string]$invocation.model -cne $expectedModel -or
                                $messages.Count -ne 1 -or [string]$messages[0].role -cne 'user' -or
                                $null -ne $invocation.PSObject.Properties['instructions'] -or
                                $null -ne $invocation.PSObject.Properties['tools'] -or
                                $null -eq $matchingPreflight -or
                                -not [string]::Equals((Get-Sha256 ([string]$stateResult.invocation_path)),
                                    [string]$matchingPreflight.raw_sha256, [StringComparison]::OrdinalIgnoreCase)) {
                                throw 'Review request does not match the single-user, tool-free request preflight.'
                            }
                            $content = @($messages[0].content)
                            $renderedPrompt = $frozenVisualPrompt.Replace($visualStatePlaceholder, [string]$expectedState.label)
                            $referenceUrl = 'data:image/png;base64,' + [Convert]::ToBase64String(
                                [IO.File]::ReadAllBytes([string]$topState.reference_path))
                            $candidateUrl = 'data:image/png;base64,' + [Convert]::ToBase64String(
                                [IO.File]::ReadAllBytes([string]$topState.candidate_path))
                            if ($content.Count -ne 3 -or [string]$content[0].type -cne 'input_text' -or
                                [string]$content[0].text -cne $renderedPrompt -or
                                [string]$content[1].type -cne 'input_image' -or
                                [string]$content[2].type -cne 'input_image' -or
                                [string]$content[1].image_url -cne $referenceUrl -or
                                [string]$content[2].image_url -cne $candidateUrl) {
                                throw 'Review request changed the prompt, image bytes, or Reference-then-Candidate order.'
                            }
                        } catch {
                            Add-VisualValidation "Visual invocation record is unreadable or malformed: $($_.Exception.Message)"
                        }
                        try {
                            $providerResponse = Get-Content -Raw -Encoding UTF8 -LiteralPath `
                                ([string]$stateResult.event_log_path) | ConvertFrom-Json
                            if ([string]$providerResponse.status -cne 'completed' -or
                                [string]$providerResponse.model -cne $expectedModel -or
                                [string]::IsNullOrWhiteSpace([string]$providerResponse.id) -or
                                -not $seenResponseIds.Add([string]$providerResponse.id) -or
                                @($providerResponse.output | Where-Object {
                                    [string]$_.type -notin @('message', 'reasoning') }).Count -ne 0) {
                                throw 'Review response is incomplete, reused, or reports an unexpected model/tool.'
                            }
                            $messages = @($providerResponse.output | Where-Object { [string]$_.type -ceq 'message' })
                            if ($messages.Count -ne 1 -or [string]$messages[0].role -cne 'assistant' -or
                                @($messages[0].content).Count -ne 1 -or
                                [string]$messages[0].content[0].type -cne 'output_text') {
                                throw 'Expected exactly one assistant text response.'
                            }
                            $rawText = Get-Content -Raw -Encoding UTF8 -LiteralPath ([string]$stateResult.raw_response_path)
                            if ([string]$messages[0].content[0].text -cne $rawText) {
                                throw 'Raw review text differs from the retained provider response.'
                            }
                            $rawLines = @($rawText.Trim() -split '\r?\n')
                            $labels = @($frozenVisualPrompt -split '\r?\n' | Where-Object { $_ -match '/2\s*$' })
                            if ($rawLines.Count -ne 7 -or $labels.Count -ne 5) {
                                throw 'Raw review must follow the seven-line rubric.'
                            }
                            for ($criterionIndex = 0; $criterionIndex -lt 5; $criterionIndex++) {
                                $label = ($labels[$criterionIndex] -split '[:\uFF1A]', 2)[0]
                                $match = [regex]::Match($rawLines[$criterionIndex],
                                    '^' + [regex]::Escape($label) + '[:\uFF1A]\s*(?<value>[0-2](?:\.0|\.5)?)/2\s*$')
                                $criterion = $criterionNames[$criterionIndex]
                                if (-not $match.Success -or
                                    [double]::Parse($match.Groups['value'].Value, [Globalization.CultureInfo]::InvariantCulture) -ne
                                    [double]$stateResult.parsed.$criterion) {
                                    throw 'Raw review criteria differ from the reported category scores.'
                                }
                            }
                            $total = [regex]::Match($rawLines[5], '^Total[:\uFF1A]\s*(?<value>\d+(?:\.\d+)?)/10\s*$')
                            if (-not $total.Success -or
                                [double]::Parse($total.Groups['value'].Value, [Globalization.CultureInfo]::InvariantCulture) -ne
                                [double]$stateResult.score -or $rawLines[6] -notmatch '^Reason[:\uFF1A]\s*\S') {
                                throw 'Raw review total or reason is invalid.'
                            }
                        } catch {
                            Add-VisualValidation "Visual provider response is unreadable or inconsistent: $($_.Exception.Message)"
                        }
                    }
                    $sum = 0.0
                    foreach ($criterion in $criterionNames) {
                        $value = [double]$stateResult.parsed.$criterion
                        if ($allowedScores -notcontains $value) {
                            Add-VisualValidation "Visual round $roundNumber state $($expectedState.id) criterion $criterion has an unsupported score."
                        }
                        $sum += $value
                    }
                    if ([Math]::Abs($sum - [double]$stateResult.parsed.score) -gt 0.001 -or
                        [Math]::Abs($sum - [double]$stateResult.score) -gt 0.001) {
                        Add-VisualValidation "Visual round $roundNumber state $($expectedState.id) parsed total is inconsistent."
                    }
                    $observedStateScores.Add([double]$stateResult.score)
                }
                if ($observedStateScores.Count -eq @($rules.visual_states).Count) {
                    $expectedRoundScore = Round-One ([double](
                        ($observedStateScores | Measure-Object -Average).Average))
                    if ([Math]::Abs($expectedRoundScore - [double]$round.score) -gt 0.001) {
                        Add-VisualValidation "Visual round $roundNumber average is inconsistent."
                    }
                    $observedRoundScores.Add([double]$round.score)
                }
            }
            if ($observedRoundScores.Count -eq $expectedRounds) {
                $expectedFinal = Round-One ([double](
                    ($observedRoundScores | Measure-Object -Average).Average))
                if ($null -eq $visual.final_score -or
                    [double]$visual.final_score -lt 0 -or
                    [double]$visual.final_score -gt 10 -or
                    [Math]::Abs($expectedFinal - [double]$visual.final_score) -gt 0.001) {
                    Add-VisualValidation "Visual final_score is absent, out of range, or inconsistent with the three rounds."
                }
            }

            if ($visualValidation.Count -eq 0) {
                $visualScore = Round-One ([double]$visual.final_score)
                $visualStatus = "evaluated"
            }
        } catch {
            Add-VisualValidation "Visual result is unreadable or malformed: $($_.Exception.Message)"
        }
    }
}
$dimensions["D6"] = [pscustomobject]@{
    name = "Visual Assembly & Presentation Fidelity"
    score = $visualScore
    maximum_score = [double]$rules.dimension_maxima.D6
    status = $visualStatus
    validation_reasons = @($visualValidation)
    model_id = [string]$rules.phases.visual.model_id
    prompt_sha256 = [string]$rules.phases.visual.prompt_sha256
    rounds = if ($null -ne $visual) { @($visual.rounds | ForEach-Object {
        if ($null -eq $_.score) { $null } else { Round-One ([double]$_.score) }
    }) } else { @() }
    states = if ($null -ne $visual) { @($visual.states) } else { @($rules.visual_states) }
    prompt = [string]$rules.phases.visual.prompt
}

$automaticScore = $null
if ($evaluatorHealthValid) {
    $automaticScore = 0.0
    foreach ($dimensionId in @("D1", "D2", "D3", "D4", "D5")) {
        $automaticScore += [double]$dimensions[$dimensionId].score
    }
    $automaticScore = Round-One $automaticScore
}
$valid = $validation.Count -eq 0
$formalComplete = $valid -and $visualStatus -eq "evaluated"
$overall = if ($formalComplete) {
    Round-One ($automaticScore + [double]$visualScore)
} else { $null }

$solved = $valid -and $staticFullPass
foreach ($requiredId in @($rules.solved_requires)) {
    if (-not (Test-ItemPassed $allTestResults ([string]$requiredId))) {
        $solved = $false
        break
    }
}
$executable = $valid -and
    (Test-ItemPassed $staticResults "STATIC01_CanonicalSceneLoadsCameraAndAdvancesFrames") -and
    (Test-ItemPassed $staticResults "STATIC02_CameraProducesAVisibleFrame")
$taskSpecificScore = [double]$dimensions["D2"].score +
    [double]$dimensions["D3"].score + [double]$dimensions["D4"].score +
    [double]$dimensions["D5"].score
$status = if (-not $valid) {
    "invalid"
} elseif (-not $staticFullPass) {
    "static_gate_failed"
} elseif ($taskSpecificScore -eq 0) {
    "no_task_implementation"
} elseif ($visualStatus -eq "invalid_visual") {
    "visual_invalid"
} elseif ($solved -and -not $formalComplete) {
    # Stable GAME_INDEPENDENT_SCORING_GUIDE status: pending_visual.
    "pending_visual"
} elseif ($solved) {
    "complete"
} else {
    "partial"
}

$failedScored = @($checkResults | Where-Object { $_.result -ne "Passed" })
$notes = if ($failedScored.Count -gt 0) {
    "$($failedScored[0].id): $($failedScored[0].question)"
} elseif ($visualStatus -eq "invalid_visual") {
    "D6 invalid_visual: " + (@($visualValidation) | Select-Object -First 1)
} elseif (-not $formalComplete) {
    "D6 pending: run the fixed three-round visual comparison before reporting Overall."
} else { "-" }

$binding = if (-not [string]::IsNullOrWhiteSpace($HashBindingPath) -and
    (Test-Path -LiteralPath $HashBindingPath -PathType Leaf)) {
    Get-Content -Raw -Encoding UTF8 -LiteralPath $HashBindingPath | ConvertFrom-Json
} else { $null }

$report = [pscustomobject]@{
    schema_version = [int]$rules.schema_version
    evaluator_protocol = [string]$rules.evaluator_protocol
    generated_utc = [DateTime]::UtcNow.ToString("o")
    engine = "Unity"
    engine_version = "6000.0.80f1"
    game = "There Are Signs - Sign Circuit"
    project_path = $ProjectPath
    valid_score = $valid
    formal_score_complete = $formalComplete
    candidate_status = $status
    validation_reasons = @($validation)
    dimensions = [pscustomobject]$dimensions
    automatic_score = if ($valid) { $automaticScore } else { $null }
    automatic_maximum_score = [double]$rules.automatic_maximum_score
    overall = if ($valid) { $overall } else { $null }
    score = if ($valid) { $overall } else { $null }
    raw_score = if ($valid) { $automaticScore } else { $null }
    maximum_score = [double]$rules.maximum_score
    outcomes = [pscustomobject]@{
        executable = if ($executable) { "Yes" } else { "No" }
        solved = if ($solved) { "Yes" } else { "No" }
        package_valid = "NotEvaluated"
        notes = $notes
    }
    phases = [pscustomobject]@{
        static = [pscustomobject]@{ method = "static"; full_pass = $staticFullPass; tests = @($staticResults) }
        dynamic = [pscustomobject]@{ method = "dynamic"; skipped = -not $staticFullPass; tests = @($dynamicResults) }
        fresh = [pscustomobject]@{ method = "dynamic_reopen"; skipped = -not $staticFullPass; tests = @($freshResults) }
        visual = [pscustomobject]@{
            method = "fixed_vlm_prompt"
            status = $visualStatus
            result_path = $VisualResultPath
            validation_reasons = @($visualValidation)
        }
    }
    evidence_binding = [pscustomobject]@{
        directory = $EvidenceDirectory
        evaluation_session_id = $EvaluationSessionId
        dynamic_process_id = $DynamicProcessId
        fresh_process_id = $FreshProcessId
        dynamic_started_utc = $DynamicStartedUtc
        dynamic_completed_utc = $DynamicCompletedUtc
        fresh_started_utc = $FreshStartedUtc
        fresh_completed_utc = $FreshCompletedUtc
        tests = @($evidenceAudit)
    }
    scoring_checks = @($checkResults)
    prerequisites = @($rules.prerequisites | ForEach-Object {
        [pscustomobject]@{
            id = [string]$_.id
            source_test_id = [string]$_.source_test_id
            result = if (Test-ItemPassed $allTestResults ([string]$_.source_test_id)) {
                "Passed"
            } else { "Failed" }
            effect = [string]$_.effect
        }
    })
    evaluator_health = @($rules.health_prerequisites | ForEach-Object {
        $healthItem = Find-PhaseItem $allTestResults ([string]$_.source_test_id)
        [pscustomobject]@{
            id = [string]$_.id
            phase = [string]$_.phase
            source_test_id = [string]$_.source_test_id
            result = if ($null -eq $healthItem) { "Missing" } else {
                [string]$healthItem.result
            }
            evidence_status = if ($null -eq $healthItem) { "missing" } else {
                [string]$healthItem.evidence_status
            }
            effect = [string]$_.effect
        }
    })
    legacy_diagnostics = [pscustomobject]@{
        note = "Legacy caps are no longer applied to Overall; Solved and per-dimension failures carry the core-flow meaning."
        static_full_pass = $staticFullPass
        failed_scoring_check_ids = @($failedScored | ForEach-Object { $_.id })
    }
    hash_binding = $binding
}

$json = $report | ConvertTo-Json -Depth 20
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($OutputPath, $json,
        [System.Text.UTF8Encoding]::new($false))
}
$json
if (-not $valid -and -not $NoExitOnInvalid) { exit 3 }
