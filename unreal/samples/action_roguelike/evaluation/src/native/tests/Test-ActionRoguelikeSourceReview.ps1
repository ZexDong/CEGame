[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/ActionRoguelikeSourceReview.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ar-source-review-'+[guid]::NewGuid().ToString('N'))
$runRoot=Join-Path $temp 'evaluation/source';$reviewRoot=Join-Path $temp 'evaluation/review'
function Save($value,$p){$value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $p}
function Hash($p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
try{
 New-Item -ItemType Directory -Path $runRoot,$reviewRoot,(Join-Path $temp 'input/project/Source'),(Join-Path $temp 'catalog') -Force|Out-Null
 $src=Join-Path $temp 'input/project/Source/Player.cpp';[IO.File]::WriteAllText($src,"void Act() { Jump(); }`n")
 $frame=Join-Path $runRoot 'state.txt';'actual state'|Set-Content $frame
 $identity=Join-Path $reviewRoot 'identity.json';Save @{candidate_identity_sha256=('a'*64)} $identity
 $catalog=@{checkpoints=@(@{id='D2-01';pass_condition='actual action'},@{id='D2-02';pass_condition='reset velocity'})}
 $catalogPath=Join-Path $temp 'catalog/checkpoints.json';Save $catalog $catalogPath
 $run=@{run_id='original';candidate_id='candidate';candidate_identity_sha256=('a'*64);candidate_failures=@(@{checkpoint_id='D2-01'});checkpoints=@(
  @{checkpoint_id='D2-01';verdict='fail';reason_code='MISSING_EVENT';attribution='candidate';detail='missing event';first_failure='state.txt';score_impact='checkpoint_zero';evidence=@('state.txt')},
  @{checkpoint_id='D2-02';verdict='pass';reason_code=$null;attribution=$null;detail='weak smoke';first_failure=$null;score_impact='full_credit';evidence=@('state.txt')})}
 $verdict=Join-Path $runRoot 'verdicts.json';Save $run $verdict
 $sr=@{path='../../input/project/Source/Player.cpp';sha256=(Hash $src);symbol='Act';line_start=1;line_end=1;excerpt='void Act() { Jump(); }'}
 $ev=@{path='state.txt';sha256=(Hash $frame)}
 $review=@{schema_version='1.0.0';policy='source-corroborated-1.0.0';source_run_id='original';reassessment_id='source-reviewed';candidate_id='candidate';candidate_identity_sha256=('a'*64);verdicts_sha256=(Hash $verdict);catalog_sha256=(Hash $catalogPath);current_candidate=@{path='../review/identity.json';sha256=(Hash $identity)};checkpoints=@(
  @{checkpoint_id='D2-01';original_verdict='fail';verdict='pass';pass_condition='actual action';basis='source_and_runtime';rationale='Input reaches actual jump and runtime corroborates action';promotion_reason='Missing event did not imply absent action';missing_requirements=@();source_evidence=@($sr);evidence=@($ev)},
  @{checkpoint_id='D2-02';original_verdict='pass';verdict='fail';pass_condition='reset velocity';basis='implementation_defect';rationale='Reset path never clears motion';promotion_reason=$null;missing_requirements=@('clean velocity');source_evidence=@($sr);evidence=@($ev)})}
 $reviewPath=Join-Path $reviewRoot 'review.json';Save $review $reviewPath;$saved=Get-Content $reviewPath -Raw
 $fresh=Get-Content $verdict -Raw|ConvertFrom-Json -Depth 100
 $result=Apply-ActionRoguelikeSourceReview $fresh $catalog $verdict $reviewPath $temp
 if($fresh.checkpoints[0].verdict -cne 'pass' -or $fresh.checkpoints[0].reason_code -or $fresh.candidate_failures.Count -ne 1 -or $fresh.candidate_failures[0].checkpoint_id -cne 'D2-02'){throw 'Promotion/failure reconciliation failed'}
 if((Hash $verdict) -cne $review.verdicts_sha256){throw 'Original verdict modified'}
 $cases=@(
  @{name='identity';edit={param($r)$r.candidate_identity_sha256='b'*64}},
  @{name='coverage';edit={param($r)$r.checkpoints=@($r.checkpoints[0])}},
  @{name='condition';edit={param($r)$r.checkpoints[0].pass_condition='weaker condition'}},
  @{name='source_hash';edit={param($r)$r.checkpoints[0].source_evidence[0].sha256='b'*64}},
  @{name='source_excerpt';edit={param($r)$r.checkpoints[0].source_evidence[0].excerpt='void Act() { Fake(); }'}},
  @{name='source_line';edit={param($r)$r.checkpoints[0].source_evidence[0].line_start=0}},
  @{name='source_escape';edit={param($r)$r.checkpoints[0].source_evidence[0].path='../../catalog/checkpoints.json'}},
  @{name='runtime_escape';edit={param($r)$r.checkpoints[0].evidence[0].path='../../input/project/Source/Player.cpp'}},
  @{name='missing_source';edit={param($r)$r.checkpoints[0].source_evidence=@()}},
  @{name='unexplained_promotion';edit={param($r)$r.checkpoints[0].promotion_reason=''}},
  @{name='pass_with_gap';edit={param($r)$r.checkpoints[0].missing_requirements=@('missing action')}},
  @{name='bad_basis';edit={param($r)$r.checkpoints[1].basis='source_and_runtime'}},
  @{name='empty_failure';edit={param($r)$r.checkpoints[1].missing_requirements=@()}},
  @{name='current_identity_hash';edit={param($r)$r.current_candidate.sha256='b'*64}},
  @{name='source_verdict_hash';edit={param($r)$r.verdicts_sha256='b'*64}}
 )
 foreach($case in $cases){
  $bad=$saved|ConvertFrom-Json -AsHashtable -Depth 100;& $case.edit $bad;Save $bad $reviewPath
  $fresh=Get-Content $verdict -Raw|ConvertFrom-Json -Depth 100;$rejected=$false
  try{$null=Apply-ActionRoguelikeSourceReview $fresh $catalog $verdict $reviewPath $temp}catch{$rejected=$true}
  if(-not $rejected){throw ('Accepted invalid review: '+$case.name)}
  if($fresh.checkpoints[0].verdict -cne 'fail'){throw 'Validation failure partially changed verdicts'}
 }
 # Source-informed uncertainty must not be misattributed as a candidate defect.
 $gap=$saved|ConvertFrom-Json -AsHashtable -Depth 100;$gap.checkpoints[1].basis='unresolved_after_source_review';Save $gap $reviewPath
 $fresh=Get-Content $verdict -Raw|ConvertFrom-Json -Depth 100
 $result=Apply-ActionRoguelikeSourceReview $fresh $catalog $verdict $reviewPath $temp
 if($result.evidence_gaps.Count -ne 1 -or $fresh.candidate_failures.Count -ne 0){throw 'Uncertainty attribution failed'}
 'ACTIONROGUELIKE_SOURCE_REVIEW_OK promotion=true source_hash_and_excerpt=true tamper_cases=15 immutable_source=true reconciled_failures=true'
}finally{
 $safe=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
 $full=[IO.Path]::GetFullPath($temp)
 if($full.StartsWith($safe,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full).StartsWith('ar-source-review-')){Remove-Item -LiteralPath $full -Recurse -Force}
}
