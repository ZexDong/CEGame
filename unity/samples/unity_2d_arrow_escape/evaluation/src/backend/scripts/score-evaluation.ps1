[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$StaticResultPath,

    [Parameter(Mandatory = $true)]
    [string]$DynamicResultPath,

    [Parameter(Mandatory = $true)]
    [string]$EvidenceDirectory,

    [string]$FreshResultPath = "",
    [string]$FreshEvidenceDirectory = "",
    [string]$FreshSeedPath = "",

    [string]$ProjectPath = "",
    [int]$StaticExitCode = 0,
    [int]$DynamicExitCode = 0,
    [int]$FreshExitCode = 0,
    [bool]$BaselineCompilePassed = $true,
    [string]$RulesPath = "",
    [string]$DefinitionsDirectory = "",
    [string]$VisualScorePath = "",
    [string]$OutputPath = "",
    [switch]$NoExitOnInvalid
)

$ErrorActionPreference = "Stop"
$evaluationRoot = Split-Path -Parent $PSScriptRoot
$sourceBindingHelperPath = (Resolve-Path -LiteralPath (
    Join-Path $PSScriptRoot "get-current-source-binding.ps1")).Path
. $sourceBindingHelperPath
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
$EvidenceDirectory = if (Test-Path -LiteralPath $EvidenceDirectory -PathType Container) {
    (Resolve-Path -LiteralPath $EvidenceDirectory).Path
} else {
    [System.IO.Path]::GetFullPath($EvidenceDirectory)
}
if (-not [string]::IsNullOrWhiteSpace($FreshResultPath) -and
    (Test-Path -LiteralPath $FreshResultPath -PathType Leaf)) {
    $FreshResultPath = (Resolve-Path -LiteralPath $FreshResultPath).Path
}
if (-not [string]::IsNullOrWhiteSpace($FreshEvidenceDirectory)) {
    $FreshEvidenceDirectory = if (Test-Path -LiteralPath $FreshEvidenceDirectory -PathType Container) {
        (Resolve-Path -LiteralPath $FreshEvidenceDirectory).Path
    } else {
        [System.IO.Path]::GetFullPath($FreshEvidenceDirectory)
    }
}
if (-not [string]::IsNullOrWhiteSpace($FreshSeedPath) -and
    (Test-Path -LiteralPath $FreshSeedPath -PathType Leaf)) {
    $FreshSeedPath = (Resolve-Path -LiteralPath $FreshSeedPath).Path
}
if (-not [string]::IsNullOrWhiteSpace($ProjectPath) -and
    (Test-Path -LiteralPath $ProjectPath)) {
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
}

$rules = Get-Content -Raw -Encoding UTF8 -LiteralPath $RulesPath | ConvertFrom-Json
$validationReasons = [System.Collections.Generic.List[string]]::new()
$visualValidationReasons = [System.Collections.Generic.List[string]]::new()

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

function Round-Score([double]$Value) {
    return [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero)
}

function Get-HashLower([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$currentSourceBinding = $null
try {
    $currentSourceBinding = Get-ArrowEscapeCurrentSourceBinding `
        $evaluationRoot $RulesPath
}
catch {
    Add-ValidationReason (
        "Current full Input/TOOLCHAIN/Prompt source binding failed: " +
        $_.Exception.Message)
}

function Get-NUnitCases([string]$Path, [string]$PhaseName) {
    try {
        [xml]$document = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
        # Ignore aggregate parent nodes (for example Failed/Child suites) and
        # score/classify each real leaf exactly once.
        $cases = @($document.SelectNodes(
            "//test-case[not(descendant::test-case)]"))
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

function Find-NUnitCase($Cases, [string]$MethodName) {
    return @($Cases | Where-Object {
        (Get-XmlAttributeValue $_ "methodname") -eq $MethodName -or
        (Get-XmlAttributeValue $_ "name") -eq $MethodName
    })
}

function Get-NUnitMessage($Case) {
    if ($null -eq $Case) { return "missing" }
    $failure = $Case.SelectSingleNode("failure/message")
    if ($null -ne $failure) { return ([string]$failure.InnerText).Trim() }
    $reason = $Case.SelectSingleNode("reason/message")
    if ($null -ne $reason) { return ([string]$reason.InnerText).Trim() }
    $output = $Case.SelectSingleNode("output")
    if ($null -ne $output -and -not [string]::IsNullOrWhiteSpace($output.InnerText)) {
        return ([string]$output.InnerText).Trim()
    }
    return ""
}

function Get-NUnitDiagnosticText($Case) {
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
    $site = Get-XmlAttributeValue $Case "site"
    $label = Get-XmlAttributeValue $Case "label"
    if ($site -match '^(?i:SetUp|TearDown)$' -or
        $label -match '^(?i:Error|Cancelled)$') {
        return ""
    }
    $diagnostic = Get-NUnitDiagnosticText $Case
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

function Test-PointerRouteEvidence($Step, [string]$TrajectoryId) {
    if ([string]$Step.operation -ne "virtual_mouse_click") { return $true }
    $valid = $true
    $events = @($Step.pointer_events)
    $route = [string]$Step.input_route
    $driverReadyCheck = @($Step.checks | Where-Object {
        ([string]$_.check_id).EndsWith(".driver_ready", [StringComparison]::Ordinal)
    } | Select-Object -First 1)
    $targetCheck = @($Step.checks | Where-Object {
        ([string]$_.check_id).EndsWith(".target", [StringComparison]::Ordinal)
    } | Select-Object -First 1)
    $topHitCheck = @($Step.checks | Where-Object {
        ([string]$_.check_id).EndsWith(".top_hit", [StringComparison]::Ordinal)
    } | Select-Object -First 1)
    $moveCheck = @($Step.checks | Where-Object {
        ([string]$_.check_id).EndsWith(".move", [StringComparison]::Ordinal)
    } | Select-Object -First 1)
    $pressCheck = @($Step.checks | Where-Object {
        ([string]$_.check_id).EndsWith(".press", [StringComparison]::Ordinal)
    } | Select-Object -First 1)
    $releaseCheck = @($Step.checks | Where-Object {
        ([string]$_.check_id).EndsWith(".release", [StringComparison]::Ordinal)
    } | Select-Object -First 1)
    $callbackRoute = $route -eq "eventsystem_pointer_handler"
    $nativeRoute = $route -in @(
        "eventsystem_native_surface",
        "physics2d_native_mouse",
        "physics_native_mouse",
        "visual_bounds_native_mouse")
    $pressPassed = @($Step.checks | Where-Object {
        ([string]$_.check_id).EndsWith(".press", [StringComparison]::Ordinal) -and
        [string]$_.status -eq "pass"
    }).Count -eq 1
    $releasePassed = @($Step.checks | Where-Object {
        ([string]$_.check_id).EndsWith(".release", [StringComparison]::Ordinal) -and
        [string]$_.status -eq "pass"
    }).Count -eq 1

    # A healthy driver can legitimately reject a candidate-owned missing target or
    # occluded/overlapped top hit before queuing a press. That is a scored candidate
    # failure. It must retain device/screen and observed rejection evidence, but it
    # cannot have a resolved route, click coordinates, or pointer callbacks yet.
    $targetFailed = $targetCheck.Count -eq 1 -and
        [string]$targetCheck[0].status -eq "fail"
    $topHitFailed = $topHitCheck.Count -eq 1 -and
        [string]$topHitCheck[0].status -eq "fail"
    $earlyCandidateFailure =
        $driverReadyCheck.Count -eq 1 -and
        [string]$driverReadyCheck[0].status -eq "pass" -and
        ($targetFailed -xor $topHitFailed)
    if ($earlyCandidateFailure) {
        $failedCheck = if ($targetFailed) { $targetCheck[0] } else { $topHitCheck[0] }
        if ([string]$Step.status -ne "fail" -or
            [string]::IsNullOrWhiteSpace([string]$failedCheck.observed)) {
            Add-ValidationReason "Early candidate input rejection lacks a failed step/observation in $TrajectoryId/$($Step.step_id)."
            $valid = $false
        }
        if ([int]$Step.input_device_id -le 0 -or
            [int]$Step.screen_width -le 0 -or [int]$Step.screen_height -le 0) {
            Add-ValidationReason "Early candidate input rejection lacks device/screen evidence in $TrajectoryId/$($Step.step_id)."
            $valid = $false
        }
        if ([Math]::Abs([double]$Step.screen_x) -gt 0.001 -or
            [Math]::Abs([double]$Step.screen_y) -gt 0.001) {
            Add-ValidationReason "Early candidate input rejection claims click coordinates before a point was resolved in $TrajectoryId/$($Step.step_id)."
            $valid = $false
        }
        if ($pressPassed -or $releasePassed -or $events.Count -ne 0) {
            Add-ValidationReason "Early candidate input rejection contains impossible press/release callbacks in $TrajectoryId/$($Step.step_id)."
            $valid = $false
        }
        $expectedBlocker = [string]$failedCheck.check_id
        $blockedChecks = if ($targetFailed) {
            @($topHitCheck, $moveCheck, $pressCheck, $releaseCheck)
        } else {
            @($moveCheck, $pressCheck, $releaseCheck)
        }
        foreach ($matches in $blockedChecks) {
            if ($matches.Count -ne 1 -or [string]$matches[0].status -ne "blocked" -or
                [string]$matches[0].blocked_by -ne $expectedBlocker) {
                Add-ValidationReason "Early candidate input rejection has an inconsistent blocked_by chain in $TrajectoryId/$($Step.step_id)."
                $valid = $false
                break
            }
        }
        if ($targetFailed) {
            if ($route -notin @("", "unresolved") -or
                -not [string]::IsNullOrWhiteSpace([string]$Step.top_hit)) {
                Add-ValidationReason "Missing-target rejection contains a forged route/top-hit in $TrajectoryId/$($Step.step_id)."
                $valid = $false
            }
        } else {
            if ($targetCheck.Count -ne 1 -or [string]$targetCheck[0].status -ne "pass" -or
                $route -ne "unresolved" -or
                [string]::IsNullOrWhiteSpace([string]$Step.top_hit) -or
                [string]$Step.top_hit -ne [string]$topHitCheck[0].observed) {
                Add-ValidationReason "Top-hit rejection evidence is structurally inconsistent in $TrajectoryId/$($Step.step_id)."
                $valid = $false
            }
        }
        return $valid
    }

    if (-not $callbackRoute -and -not $nativeRoute) {
        Add-ValidationReason "Unknown or missing native input route in $TrajectoryId/$($Step.step_id)."
        $valid = $false
    }
    if ($callbackRoute -and $pressPassed -and
        ($events.Count -lt 1 -or [string]$events[0].phase -ne "down")) {
        Add-ValidationReason "Missing PointerDown evidence in $TrajectoryId/$($Step.step_id)."
        $valid = $false
    }
    if ($callbackRoute -and $releasePassed) {
        $phases = @($events | ForEach-Object { [string]$_.phase })
        if ($events.Count -ne 3 -or ($phases -join ",") -ne "down,up,click") {
            Add-ValidationReason "Pointer evidence does not prove down -> up -> click in $TrajectoryId/$($Step.step_id)."
            $valid = $false
        }
    }
    if ($callbackRoute -and $events.Count -gt 3) {
        Add-ValidationReason "Pointer evidence contains duplicate callbacks in $TrajectoryId/$($Step.step_id)."
        $valid = $false
    }
    if ($nativeRoute -and $events.Count -ne 0) {
        Add-ValidationReason "Native Mouse route unexpectedly contains EventSystem callbacks in $TrajectoryId/$($Step.step_id)."
        $valid = $false
    }
    if ($callbackRoute -and $events.Count -gt 0) {
        $pointerId = [int]$events[0].pointer_id
        foreach ($event in $events) {
            if ([string]$event.button -ne "Left" -or [int]$event.pointer_id -ne $pointerId -or
                [int]$event.frame -lt [int]$Step.frame_start -or
                [int]$event.frame -gt [int]$Step.frame_end) {
                Add-ValidationReason "Pointer callback metadata is inconsistent in $TrajectoryId/$($Step.step_id)."
                $valid = $false
                break
            }
        }
        if ([int]$Step.input_device_id -le 0 -or [int]$Step.input_device_id -ne $pointerId -or
            [int]$Step.screen_width -le 0 -or [int]$Step.screen_height -le 0) {
            Add-ValidationReason "Pointer device/screen evidence is invalid in $TrajectoryId/$($Step.step_id)."
            $valid = $false
        }
    }
    if ([int]$Step.input_device_id -le 0 -or
        [int]$Step.screen_width -le 0 -or [int]$Step.screen_height -le 0 -or
        [string]::IsNullOrWhiteSpace([string]$Step.top_hit)) {
        Add-ValidationReason "Native input device/screen/top-hit evidence is invalid in $TrajectoryId/$($Step.step_id)."
        $valid = $false
    }
    return $valid
}

if ([int]$rules.schema_version -ne 2) {
    Add-ValidationReason "rules.json must use schema_version 2."
}
$dimensionMaximum = (@($rules.dimensions) | Measure-Object -Property maximum_score -Sum).Sum
if ([double]$dimensionMaximum -ne [double]$rules.maximum_score) {
    Add-ValidationReason "D1-D6 maxima do not sum to the benchmark maximum."
}
foreach ($dimension in @($rules.dimensions)) {
    if ([string]$dimension.id -ne "D6" -and @($dimension.checkpoints).Count -eq 0) {
        Add-ValidationReason "Dimension $($dimension.id) has no checkpoints."
    }
}

$acceptedExitCodes = @($rules.accepted_unity_exit_codes | ForEach-Object { [int]$_ })
if ($acceptedExitCodes -notcontains $StaticExitCode) {
    Add-ValidationReason "Static Unity exit code $StaticExitCode is an infrastructure error."
}
if ($acceptedExitCodes -notcontains $DynamicExitCode) {
    Add-ValidationReason "Dynamic Unity exit code $DynamicExitCode is an infrastructure error."
}
if ([string]::IsNullOrWhiteSpace($FreshResultPath) -or
    -not (Test-Path -LiteralPath $FreshResultPath -PathType Leaf)) {
    Add-ValidationReason "Fresh phase result XML is required by the post-Dynamic reopen protocol."
} elseif ($acceptedExitCodes -notcontains $FreshExitCode) {
    Add-ValidationReason "Fresh Unity exit code $FreshExitCode is an infrastructure error."
}

$staticCases = @(Get-NUnitCases $StaticResultPath "Static")
$staticResults = [System.Collections.Generic.List[object]]::new()
$staticPassMap = @{}
$candidateStaticMarker = "[OMNIGAME_CANDIDATE_STATIC]"
$evaluatorUnsupportedMarker = "[OMNIGAME_EVALUATOR_UNSUPPORTED]"
$evaluatorUnsupportedReasons = [System.Collections.Generic.List[string]]::new()
$staticAttributableCandidateFailures = [System.Collections.Generic.List[string]]::new()
foreach ($testRule in @($rules.phases.static.tests)) {
    $matches = @(Find-NUnitCase $staticCases ([string]$testRule.id))
    if ($matches.Count -ne 1) {
        Add-ValidationReason "Expected one static test $($testRule.id), found $($matches.Count)."
    }
    $case = if ($matches.Count -gt 0) { $matches[0] } else { $null }
    $result = if ($null -eq $case) { "Missing" } else {
        Get-XmlAttributeValue $case "result"
    }
    $message = Get-NUnitMessage $case
    $passed = $result -eq "Passed"
    if ($result -eq "Failed" -and $message.Contains($evaluatorUnsupportedMarker)) {
        $unsupportedReason = "evaluator_unsupported: Static test $($testRule.id): $message"
        $evaluatorUnsupportedReasons.Add($unsupportedReason)
        Add-ValidationReason $unsupportedReason
    } elseif ($result -eq "Failed" -and -not $message.Contains($candidateStaticMarker)) {
        Add-ValidationReason "Static test $($testRule.id) failed without the candidate marker."
    } elseif ($result -eq "Failed") {
        $staticAttributableCandidateFailures.Add([string]$testRule.id)
    } elseif ($result -notin @("Passed", "Failed", "Missing")) {
        Add-ValidationReason "Static test $($testRule.id) returned unsupported result '$result'."
    }
    $staticPassMap[[string]$testRule.id] = $passed
    $staticResults.Add([pscustomobject]@{
        id = [string]$testRule.id
        result = $result
        passed = $passed
        message = $message
    })
}
foreach ($regressionCase in @($staticCases | Where-Object {
    (Get-XmlAttributeValue $_ "methodname").StartsWith(
        "EVALUATOR_REGRESSION_", [StringComparison]::Ordinal) -or
    (Get-XmlAttributeValue $_ "name").StartsWith(
        "EVALUATOR_REGRESSION_", [StringComparison]::Ordinal)
})) {
    if ((Get-XmlAttributeValue $regressionCase "result") -ne "Passed") {
        Add-ValidationReason ("Static evaluator self-test " +
            "$(Get-XmlAttributeValue $regressionCase 'name') did not pass.")
    }
}
$staticExitCandidateAttributable = $staticAttributableCandidateFailures.Count -gt 0
if ($StaticExitCode -ne 0 -and $acceptedExitCodes -contains $StaticExitCode -and
    -not $staticExitCandidateAttributable -and
    $evaluatorUnsupportedReasons.Count -eq 0) {
    Add-ValidationReason (
        "Static Unity exit code $StaticExitCode had no candidate-marked leaf failure; " +
        "COMMAND_FAILED without attributable leaf evidence is infrastructure-invalid.")
}
$staticFullPass = @($staticResults | Where-Object { -not $_.passed }).Count -eq 0
$staticLaunchGateIds = @($rules.phases.static.launch_gate_test_ids |
    ForEach-Object { [string]$_ })
if ($staticLaunchGateIds.Count -eq 0) {
    Add-ValidationReason "rules.json does not declare any Static launch-gate tests."
}
if (@($staticLaunchGateIds | Sort-Object -Unique).Count -ne
    $staticLaunchGateIds.Count) {
    Add-ValidationReason "rules.json declares duplicate Static launch-gate test IDs."
}
foreach ($launchTestId in $staticLaunchGateIds) {
    if (-not $staticPassMap.ContainsKey($launchTestId)) {
        Add-ValidationReason "Static launch-gate test is not a declared Static test: $launchTestId"
    }
}
$staticLaunchGatePassed = $staticLaunchGateIds.Count -gt 0 -and
    @($staticLaunchGateIds | Where-Object {
        -not $staticPassMap.ContainsKey($_) -or -not [bool]$staticPassMap[$_]
    }).Count -eq 0
$launchGatePassed = [bool]$BaselineCompilePassed -and $staticLaunchGatePassed

$dynamicCases = @(Get-NUnitCases $DynamicResultPath "Dynamic")
$dynamicHealthResults = [System.Collections.Generic.List[object]]::new()
foreach ($healthId in @($rules.health_prerequisites.dynamic | ForEach-Object { [string]$_ })) {
    $matches = @(Find-NUnitCase $dynamicCases $healthId)
    $case = if ($matches.Count -eq 1) { $matches[0] } else { $null }
    $result = if ($null -eq $case) { "Missing" } else {
        Get-XmlAttributeValue $case "result"
    }
    $message = Get-NUnitMessage $case
    $passed = $matches.Count -eq 1 -and $result -eq "Passed"
    if (-not $passed) {
        Add-ValidationReason (
            "evaluator_health_failure: Dynamic prerequisite $healthId " +
            "must pass exactly once; found $($matches.Count), result=$result, message=$message")
    }
    $dynamicHealthResults.Add([pscustomobject]@{
        id = $healthId
        result = $result
        passed = $passed
        message = $message
    })
}
foreach ($regressionCase in @($dynamicCases | Where-Object {
    (Get-XmlAttributeValue $_ "methodname").StartsWith(
        "EVALUATOR_REGRESSION_", [StringComparison]::Ordinal) -or
    (Get-XmlAttributeValue $_ "name").StartsWith(
        "EVALUATOR_REGRESSION_", [StringComparison]::Ordinal)
})) {
    if ((Get-XmlAttributeValue $regressionCase "result") -ne "Passed") {
        Add-ValidationReason ("Evaluator self-test " +
            "$(Get-XmlAttributeValue $regressionCase 'name') did not pass.")
    }
}

$trajectoryResults = [System.Collections.Generic.List[object]]::new()
$milestonePassMap = @{}
$dynamicCheckSources = @{}
$dynamicCandidateMarker = "[OMNIGAME_CANDIDATE_DYNAMIC]"
$dynamicAttributableCandidateFailures = [System.Collections.Generic.List[string]]::new()
$legacyEarned = 0.0
$legacyMaximum = 0.0
foreach ($trajectoryRule in @($rules.phases.dynamic.trajectories)) {
    $trajectoryId = [string]$trajectoryRule.id
    $nunitMatches = @(Find-NUnitCase $dynamicCases ([string]$trajectoryRule.nunit_test))
    if ($nunitMatches.Count -ne 1) {
        Add-ValidationReason "Expected one dynamic test $($trajectoryRule.nunit_test), found $($nunitMatches.Count)."
    }
    $nunitCase = if ($nunitMatches.Count -gt 0) { $nunitMatches[0] } else { $null }
    $nunitResult = if ($null -eq $nunitCase) { "Missing" } else {
        Get-XmlAttributeValue $nunitCase "result"
    }
    $nunitMessage = Get-NUnitMessage $nunitCase
    $nunitPassed = $nunitMatches.Count -eq 1 -and $nunitResult -eq "Passed"
    $nunitCandidateMarked = $nunitMatches.Count -eq 1 -and
        $nunitResult -eq "Failed" -and
        $nunitMessage.Contains($dynamicCandidateMarker)
    $nunitCandidateRuntimeFrame = if ($nunitMatches.Count -eq 1 -and
        $nunitResult -eq "Failed") {
        Get-CandidateRuntimeFrame $nunitCase
    } else { "" }
    $nunitCandidateRuntimeException =
        -not [string]::IsNullOrWhiteSpace($nunitCandidateRuntimeFrame)
    if (-not $nunitPassed -and -not $nunitCandidateMarked -and
        -not $nunitCandidateRuntimeException) {
        Add-ValidationReason (
            "Dynamic trajectory test $($trajectoryRule.nunit_test) must either pass after " +
            "sealing evidence, fail once with $dynamicCandidateMarker, or expose a " +
            "candidate-owned Assets stack frame; found " +
            "$($nunitMatches.Count), result=$nunitResult, message=$nunitMessage")
    }

    $definitionPath = Join-Path $DefinitionsDirectory "$trajectoryId.json"
    $evidencePath = Join-Path $EvidenceDirectory "$trajectoryId.json"
    $expectedIds = @()
    $definitionValid = $true
    $evidenceValid = $true
    $evidence = $null
    $checkMap = @{}

    if (-not (Test-Path -LiteralPath $definitionPath -PathType Leaf)) {
        Add-ValidationReason "Missing trajectory definition: $trajectoryId"
        $definitionValid = $false
    } else {
        try {
            $definition = Get-Content -Raw -Encoding UTF8 -LiteralPath $definitionPath | ConvertFrom-Json
            foreach ($step in @($definition.steps)) {
                foreach ($checkId in @($step.check_ids)) { $expectedIds += [string]$checkId }
            }
            if ($expectedIds.Count -eq 0 -or
                @($expectedIds | Select-Object -Unique).Count -ne $expectedIds.Count) {
                Add-ValidationReason "Trajectory definition $trajectoryId has empty or duplicate check IDs."
                $definitionValid = $false
            }
        }
        catch {
            Add-ValidationReason "Trajectory definition $trajectoryId is unreadable: $($_.Exception.Message)"
            $definitionValid = $false
        }
    }

    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        if (-not $nunitCandidateRuntimeException) {
            Add-ValidationReason "Missing trajectory evidence: $trajectoryId"
            $evidenceValid = $false
        }
    } else {
        try {
            $evidence = Get-Content -Raw -Encoding UTF8 -LiteralPath $evidencePath | ConvertFrom-Json
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
                if (-not [string]::Equals($definitionHash, [string]$evidence.definition_sha256,
                        [StringComparison]::OrdinalIgnoreCase)) {
                    Add-ValidationReason "Trajectory definition hash mismatch for $trajectoryId."
                    $evidenceValid = $false
                }
            }
            foreach ($step in @($evidence.steps)) {
                if (-not (Test-PointerRouteEvidence $step $trajectoryId)) { $evidenceValid = $false }
                foreach ($check in @($step.checks)) {
                    $checkId = [string]$check.check_id
                    if ([string]::IsNullOrWhiteSpace($checkId) -or $checkMap.ContainsKey($checkId)) {
                        Add-ValidationReason "Trajectory evidence $trajectoryId has an empty/duplicate check ID."
                        $evidenceValid = $false
                    } else {
                        $checkMap[$checkId] = $check
                    }
                }
            }
        }
        catch {
            Add-ValidationReason "Trajectory evidence $trajectoryId is unreadable: $($_.Exception.Message)"
            $evidenceValid = $false
        }
    }

    $candidateEvidenceConsistent = $false
    $hasPassedProperty = $null -ne $evidence -and
        $null -ne $evidence.PSObject.Properties["passed"]
    $missingExpectedChecks = if ($definitionValid) {
        @($expectedIds | Where-Object { -not $checkMap.ContainsKey([string]$_) })
    } else { @() }
    $sealedNonPassChecks = @()
    if ($definitionValid -and $evidenceValid -and $null -ne $evidence) {
        if (-not $hasPassedProperty) {
            Add-ValidationReason "Trajectory evidence $trajectoryId is missing its sealed passed verdict."
            $evidenceValid = $false
        }
        if (@($missingExpectedChecks).Count -gt 0) {
            Add-ValidationReason (
                "Trajectory evidence $trajectoryId is missing declared checks: " +
                ($missingExpectedChecks -join ", "))
            $evidenceValid = $false
        }
        # The trajectory NUnit case reports evaluator execution/sealing health,
        # not an all-or-nothing candidate verdict. Candidate behavior failures
        # therefore remain valid partial-score evidence when the sealed verdict,
        # counters and check statuses agree with one another.
        $allEvidenceChecks = @($evidence.steps | ForEach-Object { @($_.checks) })
        $sealedNonPassChecks = @($allEvidenceChecks | Where-Object {
            ([string]$_.status).ToLowerInvariant() -in @("fail", "blocked")
        })
        $unknownStatuses = @($allEvidenceChecks | Where-Object {
            ([string]$_.status).ToLowerInvariant() -notin @("pass", "fail", "blocked")
        })
        $actualPassed = @($allEvidenceChecks | Where-Object {
            ([string]$_.status).ToLowerInvariant() -eq "pass"
        }).Count
        $actualFailed = @($allEvidenceChecks | Where-Object {
            ([string]$_.status).ToLowerInvariant() -eq "fail"
        }).Count
        $actualBlocked = @($allEvidenceChecks | Where-Object {
            ([string]$_.status).ToLowerInvariant() -eq "blocked"
        }).Count
        $computedPassed = $unknownStatuses.Count -eq 0 -and
            $actualFailed -eq 0 -and $actualBlocked -eq 0

        # TrajectoryEvidence.failure is deliberately the first explicit
        # status=fail message.  A normally completed candidate journey may
        # instead stop after valid observations and seal only blocked checks;
        # that blocked-only record must keep failure empty.  Conversely, an
        # explicit failed check must always carry the non-empty summary that
        # the writer emits.
        $failureSummaryMissing = $actualFailed -gt 0 -and
            [string]::IsNullOrWhiteSpace([string]$evidence.failure)
        $failureSummaryForged = $actualFailed -eq 0 -and
            -not [string]::IsNullOrWhiteSpace([string]$evidence.failure)

        # Every blocked check must have a closed attribution chain.  The
        # harness uses trajectory.not_executed only when no explicit check has
        # failed yet; once a failure exists, all later blocked checks point
        # directly to a real status=fail check ID.  A blocked-only trajectory
        # must also retain at least one passed observation so an entirely
        # unexecuted evaluator body cannot masquerade as candidate evidence.
        $invalidBlockedChains = @($allEvidenceChecks | Where-Object {
            if (([string]$_.status).ToLowerInvariant() -ne "blocked") {
                return $false
            }
            $blocker = [string]$_.blocked_by
            if ([string]::IsNullOrWhiteSpace($blocker)) { return $true }
            if ($actualFailed -eq 0) {
                return $blocker -ne "trajectory.not_executed"
            }
            return $blocker -eq "trajectory.not_executed" -or
                -not $checkMap.ContainsKey($blocker) -or
                ([string]$checkMap[$blocker].status).ToLowerInvariant() -ne "fail"
        })
        $blockedOnlyWithoutProgress = $actualFailed -eq 0 -and
            $actualBlocked -gt 0 -and $actualPassed -eq 0
        if ($invalidBlockedChains.Count -gt 0 -or $blockedOnlyWithoutProgress) {
            Add-ValidationReason (
                "Trajectory evidence $trajectoryId has an invalid blocked_by " +
                "dependency chain or no passed observation before a blocked-only seal.")
            $evidenceValid = $false
        }
        if ($unknownStatuses.Count -gt 0 -or
            [bool]$evidence.passed -ne $computedPassed -or
            [int]$evidence.checks_passed -ne $actualPassed -or
            [int]$evidence.checks_failed -ne $actualFailed -or
            [int]$evidence.checks_blocked -ne $actualBlocked -or
            $failureSummaryMissing -or $failureSummaryForged) {
            Add-ValidationReason (
                "Trajectory evidence $trajectoryId has an inconsistent sealed verdict, " +
                "failure summary, status set, or pass/fail/blocked counters.")
            $evidenceValid = $false
        }
    }
    if ($nunitCandidateMarked -and $definitionValid -and $evidenceValid -and
        $null -ne $evidence) {
        # The private harness may seal a candidate failure on a diagnostic
        # input/motion check that is intentionally not a public scoring leaf.
        # Any internally consistent sealed non-pass check can therefore
        # explain the candidate-marked NUnit failure and the phase exit code.
        # Milestone credit below still comes only from the declared check IDs,
        # so private diagnostic checks can never deduct hidden points.
        $candidateEvidenceConsistent = $hasPassedProperty -and
            -not [bool]$evidence.passed -and
            @($sealedNonPassChecks).Count -gt 0
        if (-not $candidateEvidenceConsistent) {
            Add-ValidationReason (
                "Dynamic candidate-marked failure $($trajectoryRule.nunit_test) lacks " +
                "sealed fail/blocked evidence.")
        } else {
            $dynamicAttributableCandidateFailures.Add($trajectoryId)
        }
    }
    $runtimeExceptionQualified = $nunitCandidateRuntimeException -and
        $definitionValid -and $evidenceValid -and $null -eq $evidence
    if ($runtimeExceptionQualified) {
        # The candidate exception prevented the harness from sealing this one
        # trajectory. Keep the run valid, but leave the check map empty so every
        # milestone in the interrupted trajectory receives zero credit. Other
        # independently sealed trajectories retain their evidence-derived score.
        $dynamicAttributableCandidateFailures.Add($trajectoryId)
    }
    $nunitQualified = $nunitPassed -or
        ($nunitCandidateMarked -and $candidateEvidenceConsistent) -or
        $runtimeExceptionQualified

    $milestoneResults = [System.Collections.Generic.List[object]]::new()
    foreach ($milestone in @($trajectoryRule.milestones)) {
        $failedChecks = [System.Collections.Generic.List[object]]::new()
        foreach ($requiredCheckId in @($milestone.required_check_ids)) {
            $requiredCheckId = [string]$requiredCheckId
            if ($expectedIds -notcontains $requiredCheckId) {
                $failedChecks.Add([pscustomobject]@{ check_id = $requiredCheckId; status = "undeclared" })
            } elseif (-not $checkMap.ContainsKey($requiredCheckId)) {
                $failedChecks.Add([pscustomobject]@{ check_id = $requiredCheckId; status = "missing" })
            } else {
                $status = ([string]$checkMap[$requiredCheckId].status).ToLowerInvariant()
                if ($status -ne "pass") {
                    $failedChecks.Add([pscustomobject]@{
                        check_id = $requiredCheckId
                        status = $status
                        blocked_by = [string]$checkMap[$requiredCheckId].blocked_by
                    })
                }
            }
        }
        $passed = $nunitQualified -and $definitionValid -and $evidenceValid -and
            $failedChecks.Count -eq 0
        $milestoneId = [string]$milestone.id
        $milestonePassMap[$milestoneId] = $passed
        $legacyMaximum += [double]$milestone.weight
        if ($passed) { $legacyEarned += [double]$milestone.weight }
        $milestoneResults.Add([pscustomobject]@{
            id = $milestoneId
            title = [string]$milestone.title
            passed = $passed
            legacy_weight = [double]$milestone.weight
            failed_checks = @($failedChecks)
        })
    }
    $trajectoryResults.Add([pscustomobject]@{
        id = $trajectoryId
        nunit_test = [string]$trajectoryRule.nunit_test
        nunit_result = $nunitResult
        nunit_message = $nunitMessage
        nunit_candidate_failure = $nunitCandidateMarked -or
            $nunitCandidateRuntimeException
        nunit_candidate_failure_kind = if ($nunitCandidateMarked) {
            "sealed_candidate_evidence"
        } elseif ($nunitCandidateRuntimeException) {
            "candidate_runtime_exception"
        } else { $null }
        nunit_candidate_runtime_frame = if ($nunitCandidateRuntimeException) {
            $nunitCandidateRuntimeFrame
        } else { $null }
        nunit_qualified = $nunitQualified
        evidence_valid = $definitionValid -and $evidenceValid
        full_pass = $nunitPassed -and $definitionValid -and $evidenceValid -and
            @($milestoneResults | Where-Object { -not $_.passed }).Count -eq 0
        milestones = @($milestoneResults)
        evidence = if ($runtimeExceptionQualified) { $null } else { $evidencePath }
    })
    $dynamicCheckSources[$trajectoryId] = @{
        expected_ids = @($expectedIds)
        checks = $checkMap
        valid = $nunitQualified -and $definitionValid -and $evidenceValid
    }
}
$dynamicExitCandidateAttributable =
    $dynamicAttributableCandidateFailures.Count -gt 0
if ($DynamicExitCode -ne 0 -and $acceptedExitCodes -contains $DynamicExitCode -and
    -not $dynamicExitCandidateAttributable) {
    Add-ValidationReason (
        "Dynamic Unity exit code $DynamicExitCode had no candidate-attributable leaf " +
        "failure with valid sealed evidence or an Assets-bound runtime exception; " +
        "COMMAND_FAILED is infrastructure-invalid.")
}

$freshCases = if (-not [string]::IsNullOrWhiteSpace($FreshResultPath) -and
    (Test-Path -LiteralPath $FreshResultPath -PathType Leaf)) {
    @(Get-NUnitCases $FreshResultPath "Fresh")
} else { @() }
$freshHealthResults = [System.Collections.Generic.List[object]]::new()
foreach ($healthId in @($rules.health_prerequisites.fresh | ForEach-Object { [string]$_ })) {
    $matches = @(Find-NUnitCase $freshCases $healthId)
    $case = if ($matches.Count -eq 1) { $matches[0] } else { $null }
    $result = if ($null -eq $case) { "Missing" } else {
        Get-XmlAttributeValue $case "result"
    }
    $message = Get-NUnitMessage $case
    $passed = $matches.Count -eq 1 -and $result -eq "Passed"
    if (-not $passed) {
        Add-ValidationReason (
            "evaluator_health_failure: Fresh prerequisite $healthId " +
            "must pass exactly once; found $($matches.Count), result=$result, message=$message")
    }
    $freshHealthResults.Add([pscustomobject]@{
        id = $healthId
        result = $result
        passed = $passed
        message = $message
    })
}

$freshTestId = [string]$rules.phases.fresh.tests[0].id
$freshTestMatches = @(Find-NUnitCase $freshCases $freshTestId)
$freshTestCase = if ($freshTestMatches.Count -eq 1) { $freshTestMatches[0] } else { $null }
$freshTestResult = if ($null -eq $freshTestCase) { "Missing" } else {
    Get-XmlAttributeValue $freshTestCase "result"
}
$freshTestMessage = Get-NUnitMessage $freshTestCase
$freshCandidateMarker = "[OMNIGAME_CANDIDATE_FRESH]"
$freshCandidateMarked = $freshTestMatches.Count -eq 1 -and
    $freshTestResult -eq "Failed" -and
    $freshTestMessage.Contains($freshCandidateMarker)
if ($freshTestMatches.Count -ne 1) {
    Add-ValidationReason "Expected one Fresh candidate test $freshTestId, found $($freshTestMatches.Count)."
} elseif ($freshTestResult -eq "Failed" -and
    -not $freshTestMessage.Contains($freshCandidateMarker)) {
    Add-ValidationReason "Fresh test $freshTestId failed without the candidate marker."
} elseif ($freshTestResult -notin @("Passed", "Failed", "Missing")) {
    Add-ValidationReason "Fresh test $freshTestId returned unsupported result '$freshTestResult'."
}

$freshProtocolPassed = $false
$freshProtocolEvidence = $null
$expectedSeedPath = Join-Path $EvidenceDirectory "fresh-process-seed.json"
if ([string]::IsNullOrWhiteSpace($FreshSeedPath) -or
    -not [string]::Equals([System.IO.Path]::GetFullPath($FreshSeedPath),
        [System.IO.Path]::GetFullPath($expectedSeedPath),
        [StringComparison]::OrdinalIgnoreCase)) {
    Add-ValidationReason "Fresh seed path is not bound to the current Dynamic evidence directory."
} elseif (-not (Test-Path -LiteralPath $FreshSeedPath -PathType Leaf)) {
    Add-ValidationReason "Fresh seed evidence is missing."
} elseif ([string]::IsNullOrWhiteSpace($FreshEvidenceDirectory)) {
    Add-ValidationReason "Fresh evidence directory is missing."
} else {
    $freshEvidencePath = Join-Path $FreshEvidenceDirectory "fresh-process-evidence.json"
    $dynamicHealthPath = Join-Path $EvidenceDirectory "evaluator-health-dynamic.json"
    $dynamicHealthPng = Join-Path $EvidenceDirectory "evaluator-health-dynamic.png"
    $freshHealthPath = Join-Path $FreshEvidenceDirectory "evaluator-health-fresh.json"
    foreach ($requiredPath in @($dynamicHealthPath, $dynamicHealthPng, $freshHealthPath,
            $freshEvidencePath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            Add-ValidationReason "evaluator_health_failure: required protocol evidence is missing: $requiredPath"
        }
    }
    if ((Test-Path -LiteralPath $FreshSeedPath -PathType Leaf) -and
        (Test-Path -LiteralPath $freshEvidencePath -PathType Leaf) -and
        (Test-Path -LiteralPath $dynamicHealthPath -PathType Leaf) -and
        (Test-Path -LiteralPath $freshHealthPath -PathType Leaf)) {
        try {
            $seed = Get-Content -Raw -Encoding UTF8 -LiteralPath $FreshSeedPath |
                ConvertFrom-Json
            $freshEvidence = Get-Content -Raw -Encoding UTF8 -LiteralPath $freshEvidencePath |
                ConvertFrom-Json
            $dynamicHealthEvidence = Get-Content -Raw -Encoding UTF8 `
                -LiteralPath $dynamicHealthPath | ConvertFrom-Json
            $freshHealthEvidence = Get-Content -Raw -Encoding UTF8 `
                -LiteralPath $freshHealthPath | ConvertFrom-Json
            $pidsValid = [int]$seed.dynamic_process_id -gt 0 -and
                [int]$freshEvidence.dynamic_process_id -eq [int]$seed.dynamic_process_id -and
                [int]$freshEvidence.fresh_process_id -gt 0 -and
                [int]$freshEvidence.fresh_process_id -ne [int]$seed.dynamic_process_id -and
                [int]$dynamicHealthEvidence.process_id -eq [int]$seed.dynamic_process_id -and
                [int]$freshHealthEvidence.dynamic_process_id -eq [int]$seed.dynamic_process_id -and
                [int]$freshHealthEvidence.fresh_process_id -eq [int]$freshEvidence.fresh_process_id
            if (-not $pidsValid) {
                Add-ValidationReason "evaluator_health_failure: Dynamic/Fresh process provenance is inconsistent."
            }
            $freshProtocolPassed = $pidsValid -and
                [bool]$seed.dirty_target_found -and
                [bool]$seed.dirty_input_route_passed -and
                [bool]$seed.dirty_distinct -and
                $freshTestResult -eq "Passed" -and
                [string]$freshEvidence.observed_level -eq [string]$seed.initial_level -and
                [int]$freshEvidence.observed_budget -eq [int]$seed.initial_budget -and
                [int]$freshEvidence.observed_arrow_count -eq [int]$seed.initial_arrow_count -and
                -not [bool]$freshEvidence.observed_completed -and
                -not [bool]$freshEvidence.observed_failed
            $freshProtocolEvidence = [pscustomobject]@{
                seed = $seed
                observation = $freshEvidence
                dynamic_health = $dynamicHealthEvidence
                fresh_health = $freshHealthEvidence
                pids_valid = $pidsValid
            }
        }
        catch {
            Add-ValidationReason "Fresh protocol evidence is unreadable: $($_.Exception.Message)"
        }
    }
}

$freshHealthPassed = $freshHealthResults.Count -gt 0 -and
    @($freshHealthResults | Where-Object { -not $_.passed }).Count -eq 0
$freshCandidateEvidenceMismatch = $false
if ($null -ne $freshProtocolEvidence) {
    $freshSeed = $freshProtocolEvidence.seed
    $freshObservation = $freshProtocolEvidence.observation
    $freshCandidateEvidenceMismatch = -not [bool]$freshSeed.dirty_target_found -or
        -not [bool]$freshSeed.dirty_input_route_passed -or
        -not [bool]$freshSeed.dirty_distinct -or
        [string]$freshObservation.observed_level -ne [string]$freshSeed.initial_level -or
        [int]$freshObservation.observed_budget -ne [int]$freshSeed.initial_budget -or
        [int]$freshObservation.observed_arrow_count -ne [int]$freshSeed.initial_arrow_count -or
        [bool]$freshObservation.observed_completed -or
        [bool]$freshObservation.observed_failed
}
$freshCandidateFailureAttributable = $freshCandidateMarked -and
    $freshHealthPassed -and $null -ne $freshProtocolEvidence -and
    [bool]$freshProtocolEvidence.pids_valid -and
    $freshCandidateEvidenceMismatch
if ($FreshExitCode -ne 0 -and $acceptedExitCodes -contains $FreshExitCode -and
    -not $freshCandidateFailureAttributable) {
    Add-ValidationReason (
        "Fresh Unity exit code $FreshExitCode had no candidate-marked leaf failure " +
        "with valid process evidence; COMMAND_FAILED is infrastructure-invalid.")
}

function Resolve-Checkpoint($Checkpoint) {
    $type = [string]$Checkpoint.source.type
    $passed = $false
    $blockedBy = @()
    switch ($type) {
        "baseline_compile" {
            $passed = [bool]$BaselineCompilePassed
        }
        "static_test" {
            $id = [string]$Checkpoint.source.id
            $passed = $staticPassMap.ContainsKey($id) -and [bool]$staticPassMap[$id]
            if (-not $passed) { $blockedBy = @($id) }
        }
        "milestone" {
            $id = [string]$Checkpoint.source.id
            $passed = $milestonePassMap.ContainsKey($id) -and [bool]$milestonePassMap[$id]
            if (-not $passed) { $blockedBy = @($id) }
        }
        "milestones_all" {
            $ids = @($Checkpoint.source.ids | ForEach-Object { [string]$_ })
            $failed = @($ids | Where-Object {
                -not $milestonePassMap.ContainsKey($_) -or -not [bool]$milestonePassMap[$_]
            })
            $passed = $ids.Count -gt 0 -and $failed.Count -eq 0
            $blockedBy = $failed
        }
        "dynamic_checks_all" {
            $references = @($Checkpoint.source.checks)
            $failed = [System.Collections.Generic.List[string]]::new()
            foreach ($reference in $references) {
                $trajectoryId = [string]$reference.trajectory_id
                $checkId = [string]$reference.id
                $qualifiedId = "$trajectoryId/$checkId"
                if ([string]::IsNullOrWhiteSpace($trajectoryId) -or
                    [string]::IsNullOrWhiteSpace($checkId) -or
                    -not $dynamicCheckSources.ContainsKey($trajectoryId)) {
                    $failed.Add($qualifiedId)
                    continue
                }

                $source = $dynamicCheckSources[$trajectoryId]
                $expectedIds = @($source["expected_ids"])
                $checks = $source["checks"]
                if (-not [bool]$source["valid"] -or
                    $expectedIds -notcontains $checkId -or
                    -not $checks.ContainsKey($checkId) -or
                    ([string]$checks[$checkId].status).ToLowerInvariant() -ne "pass") {
                    $failed.Add($qualifiedId)
                }
            }
            $passed = $references.Count -gt 0 -and $failed.Count -eq 0
            $blockedBy = @($failed)
        }
        "fresh_process_reopen" {
            $passed = [bool]$freshProtocolPassed
            if (-not $passed) {
                $blockedBy = @(
                    "post-Dynamic dirty-state seed and separate Fresh-process observation")
            }
        }
        default {
            Add-ValidationReason "Unknown checkpoint source type '$type' for $($Checkpoint.id)."
        }
    }
    return [pscustomobject]@{
        id = [string]$Checkpoint.id
        title = [string]$Checkpoint.title
        status = if ($passed) { "pass" } else { "fail" }
        passed = $passed
        source_type = $type
        failed_dependencies = @($blockedBy)
    }
}

$dimensionResults = [System.Collections.Generic.List[object]]::new()
$automaticScore = 0.0
foreach ($dimension in @($rules.dimensions | Where-Object { [string]$_.id -ne "D6" })) {
    $checkpointResults = @($dimension.checkpoints | ForEach-Object { Resolve-Checkpoint $_ })
    $passedCount = @($checkpointResults | Where-Object { $_.passed }).Count
    $score = if ($checkpointResults.Count -gt 0) {
        Round-Score ([double]$dimension.maximum_score * $passedCount / $checkpointResults.Count)
    } else { 0.0 }
    $automaticScore += $score
    $dimensionResults.Add([pscustomobject]@{
        id = [string]$dimension.id
        title = [string]$dimension.title
        stage = [string]$dimension.stage
        status = "evaluated"
        score = $score
        maximum_score = [double]$dimension.maximum_score
        passed_checkpoints = $passedCount
        total_checkpoints = $checkpointResults.Count
        checkpoints = $checkpointResults
    })
}
$automaticScore = Round-Score $automaticScore

$visualDimension = @($rules.dimensions | Where-Object { [string]$_.id -eq "D6" }) |
    Select-Object -First 1
$d6Status = "pending"
$d6Score = $null
$visualRounds = @()
$visualStates = @()
$visualInputPath = $null
$visualInputSha256 = $null
if (-not [string]::IsNullOrWhiteSpace($VisualScorePath)) {
    if (-not (Test-Path -LiteralPath $VisualScorePath -PathType Leaf)) {
        Add-VisualValidationReason "Visual score file does not exist: $VisualScorePath"
    } else {
        try {
            $VisualScorePath = (Resolve-Path -LiteralPath $VisualScorePath).Path
            $visual = Get-Content -Raw -Encoding UTF8 -LiteralPath $VisualScorePath | ConvertFrom-Json
            if ([int]$visual.schema_version -ne 2) {
                Add-VisualValidationReason "Visual score schema_version must be 2."
            }
            if ([string]$visual.status -ne "evaluated") {
                Add-VisualValidationReason "Visual score status must be evaluated."
            }

            $declaredInputPath = [string]$visual.input_path
            $declaredInputHash = [string]$visual.input_sha256
            if ([string]::IsNullOrWhiteSpace($declaredInputPath)) {
                Add-VisualValidationReason "Visual score is missing input_path provenance."
            } elseif ($declaredInputHash -notmatch '^[0-9a-fA-F]{64}$') {
                Add-VisualValidationReason "Visual score input_sha256 must be a 64-character SHA256."
            } else {
                $resolvedInputPath = if ([System.IO.Path]::IsPathRooted($declaredInputPath)) {
                    $declaredInputPath
                } else {
                    Join-Path (Split-Path -Parent $VisualScorePath) $declaredInputPath
                }
                if (-not (Test-Path -LiteralPath $resolvedInputPath -PathType Leaf)) {
                    Add-VisualValidationReason "Visual input provenance file does not exist: $resolvedInputPath"
                } else {
                    $resolvedInputPath = (Resolve-Path -LiteralPath $resolvedInputPath).Path
                    $actualInputHash = (Get-FileHash -LiteralPath $resolvedInputPath `
                        -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($actualInputHash -ne $declaredInputHash.ToLowerInvariant()) {
                        Add-VisualValidationReason (
                            "Visual input provenance SHA256 mismatch. Declared " +
                            "$declaredInputHash, actual $actualInputHash.")
                    } else {
                        $visualInputPath = $resolvedInputPath
                        $visualInputSha256 = $actualInputHash
                    }
                }
            }

            if ($visualValidationReasons.Count -eq 0) {
                $scoreVisualScript = Join-Path $PSScriptRoot "score-visual.ps1"
                $recomputedRaw = & $scoreVisualScript -InputPath $visualInputPath
                $recomputed = (($recomputedRaw -join [Environment]::NewLine) |
                    ConvertFrom-Json)

                $expectedVisualRoot = [System.IO.Path]::GetFullPath(
                    (Join-Path $EvidenceDirectory "visual"))
                foreach ($state in @($recomputed.states)) {
                    $stateId = [string]$state.id
                    $expectedCandidate = [System.IO.Path]::GetFullPath(
                        (Join-Path $expectedVisualRoot ($stateId + ".png")))
                    $actualCandidate = [System.IO.Path]::GetFullPath(
                        [string]$state.candidate.path)
                    if (-not [string]::Equals($actualCandidate, $expectedCandidate,
                            [StringComparison]::OrdinalIgnoreCase)) {
                        Add-VisualValidationReason (
                            "State $stateId candidate is not bound to this Dynamic run's " +
                            "visual evidence directory.")
                    }
                }

                if ($visualValidationReasons.Count -eq 0) {
                    $d6Status = "evaluated"
                    $d6Score = [double]$recomputed.d6_score
                    $visualRounds = @($recomputed.rounds | ForEach-Object { [double]$_ })
                    $visualStates = @($recomputed.states)
                }
            }
        }
        catch {
            Add-VisualValidationReason "Visual provenance validation failed: $($_.Exception.Message)"
        }
    }
    if ($visualValidationReasons.Count -gt 0) {
        $d6Status = "invalid_visual"
        $d6Score = $null
        $visualRounds = @()
        $visualStates = @()
    }
}
$dimensionResults.Add([pscustomobject]@{
    id = "D6"
    title = [string]$visualDimension.title
    stage = "visual"
    status = $d6Status
    score = $d6Score
    maximum_score = 10.0
    rounds = @($visualRounds)
    states = @($visualStates)
    prompt = Join-Path $evaluationRoot ([string]$rules.phases.visual.prompt_path)
    reference_manifest = Join-Path $evaluationRoot ([string]$rules.phases.visual.reference_manifest_path)
})

$validScore = $validationReasons.Count -eq 0
$rawOverallScore = if ($validScore -and $d6Status -eq "evaluated") {
    Round-Score ($automaticScore + [double]$d6Score)
} else { $null }

# Score caps are explicit GDD/common-baseline completeness gates. They never
# manufacture a failure and never branch on model/run identity: each trigger is
# resolved from the same sealed Static/Dynamic/Fresh evidence used by D1-D5.
$scoreCapResults = [System.Collections.Generic.List[object]]::new()
$activeOverallCap = 100.0
foreach ($cap in @($rules.official_scoring.score_caps)) {
    $sourceType = [string]$cap.source.type
    $sourceId = [string]$cap.source.id
    $sourcePassed = $false
    switch ($sourceType) {
        "milestone" {
            $sourcePassed = $milestonePassMap.ContainsKey($sourceId) -and
                [bool]$milestonePassMap[$sourceId]
        }
        "checkpoint" {
            $checkpoint = @($dimensionResults | ForEach-Object { @($_.checkpoints) } |
                Where-Object { [string]$_.id -eq $sourceId }) | Select-Object -First 1
            $sourcePassed = $null -ne $checkpoint -and [bool]$checkpoint.passed
        }
        default {
            Add-ValidationReason "Unknown score-cap source type '$sourceType' for $($cap.id)."
        }
    }
    $triggered = -not $sourcePassed
    $maximum = [double]$cap.maximum_overall_score
    if ($triggered) { $activeOverallCap = [Math]::Min($activeOverallCap, $maximum) }
    $scoreCapResults.Add([pscustomobject]@{
        id = [string]$cap.id
        source_type = $sourceType
        source_id = $sourceId
        source_passed = [bool]$sourcePassed
        triggered = [bool]$triggered
        maximum_overall_score = $maximum
        reason = [string]$cap.reason
    })
}
$validScore = $validationReasons.Count -eq 0
$overallScore = if ($validScore -and $null -ne $rawOverallScore) {
    Round-Score ([Math]::Min([double]$rawOverallScore, $activeOverallCap))
} else { $null }
$executable = $launchGatePassed
$d2 = @($dimensionResults | Where-Object { $_.id -eq "D2" }) | Select-Object -First 1
$d3 = @($dimensionResults | Where-Object { $_.id -eq "D3" }) | Select-Object -First 1
$d4 = @($dimensionResults | Where-Object { $_.id -eq "D4" }) | Select-Object -First 1
$d5 = @($dimensionResults | Where-Object { $_.id -eq "D5" }) | Select-Object -First 1
$activeScoreCaps = @($scoreCapResults | Where-Object { $_.triggered })
$solved = $validScore -and $executable -and $staticFullPass -and
    [double]$d2.score -eq [double]$d2.maximum_score -and
    [double]$d3.score -eq [double]$d3.maximum_score -and
    [double]$d4.score -eq [double]$d4.maximum_score -and
    [double]$d5.score -eq [double]$d5.maximum_score -and
    $activeScoreCaps.Count -eq 0
$reportedExecutable = if ($evaluatorUnsupportedReasons.Count -gt 0) {
    $null
} else {
    [bool]$executable
}
$candidateStatus = if ($evaluatorUnsupportedReasons.Count -gt 0) {
    "evaluator_unsupported"
} elseif (-not $validScore) {
    "invalid"
} elseif (-not $executable) {
    "not_executable"
} elseif ($d6Status -eq "invalid_visual") {
    "invalid_visual"
} elseif ($solved -and $d6Status -eq "pending") {
    "solved_pending_visual"
} elseif ($solved) {
    "complete"
} else {
    "partial"
}

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
    raw_score_before_caps = $rawOverallScore
    maximum_score = 100.0
    automatic_score = if ($validScore) { $automaticScore } else { $null }
    automatic_maximum_score = 90.0
    d6_status = $d6Status
    executable = $reportedExecutable
    launch_gate_passed = if ($evaluatorUnsupportedReasons.Count -gt 0) {
        $null
    } else {
        [bool]$launchGatePassed
    }
    solved = [bool]$solved
    package_valid = $null
    source_binding = $currentSourceBinding
    dimensions = @($dimensionResults)
    score_caps = @($scoreCapResults)
    active_overall_cap = if ($activeScoreCaps.Count -gt 0) {
        [double]$activeOverallCap
    } else { $null }
    overall = [pscustomobject]@{
        status = if ($evaluatorUnsupportedReasons.Count -gt 0) {
            "evaluator_unsupported"
        } elseif (-not $validScore) {
            "invalid"
        } elseif ($d6Status -eq "invalid_visual") {
            "invalid_visual"
        } elseif ($d6Status -eq "pending") {
            "pending_d6"
        } else {
            "evaluated"
        }
        score = $overallScore
        raw_score_before_caps = $rawOverallScore
        maximum_score = 100.0
        automatic_score = if ($validScore) { $automaticScore } else { $null }
        automatic_maximum_score = 90.0
        active_cap = if ($activeScoreCaps.Count -gt 0) {
            [double]$activeOverallCap
        } else { $null }
    }
    phases = [pscustomobject]@{
        static = [pscustomobject]@{
            maximum_score = 10.0
            full_pass = $staticFullPass
            launch_gate_passed = if ($evaluatorUnsupportedReasons.Count -gt 0) {
                $null
            } else {
                [bool]$launchGatePassed
            }
            launch_gate_test_ids = @($staticLaunchGateIds)
            unity_exit_code = $StaticExitCode
            exit_candidate_attributable = $staticExitCandidateAttributable
            result_xml = $StaticResultPath
            tests = @($staticResults)
        }
        dynamic = [pscustomobject]@{
            maximum_score = 80.0
            unity_exit_code = $DynamicExitCode
            exit_candidate_attributable = $dynamicExitCandidateAttributable
            attributable_candidate_failures = @($dynamicAttributableCandidateFailures)
            result_xml = $DynamicResultPath
            evidence_directory = $EvidenceDirectory
            visual_capture_directory = Join-Path $EvidenceDirectory "visual"
            health_prerequisites = @($dynamicHealthResults)
            trajectories = @($trajectoryResults)
        }
        fresh = [pscustomobject]@{
            unity_exit_code = $FreshExitCode
            exit_candidate_attributable = $freshCandidateFailureAttributable
            result_xml = $FreshResultPath
            evidence_directory = $FreshEvidenceDirectory
            seed_path = $FreshSeedPath
            health_prerequisites = @($freshHealthResults)
            candidate_test = [pscustomobject]@{
                id = $freshTestId
                result = $freshTestResult
                message = $freshTestMessage
            }
            protocol_passed = [bool]$freshProtocolPassed
            protocol_evidence = $freshProtocolEvidence
        }
        visual = [pscustomobject]@{
            maximum_score = 10.0
            status = $d6Status
            score_file = if ([string]::IsNullOrWhiteSpace($VisualScorePath)) { $null } else { $VisualScorePath }
            input_path = $visualInputPath
            input_sha256 = $visualInputSha256
            validation_reasons = @($visualValidationReasons)
        }
    }
    legacy_diagnostics = [pscustomobject]@{
        milestone_score = Round-Score $legacyEarned
        milestone_maximum = Round-Score $legacyMaximum
        note = "Diagnostic only; official scoring is D1-D6 above."
    }
    artifacts = [pscustomobject]@{
        rules = $RulesPath
        trajectory_definitions = $DefinitionsDirectory
        visual_prompt = Join-Path $evaluationRoot ([string]$rules.phases.visual.prompt_path)
        reference_manifest = Join-Path $evaluationRoot ([string]$rules.phases.visual.reference_manifest_path)
    }
}

$json = $report | ConvertTo-Json -Depth 16
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputParent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
        New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($OutputPath, $json,
        [System.Text.UTF8Encoding]::new($false))
}
$json

if (-not $validScore -and -not $NoExitOnInvalid) { exit 3 }
