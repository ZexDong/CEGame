[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateCapturesDirectory,
    [Parameter(Mandatory)][string]$CandidateId,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$CandidateIdentitySha256,
    [Parameter(Mandatory)][string]$ModelId,
    [string]$ResponsesPath,
    [Parameter(Mandatory)][string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-JsonFile($Value, [string]$Path) {
    $parent = Split-Path -Parent $Path
    if ($parent) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Get-Sha256Text([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Round-OneDecimal([double]$Value) {
    return [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero)
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$evaluatorRoot = [IO.Path]::GetFullPath((Join-Path $scriptRoot '..'))
Import-Module (Join-Path $scriptRoot 'BomberEvaluator.Common.psm1') -Force
Import-Module (Join-Path $scriptRoot 'BomberObservation.psm1') -Force
Import-Module (Join-Path $scriptRoot 'BomberD6.psm1') -Force
Assert-BomberD6Protocol $evaluatorRoot
[void](Assert-BomberOriginalReferences $evaluatorRoot)
$config = Get-BomberEvaluatorConfig -EvaluatorRoot $evaluatorRoot
$d6Root = Join-Path $evaluatorRoot 'd6'
$referenceManifestPath = Join-Path $d6Root 'd6-reference-manifest.json'
$promptPath = Join-Path $d6Root 'FIXED_VLM_PROMPT.txt'
$referenceManifest = Get-Content -LiteralPath $referenceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$referenceManifestHash = (Get-FileHash -LiteralPath $referenceManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$promptHash = (Get-FileHash -LiteralPath $promptPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([string]$referenceManifest.fixed_prompt_sha256 -cne $promptHash -or @($referenceManifest.states).Count -ne [int]$config.scoring.d6_states.Count) {
    throw 'The frozen D6 reference package is invalid.'
}

$capturesFull = [IO.Path]::GetFullPath($CandidateCapturesDirectory)
$outputFull = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $capturesFull -PathType Container)) {
    # Missing candidate capture directories are candidate evidence failures,
    # not evaluator faults. Keep the directory absent and let every state
    # receive an attributed numeric zero below.
    $capturesFull = [IO.Path]::GetFullPath($CandidateCapturesDirectory)
}
if (Test-Path -LiteralPath $outputFull) {
    if (@(Get-ChildItem -LiteralPath $outputFull -Force).Count -gt 0) { throw 'D6 output directory must be absent or empty.' }
}
[void](New-Item -ItemType Directory -Path $outputFull -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $outputFull 'rounds') -Force)

$captureNames = [ordered]@{
    'active-duel' = 'active-arena.png'
    'chain-reaction' = 'chain-reaction.png'
    'player1-win' = 'player1-win.png'
}
$stateEvidence = [Collections.Generic.List[object]]::new()
foreach ($referenceState in $referenceManifest.states) {
    $stateId = [string]$referenceState.state_id
    $candidatePath = Join-Path $capturesFull $captureNames[$stateId]
    try {
        [void](Resolve-BomberSafePath -Root $capturesFull -Path $candidatePath)
    }
    catch {
        $candidatePath = Join-Path $capturesFull '__invalid_capture_path__'
    }
    Assert-BomberSemanticCapture $candidatePath $stateId $CandidateIdentitySha256
    $health = Get-BomberD6CaptureHealth $candidatePath -Width $config.robustness.capture_width -Height $config.robustness.capture_height
    $candidateRelative = if (Test-Path -LiteralPath $candidatePath -PathType Leaf) { [IO.Path]::GetRelativePath($outputFull, $candidatePath).Replace('\','/') } else { $null }
    $stateEvidence.Add([pscustomobject][ordered]@{
        state_id = $stateId
        reference_image = [string]$referenceState.reference_image
        reference_sha256 = [string]$referenceState.sha256
        candidate_image = $candidateRelative
        candidate_status = [string]$health.status
        candidate_sha256 = $health.sha256
        width = $health.width
        height = $health.height
        reason_code = $health.reason_code
    })
}
$healthyCount = @($stateEvidence | Where-Object candidate_status -eq 'healthy').Count


$responses=$null
if($ResponsesPath){
    $responses=Get-Content -LiteralPath $ResponsesPath -Raw|ConvertFrom-Json -Depth 100
    if($responses.schema_version -cne '2.0.0' -or $responses.protocol -cne 'canonical_five_criteria_three_rounds' -or $responses.model_id -cne $ModelId -or $responses.candidate_identity_sha256 -cne $CandidateIdentitySha256 -or $responses.prompt_sha256 -cne $promptHash -or $responses.reference_manifest_sha256 -cne $referenceManifestHash -or @($responses.rounds).Count -ne 3){throw 'D6_RESPONSE_IDENTITY_INVALID'}
    for($i=0;$i -lt $stateEvidence.Count;++$i){
        $pair=$responses.pairs[$i];$state=$stateEvidence[$i]
        if($pair.state_id -cne $state.state_id -or $pair.candidate_sha256 -cne $state.candidate_sha256 -or $pair.reference_sha256 -cne $state.reference_sha256){throw 'D6_RESPONSE_IMAGE_BINDING_INVALID'}
    }
}elseif($healthyCount -gt 0){throw 'D6_THREE_ROUNDS_REQUIRED'}
$roundRecords=[Collections.Generic.List[object]]::new();$allScores=[Collections.Generic.List[double]]::new()
for($roundNumber=1;$roundNumber -le 3;++$roundNumber){
    $roundStates=[Collections.Generic.List[object]]::new();$responseHash=$null
    if($responses){
        $rawRound=$responses.rounds[$roundNumber-1]
        if($rawRound.round -ne $roundNumber -or @($rawRound.states).Count -ne $stateEvidence.Count){throw 'D6_RESPONSE_ROUND_ORDER_INVALID'}
        $responseHash=Get-Sha256Text ($rawRound|ConvertTo-Json -Depth 30 -Compress)
        Write-JsonFile $rawRound (Join-Path $outputFull "rounds/round-$roundNumber-raw.json")
    }
    for($i=0;$i -lt $stateEvidence.Count;++$i){
        $state=$stateEvidence[$i]
        if($state.candidate_status -eq 'healthy'){
            $rawState=$responses.rounds[$roundNumber-1].states[$i]
            if($rawState.state_id -cne $state.state_id){throw 'D6_RESPONSE_STATE_ORDER_INVALID'}
            $parsed=ConvertFrom-BomberVisualResponse $rawState.response_text
            $roundStates.Add([pscustomobject]@{state_id=$state.state_id;score=$parsed.score;criteria=$parsed.criteria;rationale=$parsed.rationale;source='vlm';reason_code=$null})
        }else{
            $roundStates.Add([pscustomobject]@{state_id=$state.state_id;score=0.0;criteria=$null;rationale="Candidate frame status: $($state.candidate_status).";source='automatic_zero';reason_code=$state.reason_code})
        }
    }
    foreach($state in $roundStates){$allScores.Add([double]$state.score)}
    $roundScore=Round-OneDecimal (($roundStates|Measure-Object score -Average).Average)
    $roundRecords.Add([pscustomobject]@{round=$roundNumber;response_sha256=$responseHash;states=@($roundStates);score=$roundScore})
}
$result=[ordered]@{schema_version='3.0.0';game_id=$config.game_id;task_revision=$config.task_revision;evaluator_revision=$config.evaluator_revision;candidate_id=$CandidateId;candidate_identity_sha256=$CandidateIdentitySha256;status='completed';protocol='canonical_five_criteria_three_rounds';model_id=$ModelId;reference_manifest_sha256=$referenceManifestHash;prompt_sha256=$promptHash;states=@($stateEvidence);rounds=@($roundRecords);score=Round-OneDecimal (($allScores|Measure-Object -Average).Average)}
$resultPath=Join-Path $outputFull 'd6-run.json';Write-JsonFile $result $resultPath;Write-Output $resultPath
