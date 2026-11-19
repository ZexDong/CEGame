[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [string]$UnityEditorPath=$env:UNITY_EDITOR,

    [string]$UnityCliPath=$env:UNITY_CLI,

    [string]$OutputDirectory = "",

    [string]$PhaseRunnerPath = "",

    [string]$BaselineRunnerPath = "",

    [string]$ScorerPath = "",

    [string]$VisualScorePath = ""
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
if ([string]::IsNullOrWhiteSpace($ScorerPath)) {
    $ScorerPath = Join-Path $PSScriptRoot "score-evaluation.ps1"
}
$ScorerPath = (Resolve-Path -LiteralPath $ScorerPath).Path
$sourceBindingHelperPath = (Resolve-Path -LiteralPath (
    Join-Path $PSScriptRoot "get-current-source-binding.ps1")).Path
. $sourceBindingHelperPath
$currentSourceBinding = $null
$persistenceHelperPath = (Resolve-Path -LiteralPath (
    Join-Path $PSScriptRoot "unity-persistence-scope.ps1")).Path
. $persistenceHelperPath
$persistenceScope = $null
$persistenceEvents = [System.Collections.Generic.List[object]]::new()

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $projectName = Split-Path -Leaf $ProjectPath
    $safeProjectName = $projectName -replace '[^A-Za-z0-9._-]', '_'
    $runId = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss-fff")
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $evaluationRoot "..\..\.."))
    $OutputDirectory = Join-Path $repositoryRoot `
        "tmp\arrow-evaluation-$runId-$safeProjectName"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$script:d6InputManifest = ""
$script:visualCaptureValidation = ""

function Get-ArrowEscapePngSize([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ valid = $false; width = 0; height = 0 }
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 24 -or
        $bytes[0] -ne 0x89 -or $bytes[1] -ne 0x50 -or
        $bytes[2] -ne 0x4e -or $bytes[3] -ne 0x47 -or
        $bytes[4] -ne 0x0d -or $bytes[5] -ne 0x0a -or
        $bytes[6] -ne 0x1a -or $bytes[7] -ne 0x0a) {
        return [pscustomobject]@{ valid = $false; width = 0; height = 0 }
    }
    $width = ([int]$bytes[16] -shl 24) -bor
        ([int]$bytes[17] -shl 16) -bor
        ([int]$bytes[18] -shl 8) -bor [int]$bytes[19]
    $height = ([int]$bytes[20] -shl 24) -bor
        ([int]$bytes[21] -shl 16) -bor
        ([int]$bytes[22] -shl 8) -bor [int]$bytes[23]
    return [pscustomobject]@{
        valid = $width -gt 0 -and $height -gt 0
        width = $width
        height = $height
    }
}

function Write-ArrowEscapeD6Artifacts([string]$EvidenceDirectory = "") {
    $visualRoot = Join-Path $OutputDirectory 'visual'
    $candidateRoot = Join-Path $OutputDirectory 'visual-candidates'
    New-Item -ItemType Directory -Path $visualRoot, $candidateRoot -Force |
        Out-Null

    $referenceManifestPath = Join-Path $evaluationRoot `
        'visual\reference-manifest.json'
    $referenceManifest = Get-Content -Raw -Encoding UTF8 `
        -LiteralPath $referenceManifestPath | ConvertFrom-Json
    $stateId = 'initial_gameplay'
    $referenceState = @($referenceManifest.states | Where-Object {
            [string]$_.id -ceq $stateId
        }) | Select-Object -First 1
    $referencePath = if ($null -eq $referenceState) { "" } else {
        [IO.Path]::GetFullPath((Join-Path (Join-Path $evaluationRoot 'visual') `
            ([string]$referenceState.reference)))
    }
    $referenceExists = -not [string]::IsNullOrWhiteSpace($referencePath) -and
        (Test-Path -LiteralPath $referencePath -PathType Leaf)
    $referenceHash = if ($referenceExists) {
        (Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    } else { "" }
    $referenceReady = [bool]$referenceManifest.formal_reference_ready -and
        [string]$referenceManifest.protocol -ceq
            'user-simplified-single-state-single-round-20260824' -and
        [int]$referenceManifest.required_rounds -eq 1 -and
        [string]$referenceManifest.primary_state_id -ceq $stateId -and
        @($referenceManifest.states).Count -eq 1 -and
        $referenceExists -and
        [string]$referenceState.sha256 -ceq $referenceHash

    $sourceVisual = if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
        ""
    } else { Join-Path $EvidenceDirectory 'visual' }
    $sourceCandidate = if ([string]::IsNullOrWhiteSpace($sourceVisual)) { "" } else {
        Join-Path $sourceVisual ($stateId + '.png')
    }
    $sourceReceipt = if ([string]::IsNullOrWhiteSpace($sourceCandidate)) { "" } else {
        $sourceCandidate + '.receipt.json'
    }
    $candidatePath = Join-Path $candidateRoot ($stateId + '.png')
    if (-not [string]::IsNullOrWhiteSpace($sourceCandidate) -and
        (Test-Path -LiteralPath $sourceCandidate -PathType Leaf)) {
        Copy-Item -LiteralPath $sourceCandidate -Destination $candidatePath -Force
    }

    $candidateExists = Test-Path -LiteralPath $candidatePath -PathType Leaf
    $png = Get-ArrowEscapePngSize $candidatePath
    $candidateBytes = if ($candidateExists) {
        [long](Get-Item -LiteralPath $candidatePath).Length
    } else { 0L }
    $candidateHash = if ($candidateExists) {
        (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant()
    } else { "" }
    $receiptPresent = -not [string]::IsNullOrWhiteSpace($sourceReceipt) -and
        (Test-Path -LiteralPath $sourceReceipt -PathType Leaf)
    $receipt = $null
    if ($receiptPresent) {
        try {
            $receipt = Get-Content -Raw -Encoding UTF8 -LiteralPath $sourceReceipt |
                ConvertFrom-Json
        }
        catch { $receipt = $null }
    }
    $receiptMatchesFile = $null -ne $receipt -and
        [string]$receipt.state_id -ceq $stateId -and
        [string]$receipt.status -ceq 'captured' -and
        [string]$receipt.file -ceq ($stateId + '.png') -and
        [int]$receipt.width -eq 1280 -and [int]$receipt.height -eq 720 -and
        [long]$receipt.bytes -eq $candidateBytes -and
        [string]$receipt.sha256 -ceq $candidateHash
    $captureValid = $candidateExists -and [bool]$png.valid -and
        [int]$png.width -eq 1280 -and [int]$png.height -eq 720 -and
        $receiptPresent -and $receiptMatchesFile
    $captureState = [ordered]@{
        id = $stateId
        file = Split-Path -Leaf $candidatePath
        valid = [bool]$captureValid
        status = if ($captureValid) { 'captured' } elseif (-not $candidateExists) {
            'missing'
        } else { 'invalid' }
        width = [int]$png.width
        height = [int]$png.height
        bytes = $candidateBytes
        sha256 = $candidateHash
        receipt_present = [bool]$receiptPresent
        receipt_matches_file = [bool]$receiptMatchesFile
        source_capture = $sourceCandidate
        source_receipt = $sourceReceipt
        process_id = if ($null -eq $receipt) { 0 } else { [int]$receipt.process_id }
        frame = if ($null -eq $receipt) { 0 } else { [int]$receipt.frame }
        captured_utc = if ($null -eq $receipt) { $null } else {
            [string]$receipt.captured_utc
        }
    }
    $captureValidationPath = Join-Path $visualRoot 'capture-validation.json'
    $captureValidation = [ordered]@{
        schema_version = 1
        valid = [bool]$captureValid
        required_resolution = @(1280, 720)
        states = @($captureState)
    }
    [IO.File]::WriteAllText($captureValidationPath,
        ($captureValidation | ConvertTo-Json -Depth 20),
        [Text.UTF8Encoding]::new($false))

    $diagnosticInventory = [System.Collections.Generic.List[object]]::new()
    foreach ($diagnostic in @($referenceManifest.diagnostic_inventory)) {
        $diagnosticId = [string]$diagnostic.id
        $candidateSource = if ([string]::IsNullOrWhiteSpace($sourceVisual)) { "" } else {
            Join-Path $sourceVisual ($diagnosticId + '.png')
        }
        $candidateDiagnostic = Join-Path $candidateRoot ($diagnosticId + '.png')
        if (-not [string]::IsNullOrWhiteSpace($candidateSource) -and
            (Test-Path -LiteralPath $candidateSource -PathType Leaf)) {
            Copy-Item -LiteralPath $candidateSource -Destination $candidateDiagnostic -Force
        }
        $diagnosticReference = [IO.Path]::GetFullPath((Join-Path `
            (Join-Path $evaluationRoot 'visual') ([string]$diagnostic.reference)))
        $diagnosticInventory.Add([ordered]@{
            id = $diagnosticId
            label = [string]$diagnostic.label
            role = 'diagnostic_inventory_only'
            excluded_from_formal_d6 = $true
            reference = $diagnosticReference
            candidate = $candidateDiagnostic
            candidate_exists = Test-Path -LiteralPath $candidateDiagnostic -PathType Leaf
            candidate_sha256 = if (Test-Path -LiteralPath $candidateDiagnostic -PathType Leaf) {
                (Get-FileHash -LiteralPath $candidateDiagnostic -Algorithm SHA256).Hash.ToLowerInvariant()
            } else { "" }
        })
    }

    $manifestPath = Join-Path $visualRoot 'd6-input.json'
    $manifest = [ordered]@{
        schema_version = 2
        benchmark_id = 'unity.arrow_escape_reconstruction.v2'
        protocol = 'user-simplified-single-state-single-round-20260824'
        formal_reference_ready = [bool]$referenceReady
        required_rounds = 1
        primary_state_id = $stateId
        manifest_role = 'native formal single-state D6 input'
        visual_evaluator = [ordered]@{
            model = 'gpt-5.6-sol'
            rounds = 1
            prompt_sha256 =
                '558b4ccffad7d13d3ae3e5c6fc5a9b36a7bba37d9be47da895c2e50bc9c5a6ee'
        }
        capture_validation = $captureValidationPath
        states = @([ordered]@{
            id = $stateId
            label = [string]$referenceState.label
            reference = $referencePath
            candidate = $candidatePath
        })
        diagnostic_inventory = @($diagnosticInventory)
    }
    [IO.File]::WriteAllText($manifestPath,
        ($manifest | ConvertTo-Json -Depth 30),
        [Text.UTF8Encoding]::new($false))

    $script:d6InputManifest = $manifestPath
    $script:visualCaptureValidation = $captureValidationPath
    return [pscustomobject]@{
        manifest = $manifestPath
        validation = $captureValidationPath
        capture_valid = [bool]$captureValid
        reference_ready = [bool]$referenceReady
    }
}

function Add-D6ArtifactsToJsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $document = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path |
        ConvertFrom-Json
    $document | Add-Member -MemberType NoteProperty `
        -Name d6_input_manifest -Value $script:d6InputManifest -Force
    $document | Add-Member -MemberType NoteProperty `
        -Name visual_capture_validation -Value $script:visualCaptureValidation -Force
    [IO.File]::WriteAllText($Path,
        ($document | ConvertTo-Json -Depth 100),
        [Text.UTF8Encoding]::new($false))
}

function Invoke-EvaluationPhase([string]$Phase, [string]$FreshSeedPath = "") {
    $phaseDirectory = Join-Path $OutputDirectory $Phase.ToLowerInvariant()
    New-Item -ItemType Directory -Path $phaseDirectory -Force | Out-Null
    $phaseArguments = @{
        ProjectPath = $ProjectPath
        Phase = $Phase
        UnityEditorPath = $UnityEditorPath
        UnityCliPath = $UnityCliPath
        OutputDirectory = $phaseDirectory
        NoExitOnCompletion = $true
    }
    if ($Phase -eq "Fresh") {
        $phaseArguments.FreshSeedPath = $FreshSeedPath
        $phaseArguments.FreshOutputDirectory = Join-Path $phaseDirectory "fresh-evidence"
    }
    $raw = & $PhaseRunnerPath @phaseArguments
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

function Get-PersistenceRunSummary {
    $failedEvents = @($persistenceEvents | Where-Object {
        -not [bool]$_.verified
    })
    $expectedBoundaries = @(
        'Baseline/Pre', 'Baseline/Post',
        'Static/Pre', 'Static/Post',
        'Dynamic/Pre', 'Dynamic/Post',
        'Fresh/Pre', 'Fresh/Post')
    $completedBoundaries = @($persistenceEvents | ForEach-Object {
        "$([string]$_.phase)/$([string]$_.boundary)"
    })
    $sequenceVerified = $completedBoundaries.Count -eq $expectedBoundaries.Count
    if ($sequenceVerified) {
        for ($index = 0; $index -lt $expectedBoundaries.Count; $index++) {
            if ($completedBoundaries[$index] -cne $expectedBoundaries[$index]) {
                $sequenceVerified = $false
                break
            }
        }
    }
    return [pscustomobject]@{
        schema_version = 1
        policy = 'exact_company_product_scope_before_and_after_each_unity_phase'
        scope = $persistenceScope
        expected_phase_sequence = @('Baseline', 'Static', 'Dynamic', 'Fresh')
        expected_boundary_count = 8
        completed_boundary_count = $persistenceEvents.Count
        failed_boundary_count = $failedEvents.Count
        all_recorded_boundaries_verified = $failedEvents.Count -eq 0
        boundary_sequence_verified = $sequenceVerified
        all_completed_boundaries_verified =
            $sequenceVerified -and $failedEvents.Count -eq 0
        events = @($persistenceEvents)
    }
}

function Add-PersistenceSummaryToJsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $document = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path |
        ConvertFrom-Json
    $document | Add-Member -MemberType NoteProperty `
        -Name unity_persistence_cleanup `
        -Value (Get-PersistenceRunSummary) -Force
    [IO.File]::WriteAllText(
        $Path,
        ($document | ConvertTo-Json -Depth 100),
        [Text.UTF8Encoding]::new($false))
}

function Invoke-PersistenceBoundary([string]$Phase, [string]$Boundary) {
    $event = Invoke-ArrowEscapeUnityPersistenceCleanup `
        -Scope $persistenceScope `
        -Phase $Phase `
        -Boundary $Boundary
    $persistenceEvents.Add($event)
    if (-not [bool]$event.verified) {
        throw "Unity persistence cleanup failed at $Phase/$Boundary. " +
            "$(@($event.errors) -join ' | ')"
    }
}

function Invoke-PersistenceBoundPhase([string]$Phase, [string]$FreshSeedPath = '') {
    Invoke-PersistenceBoundary $Phase 'Pre'
    $phaseRun = $null
    $phaseError = $null
    try { $phaseRun = Invoke-EvaluationPhase $Phase $FreshSeedPath }
    catch { $phaseError = $_ }

    $postError = $null
    try { Invoke-PersistenceBoundary $Phase 'Post' }
    catch { $postError = $_ }
    if ($null -ne $phaseError) { throw $phaseError }
    if ($null -ne $postError) { throw $postError }
    return $phaseRun
}

function Invoke-PersistenceBoundBaseline {
    Invoke-PersistenceBoundary 'Baseline' 'Pre'
    $baseline = $null
    $baselineError = $null
    try { $baseline = Invoke-CandidateCompileBaseline }
    catch { $baselineError = $_ }

    $postError = $null
    try { Invoke-PersistenceBoundary 'Baseline' 'Post' }
    catch { $postError = $_ }
    if ($null -ne $baselineError) { throw $baselineError }
    if ($null -ne $postError) { throw $postError }
    return $baseline
}

function Assert-PhaseInfrastructureHealthy($PhaseRun) {
    if ([string]$PhaseRun.execution_status -eq "infrastructure_error") {
        if ([string]$PhaseRun.failure_kind -eq "evaluator_health_failure") {
            throw "invalid_evaluator_health: $($PhaseRun.phase) evaluator health " +
                "prerequisites failed. $(@($PhaseRun.health_validation_reasons) -join ' | ') " +
                "See log: $($PhaseRun.log)"
        }
        throw "$($PhaseRun.phase) evaluation infrastructure failed with Unity exit code " +
            "$($PhaseRun.exit_code). See log: $($PhaseRun.log)"
    }
    $resultPath = [string]$PhaseRun.result
    $resultExists = -not [string]::IsNullOrWhiteSpace($resultPath) -and
        (Test-Path -LiteralPath $resultPath -PathType Leaf)
    if (-not $resultExists) {
        $attributableCompilerFailure =
            [string]$PhaseRun.execution_status -eq "candidate_failed" -and
            [string]$PhaseRun.failure_kind -eq "candidate_compilation_error" -and
            @($PhaseRun.compiler_errors).Count -gt 0
        if ($attributableCompilerFailure) {
            return
        }
        throw "$($PhaseRun.phase) evaluation produced no NUnit result XML. " +
            "See log: $($PhaseRun.log)"
    }
}

function Complete-StaticCandidateFailure(
    $StaticRun,
    $BaselineRun,
    $CandidateFailure,
    $StaticTests
) {
    $rulesPath = Join-Path $evaluationRoot "rules.json"
    $rules = Get-Content -Raw -Encoding UTF8 -LiteralPath $rulesPath | ConvertFrom-Json
    Write-ArrowEscapeD6Artifacts | Out-Null
    $scorePath = Join-Path $OutputDirectory "score.json"
    $staticTests = @($StaticTests)
    $baselinePassed = [string]$BaselineRun.execution_status -eq "passed"
    $staticPassMap = @{}
    foreach ($test in $staticTests) {
        $staticPassMap[[string]$test.id] = [bool]$test.passed
    }

    $d1Definition = @($rules.dimensions | Where-Object { $_.id -eq "D1" }) |
        Select-Object -First 1
    $d1Checkpoints = foreach ($checkpoint in @($d1Definition.checkpoints)) {
        $type = [string]$checkpoint.source.type
        $passed = if ($type -eq "baseline_compile") {
            $baselinePassed
        } elseif ($type -eq "static_test") {
            $id = [string]$checkpoint.source.id
            $staticPassMap.ContainsKey($id) -and [bool]$staticPassMap[$id]
        } else {
            $false
        }
        [pscustomobject]@{
            id = [string]$checkpoint.id
            title = [string]$checkpoint.title
            status = if ($passed) { "pass" } else { "fail" }
            passed = [bool]$passed
            source_type = $type
        }
    }
    $d1Passed = @($d1Checkpoints | Where-Object { $_.passed }).Count
    $d1Score = [Math]::Round(10.0 * $d1Passed / 4.0, 1,
        [MidpointRounding]::AwayFromZero)
    $dimensions = [System.Collections.Generic.List[object]]::new()
    $dimensions.Add([pscustomobject]@{
        id = "D1"
        title = [string]$d1Definition.title
        stage = "static"
        status = "evaluated"
        score = $d1Score
        maximum_score = 10.0
        passed_checkpoints = $d1Passed
        total_checkpoints = 4
        checkpoints = @($d1Checkpoints)
    })
    foreach ($id in @("D2", "D3", "D4", "D5")) {
        $definition = @($rules.dimensions | Where-Object { $_.id -eq $id }) |
            Select-Object -First 1
        $dimensions.Add([pscustomobject]@{
            id = $id
            title = [string]$definition.title
            stage = [string]$definition.stage
            status = "not_reached"
            score = 0.0
            maximum_score = [double]$definition.maximum_score
            passed_checkpoints = 0
            total_checkpoints = @($definition.checkpoints).Count
            checkpoints = @()
        })
    }
    $dimensions.Add([pscustomobject]@{
        id = "D6"
        title = "Visual Assembly & Presentation Fidelity"
        stage = "visual"
        status = "pending"
        score = $null
        maximum_score = 10.0
        rounds = @()
        states = @()
        prompt = Join-Path $evaluationRoot "visual\visual_prompt.txt"
        reference_manifest = Join-Path $evaluationRoot "visual\reference-manifest.json"
    })

    $report = [pscustomobject]@{
        schema_version = 2
        evaluator_protocol = [string]$rules.evaluator_protocol
        evaluator_revision = [string]$rules.evaluator_revision
        generated_utc = [DateTime]::UtcNow.ToString("o")
        project_path = $ProjectPath
        valid_score = $true
        candidate_status = "not_executable"
        validation_reasons = @()
        score = $null
        maximum_score = 100.0
        automatic_score = $d1Score
        automatic_maximum_score = 90.0
        d6_status = "pending"
        executable = $false
        launch_gate_passed = $false
        solved = $false
        package_valid = $null
        source_binding = $currentSourceBinding
        dimensions = @($dimensions)
        overall = [pscustomobject]@{
            status = "pending_d6"
            score = $null
            maximum_score = 100.0
            automatic_score = $d1Score
            automatic_maximum_score = 90.0
        }
        candidate_failure = [pscustomobject]@{
            kind = [string]$CandidateFailure.kind
            reason = [string]$CandidateFailure.reason
            attribution = [string]$CandidateFailure.attribution
            compiler_errors = @($CandidateFailure.compiler_errors)
            log = [string]$CandidateFailure.log
            baseline_compile = $BaselineRun
        }
        phases = [pscustomobject]@{
            static = [pscustomobject]@{
                maximum_score = 10.0
                full_pass = $false
                launch_gate_passed = $false
                launch_gate_test_ids = @($rules.phases.static.launch_gate_test_ids)
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
                result_xml = if ($null -ne $StaticRun) { [string]$StaticRun.result } else { $null }
                log = [string]$CandidateFailure.log
                tests = @($staticTests)
            }
            dynamic = [pscustomobject]@{
                maximum_score = 80.0
                skipped = $true
                skip_reason = "The baseline launch/render gate did not pass; dynamic player trajectories were not safe to run."
                trajectories = @()
            }
            fresh = [pscustomobject]@{
                skipped = $true
                skip_reason = "The baseline launch/render gate did not pass; the post-Dynamic Fresh protocol was not reachable."
            }
            visual = [pscustomobject]@{
                maximum_score = 10.0
                status = "pending"
            }
        }
        legacy_diagnostics = [pscustomobject]@{
            note = "Dynamic legacy milestones were not run after the baseline launch/render gate failure."
        }
        artifacts = [pscustomobject]@{
            rules = $rulesPath
            trajectory_definitions = Join-Path $evaluationRoot `
                "package\Tests\Dynamic\Resources\TrajectoryDefinitions"
            visual_prompt = Join-Path $evaluationRoot "visual\visual_prompt.txt"
            reference_manifest = Join-Path $evaluationRoot "visual\reference-manifest.json"
        }
    }
    $scoreJson = $report | ConvertTo-Json -Depth 16
    [System.IO.File]::WriteAllText($scorePath, $scoreJson,
        [System.Text.UTF8Encoding]::new($false))

    [pscustomobject]@{
        project_path = $ProjectPath
        run_directory = $OutputDirectory
        valid_score = $true
        score = $null
        automatic_score = $d1Score
        maximum_score = 100.0
        candidate_status = "not_executable"
        static = if ($null -ne $StaticRun) { $StaticRun } else { $BaselineRun }
        baseline_compile = $BaselineRun
        dynamic = [pscustomobject]@{
            execution_status = "skipped"
            skip_reason = "Baseline launch/render gate failed."
        }
        unity_persistence_cleanup = Get-PersistenceRunSummary
        d6_status = "pending"
        d6_input_manifest = $script:d6InputManifest
        visual_capture_validation = $script:visualCaptureValidation
        score_report = $scorePath
    } | ConvertTo-Json -Depth 10
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

function Complete-StaticEvaluatorUnsupported(
    $StaticRun,
    $BaselineRun,
    $UnsupportedFailures,
    $StaticTests
) {
    $rulesPath = Join-Path $evaluationRoot "rules.json"
    $rules = Get-Content -Raw -Encoding UTF8 -LiteralPath $rulesPath |
        ConvertFrom-Json
    $scorePath = Join-Path $OutputDirectory "score.json"
    $staticTests = @($StaticTests)
    $unsupportedFailures = @($UnsupportedFailures)
    $reason = ($unsupportedFailures | ForEach-Object {
        "$($_.id): $($_.message)"
    }) -join " | "

    $dimensions = @($rules.dimensions | ForEach-Object {
        [pscustomobject]@{
            id = [string]$_.id
            title = [string]$_.title
            stage = [string]$_.stage
            status = "not_evaluated"
            score = $null
            maximum_score = [double]$_.maximum_score
            passed_checkpoints = 0
            total_checkpoints = @($_.checkpoints).Count
            checkpoints = @()
        }
    })

    $report = [pscustomobject]@{
        schema_version = 2
        evaluator_protocol = [string]$rules.evaluator_protocol
        evaluator_revision = [string]$rules.evaluator_revision
        generated_utc = [DateTime]::UtcNow.ToString("o")
        project_path = $ProjectPath
        valid_score = $false
        candidate_status = "evaluator_unsupported"
        validation_reasons = @(
            "evaluator_unsupported: $reason"
        )
        score = $null
        maximum_score = 100.0
        automatic_score = $null
        automatic_maximum_score = 90.0
        d6_status = "not_evaluated"
        # The candidate compiled and entered Play, but this evaluator cannot
        # establish the architecture-independent render/input facts needed to
        # publish D1. Do not misstate that coverage gap as candidate
        # non-executability.
        executable = $null
        launch_gate_passed = $null
        solved = $false
        package_valid = $null
        source_binding = $currentSourceBinding
        dimensions = @($dimensions)
        overall = [pscustomobject]@{
            status = "evaluator_unsupported"
            score = $null
            maximum_score = 100.0
            automatic_score = $null
            automatic_maximum_score = 90.0
        }
        evaluator_failure = [pscustomobject]@{
            kind = "unsupported_candidate_presentation_input_architecture"
            reason = $reason
            attribution = "stable_evaluator_unsupported_marker_in_static_evaluator"
            unsupported_tests = @($unsupportedFailures)
            log = [string]$StaticRun.log
            baseline_compile = $BaselineRun
        }
        phases = [pscustomobject]@{
            static = [pscustomobject]@{
                maximum_score = 10.0
                full_pass = $false
                launch_gate_passed = $null
                launch_gate_test_ids = @($rules.phases.static.launch_gate_test_ids)
                unity_exit_code = [int]$StaticRun.exit_code
                execution_status = "evaluator_unsupported"
                unity_test_execution_status = [string]$StaticRun.execution_status
                result_xml = [string]$StaticRun.result
                log = [string]$StaticRun.log
                tests = @($staticTests)
            }
            dynamic = [pscustomobject]@{
                maximum_score = 80.0
                skipped = $true
                skip_reason = "Evaluator coverage does not support the detected candidate presentation/input architecture."
                trajectories = @()
            }
            fresh = [pscustomobject]@{
                skipped = $true
                skip_reason = "Dynamic evaluation was not valid to run for an evaluator-unsupported candidate architecture."
            }
            visual = [pscustomobject]@{
                maximum_score = 10.0
                status = "not_evaluated"
            }
        }
        artifacts = [pscustomobject]@{
            rules = $rulesPath
            trajectory_definitions = Join-Path $evaluationRoot `
                "package\Tests\Dynamic\Resources\TrajectoryDefinitions"
            visual_prompt = Join-Path $evaluationRoot "visual\visual_prompt.txt"
            reference_manifest = Join-Path $evaluationRoot "visual\reference-manifest.json"
            d6_input_manifest = $script:d6InputManifest
            visual_capture_validation = $script:visualCaptureValidation
        }
    }
    $scoreJson = $report | ConvertTo-Json -Depth 16
    [System.IO.File]::WriteAllText($scorePath, $scoreJson,
        [System.Text.UTF8Encoding]::new($false))

    [pscustomobject]@{
        project_path = $ProjectPath
        run_directory = $OutputDirectory
        valid_score = $false
        score = $null
        automatic_score = $null
        maximum_score = 100.0
        candidate_status = "evaluator_unsupported"
        static = [pscustomobject]@{
            execution_status = "evaluator_unsupported"
            unity_test_execution_status = [string]$StaticRun.execution_status
            exit_code = [int]$StaticRun.exit_code
            result = [string]$StaticRun.result
            log = [string]$StaticRun.log
        }
        baseline_compile = $BaselineRun
        dynamic = [pscustomobject]@{
            execution_status = "skipped"
            skip_reason = "Evaluator coverage does not support the detected candidate architecture."
        }
        unity_persistence_cleanup = Get-PersistenceRunSummary
        d6_status = "not_evaluated"
        score_report = $scorePath
    } | ConvertTo-Json -Depth 10
}

function Get-StaticTestDisposition($StaticRun) {
    $candidateMarker = "[OMNIGAME_CANDIDATE_STATIC]"
    $unsupportedMarker = "[OMNIGAME_EVALUATOR_UNSUPPORTED]"
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

    # NUnit parents can be Failed with label=Child when one descendant failed.
    # Only leaf cases carry the real assertion/setup attribution.
    $cases = @($document.SelectNodes(
        "//test-case[not(descendant::test-case)]"))
    $results = [System.Collections.Generic.List[object]]::new()
    $candidateFailures = [System.Collections.Generic.List[object]]::new()
    $unsupportedFailures = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in @($rules.phases.static.tests)) {
        $id = [string]$rule.id
        $matches = @($cases | Where-Object {
            (Get-XmlAttributeValue $_ "methodname") -eq $id -or
            (Get-XmlAttributeValue $_ "name") -eq $id
        })
        if ($matches.Count -ne 1) {
            throw "Expected exactly one Static test case $id, found $($matches.Count)."
        }
        $case = $matches[0]
        $result = Get-XmlAttributeValue $case "result"
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
            if ($message.Contains($unsupportedMarker)) {
                $unsupportedFailures.Add([pscustomobject]@{
                    id = $id
                    message = $message
                })
            } elseif (-not $message.Contains($candidateMarker)) {
                throw "Static test $id failed without the stable candidate marker; " +
                    "treating it as an evaluator or infrastructure error. Message: $message"
            } else {
                $candidateFailures.Add([pscustomobject]@{
                    id = $id
                    message = $message
                })
            }
        } elseif ($result -ne "Passed") {
            throw "Static test $id returned unsupported result '$result'. " +
                "Skipped, inconclusive, missing, or evaluator-error results are invalid infrastructure."
        }

        $results.Add([pscustomobject]@{
            id = $id
            result = $result
            passed = $result -eq "Passed"
            message = $message
        })
    }

    foreach ($regressionCase in @($cases | Where-Object {
        (Get-XmlAttributeValue $_ "methodname").StartsWith(
            "EVALUATOR_REGRESSION_", [StringComparison]::Ordinal) -or
        (Get-XmlAttributeValue $_ "name").StartsWith(
            "EVALUATOR_REGRESSION_", [StringComparison]::Ordinal)
    })) {
        if ((Get-XmlAttributeValue $regressionCase "result") -ne "Passed") {
            throw "Static evaluator self-test " +
                "$(Get-XmlAttributeValue $regressionCase 'name') did not pass."
        }
    }

    $launchGateIds = @($rules.phases.static.launch_gate_test_ids |
        ForEach-Object { [string]$_ })
    if ($launchGateIds.Count -eq 0) {
        throw "rules.json does not declare any Static launch-gate tests."
    }
    if (@($launchGateIds | Sort-Object -Unique).Count -ne $launchGateIds.Count) {
        throw "rules.json declares duplicate Static launch-gate test IDs."
    }
    $declaredStaticIds = @($rules.phases.static.tests |
        ForEach-Object { [string]$_.id })
    foreach ($launchGateId in $launchGateIds) {
        if ($declaredStaticIds -notcontains $launchGateId) {
            throw "Static launch-gate test is not declared in phases.static.tests: $launchGateId"
        }
    }
    $launchGateFailures = @($candidateFailures | Where-Object {
        $launchGateIds -contains [string]$_.id
    })

    [pscustomobject]@{
        evaluator_unsupported = $unsupportedFailures.Count -gt 0
        unsupported_failures = @($unsupportedFailures)
        candidate_failed = $candidateFailures.Count -gt 0
        candidate_failures = @($candidateFailures)
        launch_gate_test_ids = @($launchGateIds)
        launch_gate_failed = $launchGateFailures.Count -gt 0
        launch_gate_failures = @($launchGateFailures)
        tests = @($results)
    }
}

$baselineRun = $null
$staticRun = $null
$dynamicRun = $null
$freshRun = $null
try {
    $rulesPath = Join-Path $evaluationRoot "rules.json"
    $currentSourceBinding = Get-ArrowEscapeCurrentSourceBinding `
        $evaluationRoot $rulesPath
    $persistenceScope = New-ArrowEscapeUnityPersistenceScope `
        -ProjectPath $ProjectPath

    # Establish candidate health before evaluator injection.  This makes any
    # later injection-only compilation failure unambiguously infrastructure.
    $baselineRun = Invoke-PersistenceBoundBaseline
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
    if ([string]$baselineRun.execution_status -ne "passed") {
        throw "Candidate baseline compile returned an unsupported result: " +
            "$($baselineRun.execution_status)/$($baselineRun.failure_kind). " +
            "See log: $($baselineRun.log)"
    }

    $staticRun = Invoke-PersistenceBoundPhase "Static"
    Assert-PhaseInfrastructureHealthy $staticRun
    if ([string]$staticRun.failure_kind -eq "candidate_compilation_error" -and
        @($staticRun.compiler_errors).Count -gt 0) {
        throw "Static evaluator injection produced compiler errors under candidate Assets, " +
            "but the same project compiled before evaluator injection. This is an evaluator " +
            "overlay/injection infrastructure failure, not a valid candidate score of zero. " +
            "Injected log: $($staticRun.log); baseline log: $($baselineRun.log)"
    }

    $staticDisposition = Get-StaticTestDisposition $staticRun
    if ([bool]$staticDisposition.evaluator_unsupported) {
        Complete-StaticEvaluatorUnsupported `
            $staticRun $baselineRun `
            @($staticDisposition.unsupported_failures) `
            @($staticDisposition.tests)
        exit 3
    }
    if ([bool]$staticDisposition.launch_gate_failed) {
        $candidateFailure = [pscustomobject]@{
            kind = "static_launch_assertion"
            reason = (@($staticDisposition.launch_gate_failures) | ForEach-Object {
                "$($_.id): $($_.message)"
            }) -join " | "
            attribution = "stable_candidate_marker_in_static_launch_gate"
            compiler_errors = @()
            log = [string]$staticRun.log
        }
        Complete-StaticCandidateFailure `
            $staticRun $baselineRun $candidateFailure @($staticDisposition.tests)
        exit 0
    }

    $softProfileFailure = [bool]$staticDisposition.candidate_failed -and
        -not [bool]$staticDisposition.launch_gate_failed -and
        [string]$staticRun.execution_status -eq "candidate_failed" -and
        [string]$staticRun.failure_kind -eq "test_failure"
    if ([string]$staticRun.execution_status -ne "passed" -and
        -not $softProfileFailure) {
        throw "Static launch tests passed but Unity phase status was " +
            "$($staticRun.execution_status)/$($staticRun.failure_kind). " +
            "See log: $($staticRun.log)"
    }

    $dynamicRun = Invoke-PersistenceBoundPhase "Dynamic"
    Assert-PhaseInfrastructureHealthy $dynamicRun
    Write-ArrowEscapeD6Artifacts -EvidenceDirectory ([string]$dynamicRun.evidence) |
        Out-Null
    $freshSeedPath = Join-Path ([string]$dynamicRun.evidence) "fresh-process-seed.json"
    $freshRun = Invoke-PersistenceBoundPhase "Fresh" $freshSeedPath
    Assert-PhaseInfrastructureHealthy $freshRun
    if ([string]$freshRun.failure_kind -eq "candidate_compilation_error" -and
        @($freshRun.compiler_errors).Count -gt 0) {
        throw "Fresh evaluator injection produced compiler errors after the same candidate " +
            "compiled before evaluator injection. This is invalid evaluator infrastructure, " +
            "not candidate score loss. Fresh log: $($freshRun.log)"
    }
    $sourceBindingAtScore = Get-ArrowEscapeCurrentSourceBinding `
        $evaluationRoot $rulesPath
    if (-not (Test-ArrowEscapeSourceBindingEqual `
            $currentSourceBinding $sourceBindingAtScore)) {
        throw "The canonical full Input/TOOLCHAIN/Prompt binding changed while evaluation was running."
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
        FreshSeedPath = $freshSeedPath
        FreshExitCode = [int]$freshRun.exit_code
        BaselineCompilePassed = $true
        OutputPath = $scorePath
        NoExitOnInvalid = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($VisualScorePath)) {
        $scoreArguments.VisualScorePath = $VisualScorePath
    }
    $scoreRaw = & $ScorerPath @scoreArguments
    $score = (($scoreRaw -join [Environment]::NewLine) | ConvertFrom-Json)
    Add-PersistenceSummaryToJsonFile $scorePath
    Add-D6ArtifactsToJsonFile $scorePath

    [pscustomobject]@{
        project_path = $ProjectPath
        run_directory = $OutputDirectory
        valid_score = [bool]$score.valid_score
        score = $score.score
        automatic_score = $score.automatic_score
        maximum_score = $score.maximum_score
        d6_status = $score.d6_status
        candidate_status = $score.candidate_status
        baseline_compile = $baselineRun
        static = $staticRun
        dynamic = $dynamicRun
        fresh = $freshRun
        unity_persistence_cleanup = Get-PersistenceRunSummary
        d6_input_manifest = $script:d6InputManifest
        visual_capture_validation = $script:visualCaptureValidation
        score_report = $scorePath
    } | ConvertTo-Json -Depth 8

    if (-not [bool]$score.valid_score) {
        exit 3
    }
    exit 0
}
catch {
    $errorPath = Join-Path $OutputDirectory "infrastructure-error.json"
    $failure = [pscustomobject]@{
        project_path = $ProjectPath
        run_directory = $OutputDirectory
        valid_score = $false
        candidate_status = "invalid"
        error = $_.Exception.Message
        stack = $_.ScriptStackTrace
        phases = [pscustomobject]@{
            baseline = $baselineRun
            static = $staticRun
            dynamic = $dynamicRun
            fresh = $freshRun
        }
        unity_persistence_cleanup = Get-PersistenceRunSummary
    }
    $json = $failure | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText(
        $errorPath,
        $json,
        [System.Text.UTF8Encoding]::new($false))
    $json
    exit 3
}
finally {
    $persistenceEvidencePath = Join-Path $OutputDirectory `
        'unity-persistence-cleanup.json'
    [IO.File]::WriteAllText(
        $persistenceEvidencePath,
        ((Get-PersistenceRunSummary) | ConvertTo-Json -Depth 100),
        [Text.UTF8Encoding]::new($false))
    Add-PersistenceSummaryToJsonFile (
        Join-Path $OutputDirectory 'score.json')
    Add-PersistenceSummaryToJsonFile (
        Join-Path $OutputDirectory 'infrastructure-error.json')
}
