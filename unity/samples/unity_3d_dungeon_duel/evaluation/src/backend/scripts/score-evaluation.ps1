[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$StaticResultPath,

    [Parameter(Mandatory = $true)]
    [string]$DynamicResultPath,

    [Parameter(Mandatory = $true)]
    [string]$EvidenceDirectory,

    [Parameter(Mandatory = $true)]
    [string]$FreshResultPath,

    [Parameter(Mandatory = $true)]
    [string]$FreshEvidenceDirectory,

    [string]$ProjectPath = "",

    [int]$StaticExitCode = 0,

    [int]$DynamicExitCode = 0,

    [int]$FreshExitCode = 0,

    [int]$DynamicProcessId = 0,

    [int]$FreshProcessId = 0,

    [string]$RulesPath = "",

    [string]$DefinitionsDirectory = "",

    [string]$VisualScorePath = "",

    [string]$OutputPath = "",

    [switch]$NoExitOnInvalid
)

$ErrorActionPreference = "Stop"
$evaluationRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RulesPath)) {
    $RulesPath = Join-Path $evaluationRoot "rules.json"
}
if ([string]::IsNullOrWhiteSpace($DefinitionsDirectory)) {
    $DefinitionsDirectory = Join-Path $evaluationRoot `
        "package\Tests\Dynamic\Resources\TrajectoryDefinitions"
}

$RulesPath = (Resolve-Path -LiteralPath $RulesPath).Path
$DefinitionsDirectory = (Resolve-Path -LiteralPath $DefinitionsDirectory).Path
$StaticResultPath = (Resolve-Path -LiteralPath $StaticResultPath).Path
$DynamicResultPath = (Resolve-Path -LiteralPath $DynamicResultPath).Path
$FreshResultPath = (Resolve-Path -LiteralPath $FreshResultPath).Path
$evidenceDirectoryExists = Test-Path -LiteralPath $EvidenceDirectory -PathType Container
$EvidenceDirectory = if ($evidenceDirectoryExists) {
    (Resolve-Path -LiteralPath $EvidenceDirectory).Path
} else {
    [System.IO.Path]::GetFullPath($EvidenceDirectory)
}
$freshEvidenceDirectoryExists = Test-Path -LiteralPath $FreshEvidenceDirectory -PathType Container
$FreshEvidenceDirectory = if ($freshEvidenceDirectoryExists) {
    (Resolve-Path -LiteralPath $FreshEvidenceDirectory).Path
} else {
    [System.IO.Path]::GetFullPath($FreshEvidenceDirectory)
}
if (-not [string]::IsNullOrWhiteSpace($ProjectPath) -and
    (Test-Path -LiteralPath $ProjectPath)) {
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
}

$rules = Get-Content -Raw -Encoding UTF8 -LiteralPath $RulesPath | ConvertFrom-Json
$validationReasons = [System.Collections.Generic.List[string]]::new()
$visualValidationReasons = [System.Collections.Generic.List[string]]::new()
$capabilityScores = @{}
$capabilityCheckpointTotals = @{}
$capabilityCheckpointPasses = @{}
foreach ($capability in @($rules.capabilities)) {
    $capabilityScores[[string]$capability.id] = 0.0
    $capabilityCheckpointTotals[[string]$capability.id] = 0
    $capabilityCheckpointPasses[[string]$capability.id] = 0
}

function Add-ValidationReason([string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Message) -and
        -not $validationReasons.Contains($Message)) {
        $validationReasons.Add($Message)
    }
}

function Add-VisualValidationReason([string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Message) -and
        -not $visualValidationReasons.Contains($Message)) {
        $visualValidationReasons.Add($Message)
    }
}

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Round-Score([double]$Value) {
    return [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero)
}

function Round-Internal([double]$Value) {
    return [Math]::Round($Value, 10, [MidpointRounding]::AwayFromZero)
}

function Get-CheckpointValue([string]$CapabilityId) {
    $capability = @($rules.capabilities | Where-Object {
        [string]$_.id -eq $CapabilityId
    }) | Select-Object -First 1
    if ($null -eq $capability -or [int]$capability.checkpoint_count -le 0) {
        return 0.0
    }
    return Round-Internal (
        [double]$capability.maximum_score / [int]$capability.checkpoint_count)
}

function Get-NUnitCases([string]$Path, [string]$PhaseName) {
    try {
        [xml]$document = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
        $cases = @($document.SelectNodes("//test-case"))
        if ($cases.Count -eq 0) {
            Add-ValidationReason "$PhaseName result XML contains no discovered test cases."
        }
        return $cases
    }
    catch {
        Add-ValidationReason "$PhaseName result XML is unreadable: $($_.Exception.Message)"
        return @()
    }
}

function Find-NUnitCase($Cases, [string]$MethodName) {
    return @($Cases | Where-Object {
        ([string]$_.methodname -eq $MethodName) -or
        ([string]$_.name -eq $MethodName)
    })
}

function Get-NUnitMessage($Case) {
    if ($null -eq $Case) {
        return "missing"
    }
    $failure = $Case.SelectSingleNode("failure/message")
    if ($null -ne $failure) {
        return ([string]$failure.InnerText).Trim()
    }
    $output = $Case.SelectSingleNode("output")
    if ($null -ne $output -and -not [string]::IsNullOrWhiteSpace($output.InnerText)) {
        return ([string]$output.InnerText).Trim()
    }
    return ""
}

function Get-NUnitStackTrace($Case) {
    if ($null -eq $Case) { return "" }
    $stack = $Case.SelectSingleNode("failure/stack-trace")
    if ($null -eq $stack) { return "" }
    return ([string]$stack.InnerText).Trim()
}

function Test-CandidateStaticFailure($Case, [string]$Message, [string]$Marker) {
    if ($Message.Contains($Marker)) { return $true }
    $normalizedStack = (Get-NUnitStackTrace $Case).Replace('\', '/')
    return $normalizedStack -match
        '(?im)(?:^|[\s(])(?:[A-Za-z]:/[^)\r\n]*/)?Assets/[^)\r\n]+\.cs:\d+'
}

function Test-EvaluatorHealthPrerequisites(
    [string]$PhaseKey,
    $Cases,
    [string]$EvidenceRoot,
    [int]$ExpectedProcessId,
    [int]$ExpectedPriorProcessId = 0
) {
    $healthProperty = $rules.health_prerequisites.PSObject.Properties[$PhaseKey]
    if ($null -eq $healthProperty) {
        Add-ValidationReason "invalid_evaluator_health: $PhaseKey health prerequisites are not declared."
        return
    }
    $health = $healthProperty.Value
    foreach ($testName in @($health.required_tests)) {
        $matches = @(Find-NUnitCase $Cases ([string]$testName))
        if ($matches.Count -ne 1) {
            Add-ValidationReason "invalid_evaluator_health: expected exactly one $PhaseKey health test $testName, found $($matches.Count)."
        } elseif ([string]$matches[0].result -ne "Passed") {
            Add-ValidationReason "invalid_evaluator_health: $PhaseKey health test $testName returned $([string]$matches[0].result)."
        }
    }
    foreach ($artifactName in @($health.required_artifacts)) {
        $artifactPath = Join-Path $EvidenceRoot ([string]$artifactName)
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            Add-ValidationReason "invalid_evaluator_health: missing $PhaseKey health artifact $artifactName."
            continue
        }
        try {
            $artifact = Get-Content -Raw -Encoding UTF8 -LiteralPath $artifactPath |
                ConvertFrom-Json
            if ([string]$artifact.evaluator_health -ne "passed") {
                Add-ValidationReason "invalid_evaluator_health: $PhaseKey artifact did not report passed."
            }
            if ($ExpectedProcessId -le 0 -or
                [int]$artifact.process_id -ne $ExpectedProcessId) {
                Add-ValidationReason "invalid_evaluator_health: $PhaseKey artifact process binding mismatch."
            }
            if ($PhaseKey -eq "fresh" -and
                [int]$artifact.prior_process_id -ne $ExpectedPriorProcessId) {
                Add-ValidationReason "invalid_evaluator_health: Fresh artifact prior-process binding mismatch."
            }
        }
        catch {
            Add-ValidationReason "invalid_evaluator_health: $PhaseKey health artifact is unreadable: $($_.Exception.Message)"
        }
    }
}

function Test-NativeInputEvidence($Step, [string]$TrajectoryId) {
    $operation = [string]$Step.operation
    $isMouse = $operation.StartsWith("virtual_mouse_", [StringComparison]::Ordinal)
    $isKeyboard = $operation.StartsWith("virtual_keyboard_", [StringComparison]::Ordinal) -or
        $operation.StartsWith("wait_then_virtual_keyboard_", [StringComparison]::Ordinal)
    if (-not $isMouse -and -not $isKeyboard) {
        return $true
    }

    $routePassed = @($Step.checks | Where-Object {
        [string]$_.status -eq "pass" -and
        (([string]$_.check_id).EndsWith(".input.route", [StringComparison]::Ordinal) -or
         ([string]$_.check_id).EndsWith(".pointer.route", [StringComparison]::Ordinal))
    }).Count -gt 0
    if (-not $routePassed) {
        return $true
    }

    $valid = $true
    $events = @($Step.input_action_events)
    $performed = @($events | Where-Object { [string]$_.phase -eq "performed" })
    $deviceId = if ($isMouse) { [int]$Step.mouse_device_id } else { [int]$Step.keyboard_device_id }
    if ($deviceId -le 0) {
        Add-ValidationReason "Native input evidence has no positive device ID in $TrajectoryId/$($Step.step_id)."
        $valid = $false
    }

    $expectedControl = if ($operation -eq "virtual_mouse_left") {
        "/leftButton"
    } elseif ($operation -eq "virtual_mouse_right") {
        "/rightButton"
    } elseif ($operation -eq "virtual_mouse_move") {
        "/position"
    } elseif ($operation.EndsWith("_2", [StringComparison]::OrdinalIgnoreCase)) {
        "/2"
    } elseif ($operation.EndsWith("_r", [StringComparison]::OrdinalIgnoreCase)) {
        "/r"
    } else {
        ""
    }

    $matchingPerformed = @($performed | Where-Object {
        [int]$_.device_id -eq $deviceId -and
        (-not [string]::IsNullOrWhiteSpace($expectedControl)) -and
        ([string]$_.control_path).EndsWith($expectedControl, [StringComparison]::OrdinalIgnoreCase)
    })
    # Direct Mouse.current / Keyboard.current polling is a normal Input System
    # consumption path and intentionally has no candidate InputAction callback.
    # When callbacks exist, retain their frame/device binding as an additional
    # diagnostic integrity check; their absence must not invalidate the route.
    foreach ($event in $matchingPerformed) {
        if ([int]$event.frame -lt [int]$Step.frame_start -or
            [int]$event.frame -gt [int]$Step.frame_end) {
            Add-ValidationReason "InputAction callback frame lies outside its injected step in $TrajectoryId/$($Step.step_id)."
            $valid = $false
            break
        }
    }

    if ($isMouse) {
        if ([int]$Step.screen_width -le 0 -or [int]$Step.screen_height -le 0 -or
            [double]$Step.screen_x -lt 0 -or [double]$Step.screen_x -gt [int]$Step.screen_width -or
            [double]$Step.screen_y -lt 0 -or [double]$Step.screen_y -gt [int]$Step.screen_height) {
            Add-ValidationReason "Mouse input coordinate is outside the recorded render surface in $TrajectoryId/$($Step.step_id)."
            $valid = $false
        }
        if ($operation -ne "virtual_mouse_move" -and
            ([string]::IsNullOrWhiteSpace([string]$Step.top_hit) -or
             [string]$Step.top_hit -eq "<none>")) {
            Add-ValidationReason "A passed 3D mouse route has no Physics top-hit in $TrajectoryId/$($Step.step_id)."
            $valid = $false
        }
    }

    return $valid
}

$staticRules = @($rules.phases.static.tests)
$dynamicRules = @($rules.phases.dynamic.trajectories)
$freshRule = $rules.phases.fresh.test
$automatedMaximum = [double]$rules.automated_maximum_score
$declaredCapabilityMaximum = (@($rules.capabilities) |
    Measure-Object -Property maximum_score -Sum).Sum
if ([double]$declaredCapabilityMaximum -ne $automatedMaximum) {
    Add-ValidationReason "D1-D5 maxima do not sum to the automated maximum."
}

$checkpointIds = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($item in $staticRules) {
    if (-not [bool]$item.scored_checkpoint -or [string]$item.dimension -ne "D1") {
        Add-ValidationReason "Static test $($item.id) must be one scored D1 checkpoint."
    }
    if (-not $checkpointIds.Add([string]$item.id)) {
        Add-ValidationReason "Duplicate scored checkpoint ID $($item.id)."
    }
    if ($capabilityCheckpointTotals.ContainsKey("D1")) {
        $capabilityCheckpointTotals["D1"]++
    }
}
foreach ($item in $dynamicRules) {
    $milestones = @($item.milestones)
    if (@($milestones.id | Select-Object -Unique).Count -ne $milestones.Count) {
        Add-ValidationReason "Trajectory $($item.id) contains duplicate milestone IDs."
    }
    foreach ($milestone in $milestones) {
        if (-not $capabilityScores.ContainsKey([string]$milestone.capability)) {
            Add-ValidationReason "Milestone $($milestone.id) references an unknown capability."
        }
        if (@($milestone.required_check_ids).Count -eq 0) {
            Add-ValidationReason "Milestone $($milestone.id) contains no semantic check IDs."
        }
        if ([bool]$milestone.scored_checkpoint) {
            if ([bool]$item.prerequisite_only) {
                Add-ValidationReason "Prerequisite trajectory $($item.id) cannot contain scored checkpoints."
            }
            if (-not $checkpointIds.Add([string]$milestone.id)) {
                Add-ValidationReason "Duplicate scored checkpoint ID $($milestone.id)."
            }
            $capabilityId = [string]$milestone.capability
            if ($capabilityCheckpointTotals.ContainsKey($capabilityId)) {
                $capabilityCheckpointTotals[$capabilityId]++
            }
        }
    }
}
if (-not $capabilityScores.ContainsKey([string]$freshRule.capability)) {
    Add-ValidationReason "Fresh test references an unknown capability."
}
if (@($freshRule.required_check_ids).Count -eq 0) {
    Add-ValidationReason "Fresh test contains no semantic check IDs."
}
if (-not [bool]$freshRule.scored_checkpoint) {
    Add-ValidationReason "Fresh lifecycle test must be a scored checkpoint."
} elseif ([string]::IsNullOrWhiteSpace([string]$freshRule.checkpoint_id)) {
    Add-ValidationReason "Fresh lifecycle test has no formal checkpoint_id."
} elseif (-not $checkpointIds.Add([string]$freshRule.checkpoint_id)) {
    Add-ValidationReason "Duplicate scored checkpoint ID $($freshRule.checkpoint_id)."
} elseif ($capabilityCheckpointTotals.ContainsKey([string]$freshRule.capability)) {
    $capabilityCheckpointTotals[[string]$freshRule.capability]++
}
foreach ($capability in @($rules.capabilities)) {
    $capabilityId = [string]$capability.id
    if ([int]$capability.checkpoint_count -le 0 -or
        [int]$capabilityCheckpointTotals[$capabilityId] -ne
        [int]$capability.checkpoint_count) {
        Add-ValidationReason "Capability $capabilityId scored-checkpoint count does not match its declaration."
    }
}
if (-not [bool]$rules.formal_scoring.legal_failed_nunit_is_evidence_envelope -or
    -not [bool]$rules.formal_scoring.legal_failed_nunit_does_not_zero_passed_checkpoints) {
    Add-ValidationReason "Formal scoring must preserve independently passed checkpoints inside a legal Failed NUnit trajectory."
}
$expectedDynamicMaximum = 0.0
foreach ($capability in @($rules.capabilities | Where-Object { [string]$_.id -ne "D1" })) {
    $capabilityId = [string]$capability.id
    $freshCount = if ($capabilityId -eq [string]$freshRule.capability) { 1 } else { 0 }
    $dynamicCount = [int]$capability.checkpoint_count - $freshCount
    $expectedDynamicMaximum += (Get-CheckpointValue $capabilityId) * $dynamicCount
}
$expectedDynamicMaximum = Round-Score $expectedDynamicMaximum
$expectedFreshMaximum = Round-Score (Get-CheckpointValue ([string]$freshRule.capability))
if ([double]$rules.phases.static.maximum_score -ne 10.0 -or
    [double]$rules.phases.dynamic.maximum_score -ne $expectedDynamicMaximum -or
    [double]$rules.phases.fresh.maximum_score -ne $expectedFreshMaximum) {
    Add-ValidationReason "Phase maxima do not match the equal-checkpoint dimension formula."
}

$acceptedExitCodes = @($rules.accepted_unity_exit_codes | ForEach-Object { [int]$_ })
if ($acceptedExitCodes -notcontains $StaticExitCode) {
    Add-ValidationReason "Static Unity exit code $StaticExitCode is an infrastructure error."
}
if ($acceptedExitCodes -notcontains $DynamicExitCode) {
    Add-ValidationReason "Dynamic Unity exit code $DynamicExitCode is an infrastructure error."
}
if ($acceptedExitCodes -notcontains $FreshExitCode) {
    Add-ValidationReason "Fresh Unity exit code $FreshExitCode is an infrastructure error."
}
if ($DynamicProcessId -le 0 -or $FreshProcessId -le 0 -or
    $DynamicProcessId -eq $FreshProcessId) {
    Add-ValidationReason "invalid_evaluator_health: Dynamic and Fresh process IDs are missing or not independent."
}

$staticCases = @(Get-NUnitCases $StaticResultPath "Static")
$staticResults = [System.Collections.Generic.List[object]]::new()
$staticPassedCheckpoints = 0
$candidateStaticMarker = "[OMNIGAME_CANDIDATE_STATIC]"
foreach ($testRule in $staticRules) {
    $matches = @(Find-NUnitCase $staticCases ([string]$testRule.id))
    if ($matches.Count -ne 1) {
        Add-ValidationReason "invalid_evaluator_health: expected exactly one Static test case $($testRule.id), found $($matches.Count)."
    }
    $case = if ($matches.Count -gt 0) { $matches[0] } else { $null }
    $result = if ($null -eq $case) { "Missing" } else { [string]$case.result }
    $message = Get-NUnitMessage $case
    $candidateStaticFailure = $result -eq "Failed" -and
        (Test-CandidateStaticFailure $case $message $candidateStaticMarker)
    $passedCheckpoint = if ($result -eq "Passed") {
        $true
    } elseif ($candidateStaticFailure) {
        $false
    } else {
        if ($result -eq "Failed") {
            Add-ValidationReason "invalid_evaluator_health: Static test $($testRule.id) failed without the stable candidate marker or a candidate Assets source frame."
        } elseif ($result -ne "Missing") {
            Add-ValidationReason "invalid_evaluator_health: Static test $($testRule.id) returned unsupported result '$result'."
        }
        $false
    }
    if ($passedCheckpoint) {
        $staticPassedCheckpoints++
        $capabilityCheckpointPasses["D1"]++
    }
    $checkpointValue = Get-CheckpointValue "D1"
    $staticResults.Add([pscustomobject]@{
        id = [string]$testRule.id
        result = $result
        checkpoint_passed = $passedCheckpoint
        score = if ($passedCheckpoint) { $checkpointValue } else { 0.0 }
        maximum_score = $checkpointValue
        diagnostic_weight = [double]$testRule.diagnostic_weight
        message = $message
    })
}
$staticScore = Round-Score (
    10.0 * $staticPassedCheckpoints / [Math]::Max(1, $staticRules.Count))
$staticFullPass = @($staticResults | Where-Object {
    -not [bool]$_.checkpoint_passed
}).Count -eq 0

$dynamicCases = @(Get-NUnitCases $DynamicResultPath "Dynamic")
$freshCases = @(Get-NUnitCases $FreshResultPath "Fresh")
Test-EvaluatorHealthPrerequisites "dynamic" $dynamicCases `
    $EvidenceDirectory $DynamicProcessId
Test-EvaluatorHealthPrerequisites "fresh" $freshCases `
    $FreshEvidenceDirectory $FreshProcessId $DynamicProcessId
$trajectoryResults = [System.Collections.Generic.List[object]]::new()
$dynamicScore = 0.0
foreach ($trajectoryRule in $dynamicRules) {
    $trajectoryId = [string]$trajectoryRule.id
    $nunitMatches = @(Find-NUnitCase $dynamicCases ([string]$trajectoryRule.nunit_test))
    if ($nunitMatches.Count -ne 1) {
        Add-ValidationReason "invalid_evaluator_health: expected exactly one Dynamic test case $($trajectoryRule.nunit_test), found $($nunitMatches.Count)."
    }
    $nunitCase = if ($nunitMatches.Count -gt 0) { $nunitMatches[0] } else { $null }
    $nunitResult = if ($null -eq $nunitCase) { "Missing" } else { [string]$nunitCase.result }
    $nunitMessage = Get-NUnitMessage $nunitCase
    if ($nunitResult -ne "Passed" -and $nunitResult -ne "Failed" -and
        $nunitResult -ne "Missing") {
        Add-ValidationReason "invalid_evaluator_health: Dynamic test $($trajectoryRule.nunit_test) returned unsupported result '$nunitResult'."
    }
    $knownCandidateSetupFailure = $nunitResult -eq "Failed" -and (
        $nunitMessage -match "couldn't be loaded because it has not been added" -or
        $nunitMessage -match "canonical Dungeon Duel scene is missing from the active build profile" -or
        $nunitMessage -match "setup\.scene_load")

    $definitionPath = Join-Path $DefinitionsDirectory "$trajectoryId.json"
    $evidencePath = Join-Path $EvidenceDirectory "$trajectoryId.json"
    $definition = $null
    $evidence = $null
    $expectedIds = @()
    $actualChecks = @()
    $definitionValid = $true
    $evidenceValid = $true
    $evidenceSource = "trajectory_evidence"

    if (-not (Test-Path -LiteralPath $definitionPath -PathType Leaf)) {
        Add-ValidationReason "Missing trajectory definition: $trajectoryId"
        $definitionValid = $false
    } else {
        try {
            $definition = Get-Content -Raw -Encoding UTF8 -LiteralPath $definitionPath |
                ConvertFrom-Json
            foreach ($step in @($definition.steps)) {
                foreach ($checkId in @($step.check_ids)) {
                    $expectedIds += [string]$checkId
                }
            }
            if ($expectedIds.Count -eq 0) {
                Add-ValidationReason "Trajectory definition $trajectoryId contains no check IDs."
                $definitionValid = $false
            }
            if (@($expectedIds | Select-Object -Unique).Count -ne $expectedIds.Count) {
                Add-ValidationReason "Trajectory definition $trajectoryId contains duplicate check IDs."
                $definitionValid = $false
            }
        }
        catch {
            Add-ValidationReason "Trajectory definition $trajectoryId is unreadable: $($_.Exception.Message)"
            $definitionValid = $false
        }
    }

    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        if ($knownCandidateSetupFailure) {
            $evidenceSource = "synthetic_blocked_from_nunit_setup_failure"
        } else {
            Add-ValidationReason "invalid_evaluator_health: missing trajectory evidence for $trajectoryId."
            $evidenceValid = $false
        }
    } else {
        try {
            $evidence = Get-Content -Raw -Encoding UTF8 -LiteralPath $evidencePath |
                ConvertFrom-Json
            foreach ($step in @($evidence.steps)) {
                foreach ($check in @($step.checks)) {
                    $actualChecks += $check
                }
                if (-not (Test-NativeInputEvidence $step $trajectoryId)) {
                    $evidenceValid = $false
                }
            }
            if ([string]$evidence.trajectory_id -ne $trajectoryId) {
                Add-ValidationReason "Trajectory evidence ID mismatch for $trajectoryId."
                $evidenceValid = $false
            }
            if ([string]$evidence.evaluator_protocol -ne [string]$rules.evaluator_protocol) {
                Add-ValidationReason "Evaluator protocol mismatch for $trajectoryId."
                $evidenceValid = $false
            }
            if ($definitionValid) {
                $definitionHash = (Get-FileHash -LiteralPath $definitionPath -Algorithm SHA256).Hash
                if (-not [string]::Equals($definitionHash,
                        [string]$evidence.definition_sha256,
                        [StringComparison]::OrdinalIgnoreCase)) {
                    Add-ValidationReason "Trajectory definition hash mismatch for $trajectoryId."
                    $evidenceValid = $false
                }
            }
        }
        catch {
            Add-ValidationReason "Trajectory evidence $trajectoryId is unreadable: $($_.Exception.Message)"
            $evidenceValid = $false
        }
    }

    $checkMap = @{}
    $unexpectedIds = [System.Collections.Generic.List[string]]::new()
    foreach ($check in $actualChecks) {
        $checkId = [string]$check.check_id
        if ([string]::IsNullOrWhiteSpace($checkId) -or $checkMap.ContainsKey($checkId)) {
            Add-ValidationReason "Trajectory evidence $trajectoryId contains an empty or duplicate check ID."
            $evidenceValid = $false
            continue
        }
        $checkMap[$checkId] = $check
        if ($definitionValid -and $expectedIds -notcontains $checkId) {
            $unexpectedIds.Add($checkId)
        }
    }
    if ($unexpectedIds.Count -gt 0) {
        Add-ValidationReason "Trajectory evidence $trajectoryId contains unexpected check IDs."
        $evidenceValid = $false
    }

    $passed = 0
    $failed = 0
    $blocked = 0
    $missing = 0
    foreach ($checkId in $expectedIds) {
        if (-not $checkMap.ContainsKey($checkId)) {
            $missing++
            continue
        }
        $status = ([string]$checkMap[$checkId].status).ToLowerInvariant()
        switch ($status) {
            "pass" { $passed++ }
            "fail" { $failed++ }
            "blocked" { $blocked++ }
            default {
                Add-ValidationReason "Trajectory evidence $trajectoryId contains invalid status '$status'."
                $evidenceValid = $false
                $failed++
            }
        }
    }

    if ($null -ne $evidence) {
        if ([int]$evidence.checks_passed -ne $passed -or
            [int]$evidence.checks_failed -ne $failed -or
            [int]$evidence.checks_blocked -ne $blocked) {
            Add-ValidationReason "Trajectory evidence summary counts mismatch for $trajectoryId."
            $evidenceValid = $false
        }
        $computedEvidencePass = $missing -eq 0 -and $failed -eq 0 -and
            $blocked -eq 0 -and $passed -eq $expectedIds.Count
        if ([bool]$evidence.passed -ne $computedEvidencePass) {
            Add-ValidationReason "invalid_evaluator_health: trajectory $trajectoryId evidence pass flag contradicts its check verdicts."
            $evidenceValid = $false
        }
    }
    if ($null -ne $evidence -and $missing -gt 0) {
        Add-ValidationReason "invalid_evaluator_health: trajectory $trajectoryId evidence is incomplete."
        $evidenceValid = $false
    }

    $evidenceCompletePass = $definitionValid -and $evidenceValid -and
        $null -ne $evidence -and $missing -eq 0 -and $failed -eq 0 -and
        $blocked -eq 0 -and $passed -eq $expectedIds.Count -and
        [bool]$evidence.passed
    $evidenceCandidateFailure = $definitionValid -and $evidenceValid -and
        $null -ne $evidence -and $missing -eq 0 -and $failed -gt 0 -and
        -not [bool]$evidence.passed
    $legalCandidateNUnitFailure = $nunitResult -eq "Failed" -and (
        $evidenceCandidateFailure -or
        ($knownCandidateSetupFailure -and $null -eq $evidence))
    if ($nunitResult -eq "Passed" -and -not $evidenceCompletePass) {
        Add-ValidationReason "invalid_evaluator_health: Dynamic NUnit passed but trajectory evidence did not fully pass for $trajectoryId."
    } elseif ($nunitResult -eq "Failed" -and $evidenceCompletePass) {
        Add-ValidationReason "invalid_evaluator_health: Dynamic NUnit failed after all trajectory evidence passed for $trajectoryId."
    } elseif ($nunitResult -eq "Failed" -and -not $legalCandidateNUnitFailure) {
        Add-ValidationReason "invalid_evaluator_health: Dynamic NUnit failure for $trajectoryId has no explicit candidate-failure evidence."
    }
    # NUnit is the integrity envelope for one trajectory, not a global score
    # switch for every independent milestone carried by that trajectory.  A
    # sealed candidate-origin Failed result remains a valid envelope; each
    # milestone is then judged only by its own declared semantic checks.
    $trajectoryEvidenceEnvelopeValid =
        ($nunitResult -eq "Passed" -and $evidenceCompletePass) -or
        ($nunitResult -eq "Failed" -and $legalCandidateNUnitFailure)

    $milestoneResults = [System.Collections.Generic.List[object]]::new()
    $earned = 0.0
    $scoredCheckpointCount = 0
    $passedScoredCheckpointCount = 0
    foreach ($milestone in @($trajectoryRule.milestones)) {
        $failedChecks = [System.Collections.Generic.List[object]]::new()
        foreach ($requiredCheckId in @($milestone.required_check_ids)) {
            $requiredCheckId = [string]$requiredCheckId
            if ($expectedIds -notcontains $requiredCheckId) {
                Add-ValidationReason "Milestone $($milestone.id) references undeclared check $requiredCheckId."
                $failedChecks.Add([pscustomobject]@{
                    check_id = $requiredCheckId
                    status = "undeclared"
                })
                continue
            }
            if (-not $checkMap.ContainsKey($requiredCheckId)) {
                $failedChecks.Add([pscustomobject]@{
                    check_id = $requiredCheckId
                    status = "missing"
                })
                continue
            }
            $requiredStatus = ([string]$checkMap[$requiredCheckId].status).ToLowerInvariant()
            if ($requiredStatus -ne "pass") {
                $failedChecks.Add([pscustomobject]@{
                    check_id = $requiredCheckId
                    status = $requiredStatus
                    blocked_by = [string]$checkMap[$requiredCheckId].blocked_by
                })
            }
        }
        if (-not $trajectoryEvidenceEnvelopeValid) {
            $failedChecks.Add([pscustomobject]@{
                check_id = "<nunit:$($trajectoryRule.nunit_test)>"
                status = if ($nunitResult -eq "Failed") {
                    "nunit_failed"
                } else {
                    "nunit_invalid"
                }
            })
        }
        $milestonePassed = $failedChecks.Count -eq 0 -and
            $trajectoryEvidenceEnvelopeValid
        $isScoredCheckpoint = [bool]$milestone.scored_checkpoint
        $checkpointValue = if ($isScoredCheckpoint) {
            Get-CheckpointValue ([string]$milestone.capability)
        } else { 0.0 }
        $milestoneEarned = if ($milestonePassed -and $isScoredCheckpoint) {
            $checkpointValue
        } else { 0.0 }
        if ($isScoredCheckpoint) {
            $scoredCheckpointCount++
            if ($milestonePassed) {
                $passedScoredCheckpointCount++
                $capabilityId = [string]$milestone.capability
                $capabilityCheckpointPasses[$capabilityId]++
            }
        }
        $earned += $milestoneEarned
        $milestoneResults.Add([pscustomobject]@{
            id = [string]$milestone.id
            title = [string]$milestone.title
            capability = [string]$milestone.capability
            scored_checkpoint = $isScoredCheckpoint
            passed = $milestonePassed
            score = Round-Internal $milestoneEarned
            maximum_score = Round-Internal $checkpointValue
            diagnostic_weight = [double]$milestone.diagnostic_weight
            required_check_ids = @($milestone.required_check_ids)
            failed_checks = @($failedChecks)
        })
    }
    $earned = Round-Internal $earned
    $dynamicScore += $earned
    $semanticFullPass = $nunitResult -eq "Passed" -and $evidenceCompletePass -and
        @($milestoneResults | Where-Object { -not $_.passed }).Count -eq 0
    $diagnosticFullPass = $semanticFullPass -and $evidenceCompletePass
    $ratio = if ($scoredCheckpointCount -gt 0) {
        $passedScoredCheckpointCount / [double]$scoredCheckpointCount
    } else {
        if ($semanticFullPass) { 1.0 } else { 0.0 }
    }
    $trajectoryMaximum = Round-Score ((@($trajectoryRule.milestones |
        Where-Object { [bool]$_.scored_checkpoint } | ForEach-Object {
            Get-CheckpointValue ([string]$_.capability)
        }) | Measure-Object -Sum).Sum)

    $trajectoryResults.Add([pscustomobject]@{
        id = $trajectoryId
        nunit_test = [string]$trajectoryRule.nunit_test
        nunit_result = $nunitResult
        evidence_envelope_valid = $trajectoryEvidenceEnvelopeValid
        full_pass = $semanticFullPass
        diagnostic_full_pass = $diagnosticFullPass
        score = Round-Score $earned
        maximum_score = $trajectoryMaximum
        diagnostic_weight = [double]$trajectoryRule.diagnostic_weight
        completion_ratio = Round-Score $ratio
        checks = [pscustomobject]@{
            expected = $expectedIds.Count
            passed = $passed
            failed = $failed
            blocked = $blocked
            missing = $missing
        }
        milestones = @($milestoneResults)
        evidence = $evidencePath
        evidence_source = $evidenceSource
        nunit_message = $nunitMessage
    })
}
$dynamicScore = Round-Score $dynamicScore

$freshId = [string]$freshRule.id
$freshNUnitMatches = @(Find-NUnitCase $freshCases ([string]$freshRule.nunit_test))
if ($freshNUnitMatches.Count -ne 1) {
    Add-ValidationReason "invalid_evaluator_health: expected exactly one Fresh test case $($freshRule.nunit_test), found $($freshNUnitMatches.Count)."
}
$freshNUnitCase = if ($freshNUnitMatches.Count -gt 0) { $freshNUnitMatches[0] } else { $null }
$freshNUnitResult = if ($null -eq $freshNUnitCase) { "Missing" } else {
    [string]$freshNUnitCase.result
}
if ($freshNUnitResult -ne "Passed" -and $freshNUnitResult -ne "Failed" -and
    $freshNUnitResult -ne "Missing") {
    Add-ValidationReason "invalid_evaluator_health: Fresh test returned unsupported result '$freshNUnitResult'."
}
$freshNUnitMessage = Get-NUnitMessage $freshNUnitCase
$freshDefinitionPath = Join-Path $DefinitionsDirectory ([string]$freshRule.definition)
if ([string]::IsNullOrWhiteSpace([string]$freshRule.definition)) {
    $freshDefinitionPath = Join-Path $DefinitionsDirectory "$freshId.json"
}
$freshEvidencePath = Join-Path $FreshEvidenceDirectory "$freshId.json"
$freshExpectedIds = @()
$freshActualChecks = @()
$freshDefinitionValid = $true
$freshEvidenceValid = $true
$freshEvidence = $null
if (-not (Test-Path -LiteralPath $freshDefinitionPath -PathType Leaf)) {
    Add-ValidationReason "Missing Fresh trajectory definition: $freshId"
    $freshDefinitionValid = $false
} else {
    try {
        $freshDefinition = Get-Content -Raw -Encoding UTF8 -LiteralPath $freshDefinitionPath |
            ConvertFrom-Json
        foreach ($step in @($freshDefinition.steps)) {
            foreach ($checkId in @($step.check_ids)) {
                $freshExpectedIds += [string]$checkId
            }
        }
        if ($freshExpectedIds.Count -eq 0 -or
            @($freshExpectedIds | Select-Object -Unique).Count -ne $freshExpectedIds.Count) {
            Add-ValidationReason "Fresh trajectory definition has no checks or duplicate check IDs."
            $freshDefinitionValid = $false
        }
    }
    catch {
        Add-ValidationReason "Fresh trajectory definition is unreadable: $($_.Exception.Message)"
        $freshDefinitionValid = $false
    }
}
if (-not (Test-Path -LiteralPath $freshEvidencePath -PathType Leaf)) {
    Add-ValidationReason "invalid_evaluator_health: missing Fresh trajectory evidence for $freshId."
    $freshEvidenceValid = $false
} else {
    try {
        $freshEvidence = Get-Content -Raw -Encoding UTF8 -LiteralPath $freshEvidencePath |
            ConvertFrom-Json
        foreach ($step in @($freshEvidence.steps)) {
            foreach ($check in @($step.checks)) { $freshActualChecks += $check }
            if (-not (Test-NativeInputEvidence $step $freshId)) {
                $freshEvidenceValid = $false
            }
        }
        if ([string]$freshEvidence.trajectory_id -ne $freshId) {
            Add-ValidationReason "Fresh trajectory evidence ID mismatch."
            $freshEvidenceValid = $false
        }
        if ([string]$freshEvidence.evaluator_protocol -ne [string]$rules.evaluator_protocol) {
            Add-ValidationReason "Fresh evaluator protocol mismatch."
            $freshEvidenceValid = $false
        }
        if ($freshDefinitionValid) {
            $freshDefinitionHash = (Get-FileHash -LiteralPath $freshDefinitionPath `
                -Algorithm SHA256).Hash
            if (-not [string]::Equals($freshDefinitionHash,
                    [string]$freshEvidence.definition_sha256,
                    [StringComparison]::OrdinalIgnoreCase)) {
                Add-ValidationReason "Fresh trajectory definition hash mismatch."
                $freshEvidenceValid = $false
            }
        }
    }
    catch {
        Add-ValidationReason "Fresh trajectory evidence is unreadable: $($_.Exception.Message)"
        $freshEvidenceValid = $false
    }
}

$freshCheckMap = @{}
$freshUnexpected = [System.Collections.Generic.List[string]]::new()
foreach ($check in $freshActualChecks) {
    $checkId = [string]$check.check_id
    if ([string]::IsNullOrWhiteSpace($checkId) -or $freshCheckMap.ContainsKey($checkId)) {
        Add-ValidationReason "Fresh evidence contains an empty or duplicate check ID."
        $freshEvidenceValid = $false
        continue
    }
    $freshCheckMap[$checkId] = $check
    if ($freshDefinitionValid -and $freshExpectedIds -notcontains $checkId) {
        $freshUnexpected.Add($checkId)
    }
}
if ($freshUnexpected.Count -gt 0) {
    Add-ValidationReason "Fresh evidence contains unexpected check IDs."
    $freshEvidenceValid = $false
}
$freshPassedChecks = 0
$freshFailedChecks = 0
$freshBlockedChecks = 0
$freshMissingChecks = 0
foreach ($checkId in $freshExpectedIds) {
    if (-not $freshCheckMap.ContainsKey($checkId)) {
        $freshMissingChecks++
        continue
    }
    switch (([string]$freshCheckMap[$checkId].status).ToLowerInvariant()) {
        "pass" { $freshPassedChecks++ }
        "fail" { $freshFailedChecks++ }
        "blocked" { $freshBlockedChecks++ }
        default {
            Add-ValidationReason "Fresh evidence contains an invalid check status."
            $freshEvidenceValid = $false
            $freshFailedChecks++
        }
    }
}
if ($null -ne $freshEvidence -and
    ([int]$freshEvidence.checks_passed -ne $freshPassedChecks -or
     [int]$freshEvidence.checks_failed -ne $freshFailedChecks -or
     [int]$freshEvidence.checks_blocked -ne $freshBlockedChecks)) {
    Add-ValidationReason "Fresh evidence summary counts mismatch."
    $freshEvidenceValid = $false
}
if ($null -ne $freshEvidence) {
    $computedFreshEvidencePass = $freshMissingChecks -eq 0 -and
        $freshFailedChecks -eq 0 -and $freshBlockedChecks -eq 0 -and
        $freshPassedChecks -eq $freshExpectedIds.Count
    if ([bool]$freshEvidence.passed -ne $computedFreshEvidencePass) {
        Add-ValidationReason "invalid_evaluator_health: Fresh evidence pass flag contradicts its check verdicts."
        $freshEvidenceValid = $false
    }
}
if ($null -ne $freshEvidence -and $freshMissingChecks -gt 0) {
    Add-ValidationReason "invalid_evaluator_health: Fresh evidence is incomplete."
    $freshEvidenceValid = $false
}
$freshEvidenceCompletePass = $freshDefinitionValid -and $freshEvidenceValid -and
    $null -ne $freshEvidence -and $freshMissingChecks -eq 0 -and
    $freshFailedChecks -eq 0 -and $freshBlockedChecks -eq 0 -and
    $freshPassedChecks -eq $freshExpectedIds.Count -and [bool]$freshEvidence.passed
$freshEvidenceCandidateFailure = $freshDefinitionValid -and $freshEvidenceValid -and
    $null -ne $freshEvidence -and $freshMissingChecks -eq 0 -and
    $freshFailedChecks -gt 0 -and -not [bool]$freshEvidence.passed
if ($freshNUnitResult -eq "Passed" -and -not $freshEvidenceCompletePass) {
    Add-ValidationReason "invalid_evaluator_health: Fresh NUnit passed but Fresh evidence did not fully pass."
} elseif ($freshNUnitResult -eq "Failed" -and $freshEvidenceCompletePass) {
    Add-ValidationReason "invalid_evaluator_health: Fresh NUnit failed after all Fresh evidence passed."
} elseif ($freshNUnitResult -eq "Failed" -and -not $freshEvidenceCandidateFailure) {
    Add-ValidationReason "invalid_evaluator_health: Fresh NUnit failure has no explicit candidate-failure evidence."
}

$freshFailedRequired = [System.Collections.Generic.List[object]]::new()
foreach ($requiredCheckId in @($freshRule.required_check_ids)) {
    $requiredCheckId = [string]$requiredCheckId
    if ($freshExpectedIds -notcontains $requiredCheckId) {
        Add-ValidationReason "Fresh rule references undeclared check $requiredCheckId."
        $freshFailedRequired.Add([pscustomobject]@{
            check_id = $requiredCheckId; status = "undeclared"
        })
    } elseif (-not $freshCheckMap.ContainsKey($requiredCheckId)) {
        $freshFailedRequired.Add([pscustomobject]@{
            check_id = $requiredCheckId; status = "missing"
        })
    } elseif (([string]$freshCheckMap[$requiredCheckId].status).ToLowerInvariant() -ne "pass") {
        $freshFailedRequired.Add([pscustomobject]@{
            check_id = $requiredCheckId
            status = ([string]$freshCheckMap[$requiredCheckId].status).ToLowerInvariant()
            blocked_by = [string]$freshCheckMap[$requiredCheckId].blocked_by
        })
    }
}
$preparationId = [string]$rules.phases.fresh.preparation_trajectory_id
$preparationResult = @($trajectoryResults | Where-Object {
    [string]$_.id -eq $preparationId
}) | Select-Object -First 1
if ($null -eq $preparationResult) {
    Add-ValidationReason "Fresh references missing Dynamic preparation trajectory $preparationId."
}
$freshFullPass = $null -ne $preparationResult -and
    [bool]$preparationResult.full_pass -and
    $freshFailedRequired.Count -eq 0 -and
    $freshNUnitResult -eq "Passed" -and $freshEvidenceCompletePass
$freshDiagnosticFullPass = $freshFullPass
$freshCheckpointValue = Get-CheckpointValue ([string]$freshRule.capability)
$freshScore = if ($freshFullPass) { $freshCheckpointValue } else { 0.0 }
if ($freshFullPass -and $capabilityCheckpointPasses.ContainsKey([string]$freshRule.capability)) {
    $capabilityCheckpointPasses[[string]$freshRule.capability]++
}
$freshResult = [pscustomobject]@{
    id = $freshId
    nunit_test = [string]$freshRule.nunit_test
    nunit_result = $freshNUnitResult
    full_pass = $freshFullPass
    diagnostic_full_pass = $freshDiagnosticFullPass
    score = Round-Score $freshScore
    maximum_score = Round-Score $freshCheckpointValue
    diagnostic_weight = [double]$freshRule.diagnostic_weight
    capability = [string]$freshRule.capability
    preparation_trajectory_id = $preparationId
    preparation_full_pass = if ($null -ne $preparationResult) {
        [bool]$preparationResult.full_pass
    } else { $false }
    required_check_ids = @($freshRule.required_check_ids)
    failed_checks = @($freshFailedRequired)
    checks = [pscustomobject]@{
        expected = $freshExpectedIds.Count
        passed = $freshPassedChecks
        failed = $freshFailedChecks
        blocked = $freshBlockedChecks
        missing = $freshMissingChecks
    }
    evidence = $freshEvidencePath
    nunit_message = $freshNUnitMessage
}

$visualManifestPath = Join-Path $evaluationRoot "visual\manifest.json"
$visualStatus = "not_evaluated"
$visualScore = $null
$visualRounds = @()
$visualScoreSource = $null
$visualStateInputs = [System.Collections.Generic.List[object]]::new()
$visualBindings = @()
$visualManifest = $null
$visualPromptPath = Join-Path $evaluationRoot "visual\visual_prompt.txt"
$visualPromptSha256 = Get-Sha256 $visualPromptPath
if (-not (Test-Path -LiteralPath $visualManifestPath -PathType Leaf)) {
    Add-VisualValidationReason "Visual manifest is missing: $visualManifestPath"
} else {
    try {
        $visualManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $visualManifestPath |
            ConvertFrom-Json
        $visualRoot = Split-Path -Parent $visualManifestPath
        if (-not [string]::IsNullOrWhiteSpace([string]$visualManifest.prompt_file)) {
            $visualPromptPath = Join-Path $visualRoot ([string]$visualManifest.prompt_file)
        }
        $visualPromptSha256 = Get-Sha256 $visualPromptPath
        if ($null -eq $visualPromptSha256) {
            Add-VisualValidationReason "Fixed visual prompt is missing: $visualPromptPath"
        } elseif ([string]$visualManifest.prompt_sha256 -ne $visualPromptSha256) {
            Add-VisualValidationReason "Visual prompt SHA256 does not match the frozen manifest binding."
        }
        foreach ($state in @($visualManifest.states)) {
            $candidatePath = Join-Path $EvidenceDirectory (
                "visual-candidates\" + [string]$state.candidate_file)
            $referencePath = Join-Path $visualRoot ([string]$state.reference_file)
            $referenceHash = Get-Sha256 $referencePath
            $candidateHash = Get-Sha256 $candidatePath
            $referenceExists = $null -ne $referenceHash
            $candidateExists = $null -ne $candidateHash
            $manifestReferenceHash = ([string]$state.reference_sha256).ToLowerInvariant()
            if (-not $referenceExists) {
                Add-VisualValidationReason "Reference image is missing for state $($state.id)."
            } elseif ($manifestReferenceHash -ne $referenceHash) {
                Add-VisualValidationReason "Reference image SHA256 mismatch for state $($state.id)."
            }
            $visualStateInputs.Add([pscustomobject]@{
                id = [string]$state.id
                label = [string]$state.label
                reference = $referencePath
                reference_exists = $referenceExists
                reference_sha256 = $referenceHash
                reference_manifest_sha256 = $manifestReferenceHash
                candidate = $candidatePath
                candidate_exists = $candidateExists
                candidate_sha256 = $candidateHash
            })
        }
        if (@($visualManifest.states).Count -lt 3 -or
            @($visualManifest.states).Count -gt 5) {
            Add-VisualValidationReason "Visual manifest must define 3 to 5 representative states."
        }
    }
    catch {
        Add-VisualValidationReason "Visual manifest is unreadable: $($_.Exception.Message)"
    }
}

if ($visualValidationReasons.Count -gt 0) {
    $visualStatus = "invalid_visual"
}

if (-not [string]::IsNullOrWhiteSpace($VisualScorePath)) {
    $visualStatus = "invalid_visual"
    if (-not (Test-Path -LiteralPath $VisualScorePath -PathType Leaf)) {
        Add-VisualValidationReason "Visual score file does not exist: $VisualScorePath"
    } elseif ($null -eq $visualManifest) {
        Add-VisualValidationReason "Visual score cannot be validated without a valid manifest."
    } elseif (@($visualStateInputs | Where-Object {
            -not $_.reference_exists
        }).Count -gt 0) {
        Add-VisualValidationReason "Visual score was supplied before all required reference images existed."
    } else {
        try {
            $VisualScorePath = (Resolve-Path -LiteralPath $VisualScorePath).Path
            $visualScoreSource = $VisualScorePath
            $scoreDirectory = Split-Path -Parent $VisualScorePath
            $scoreDirectoryPrefix = [System.IO.Path]::GetFullPath($scoreDirectory).TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar) +
                [System.IO.Path]::DirectorySeparatorChar
            $visualDocument = Get-Content -Raw -Encoding UTF8 -LiteralPath $VisualScorePath |
                ConvertFrom-Json
            if ([int]$visualDocument.schema_version -ne 2) {
                Add-VisualValidationReason "D6 score must use schema_version 2 with evidence bindings."
            }
            if ([string]$visualDocument.benchmark_id -ne [string]$rules.benchmark_id) {
                Add-VisualValidationReason "D6 score benchmark_id does not match this evaluator."
            }
            $documentPromptHash = ([string]$visualDocument.prompt_sha256).ToLowerInvariant()
            if ($null -eq $visualPromptSha256 -or
                $documentPromptHash -ne $visualPromptSha256 -or
                $documentPromptHash -ne ([string]$visualManifest.prompt_sha256).ToLowerInvariant()) {
                Add-VisualValidationReason "D6 score prompt SHA256 does not bind the frozen visual_prompt.txt."
            }

            $expectedStateIds = @($visualManifest.states | ForEach-Object { [string]$_.id })
            $bindings = @($visualDocument.image_bindings)
            $bindingIds = @($bindings | ForEach-Object { [string]$_.id })
            if ($bindings.Count -ne $expectedStateIds.Count -or
                @($bindingIds | Select-Object -Unique).Count -ne $bindingIds.Count -or
                @($expectedStateIds | Where-Object { $bindingIds -notcontains $_ }).Count -gt 0) {
                Add-VisualValidationReason "D6 image_bindings must bind every manifest state exactly once."
            }
            foreach ($stateInput in @($visualStateInputs)) {
                $binding = @($bindings | Where-Object { [string]$_.id -eq [string]$stateInput.id })
                if ($binding.Count -ne 1) { continue }
                $boundReference = ([string]$binding[0].reference_sha256).ToLowerInvariant()
                $boundCandidate = ([string]$binding[0].candidate_sha256).ToLowerInvariant()
                if ($boundReference -ne [string]$stateInput.reference_sha256) {
                    Add-VisualValidationReason "D6 reference hash binding mismatch for state $($stateInput.id)."
                }
                $expectedCandidateHash = if ([bool]$stateInput.candidate_exists) {
                    [string]$stateInput.candidate_sha256
                } else { "" }
                if ($boundCandidate -ne $expectedCandidateHash) {
                    Add-VisualValidationReason "D6 candidate hash binding mismatch for state $($stateInput.id). Missing candidates must bind an empty hash and score zero in every round."
                }
            }
            $visualBindings = @($bindings)

            $requiredRounds = [int]$rules.phases.visual.required_rounds
            $rounds = @($visualDocument.rounds)
            $allowedScores = @($rules.phases.visual.allowed_item_scores |
                ForEach-Object { [double]$_ })
            $categoryNames = @(
                "scene_assembly",
                "composition_layout",
                "scale_layering_clarity",
                "style_color_cohesion",
                "overall_finish")
            if ($rounds.Count -ne $requiredRounds) {
                Add-VisualValidationReason "D6 score must contain exactly $requiredRounds rounds."
            }
            $roundNumbers = @($rounds | ForEach-Object { [int]$_.round })
            if (@($roundNumbers | Select-Object -Unique).Count -ne $roundNumbers.Count -or
                @((1..$requiredRounds) | Where-Object { $roundNumbers -notcontains $_ }).Count -gt 0) {
                Add-VisualValidationReason "D6 rounds must be uniquely numbered 1 through $requiredRounds."
            }
            $modelIds = @($rounds | ForEach-Object { ([string]$_.model_id).Trim() })
            if ($modelIds.Count -ne $requiredRounds -or
                @($modelIds | Where-Object {
                    [string]::IsNullOrWhiteSpace($_) -or $_.Contains('<')
                }).Count -gt 0 -or
                @($modelIds | Select-Object -Unique).Count -ne 1) {
                Add-VisualValidationReason "All D6 rounds must record the same non-placeholder model_id."
            }

            $computedRoundScores = [System.Collections.Generic.List[double]]::new()
            $roundEvidence = [System.Collections.Generic.List[object]]::new()
            $seenRawPaths = [System.Collections.Generic.HashSet[string]]::new(
                [StringComparer]::OrdinalIgnoreCase)
            foreach ($round in $rounds) {
                $rawFile = [string]$round.raw_response_file
                $rawPath = if ([string]::IsNullOrWhiteSpace($rawFile)) {
                    ""
                } else {
                    [System.IO.Path]::GetFullPath((Join-Path $scoreDirectory $rawFile))
                }
                $rawHash = if (-not [string]::IsNullOrWhiteSpace($rawPath) -and
                    $rawPath.StartsWith($scoreDirectoryPrefix,
                        [StringComparison]::OrdinalIgnoreCase)) {
                    Get-Sha256 $rawPath
                } else { $null }
                if ($null -eq $rawHash) {
                    Add-VisualValidationReason "D6 round $($round.round) raw response is missing or outside the score directory."
                } elseif (-not $seenRawPaths.Add($rawPath)) {
                    Add-VisualValidationReason "Each D6 round must preserve a distinct raw response file."
                } elseif (([string]$round.raw_response_sha256).ToLowerInvariant() -ne $rawHash) {
                    Add-VisualValidationReason "D6 round $($round.round) raw response SHA256 mismatch."
                }

                $stateScores = @($round.states)
                $stateIds = @($stateScores | ForEach-Object { [string]$_.id })
                if ($stateIds.Count -ne $expectedStateIds.Count -or
                    @($stateIds | Select-Object -Unique).Count -ne $stateIds.Count -or
                    @($expectedStateIds | Where-Object { $stateIds -notcontains $_ }).Count -gt 0) {
                    Add-VisualValidationReason "Each D6 round must score every manifest state exactly once."
                }
                $totals = [System.Collections.Generic.List[double]]::new()
                foreach ($stateScore in $stateScores) {
                    $stateInput = @($visualStateInputs | Where-Object {
                        [string]$_.id -eq [string]$stateScore.id
                    }) | Select-Object -First 1
                    $sum = 0.0
                    foreach ($category in $categoryNames) {
                        $property = $stateScore.PSObject.Properties[$category]
                        $parsed = 0.0
                        if ($null -eq $property -or
                            -not [double]::TryParse([string]$property.Value,
                                [Globalization.NumberStyles]::Float,
                                [Globalization.CultureInfo]::InvariantCulture,
                                [ref]$parsed) -or
                            $allowedScores -notcontains $parsed) {
                            Add-VisualValidationReason "D6 state $($stateScore.id) has an invalid $category score."
                        } else {
                            $sum += $parsed
                        }
                    }
                    $sum = Round-Score $sum
                    if ($null -ne $stateInput -and -not [bool]$stateInput.candidate_exists -and
                        $sum -ne 0.0) {
                        Add-VisualValidationReason "D6 missing candidate state $($stateScore.id) must receive zero in every round."
                    }
                    $declaredTotal = 0.0
                    if (-not [double]::TryParse([string]$stateScore.total,
                            [Globalization.NumberStyles]::Float,
                            [Globalization.CultureInfo]::InvariantCulture,
                            [ref]$declaredTotal) -or
                        [Math]::Abs($sum - $declaredTotal) -gt 0.0001) {
                        Add-VisualValidationReason "D6 state $($stateScore.id) total does not equal its five categories."
                    }
                    $totals.Add($sum)
                }
                $roundAverage = if ($totals.Count -gt 0) {
                    Round-Score (($totals | Measure-Object -Average).Average)
                } else { 0.0 }
                $declaredAverage = 0.0
                if (-not [double]::TryParse([string]$round.average,
                        [Globalization.NumberStyles]::Float,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$declaredAverage) -or
                    [Math]::Abs($roundAverage - $declaredAverage) -gt 0.0001) {
                    Add-VisualValidationReason "D6 round $($round.round) average does not match its state totals."
                }
                $computedRoundScores.Add($roundAverage)
                $roundEvidence.Add([pscustomobject]@{
                    round = [int]$round.round
                    model_id = [string]$round.model_id
                    raw_response_file = $rawPath
                    raw_response_sha256 = $rawHash
                    parsed_states = @($stateScores)
                    parsed_average = $roundAverage
                })
            }
            $computedFinal = if ($computedRoundScores.Count -gt 0) {
                [Math]::Round(
                    ($computedRoundScores | Measure-Object -Average).Average,
                    1,
                    [MidpointRounding]::AwayFromZero)
            } else { 0.0 }
            $declaredFinal = 0.0
            if (-not [double]::TryParse([string]$visualDocument.final_score,
                    [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$declaredFinal) -or
                [Math]::Abs($computedFinal - $declaredFinal) -gt 0.0001) {
                Add-VisualValidationReason "D6 final score does not equal the three-round average."
            }
            if ($visualValidationReasons.Count -eq 0) {
                $visualScore = $computedFinal
                $visualRounds = @($roundEvidence)
                $visualScoreSource = $VisualScorePath
                $visualStatus = "evaluated"
            }
        }
        catch {
            Add-VisualValidationReason "Visual score is unreadable: $($_.Exception.Message)"
        }
    }
}

foreach ($capability in @($rules.capabilities)) {
    $capabilityId = [string]$capability.id
    $declaredCount = [int]$capability.checkpoint_count
    $passedCount = [int]$capabilityCheckpointPasses[$capabilityId]
    $capabilityScores[$capabilityId] = if ($declaredCount -gt 0) {
        Round-Score (
            [double]$capability.maximum_score * $passedCount / $declaredCount)
    } else { 0.0 }
}
$staticScore = [double]$capabilityScores["D1"]
$automatedScore = Round-Score ((@($rules.capabilities | ForEach-Object {
    [double]$capabilityScores[[string]$_.id]
}) | Measure-Object -Sum).Sum)
$scoreBeforeCaps = if ($visualStatus -eq "evaluated") {
    Round-Score ($automatedScore + [double]$visualScore)
} else {
    $automatedScore
}
$scoreAfterCaps = $scoreBeforeCaps
$gateResults = [System.Collections.Generic.List[object]]::new()
foreach ($gate in @($rules.score_caps)) {
    $phaseId = [string]$gate.phase_id
    $trajectoryId = [string]$gate.trajectory_id
    $milestoneId = [string]$gate.milestone_id
    $minimumCandidateVisualStates = if (
        $null -ne $gate.PSObject.Properties['minimum_candidate_visual_states']) {
        [int]$gate.minimum_candidate_visual_states
    } else { 0 }
    $hasPhaseTarget = -not [string]::IsNullOrWhiteSpace($phaseId)
    $hasTrajectoryTarget = -not [string]::IsNullOrWhiteSpace($trajectoryId)
    $hasMilestoneTarget = -not [string]::IsNullOrWhiteSpace($milestoneId)
    $hasVisualStateTarget = $minimumCandidateVisualStates -gt 0
    $targetKindCount = @(@(
        $hasPhaseTarget,
        $hasTrajectoryTarget,
        $hasMilestoneTarget,
        $hasVisualStateTarget
    ) | Where-Object { $_ }).Count
    $gateScope = if ($hasPhaseTarget) {
        "phase"
    } elseif ($hasTrajectoryTarget) {
        "trajectory"
    } elseif ($hasVisualStateTarget) {
        "visual_state_coverage"
    } else {
        "milestone"
    }
    $targetFound = $false
    $targetFullPass = $false

    if ($targetKindCount -ne 1) {
        Add-ValidationReason "Score gate $($gate.id) must target exactly one phase, trajectory, milestone, or visual-state coverage requirement."
    } elseif ($hasPhaseTarget) {
        if ($phaseId -eq "static") {
            $targetFound = $true
            $targetFullPass = $staticFullPass
        } elseif ($phaseId -eq "fresh") {
            $targetFound = $true
            $targetFullPass = $freshFullPass
        } else {
            Add-ValidationReason "Score gate $($gate.id) references unknown phase $phaseId."
        }
    } elseif ($hasTrajectoryTarget) {
        $trajectory = @($trajectoryResults | Where-Object {
            $_.id -eq $trajectoryId
        }) | Select-Object -First 1
        $targetFound = $null -ne $trajectory
        if ($targetFound) {
            $targetFullPass = [bool]$trajectory.full_pass
        } else {
            Add-ValidationReason "Score gate $($gate.id) references unknown trajectory $trajectoryId."
        }
    } elseif ($hasMilestoneTarget) {
        $milestoneMatches = @($trajectoryResults | ForEach-Object {
            @($_.milestones | Where-Object { [string]$_.id -eq $milestoneId })
        })
        if ($milestoneMatches.Count -eq 1) {
            $targetFound = $true
            $targetFullPass = [bool]$milestoneMatches[0].passed
        } else {
            Add-ValidationReason "Score gate $($gate.id) references milestone $milestoneId, found $($milestoneMatches.Count)."
        }
    } else {
        $targetFound = @($visualStateInputs).Count -gt 0
        $candidateVisualStateCount = @($visualStateInputs | Where-Object {
            [bool]$_.candidate_exists
        }).Count
        $targetFullPass = $targetFound -and
            $candidateVisualStateCount -ge $minimumCandidateVisualStates
    }

    $triggered = -not $targetFound -or
        ([bool]$gate.requires_full_pass -and -not $targetFullPass)
    $before = $scoreAfterCaps
    $applyToOverall = $null -ne $gate.PSObject.Properties["apply_to_overall"] -and
        [bool]$gate.apply_to_overall
    if ($triggered -and $applyToOverall) {
        $scoreAfterCaps = [Math]::Min($scoreAfterCaps, [double]$gate.maximum_final_score)
    }
    $gateResults.Add([pscustomobject]@{
        id = [string]$gate.id
        scope = $gateScope
        phase_id = if ($hasPhaseTarget) { $phaseId } else { $null }
        trajectory_id = if ($hasTrajectoryTarget) { $trajectoryId } else { $null }
        milestone_id = if ($hasMilestoneTarget) { $milestoneId } else { $null }
        minimum_candidate_visual_states = if ($hasVisualStateTarget) {
            $minimumCandidateVisualStates
        } else { $null }
        candidate_visual_state_count = if ($hasVisualStateTarget) {
            $candidateVisualStateCount
        } else { $null }
        triggered = $triggered
        apply_to_overall = $applyToOverall
        reduced_score = $scoreAfterCaps -lt $before
        maximum_final_score = [double]$gate.maximum_final_score
        reason = [string]$gate.reason
    })
}
$scoreAfterCaps = Round-Score $scoreAfterCaps

$capabilityResults = [System.Collections.Generic.List[object]]::new()
foreach ($capability in @($rules.capabilities)) {
    $earned = Round-Score ([double]$capabilityScores[[string]$capability.id])
    $maximum = [double]$capability.maximum_score
    $checkpointCount = [int]$capability.checkpoint_count
    $passedCheckpointCount = [int]$capabilityCheckpointPasses[[string]$capability.id]
    $capabilityResults.Add([pscustomobject]@{
        id = [string]$capability.id
        title = [string]$capability.title
        score = $earned
        maximum_score = $maximum
        passed_checkpoints = $passedCheckpointCount
        total_checkpoints = $checkpointCount
        completion_ratio = if ($checkpointCount -gt 0) {
            Round-Score ($passedCheckpointCount / [double]$checkpointCount)
        } else {
            0.0
        }
    })
}

$validScore = $validationReasons.Count -eq 0
$hasEvaluatorHealthFailure = @($validationReasons | Where-Object {
    $_ -match '^invalid_evaluator_health:'
}).Count -gt 0
$candidateStatus = if (-not $validScore) {
    if ($hasEvaluatorHealthFailure) { "invalid_evaluator_health" } else { "invalid" }
} elseif ($visualStatus -eq "invalid_visual") {
    if ($automatedScore -eq $automatedMaximum) {
        "functional_complete_visual_invalid"
    } else {
        "partial_visual_invalid"
    }
} elseif ($visualStatus -eq "evaluated" -and
    $scoreAfterCaps -eq [double]$rules.maximum_score) {
    "complete"
} elseif ($automatedScore -eq $automatedMaximum -and
    $visualStatus -ne "evaluated") {
    "functional_complete_visual_pending"
} elseif ($automatedScore -eq 0) {
    "no_implementation"
} else {
    "partial"
}

$dimensionLookup = @{}
foreach ($item in @($capabilityResults)) {
    $dimensionLookup[[string]$item.id] = $item
}
$dimensionReport = [ordered]@{}
foreach ($dimension in @($rules.dimensions)) {
    $dimensionId = [string]$dimension.id
    if ($dimensionId -eq "D6") {
        $dimensionReport[$dimensionId] = [pscustomobject]@{
            title = [string]$dimension.title
            score = if ($visualStatus -eq "evaluated") { [double]$visualScore } else { $null }
            maximum_score = [double]$dimension.maximum_score
            status = $visualStatus
            rounds = @($visualRounds)
        }
    } else {
        $result = $dimensionLookup[$dimensionId]
        $dimensionReport[$dimensionId] = [pscustomobject]@{
            title = [string]$dimension.title
            score = if ($null -ne $result) { [double]$result.score } else { 0.0 }
            maximum_score = [double]$dimension.maximum_score
            status = "evaluated"
        }
    }
}

$overallStatus = if (-not $validScore) {
    if ($hasEvaluatorHealthFailure) { "invalid_evaluator_health" } else { "invalid" }
} elseif ($visualStatus -eq "invalid_visual") {
    "invalid_visual"
} elseif ($visualStatus -eq "evaluated") {
    "evaluated"
} else {
    "pending_visual"
}
$overallScore = if ($validScore -and $visualStatus -eq "evaluated") {
    $scoreAfterCaps
} else {
    $null
}
$visualInputsReady = @($visualStateInputs).Count -ge 3 -and
    @($visualStateInputs | Where-Object {
        -not $_.reference_exists -or
        [string]::IsNullOrWhiteSpace([string]$_.reference_sha256) -or
        [string]$_.reference_sha256 -ne [string]$_.reference_manifest_sha256
    }).Count -eq 0 -and $null -ne $visualPromptSha256 -and
    $visualValidationReasons.Count -eq 0

$report = [pscustomobject]@{
    schema_version = 2
    evaluator_protocol = [string]$rules.evaluator_protocol
    evaluator_revision = [string]$rules.evaluator_revision
    generated_utc = [DateTime]::UtcNow.ToString("o")
    project_path = $ProjectPath
    valid_score = $validScore
    candidate_status = $candidateStatus
    validation_reasons = @($validationReasons)
    visual_validation_reasons = @($visualValidationReasons)
    score = $overallScore
    score_status = $overallStatus
    automated_score = if ($validScore) { $automatedScore } else { $null }
    automated_maximum_score = $automatedMaximum
    score_before_caps = if ($validScore -and $visualStatus -eq "evaluated") {
        $scoreBeforeCaps
    } else { $null }
    maximum_score = [double]$rules.maximum_score
    dimensions = [pscustomobject]$dimensionReport
    overall = [pscustomobject]@{
        score = $overallScore
        maximum_score = [double]$rules.maximum_score
        status = $overallStatus
        note = if ($overallStatus -eq "pending_visual") {
            "D1-D5 are automated; D6 requires the fixed three-round VLM procedure."
        } elseif ($overallStatus -eq "invalid_visual") {
            "D6 evidence bindings are missing or inconsistent; no Overall score may be emitted."
        } else { $null }
    }
    executable = $validScore -and $staticFullPass
    solved = $validScore -and $staticFullPass -and
        @($trajectoryResults | ForEach-Object {
            @($_.milestones | Where-Object {
                [bool]$_.scored_checkpoint -and -not [bool]$_.passed
            })
        }).Count -eq 0 -and $freshFullPass
    package_valid = [pscustomobject]@{
        value = $null
        status = "not_evaluated"
    }
    phases = [pscustomobject]@{
        static = [pscustomobject]@{
            score = $staticScore
            maximum_score = [double]$rules.phases.static.maximum_score
            full_pass = $staticFullPass
            unity_exit_code = $StaticExitCode
            result_xml = $StaticResultPath
            tests = @($staticResults)
        }
        dynamic = [pscustomobject]@{
            score = $dynamicScore
            maximum_score = [double]$rules.phases.dynamic.maximum_score
            unity_exit_code = $DynamicExitCode
            result_xml = $DynamicResultPath
            evidence_directory = $EvidenceDirectory
            trajectories = @($trajectoryResults)
        }
        fresh = [pscustomobject]@{
            score = Round-Score $freshScore
            maximum_score = [double]$rules.phases.fresh.maximum_score
            unity_exit_code = $FreshExitCode
            dynamic_process_id = $DynamicProcessId
            fresh_process_id = $FreshProcessId
            independent_process = $DynamicProcessId -gt 0 -and
                $FreshProcessId -gt 0 -and $DynamicProcessId -ne $FreshProcessId
            result_xml = $FreshResultPath
            evidence_directory = $FreshEvidenceDirectory
            test = $freshResult
        }
        visual = [pscustomobject]@{
            status = $visualStatus
            score = if ($visualStatus -eq "evaluated") { [double]$visualScore } else { $null }
            maximum_score = [double]$rules.phases.visual.maximum_score
            rounds = @($visualRounds)
            score_file = $visualScoreSource
            manifest = $visualManifestPath
            prompt = $visualPromptPath
            prompt_sha256 = $visualPromptSha256
            image_bindings = @($visualBindings)
            validation_reasons = @($visualValidationReasons)
            inputs_ready = $visualInputsReady
            states = @($visualStateInputs)
        }
    }
    score_caps = @($gateResults)
    capabilities = @($capabilityResults)
    artifacts = [pscustomobject]@{
        rules = $RulesPath
        trajectory_definitions = $DefinitionsDirectory
        visual_manifest = $visualManifestPath
        visual_prompt = $visualPromptPath
    }
}

$json = $report | ConvertTo-Json -Depth 12
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputParent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
        New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $OutputPath,
        $json,
        [System.Text.UTF8Encoding]::new($false))
}
$json

if (-not $validScore -and -not $NoExitOnInvalid) {
    exit 3
}

