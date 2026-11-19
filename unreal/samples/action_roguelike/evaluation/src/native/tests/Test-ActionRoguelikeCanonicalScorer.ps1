[CmdletBinding()]param()
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
function Assert([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
$source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$temp=Join-Path ([IO.Path]::GetTempPath()) ('actionroguelike-scorer-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'ActionRoguelikeD6TestFixture.ps1')
$originalHash=(Get-FileHash (Join-Path $source 'd6/d6-reference-manifest.json')).Hash
try {
    $fixture=New-TestD6Fixture $source $temp
    $d6=Invoke-TestD6 $fixture (Join-Path $temp 'd6');Assert ($d6.status-ceq'completed') 'D6 fixture did not complete.'
    $d6Path=Join-Path $temp 'd6/d6-run.json';$d6Backup=$d6|ConvertTo-Json -Depth 100
    $catalog=Get-Content -Raw (Join-Path $fixture.root 'catalog/checkpoints.json')|ConvertFrom-Json -Depth 100
    $run=[ordered]@{schema_version='4.0.0';game_id='ActionRoguelike';task_name='Rift Hunting';task_revision='2.2.0-diagnostic';run_id='unit';candidate_id='unit';candidate_identity_sha256=('a'*64);evaluator_revision='actionroguelike-evaluator-4.1.0';run_status='completed';checkpoints=@($catalog.checkpoints|ForEach-Object{[ordered]@{checkpoint_id=$_.id;dimension=$_.dimension;verdict='pass';detail='unit';reason_code=$null;attribution=$null;first_failure=$null;score_impact='full_credit';evidence=@()}});candidate_failures=@();faults=@();warnings=@();budget=[ordered]@{}}
    $verdictPath=Join-Path $temp 'verdicts.json';$scorePath=Join-Path $temp 'result.json';Write-TestD6Json $run $verdictPath
    $scorer=Join-Path $fixture.root 'scripts/Invoke-ActionRoguelikeCanonicalScorer.ps1'
    & $scorer -VerdictsPath $verdictPath -D6RunPath $d6Path -OutputPath $scorePath|Out-Null
    $text=Get-Content -Raw $scorePath;Assert ($text|Test-Json -SchemaFile (Join-Path $fixture.root 'schemas/evaluation-result.schema.json')) 'All-pass output schema failed.'
    $result=$text|ConvertFrom-Json;Assert ($result.functional_total-eq90-and$result.overall-eq100-and$result.diagnostic_only-and-not$result.formal_score_publishable) 'All-pass score or freeze boundary incorrect.'
    $run.mode='transport_health_only';Write-TestD6Json $run $verdictPath;$rejected=$false
    try{& $scorer -VerdictsPath $verdictPath -D6RunPath $d6Path -OutputPath (Join-Path $temp 'transport-score.json')|Out-Null}catch{$rejected=$_.Exception.Message-like'Transport health*'}
    Assert ($rejected-and-not(Test-Path -LiteralPath (Join-Path $temp 'transport-score.json'))) 'Transport-only health was published as a gameplay score.'
    $run.mode='canonical_independent_atomic_cases';Write-TestD6Json $run $verdictPath
    $run.checkpoints[5].verdict='fail';$run.checkpoints[5].reason_code='UNIT_FAILURE';$run.checkpoints[5].attribution='candidate';$run.checkpoints[5].first_failure='unit';$run.checkpoints[5].score_impact='checkpoint_zero';Write-TestD6Json $run $verdictPath
    & $scorer -VerdictsPath $verdictPath -D6RunPath $d6Path -OutputPath $scorePath|Out-Null
    $failed=Get-Content -Raw $scorePath|ConvertFrom-Json;Assert ($failed.dimensions.D2.score-lt30) 'Failed checkpoint did not reduce score.'
    $tests=@(
        @{name='protocol';change={param($x)$x.protocol='legacy_three_states_three_rounds'}},
        @{name='model';change={param($x)$x.model.version='tampered'}},
        @{name='config';change={param($x)$x.vlm_config_sha256=('f'*64)}},
        @{name='fault';change={param($x)$x.faults=@(@{code='VLM_FAILED'})}},
        @{name='string_component';change={param($x)$x.rounds[0].states[0].components[0]='2'}},
        @{name='boolean_component';change={param($x)$x.rounds[0].states[0].components[0]=$true}},
        @{name='aggregate';change={param($x)$x.score_raw=9}},
        @{name='fake_zero';change={param($x)$x.rounds[0].states[0].source='automatic_zero'}},
        @{name='response_hash';change={param($x)$x.rounds[0].states[0].response_sha256=('f'*64)}},
        @{name='bundle_hash';change={param($x)$x.evidence_bundle_sha256=('f'*64)}}
    )
    foreach($test in $tests){$bad=$d6Backup|ConvertFrom-Json -AsHashtable -Depth 100;& $test.change $bad;Write-TestD6Json $bad $d6Path;$rejected=$false;try{& $scorer -VerdictsPath $verdictPath -D6RunPath $d6Path -OutputPath (Join-Path $temp ($test.name+'.json'))|Out-Null}catch{$rejected=$true};Assert $rejected ('Scorer accepted '+$test.name)}
    Write-TestD6Json ($d6Backup|ConvertFrom-Json -AsHashtable -Depth 100) $d6Path
    $run.checkpoints[5].dimension='D1';Write-TestD6Json $run $verdictPath;$rejected=$false;try{& $scorer -VerdictsPath $verdictPath -D6RunPath $d6Path -OutputPath (Join-Path $temp 'reassigned.json')|Out-Null}catch{$rejected=$true};Assert $rejected 'Checkpoint dimension reassignment accepted.'
    $run.checkpoints[5].dimension='D2';$run.checkpoints[0].verdict=$null;Write-TestD6Json $run $verdictPath;$rejected=$false;try{& $scorer -VerdictsPath $verdictPath -D6RunPath $d6Path -OutputPath (Join-Path $temp 'null.json')|Out-Null}catch{$rejected=$true};Assert $rejected 'Null checkpoint accepted.'
    Assert ((Get-FileHash (Join-Path $source 'd6/d6-reference-manifest.json')).Hash-ceq$originalHash) 'Scorer test changed checked-in manifest.'
    Write-Output 'ACTIONROGUELIKE_SCORER_OK checkpoints=40 evidence_replay=true tamper_cases=13 transport_health_not_scorable=true original_manifest_unchanged=true'
}finally{if(Test-Path -LiteralPath $temp){Remove-TestD6Temp $temp}}
