[CmdletBinding()]param()
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$temp=Join-Path ([IO.Path]::GetTempPath()) ('actionroguelike-d6-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'ActionRoguelikeD6TestFixture.ps1')
$originalHash=(Get-FileHash (Join-Path $source 'd6/d6-reference-manifest.json')).Hash
try{
    $fixture=New-TestD6Fixture $source $temp
    . (Join-Path $fixture.root 'scripts/ActionRoguelikeD6Protocol.ps1')
    # Check exact authority text, not a translated/custom output contract.
    $guide=[IO.File]::ReadAllText((Join-Path $source '../../../gamecreate/GAME_INDEPENDENT_SCORING_GUIDE.md')).Replace("`r`n","`n")
    $section=$guide.Substring($guide.IndexOf('### 6.2'));$canonical=[regex]::Match($section,'(?s)```text\n(.*?)\n```').Groups[1].Value+"`n"
    Assert ([IO.File]::ReadAllText((Join-Path $source 'd6/FIXED_VLM_PROMPT.txt')).Replace("`r`n","`n")-ceq$canonical) 'Prompt differs from scoring guide.'
    $result=Invoke-TestD6 $fixture (Join-Path $temp 'all-pass');Assert ($result.status-ceq'completed'-and$result.score-eq10) ('Healthy protocol failed: '+($result.faults|ConvertTo-Json -Compress))
    Assert ((Get-Content -Raw (Join-Path $temp 'all-pass/d6-run.json'))|Test-Json -SchemaFile (Join-Path $fixture.root 'schemas/d6-run.schema.json')) 'D6 result schema failed.'
    # Premature round rounding gives 9.5; the exact average is 85/9 -> 9.4.
    $backup=$fixture.bundle|ConvertTo-Json -Depth 100
    for($r=0;$r-lt2;$r++){$fixture.bundle.rounds[$r].states[0].response.text=$fixture.bundle.rounds[$r].states[0].response.text.Replace('Scene completeness and asset assembly:2/2','Scene completeness and asset assembly:1/2').Replace('Total:10/10','Total:9/10')}
    $fixture.bundle.rounds[2].states[0].response.text=$fixture.bundle.rounds[2].states[0].response.text.Replace('Scene completeness and asset assembly:2/2','Scene completeness and asset assembly:0/2').Replace('Composition and layout:2/2','Composition and layout:1/2').Replace('Total:10/10','Total:7/10')
    $precision=Invoke-TestD6 $fixture (Join-Path $temp 'precision');Assert ($precision.status-ceq'completed'-and[Math]::Abs($precision.score_raw-(85.0/9))-lt1e-12-and$precision.score-eq9.4) 'Full precision average was lost.'
    $mutations=@(
        @{name='extra_line';change={param($b)$b.rounds[0].states[0].response.text+="`nextra"};code='D6_RESPONSE_LINE_COUNT'},
        @{name='wrong_total';change={param($b)$b.rounds[0].states[0].response.text=$b.rounds[0].states[0].response.text.Replace('Total:10/10','Total:9/10')};code='D6_RESPONSE_TOTAL_MISMATCH'},
        @{name='bad_component';change={param($b)$b.rounds[0].states[0].response.text=$b.rounds[0].states[0].response.text.Replace('Composition and layout:2/2','Composition and layout:true/2')};code='D6_RESPONSE_COMPONENT_INVALID'},
        @{name='model_drift';change={param($b)$b.rounds[1].states[0].request.model.version='drift'};code='D6_MODEL_CONFIGURATION_MISMATCH'},
        @{name='parameter_drift';change={param($b)$b.rounds[1].states[0].request.model.parameters.temperature=0.9};code='D6_MODEL_CONFIGURATION_MISMATCH'},
        @{name='prompt_drift';change={param($b)$b.rounds[1].states[0].request.prompt+='x'};code='D6_REQUEST_PROMPT_MISMATCH'},
        @{name='swapped_images';change={param($b)$b.rounds[0].states[0].request.images[0].role='candidate'};code='D6_REQUEST_IMAGES_INVALID'},
        @{name='wrong_round';change={param($b)$b.rounds[1].round=1};code='D6_ROUND_SET_INVALID'},
        @{name='capture_fault';change={param($b)$b.capture_health.status='failed'};code='D6_CAPTURE_INFRASTRUCTURE_FAULT'},
        @{name='response_model_drift';change={param($b)$b.rounds[1].states[0].response.model.version='drift'};code='D6_RESPONSE_IDENTITY_INVALID'},
        @{name='duplicate_request';change={param($b)$b.rounds[1].states[0].request.request_id=$b.rounds[0].states[0].request.request_id};code='D6_REQUEST_ID_INVALID'},
        @{name='nonhalf_score';change={param($b)$b.rounds[0].states[0].response.text=$b.rounds[0].states[0].response.text.Replace('Composition and layout:2/2','Composition and layout:0.25/2')};code='D6_RESPONSE_COMPONENT_INVALID'},
        @{name='missing_round';change={param($b)$b.rounds=@($b.rounds[0],$b.rounds[1])};code='D6_STATE_OR_ROUND_SET_INVALID'},
        @{name='receipt_hash';change={param($b)$b.capture_health.receipt_sha256=('f'*64)};code='D6_EVIDENCE_HASH_MISMATCH'},
        @{name='evidence_escape';change={param($b)$b.capture_health.receipt='../escape.json'};code='D6_EVIDENCE_PATH_ESCAPE'}
    )
    foreach($test in $mutations){$fixture.bundle=$backup|ConvertFrom-Json -AsHashtable -Depth 100;& $test.change $fixture.bundle;$bad=Invoke-TestD6 $fixture (Join-Path $temp $test.name);Assert ($bad.status-ceq'run_invalid'-and$bad.faults[0].code-ceq$test.code) ($test.name+': '+($bad.faults|ConvertTo-Json -Compress))}
    $fixture.bundle=$backup|ConvertFrom-Json -AsHashtable -Depth 100
    # Candidate missing and black frames, with healthy independent capture control.
    [IO.File]::Delete((Join-Path $fixture.captures 'active-arena.png'))
    $black=[Drawing.Bitmap]::new(1280,720);try{$black.Save((Join-Path $fixture.captures 'black-hole-combat.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$black.Dispose()}
    foreach($i in 0,1){$fixture.bundle.states[$i].status=@('missing','black_or_blank')[$i];$fixture.bundle.states[$i].attribution='candidate';$sr=$fixture.bundle.states[$i];Write-TestD6Json @{state_id=$sr.state_id;candidate_identity_sha256=('a'*64);status=$sr.status;attribution='candidate'} (Join-Path $fixture.evidence $sr.receipt);$sr.receipt_sha256=Get-D6Hash (Join-Path $fixture.evidence $sr.receipt);foreach($round in $fixture.bundle.rounds){$round.states[$i].request=$null;$round.states[$i].response=$null}}
    $zero=Invoke-TestD6 $fixture (Join-Path $temp 'zero');Assert ($zero.status-ceq'completed'-and$zero.score-eq3.3-and$zero.rounds[0].states[0].source-ceq'automatic_zero') ('Attributed zero failed: '+($zero.faults|ConvertTo-Json -Compress))
    # All states unreachable still produces three numeric-zero rounds when
    # independent capture health and per-state candidate attribution are bound.
    [IO.File]::Delete((Join-Path $fixture.captures 'terminal-result.png'))
    $sr=$fixture.bundle.states[2];$sr.status='missing';$sr.attribution='candidate'
    Write-TestD6Json @{state_id=$sr.state_id;candidate_identity_sha256=('a'*64);status=$sr.status;attribution='candidate'} (Join-Path $fixture.evidence $sr.receipt);$sr.receipt_sha256=Get-D6Hash (Join-Path $fixture.evidence $sr.receipt)
    foreach($round in $fixture.bundle.rounds){$round.states[2].request=$null;$round.states[2].response=$null}
    $allZero=Invoke-TestD6 $fixture (Join-Path $temp 'all-zero');Assert ($allZero.status-ceq'completed'-and$allZero.score-eq0-and@($allZero.rounds).Count-eq3) 'All unreachable frames were not numeric zero.'
    $duplicatePath=Join-Path $temp 'duplicate.json';[IO.File]::WriteAllText($duplicatePath,'{"x":1,"x":2}')
    $duplicateRejected=$false;try{$null=Read-D6Json $duplicatePath}catch{$duplicateRejected=$_.Exception.Message-ceq'D6_JSON_DUPLICATE_KEY'};Assert $duplicateRejected 'Duplicate JSON keys were accepted.'
    $fixture.manifest.reference_status='blocked_pending_original_derived_capture';Write-TestD6Json $fixture.manifest (Join-Path $fixture.root 'd6/d6-reference-manifest.json')
    $blocked=Invoke-TestD6 $fixture (Join-Path $temp 'blocked');Assert ($blocked.status-ceq'run_invalid'-and$blocked.faults[0].code-ceq'D6_REFERENCE_PROVENANCE_INVALID') 'Unready references were scored.'
    Assert ((Get-FileHash (Join-Path $source 'd6/d6-reference-manifest.json')).Hash-ceq$originalHash) 'Test modified checked-in manifest.'
    Write-Output 'ACTIONROGUELIKE_D6_OK exact_prompt=true per_pair_parser=true negative_cases=16 original_manifest_unchanged=true'
}finally{if(Test-Path -LiteralPath $temp){Remove-TestD6Temp $temp}}
