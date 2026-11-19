[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [string]$UnityEditorPath=$env:UNITY_EDITOR,

    [string]$UnityCliPath=$env:UNITY_CLI,

    [string]$OutputDirectory = "",

    [string]$PhaseRunnerPath = "",

    [string]$BaselineRunnerPath = "",

    [string]$VisualScorePath = "",

    [switch]$AllowRepositoryTmpOutput
)

$ErrorActionPreference = "Stop"
$evaluationRoot = Split-Path -Parent $PSScriptRoot
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$UnityEditorPath = (Resolve-Path -LiteralPath $UnityEditorPath).Path
$UnityCliPath = (Resolve-Path -LiteralPath $UnityCliPath).Path
if ([string]::IsNullOrWhiteSpace($PhaseRunnerPath)) {
    $PhaseRunnerPath = Join-Path $PSScriptRoot "run-phase.ps1"
}
$PhaseRunnerPath = (Resolve-Path -LiteralPath $PhaseRunnerPath).Path
if ([string]::IsNullOrWhiteSpace($BaselineRunnerPath)) {
    $BaselineRunnerPath = Join-Path $PSScriptRoot "run-candidate-compile.ps1"
}
$BaselineRunnerPath = (Resolve-Path -LiteralPath $BaselineRunnerPath).Path

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    throw "OutputDirectory is required. Use a new directory under repository runs/ " +
        "or this Demo's evaluation/reference/."
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$demoRoot = Split-Path -Parent $evaluationRoot
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $demoRoot)
$allowedRuns = ([System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "runs"))).TrimEnd('\') + '\'
$allowedReference = ([System.IO.Path]::GetFullPath(
    (Join-Path $evaluationRoot "reference"))).TrimEnd('\') + '\'
$allowedTmp = ([System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "tmp"))).TrimEnd('\') + '\'
$outputBoundary = $OutputDirectory.TrimEnd('\') + '\'
if (-not $outputBoundary.StartsWith(
        $allowedRuns, [StringComparison]::OrdinalIgnoreCase) -and
    -not $outputBoundary.StartsWith(
        $allowedReference, [StringComparison]::OrdinalIgnoreCase) -and
    -not ($AllowRepositoryTmpOutput -and $outputBoundary.StartsWith(
        $allowedTmp, [StringComparison]::OrdinalIgnoreCase))) {
    throw "OutputDirectory must be under $allowedRuns or $allowedReference"
}
if (Test-Path -LiteralPath $OutputDirectory) {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        throw "OutputDirectory exists but is not a directory: $OutputDirectory"
    }
    $existingOutput = @(Get-ChildItem -LiteralPath $OutputDirectory -Force)
    if ($existingOutput.Count -gt 0) {
        throw "OutputDirectory must be new or empty; refusing to mix stale evidence: " +
            $OutputDirectory
    }
} else {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

function Invoke-EvaluationPhase([string]$Phase, [int]$PriorProcessId = 0) {
    $phaseDirectory = Join-Path $OutputDirectory $Phase.ToLowerInvariant()
    New-Item -ItemType Directory -Path $phaseDirectory -Force | Out-Null
    $raw = & $PhaseRunnerPath `
        -ProjectPath $ProjectPath `
        -Phase $Phase `
        -UnityEditorPath $UnityEditorPath `
        -UnityCliPath $UnityCliPath `
        -OutputDirectory $phaseDirectory `
        -PriorProcessId $PriorProcessId `
        -NoExitOnCompletion
    return (($raw -join [Environment]::NewLine) | ConvertFrom-Json)
}

function Invoke-CandidateCompileBaseline {
    $baselineDirectory = Join-Path $OutputDirectory "baseline"
    New-Item -ItemType Directory -Path $baselineDirectory -Force | Out-Null
    $raw = & $BaselineRunnerPath `
        -ProjectPath $ProjectPath `
        -UnityEditorPath $UnityEditorPath `
        -UnityCliPath $UnityCliPath `
        -OutputDirectory $baselineDirectory `
        -NoExitOnCompletion
    return (($raw -join [Environment]::NewLine) | ConvertFrom-Json)
}

function Assert-PhaseInfrastructureHealthy($PhaseRun) {
    if ([string]$PhaseRun.execution_status -eq "infrastructure_error") {
        $prefix = if ([string]$PhaseRun.failure_kind -eq "evaluator_health_failure") {
            "invalid_evaluator_health: "
        } else { "" }
        throw $prefix + "$($PhaseRun.phase) evaluation infrastructure failed with Unity exit code " +
            "$($PhaseRun.exit_code). See log: $($PhaseRun.log)"
    }
    $resultPath = [string]$PhaseRun.result
    $resultExists = -not [string]::IsNullOrWhiteSpace($resultPath) -and
        (Test-Path -LiteralPath $resultPath -PathType Leaf)
    if (-not $resultExists) {
        $attributableCandidateFailure =
            [string]$PhaseRun.execution_status -eq "candidate_failed" -and
            (
                ([string]$PhaseRun.failure_kind -eq "candidate_compilation_error" -and
                    @($PhaseRun.compiler_errors).Count -gt 0) -or
                ([string]$PhaseRun.failure_kind -eq "candidate_input_api_mismatch" -and
                    $null -ne $PhaseRun.input_system_mismatch_evidence)
            )
        if ($attributableCandidateFailure) {
            return
        }
        throw "$($PhaseRun.phase) evaluation produced no NUnit result XML. " +
            "See log: $($PhaseRun.log)"
    }
}

function Assert-EvaluatorHealthArtifacts($PhaseRun) {
    $phaseName = [string]$PhaseRun.phase
    if ($phaseName -ne "Dynamic" -and $phaseName -ne "Fresh") { return }
    $rules = Get-Content -Raw -Encoding UTF8 -LiteralPath (
        Join-Path $evaluationRoot "rules.json") | ConvertFrom-Json
    $phaseKey = $phaseName.ToLowerInvariant()
    $healthRule = $rules.health_prerequisites.PSObject.Properties[$phaseKey].Value
    foreach ($artifactName in @($healthRule.required_artifacts)) {
        $artifactPath = Join-Path ([string]$PhaseRun.evidence) ([string]$artifactName)
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            throw "invalid_evaluator_health: $phaseName protected artifact is missing: $artifactPath"
        }
        try {
            $artifact = Get-Content -Raw -Encoding UTF8 -LiteralPath $artifactPath |
                ConvertFrom-Json
            if ([string]$artifact.evaluator_health -ne "passed" -or
                [int]$artifact.process_id -ne [int]$PhaseRun.process_id) {
                throw "artifact content/process binding mismatch"
            }
        }
        catch {
            throw "invalid_evaluator_health: $phaseName protected artifact is invalid: " +
                $_.Exception.Message
        }
    }
}

function Complete-StaticCandidateFailure(
    $StaticRun,
    $BaselineRun,
    $CandidateFailure,
    $StaticTests
) {
    $rulesPath = Join-Path $evaluationRoot "rules.json"
    $rules = Get-Content -Raw -Encoding UTF8 -LiteralPath $rulesPath |
        ConvertFrom-Json
    $scorePath = Join-Path $OutputDirectory "score.json"
    $staticTests = @($StaticTests)
    $staticRuleCount = @($rules.phases.static.tests).Count
    $staticPassedCount = @($staticTests | Where-Object {
        [string]$_.result -eq "Passed"
    }).Count
    $staticScore = if ($staticRuleCount -gt 0) {
        [Math]::Round(
            10.0 * $staticPassedCount / $staticRuleCount,
            1,
            [MidpointRounding]::AwayFromZero)
    } else { 0.0 }
    $gateResults = foreach ($gate in @($rules.score_caps)) {
        $isStaticGate = [string]$gate.phase_id -eq "static"
        [pscustomobject]@{
            id = [string]$gate.id
            scope = if (-not [string]::IsNullOrWhiteSpace([string]$gate.phase_id)) {
                "phase"
            } else {
                "trajectory"
            }
            phase_id = if (-not [string]::IsNullOrWhiteSpace([string]$gate.phase_id)) {
                [string]$gate.phase_id
            } else {
                $null
            }
            trajectory_id = if (-not [string]::IsNullOrWhiteSpace([string]$gate.trajectory_id)) {
                [string]$gate.trajectory_id
            } else {
                $null
            }
            triggered = $isStaticGate
            apply_to_overall = $false
            reduced_score = $false
            maximum_final_score = [double]$gate.maximum_final_score
            reason = [string]$gate.reason
        }
    }
    $capabilityResults = foreach ($capability in @($rules.capabilities)) {
        [pscustomobject]@{
            id = [string]$capability.id
            title = [string]$capability.title
            score = if ([string]$capability.id -eq "D1") {
                [double]$staticScore
            } else { 0.0 }
            maximum_score = [double]$capability.maximum_score
            completion_ratio = if ([string]$capability.id -eq "D1") {
                [double]$staticScore / [double]$capability.maximum_score
            } else { 0.0 }
        }
    }
    $report = [pscustomobject]@{
        schema_version = 2
        evaluator_protocol = [string]$rules.evaluator_protocol
        generated_utc = [DateTime]::UtcNow.ToString("o")
        project_path = $ProjectPath
        valid_score = $true
        candidate_status = "static_gate_failed"
        validation_reasons = @()
        score = $null
        score_status = "pending_visual"
        automated_score = [double]$staticScore
        automated_maximum_score = [double]$rules.automated_maximum_score
        score_before_caps = $null
        maximum_score = [double]$rules.maximum_score
        dimensions = [pscustomobject]@{
            D1 = [pscustomobject]@{
                title = "Engineering Validity & Engine Integration"
                score = [double]$staticScore
                maximum_score = 10.0
                status = "evaluated"
            }
            D2 = [pscustomobject]@{ title = "Specification Fulfillment & Content Completeness"; score = 0.0; maximum_score = 30.0; status = "not_reached" }
            D3 = [pscustomobject]@{ title = "Gameplay Correctness & System Behavior"; score = 0.0; maximum_score = 20.0; status = "not_reached" }
            D4 = [pscustomobject]@{ title = "End-to-End Flow & Lifecycle Integrity"; score = 0.0; maximum_score = 20.0; status = "not_reached" }
            D5 = [pscustomobject]@{ title = "Interface Functionality & Player Feedback"; score = 0.0; maximum_score = 10.0; status = "not_reached" }
            D6 = [pscustomobject]@{ title = "Visual Assembly & Presentation Fidelity"; score = $null; maximum_score = 10.0; status = "not_evaluated"; rounds = @() }
        }
        overall = [pscustomobject]@{
            score = $null
            maximum_score = 100.0
            status = "pending_visual"
            note = "Dynamic was skipped after the Static candidate failure; D6 was not evaluated."
        }
        executable = $false
        solved = $false
        package_valid = [pscustomobject]@{ value = $null; status = "not_evaluated" }
        candidate_failure = [pscustomobject]@{
            kind = [string]$CandidateFailure.kind
            reason = [string]$CandidateFailure.reason
            attribution = [string]$CandidateFailure.attribution
            compiler_errors = @($CandidateFailure.compiler_errors)
            input_system_mismatch_evidence = if (
                $null -ne $CandidateFailure.PSObject.Properties[
                    "input_system_mismatch_evidence"]
            ) {
                $CandidateFailure.input_system_mismatch_evidence
            } else {
                $null
            }
            log = [string]$CandidateFailure.log
            baseline_compile = $BaselineRun
            injected_static_diagnostics = [pscustomobject]@{
                compiler_errors = if ($null -ne $StaticRun) {
                    @($StaticRun.compiler_errors)
                } else {
                    @()
                }
                log = if ($null -ne $StaticRun) { [string]$StaticRun.log } else { "" }
            }
        }
        phases = [pscustomobject]@{
            static = [pscustomobject]@{
                score = [double]$staticScore
                maximum_score = [double]$rules.phases.static.maximum_score
                full_pass = $false
                unity_exit_code = if ($null -ne $StaticRun) {
                    [int]$StaticRun.exit_code
                } else {
                    [int]$BaselineRun.exit_code
                }
                execution_status = if ($null -ne $StaticRun) {
                    [string]$StaticRun.execution_status
                } else {
                    [string]$BaselineRun.execution_status
                }
                failure_kind = [string]$CandidateFailure.kind
                result_xml = if ($null -ne $StaticRun) {
                    [string]$StaticRun.result
                } else {
                    $null
                }
                log = [string]$CandidateFailure.log
                tests = @($staticTests)
            }
            dynamic = [pscustomobject]@{
                score = 0.0
                maximum_score = [double]$rules.phases.dynamic.maximum_score
                skipped = $true
                skip_reason = "Static playability gate failed."
                trajectories = @()
            }
            fresh = [pscustomobject]@{
                score = 0.0
                maximum_score = [double]$rules.phases.fresh.maximum_score
                skipped = $true
                skip_reason = "Static playability gate failed."
            }
            visual = [pscustomobject]@{
                status = "not_evaluated"
                score = $null
                maximum_score = 10.0
                rounds = @()
                inputs_ready = $false
                states = @()
            }
        }
        score_caps = @($gateResults)
        capabilities = @($capabilityResults)
        artifacts = [pscustomobject]@{
            rules = $rulesPath
            trajectory_definitions = Join-Path $evaluationRoot `
                "package\Tests\Dynamic\Resources\TrajectoryDefinitions"
            visual_manifest = Join-Path $evaluationRoot "visual\manifest.json"
            visual_prompt = Join-Path $evaluationRoot "visual\visual_prompt.txt"
        }
    }
    $scoreJson = $report | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText(
        $scorePath,
        $scoreJson,
        [System.Text.UTF8Encoding]::new($false))

    [pscustomobject]@{
        project_path = $ProjectPath
        run_directory = $OutputDirectory
        valid_score = $true
        score = $null
        score_status = "pending_visual"
        automated_score = [double]$staticScore
        maximum_score = [double]$rules.maximum_score
        candidate_status = "static_gate_failed"
        static = if ($null -ne $StaticRun) { $StaticRun } else { $BaselineRun }
        baseline_compile = $BaselineRun
        dynamic = [pscustomobject]@{
            execution_status = "skipped"
            skip_reason = "Static playability gate failed."
        }
        fresh = [pscustomobject]@{
            execution_status = "skipped"
            skip_reason = "Static playability gate failed."
        }
        score_report = $scorePath
    } | ConvertTo-Json -Depth 8
}

function Get-StaticTestDisposition($StaticRun) {
    $candidateMarker = "[OMNIGAME_CANDIDATE_STATIC]"
    $rulesPath = Join-Path $evaluationRoot "rules.json"
    $rules = Get-Content -Raw -Encoding UTF8 -LiteralPath $rulesPath |
        ConvertFrom-Json
    try {
        [xml]$document = Get-Content -Raw -Encoding UTF8 -LiteralPath (
            [string]$StaticRun.result)
    }
    catch {
        throw "Static result XML is unreadable: $($_.Exception.Message)"
    }

    $cases = @($document.SelectNodes("//test-case"))
    $results = [System.Collections.Generic.List[object]]::new()
    $candidateFailures = [System.Collections.Generic.List[object]]::new()

    function Get-FailureStackTrace($Case) {
        $stackNode = $Case.SelectSingleNode("failure/stack-trace")
        if ($null -eq $stackNode) { return "" }
        return ([string]$stackNode.InnerText).Trim()
    }

    function Get-CandidateFailureAttribution(
        $Case,
        [string]$Message,
        [string]$TestId
    ) {
        if ($Message.Contains($candidateMarker)) {
            return "stable_candidate_marker_in_static_evaluator"
        }

        # A malformed hand-authored Scene can fail inside Unity's native Scene
        # loader before SetUp reaches RequireCandidate. Such a failure has no
        # candidate Assets/*.cs frame, but it is still attributable to the
        # submitted canonical Scene rather than to the injected evaluator.
        # Keep this deliberately narrow: the exact canonical path, an explicit
        # Scene open/load/deserialization failure, and either STATIC01 or the
        # shared UnitySetUp boundary must all be present.
        $stackTrace = Get-FailureStackTrace $Case
        $normalizedFailure = ($Message + "`n" + $stackTrace).Replace('\', '/')
        $canonicalScene = "Assets/DungeonDuelBenchmark/Scenes/DungeonDuel.unity"
        $mentionsCanonicalScene = $normalizedFailure.IndexOf(
            $canonicalScene,
            [StringComparison]::OrdinalIgnoreCase) -ge 0
        $isUnitySetUpFailure =
            $Message -match '(?im)^\s*(?:Unity)?SetUp\s*:' -or
            $normalizedFailure -match '(?i)\bStaticGateTests\.SetUp\b'
        $hasSceneOperation = $normalizedFailure -match
            '(?i)\b(?:open(?:ing|ed)?|load(?:ing|ed)?|deserializ(?:e|ed|ing|ation)|serializ(?:e|ed|ing|ation)|pars(?:e|ed|ing))\b'
        $hasFailureSignal = $normalizedFailure -match
            '(?i)\b(?:fail(?:ed|ure)?|error|exception|invalid|cannot|could\s+not|couldn''t|unable)\b'
        if ($mentionsCanonicalScene -and $isUnitySetUpFailure -and
            $hasSceneOperation -and $hasFailureSignal) {
            return "candidate_scene_deserialization_failure"
        }

        # Unity Test Framework can fail a UnitySetUp before the evaluator's
        # assertion executes when candidate runtime code logs an unhandled
        # exception during Scene load. In that case NUnit omits our marker, but
        # the failure stack still identifies an Assets/... candidate source
        # frame. Treat that as a candidate D1 failure, not evaluator-invalid.
        # Evaluator code is injected as a Packages/ dependency and therefore
        # cannot satisfy this candidate-source pattern.
        $normalizedStack = $stackTrace.Replace('\', '/')
        if ($normalizedStack -match
            '(?im)(?:^|[\s(])(?:[A-Za-z]:/[^)\r\n]*/)?Assets/[^)\r\n]+\.cs:\d+') {
            return "candidate_assets_stack_trace"
        }

        # Unity sometimes reports the new/legacy input mismatch through
        # LogAssert without preserving the candidate Update() frame in NUnit's
        # stack-trace node. This was previously an attribution cliff: the same
        # defect could be a valid candidate failure or evaluator-invalid solely
        # depending on Unity's stack serialization. Keep the fallback narrow and
        # independently corroborated. It only applies to the exact Input System
        # mismatch diagnostic, only when this submitted project is configured as
        # Input System-only, and only when candidate-authored C# under the writable
        # root actually references legacy UnityEngine.Input APIs. Evaluator-owned
        # Packages code and arbitrary unmarked exceptions remain invalid.
        $isLegacyInputMismatch = $normalizedFailure -match
            '(?is)You are trying to read Input using the UnityEngine\.Input class.*active Input handling.*Input System package'
        if ($isLegacyInputMismatch) {
            $projectSettings = Join-Path $ProjectPath "ProjectSettings\ProjectSettings.asset"
            $inputSystemOnly = $false
            if (Test-Path -LiteralPath $projectSettings -PathType Leaf) {
                $settingsText = Get-Content -Raw -Encoding UTF8 -LiteralPath $projectSettings
                $inputSystemOnly = $settingsText -match '(?m)^\s*activeInputHandler:\s*1\s*$'
            }
            $candidateRoot = Join-Path $ProjectPath "Assets\DungeonDuelBenchmark"
            $legacyApiPattern = '(?<![A-Za-z0-9_])(?:UnityEngine\.)?Input\s*\.\s*(?:GetKey|GetKeyDown|GetKeyUp|GetMouseButton|GetMouseButtonDown|GetMouseButtonUp|mousePosition|mouseScrollDelta|touchCount|GetTouch|GetAxis|GetAxisRaw|GetButton|GetButtonDown|GetButtonUp|anyKey|anyKeyDown)\b'
            $legacySourceFiles = [System.Collections.Generic.List[string]]::new()
            if (Test-Path -LiteralPath $candidateRoot -PathType Container) {
                foreach ($sourceFile in @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter '*.cs')) {
                    try {
                        $sourceText = Get-Content -Raw -Encoding UTF8 -LiteralPath $sourceFile.FullName
                        if ($sourceText -match $legacyApiPattern) {
                            $legacySourceFiles.Add($sourceFile.FullName)
                        }
                    }
                    catch {
                        # A source read failure must not turn into an accidental
                        # candidate attribution; leave the corroboration absent.
                    }
                }
            }
            if ($inputSystemOnly -and $legacySourceFiles.Count -gt 0) {
                return "candidate_legacy_input_api_mismatch"
            }
        }
        return ""
    }

    foreach ($rule in @($rules.phases.static.tests)) {
        $id = [string]$rule.id
        $matches = @($cases | Where-Object {
            ([string]$_.methodname -eq $id) -or ([string]$_.name -eq $id)
        })
        if ($matches.Count -ne 1) {
            throw "Expected exactly one Static test case $id, found $($matches.Count)."
        }
        $case = $matches[0]
        $result = [string]$case.result
        $failureNode = $case.SelectSingleNode("failure/message")
        $reasonNode = $case.SelectSingleNode("reason/message")
        $message = if ($null -ne $failureNode) {
            ([string]$failureNode.InnerText).Trim()
        } elseif ($null -ne $reasonNode) {
            ([string]$reasonNode.InnerText).Trim()
        } else {
            ""
        }

        if ($result -eq "Failed") {
            $attribution = Get-CandidateFailureAttribution $case $message $id
            if ([string]::IsNullOrWhiteSpace($attribution)) {
                throw "Static test $id failed without the stable candidate marker; " +
                    "its NUnit stack also contains no candidate Assets source frame; " +
                    "treating it as an evaluator or infrastructure error. Message: $message"
            }
            $candidateFailures.Add([pscustomobject]@{
                id = $id
                message = $message
                attribution = $attribution
                stack_trace = Get-FailureStackTrace $case
            })
        } elseif ($result -ne "Passed") {
            throw "Static test $id returned unsupported result '$result'. " +
                "Skipped, inconclusive, missing, or evaluator-error results are invalid infrastructure."
        }

        $results.Add([pscustomobject]@{
            id = $id
            result = $result
            checkpoint_passed = $result -eq "Passed"
            score = if ($result -eq "Passed") {
                10.0 / [Math]::Max(1, @($rules.phases.static.tests).Count)
            } else { 0.0 }
            maximum_score = 10.0 / [Math]::Max(1, @($rules.phases.static.tests).Count)
            diagnostic_weight = [double]$rule.diagnostic_weight
            message = $message
        })
    }

    [pscustomobject]@{
        candidate_failed = $candidateFailures.Count -gt 0
        candidate_failures = @($candidateFailures)
        tests = @($results)
    }
}

try {
    $baselineRun = Invoke-CandidateCompileBaseline
    if ([string]$baselineRun.execution_status -eq "infrastructure_error") {
        throw "Candidate baseline compile failed as evaluation infrastructure. " +
            "See log: $($baselineRun.log)"
    }
    if ([string]$baselineRun.failure_kind -eq "candidate_compilation_error" -and
        @($baselineRun.compiler_errors).Count -gt 0) {
        $candidateFailure = [pscustomobject]@{
            kind = [string]$baselineRun.failure_kind
            reason = [string]$baselineRun.failure_reason
            attribution = "confirmed_without_evaluator_injection"
            compiler_errors = @($baselineRun.compiler_errors)
            log = [string]$baselineRun.log
        }
        Complete-StaticCandidateFailure `
            $null $baselineRun $candidateFailure @()
        exit 0
    }
    if ([string]$baselineRun.failure_kind -eq "candidate_input_api_mismatch") {
        $candidateFailure = [pscustomobject]@{
            kind = [string]$baselineRun.failure_kind
            reason = [string]$baselineRun.failure_reason
            attribution = "corroborated_log_project_setting_and_candidate_source"
            compiler_errors = @()
            input_system_mismatch_evidence =
                $baselineRun.input_system_mismatch_evidence
            log = [string]$baselineRun.log
        }
        Complete-StaticCandidateFailure `
            $null $baselineRun $candidateFailure @()
        exit 0
    }
    if ([string]$baselineRun.execution_status -ne "passed") {
        throw "Candidate baseline compile returned an unsupported result: " +
            "$($baselineRun.execution_status)/$($baselineRun.failure_kind). " +
            "See log: $($baselineRun.log)"
    }

    $staticRun = Invoke-EvaluationPhase "Static"
    Assert-PhaseInfrastructureHealthy $staticRun
    if ([string]$staticRun.failure_kind -eq "candidate_input_api_mismatch") {
        $candidateFailure = [pscustomobject]@{
            kind = [string]$staticRun.failure_kind
            reason = [string]$staticRun.failure_reason
            attribution = "corroborated_log_project_setting_and_candidate_source"
            compiler_errors = @()
            input_system_mismatch_evidence =
                $staticRun.input_system_mismatch_evidence
            log = [string]$staticRun.log
        }
        Complete-StaticCandidateFailure `
            $staticRun $baselineRun $candidateFailure @()
        exit 0
    }
    if ([string]$staticRun.failure_kind -eq "candidate_compilation_error" -and
        @($staticRun.compiler_errors).Count -gt 0) {
        throw "Static evaluator injection produced compiler errors under candidate Assets, " +
            "but the same project compiled before evaluator injection. This is an evaluator " +
            "overlay/injection infrastructure failure, not a valid candidate score of zero. " +
            "Injected log: $($staticRun.log); baseline log: $($baselineRun.log)"
    }

    $staticDisposition = Get-StaticTestDisposition $staticRun
    if ([bool]$staticDisposition.candidate_failed) {
        $candidateFailure = [pscustomobject]@{
            kind = "static_playability_failure"
            reason = (@($staticDisposition.candidate_failures) | ForEach-Object {
                "$($_.id) [$($_.attribution)]: $($_.message)"
            }) -join " | "
            attribution = (@($staticDisposition.candidate_failures) |
                ForEach-Object { [string]$_.attribution } |
                Sort-Object -Unique) -join "+"
            compiler_errors = @()
            log = [string]$staticRun.log
        }
        Complete-StaticCandidateFailure `
            $staticRun $baselineRun $candidateFailure @($staticDisposition.tests)
        exit 0
    }

    if ([string]$staticRun.execution_status -ne "passed") {
        throw "Static tests all passed but Unity phase status was " +
            "$($staticRun.execution_status)/$($staticRun.failure_kind). " +
            "See log: $($staticRun.log)"
    }

    $dynamicRun = Invoke-EvaluationPhase "Dynamic"
    Assert-PhaseInfrastructureHealthy $dynamicRun
    if ([string]$dynamicRun.failure_kind -eq "candidate_compilation_error") {
        throw "Dynamic evaluator injection produced compiler errors after the clean baseline compile. " +
            "This is evaluator infrastructure, not candidate gameplay. See log: $($dynamicRun.log)"
    }
    Assert-EvaluatorHealthArtifacts $dynamicRun

    $freshRun = Invoke-EvaluationPhase "Fresh" ([int]$dynamicRun.process_id)
    Assert-PhaseInfrastructureHealthy $freshRun
    if ([string]$freshRun.failure_kind -eq "candidate_compilation_error") {
        throw "Fresh evaluator injection produced compiler errors after the clean baseline compile. " +
            "This is evaluator infrastructure, not candidate gameplay. See log: $($freshRun.log)"
    }
    Assert-EvaluatorHealthArtifacts $freshRun
    if ([int]$dynamicRun.process_id -le 0 -or [int]$freshRun.process_id -le 0 -or
        [int]$dynamicRun.process_id -eq [int]$freshRun.process_id) {
        throw "invalid_evaluator_health: Dynamic and Fresh did not expose distinct Unity process IDs."
    }
    $scorePath = Join-Path $OutputDirectory "score.json"
    $scoreArguments = @{
        StaticResultPath = [string]$staticRun.result
        DynamicResultPath = [string]$dynamicRun.result
        EvidenceDirectory = [string]$dynamicRun.evidence
        ProjectPath = $ProjectPath
        StaticExitCode = [int]$staticRun.exit_code
        DynamicExitCode = [int]$dynamicRun.exit_code
        FreshResultPath = [string]$freshRun.result
        FreshEvidenceDirectory = [string]$freshRun.evidence
        FreshExitCode = [int]$freshRun.exit_code
        DynamicProcessId = [int]$dynamicRun.process_id
        FreshProcessId = [int]$freshRun.process_id
        OutputPath = $scorePath
        NoExitOnInvalid = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($VisualScorePath)) {
        $scoreArguments.VisualScorePath = $VisualScorePath
    }
    $scoreRaw = & (Join-Path $PSScriptRoot "score-evaluation.ps1") @scoreArguments
    $score = (($scoreRaw -join [Environment]::NewLine) | ConvertFrom-Json)

    [pscustomobject]@{
        project_path = $ProjectPath
        run_directory = $OutputDirectory
        valid_score = [bool]$score.valid_score
        score = $score.score
        score_status = $score.score_status
        automated_score = $score.automated_score
        maximum_score = $score.maximum_score
        candidate_status = $score.candidate_status
        static = $staticRun
        dynamic = $dynamicRun
        fresh = $freshRun
        score_report = $scorePath
    } | ConvertTo-Json -Depth 8

    if (-not [bool]$score.valid_score) {
        exit 3
    }
    exit 0
}
catch {
    $errorPath = Join-Path $OutputDirectory "infrastructure-error.json"
    $healthInvalid = $_.Exception.Message -match 'invalid_evaluator_health|evaluator.health'
    $failure = [pscustomobject]@{
        project_path = $ProjectPath
        run_directory = $OutputDirectory
        valid_score = $false
        candidate_status = if ($healthInvalid) { "invalid_evaluator_health" } else { "invalid" }
        error = $_.Exception.Message
        stack = $_.ScriptStackTrace
    }
    $json = $failure | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText(
        $errorPath,
        $json,
        [System.Text.UTF8Encoding]::new($false))
    $json
    exit 3
}
