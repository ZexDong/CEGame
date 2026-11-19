[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VerdictsPath,
    [Parameter(Mandatory)][string]$D6RunPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$EvidenceReviewPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Round-OneDecimal([double]$Value) {
    return [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero)
}

function Test-NumericValue([object]$Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$evaluatorRoot = [IO.Path]::GetFullPath((Join-Path $scriptRoot '..'))
$catalog = Get-Content -LiteralPath (Join-Path $evaluatorRoot 'catalog/checkpoints.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$run = Get-Content -LiteralPath ([IO.Path]::GetFullPath($VerdictsPath)) -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100

if ([string]$run.game_id -cne 'ActionRoguelike' -or [string]$run.schema_version -cne '4.0.0' -or
    [string]$run.task_revision -cne '2.2.0-diagnostic' -or [string]$run.evaluator_revision -cne 'actionroguelike-evaluator-4.1.0') {
    throw 'Verdict record identity is invalid.'
}
if ([string]$run.run_status -cne 'completed' -or @($run.faults).Count -gt 0) {
    throw 'The scorer refuses an evaluator-invalid run. Repair the evaluator or host and rerun instead of publishing N/A scores.'
}

$expected = @($catalog.checkpoints | ForEach-Object { [string]$_.id })
$actual = @($run.checkpoints | ForEach-Object { [string]$_.checkpoint_id })
if (@($expected | Sort-Object -Unique).Count -ne $expected.Count -or
    @($actual | Sort-Object -Unique).Count -ne $actual.Count -or
    (($expected | Sort-Object) -join "`n") -cne (($actual | Sort-Object) -join "`n")) {
    throw 'Verdict record does not exactly cover the checkpoint catalog.'
}

foreach ($checkpoint in $catalog.checkpoints) {
    $item=@($run.checkpoints | Where-Object { $_.checkpoint_id -ceq $checkpoint.id })
    if ($item.Count -ne 1 -or [string]$item[0].dimension -cne [string]$checkpoint.dimension) {
        throw "Checkpoint dimension does not match its catalog owner: $($checkpoint.id)."
    }
}
if ($run.PSObject.Properties['mode'] -and [string]$run.mode -ceq 'transport_health_only') {
    throw 'Transport health is not a complete gameplay evaluation and cannot produce scores.'
}

$strictReview=$null
if($EvidenceReviewPath){
    $reviewPolicy=(Get-Content -LiteralPath $EvidenceReviewPath -Raw|ConvertFrom-Json -Depth 100).policy
    if($reviewPolicy -ceq 'source-corroborated-1.0.0'){
        . (Join-Path $scriptRoot 'ActionRoguelikeSourceReview.ps1')
        $strictReview=Apply-ActionRoguelikeSourceReview -Run $run -Catalog $catalog -VerdictsPath $VerdictsPath -ReviewPath $EvidenceReviewPath -EvaluatorRoot $evaluatorRoot
    }else{throw 'Unsupported evidence review policy. Use source-corroborated-1.0.0.'}
}

$dimensionMax = [ordered]@{ D1=10.0; D2=30.0; D3=20.0; D4=20.0; D5=10.0 }
$dimensions = [ordered]@{}
foreach ($dimension in $dimensionMax.Keys) {
    $items = @($run.checkpoints | Where-Object dimension -eq $dimension)
    foreach ($item in $items) {
        if ([string]$item.verdict -notin @('pass','fail','unreachable')) {
            throw "A completed candidate has a non-numeric checkpoint disposition: $($item.checkpoint_id)."
        }
        if ([string]$item.verdict -ne 'pass' -and
            ([string]::IsNullOrWhiteSpace([string]$item.reason_code) -or
             ([string]$item.attribution -cne 'candidate' -and -not($strictReview -and [string]$item.attribution -ceq 'evidence_gap')) -or
             [string]::IsNullOrWhiteSpace([string]$item.detail) -or
             [string]::IsNullOrWhiteSpace([string]$item.first_failure))) {
            throw "Candidate failure attribution is incomplete for $($item.checkpoint_id)."
        }
    }
    $passed = @($items | Where-Object verdict -eq 'pass').Count
    $score = Round-OneDecimal ([double]$dimensionMax[$dimension] * $passed / $items.Count)
    $dimensions[$dimension] = [ordered]@{
        score = $score
        maximum = [double]$dimensionMax[$dimension]
        passed = $passed
        failed = @($items | Where-Object verdict -eq 'fail').Count
        unreachable = @($items | Where-Object verdict -eq 'unreachable').Count
        total = $items.Count
    }
}

# Replay immutable requests, responses, and captures instead of trusting totals.
. (Join-Path $scriptRoot 'ActionRoguelikeD6Protocol.ps1')
$d6RunFull = [IO.Path]::GetFullPath($D6RunPath)
$d6Run = Read-D6Json $d6RunFull
Assert-D6 ($d6Run.schema_version -ceq '4.0.0' -and $d6Run.game_id -ceq 'ActionRoguelike' -and $d6Run.task_revision -ceq '2.2.0-diagnostic' -and $d6Run.evaluator_revision -ceq 'actionroguelike-evaluator-4.1.0' -and $d6Run.protocol -ceq 'canonical_d6_v4') 'D6_RUN_IDENTITY_INVALID'
Assert-D6 ($d6Run.candidate_id -ceq $run.candidate_id -and $d6Run.candidate_identity_sha256 -ceq $run.candidate_identity_sha256) 'D6_CANDIDATE_IDENTITY_MISMATCH'
Assert-D6 ($d6Run.status -ceq 'completed' -and @($d6Run.faults).Count -eq 0) 'D6_RUN_INVALID'
$d6Root = Split-Path -Parent $d6RunFull
$bundlePath = Assert-D6Artifact $d6Root $d6Run.evidence_bundle $d6Run.evidence_bundle_sha256
$verified = Get-D6Evaluation $evaluatorRoot (Join-Path $d6Root 'captures') $bundlePath $run.candidate_id $run.candidate_identity_sha256 $d6Run.model_id
foreach ($key in @('model','states','rounds','score_raw','score','vlm_config_sha256','reference_manifest_sha256','prompt_sha256')) {
    Assert-D6 ((ConvertTo-D6Canonical $d6Run[$key]) -ceq (ConvertTo-D6Canonical $verified[$key])) ('D6_REPLAY_MISMATCH_' + $key.ToUpperInvariant())
}
Assert-D6 ($d6Run.vlm_version -ceq $verified.model.version) 'D6_MODEL_VERSION_MISMATCH'
foreach ($raw in $verified.raw_records) {
    $prefix='rounds/'+$raw.round+'/'+$raw.state_id+'/'
    $null=Assert-D6Artifact $d6Root ($prefix+'request.json') (Get-D6TextHash (ConvertTo-D6Canonical $raw.request))
    $null=Assert-D6Artifact $d6Root ($prefix+'response.json') (Get-D6TextHash (ConvertTo-D6Canonical $raw.response))
}
$d6Score=[double]$verified.score
$d6Raw=[double]$verified.score_raw
$roundScores=@($verified.rounds | ForEach-Object { [double]$_.score })
$dimensions.D6 = [ordered]@{
    score=$d6Score; maximum=10.0; protocol='canonical_d6_v4'; round_scores=$roundScores
    raw_score=$d6Raw; status='completed'; model_id=[string]$verified.model.id
}

$functional = Round-OneDecimal ([double]($dimensions.D1.score + $dimensions.D2.score + $dimensions.D3.score + $dimensions.D4.score + $dimensions.D5.score))
$overall = Round-OneDecimal ([double]$functional + [double]$d6Score)
$d1Build = @($run.checkpoints | Where-Object checkpoint_id -eq 'D1-03')[0]
$d1Start = @($run.checkpoints | Where-Object checkpoint_id -eq 'D1-04')[0]
$coreFailures = @($run.checkpoints | Where-Object { $_.dimension -in @('D3','D4') -and $_.verdict -ne 'pass' })
$outputFull = [IO.Path]::GetFullPath($OutputPath)
$result = [ordered]@{
    schema_version = '4.0.0'
    game_id = 'ActionRoguelike'
    task_name = 'Rift Hunting'
    task_revision = '2.2.0-diagnostic'
    engine = 'Unreal Engine 5.6.1'
    run_id = [string]$run.run_id
    candidate_id = [string]$run.candidate_id
    candidate_identity_sha256 = [string]$run.candidate_identity_sha256
    evaluator_revision = [string]$run.evaluator_revision
    scorer_revision = 'actionroguelike-canonical-scorer-4.1.0'
    evaluation_status = 'completed'
    diagnostic_only = $true
    formal_freeze_performed = $false
    dimensions = $dimensions
    functional_total = $functional
    overall = $overall
    executable = if ($d1Build.verdict -eq 'pass' -and $d1Start.verdict -eq 'pass') { 'Yes' } else { 'No' }
    solved = if ($coreFailures.Count -eq 0) { 'Yes' } else { 'No' }
    package_valid = $null
    formal_score_publishable = $false
    checkpoints = $run.checkpoints
    candidate_failures = @($run.candidate_failures)
    faults = @()
    budget = $run.budget
    d6_evidence = [IO.Path]::GetRelativePath((Split-Path -Parent $outputFull), $d6RunFull).Replace('\','/')
}

if($strictReview){
    $result.scorer_revision='actionroguelike-canonical-scorer-4.1.0-source.1'
    $result.scoring_policy=$strictReview.policy
    $result.source_run_id=$strictReview.source_run_id
    $result.source_evidence_root=[IO.Path]::GetRelativePath((Split-Path -Parent $outputFull),(Split-Path -Parent ([IO.Path]::GetFullPath($VerdictsPath)))).Replace('\','/')
    $result.evidence_review=[ordered]@{path=[IO.Path]::GetRelativePath((Split-Path -Parent $outputFull),$strictReview.review_path).Replace('\','/');sha256=$strictReview.review_sha256}
    $result.evidence_gaps=$strictReview.evidence_gaps
}

New-Item -ItemType Directory -Path (Split-Path -Parent $outputFull) -Force | Out-Null
[IO.File]::WriteAllText($outputFull, ($result | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Output $outputFull
