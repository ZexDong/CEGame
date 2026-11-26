[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VerdictsPath,
    [Parameter(Mandatory)][string]$D6RunPath,
    [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSCommandPath
$evaluatorRoot = [IO.Path]::GetFullPath((Join-Path $scriptRoot '..'))
Import-Module (Join-Path $scriptRoot 'BomberEvaluator.Common.psm1') -Force
Import-Module (Join-Path $scriptRoot 'BomberD6.psm1') -Force
Assert-BomberD6Protocol $evaluatorRoot
[void](Assert-BomberOriginalReferences $evaluatorRoot)

function Assert-Scorer([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Read-ScorerJson([string]$Path) {
    try {
        Assert-Scorer (Test-Path -LiteralPath $Path -PathType Leaf) 'A scorer input JSON file is missing.'
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    }
    catch { throw ('SCORER_INPUT_INVALID: ' + $_.Exception.Message) }
}

function Round-OneDecimal([double]$Value) {
    Assert-Scorer (-not [double]::IsNaN($Value) -and -not [double]::IsInfinity($Value)) 'A score is not finite.'
    return [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero)
}

function Test-NumericValue([object]$Value) {
    if ($null -eq $Value) { return $false }
    try {
        $number = [double]$Value
        return (-not [double]::IsNaN($number)) -and (-not [double]::IsInfinity($number))
    }
    catch { return $false }
}

function Test-HalfPoint([object]$Value) {
    if (-not (Test-NumericValue $Value)) { return $false }
    $number = [double]$Value
    return $number -ge 0.0 -and $number -le 10.0 -and [Math]::Abs(($number * 2.0) - [Math]::Round($number * 2.0)) -lt 0.000000001
}

function Get-SafeRelative([string]$Base, [string]$Path) {
    $baseFull = [IO.Path]::GetFullPath($Base).TrimEnd('\','/')
    $pathFull = [IO.Path]::GetFullPath($Path)
    $prefix = $baseFull + [IO.Path]::DirectorySeparatorChar
    if (-not $pathFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return '<external-evidence>' }
    return [IO.Path]::GetRelativePath($baseFull, $pathFull).Replace('\','/')
}

$config = Get-BomberEvaluatorConfig -EvaluatorRoot $evaluatorRoot
$catalog = Read-ScorerJson (Join-Path $evaluatorRoot 'catalog/checkpoints.json')
$run = Read-ScorerJson ([IO.Path]::GetFullPath($VerdictsPath))

Assert-Scorer ([string]$run.game_id -ceq [string]$config.game_id) 'Verdict record game identity is invalid.'
Assert-Scorer ([string]$run.schema_version -ceq '3.0.0') 'Verdict record schema version is invalid.'
Assert-Scorer ([string]$run.task_revision -ceq [string]$config.task_revision) 'Verdict record task revision is invalid.'
Assert-Scorer ([string]$run.evaluator_revision -ceq [string]$config.evaluator_revision) 'Verdict record evaluator revision is invalid.'
Assert-Scorer ([string]$run.run_status -ceq 'completed') 'The scorer refuses an evaluator-invalid run; repair the evaluator or host and rerun.'
Assert-Scorer (@($run.faults).Count -eq 0) 'The scorer refuses a run with infrastructure faults.'
Assert-Scorer ([string]$run.candidate_identity_sha256 -match '^[0-9a-f]{64}$') 'Candidate identity is not a lowercase SHA-256 value.'

$expectedEntries = @($catalog.checkpoints)
$expectedIds = @($expectedEntries | ForEach-Object { [string]$_.id })
$actualEntries = @($run.checkpoints)
$actualIds = @($actualEntries | ForEach-Object { [string]$_.checkpoint_id })
Assert-Scorer ($expectedIds.Count -gt 0) 'The checkpoint catalog is empty.'
Assert-Scorer (@($expectedIds | Sort-Object -Unique).Count -eq $expectedIds.Count) 'The checkpoint catalog contains duplicate IDs.'
Assert-Scorer (@($actualIds | Sort-Object -Unique).Count -eq $actualIds.Count) 'The verdict record contains duplicate checkpoint IDs.'
Assert-Scorer ((@($expectedIds | Sort-Object) -join "`n") -ceq (@($actualIds | Sort-Object) -join "`n")) 'Verdict record does not exactly cover the checkpoint catalog.'

$dimensionMax = [ordered]@{}
foreach ($property in $config.scoring.dimensions.PSObject.Properties) { $dimensionMax[$property.Name] = [double]$property.Value }
$dimensions = [ordered]@{}
foreach ($dimension in @('D1','D2','D3','D4','D5')) {
    $catalogItems = @($expectedEntries | Where-Object { [string]$_.dimension -ceq $dimension })
    $items = @($actualEntries | Where-Object { [string]$_.dimension -ceq $dimension })
    Assert-Scorer ($catalogItems.Count -gt 0 -and $items.Count -eq $catalogItems.Count) "Dimension $dimension has an invalid checkpoint count."
    foreach ($item in $items) {
        Assert-Scorer ([string]$item.verdict -in @('pass','fail','unreachable')) "Checkpoint $($item.checkpoint_id) has a non-numeric disposition."
        if ([string]$item.verdict -ne 'pass') {
            Assert-Scorer (-not [string]::IsNullOrWhiteSpace([string]$item.reason_code)) "Checkpoint $($item.checkpoint_id) lacks a failure reason."
            Assert-Scorer ([string]$item.attribution -ceq 'candidate') "Checkpoint $($item.checkpoint_id) is not attributed to the candidate."
            Assert-Scorer (-not [string]::IsNullOrWhiteSpace([string]$item.detail)) "Checkpoint $($item.checkpoint_id) lacks failure detail."
            Assert-Scorer (-not [string]::IsNullOrWhiteSpace([string]$item.first_failure)) "Checkpoint $($item.checkpoint_id) lacks first-failure evidence."
            Assert-Scorer ([string]$item.score_impact -ceq 'checkpoint_zero') "Checkpoint $($item.checkpoint_id) does not declare a zero score impact."
        }
        else {
            Assert-Scorer ([string]$item.score_impact -ceq 'full_credit') "Checkpoint $($item.checkpoint_id) does not declare full credit."
        }
    }
    $passed = @($items | Where-Object { [string]$_.verdict -ceq 'pass' }).Count
    $failed = @($items | Where-Object { [string]$_.verdict -ceq 'fail' }).Count
    $unreachable = @($items | Where-Object { [string]$_.verdict -ceq 'unreachable' }).Count
    $dimensions[$dimension] = [ordered]@{
        score = Round-OneDecimal ([double]$dimensionMax[$dimension] * $passed / $items.Count)
        maximum = [double]$dimensionMax[$dimension]
        passed = $passed
        failed = $failed
        unreachable = $unreachable
        total = $items.Count
    }
}

$referenceManifestPath = Join-Path $evaluatorRoot 'd6/d6-reference-manifest.json'
$promptPath = Join-Path $evaluatorRoot 'd6/FIXED_VLM_PROMPT.txt'
$referenceManifest = Read-ScorerJson $referenceManifestPath
$d6RunFull = [IO.Path]::GetFullPath($D6RunPath)
$d6Run = Read-ScorerJson $d6RunFull
$stateIds = @($config.scoring.d6_states | ForEach-Object { [string]$_ })
$roundCount = [int]$config.scoring.d6_rounds
Assert-Scorer ([string]$d6Run.schema_version -ceq '3.0.0') 'D6 run schema version is invalid.'
Assert-Scorer ([string]$d6Run.game_id -ceq [string]$config.game_id) 'D6 run game identity is invalid.'
Assert-Scorer ([string]$d6Run.task_revision -ceq [string]$config.task_revision) 'D6 run task revision is invalid.'
Assert-Scorer ([string]$d6Run.evaluator_revision -ceq [string]$config.evaluator_revision) 'D6 run evaluator revision is invalid.'
Assert-Scorer ([string]$d6Run.candidate_id -ceq [string]$run.candidate_id) 'D6 candidate ID does not match the D1-D5 run.'
Assert-Scorer ([string]$d6Run.candidate_identity_sha256 -ceq [string]$run.candidate_identity_sha256) 'D6 candidate identity does not match the D1-D5 run.'
Assert-Scorer ([string]$d6Run.reference_manifest_sha256 -ceq (Get-BomberSha256 $referenceManifestPath)) 'D6 reference manifest binding is stale.'
Assert-Scorer ([string]$d6Run.prompt_sha256 -ceq (Get-BomberSha256 $promptPath)) 'D6 fixed prompt binding is stale.'
Assert-Scorer ($d6Run.protocol -ceq 'canonical_five_criteria_three_rounds') 'D6 protocol is obsolete.'
Assert-Scorer ([string]$d6Run.status -ceq 'completed') 'D6 run is not complete.'

$referenceStates = @($referenceManifest.states)
Assert-Scorer ($referenceStates.Count -eq $stateIds.Count) 'D6 reference state count is inconsistent with the evaluator config.'
$evidenceStates = @($d6Run.states)
Assert-Scorer ($evidenceStates.Count -eq $stateIds.Count) 'D6 evidence state count is invalid.'
for ($i = 0; $i -lt $stateIds.Count; ++$i) {
    Assert-Scorer ([string]$referenceStates[$i].state_id -ceq $stateIds[$i]) 'D6 reference state order is invalid.'
    Assert-Scorer ([string]$evidenceStates[$i].state_id -ceq $stateIds[$i]) 'D6 evidence state order is invalid.'
    Assert-Scorer ([string]$evidenceStates[$i].reference_sha256 -ceq [string]$referenceStates[$i].sha256) "D6 reference image hash mismatch for $($stateIds[$i])."
    Assert-Scorer ([string]$evidenceStates[$i].candidate_status -in @('healthy','missing','invalid_png','wrong_resolution','black_or_blank')) "D6 candidate status is invalid for $($stateIds[$i])."
    if ([string]$evidenceStates[$i].candidate_status -ne 'healthy') {
        Assert-Scorer ([string]$evidenceStates[$i].reason_code -match '^D6_CANDIDATE_') "D6 candidate zero reason is missing for $($stateIds[$i])."
    }
}

$rounds = @($d6Run.rounds)
Assert-Scorer ($rounds.Count -eq $roundCount) 'D6 must contain exactly three ordered rounds.'
$roundScores = [Collections.Generic.List[double]]::new()
for ($roundIndex = 0; $roundIndex -lt $roundCount; ++$roundIndex) {
    $round = $rounds[$roundIndex]
    Assert-Scorer ([int]$round.round -eq ($roundIndex + 1)) 'D6 rounds must be ordered 1,2,3.'
    $states = @($round.states)
    Assert-Scorer ($states.Count -eq $stateIds.Count) "D6 round $($round.round) has the wrong state count."
    $sum = 0.0
    for ($stateIndex = 0; $stateIndex -lt $stateIds.Count; ++$stateIndex) {
        $state = $states[$stateIndex]
        Assert-Scorer ([string]$state.state_id -ceq $stateIds[$stateIndex]) 'D6 state order is invalid.'
        Assert-Scorer (Test-HalfPoint $state.score) 'D6 state score must be 0..10 in 0.5 increments.'
        Assert-Scorer ([string]$state.source -in @('vlm','automatic_zero')) 'D6 state source is invalid.'
        $expectedSource = if ($evidenceStates[$stateIndex].candidate_status -eq 'healthy') { 'vlm' } else { 'automatic_zero' }
        Assert-Scorer ([string]$state.source -ceq $expectedSource) 'D6 score source disagrees with capture health.'
        if ([string]$state.source -ceq 'automatic_zero') {
            Assert-Scorer ([double]$state.score -eq 0.0 -and -not [string]::IsNullOrWhiteSpace([string]$state.reason_code)) 'Automatic D6 zero is not attributed.'
        }
        else {
            Assert-Scorer (-not [string]::IsNullOrWhiteSpace([string]$state.rationale)) 'VLM D6 state rationale is empty.'
            $criteria=@($state.criteria.PSObject.Properties)
            Assert-Scorer ($criteria.Count -eq 5) 'D6 needs the five canonical criterion scores.'
            $criterionNames=@('Scene completeness and asset assembly','Composition and layout','Scale, hierarchy, and clarity','Style and color consistency','Overall polish')
            Assert-Scorer (@($criteria.Name | Where-Object { $_ -cnotin $criterionNames }).Count -eq 0) 'D6 criterion names do not match the canonical prompt.'
            foreach($criterion in $criteria){Assert-Scorer ((Test-HalfPoint $criterion.Value) -and [double]$criterion.Value -le 2) 'D6 criterion is outside 0..2 half points.'}
            Assert-Scorer (($criteria|Measure-Object Value -Sum).Sum -eq [double]$state.score) 'D6 criterion sum is inconsistent.'
        }
        $sum += [double]$state.score
    }
    $computed = Round-OneDecimal ($sum / $states.Count)
    Assert-Scorer (Test-NumericValue $round.score -and [Math]::Abs([double]$round.score - $computed) -lt 0.000000001) "D6 round $($round.round) aggregate is inconsistent."
    $roundScores.Add($computed)
}
$d6Score = Round-OneDecimal ((@($rounds | ForEach-Object { $_.states } | ForEach-Object { [double]$_.score }) | Measure-Object -Average).Average)
Assert-Scorer (Test-NumericValue $d6Run.score -and [Math]::Abs([double]$d6Run.score - $d6Score) -lt 0.000000001) 'D6 final aggregate is inconsistent.'
$dimensions.D6 = [ordered]@{
    score = $d6Score
    maximum = [double]$dimensionMax.D6
    protocol = [string]$d6Run.protocol
    round_scores = @($roundScores)
    rounds = @($rounds)
    status = 'completed'
    model_id = [string]$d6Run.model_id
    evidence = Get-SafeRelative -Base (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))) -Path $d6RunFull
}

$functional = Round-OneDecimal ([double]($dimensions.D1.score + $dimensions.D2.score + $dimensions.D3.score + $dimensions.D4.score + $dimensions.D5.score))
$overall = Round-OneDecimal ([double]$functional + [double]$d6Score)
$d1Start = @($actualEntries | Where-Object checkpoint_id -eq 'D1-03') | Select-Object -First 1
$d1Provider = @($actualEntries | Where-Object checkpoint_id -eq 'D1-04') | Select-Object -First 1
$coreFailures = @($actualEntries | Where-Object { [string]$_.dimension -in @('D3','D4') -and [string]$_.verdict -ne 'pass' })

$result = [ordered]@{
    schema_version = '3.0.0'
    game_id = [string]$config.game_id
    task_name = [string]$run.task_name
    task_revision = [string]$config.task_revision
    engine = "Unreal Engine $($config.engine.version)"
    engine_changelist = [int64]$config.engine.changelist
    run_id = [string]$run.run_id
    candidate_id = [string]$run.candidate_id
    candidate_identity_sha256 = [string]$run.candidate_identity_sha256
    evaluator_revision = [string]$config.evaluator_revision
    scorer_revision = [string]$config.scorer_revision
    evaluation_status = 'completed'
    diagnostic_only = $true
    formal_freeze_performed = $false
    dimensions = $dimensions
    functional_total = $functional
    overall = $overall
    executable = if ($d1Start.verdict -eq 'pass' -and $d1Provider.verdict -eq 'pass') { 'Yes' } else { 'No' }
    solved = if ($coreFailures.Count -eq 0) { 'Yes' } else { 'No' }
    package_valid = $true
    formal_score_publishable = $false
    checkpoints = $actualEntries
    candidate_failures = @($run.candidate_failures)
    faults = @()
    warnings = @($run.warnings)
    budget = $run.budget
    d6_evidence = Get-SafeRelative -Base (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))) -Path $d6RunFull
    score_provenance = [ordered]@{catalog='catalog/checkpoints.json';config='contracts/evaluator-config.json';d6_reference='d6/d6-reference-manifest.json';fixed_prompt='d6/FIXED_VLM_PROMPT.txt'}
}

$outputFull = [IO.Path]::GetFullPath($OutputPath)
[void](New-Item -ItemType Directory -Path (Split-Path -Parent $outputFull) -Force)
Write-BomberJson -Value $result -Path $outputFull
Write-Output $outputFull
