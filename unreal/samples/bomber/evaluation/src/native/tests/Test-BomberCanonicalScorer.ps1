[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Write-Json($Value,[string]$Path){[IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n"),[Text.UTF8Encoding]::new($false))}
$root=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSCommandPath) '..'))
. (Join-Path $PSScriptRoot 'TestFixture.ps1')
$fixture=New-BomberTestFixture $root
$root=$fixture.root
$config=Get-Content -Raw (Join-Path $root 'contracts/evaluator-config.json') -Encoding UTF8|ConvertFrom-Json -Depth 50
$catalog=Get-Content -Raw (Join-Path $root 'catalog/checkpoints.json') -Encoding UTF8|ConvertFrom-Json -Depth 100
$reference=Get-Content -Raw (Join-Path $root 'd6/d6-reference-manifest.json') -Encoding UTF8|ConvertFrom-Json -Depth 100
$temp=$fixture.temp
try {
  $identity='a'*64
  $checkpoints=@($catalog.checkpoints|ForEach-Object{[ordered]@{checkpoint_id=[string]$_.id;dimension=[string]$_.dimension;verdict='pass';detail='unit';reason_code=$null;attribution=$null;first_failure=$null;score_impact='full_credit';evidence=@()}})
  $base=[ordered]@{schema_version='3.0.0';game_id='Bomber';task_name='Bomber Local Duel';task_revision=[string]$config.task_revision;run_id='unit';candidate_id='unit';candidate_identity_sha256=$identity;evaluator_revision=[string]$config.evaluator_revision;run_status='completed';checkpoints=$checkpoints;candidate_failures=@();faults=@();warnings=@();budget=[ordered]@{}}
  $stateEvidence=@($reference.states|ForEach-Object{[ordered]@{state_id=[string]$_.state_id;reference_image=[string]$_.reference_image;reference_sha256=[string]$_.sha256;candidate_image=$null;candidate_status='missing';candidate_sha256=$null;reason_code='D6_CANDIDATE_STATE_MISSING'}})
  $rounds=@(1..3|ForEach-Object{[ordered]@{round=$_;response_sha256=('b'*64);states=@($stateEvidence|ForEach-Object{[ordered]@{state_id=$_.state_id;score=0.0;rationale='missing';source='automatic_zero';reason_code='D6_CANDIDATE_STATE_MISSING'}});score=0.0}})
  $d6=[ordered]@{schema_version='3.0.0';game_id='Bomber';task_revision=[string]$config.task_revision;evaluator_revision=[string]$config.evaluator_revision;candidate_id='unit';candidate_identity_sha256=$identity;status='completed';protocol='canonical_five_criteria_three_rounds';model_id='unit-vlm';reference_manifest_sha256=(Get-FileHash (Join-Path $root 'd6/d6-reference-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant();prompt_sha256=(Get-FileHash (Join-Path $root 'd6/FIXED_VLM_PROMPT.txt') -Algorithm SHA256).Hash.ToLowerInvariant();states=$stateEvidence;rounds=$rounds;score=0.0}
  $vp=Join-Path $temp 'verdicts.json';$dp=Join-Path $temp 'd6.json';$op=Join-Path $temp 'result.json';Write-Json $base $vp;Write-Json $d6 $dp;& (Join-Path $root 'scripts/Invoke-BomberCanonicalScorer.ps1') -VerdictsPath $vp -D6RunPath $dp -OutputPath $op|Out-Null;$result=Get-Content -Raw $op|ConvertFrom-Json -Depth 100
  Assert ($result.dimensions.D1.score -eq 10 -and $result.dimensions.D2.score -eq 30 -and $result.dimensions.D3.score -eq 20 -and $result.dimensions.D4.score -eq 20 -and $result.dimensions.D5.score -eq 10 -and $result.dimensions.D6.score -eq 0) 'All-pass functional or zero-D6 scores are wrong.'
  Assert ($result.functional_total -eq 90 -and $result.overall -eq 90) 'Numeric totals are wrong.'
  $visual=$d6|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  foreach($state in $visual.states){$state.candidate_status='healthy'}
  foreach($round in $visual.rounds){
    foreach($state in $round.states){
      $state.source='vlm';$state.score=7;$state.reason_code=$null
      $state|Add-Member criteria ([pscustomobject]@{'Scene completeness and asset assembly'=2;'Composition and layout'=1.5;'Scale, hierarchy, and clarity'=1;'Style and color consistency'=0.5;'Overall polish'=2})
    }
    $round.score=7
  }
  $visual.score=7;Write-Json $visual $dp
  & (Join-Path $root 'scripts/Invoke-BomberCanonicalScorer.ps1') -VerdictsPath $vp -D6RunPath $dp -OutputPath $op|Out-Null
  Assert ((Get-Content -Raw $op|ConvertFrom-Json).overall -eq 97) 'Canonical five-criterion D6 did not score.'
  $visual.rounds[0].states[0].criteria=[pscustomobject]@{a=2;b=1.5;c=1;d=0.5;e=2};Write-Json $visual $dp
  $rejected=$false;try{& (Join-Path $root 'scripts/Invoke-BomberCanonicalScorer.ps1') -VerdictsPath $vp -D6RunPath $dp -OutputPath $op|Out-Null}catch{$rejected=$_.Exception.Message -match 'criterion names'};Assert $rejected 'Noncanonical criterion names were accepted.'
  $visual.states[0].candidate_status='missing';$visual.states[0].reason_code='D6_CANDIDATE_STATE_MISSING';Write-Json $visual $dp
  $rejected=$false;try{& (Join-Path $root 'scripts/Invoke-BomberCanonicalScorer.ps1') -VerdictsPath $vp -D6RunPath $dp -OutputPath $op|Out-Null}catch{$rejected=$_.Exception.Message -match 'capture health'};Assert $rejected 'Missing capture received VLM points.'
  Write-Json $d6 $dp
  $checkpoints[5].verdict='fail';$checkpoints[5].reason_code='UNIT_FAILURE';$checkpoints[5].attribution='candidate';$checkpoints[5].first_failure='states/unit.json';$checkpoints[5].score_impact='checkpoint_zero';$base.checkpoints=$checkpoints;$base.candidate_failures=@([ordered]@{reason_code='UNIT_FAILURE';attribution='candidate';first_failure='states/unit.json';affected_checkpoints=@($checkpoints[5].checkpoint_id);evidence=@('states/unit.json')});Write-Json $base $vp;& (Join-Path $root 'scripts/Invoke-BomberCanonicalScorer.ps1') -VerdictsPath $vp -D6RunPath $dp -OutputPath $op|Out-Null;$failed=Get-Content -Raw $op|ConvertFrom-Json -Depth 100;Assert ($failed.dimensions.D2.score -lt 30 -and $failed.functional_total -lt 90) 'A failed checkpoint did not reduce numeric totals.'
  $checkpoints[5].verdict=$null;$base.checkpoints=$checkpoints;Write-Json $base $vp;$rejected=$false;try{& (Join-Path $root 'scripts/Invoke-BomberCanonicalScorer.ps1') -VerdictsPath $vp -D6RunPath $dp -OutputPath $op|Out-Null}catch{$rejected=$true};Assert $rejected 'The scorer accepted a null checkpoint for a completed candidate.'
  Write-Output 'CANONICAL_SCORER_OK checkpoints=43 numeric_dimensions=6 no_na_scores=true strict_failure_attribution=true'
}
finally { Remove-BomberTestFixture $fixture.temp }
