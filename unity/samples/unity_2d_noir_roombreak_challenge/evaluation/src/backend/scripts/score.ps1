param(
 [Parameter(Mandatory=$true)][string]$OutputRoot,
 [Parameter(Mandatory=$true)][string]$ProjectPath,
 [Parameter(Mandatory=$true)][int]$StaticExit,
 [Parameter(Mandatory=$true)][int]$DynamicExit,
 [Parameter(Mandatory=$true)][int]$FreshExit,
 [bool]$StaticTimedOut=$false,
 [bool]$DynamicTimedOut=$false,
 [bool]$FreshTimedOut=$false,
 [switch]$CandidateCompileFailure
)
$ErrorActionPreference='Stop'
$evaluationRoot=Split-Path -Parent $PSScriptRoot
$rules=Get-Content -LiteralPath (Join-Path $evaluationRoot 'rules.json') -Raw|ConvertFrom-Json
$coverage=Get-Content -LiteralPath (Join-Path $evaluationRoot $rules.coverage_manifest) -Raw|ConvertFrom-Json
$titles=@{D1='Engineering Validity & Engine Integration';D2='Specification Fulfillment & Content Completeness';D3='Gameplay Correctness & System Behavior';D4='End-to-End Flow & Lifecycle Integrity';D5='Interface Functionality & Player Feedback'}

function Get-OrdinalSet([object[]]$values){$set=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($value in @($values)){if($null-ne$value){[void]$set.Add([string]$value)}};return ,$set}
function Compare-Set([object[]]$left,[object[]]$right){$a=Get-OrdinalSet $left;$b=Get-OrdinalSet $right;return $a.SetEquals($b)}
function Get-Duplicates([object[]]$values){$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$duplicates=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($value in @($values)){$text=[string]$value;if(-not$seen.Add($text)){[void]$duplicates.Add($text)}};$result=@($duplicates);[Array]::Sort($result,[StringComparer]::Ordinal);return $result}
function Get-LeafNames([xml]$xml){@($xml.SelectNodes('//test-case')|ForEach-Object{[string]$_.name})}
function Get-ExpectedInputRoute([string]$phase){switch($phase){'static'{'No player input; saved-entry engineering gate only'}'dynamic'{'Unity Input System virtual Keyboard and Mouse through real player-loop frames'}'fresh'{'New Unity process; normal Input System pointer/Enter starts reopened run'}default{''}}}

$ruleReasons=[System.Collections.Generic.List[string]]::new();$ruleChecks=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);$ruleIds=@()
if([string]$rules.benchmark_id-cne[string]$coverage.benchmark_id){$ruleReasons.Add('rules.json and requirement-coverage.json benchmark IDs differ.')}
foreach($dimension in @('D1','D2','D3','D4','D5')){
  $sum=0.0
  foreach($rule in @($rules.dimensions.$dimension.checks)){
    $id=[string]$rule.id;$ruleIds+=$id;$sum+=[double]$rule.weight
    if($ruleChecks.ContainsKey($id)){$ruleReasons.Add("rules.json duplicates check ID $id.")}
    if(@($rule.requirements).Count-eq0){$ruleReasons.Add("rules.json $id has no GDD or COMMON-BASELINE mapping.")}
    $duplicateRequirements=Get-Duplicates @($rule.requirements);if($duplicateRequirements.Count){$ruleReasons.Add("rules.json $id duplicates requirement IDs: $($duplicateRequirements-join', ').")}
    $ruleChecks[$id]=[pscustomobject]@{dimension=$dimension;weight=[double]$rule.weight;requirements=@($rule.requirements)}
  }
  if([math]::Abs($sum-[double]$rules.dimensions.$dimension.maximum_score)-gt.0001){$ruleReasons.Add("rules.json $dimension weights sum to $sum, expected $($rules.dimensions.$dimension.maximum_score).")}
}
$automaticMaximum=0.0;foreach($dimension in @('D1','D2','D3','D4','D5')){$automaticMaximum+=[double]$rules.dimensions.$dimension.maximum_score};if([math]::Abs($automaticMaximum-[double]$rules.automatic_score_maximum)-gt.0001-or[math]::Abs($automaticMaximum-90.0)-gt.0001){$ruleReasons.Add("D1-D5 maximum is $automaticMaximum, expected 90.")}
$ruleIdSet=Get-OrdinalSet $ruleIds
$phaseCheckIds=@();foreach($phase in @('static','dynamic','fresh')){$phaseCheckIds+=@($rules.phase_contract.$phase.expected_check_ids|ForEach-Object{[string]$_})};$phaseDuplicates=Get-Duplicates $phaseCheckIds;if($phaseDuplicates.Count){$ruleReasons.Add("phase_contract duplicates check IDs: $($phaseDuplicates-join', ').")};if(-not(Compare-Set $phaseCheckIds $ruleIds)){$ruleReasons.Add('phase_contract expected_check_ids must match the complete D1-D5 rules check set exactly.')}

$gddIds=@();$gddPath=''
try{
  if([string]::IsNullOrWhiteSpace([string]$coverage.gdd_source)){throw 'requirement-coverage.json has no gdd_source.'}
  $gddPath=[IO.Path]::GetFullPath((Join-Path $evaluationRoot ([string]$coverage.gdd_source)))
  if(-not(Test-Path -LiteralPath $gddPath -PathType Leaf)){throw "GDD source is missing: $gddPath"}
  $gddText=[IO.File]::ReadAllText($gddPath)
  # Do not bind acceptance parsing to a numbered Markdown section. GDD headings can
  # be renumbered without changing the public requirement IDs. A short scope table
  # may repeat the same IDs, so select the requirement-row shape with the greatest
  # column count (the detailed acceptance table in the current public GDD).
  $gddRowMatches=@([regex]::Matches($gddText,'(?m)^\|\s*(?<id>[A-Z][A-Z0-9]*-\d{2})\s*\|[^\r\n]*$'))
  if($gddRowMatches.Count-eq0){throw 'GDD contains no Markdown requirement rows with public requirement IDs.'}
  $gddRows=@($gddRowMatches|ForEach-Object{
    $line=[string]$_.Value
    [pscustomobject]@{id=[string]$_.Groups['id'].Value;column_count=@($line.Trim().Trim('|').Split('|')).Count}
  })
  $maxColumnCount=[int](($gddRows|Measure-Object -Property column_count -Maximum).Maximum)
  $gddIds=@($gddRows|Where-Object{[int]$_.column_count-eq$maxColumnCount}|ForEach-Object{[string]$_.id})
  if($gddIds.Count-eq0){throw 'GDD contains no usable public requirement table.'}
  $gddDuplicates=Get-Duplicates $gddIds;if($gddDuplicates.Count){$ruleReasons.Add("GDD requirement table duplicates requirement IDs: $($gddDuplicates-join', ').")}
}
catch{$ruleReasons.Add("GDD acceptance source is invalid: $($_.Exception.Message)")}

$baselineId=[string]$coverage.common_baseline.id
if($baselineId-cne'COMMON-BASELINE'){$ruleReasons.Add('requirement-coverage.json must declare the explicit COMMON-BASELINE mapping.')}
if([string]$rules.common_baseline.id-cne$baselineId){$ruleReasons.Add('rules.json and requirement-coverage.json COMMON-BASELINE IDs differ.')}
$coveredRequirementIds=@($coverage.requirements|ForEach-Object{[string]$_.id})
$coverageDuplicates=Get-Duplicates $coveredRequirementIds;if($coverageDuplicates.Count){$ruleReasons.Add("Coverage duplicates requirement IDs: $($coverageDuplicates-join', ').")}
if($gddIds.Count-and-not(Compare-Set $gddIds $coveredRequirementIds)){$ruleReasons.Add('GDD requirement table and requirement-coverage.json requirement IDs must match exactly.')}
$allRequirementIds=@($coveredRequirementIds)+@($baselineId);$coveredRequirementSet=Get-OrdinalSet $allRequirementIds;$gddSet=Get-OrdinalSet $gddIds
foreach($item in @($coverage.requirements)){
  if([string]::IsNullOrWhiteSpace([string]$item.id)){$ruleReasons.Add('Coverage contains an empty requirement ID.');continue}
  $duplicateChecks=Get-Duplicates @($item.checks);if($duplicateChecks.Count){$ruleReasons.Add("Coverage $($item.id) duplicates check IDs: $($duplicateChecks-join', ').")}
  foreach($id in @($item.checks)){if(-not$ruleIdSet.Contains([string]$id)){$ruleReasons.Add("Coverage $($item.id) references unknown check $id.")}}
  $expectedChecks=@($ruleIds|Where-Object{(Get-OrdinalSet @($ruleChecks[$_].requirements)).Contains([string]$item.id)});if(-not(Compare-Set @($item.checks) $expectedChecks)){$ruleReasons.Add("Coverage $($item.id) check list does not exactly match rules.json requirement mappings.")}
}
$baselineChecks=@($coverage.common_baseline.checks);$baselineDuplicates=Get-Duplicates $baselineChecks;if($baselineDuplicates.Count){$ruleReasons.Add("COMMON-BASELINE duplicates check IDs: $($baselineDuplicates-join', ').")};foreach($id in $baselineChecks){if(-not$ruleIdSet.Contains([string]$id)){$ruleReasons.Add("COMMON-BASELINE references unknown check $id.")}};$expectedBaselineChecks=@($ruleIds|Where-Object{(Get-OrdinalSet @($ruleChecks[$_].requirements)).Contains($baselineId)});if(-not(Compare-Set $baselineChecks $expectedBaselineChecks)){$ruleReasons.Add('COMMON-BASELINE check list does not exactly match rules.json mappings.')}
foreach($id in $ruleIds){
  $inGddCoverage=@($coverage.requirements|Where-Object{(Get-OrdinalSet @($_.checks)).Contains([string]$id)}).Count-gt0;$inBaseline=(Get-OrdinalSet $baselineChecks).Contains([string]$id);if(-not$inGddCoverage-and-not$inBaseline){$ruleReasons.Add("Scored check $id is absent from GDD coverage and COMMON-BASELINE.")}
  foreach($requirement in @($ruleChecks[$id].requirements)){if(-not$coveredRequirementSet.Contains([string]$requirement)){$ruleReasons.Add("Scored check $id references requirement $requirement absent from coverage.")};if($requirement-cne$baselineId-and$gddIds.Count-and-not$gddSet.Contains([string]$requirement)){$ruleReasons.Add("Scored check $id references requirement $requirement absent from the GDD requirement table and is not COMMON-BASELINE.")}}
}

if($CandidateCompileFailure){
  $checks=@();$dims=[ordered]@{}
  foreach($dimension in @('D1','D2','D3','D4','D5')){
    foreach($rule in @($rules.dimensions.$dimension.checks)){$checks+=[ordered]@{id=[string]$rule.id;dimension=$dimension;weight=[double]$rule.weight;passed=$false;expected='candidate must compile before this checkpoint can run';observed='blocked by candidate-owned C# compilation error';requirement_ids=(@($rule.requirements)-join',');trajectory='candidate_compile_failure'}}
    $max=[double]$rules.dimensions.$dimension.maximum_score;$dims[$dimension]=[ordered]@{title=$titles[$dimension];score=if($ruleReasons.Count-eq0){0.0}else{$null};maximum_score=$max;status=if($ruleReasons.Count-eq0){'evaluated'}else{'not_evaluated'}}
  }
  $valid=$ruleReasons.Count-eq0;$dims.D6=[ordered]@{title='Visual Assembly & Presentation Fidelity';score=$null;maximum_score=10.0;status='not_evaluated';rounds=@()};$receipt=Join-Path $OutputRoot 'candidate-compile-failure.json'
  $result=[ordered]@{schema_version=4;evaluator_protocol='game-independent-d1-d6-v2';evaluator_revision=[string]$rules.evaluator_revision;generated_utc=[DateTime]::UtcNow.ToString('o');project_path=$ProjectPath;valid_score=$valid;candidate_status=if($valid){'invalid_game'}else{'evaluator_invalid'};validation_reasons=@($ruleReasons);candidate_failure_reasons=if(Test-Path -LiteralPath $receipt){@(Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json).diagnostics}else{@('candidate compilation failed')};visual_validation_reasons=if($valid){@('D6 is unavailable because the candidate does not compile.')}else{@()};score=$null;score_status=if($valid){'pending_visual'}else{'evaluator_invalid'};automated_score=if($valid){0.0}else{$null};automated_maximum_score=90.0;maximum_score=100.0;dimensions=$dims;overall=[ordered]@{score=$null;maximum_score=100.0;status=if($valid){'pending_visual'}else{'evaluator_invalid'}};executable=if($valid){$false}else{$null};solved=if($valid){$false}else{$null};phases=[ordered]@{static=[ordered]@{exit_code=$StaticExit;status='candidate_compile_failure'};dynamic=[ordered]@{exit_code=$DynamicExit;status='blocked_by_candidate_compile'};fresh=[ordered]@{exit_code=$FreshExit;status='blocked_by_candidate_compile'}};checks=if($valid){$checks}else{@()}}
  $result|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $OutputRoot 'score.json') -Encoding utf8;if($valid){exit 0}else{exit 3}
}

$reasons=[System.Collections.Generic.List[string]]::new();foreach($reason in $ruleReasons){$reasons.Add($reason)}
$candidateFailureReasons=[System.Collections.Generic.List[string]]::new()
$phaseExit=@{static=$StaticExit;dynamic=$DynamicExit;fresh=$FreshExit};$phaseTimedOut=@{static=$StaticTimedOut;dynamic=$DynamicTimedOut;fresh=$FreshTimedOut};$allEvidence=@();$phaseInfo=[ordered]@{};$phaseDocuments=@{}
foreach($phase in @('static','dynamic','fresh')){
  $xmlPath=Join-Path $OutputRoot ($phase+'.xml');$evidencePath=Join-Path $OutputRoot ($phase+'-evidence.json');$contract=$rules.phase_contract.$phase
  $expectedTestNames=@($contract.expected_test_names|ForEach-Object{[string]$_});$expectedTrajectoryIds=@($contract.expected_trajectory_ids|ForEach-Object{[string]$_});$testToTrajectory=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);$trajectoryToTest=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
  if($expectedTestNames.Count-ne[int]$contract.expected_tests-or$expectedTrajectoryIds.Count-ne[int]$contract.expected_tests){$reasons.Add("$phase phase contract must declare exactly $($contract.expected_tests) NUnit test names and distinct trajectory IDs.")}
  $testDuplicates=Get-Duplicates $expectedTestNames;$trajectoryContractDuplicates=Get-Duplicates $expectedTrajectoryIds;if($testDuplicates.Count){$reasons.Add("$phase phase contract duplicates NUnit test names: $($testDuplicates-join', ').")};if($trajectoryContractDuplicates.Count){$reasons.Add("$phase phase contract duplicates trajectory IDs: $($trajectoryContractDuplicates-join', ').")}
  for($identityIndex=0;$identityIndex-lt[Math]::Min($expectedTestNames.Count,$expectedTrajectoryIds.Count);$identityIndex++){if(-not$testToTrajectory.ContainsKey($expectedTestNames[$identityIndex])){$testToTrajectory[$expectedTestNames[$identityIndex]]=$expectedTrajectoryIds[$identityIndex]};if(-not$trajectoryToTest.ContainsKey($expectedTrajectoryIds[$identityIndex])){$trajectoryToTest[$expectedTrajectoryIds[$identityIndex]]=$expectedTestNames[$identityIndex]}}
  if($phaseTimedOut[$phase]-or$phaseExit[$phase]-eq124){$reasons.Add("$phase evaluator process timed out.")}
  $xmlReadable=$false;$xmlIdentityValid=$false;$leafNames=@();$passedLeafNames=@();$failedLeafNames=@();$xml=$null;$run=$null
  if(Test-Path -LiteralPath $xmlPath){try{
    [xml]$xml=Get-Content -LiteralPath $xmlPath -Raw;$run=$xml.'test-run';$leaves=@($xml.SelectNodes('//test-case'));$leafNames=@($leaves|ForEach-Object{[string]$_.name});$passedLeafNames=@($leaves|Where-Object{[string]$_.result-ceq'Passed'}|ForEach-Object{[string]$_.name});$failedLeafNames=@($leaves|Where-Object{[string]$_.result-ceq'Failed'}|ForEach-Object{[string]$_.name});$unknownResults=@($leaves|Where-Object{[string]$_.result-cne'Passed'-and[string]$_.result-cne'Failed'}|ForEach-Object{[string]$_.name});$badFullNames=@($leaves|Where-Object{[string]::IsNullOrWhiteSpace([string]$_.fullname) -or -not ([string]$_.fullname).EndsWith('.'+[string]$_.name,[StringComparison]::Ordinal)}|ForEach-Object{[string]$_.name});$leafDuplicates=Get-Duplicates $leafNames
    $xmlReadable=$true;$xmlIdentityValid=($leaves.Count-eq[int]$contract.expected_tests-and[int]$run.total-eq[int]$contract.expected_tests-and[int]$run.passed-eq$passedLeafNames.Count-and[int]$run.failed-eq$failedLeafNames.Count-and[int]$run.skipped-eq0-and[int]$run.inconclusive-eq0-and$unknownResults.Count-eq0-and$badFullNames.Count-eq0-and$leafDuplicates.Count-eq0-and(Compare-Set $leafNames $expectedTestNames))
  }catch{$reasons.Add("$phase XML is unreadable: $($_.Exception.Message)")}}else{$reasons.Add("$phase XML is missing.")}
  if($xmlReadable-and-not$xmlIdentityValid){$reasons.Add("$phase XML/test identity must contain exactly $($contract.expected_tests) declared leaves: $($expectedTestNames-join', ').")}
  $failedTrajectoryIds=@($failedLeafNames|ForEach-Object{if($testToTrajectory.ContainsKey([string]$_)){$testToTrajectory[[string]$_]}})
  if($xmlReadable-and$xmlIdentityValid){foreach($leaf in $failedLeafNames){$mappedLeafTrajectory=if($testToTrajectory.ContainsKey([string]$leaf)){$testToTrajectory[[string]$leaf]}else{'unmapped'};$candidateFailureReasons.Add("$phase declared NUnit test $leaf (trajectory $mappedLeafTrajectory) returned Failed/Error and is treated as a candidate failure.")};if($phaseExit[$phase]-ne0-and$failedLeafNames.Count-eq0-and-not$phaseTimedOut[$phase]){$reasons.Add("$phase Unity CLI exited $($phaseExit[$phase]) although every declared leaf passed.")}}
  elseif($phaseExit[$phase]-ne0-and-not$phaseTimedOut[$phase]){$reasons.Add("$phase Unity CLI exited $($phaseExit[$phase]) without a complete declared trajectory identity.")}
  $checks=@();$document=$null
  if(Test-Path -LiteralPath $evidencePath){try{$document=Get-Content -LiteralPath $evidencePath -Raw|ConvertFrom-Json;$checks=@($document.checks);$phaseDocuments[$phase]=$document}catch{$reasons.Add("$phase evidence is unreadable: $($_.Exception.Message)")}}else{$reasons.Add("$phase evidence is missing.")}
  if($null-ne$document){
    if([int]$document.schema_version-lt2){$reasons.Add("$phase evidence schema must be >=2.")};if([string]$document.phase-cne$phase){$reasons.Add("$phase evidence phase mismatch.")};if([int]$document.process_id-le0){$reasons.Add("$phase evidence has no Unity process ID.")};$expectedInputRoute=Get-ExpectedInputRoute $phase;if([string]$document.input_route-cne$expectedInputRoute){$reasons.Add("$phase evidence input route differs from the evaluator-owned route.")}
    $trajectoryIds=@($document.trajectories|ForEach-Object{[string]$_.id});$trajectoryDuplicates=Get-Duplicates $trajectoryIds;if($trajectoryDuplicates.Count){$reasons.Add("$phase evidence duplicates trajectory IDs: $($trajectoryDuplicates-join', ').")};$expectedTrajectorySet=Get-OrdinalSet $expectedTrajectoryIds;$trajectorySet=Get-OrdinalSet $trajectoryIds;$unexpectedTrajectories=@($trajectoryIds|Where-Object{-not$expectedTrajectorySet.Contains([string]$_)});if($unexpectedTrajectories.Count){$reasons.Add("$phase evidence has unexpected trajectories: $($unexpectedTrajectories-join', ').")};$missingTrajectories=@($expectedTrajectoryIds|Where-Object{-not$trajectorySet.Contains([string]$_)});$unexplainedMissingTrajectories=@($missingTrajectories|Where-Object{$failedTrajectoryIds-notcontains[string]$_});if($unexplainedMissingTrajectories.Count){$reasons.Add("$phase evidence misses trajectories whose mapped NUnit tests did not fail: $($unexplainedMissingTrajectories-join', ').")}
    foreach($trajectory in @($document.trajectories)){$expectedTestName=if($trajectoryToTest.ContainsKey([string]$trajectory.id)){$trajectoryToTest[[string]$trajectory.id]}else{''};if([string]$trajectory.test_name-cne$expectedTestName){$reasons.Add("$phase trajectory $($trajectory.id) test_name mismatch: expected $expectedTestName.")};if([int]$trajectory.process_id-ne[int]$document.process_id){$reasons.Add("$phase trajectory $($trajectory.id) process ID differs from its evidence document.")};if([int]$trajectory.started_frame-lt0-or([int]$trajectory.completed_frame-gt0-and[int]$trajectory.completed_frame-lt[int]$trajectory.started_frame)){$reasons.Add("$phase trajectory $($trajectory.id) has invalid frame bounds.")};if([string]$trajectory.input_route-cne$expectedInputRoute){$reasons.Add("$phase trajectory $($trajectory.id) input route differs from the evaluator-owned route.")};if([string]::IsNullOrWhiteSpace([string]$trajectory.status)){$reasons.Add("$phase trajectory $($trajectory.id) has no status.")}}
    foreach($check in $checks){if([int]$check.process_id-ne[int]$document.process_id){$reasons.Add("$phase check $($check.id) process ID differs from its evidence document.")};if(-not$expectedTrajectorySet.Contains([string]$check.trajectory)){$reasons.Add("$phase check $($check.id) references an unknown trajectory.")};if($failedTrajectoryIds-contains[string]$check.trajectory){$check.passed=$false;$check.observed='blocked_by_candidate_failure | '+[string]$check.observed;if($null-eq$check.PSObject.Properties['status']){$check|Add-Member -NotePropertyName status -NotePropertyValue 'blocked_by_candidate_failure'}else{$check.status='blocked_by_candidate_failure'}}}
  }
  $expected=@($contract.expected_check_ids);$ids=@($checks|ForEach-Object id);$duplicates=Get-Duplicates $ids;if($duplicates.Count){$reasons.Add("$phase evidence has duplicate IDs: $($duplicates-join', ')")};$expectedSet=Get-OrdinalSet $expected;$idSet=Get-OrdinalSet $ids;$missing=@($expected|Where-Object{-not$idSet.Contains([string]$_)});$extra=@($ids|Where-Object{-not$expectedSet.Contains([string]$_)});if($extra.Count){$reasons.Add("$phase evidence has unexpected IDs: $($extra-join', ')")}
  foreach($id in $missing){
    if($xmlIdentityValid-and$failedLeafNames.Count-gt0-and$null-ne$document){
      $rule=$ruleChecks[[string]$id];$mappedTrajectory=@($failedTrajectoryIds|Select-Object -First 1);$trajectoryEvidence=@($document.trajectories|Where-Object{[string]$_.id-ceq[string]$mappedTrajectory[0]}|Select-Object -First 1);$syntheticFrame=if($trajectoryEvidence.Count){[Math]::Max([int]$trajectoryEvidence[0].started_frame,[int]$trajectoryEvidence[0].completed_frame)}else{0}
      $checks+=[pscustomobject][ordered]@{id=[string]$id;dimension=[string]$rule.dimension;weight=[double]$rule.weight;passed=$false;status='blocked_by_candidate_failure';expected='declared trajectory must reach and verify this checkpoint';observed='blocked_by_candidate_failure | candidate trajectory failed before writing this check';requirement_ids=(@($rule.requirements)-join',');trajectory=[string]$mappedTrajectory[0];process_id=[int]$document.process_id;frame=$syntheticFrame;utc=[DateTime]::UtcNow.ToString('o')}
      $candidateFailureReasons.Add("$phase missing scored check $id was bound to failed declared trajectory $($mappedTrajectory[0]) and scored false.")
    }
    else{$reasons.Add("$phase evidence missing IDs without a complete candidate-failure trajectory: $id")}
  }
  $allEvidence+=@($checks);$phaseInfo[$phase]=[ordered]@{exit_code=$phaseExit[$phase];timed_out=[bool]$phaseTimedOut[$phase];executor='unity-cli';xml=$xmlPath;evidence=$evidencePath;xml_valid=$xmlIdentityValid;test_count=$leafNames.Count;test_names=$leafNames;passed_tests=$passedLeafNames;failed_tests=$failedLeafNames;check_count=$checks.Count;process_id=if($null-ne$document){[int]$document.process_id}else{0}}
}

foreach($evidence in $allEvidence){
  if(-not$ruleChecks.ContainsKey([string]$evidence.id)){$reasons.Add("Evidence ID $($evidence.id) is absent from rules.json.");continue}
  $rule=$ruleChecks[[string]$evidence.id]
  if([string]$evidence.dimension-cne$rule.dimension){$reasons.Add("$($evidence.id) dimension mismatch.")}
  if([math]::Abs([double]$evidence.weight-[double]$rule.weight)-gt.0001){$reasons.Add("$($evidence.id) weight mismatch: evidence=$($evidence.weight), rules=$($rule.weight).")}
  $mapped=@(([string]$evidence.requirement_ids)-split','|Where-Object{$_});if(-not(Compare-Set $mapped @($rule.requirements))){$reasons.Add("$($evidence.id) public requirement mapping mismatch.")}
  if([int]$evidence.process_id-le0-or[int]$evidence.frame-lt0-or[string]::IsNullOrWhiteSpace([string]$evidence.trajectory)){$reasons.Add("$($evidence.id) lacks sealed trajectory/process/frame evidence.")}
}

if($phaseDocuments.ContainsKey('dynamic')-and$phaseDocuments.ContainsKey('fresh')){
  $dynamicDoc=$phaseDocuments.dynamic;$freshDoc=$phaseDocuments.fresh
  if([int]$dynamicDoc.process_id-eq[int]$freshDoc.process_id){$reasons.Add('Fresh lifecycle reused the dynamic Unity process ID.')}
}

$valid=$reasons.Count-eq0;$dimensions=[ordered]@{};$automated=0.0
foreach($dimension in @('D1','D2','D3','D4','D5')){$maximum=[double]$rules.dimensions.$dimension.maximum_score;if($valid){$score=0.0;foreach($rule in @($rules.dimensions.$dimension.checks)){$evidence=@($allEvidence|Where-Object{[string]$_.id-ceq[string]$rule.id});if($evidence.Count-eq1-and[bool]$evidence[0].passed){$score+=[double]$rule.weight}};$score=[math]::Round($score,2);$automated+=$score;$dimensions[$dimension]=[ordered]@{title=$titles[$dimension];score=$score;maximum_score=$maximum;status='evaluated'}}else{$dimensions[$dimension]=[ordered]@{title=$titles[$dimension];score=$null;maximum_score=$maximum;status='not_evaluated'}}}
$dimensions.D6=[ordered]@{title='Visual Assembly & Presentation Fidelity';score=$null;maximum_score=10.0;status='not_evaluated';rounds=@()}
$solved=$valid
foreach($dimension in @('D1','D2','D3','D4')){if(-not$valid-or[math]::Abs([double]$dimensions[$dimension].score-[double]$dimensions[$dimension].maximum_score)-gt.0001){$solved=$false}}
$result=[ordered]@{schema_version=4;evaluator_protocol='game-independent-d1-d6-v2';evaluator_revision=[string]$rules.evaluator_revision;generated_utc=[DateTime]::UtcNow.ToString('o');project_path=$ProjectPath;valid_score=$valid;candidate_status=if($valid){if($dimensions.D1.score-lt$dimensions.D1.maximum_score){'invalid_game'}elseif($solved){'solved'}else{'partial'}}else{'evaluator_invalid'};validation_reasons=@($reasons);candidate_failure_reasons=if($valid){@($candidateFailureReasons)}else{@()};visual_validation_reasons=if($valid){@('D6 requires the current fixed single-state single-round visual procedure.')}else{@()};score=$null;score_status=if($valid){'pending_visual'}else{'evaluator_invalid'};automated_score=if($valid){[math]::Round($automated,2)}else{$null};automated_maximum_score=90.0;maximum_score=100.0;dimensions=$dimensions;overall=[ordered]@{score=$null;maximum_score=100.0;status=if($valid){'pending_visual'}else{'evaluator_invalid'}};executable=if($valid){$dimensions.D1.score-eq$dimensions.D1.maximum_score}else{$null};solved=if($valid){[bool]$solved}else{$null};phases=$phaseInfo;checks=if($valid){$allEvidence}else{@()}}
$result|ConvertTo-Json -Depth 18|Set-Content -LiteralPath (Join-Path $OutputRoot 'score.json') -Encoding utf8
if($valid){exit 0}else{exit 3}


